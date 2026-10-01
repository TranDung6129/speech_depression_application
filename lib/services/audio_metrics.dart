import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Chỉ số chất lượng thu âm, tính trên bản thô ngay sau khi thu (WP2 mục 5.1, 6).
///
/// Đây là phép **đo**, không phải xử lý: app không bao giờ sửa mẫu âm thanh.
/// Server tính lại đúng các chỉ số này trên bản thô (backend `app/quality.py`)
/// và gắn cờ `quality_mismatch` khi lệch, nên hai phía phải dùng CÙNG MỘT
/// định nghĩa:
///
/// - khung 20 ms không chồng lấn, RMS theo mẫu đã chia 32768;
/// - dBFS = 20·log10(RMS), sàn ở -100 dB;
/// - phân vị nội suy tuyến tính như `numpy.percentile` mặc định;
/// - `noise_floor_db` = trung vị dB khung của phần A;
/// - `speech_db` = phân vị 90 dB khung của chính file đó;
/// - `snr_db` = `speech_db` - `noise_floor_db`;
/// - khung là tiếng nói khi dB > max(noise_floor + 10, -55).
class AudioMetrics {
  AudioMetrics._();

  static const double frameSec = 0.02;
  static const double dbFloor = -100;
  static const double vadMarginDb = 10;
  static const double vadAbsMinDb = -55;
  static const int _clipLevel = 32767;

  /// Ngưỡng dB để coi một khung (hoặc một mẫu biên độ realtime) là tiếng nói.
  static double speechThresholdDb(double noiseFloorDb) =>
      math.max(noiseFloorDb + vadMarginDb, vadAbsMinDb);

  /// Phân vị nội suy tuyến tính, giống `numpy.percentile(..., method="linear")`.
  static double percentile(List<double> values, double p) {
    if (values.isEmpty) return dbFloor;
    final sorted = List<double>.from(values)..sort();
    final rank = p / 100 * (sorted.length - 1);
    final lo = rank.floor();
    final hi = rank.ceil();
    if (lo == hi) return sorted[lo];
    return sorted[lo] + (sorted[hi] - sorted[lo]) * (rank - lo);
  }

  static List<double> frameDb(Int16List samples, int sampleRate) {
    final size = (sampleRate * frameSec).round();
    final count = size == 0 ? 0 : samples.length ~/ size;
    final out = List<double>.filled(count, dbFloor);
    for (var f = 0; f < count; f++) {
      var sum = 0.0;
      final base = f * size;
      for (var i = 0; i < size; i++) {
        final x = samples[base + i] / 32768.0;
        sum += x * x;
      }
      final rms = math.sqrt(sum / size);
      if (rms > 0) {
        out[f] = math.max(20 * math.log(rms) / math.ln10, dbFloor);
      }
    }
    return out;
  }

  static double noiseFloorDb(List<double> frames) =>
      frames.isEmpty ? dbFloor : percentile(frames, 50);

  static PartMetrics measure(Int16List samples, int sampleRate, double floorDb) {
    final frames = frameDb(samples, sampleRate);
    final duration = sampleRate == 0 ? 0.0 : samples.length / sampleRate;
    final threshold = speechThresholdDb(floorDb);
    final voiced = frames.where((db) => db > threshold).length;
    final speechSec = voiced * frameSec;

    var peak = 0;
    var clipped = 0;
    for (final s in samples) {
      final a = s.abs();
      if (a > peak) peak = a;
      if (a >= _clipLevel) clipped++;
    }

    final speechDb = frames.isEmpty ? dbFloor : percentile(frames, 90);
    return PartMetrics(
      durationTotalSec: duration,
      speechSec: speechSec,
      speechRatio: duration == 0 ? 0 : speechSec / duration,
      noiseFloorDb: floorDb,
      speechDb: speechDb,
      peakDb: peak == 0
          ? dbFloor
          : math.max(20 * math.log(peak / 32768.0) / math.ln10, dbFloor),
      snrDb: speechDb - floorDb,
      clippingRatio: samples.isEmpty ? 0 : clipped / samples.length,
    );
  }

  /// Đo cả ba phần của một phiên. Chạy trong isolate (`compute`) vì phải
  /// duyệt hàng triệu mẫu.
  static SessionMetrics measureSessionFiles(Map<String, String> paths) {
    final a = readWav(File(paths['A']!).readAsBytesSync());
    final floor = noiseFloorDb(frameDb(a.samples, a.sampleRate));
    final out = <String, PartMetrics>{};
    for (final entry in paths.entries) {
      final wav = entry.key == 'A'
          ? a
          : readWav(File(entry.value).readAsBytesSync());
      out[entry.key] = measure(wav.samples, wav.sampleRate, floor);
    }
    return SessionMetrics(out);
  }

