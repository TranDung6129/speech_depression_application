import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Nhắc phiên hằng ngày bằng thông báo (WP2 mục 3: mặc định một phiên mỗi
/// ngày, cùng khung giờ, nhắc bằng thông báo).
///
/// Thông báo lặp mỗi ngày đúng giờ đã chọn. Thu xong phiên của hôm nay thì
/// lịch được đặt lại bắt đầu từ ngày mai, để không nhắc người đã thu rồi.
/// Dùng chế độ không chính xác (`inexactAllowWhileIdle`): lệch vài phút là
/// chấp nhận được, và không phải xin quyền báo thức chính xác.
///
/// Nội dung thông báo chỉ nói về việc thu, không có từ ngữ chẩn đoán.
class ReminderService {
  ReminderService._();
  static final ReminderService instance = ReminderService._();

  static const _id = 1;
  static const _kEnabled = 'reminder_enabled';
  static const _channelId = 'daily_session';

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> init() async {
    if (_ready || kIsWeb) return;
    try {
      tzdata.initializeTimeZones();
      final local = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(local.identifier));
    } catch (_) {
      // Không đọc được múi giờ máy: giữ UTC mặc định của gói timezone.
    }
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/launcher_icon'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      _ready = true;
    } catch (e) {
      debugPrint('Không khởi tạo được thông báo: $e');
    }
  }

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kEnabled) ?? true;
  }

  Future<void> setEnabled(bool enabled, {required int hour, required int minute}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, enabled);
    if (enabled) {
      await schedule(hour: hour, minute: minute, askPermission: true);
    } else {
      await cancel();
    }
  }

  /// Lần nhắc kế tiếp: hôm nay nếu chưa tới giờ (và chưa thu), không thì
  /// ngày mai. Hàm thuần để test được.
  static DateTime nextReminder(
    DateTime now, {
    required int hour,
    required int minute,
    bool doneToday = false,
  }) {
    final today = DateTime(now.year, now.month, now.day, hour, minute);
    if (!doneToday && today.isAfter(now)) return today;
    return DateTime(now.year, now.month, now.day + 1, hour, minute);
  }

  Future<void> schedule({
    required int hour,
    required int minute,
    bool doneToday = false,
    bool askPermission = false,
  }) async {
    await init();
    if (!_ready || !await isEnabled()) return;

    if (askPermission) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, sound: true);
    }

    final now = tz.TZDateTime.now(tz.local);
    final next = nextReminder(now, hour: hour, minute: minute, doneToday: doneToday);
    try {
      await _plugin.cancel(id: _id);
      await _plugin.zonedSchedule(
        id: _id,
        title: "Today's voice session",
        body: 'Three short steps, about two minutes.',
        scheduledDate: tz.TZDateTime(
            tz.local, next.year, next.month, next.day, next.hour, next.minute),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            'Daily session reminder',
            channelDescription: 'A daily reminder to record your voice session',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e) {
      debugPrint('Không đặt được lịch nhắc: $e');
    }
  }

  Future<void> cancel() async {
    await init();
    if (!_ready) return;
    try {
      await _plugin.cancel(id: _id);
    } catch (_) {}
  }
}
