import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_journal/models/models.dart';
import 'package:voice_journal/services/audio_metrics.dart';
import 'package:voice_journal/services/device_context.dart';
import 'package:voice_journal/services/quality_gate.dart';
import 'package:voice_journal/services/session_config.dart';
import 'package:voice_journal/services/session_metadata.dart';

PartMetrics part({double speech = 30, double snr = 30, double clip = 0}) =>
    PartMetrics(
      durationTotalSec: speech + 5,
      speechSec: speech,
      speechRatio: speech / (speech + 5),
      noiseFloorDb: -60,
      speechDb: -60 + snr,
      peakDb: -3,
      snrDb: snr,
      clippingRatio: clip,
    );

SessionMetrics session({double b = 30, double c = 30, double snr = 30, double clip = 0}) =>
    SessionMetrics({
      'A': part(speech: 0, snr: 0),
      'B': part(speech: b, snr: snr, clip: clip),
      'C': part(speech: c, snr: snr, clip: clip),
    });

final config = SessionConfig.fromJson({
  'min_speech_sec': 45,
  'part_a_sec': 5,
  'part_b_target_speech_sec': 25,
  'part_c_min_speech_sec': 25,
  'text_id': 'vi-b-test',
  'text': 'Văn bản thử.',
  'prompts': [
    {'prompt_id': 'c01', 'text': 'Một'},
    {'prompt_id': 'c02', 'text': 'Hai'},
  ],
  'quality': {
    'min_snr_db': 10,
    'max_clipping_ratio': 0.01,
    'reject_speech_sec': 3,
  },
});

void main() {
  group('QualityGate', () {
    test('clean session has no flags', () {
      final r = QualityGate.evaluate(
          metrics: session(),
          config: config,
          unprocessedSource: true,
          stoppedEarly: false);
      expect(r.rejected, isFalse);
      expect(r.flags, isEmpty);
      expect(r.speechSec, 60);
    });

    test('threshold comes from config, not from the app', () {
      final r = QualityGate.evaluate(
          metrics: session(b: 20, c: 20),
          config: config,
          unprocessedSource: true,
          stoppedEarly: false);
      expect(r.rejected, isFalse, reason: 'flag, do not drop');
      expect(r.flags, contains(QualityFlag.belowMeasurementThreshold));
    });

    test('noisy, clipped, OS-processed and early-stopped sessions are flagged',
        () {
      final r = QualityGate.evaluate(
          metrics: session(snr: 5, clip: 0.05),
          config: config,
          unprocessedSource: false,
          stoppedEarly: true);
      expect(r.rejected, isFalse);
      expect(
          r.flags,
          containsAll([
            QualityFlag.lowSnr,
            QualityFlag.clipping,
            QualityFlag.osProcessingPossible,
            QualityFlag.stoppedEarly,
          ]));
    });

    test('near-silent session is rejected', () {
      final r = QualityGate.evaluate(
          metrics: session(b: 1, c: 1),
          config: config,
          unprocessedSource: true,
          stoppedEarly: false);
      expect(r.rejected, isTrue);
    });
  });

  test('prompt rotates through the fixed list by day', () {
    final d1 = config.promptFor(DateTime(2026, 10, 1));
    final d2 = config.promptFor(DateTime(2026, 10, 2));
    final d3 = config.promptFor(DateTime(2026, 10, 3));
    expect(d1.id, isNot(d2.id));
    expect(d1.id, d3.id);
  });

  test('metadata carries every section 5.1 field for all three parts', () {
    final start = DateTime(2026, 10, 1, 9);
    final meta = buildSessionMetadata(
      sessionId: 's1',
      userId: 'u1',
      startedAt: {for (final p in TaskPart.values) p: start},
      timezone: '+07:00',
      textId: 'vi-b-test',
      promptId: 'c01',
      device: const DeviceInfo(
          model: 'Pixel 7', osVersion: 'Android 14', appVersion: '0.2.0+2'),
      deviceId: 'dev-1',
      mic: const MicSource(name: 'unprocessed', unprocessed: true),
      context: RecordingContext.home,
      metrics: session(),
      belowThreshold: false,
      qualityFlags: const [],
    );
    const required = [
      'session_id', 'user_id', 'timestamp_utc', 'timezone', 'task_part',
      'device_model', 'device_id', 'os_version', 'app_version', 'mic_source',
      'unprocessed_source', 'recording_context', 'duration_total_sec',
      'speech_sec', 'speech_ratio', 'noise_floor_db', 'speech_db', 'peak_db',
      'snr_db', 'clipping_ratio', 'below_measurement_threshold',
      'quality_flags',
    ];
    expect(meta.map((m) => m['task_part']), ['A', 'B', 'C']);
    for (final m in meta) {
      for (final key in required) {
        expect(m[key], isNotNull, reason: '${m['task_part']}.$key');
      }
      // gain_applied_db là trường server thêm, app không bao giờ gửi.
      expect(m.containsKey('gain_applied_db'), isFalse);
    }
    expect(meta[1]['text_id'], 'vi-b-test');
    expect(meta[2]['prompt_id'], 'c01');
    expect(() => jsonEncode(meta), returnsNormally);
  });

  // Như test_patient_never_sees_score ở backend: dữ liệu phía bệnh nhân không
  // có trường điểm, nhãn hay mức rủi ro (mục 11).
  test('patient_never_sees_score: local session model has no score field', () {
    final s = LocalSession(
      id: 's1',
      recordedAt: DateTime(2026, 10, 1),
      speechSec: 50,
      minSpeechSec: 45,
      qualityFlags: const [],
    ).toJson();
    const forbidden = {'score', 'raw_score', 'risk', 'risk_level', 'level'};
    expect(s.keys.toSet().intersection(forbidden), isEmpty);
  });
}
