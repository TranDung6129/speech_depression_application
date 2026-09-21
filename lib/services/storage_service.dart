import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// Lưu trữ cục bộ cho bản demo.
///
/// Bản triển khai thật nên chuyển sang sqflite/Isar: số bản ghi tăng theo
/// ngày, và ta cần truy vấn theo khoảng thời gian khi phân tích về sau.
class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  static const _kEntries = 'journal_entries';
  static const _kDraft = 'assessment_draft';
  static const _kSessions = 'assessment_sessions';
  static const _kReminderHour = 'reminder_hour';
  static const _kReminderMinute = 'reminder_minute';
  static const _kAssessmentIntervalDays = 'assessment_interval_days';

  SharedPreferences? _prefs;
  Future<SharedPreferences> get _p async =>
      _prefs ??= await SharedPreferences.getInstance();

  // ---- Nhật ký hằng ngày ----

  Future<List<JournalEntry>> loadEntries() async {
    final prefs = await _p;
    final raw = prefs.getStringList(_kEntries) ?? [];
    final entries = raw
        .map((s) => JournalEntry.fromJson(
            jsonDecode(s) as Map<String, dynamic>))
        .toList();
    entries.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    return entries;
  }

  Future<void> saveEntry(JournalEntry entry) async {
    final prefs = await _p;
    final raw = prefs.getStringList(_kEntries) ?? [];
    raw.add(jsonEncode(entry.toJson()));
    await prefs.setStringList(_kEntries, raw);
  }

  Future<void> updateEntry(JournalEntry entry) async {
    final prefs = await _p;
    final entries = await loadEntries();
    final updated = entries
        .map((e) => e.id == entry.id ? entry : e)
        .map((e) => jsonEncode(e.toJson()))
        .toList();
    await prefs.setStringList(_kEntries, updated);
  }

  /// Ngày nào đã có nhật ký — dùng vẽ lịch tháng.
  /// Lịch chỉ hiển thị **đã ghi / chưa ghi**, không tô màu theo cảm xúc:
  /// nhìn lại cả tháng toàn màu tối có thể khiến người dùng nản thêm.
  Future<Set<DateTime>> recordedDays() async {
    final entries = await loadEntries();
    return entries
        .map((e) => DateTime(
            e.recordedAt.year, e.recordedAt.month, e.recordedAt.day))
        .toSet();
  }

  // ---- Đánh giá chuyên sâu ----

  Future<AssessmentSession?> loadDraft() async {
    final prefs = await _p;
    final raw = prefs.getString(_kDraft);
    if (raw == null) return null;
    return AssessmentSession.fromJson(
        jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveDraft(AssessmentSession session) async {
    final prefs = await _p;
    await prefs.setString(_kDraft, jsonEncode(session.toJson()));
  }

  /// Khi người dùng chọn "Bắt đầu đánh giá mới" mà đang có draft dở:
  /// draft cũ KHÔNG bị xoá, chỉ chuyển sang trạng thái `abandoned` và
  /// chuyển vào kho phiên. Các câu đã trả lời vẫn là mẫu giọng hợp lệ.
  Future<void> archiveDraftAsAbandoned() async {
    final draft = await loadDraft();
    if (draft == null) return;
    await _appendSession(draft.copyWith(status: SessionStatus.abandoned));
    await clearDraft();
  }

  Future<void> completeDraft() async {
    final draft = await loadDraft();
    if (draft == null) return;
    await _appendSession(draft.copyWith(status: SessionStatus.completed));
    await clearDraft();
  }

  Future<void> clearDraft() async {
    final prefs = await _p;
    await prefs.remove(_kDraft);
  }

  FPhụ cấp ăn + phụ cấp trách nhiệm, đóng BHXH
uture<void> _appendSession(AssessmentSession session) async {
    final prefs = await _p;
    final raw = prefs.getStringList(_kSessions) ?? [];
    raw.add(jsonEncode(session.toJson()));
    await prefs.setStringList(_kSessions, raw);
  }

  Future<List<AssessmentSession>> loadSessions() async {
    final prefs = await _p;
    final raw = prefs.getStringList(_kSessions) ?? [];
    final sessions = raw
        .map((s) => AssessmentSession.fromJson(
            jsonDecode(s) as Map<String, dynamic>))
        .toList();
    sessions.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return sessions;
  }

  // ---- Cài đặt ----

  /// Tần suất đánh giá do người dùng tự chọn. Giá trị này chỉ điều khiển
  /// lời nhắc; khoảng cách thực tế giữa các phiên phải đọc từ timestamp,
  /// không được suy ra từ cài đặt này.
  Future<int> assessmentIntervalDays() async {
    final prefs = await _p;
    return prefs.getInt(_kAssessmentIntervalDays) ?? 7;
  }

  Future<void> setAssessmentIntervalDays(int days) async {
    final prefs = await _p;
    await prefs.setInt(_kAssessmentIntervalDays, days);
  }

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

  /// Xoá toàn bộ dữ liệu — bắt buộc phải có cho phần quyền riêng tư.
  Future<void> wipeAll() async {
    final prefs = await _p;
    await prefs.remove(_kEntries);
    await prefs.remove(_kDraft);
    await prefs.remove(_kSessions);
  }
}
