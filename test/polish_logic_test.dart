import 'dart:math';

import 'package:dday_before/models/dday.dart';
import 'package:dday_before/screens/edit_screen.dart';
import 'package:dday_before/utils/day_calc.dart';
import 'package:dday_before/utils/dday_sorter.dart';
import 'package:flutter_test/flutter_test.dart';

/// The v1.0.0 comparator, kept verbatim as a reference for the faster
/// precomputed-key implementation.
List<DdayItem> referenceSort(
  List<DdayItem> items,
  DdaySortMode mode, {
  required DateTime today,
}) {
  final todayNormalized = localToday(today);
  int compareCreatedAtDesc(DdayItem a, DdayItem b) {
    final parsedA = DateTime.tryParse(a.createdAt)?.toUtc();
    final parsedB = DateTime.tryParse(b.createdAt)?.toUtc();
    if (parsedA != null && parsedB != null) {
      return parsedB.compareTo(parsedA);
    }
    return b.createdAt.compareTo(a.createdAt);
  }

  final sorted = List<DdayItem>.from(items);
  sorted.sort((a, b) {
    if (a.pinned != b.pinned) {
      return a.pinned ? -1 : 1;
    }
    int primary = 0;
    switch (mode) {
      case DdaySortMode.nearest:
        final diffA = effectiveDayDiff(a, today: todayNormalized);
        final diffB = effectiveDayDiff(b, today: todayNormalized);
        final upcomingA = diffA >= 0;
        final upcomingB = diffB >= 0;
        if (upcomingA != upcomingB) {
          primary = upcomingA ? -1 : 1;
        } else if (upcomingA) {
          primary = diffA.compareTo(diffB);
        } else {
          primary = (-diffA).compareTo(-diffB);
        }
      case DdaySortMode.dateAsc:
        primary = formatIsoDate(effectiveTargetDate(a, today: todayNormalized))
            .compareTo(
                formatIsoDate(effectiveTargetDate(b, today: todayNormalized)));
      case DdaySortMode.createdDesc:
        primary = compareCreatedAtDesc(a, b);
    }
    if (primary != 0) return primary;
    final tie = compareCreatedAtDesc(a, b);
    if (tie != 0) return tie;
    return a.id.compareTo(b.id);
  });
  return sorted;
}

void main() {
  group('P3: yearly repeat with a future start date', () {
    final today = DateTime(2026, 11, 25, 10);
    DdayItem yearly(String date) => DdayItem.create(
          id: 'y',
          title: '生日',
          date: date,
          repeatYearly: true,
        );

    test('counts down to the original date before the first occurrence', () {
      final item = yearly('2030-01-01');
      expect(formatDisplayDateZh(effectiveTargetDate(item, today: today)),
          '2030/01/01 (二)');
      expect(effectiveDayDiff(item, today: today), 1133);
      expect(formatCountdown(item, today: today), 'D-1133');
      expect(anniversarySubtitle(item, today: today), '每年重複');
    });

    test('first occurrence day shows D-Day and no anniversary count', () {
      final item = yearly('2026-11-25');
      expect(formatCountdown(item, today: today), 'D-Day');
      expect(anniversarySubtitle(item, today: today), '每年重複');
    });

    test('the day after the first occurrence jumps to next year', () {
      final item = yearly('2026-11-24');
      expect(
        formatIsoDate(effectiveTargetDate(item, today: today)),
        '2027-11-24',
      );
      expect(anniversarySubtitle(item, today: today), '每年重複・第 1 週年');
    });

    test('future Feb 29 start is kept as-is until it happens', () {
      final item = yearly('2028-02-29');
      expect(formatIsoDate(effectiveTargetDate(item, today: today)),
          '2028-02-29');
      final afterFirst = DateTime(2028, 3, 1);
      expect(formatIsoDate(effectiveTargetDate(item, today: afterFirst)),
          '2029-02-28');
    });

    test('edit preview helper agrees', () {
      expect(
        formatCountdownFromValues(
          date: '2030-01-01',
          countFromOne: false,
          repeatYearly: true,
          today: today,
        ),
        'D-1133',
      );
    });
  });

  group('P8: precomputed sort keys match the v1.0.0 comparator', () {
    test('200 random items in all modes', () {
      final random = Random(20261125);
      final today = DateTime(2026, 11, 25, 10);
      final createdPool = <String>[
        for (var i = 0; i < 20; i++)
          DateTime.utc(2026, 1 + random.nextInt(11), 1 + random.nextInt(28))
              .toIso8601String(),
      ];
      final items = <DdayItem>[
        for (var i = 0; i < 200; i++)
          () {
            final repeat = random.nextInt(4) == 0;
            // Past start dates only for yearly items: P3 intentionally
            // changed future-start yearly items.
            final year = repeat
                ? 1990 + random.nextInt(30)
                : 2020 + random.nextInt(10);
            final date = DateTime.utc(
              year,
              1 + random.nextInt(12),
              1 + random.nextInt(28),
            );
            return DdayItem(
              id: 'id-${random.nextInt(1000).toString().padLeft(4, '0')}-$i',
              title: 'T$i',
              date: formatIsoDate(date),
              countFromOne: !repeat && random.nextBool(),
              pinned: random.nextInt(5) == 0,
              createdAt: createdPool[random.nextInt(createdPool.length)],
              repeatYearly: repeat,
            );
          }(),
      ];

      for (final mode in DdaySortMode.values) {
        expect(
          sortDdays(items, mode, today: today).map((e) => e.id).toList(),
          referenceSort(items, mode, today: today).map((e) => e.id).toList(),
          reason: mode.storageKey,
        );
      }
    });
  });

  group('P7: validateTitle counts user-visible characters', () {
    test('50 emoji pass, 51 fail', () {
      expect(validateTitle('🎂' * 50), isNull);
      expect(validateTitle('👨‍👩‍👧' * 50), isNull, reason: 'ZWJ family = 1 char');
      expect(validateTitle('🎂' * 51), '標題最多 50 個字');
    });

    test('blank titles fail, normal titles pass', () {
      expect(validateTitle(null), '請輸入標題');
      expect(validateTitle('   '), '請輸入標題');
      expect(validateTitle('  期末考  '), isNull);
      expect(validateTitle('字' * 50), isNull);
      expect(validateTitle('字' * 51), '標題最多 50 個字');
    });
  });
}
