/// ---------------------------------------------------------------------------
/// Phiên thu ba phần (WP2 mục 2)
/// ---------------------------------------------------------------------------
///
/// Một phiên = ba file cùng `session_id`, phân biệt bằng `task_part`:
///  A. im lặng 5 giây, đo nền nhiễu;
///  B. đọc một văn bản cố định (`text_id`), giống nhau cho mọi người, mọi phiên;
///  C. nói tự do theo một lời nhắc (`prompt_id`) xoay vòng theo danh sách.
///
/// Mặc định mỗi ngày một phiên. Đơn vị phân tích là quỹ đạo của một người
/// (`user_id + timestamp`), không phải một phiên đơn lẻ (mục 3).
library;

enum TaskPart { a, b, c }

extension TaskPartCode on TaskPart {
  /// Giá trị ghi vào `task_part`.
  String get code => switch (this) {
        TaskPart.a => 'A',
        TaskPart.b => 'B',
        TaskPart.c => 'C',
      };
}

/// Nơi thu, để tách phiên ở nhà với phiên tại phòng khám (mục 5.1).
enum RecordingContext { home, clinic, lab }

extension RecordingContextLabel on RecordingContext {
  String get label => switch (this) {
        RecordingContext.home => 'At home',
        RecordingContext.clinic => 'At the clinic',
        RecordingContext.lab => 'In the lab',
      };
}

/// Cờ chất lượng (mục 6). Cờ chỉ ghi nhận, không loại bỏ phiên.
class QualityFlag {
  QualityFlag._();

  static const lowSnr = 'low_snr';
  static const clipping = 'clipping';
  static const belowMeasurementThreshold = 'below_measurement_threshold';
  static const osProcessingPossible = 'os_processing_possible';

  /// Người dùng dừng trước khi phần C đủ (mục 2.4): vẫn lưu, kèm cờ.
  static const stoppedEarly = 'stopped_early';
}

/// Bản ghi cục bộ của một phiên đã lưu, cho màn hình chính và lịch sử.
///
/// Chỉ có số liệu về việc thu (khi nào, bao nhiêu giây tiếng nói, cờ chất
/// lượng). Không có điểm, nhãn hay mức rủi ro — bệnh nhân không bao giờ thấy
/// những thứ đó (mục 11).
class LocalSession {
  final String id;
  final DateTime recordedAt;
  final double speechSec;
  final double minSpeechSec;
  final List<String> qualityFlags;
  final bool uploaded;

  const LocalSession({
    required this.id,
    required this.recordedAt,
    required this.speechSec,
    required this.minSpeechSec,
    required this.qualityFlags,
    this.uploaded = false,
  });

  bool get belowThreshold =>
      qualityFlags.contains(QualityFlag.belowMeasurementThreshold);

  LocalSession copyWith({bool? uploaded}) => LocalSession(
        id: id,
        recordedAt: recordedAt,
        speechSec: speechSec,
        minSpeechSec: minSpeechSec,
        qualityFlags: qualityFlags,
        uploaded: uploaded ?? this.uploaded,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'recorded_at': recordedAt.toIso8601String(),
        'speech_sec': speechSec,
        'min_speech_sec': minSpeechSec,
        'quality_flags': qualityFlags,
        'uploaded': uploaded,
      };

  factory LocalSession.fromJson(Map<String, dynamic> json) => LocalSession(
        id: json['id'] as String,
        recordedAt: DateTime.parse(json['recorded_at'] as String),
        speechSec: (json['speech_sec'] as num).toDouble(),
        minSpeechSec: (json['min_speech_sec'] as num).toDouble(),
        qualityFlags: (json['quality_flags'] as List<dynamic>).cast<String>(),
        uploaded: json['uploaded'] as bool? ?? false,
      );
}

/// Hướng dẫn cải thiện cho từng cờ, hiển thị cho bệnh nhân sau phiên.
/// Chỉ nói về điều kiện thu, không bao giờ nói về giọng hay sức khoẻ.
String? guidanceFor(String flag) => switch (flag) {
      QualityFlag.lowSnr =>
        'There was quite a lot of background noise. Next time, try a quieter room.',
      QualityFlag.clipping =>
        'The sound was a little too loud for the microphone. Next time, hold the phone a bit further away.',
      QualityFlag.belowMeasurementThreshold =>
        'The recording was on the short side. Next time, try to keep talking a little longer.',
      QualityFlag.stoppedEarly =>
        'The session ended early. That is okay — it has still been saved.',
      _ => null,
    };
