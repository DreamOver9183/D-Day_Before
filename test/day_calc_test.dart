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

  group('repeatYearly & Feb 29 handling', () {
    test('normal yearly birthday jumps to next year after passing', () {
      final item = DdayItem(
        id: 'bday',
        title: '生日',
        date: '1998-11-20',
        countFromOne: false,
        pinned: false,
        repeatYearly: true,
        createdAt: '2026-01-01T00:00:00.000Z',
      );

      // Before birthday in 2026 -> 2026-11-20 (5 days)
      expect(
        formatCountdown(item, today: DateTime(2026, 11, 15)),
        'D-5',
      );
      // On birthday -> D-Day
      expect(
        formatCountdown(item, today: DateTime(2026, 11, 20)),
        'D-Day',
      );
      expect(
        anniversarySubtitle(item, today: DateTime(2026, 11, 20)),
        '每年重複・第 28 週年',
      );
      // After birthday -> 2027-11-20 (360 days from 2026-11-25)
      expect(
        formatCountdown(item, today: DateTime(2026, 11, 25)),
        'D-360',
      );
      expect(
        anniversarySubtitle(item, today: DateTime(2026, 11, 25)),
        '每年重複・第 29 週年',
      );
    });

    test('Feb 29 uses Feb 28 in non-leap years and Feb 29 in leap years', () {
      final leapItem = DdayItem(
        id: 'leap',
        title: '四年一度',
        date: '2024-02-29',
        countFromOne: false,
        pinned: false,
        repeatYearly: true,
        createdAt: '2024-02-29T00:00:00.000Z',
      );

      // Non-leap 2025: Feb 27 -> D-1 (Feb 28)
      expect(
        formatCountdown(leapItem, today: DateTime(2025, 2, 27)),
        'D-1',
      );
      // Non-leap 2025: Feb 28 -> D-Day
      expect(
        formatCountdown(leapItem, today: DateTime(2025, 2, 28)),
        'D-Day',
      );
      // Non-leap 2025: Mar 1 -> jumps to 2026-02-28 (364 days)
      expect(
        nextYearlyOccurrence('2024-02-29', today: DateTime(2025, 3, 1)),
        DateTime.utc(2026, 2, 28),
      );
      // Leap 2028: Feb 28 -> D-1 (Feb 29)
      expect(
        formatCountdown(leapItem, today: DateTime(2028, 2, 28)),
        'D-1',
      );
      expect(
        formatCountdown(leapItem, today: DateTime(2028, 2, 29)),
        'D-Day',
      );
    });
  });
}
