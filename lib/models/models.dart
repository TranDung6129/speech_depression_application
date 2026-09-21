import 'package:flutter/material.dart';

/// ---------------------------------------------------------------------------
/// Nhật ký hằng ngày
/// ---------------------------------------------------------------------------

class JournalEntry {
  final String id;
  final DateTime recordedAt;
  final String audioPath;
  final Duration duration;

  /// Nhãn cảm xúc do CHÍNH người dùng tự gắn (self-report).
  /// Đây không phải điểm số của mô hình — bệnh nhân không bao giờ thấy điểm.
  final MoodTag? selfTag;

  /// Đã gửi lên backend chưa (khe cắm model WP2 ↔ WP3).
  final bool uploaded;

  const JournalEntry({
    required this.id,
    required this.recordedAt,
    required this.audioPath,
    required this.duration,
    this.selfTag,
    this.uploaded = false,
  });

  JournalEntry copyWith({MoodTag? selfTag, bool? uploaded}) => JournalEntry(
        id: id,
        recordedAt: recordedAt,
        audioPath: audioPath,
        duration: duration,
        selfTag: selfTag ?? this.selfTag,
        uploaded: uploaded ?? this.uploaded,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        // Lưu timestamp đầy đủ, KHÔNG làm tròn theo ngày/tuần.
        // Khoảng cách thực tế giữa các lần ghi là dữ liệu cần cho phân tích
        // độ ổn định theo thời gian (test–retest) về sau.
        'recorded_at': recordedAt.toIso8601String(),
        'audio_path': audioPath,
        'duration_ms': duration.inMilliseconds,
        'self_tag': selfTag?.id,
        'uploaded': uploaded,
      };

  factory JournalEntry.fromJson(Map<String, dynamic> json) => JournalEntry(
        id: json['id'] as String,
        recordedAt: DateTime.parse(json['recorded_at'] as String),
        audioPath: json['audio_path'] as String,
        duration: Duration(milliseconds: json['duration_ms'] as int),
        selfTag: MoodTag.byId(json['self_tag'] as String?),
        uploaded: json['uploaded'] as bool? ?? false,
      );
}

/// Nhãn cảm xúc tự khai. Danh sách cố định (không nhập tự do) để dễ mã hoá
/// thành biến phân loại khi đối chiếu với đầu ra của mô hình.
class MoodTag {
  final String id;
  final String label;
  final IconData icon;

  const MoodTag._(this.id, this.label, this.icon);

  static const calm = MoodTag._('calm', 'Bình thản', Icons.spa_outlined);
  static const glad = MoodTag._('glad', 'Dễ chịu', Icons.wb_sunny_outlined);
  static const tired = MoodTag._('tired', 'Mệt', Icons.battery_2_bar_outlined);
  static const heavy = MoodTag._('heavy', 'Nặng nề', Icons.cloud_outlined);
  static const restless =
      MoodTag._('restless', 'Bồn chồn', Icons.waves_outlined);

  static const all = <MoodTag>[calm, glad, tired, heavy, restless];

  static MoodTag? byId(String? id) {
    if (id == null) return null;
    for (final t in all) {
      if (t.id == id) return t;
    }
    return null;
  }
}

/// Câu gợi ý đổi mỗi ngày — phần "nổi bật" của màn nhật ký.
/// Câu hỏi cố ý để mở và trung tính: không hỏi trực tiếp về triệu chứng,
/// tránh dẫn dắt câu trả lời và tránh cảm giác đang bị khám bệnh.
class DailyPrompt {
  static const _prompts = <String>[
    'Có điều gì nhỏ hôm nay khiến bạn dừng lại một chút?',
    'Hôm nay bạn đã đi qua những đâu, gặp những ai?',
    'Nếu kể lại hôm nay cho một người bạn, bạn sẽ bắt đầu từ đâu?',
    'Có việc gì hôm nay bạn làm xong và thấy nhẹ người không?',
    'Buổi sáng hôm nay của bạn bắt đầu như thế nào?',
    'Có âm thanh hay hình ảnh nào hôm nay còn đọng lại trong bạn?',
    'Hôm nay có lúc nào bạn thấy thời gian trôi nhanh không?',
  ];

  /// Chọn theo ngày để mọi lần mở app trong cùng một ngày đều thấy cùng câu.
  static String forDate(DateTime date) {
    final dayIndex = date.difference(DateTime(2020, 1, 1)).inDays;
    return _prompts[dayIndex % _prompts.length];
  }
}

/// ---------------------------------------------------------------------------
/// Đánh giá chuyên sâu
/// ---------------------------------------------------------------------------

/// Bộ câu hỏi mở, mỗi câu nhắm vào một ngữ cảnh gợi nhớ khác nhau.
/// Đây KHÔNG phải thang đo lâm sàng (PHQ-9/SDS) — nội dung thang đo chuẩn
/// phải do người có chuyên môn duyệt và có ràng buộc bản quyền riêng.
class AssessmentQuestion {
  final int index;
  final String text;
  final String hint;

