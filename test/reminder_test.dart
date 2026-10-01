import 'package:flutter_test/flutter_test.dart';
import 'package:voice_journal/services/reminder_service.dart';

void main() {
  group('nextReminder', () {
    test('later today when the time has not passed', () {
      final next = ReminderService.nextReminder(DateTime(2026, 10, 1, 8),
          hour: 20, minute: 0);
      expect(next, DateTime(2026, 10, 1, 20));
    });

    test('tomorrow when the time has passed', () {
      final next = ReminderService.nextReminder(DateTime(2026, 10, 1, 21),
          hour: 20, minute: 0);
      expect(next, DateTime(2026, 10, 2, 20));
    });

    test('tomorrow when today is already recorded', () {
      final next = ReminderService.nextReminder(DateTime(2026, 10, 1, 8),
          hour: 20, minute: 0, doneToday: true);
      expect(next, DateTime(2026, 10, 2, 20));
    });

    test('rolls over month end', () {
      final next = ReminderService.nextReminder(DateTime(2026, 10, 31, 22),
          hour: 7, minute: 30);
      expect(next, DateTime(2026, 11, 1, 7, 30));
    });
  });
}
