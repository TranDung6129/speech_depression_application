import 'audio_metrics.dart';
import 'device_context.dart';
import '../models/models.dart';

/// Dựng metadata mục 5.1 cho ba file của một phiên.
///
/// Thiếu bất kỳ trường nào thì phiên không hợp lệ cho phân tích, nên mọi
/// trường đều được điền, kể cả khi giá trị là "không biết" (`unknown`).
/// Hàm thuần, không gọi nền tảng, để test được.
List<Map<String, dynamic>> buildSessionMetadata({
  required String sessionId,
  required String userId,
  required Map<TaskPart, DateTime> startedAt,
  required String timezone,
  required String textId,
  required String promptId,
  required DeviceInfo device,
  required String deviceId,
  required MicSource mic,
  required RecordingContext context,
  required SessionMetrics metrics,
  required bool belowThreshold,
  required List<String> qualityFlags,
}) {
  return [
    for (final part in TaskPart.values)
      {
        'session_id': sessionId,
        'user_id': userId,
        'timestamp_utc': startedAt[part]!.toUtc().toIso8601String(),
        'timezone': timezone,
        'task_part': part.code,
        'prompt_id': part == TaskPart.c ? promptId : null,
        'text_id': part == TaskPart.b ? textId : null,
        'device_model': device.model,
        'device_id': deviceId,
        'os_version': device.osVersion,
        'app_version': device.appVersion,
        'mic_source': mic.name,
        'unprocessed_source': mic.unprocessed,
        'recording_context': context.name,
        ...metrics.parts[part.code]!.toJson(),
        'below_measurement_threshold': belowThreshold,
        'quality_flags': qualityFlags,
      },
  ];
}
