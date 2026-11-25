import 'dart:math';

import 'package:flutter/foundation.dart';

import '../theme/dday_colors.dart';
import '../theme/dday_icons.dart';
import '../services/background_images.dart';

/// Sorting strategies supported by the home list.
enum DdaySortMode {
  nearest('nearest', '距離今天最近'),
  dateAsc('dateAsc', '日期先後（舊 → 新）'),
  createdDesc('createdDesc', '建立時間（最新優先）');

  const DdaySortMode(this.storageKey, this.label);

  final String storageKey;
  final String label;

  static DdaySortMode fromStorageKey(String? key) {
    for (final mode in values) {
      if (mode.storageKey == key) {
        return mode;
      }
    }
    return DdaySortMode.nearest;
  }
}

final Random _secureRandom = Random.secure();

/// Generates a random RFC-4122 UUID v4 string without external dependencies.
String generateUuidV4() {
  final bytes = List<int>.generate(16, (_) => _secureRandom.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant RFC 4122

  String hex(int byte) => byte.toRadixString(16).padLeft(2, '0');
  final buffer = StringBuffer();
  for (var i = 0; i < 16; i++) {
    if (i == 4 || i == 6 || i == 8 || i == 10) {
      buffer.write('-');
    }
    buffer.write(hex(bytes[i]));
  }
  return buffer.toString();
}

final RegExp _isoDatePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

const Object _unset = Object();

/// Immutable D-Day entry stored in local JSON.
class DdayItem {
  const DdayItem({
    required this.id,
    required this.title,
    required this.date,
    required this.countFromOne,
    required this.pinned,
    required this.createdAt,
    this.repeatYearly = false,
    this.colorKey,
    this.reminderDaysBefore = const <int>[],
    this.iconKey,
    this.backgroundImage,
  });

  final String id;
  final String title;
  final String date; // Pure date: YYYY-MM-DD
  final bool countFromOne;
  final bool pinned;
  final String createdAt; // UTC ISO-8601 ending in Z
  final bool repeatYearly;
  final String? colorKey;
  final List<int> reminderDaysBefore;

  /// Category icon key (see [DdayIcons]); null shows the default icon.
  final String? iconKey;

  /// File name of the item's background photo in app storage (see
  /// [BackgroundImages]); null when the item has no photo.
  final String? backgroundImage;

  factory DdayItem.create({
    required String title,
    required String date,
    bool countFromOne = false,
    bool pinned = false,
    bool repeatYearly = false,
    String? colorKey,
    List<int> reminderDaysBefore = const <int>[],
    String? iconKey,
    String? backgroundImage,
    DateTime? now,
    String? id,
  }) {
    final timestamp = (now ?? DateTime.now()).toUtc().toIso8601String();
    return DdayItem(
      id: id ?? generateUuidV4(),
      title: title.trim(),
      date: date,
      countFromOne: repeatYearly ? false : countFromOne,
      pinned: pinned,
      createdAt: timestamp,
      repeatYearly: repeatYearly,
      colorKey: DdayColors.normalizeKey(colorKey),
      reminderDaysBefore: _normalizeReminderDays(reminderDaysBefore),
      iconKey: DdayIcons.normalizeKey(iconKey),
      backgroundImage: BackgroundImages.normalizeName(backgroundImage),
    );
  }

  DdayItem copyWith({
    String? id,
    String? title,
    String? date,
    bool? countFromOne,
    bool? pinned,
    String? createdAt,
    bool? repeatYearly,
    Object? colorKey = _unset,
    List<int>? reminderDaysBefore,
    Object? iconKey = _unset,
    Object? backgroundImage = _unset,
  }) {
    return DdayItem(
      id: id ?? this.id,
      title: title ?? this.title,
      date: date ?? this.date,
      countFromOne: countFromOne ?? this.countFromOne,
      pinned: pinned ?? this.pinned,
      createdAt: createdAt ?? this.createdAt,
      repeatYearly: repeatYearly ?? this.repeatYearly,
      colorKey: identical(colorKey, _unset)
          ? this.colorKey
          : DdayColors.normalizeKey(colorKey),
      reminderDaysBefore: reminderDaysBefore != null
          ? _normalizeReminderDays(reminderDaysBefore)
          : this.reminderDaysBefore,
      iconKey: identical(iconKey, _unset)
          ? this.iconKey
          : DdayIcons.normalizeKey(iconKey),
      backgroundImage: identical(backgroundImage, _unset)
          ? this.backgroundImage
          : BackgroundImages.normalizeName(backgroundImage),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'date': date,
      'countFromOne': countFromOne,
      'pinned': pinned,
      'createdAt': createdAt,
      'repeatYearly': repeatYearly,
      if (colorKey != null) 'colorKey': colorKey,
      if (reminderDaysBefore.isNotEmpty)
        'reminderDaysBefore': reminderDaysBefore,
      if (iconKey != null) 'iconKey': iconKey,
      if (backgroundImage != null) 'backgroundImage': backgroundImage,
    };
  }

  /// Resiliently parses a JSON object into a [DdayItem], returning null if
  /// required fields are missing or invalid. Unknown fields are ignored.
  static DdayItem? tryFromJson(dynamic raw) {
    if (raw is! Map) {
      return null;
    }

    final rawId = raw['id'];
    final rawTitle = raw['title'];
    final rawDate = raw['date'];

    if (rawId is! String || rawId.trim().isEmpty) {
      return null;
    }
    if (rawTitle is! String || rawTitle.trim().isEmpty) {
      return null;
    }
    if (rawDate is! String || !_isValidIsoDate(rawDate)) {
      return null;
    }

    final rawCountFromOne = raw['countFromOne'];
    final rawPinned = raw['pinned'];
    final rawRepeatYearly = raw['repeatYearly'];
    final rawCreatedAt = raw['createdAt'];
    final rawColorKey = raw['colorKey'] ?? raw['color'];
    final rawReminders = raw['reminderDaysBefore'];

    String normalizedCreatedAt;
    if (rawCreatedAt is String) {
      final parsed = DateTime.tryParse(rawCreatedAt);
      normalizedCreatedAt = parsed != null
          ? parsed.toUtc().toIso8601String()
          : DateTime.fromMillisecondsSinceEpoch(
              0,
              isUtc: true,
            ).toIso8601String();
    } else {
      normalizedCreatedAt = DateTime.fromMillisecondsSinceEpoch(
        0,
        isUtc: true,
      ).toIso8601String();
    }

    final repeatYearly = rawRepeatYearly is bool ? rawRepeatYearly : false;
    final countFromOne = !repeatYearly && rawCountFromOne is bool
        ? rawCountFromOne
        : false;
    final reminders = rawReminders is List
        ? _normalizeReminderDays(rawReminders.whereType<int>())
        : const <int>[];

    return DdayItem(
      id: rawId.trim(),
      title: rawTitle.trim(),
      date: rawDate,
      countFromOne: countFromOne,
      pinned: rawPinned is bool ? rawPinned : false,
      createdAt: normalizedCreatedAt,
      repeatYearly: repeatYearly,
      colorKey: DdayColors.normalizeKey(rawColorKey),
      reminderDaysBefore: reminders,
      iconKey: DdayIcons.normalizeKey(raw['iconKey']),
      backgroundImage: BackgroundImages.normalizeName(raw['backgroundImage']),
    );
  }

  static List<int> _normalizeReminderDays(Iterable<int> days) {
    final unique = <int>{
      for (final d in days)
        if (d >= 0) d,
    }.toList()..sort();
    return List<int>.unmodifiable(unique);
  }

  static bool _isValidIsoDate(String value) {
    final match = _isoDatePattern.firstMatch(value);
    if (match == null) {
      return false;
    }
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final dt = DateTime.utc(year, month, day);
    return dt.year == year && dt.month == month && dt.day == day;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DdayItem &&
        other.id == id &&
        other.title == title &&
        other.date == date &&
        other.countFromOne == countFromOne &&
        other.pinned == pinned &&
        other.createdAt == createdAt &&
        other.repeatYearly == repeatYearly &&
        other.colorKey == colorKey &&
        listEquals(other.reminderDaysBefore, reminderDaysBefore) &&
        other.iconKey == iconKey &&
        other.backgroundImage == backgroundImage;
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    date,
    countFromOne,
    pinned,
    createdAt,
    repeatYearly,
    colorKey,
    Object.hashAll(reminderDaysBefore),
    iconKey,
    backgroundImage,
  );
}
