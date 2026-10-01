import '../models/models.dart';
import 'audio_metrics.dart';
import 'session_config.dart';

/// Cổng chất lượng trên máy, chạy ngay sau khi thu xong, trước khi upload
/// (WP2 mục 6).
///
/// Nguyên tắc: **gắn cờ, không loại bỏ**. Ngưỡng chưa chốt nên đặt rộng và chỉ
/// ghi số liệu, không chặn người dùng. Trường hợp duy nhất bị từ chối là phiên
/// gần như im lặng toàn bộ — khi đó không có gì để đo, và phiên không tính
/// vào lịch.
///
/// Không bao giờ cho thu đè lên phiên vừa thu: chỉ đề nghị thu thêm một phiên
/// mới. Thu đè tạo ra chọn lọc theo cảm nhận của người dùng về giọng mình —
/// loại thiên lệch không sửa được về sau.
class QualityGate {
  QualityGate._();

  static GateResult evaluate({
    required SessionMetrics metrics,
    required SessionConfig config,
    required bool unprocessedSource,
    required bool stoppedEarly,
  }) {
    final speechSec = metrics.speechSec;
    if (speechSec < config.rejectSpeechSec) {
      return GateResult(
        rejected: true,
        speechSec: speechSec,
        belowThreshold: true,
        flags: const [],
      );
    }

    final flags = <String>{};
    for (final part in const ['B', 'C']) {
      final m = metrics.parts[part];
      if (m == null || m.durationTotalSec == 0) continue;
      if (m.snrDb < config.minSnrDb) flags.add(QualityFlag.lowSnr);
      if (m.clippingRatio > config.maxClippingRatio) {
        flags.add(QualityFlag.clipping);
      }
    }
    final below = speechSec < config.minSpeechSec;
    if (below) flags.add(QualityFlag.belowMeasurementThreshold);
    if (!unprocessedSource) flags.add(QualityFlag.osProcessingPossible);
    if (stoppedEarly) flags.add(QualityFlag.stoppedEarly);

    return GateResult(
      rejected: false,
      speechSec: speechSec,
      belowThreshold: below,
      flags: flags.toList()..sort(),
    );
  }
}

class GateResult {
  /// Phiên gần như im lặng toàn bộ: không lưu, không tính vào lịch.
  final bool rejected;
  final double speechSec;
  final bool belowThreshold;
  final List<String> flags;

  const GateResult({
    required this.rejected,
    required this.speechSec,
    required this.belowThreshold,
    required this.flags,
  });
}
