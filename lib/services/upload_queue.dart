import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import 'auth_service.dart';
import 'storage_service.dart';

/// Hàng đợi tải bản ghi lên máy chủ.
///
/// Lý do phải có hàng đợi thay vì gọi thẳng API lúc ghi xong: người dùng
/// thường ghi nhật ký ở nơi sóng yếu, và mất bản ghi vì rớt mạng là mất luôn
/// dữ liệu không tái tạo được. Hàng đợi tồn tại qua lần khởi động app, tự thử
/// lại khi có mạng trở lại.
///
/// Nguyên tắc bất di bất dịch: **file âm thanh cục bộ chỉ bị xoá sau khi máy
/// chủ xác nhận đã nhận.** Thà tốn dung lượng máy còn hơn mất bản ghi.
class UploadQueue extends ChangeNotifier {
  UploadQueue._();
  static final UploadQueue instance = UploadQueue._();

  // Đổi khoá khi đổi định dạng job: job kiểu cũ (một file mỗi job, gửi tới
  // /v1/recordings) không đọc được bằng định dạng mới.
  static const _kQueue = 'upload_queue_v2';

  final List<UploadJob> _jobs = [];
  bool _isRunning = false;
  StreamSubscription<List<ConnectivityResult>>? _connSub;

  List<UploadJob> get jobs => List.unmodifiable(_jobs);
  int get pendingCount => _jobs.where((j) => !j.isExhausted).length;
  int get failedCount => _jobs.where((j) => j.isExhausted).length;

  /// Gọi một lần lúc khởi động app.
  Future<void> start() async {
    await _load();

    // Có mạng trở lại thì chạy lại hàng đợi ngay, không đợi người dùng
    // mở app lần sau.
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online) {
        unawaited(flush());
      }
    });

    unawaited(flush());
  }

  @override
  void dispose() {
    _connSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kQueue) ?? [];
    _jobs
      ..clear()
      ..addAll(
        raw.map((s) => UploadJob.fromJson(
              jsonDecode(s) as Map<String, dynamic>,
            )),
      );
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _kQueue,
      _jobs.map((j) => jsonEncode(j.toJson())).toList(),
    );
    notifyListeners();
  }

  Future<void> clearAll() async {
    _jobs.clear();
    await _save();
  }

  /// Đưa một bản ghi vào hàng đợi. Trả về ngay, việc tải chạy nền.
  Future<void> enqueue(UploadJob job) async {
    _jobs.add(job);
    await _save();
    unawaited(flush());
  }

  /// Thử tải hết những việc đang chờ.
  ///
  /// Chạy tuần tự chứ không song song: bản ghi âm thanh khá nặng, và tải
  /// song song trên mạng di động yếu thường làm cả nhóm cùng timeout.
  Future<void> flush() async {
    if (_isRunning) return;
    if (!AuthService.instance.isSignedIn) return;

    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.every((r) => r == ConnectivityResult.none)) return;

    _isRunning = true;
    try {
      for (final job in List<UploadJob>.from(_jobs)) {
        if (job.isExhausted) continue;
        if (!job.isDue) continue;

        final ok = await _attempt(job);
        if (ok) {
          _jobs.remove(job);
          await _save();
        } else {
          job.attempts += 1;
          job.nextAttemptAt = DateTime.now().add(job.backoff);
          await _save();
        }
      }
    } finally {
      _isRunning = false;
    }
  }

  Future<bool> _attempt(UploadJob job) async {
    final files = {
      for (final e in job.audioPaths.entries) e.key: File(e.value),
    };

    for (final file in files.values) {
      if (!await file.exists()) {
        // File đã biến mất (người dùng xoá, hệ điều hành dọn dẹp). Không có
        // gì để tải nữa — bỏ khỏi hàng đợi thay vì thử mãi.
        debugPrint('Bỏ qua job ${job.id}: không tìm thấy ${file.path}.');
        job.attempts = AppConfig.maxUploadAttempts;
        job.lastError = 'Recording file is missing';
        return false;
      }
    }

    try {
      final uri = Uri.parse('${AppConfig.apiBaseUrl}/v1/sessions');
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${AuthService.instance.token}'
        ..fields['session_id'] = job.id
        ..fields['metadata'] = job.metadataJson;

      for (final e in files.entries) {
        request.files.add(await http.MultipartFile.fromPath(
          'part_${e.key.toLowerCase()}',
          e.value.path,
        ));
      }

      final streamed = await request.send().timeout(
            const Duration(minutes: 3),
          );
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 201) {
        // Chỉ xoá bản cục bộ khi checksum từng phần khớp với máy chủ.
        final serverSha = _readServerSha256(response.body);
        for (final e in files.entries) {
          final local = await _sha256Hex(e.value);
          if (serverSha[e.key] != local) {
            job.lastError = 'Checksum mismatch; keeping files for retry';
            return false;
          }
        }
        await StorageService.instance.markUploaded(job.id);
        await _deleteLocal(files.values);
        return true;
      }

      if (response.statusCode == 401) {
        // Token hết hạn. Dừng cả hàng đợi thay vì đốt hết lượt thử lại
        // của mọi job vào một lỗi mà thử lại không giải quyết được.
        job.lastError = 'Signed out';
        await AuthService.instance.signOut();
        return false;
      }

      if (response.statusCode >= 400 && response.statusCode < 500) {
        // Lỗi phía client (sai định dạng, file quá lớn) — thử lại cũng cho
        // kết quả y hệt, nên dừng luôn. File vẫn giữ trên máy.
        job.attempts = AppConfig.maxUploadAttempts;
        job.lastError = 'Server rejected (${response.statusCode})';
        return false;
      }

      job.lastError = 'Server error (${response.statusCode})';
      return false;
    } catch (_) {
      job.lastError = 'Could not connect';
      return false;
    }
  }

  static Map<String, String> _readServerSha256(String body) {
    try {
      final parsed = jsonDecode(body);
      if (parsed is Map<String, dynamic> && parsed['files'] is List) {
        return {
          for (final f in parsed['files'] as List)
            if (f is Map && f['task_part'] is String && f['sha256'] is String)
              f['task_part'] as String: f['sha256'] as String,
        };
      }
    } catch (_) {
      // Phản hồi hỏng: coi như chưa xác nhận, giữ file để thử lại.
    }
    return const {};
  }

  static Future<String> _sha256Hex(File file) async {
    final bytes = await file.readAsBytes();
    return sha256.convert(bytes).toString();
  }

  static Future<void> _deleteLocal(Iterable<File> files) async {
    for (final file in files) {
      try {
        await file.delete();
        final dir = file.parent;
        if (await dir.exists() && await dir.list().isEmpty) {
          await dir.delete();
        }
      } catch (_) {
        // Không xoá được thì để lại; dữ liệu đã an toàn trên máy chủ.
      }
    }
  }

  /// Thử lại thủ công những việc đã hết lượt, dùng cho nút trong phần cài đặt.
  Future<void> retryFailed() async {
    for (final job in _jobs) {
      if (job.isExhausted) {
        job.attempts = 0;
        job.nextAttemptAt = null;
        job.lastError = null;
      }
    }
    await _save();
    await flush();
  }

  Future<void> clear() async {
    _jobs.clear();
    await _save();
  }
}

