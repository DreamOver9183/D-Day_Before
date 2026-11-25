import '../models/dday.dart';
import 'day_calc.dart';

/// Returns a new sorted list of [items] according to [mode], always keeping
/// pinned items above unpinned items and applying deterministic tie-breakers.
List<DdayItem> sortDdays(
  List<DdayItem> items,
  DdaySortMode mode, {
  DateTime? today,
}) {
  final todayNormalized = localToday(today);

  // Compute every sort key once per item instead of once per comparison.
  final keyed = <_SortKey>[
    for (final item in items) _SortKey.of(item, todayNormalized),
  ];

  keyed.sort((a, b) {
    if (a.item.pinned != b.item.pinned) {
      return a.item.pinned ? -1 : 1;
    }

    int primary = 0;
    switch (mode) {
      case DdaySortMode.nearest:
        final upcomingA = a.diff >= 0;
        final upcomingB = b.diff >= 0;
        if (upcomingA != upcomingB) {
          primary = upcomingA ? -1 : 1;
        } else if (upcomingA) {
          primary = a.diff.compareTo(b.diff);
        } else {
          // Both past: D+1 comes before D+5, D+5 before D+500.
          primary = (-a.diff).compareTo(-b.diff);
        }
      case DdaySortMode.dateAsc:
        primary = a.targetIso.compareTo(b.targetIso);
      case DdaySortMode.createdDesc:
        primary = _compareCreatedAtDesc(a, b);
    }

    if (primary != 0) {
      return primary;
    }

    final tieCreated = _compareCreatedAtDesc(a, b);
    if (tieCreated != 0) {
      return tieCreated;
    }
    return a.item.id.compareTo(b.item.id);
  });

  return <DdayItem>[for (final k in keyed) k.item];
}

class _SortKey {
  _SortKey(this.item, this.diff, this.targetIso, this.createdAtUtc);

  factory _SortKey.of(DdayItem item, DateTime today) {
    final target = effectiveTargetDate(item, today: today);
    return _SortKey(
      item,
      target.difference(today).inDays,
      formatIsoDate(target),
      DateTime.tryParse(item.createdAt)?.toUtc(),
    );
  }

  final DdayItem item;
  final int diff;
  final String targetIso;
  final DateTime? createdAtUtc;
}

int _compareCreatedAtDesc(_SortKey a, _SortKey b) {
  final parsedA = a.createdAtUtc;
  final parsedB = b.createdAtUtc;
  if (parsedA != null && parsedB != null) {
    return parsedB.compareTo(parsedA);
  }
  return b.item.createdAt.compareTo(a.item.createdAt);
}
