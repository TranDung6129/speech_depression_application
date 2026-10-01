import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../config.dart';

/// Thông tin thiết bị và nguồn micro cho metadata mục 5.1.
///
/// Nói chuyện với code native qua kênh `voice_journal/audio`
/// (android/app/src/main/kotlin/.../MainActivity.kt; iOS xem README). Nền tảng
/// chưa có code native thì rơi về giá trị an toàn và ghi
/// `unprocessed_source = false` — tức là thừa nhận hệ điều hành có thể đã xử
/// lý tín hiệu, chứ không khai man là thu sạch.
class DeviceContext {
  DeviceContext._();
  static final DeviceContext instance = DeviceContext._();

  static const _channel = MethodChannel('voice_journal/audio');
  static const _kDeviceId = 'device_id';

  String? _deviceId;
  DeviceInfo? _info;

  /// Mã ẩn danh sinh một lần khi cài app. Không phải IMEI hay mã phần cứng,
  /// chỉ có nghĩa trong hệ thống này. Cần vì `device_model` chỉ cho biết cùng
  /// loại máy, còn ước lượng kênh (mục 8.4) cần biết cùng một chiếc máy.
  ///
  /// Lưu ở shared_preferences chứ không ở secure storage: đăng xuất xoá sạch
  /// secure storage, nhưng máy thì vẫn là chiếc máy đó.
  Future<String> deviceId() async {
    if (_deviceId != null) return _deviceId!;
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_kDeviceId);
    if (id == null) {
      id = const Uuid().v4();
      await prefs.setString(_kDeviceId, id);
    }
    return _deviceId = id;
  }

  Future<DeviceInfo> info() async {
    if (_info != null) return _info!;
    var model = 'unknown';
    var os = kIsWeb ? 'web' : '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('deviceInfo');
      model = raw?['model'] as String? ?? model;
      os = raw?['os_version'] as String? ?? os;
    } on MissingPluginException {
      // Nền tảng chưa có code native.
    } on PlatformException {
      // Giữ giá trị mặc định.
    }
    return _info = DeviceInfo(
      model: model,
      osVersion: os,
      appVersion: AppConfig.appVersion,
    );
  }

  /// Chọn nguồn micro ít bị hệ điều hành xử lý nhất (mục 4.2).
  ///
  /// - Android: `UNPROCESSED` nếu máy báo hỗ trợ, không thì `VOICE_RECOGNITION`.
  /// - iOS: `AVAudioSession` ở mode `.measurement`.
  Future<MicSource> pickMicSource() async {
    if (kIsWeb) return const MicSource.fallback('web');
    try {
      if (Platform.isAndroid) {
        final ok = await _channel.invokeMethod<bool>('supportsUnprocessed') ?? false;
        return ok
            ? const MicSource(
                name: 'unprocessed',
                unprocessed: true,
                android: AndroidMic.unprocessed,
              )
            : const MicSource(
                name: 'voice_recognition',
                unprocessed: false,
                android: AndroidMic.voiceRecognition,
              );
      }
      if (Platform.isIOS) {
        final ok =
            await _channel.invokeMethod<bool>('configureMeasurementSession') ?? false;
        return ok
            ? const MicSource(
                name: 'ios_measurement',
                unprocessed: true,
                iosSessionManagedByApp: true,
              )
            : const MicSource.fallback('ios_default');
      }
    } on MissingPluginException {
      // Rơi xuống nguồn mặc định bên dưới.
    } on PlatformException {
      // Như trên.
    }
    return MicSource.fallback(
      Platform.isAndroid ? 'voice_recognition' : 'default',
      android: Platform.isAndroid ? AndroidMic.voiceRecognition : null,
    );
  }

  /// Độ lệch múi giờ của máy, dạng `+07:00`.
  static String timezone(DateTime local) {
    final offset = local.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final abs = offset.abs();
    final h = abs.inHours.toString().padLeft(2, '0');
    final m = abs.inMinutes.remainder(60).toString().padLeft(2, '0');
    return '$sign$h:$m';
  }
}

class DeviceInfo {
  final String model;
  final String osVersion;
  final String appVersion;

  const DeviceInfo({
    required this.model,
    required this.osVersion,
    required this.appVersion,
  });
}

enum AndroidMic { unprocessed, voiceRecognition }

class MicSource {
  /// Giá trị ghi vào `mic_source`.
  final String name;

  /// Giá trị ghi vào `unprocessed_source`.
  final bool unprocessed;

  final AndroidMic? android;

  /// iOS: app đã tự đặt `AVAudioSession` ở mode `.measurement`, plugin thu âm
  /// không được ghi đè cấu hình đó.
  final bool iosSessionManagedByApp;

  const MicSource({
    required this.name,
    required this.unprocessed,
    this.android,
    this.iosSessionManagedByApp = false,
  });

  const MicSource.fallback(this.name, {this.android})
      : unprocessed = false,
        iosSessionManagedByApp = false;
}
