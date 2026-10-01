import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// Lưu trữ cục bộ: danh sách phiên đã thu và cài đặt nhắc.
///
/// Bản triển khai thật nên chuyển sang sqflite/Isar: số phiên tăng theo ngày.
class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  static const _kSessions = 'capture_sessions';
  static const _kReminderHour = 'reminder_hour';
  static const _kReminderMinute = 'reminder_minute';
  static const _kRecordingContext = 'recording_context';

  // Khoá của bản app trước (nhật ký + đánh giá bốn câu), chỉ còn để dọn.
  static const _legacyKeys = [
    'journal_entries',
    'assessment_draft',
    'assessment_sessions',
    'assessment_interval_days',
  ];

  SharedPreferences? _prefs;
  Future<SharedPreferences> get _p async =>
      _prefs ??= await SharedPreferences.getInstance();

  // ---- Phiên ----

  Future<List<LocalSession>> loadSessions() async {
    final prefs = await _p;
    final raw = prefs.getStringList(_kSessions) ?? [];
    final sessions = raw
        .map((s) => LocalSession.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
    sessions.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    return sessions;
  }

  Future<void> saveSession(LocalSession session) async {
    final prefs = await _p;
    final raw = prefs.getStringList(_kSessions) ?? [];
    raw.add(jsonEncode(session.toJson()));
    await prefs.setStringList(_kSessions, raw);
  }

  Future<void> markUploaded(String sessionId) async {
    final prefs = await _p;
    final sessions = await loadSessions();
    await prefs.setStringList(
      _kSessions,
      sessions
          .map((s) => s.id == sessionId ? s.copyWith(uploaded: true) : s)
          .map((s) => jsonEncode(s.toJson()))
          .toList(),
    );
  }

  /// Ngày nào đã có phiên — dùng vẽ lịch. Chỉ hai trạng thái đã thu / chưa
  /// thu, không tô màu theo bất kỳ số đo nào.
  Future<Set<DateTime>> recordedDays() async {
    final sessions = await loadSessions();
    return sessions
        .map((s) =>
            DateTime(s.recordedAt.year, s.recordedAt.month, s.recordedAt.day))
        .toSet();
  }

  // ---- Cài đặt ----

  /// Giờ nhắc hằng ngày. Lịch mặc định là một phiên mỗi ngày, cùng khung giờ
  /// (mục 3). Khoảng cách thực tế giữa các phiên đọc từ timestamp, không suy
  /// ra từ cài đặt này.
  Future<(int, int)> reminderTime() async {
    final prefs = await _p;
    return (
      prefs.getInt(_kReminderHour) ?? 20,
      prefs.getInt(_kReminderMinute) ?? 0,
    );
  }

  Future<void> setReminderTime(int hour, int minute) async {
    final prefs = await _p;
    await prefs.setInt(_kReminderHour, hour);
    await prefs.setInt(_kReminderMinute, minute);
  }

  Future<RecordingContext> recordingContext() async {
    final prefs = await _p;
    final name = prefs.getString(_kRecordingContext);
    return RecordingContext.values.firstWhere(
      (c) => c.name == name,
      orElse: () => RecordingContext.home,
    );
  }

  Future<void> setRecordingContext(RecordingContext context) async {
    final prefs = await _p;
    await prefs.setString(_kRecordingContext, context.name);
  }

  /// Xoá toàn bộ dữ liệu trên máy, kể cả file âm thanh chưa tải lên.
  Future<void> wipeAll() async {
    final prefs = await _p;
    await prefs.remove(_kSessions);
    for (final key in _legacyKeys) {
      await prefs.remove(key);
    }
    if (kIsWeb) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      for (final name in const ['sessions', 'recordings']) {
        final folder = Directory('${dir.path}/$name');
        if (await folder.exists()) await folder.delete(recursive: true);
      }
    } catch (_) {
      // Không có thư mục tài liệu (ví dụ trong test) thì không có gì để xoá.
    }
  }
}
