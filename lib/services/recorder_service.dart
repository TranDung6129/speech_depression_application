import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'audio_metrics.dart';
import 'device_context.dart';

/// Thu âm theo chuẩn WP2 mục 4.1: **16 kHz, mono, PCM 16 bit WAV**.
///
/// App thu sạch, server xử lý (mục 1): không khử vang, không khử nhiễu, không
/// tự chỉnh gain, không lọc, không chuẩn mức. Các khối đó thay đổi đúng đại
/// lượng ta đang đo. Ngoài việc tắt DSP của plugin, nguồn micro được chọn sao
/// cho hệ điều hành cũng không chen vào (mục 4.2, xem [DeviceContext]).
///
/// Biên độ realtime chỉ dùng để vẽ sóng và **đếm** giây tiếng nói (VAD dùng để
/// đếm, không dùng để cắt — mục 2.4). Số đo chính thức tính lại trên file sau
/// khi thu, bằng [AudioMetrics].
class RecorderService {
  RecorderService._();
  static final RecorderService instance = RecorderService._();

  /// Chu kỳ lấy biên độ realtime.
  static const Duration levelInterval = Duration(milliseconds: 100);

  AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Amplitude>? _ampSub;
  DateTime? _startedAt;

  bool get isRecording => _startedAt != null;

  /// Biên độ realtime (dBFS) của bản đang thu.
  final _dbController = StreamController<double>.broadcast();
  Stream<double> get dbStream => _dbController.stream;

  Future<bool> ensurePermission() => _recorder.hasPermission();

  /// Bắt đầu ghi một phần của phiên vào [path].
  Future<void> start(String path, MicSource mic) async {
    if (!await ensurePermission()) {
      throw const RecorderPermissionDenied();
    }

    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }
    await _ampSub?.cancel();
    _ampSub = null;
    await _recorder.dispose();
    _recorder = AudioRecorder();

    await _recorder.start(
      RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
        echoCancel: false,
        noiseSuppress: false,
        autoGain: false,
        androidConfig: AndroidRecordConfig(
          audioSource: switch (mic.android) {
            AndroidMic.unprocessed => AndroidAudioSource.unprocessed,
            _ => AndroidAudioSource.voiceRecognition,
          },
        ),
        iosConfig: IosRecordConfig(
          // Không cho micro Bluetooth: đổi micro giữa chừng là đổi kênh thu.
          categoryOptions: const [IosAudioCategoryOption.defaultToSpeaker],
          // App đã tự đặt AVAudioSession ở mode `.measurement` thì plugin
          // không được ghi đè.
          // ignore: deprecated_member_use
          manageAudioSession: !mic.iosSessionManagedByApp,
        ),
      ),
      path: path,
    );

    _startedAt = DateTime.now();
    _ampSub = _recorder.onAmplitudeChanged(levelInterval).listen((amp) {
      _dbController.add(amp.current);
    });
  }

  /// Dừng ghi, trả về đường dẫn file và thời lượng thu.
  Future<(String?, Duration)> stop() async {
    final path = await _recorder.stop();
    await _ampSub?.cancel();
    _ampSub = null;
    final duration = _startedAt == null
        ? Duration.zero
        : DateTime.now().difference(_startedAt!);
    _startedAt = null;
    return (path, duration);
  }

  /// Dừng ghi và xoá file đang ghi dở.
  Future<void> cancel() async {
    final path = await _recorder.stop();
    await _ampSub?.cancel();
    _ampSub = null;
    _startedAt = null;
    if (path != null && !kIsWeb) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  }

  /// Thư mục chứa ba file của một phiên.
  static Future<Directory> sessionDirectory(String sessionId) async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/sessions/$sessionId');
    if (!await folder.exists()) await folder.create(recursive: true);
    return folder;
  }
}

/// Đếm giây tiếng nói realtime từ biên độ 100 ms, chỉ để hiển thị tiến độ.
///
/// Dùng cùng ngưỡng với phép đo trên file ([AudioMetrics.speechThresholdDb]),
/// nên con số hiển thị gần với con số cuối cùng; nhưng quyết định gắn cờ luôn
/// dựa trên số đo trên file, không dựa trên bộ đếm này.
class LiveSpeechCounter {
  LiveSpeechCounter(this.noiseFloorDb);

  final double noiseFloorDb;
  int _speechTicks = 0;
  final List<double> _levels = [];

  void add(double db) {
    _levels.add(db);
    if (db > AudioMetrics.speechThresholdDb(noiseFloorDb)) _speechTicks++;
  }

  double get speechSec =>
      _speechTicks * RecorderService.levelInterval.inMilliseconds / 1000;

  /// SNR ước lượng tạm: phân vị 90 của biên độ realtime trừ nền nhiễu.
  double? get liveSnrDb => _levels.length < 20
      ? null
      : AudioMetrics.percentile(_levels, 90) - noiseFloorDb;

  /// Nền nhiễu ước lượng từ phần A, theo biên độ realtime.
  static double floorFrom(List<double> levels) =>
      levels.isEmpty ? AudioMetrics.dbFloor : AudioMetrics.percentile(levels, 50);
}

class RecorderPermissionDenied implements Exception {
  const RecorderPermissionDenied();
  @override
  String toString() => 'Microphone permission was not granted.';
}
