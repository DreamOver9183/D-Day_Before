import '../models/dday.dart';

const List<String> _zhWeekdays = <String>['一', '二', '三', '四', '五', '六', '日'];
final RegExp _isoDatePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// Returns the local calendar date represented as UTC midnight to prevent DST
/// 23-hour day truncation bugs when computing day differences.
DateTime localToday([DateTime? now]) {
  final current = now ?? DateTime.now();
  return DateTime.utc(current.year, current.month, current.day);
}

/// Parses a strict `YYYY-MM-DD` date string into UTC midnight, or returns null
/// if the format or calendar date (e.g., 2025-02-29) is invalid.
DateTime? tryParseIsoDate(String yyyyMmDd) {
  final match = _isoDatePattern.firstMatch(yyyyMmDd);
  if (match == null) {
    return null;
  }
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final dt = DateTime.utc(year, month, day);
  if (dt.year != year || dt.month != month || dt.day != day) {
    return null;
  }
  return dt;
}

/// Parses a strict `YYYY-MM-DD` string into UTC midnight, throwing
/// [FormatException] when invalid.
DateTime parseIsoDate(String yyyyMmDd) {
  final parsed = tryParseIsoDate(yyyyMmDd);
  if (parsed == null) {
    throw FormatException('Invalid YYYY-MM-DD date: $yyyyMmDd');
  }
  return parsed;
}

/// Formats a [DateTime] using its calendar components as `YYYY-MM-DD`.
String formatIsoDate(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

/// Formats a [DateTime] as Traditional Chinese display date with weekday,
/// e.g. `2026/12/25 (五)`.
String formatDisplayDateZh(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  final weekday = _zhWeekdays[date.weekday - 1];
  return '$y/$m/$d ($weekday)';
}

/// Formats a `YYYY-MM-DD` string into `YYYY/MM/DD (週)`, falling back to the
/// raw string if parsing fails.
String formatDisplayIsoDateZh(String isoDate) {
  final parsed = tryParseIsoDate(isoDate);
  if (parsed == null) {
    return isoDate;
  }
  return formatDisplayDateZh(parsed);
}

/// Computes `targetDate - today` in whole days using UTC midnight normalization
/// so DST transitions never cause off-by-one errors.
int dayDiff(String targetDateStr, {DateTime? today}) {
  final targetUtc = parseIsoDate(targetDateStr);
  final todayUtc = localToday(today);
  return targetUtc.difference(todayUtc).inDays;
}

/// Formats the countdown label for raw values.
String formatCountdownFromValues({
  required String date,
  required bool countFromOne,
  DateTime? today,
}) {
  final diff = dayDiff(date, today: today);
  if (countFromOne) {
    if (diff <= 0) {
      return '第 ${-diff + 1} 天';
    }
    return 'D-$diff';
  }

  if (diff > 0) {
    return 'D-$diff';
  }
  if (diff == 0) {
    return 'D-Day';
  }
  return 'D+${-diff}';
}

/// Formats the countdown label for a [DdayItem].
String formatCountdown(DdayItem item, {DateTime? today}) {
  return formatCountdownFromValues(
    date: item.date,
    countFromOne: item.countFromOne,
    today: today,
  );
}
