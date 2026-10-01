import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

/// Cấu hình phiên do server giữ, đọc qua `GET /v1/config` (WP2 mục 2.2, 10.3).
///
/// Ngưỡng tiếng nói (`min_speech_sec`) còn chờ PI quyết, nên **không được viết
/// cứng trong app**: đổi ngưỡng ở server là đủ, không phải phát hành bản app
/// mới. App đọc lại lúc bắt đầu mỗi phiên; mất mạng thì dùng bản đã lưu lần
/// gần nhất. Chưa từng tải được lần nào thì không cho bắt đầu phiên.
class SessionConfig {
  final double minSpeechSec;
  final double partASec;
  final double partBTargetSpeechSec;
  final double partCMinSpeechSec;
  final String textId;
  final String text;
  final List<SessionPrompt> prompts;
  final double minSnrDb;
  final double maxClippingRatio;
  final double rejectSpeechSec;
  final DateTime fetchedAt;

  const SessionConfig({
    required this.minSpeechSec,
    required this.partASec,
    required this.partBTargetSpeechSec,
    required this.partCMinSpeechSec,
    required this.textId,
    required this.text,
    required this.prompts,
    required this.minSnrDb,
    required this.maxClippingRatio,
    required this.rejectSpeechSec,
    required this.fetchedAt,
  });

  /// Lời nhắc phần C xoay vòng theo danh sách cố định, mỗi ngày một lời.
  SessionPrompt promptFor(DateTime day) {
    final index = DateTime.utc(day.year, day.month, day.day)
        .difference(DateTime.utc(2020, 1, 1))
        .inDays;
    return prompts[index % prompts.length];
  }

  factory SessionConfig.fromJson(Map<String, dynamic> j, {DateTime? fetchedAt}) {
    final quality = j['quality'] as Map<String, dynamic>;
    final prompts = (j['prompts'] as List<dynamic>)
        .map((p) => SessionPrompt(
              id: (p as Map<String, dynamic>)['prompt_id'] as String,
              text: p['text'] as String,
            ))
        .toList();
    if (prompts.isEmpty) throw const FormatException('Cấu hình thiếu lời nhắc');
    return SessionConfig(
      minSpeechSec: (j['min_speech_sec'] as num).toDouble(),
      partASec: (j['part_a_sec'] as num).toDouble(),
      partBTargetSpeechSec: (j['part_b_target_speech_sec'] as num).toDouble(),
      partCMinSpeechSec: (j['part_c_min_speech_sec'] as num).toDouble(),
      textId: j['text_id'] as String,
      text: j['text'] as String,
      prompts: prompts,
      minSnrDb: (quality['min_snr_db'] as num).toDouble(),
      maxClippingRatio: (quality['max_clipping_ratio'] as num).toDouble(),
      rejectSpeechSec: (quality['reject_speech_sec'] as num).toDouble(),
      fetchedAt: fetchedAt ??
          DateTime.tryParse(j['_fetched_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class SessionPrompt {
  final String id;
  final String text;

  const SessionPrompt({required this.id, required this.text});
}

class SessionConfigService {
  SessionConfigService._();
  static final SessionConfigService instance = SessionConfigService._();

  static const _kCache = 'session_config_cache';

  /// Tải cấu hình mới; lỗi mạng thì trả bản đã lưu, không có thì null.
  Future<SessionConfig?> load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final response = await http
          .get(Uri.parse('${AppConfig.apiBaseUrl}/v1/config'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final config = SessionConfig.fromJson(body, fetchedAt: DateTime.now());
        body['_fetched_at'] = config.fetchedAt.toIso8601String();
        await prefs.setString(_kCache, jsonEncode(body));
        return config;
      }
    } catch (_) {
      // Rơi xuống bản đã lưu.
    }
    final cached = prefs.getString(_kCache);
    if (cached == null) return null;
    try {
      return SessionConfig.fromJson(jsonDecode(cached) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}
