import 'package:dday_before/models/dday.dart';
import 'package:dday_before/utils/day_calc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('dayDiff & formatCountdown', () {
    final today = DateTime(2026, 11, 25, 15, 30);

    test('default mode: future, today, past', () {
      expect(
        formatCountdownFromValues(
          date: '2026-12-25',
          countFromOne: false,
          today: today,
        ),
        'D-30',
      );
      expect(
        formatCountdownFromValues(
          date: '2026-11-26',
          countFromOne: false,
          today: today,
        ),
        'D-1',
      );
      expect(
        formatCountdownFromValues(
          date: '2026-11-25',
          countFromOne: false,
          today: today,
        ),
        'D-Day',
      );
      expect(
        formatCountdownFromValues(
          date: '2026-11-24',
          countFromOne: false,
          today: today,
        ),
        'D+1',
      );
      expect(
        formatCountdownFromValues(
          date: '2026-11-20',
          countFromOne: false,
          today: today,
        ),
        'D+5',
      );
    });

    test('countFromOne mode: start day is day 1, future is D-N', () {
      expect(
        formatCountdownFromValues(
          date: '2026-11-25',
          countFromOne: true,
          today: today,
        ),
        '第 1 天',
      );
      expect(
        formatCountdownFromValues(
          date: '2026-11-20',
          countFromOne: true,
          today: today,
        ),
        '第 6 天',
      );
      expect(
        formatCountdownFromValues(
          date: '2026-11-30',
          countFromOne: true,
          today: today,
        ),
        'D-5',
      );
    });

    test('cross-month, cross-year, and leap year 2/29', () {
      expect(
        dayDiff('2027-01-05', today: DateTime(2026, 12, 30)),
        6,
      );
      expect(
        dayDiff('2024-03-01', today: DateTime(2024, 2, 29)),
        1,
      );
      expect(
        dayDiff('2025-03-01', today: DateTime(2025, 2, 28)),
        1,
      );
      expect(
        dayDiff('2028-02-29', today: DateTime(2024, 2, 29)),
        1461,
      );
    });

    test('ignores time of day when computing difference', () {
      final lateNight = DateTime(2026, 11, 25, 23, 59, 59);
      final earlyMorning = DateTime(2026, 11, 25, 0, 0, 1);
      expect(dayDiff('2026-11-26', today: lateNight), 1);
      expect(dayDiff('2026-11-26', today: earlyMorning), 1);
    });

    test('UTC date difference avoids 23-hour DST truncation', () {
      // Even if input DateTimes span a 23h DST boundary in any local TZ,
      // dayDiff normalizes to UTC calendar dates first.
      final marchDay = DateTime(2026, 3, 7, 23, 50);
      expect(dayDiff('2026-03-09', today: marchDay), 2);
    });

    test('formatDisplayDateZh includes weekday in Traditional Chinese', () {
      expect(formatDisplayIsoDateZh('2026-12-25'), '2026/12/25 (五)');
      expect(formatDisplayIsoDateZh('2026-11-25'), '2026/11/25 (三)');
    });

    test('tryParseIsoDate rejects impossible calendar dates', () {
      expect(tryParseIsoDate('2025-02-29'), isNull);
      expect(tryParseIsoDate('2024-02-29'), isNotNull);
      expect(tryParseIsoDate('2026-13-01'), isNull);
    });

    test('formatCountdown works with DdayItem', () {
      final item = DdayItem.create(
        id: 'id-1',
        title: 'Test',
        date: '2026-11-25',
        countFromOne: true,
        now: today,
      );
      expect(formatCountdown(item, today: today), '第 1 天');
    });
  });
}
