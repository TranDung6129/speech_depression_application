import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import 'auth_service.dart';

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

  static const _kQueue = 'upload_queue';

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
    final file = File(job.audioPath);

    if (!await file.exists()) {
      // File đã biến mất (người dùng xoá, hệ điều hành dọn cache).
      // Không có gì để tải nữa — bỏ khỏi hàng đợi thay vì thử mãi.
      debugPrint('Bỏ qua job ${job.id}: không tìm thấy file.');
      job.attempts = AppConfig.maxUploadAttempts;
      job.lastError = 'Không tìm thấy file âm thanh';
      return false;
    }

    try {
      final uri = Uri.parse('${AppConfig.apiBaseUrl}/v1/recordings');
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${AuthService.instance.token}'
        ..fields['recorded_at'] = job.recordedAt.toIso8601String()
        ..fields['kind'] = job.kind
        ..fields['sample_rate'] = '16000'
        ..fields['channels'] = '1';

      if (job.questionIndex != null) {
        request.fields['question_index'] = '${job.questionIndex}';
      }
      if (job.sessionId != null) {
        request.fields['session_id'] = job.sessionId!;
      }
      if (job.selfTag != null) {
        request.fields['self_tag'] = job.selfTag!;
      }

      request.files.add(
        await http.MultipartFile.fromPath('audio', job.audioPath),
      );

      final streamed = await request.send().timeout(
            const Duration(minutes: 2),
          );
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 201) {
        return true;
      }

      if (response.statusCode == 401) {
        // Token hết hạn. Dừng cả hàng đợi thay vì đốt hết lượt thử lại
        // của mọi job vào một lỗi mà thử lại không giải quyết được.
        job.lastError = 'Phiên đăng nhập hết hạn';
        await AuthService.instance.signOut();
        return false;
      }

      if (response.statusCode >= 400 && response.statusCode < 500) {
        // Lỗi phía client (sai sample rate, file quá lớn) — thử lại
        // cũng cho kết quả y hệt, nên dừng luôn.
        job.attempts = AppConfig.maxUploadAttempts;
        job.lastError = 'Máy chủ từ chối (${response.statusCode})';
        return false;
      }

      job.lastError = 'Lỗi máy chủ (${response.statusCode})';
      return false;
    } catch (_) {
      job.lastError = 'Không kết nối được';
      return false;
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

class UploadJob {
  final String id;
  final String audioPath;
  final DateTime recordedAt;
  final String kind; // 'journal' | 'assessment'
  final int? questionIndex;
  final String? sessionId;

  /// Nhãn cảm xúc tự khai, gửi kèm ngay trong lần tải lên.
  ///
  /// Gộp vào đây thay vì gọi PATCH riêng sau đó: id cục bộ và id máy chủ là
  /// hai thứ khác nhau, nên đồng bộ ngược sẽ cần lưu thêm bảng ánh xạ id —
  /// máy móc thừa cho một trường duy nhất.
  final String? selfTag;

  int attempts;
  DateTime? nextAttemptAt;
  String? lastError;

  UploadJob({
    required this.id,
    required this.audioPath,
    required this.recordedAt,
    required this.kind,
    this.questionIndex,
    this.sessionId,
    this.selfTag,
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
        'audio_path': audioPath,
        'recorded_at': recordedAt.toIso8601String(),
        'kind': kind,
        'question_index': questionIndex,
        'session_id': sessionId,
        'self_tag': selfTag,
        'attempts': attempts,
        'next_attempt_at': nextAttemptAt?.toIso8601String(),
        'last_error': lastError,
      };

  factory UploadJob.fromJson(Map<String, dynamic> json) => UploadJob(
        id: json['id'] as String,
        audioPath: json['audio_path'] as String,
        recordedAt: DateTime.parse(json['recorded_at'] as String),
        kind: json['kind'] as String,
        questionIndex: json['question_index'] as int?,
        sessionId: json['session_id'] as String?,
        selfTag: json['self_tag'] as String?,
        attempts: json['attempts'] as int? ?? 0,
        nextAttemptAt: json['next_attempt_at'] == null
            ? null
            : DateTime.parse(json['next_attempt_at'] as String),
        lastError: json['last_error'] as String?,
      );
}