  /// Đọc WAV PCM 16 bit, lấy kênh đầu. Duyệt theo chunk vì header WAV do
  /// các nền tảng ghi ra có thể chèn thêm chunk `LIST`/`fact` trước `data`.
  static WavData readWav(Uint8List bytes) {
    final view = ByteData.sublistView(bytes);
    if (bytes.length < 12 ||
        String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
      throw const FormatException('Không phải file WAV');
    }
    var offset = 12;
    var sampleRate = 0;
    var channels = 1;
    var bits = 16;
    Int16List? samples;
    while (offset + 8 <= bytes.length) {
      final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      var size = view.getUint32(offset + 4, Endian.little);
      final body = offset + 8;
      if (id == 'fmt ') {
        channels = view.getUint16(body + 2, Endian.little);
        sampleRate = view.getUint32(body + 4, Endian.little);
        bits = view.getUint16(body + 14, Endian.little);
      } else if (id == 'data') {
        // Một số bộ ghi để kích thước 0 hoặc 0xFFFFFFFF khi chưa đóng file.
        if (size == 0 || body + size > bytes.length) size = bytes.length - body;
        if (bits != 16) throw FormatException('Cần PCM 16 bit, nhận $bits bit');
        final frameCount = size ~/ (2 * channels);
        samples = Int16List(frameCount);
        for (var i = 0; i < frameCount; i++) {
          samples[i] = view.getInt16(body + i * 2 * channels, Endian.little);
        }
        break;
      }
      offset = body + size + (size.isOdd ? 1 : 0);
    }
    if (samples == null) throw const FormatException('WAV thiếu chunk data');
    return WavData(sampleRate, channels, samples);
  }

  /// WAV rỗng (chỉ header) cho phần chưa kịp thu khi người dùng dừng sớm.
  /// Phiên vẫn đủ ba file để lưu, kèm cờ `stopped_early`.
  static Uint8List emptyWav({int sampleRate = 16000}) {
    final b = ByteData(44);
    void tag(int at, String s) {
      for (var i = 0; i < 4; i++) {
        b.setUint8(at + i, s.codeUnitAt(i));
      }
    }

    tag(0, 'RIFF');
    b.setUint32(4, 36, Endian.little);
    tag(8, 'WAVE');
    tag(12, 'fmt ');
    b.setUint32(16, 16, Endian.little);
    b.setUint16(20, 1, Endian.little);
    b.setUint16(22, 1, Endian.little);
    b.setUint32(24, sampleRate, Endian.little);
    b.setUint32(28, sampleRate * 2, Endian.little);
    b.setUint16(32, 2, Endian.little);
    b.setUint16(34, 16, Endian.little);
    tag(36, 'data');
    b.setUint32(40, 0, Endian.little);
    return b.buffer.asUint8List();
  }
}

class WavData {
  final int sampleRate;
  final int channels;
  final Int16List samples;

  const WavData(this.sampleRate, this.channels, this.samples);
}

class PartMetrics {
  final double durationTotalSec;
  final double speechSec;
  final double speechRatio;
  final double noiseFloorDb;
  final double speechDb;
  final double peakDb;
  final double snrDb;
  final double clippingRatio;

  const PartMetrics({
    required this.durationTotalSec,
    required this.speechSec,
    required this.speechRatio,
    required this.noiseFloorDb,
    required this.speechDb,
    required this.peakDb,
    required this.snrDb,
    required this.clippingRatio,
  });

  Map<String, dynamic> toJson() => {
        'duration_total_sec': durationTotalSec,
        'speech_sec': speechSec,
        'speech_ratio': speechRatio,
        'noise_floor_db': noiseFloorDb,
        'speech_db': speechDb,
        'peak_db': peakDb,
        'snr_db': snrDb,
        'clipping_ratio': clippingRatio,
      };
}

class SessionMetrics {
  final Map<String, PartMetrics> parts;

  const SessionMetrics(this.parts);

  /// Tiếng nói thật của cả phiên: B + C, không tính phần A (mục 2.2).
  double get speechSec =>
      (parts['B']?.speechSec ?? 0) + (parts['C']?.speechSec ?? 0);
}
