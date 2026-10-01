import 'package:flutter/material.dart';

/// ---------------------------------------------------------------------------
/// Daily journal
/// ---------------------------------------------------------------------------

class JournalEntry {
  final String id;
  final DateTime recordedAt;
  final String audioPath;
  final Duration duration;

  /// User-defined mood tag (self-report only).
  /// This is not a model score; patients never see a score.
  final MoodTag? selfTag;

  /// Whether this entry has been uploaded to the backend.
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

/// User-defined mood tags.
class MoodTag {
  final String id;
  final String label;
  final IconData icon;

  const MoodTag._(this.id, this.label, this.icon);

  static const calm = MoodTag._('calm', 'Calm', Icons.spa_outlined);
  static const glad = MoodTag._('glad', 'Good', Icons.wb_sunny_outlined);
  static const tired = MoodTag._('tired', 'Tired', Icons.battery_2_bar_outlined);
  static const heavy = MoodTag._('heavy', 'Heavy', Icons.cloud_outlined);
  static const restless =
      MoodTag._('restless', 'Restless', Icons.waves_outlined);

  static const all = <MoodTag>[calm, glad, tired, heavy, restless];

  static MoodTag? byId(String? id) {
    if (id == null) return null;
    for (final t in all) {
      if (t.id == id) return t;
    }
    return null;
  }
}

/// Prompt shown each day to spark reflection.
class DailyPrompt {
  static const _prompts = <String>[
    'Is there anything small today that made you pause for a moment?',
    'Where did you go today, and who did you spend time with?',
    'If you were to tell today to a friend, where would you begin?',
    'Did you finish anything today that made you feel lighter?',
    'How did your morning begin today?',
    'Is there any sound or image from today that still stays with you?',
    'Did time ever feel like it moved quickly today?',
  ];

  static String forDate(DateTime date) {
    final dayIndex = date.difference(DateTime(2020, 1, 1)).inDays;
    return _prompts[dayIndex % _prompts.length];
  }
}

/// ---------------------------------------------------------------------------
/// Deep assessment
/// ---------------------------------------------------------------------------

/// Open-ended questions, each framed in a different memory context.
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
      text: 'What stands out most from the past week?',
      hint: 'No need for a perfect answer — just be honest',
    ),
    AssessmentQuestion(
      index: 1,
      text: 'How have your sleep and rest been lately?',
      hint: 'Tell it in your own words',
    ),
    AssessmentQuestion(
      index: 2,
      text: 'What has recently given you even a small sense of motivation?',
      hint: 'There is no right or wrong answer',
    ),
    AssessmentQuestion(
      index: 3,
      text: 'What are you looking forward to or worrying about next?',
      hint: 'You can say as much or as little as you want',
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
          'The recording is a bit short. Please say a little more.',
        AudioCheckResult.tooQuiet =>
          'The audio is a bit quiet. Please move closer to the microphone.',
        AudioCheckResult.noSignal =>
          'The microphone did not pick up any sound. Please check it and try again.',
      };
}