  const AssessmentQuestion({
    required this.index,
    required this.text,
    required this.hint,
  });

  static const List<AssessmentQuestion> all = [
    AssessmentQuestion(
      index: 0,
      text: 'Tuần vừa rồi có điều gì khiến bạn nhớ nhất?',
      hint: 'Không cần trả lời hay — chỉ cần thật',
    ),
    AssessmentQuestion(
      index: 1,
      text: 'Những ngày qua bạn ngủ và nghỉ ngơi thế nào?',
      hint: 'Cứ kể theo cách bạn nhớ',
    ),
    AssessmentQuestion(
      index: 2,
      text: 'Điều gì gần đây làm bạn thấy có động lực, dù rất nhỏ?',
      hint: 'Không có câu trả lời đúng hay sai',
    ),
    AssessmentQuestion(
      index: 3,
      text: 'Sắp tới có việc gì bạn đang mong hoặc đang lo?',
      hint: 'Nói bao nhiêu cũng được',
    ),
  ];

  static int get total => all.length;
}

class AssessmentAnswer {
  final int questionIndex;
  final String audioPath;
  final Duration duration;
  final DateTime answeredAt;

  const AssessmentAnswer({
    required this.questionIndex,
    required this.audioPath,
    required this.duration,
    required this.answeredAt,
  });

  Map<String, dynamic> toJson() => {
        'question_index': questionIndex,
        'audio_path': audioPath,
        'duration_ms': duration.inMilliseconds,
        'answered_at': answeredAt.toIso8601String(),
      };

  factory AssessmentAnswer.fromJson(Map<String, dynamic> json) =>
      AssessmentAnswer(
        questionIndex: json['question_index'] as int,
        audioPath: json['audio_path'] as String,
        duration: Duration(milliseconds: json['duration_ms'] as int),
        answeredAt: DateTime.parse(json['answered_at'] as String),
      );
}

enum SessionStatus { draft, completed, abandoned }

class AssessmentSession {
  final String id;
  final DateTime startedAt;
  final DateTime lastTouchedAt;
  final List<AssessmentAnswer> answers;
  final SessionStatus status;

  const AssessmentSession({
    required this.id,
    required this.startedAt,
    required this.lastTouchedAt,
    required this.answers,
    required this.status,
  });

  int get answeredCount => answers.length;
  bool get isComplete => answeredCount >= AssessmentQuestion.total;

  /// Câu tiếp theo cần trả lời; null nếu đã xong hết.
  int? get nextQuestionIndex {
    final answered = answers.map((a) => a.questionIndex).toSet();
    for (var i = 0; i < AssessmentQuestion.total; i++) {
      if (!answered.contains(i)) return i;
    }
    return null;
  }

  AssessmentSession copyWith({
    List<AssessmentAnswer>? answers,
    SessionStatus? status,
    DateTime? lastTouchedAt,
  }) =>
      AssessmentSession(
        id: id,
        startedAt: startedAt,
        lastTouchedAt: lastTouchedAt ?? DateTime.now(),
        answers: answers ?? this.answers,
        status: status ?? this.status,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'started_at': startedAt.toIso8601String(),
        'last_touched_at': lastTouchedAt.toIso8601String(),
        'status': status.name,
        'answers': answers.map((a) => a.toJson()).toList(),
      };

  factory AssessmentSession.fromJson(Map<String, dynamic> json) =>
      AssessmentSession(
        id: json['id'] as String,
        startedAt: DateTime.parse(json['started_at'] as String),
        lastTouchedAt: DateTime.parse(json['last_touched_at'] as String),
        status: SessionStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => SessionStatus.draft,
        ),
        answers: (json['answers'] as List<dynamic>)
            .map((e) => AssessmentAnswer.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// ---------------------------------------------------------------------------
/// Kết quả kiểm tra kỹ thuật sau khi ghi âm
/// ---------------------------------------------------------------------------

/// Chỉ kiểm tra LỖI KỸ THUẬT (mất tiếng, quá ngắn, quá ồn).
/// Cố ý KHÔNG cho người dùng nghe lại rồi ghi lại vì "không ưng nội dung":
/// ghi lại nhiều lần sẽ làm mất tính tự nhiên của mẫu giọng (bớt ngập ngừng,
/// bớt khoảng lặng) và tạo nhiễu cho các đặc trưng thời gian/ngữ điệu.
enum AudioCheckResult { ok, tooShort, tooQuiet, noSignal }

extension AudioCheckMessage on AudioCheckResult {
  String get message => switch (this) {
        AudioCheckResult.ok => '',
        AudioCheckResult.tooShort =>
          'Bản ghi hơi ngắn. Bạn thử nói thêm một chút nhé.',
        AudioCheckResult.tooQuiet =>
          'Âm thanh khá nhỏ. Bạn thử lại gần micro hơn nhé.',
        AudioCheckResult.noSignal =>
          'Micro chưa thu được tiếng. Bạn kiểm tra lại giúp mình nhé.',
      };
}