/// Một phiên chờ tải lên: ba file A, B, C và metadata mục 5.1.
class UploadJob {
  /// Chính là `session_id`. Gửi lại cùng id thì máy chủ trả lại phiên đã lưu,
  /// không tạo phiên mới và không ghi đè bản thô.
  final String id;

  /// `task_part` (A, B, C) → đường dẫn file WAV.
  final Map<String, String> audioPaths;

  /// Danh sách metadata ba phần, đã mã hoá JSON.
  final String metadataJson;

  final DateTime recordedAt;

  int attempts;
  DateTime? nextAttemptAt;
  String? lastError;

  UploadJob({
    required this.id,
    required this.audioPaths,
    required this.metadataJson,
    required this.recordedAt,
    this.attempts = 0,
    this.nextAttemptAt,
    this.lastError,
  });

  bool get isExhausted => attempts >= AppConfig.maxUploadAttempts;

  bool get isDue =>
      nextAttemptAt == null || DateTime.now().isAfter(nextAttemptAt!);

  /// Backoff luỹ thừa: 2s, 4s, 8s, 16s, 32s, 64s.
  Duration get backoff => AppConfig.retryBaseDelay * (1 << attempts);

  Map<String, dynamic> toJson() => {
        'id': id,
        'audio_paths': audioPaths,
        'metadata_json': metadataJson,
        'recorded_at': recordedAt.toIso8601String(),
        'attempts': attempts,
        'next_attempt_at': nextAttemptAt?.toIso8601String(),
        'last_error': lastError,
      };

  factory UploadJob.fromJson(Map<String, dynamic> json) => UploadJob(
        id: json['id'] as String,
        audioPaths: (json['audio_paths'] as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, v as String)),
        metadataJson: json['metadata_json'] as String,
        recordedAt: DateTime.parse(json['recorded_at'] as String),
        attempts: json['attempts'] as int? ?? 0,
        nextAttemptAt: json['next_attempt_at'] == null
            ? null
            : DateTime.parse(json['next_attempt_at'] as String),
        lastError: json['last_error'] as String?,
      );
}
