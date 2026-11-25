import 'package:dday_before/models/dday.dart';
import 'package:dday_before/utils/dday_sorter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final today = DateTime(2026, 11, 25);

  DdayItem makeItem({
    required String id,
    required String date,
    bool pinned = false,
    bool countFromOne = false,
    String createdAt = '2026-11-20T00:00:00.000Z',
  }) {
    return DdayItem(
      id: id,
      title: id,
      date: date,
      countFromOne: countFromOne,
      pinned: pinned,
      createdAt: createdAt,
    );
  }

  group('sortDdays', () {
    test('nearest mode orders D-Day -> D-N -> D+1 -> D+500', () {
      final items = <DdayItem>[
        makeItem(id: 'past500', date: '2025-07-13'),
        makeItem(id: 'future30', date: '2026-12-25'),
        makeItem(id: 'past1', date: '2026-11-24'),
        makeItem(id: 'today', date: '2026-11-25'),
        makeItem(id: 'future1', date: '2026-11-26'),
      ];

      final sorted = sortDdays(items, DdaySortMode.nearest, today: today);
      expect(
        sorted.map((e) => e.id).toList(),
        <String>['today', 'future1', 'future30', 'past1', 'past500'],
      );
    });

    test('pinned items stay on top and follow active sort mode among themselves',
        () {
      final items = <DdayItem>[
        makeItem(id: 'unpinned_today', date: '2026-11-25', pinned: false),
        makeItem(id: 'pinned_far', date: '2027-05-01', pinned: true),
        makeItem(id: 'pinned_near', date: '2026-12-01', pinned: true),
        makeItem(id: 'pinned_past', date: '2026-11-01', pinned: true),
      ];

      final sorted = sortDdays(items, DdaySortMode.nearest, today: today);
      expect(
        sorted.map((e) => e.id).toList(),
        <String>['pinned_near', 'pinned_far', 'pinned_past', 'unpinned_today'],
      );
    });

    test('dateAsc sorts chronologically keeping pinned first', () {
      final items = <DdayItem>[
        makeItem(id: 'c', date: '2026-12-25'),
        makeItem(id: 'a', date: '2026-01-01'),
        makeItem(id: 'p2', date: '2027-01-01', pinned: true),
        makeItem(id: 'p1', date: '2026-06-01', pinned: true),
      ];

      final sorted = sortDdays(items, DdaySortMode.dateAsc, today: today);
      expect(sorted.map((e) => e.id).toList(), <String>['p1', 'p2', 'a', 'c']);
    });

    test('createdDesc sorts newest first with deterministic tie-breakers', () {
      final items = <DdayItem>[
        makeItem(
          id: 'b_same',
          date: '2026-12-01',
          createdAt: '2026-11-20T10:00:00.000Z',
        ),
        makeItem(
          id: 'a_same',
          date: '2026-12-01',
          createdAt: '2026-11-20T10:00:00.000Z',
        ),
        makeItem(
          id: 'newer',
          date: '2026-12-01',
          createdAt: '2026-11-21T10:00:00.000Z',
        ),
      ];

      final sorted = sortDdays(items, DdaySortMode.createdDesc, today: today);
      expect(
        sorted.map((e) => e.id).toList(),
        <String>['newer', 'a_same', 'b_same'],
      );
    });
  });
}
