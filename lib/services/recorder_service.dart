import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';

/// Thu âm theo chuẩn dữ liệu chung của dự án: **16 kHz, mono, WAV**.
/// Giữ đúng chuẩn này ở client là điều kiện để tái dùng thẳng pipeline
/// trích đặc trưng đã viết cho WP1 mà không phải resample lại.
class RecorderService {
  RecorderService._();
  static final RecorderService instance = RecorderService._();

  final AudioRecorder _recorder = AudioRecorder();
  final _uuid = const Uuid();

  /// Ngưỡng thời lượng tối thiểu. Dưới mức này thì các thống kê về
  /// khoảng lặng và nhịp nói gần như không còn ý nghĩa.
  static const Duration minDuration = Duration(seconds: 5);

  /// Biên độ trung bình (dBFS) dưới ngưỡng này coi như quá nhỏ.
  static const double minMeanDb = -45;

  /// Dưới ngưỡng này coi như micro không thu được gì.
  static const double silenceDb = -58;

  final List<double> _amplitudeLog = [];
  StreamSubscription<Amplitude>? _ampSub;
  DateTime? _startedAt;

  bool get isRecording => _startedAt != null;

  /// Biên độ realtime, đã chuẩn hoá về 0..1 để vẽ waveform.
  final _levelController = StreamController<double>.broadcast();
  Stream<double> get levelStream => _levelController.stream;

  Future<bool> ensurePermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  /// Bắt đầu ghi. Trả về đường dẫn file sẽ được ghi vào.
  Future<String> start({String prefix = 'journal'}) async {
    if (!await ensurePermission()) {
      throw const RecorderPermissionDenied();
    }

    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/recordings');
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }

    final path = '${folder.path}/${prefix}_${_uuid.v4()}.wav';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
        // Tắt các xử lý của hệ điều hành: chúng thay đổi biên độ và
        // khoảng lặng, tức là làm méo chính những đặc trưng ta cần đo.
        echoCancel: false,
        noiseSuppress: false,
        autoGain: false,
      ),
      path: path,
    );

    _amplitudeLog.clear();
    _startedAt = DateTime.now();

    _ampSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 100))
        .listen((amp) {
      _amplitudeLog.add(amp.current);
      // amp.current tính bằng dBFS, thường nằm trong khoảng -60..0.
      final normalized = ((amp.current + 60) / 60).clamp(0.0, 1.0);
      _levelController.add(normalized);
    });

    return path;
  }

  /// Dừng ghi và trả về kết quả kèm đánh giá chất lượng kỹ thuật.
  Future<RecordingResult> stop() async {
    final path = await _recorder.stop();
    await _ampSub?.cancel();
    _ampSub = null;

    final duration = _startedAt == null
        ? Duration.zero
        : DateTime.now().difference(_startedAt!);
    _startedAt = null;

    if (path == null) {
      return RecordingResult(
        path: '',
        duration: duration,
        check: AudioCheckResult.noSignal,
      );
    }

    return RecordingResult(
      path: path,
      duration: duration,
      check: _evaluate(duration),
    );
  }

  Future<void> cancel() async {
    final path = await _recorder.stop();
    await _ampSub?.cancel();
    _ampSub = null;
    _startedAt = null;
    if (path != null) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  }

  /// Kiểm tra tự động, chạy ngầm. Người dùng không phải tự nghe lại và
  /// tự đánh giá — tránh việc họ ghi lại chỉ vì không thích giọng mình.
  AudioCheckResult _evaluate(Duration duration) {
    if (_amplitudeLog.isEmpty) return AudioCheckResult.noSignal;

    final mean =
        _amplitudeLog.reduce((a, b) => a + b) / _amplitudeLog.length;

    if (mean < silenceDb) return AudioCheckResult.noSignal;
    if (duration < minDuration) return AudioCheckResult.tooShort;
    if (mean < minMeanDb) return AudioCheckResult.tooQuiet;
    return AudioCheckResult.ok;
  }

  Future<void> dispose() async {
    await _ampSub?.cancel();
    await _recorder.dispose();
    await _levelController.close();
  }
}

class RecordingResult {
  final String path;
  final Duration duration;
  final AudioCheckResult check;

  const RecordingResult({
    required this.path,
    required this.duration,
    required this.check,
  });

  bool get isUsable => check == AudioCheckResult.ok;
}

class RecorderPermissionDenied implements Exception {
  const RecorderPermissionDenied();
  @override
  String toString() => 'Chưa được cấp quyền truy cập micro.';
}
