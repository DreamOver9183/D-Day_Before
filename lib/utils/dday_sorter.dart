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
  final sorted = List<DdayItem>.from(items);

  sorted.sort((a, b) {
    if (a.pinned != b.pinned) {
      return a.pinned ? -1 : 1;
    }

    int primary = 0;
    switch (mode) {
      case DdaySortMode.nearest:
        final diffA = dayDiff(a.date, today: todayNormalized);
        final diffB = dayDiff(b.date, today: todayNormalized);
        final upcomingA = diffA >= 0;
        final upcomingB = diffB >= 0;
        if (upcomingA != upcomingB) {
          primary = upcomingA ? -1 : 1;
        } else if (upcomingA) {
          primary = diffA.compareTo(diffB);
        } else {
          // Both past: D+1 comes before D+5, D+5 before D+500.
          primary = (-diffA).compareTo(-diffB);
        }
      case DdaySortMode.dateAsc:
        primary = a.date.compareTo(b.date);
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
    return a.id.compareTo(b.id);
  });

  return sorted;
}

int _compareCreatedAtDesc(DdayItem a, DdayItem b) {
  final parsedA = DateTime.tryParse(a.createdAt)?.toUtc();
  final parsedB = DateTime.tryParse(b.createdAt)?.toUtc();
  if (parsedA != null && parsedB != null) {
    return parsedB.compareTo(parsedA);
  }
  return b.createdAt.compareTo(a.createdAt);
}
