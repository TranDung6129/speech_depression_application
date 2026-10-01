import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_journal/services/audio_metrics.dart';

void main() {
  group('AudioMetrics', () {
    test('percentile matches numpy linear interpolation', () {
      expect(AudioMetrics.percentile([1, 2, 3, 4], 50), 2.5);
      expect(AudioMetrics.percentile([1, 2, 3, 4], 90), closeTo(3.7, 1e-12));
      expect(AudioMetrics.percentile([5], 90), 5);
    });

    test('digital silence sits on the -100 dB floor', () {
      final frames = AudioMetrics.frameDb(Int16List(16000), 16000);
      expect(frames.length, 50);
      expect(frames.every((db) => db == AudioMetrics.dbFloor), isTrue);
    });

    test('empty WAV parses to zero samples', () {
      final wav = AudioMetrics.readWav(AudioMetrics.emptyWav());
      expect(wav.sampleRate, 16000);
      expect(wav.samples, isEmpty);
      final m = AudioMetrics.measure(wav.samples, wav.sampleRate, -60);
      expect(m.durationTotalSec, 0);
      expect(m.speechSec, 0);
    });

    // Hợp đồng app ↔ server: số liệu mong đợi sinh bằng backend
    // `app/quality.py` trên đúng hai file này. Lệch là cờ `quality_mismatch`
    // sẽ bật vô cớ trên mọi phiên thật.
    test('matches server quality.py on the contract fixtures', () {
      final expected = jsonDecode(
              File('test/fixtures/contract_expected.json').readAsStringSync())
          as Map<String, dynamic>;
      final metrics = AudioMetrics.measureSessionFiles({
        'A': 'test/fixtures/contract_a.wav',
        'B': 'test/fixtures/contract_b.wav',
      });
      for (final part in ['A', 'B']) {
        final got = metrics.parts[part]!.toJson();
        final want = expected[part] as Map<String, dynamic>;
        for (final key in want.keys) {
          expect(got[key], closeTo((want[key] as num).toDouble(), 1e-6),
              reason: '$part.$key');
        }
      }
    });
  });
}
