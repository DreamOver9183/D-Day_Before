import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/dday.dart';

/// Thrown when SharedPreferences reports that a write did not succeed.
class StorageWriteException implements Exception {
  const StorageWriteException(this.key, [this.cause]);

  final String key;
  final Object? cause;

  @override
  String toString() =>
      'StorageWriteException($key${cause == null ? '' : ': $cause'})';
}

/// Result of [DdayStore.loadItemsDetailed].
class LoadItemsResult {
  const LoadItemsResult({required this.items, this.recoveryRaw});

  /// Items that parsed successfully.
  final List<DdayItem> items;

  /// Original stored text that could not be fully read, kept until the user
  /// acknowledges it. Null when nothing needs recovering.
  final String? recoveryRaw;
}

/// Persists D-Day entries and user preferences in legacy XML SharedPreferences
/// so future native Android widgets can read the same file directly.
class DdayStore {
  DdayStore({Future<SharedPreferences> Function()? prefsProvider})
    : _prefsProvider = prefsProvider ?? SharedPreferences.getInstance;

  static const int currentSchemaVersion = 1;
  static const String itemsKey = 'dday_items_v1';
  static const String recoveryKey = 'dday_items_recovery_v1';
  static const String sortModeKey = 'dday_sort_mode';
  static const String themeModeKey = 'dday_theme_mode';
  static const String ongoingNotificationKey = 'dday_ongoing_notification';
  static const String reminderTimeKey = 'dday_reminder_time';
  static const String updateAutoCheckKey = 'dday_update_auto_check';
  static const String updateLastCheckKey = 'dday_update_last_check';

  final Future<SharedPreferences> Function() _prefsProvider;

  Future<List<DdayItem>> loadItems() async {
    return (await loadItemsDetailed()).items;
  }

  /// Loads items and, if the stored data was corrupt or partly unreadable,
  /// preserves the original text under [recoveryKey] so a later save cannot
  /// silently destroy it.
  Future<LoadItemsResult> loadItemsDetailed() async {
    final SharedPreferences prefs;
    try {
      prefs = await _prefsProvider();
    } catch (_) {
      return const LoadItemsResult(items: <DdayItem>[]);
    }

    final existingRecovery = _readString(prefs, recoveryKey);
    final raw = _readString(prefs, itemsKey);
    if (raw == null || raw.trim().isEmpty) {
      return LoadItemsResult(
        items: const <DdayItem>[],
        recoveryRaw: _nonEmpty(existingRecovery),
      );
    }

    final result = <DdayItem>[];
    var damaged = false;
    try {
      final decoded = jsonDecode(raw);
      final rawItems = decoded is Map ? decoded['items'] : null;
      if (rawItems is List) {
        for (final entry in rawItems) {
          final item = DdayItem.tryFromJson(entry);
          if (item != null) {
            result.add(item);
          } else {
            damaged = true;
          }
        }
      } else {
        damaged = true;
      }
    } catch (_) {
      damaged = true;
    }

    var recovery = _nonEmpty(existingRecovery);
    if (damaged && recovery == null) {
      recovery = raw;
      try {
        await prefs.setString(recoveryKey, raw);
      } catch (_) {
        // Still hand the raw text to the UI for this session.
      }
    }

    return LoadItemsResult(items: result, recoveryRaw: recovery);
  }

  /// Removes the preserved recovery text after the user acknowledged it.
  Future<void> clearRecoveryRaw() async {
    await _write(recoveryKey, (prefs) => prefs.remove(recoveryKey));
  }

  Future<void> saveItems(List<DdayItem> items) async {
    final payload = <String, dynamic>{
      'schemaVersion': currentSchemaVersion,
      'items': items.map((item) => item.toJson()).toList(),
    };
    final encoded = jsonEncode(payload);
    await _write(itemsKey, (prefs) => prefs.setString(itemsKey, encoded));
  }

  static String? _readString(SharedPreferences prefs, String key) {
    try {
      return prefs.getString(key);
    } catch (_) {
      return null;
    }
  }

  static String? _nonEmpty(String? value) =>
      value == null || value.isEmpty ? null : value;

  /// Runs a SharedPreferences write and converts both thrown errors and a
  /// `false` result into [StorageWriteException].
  Future<void> _write(
    String key,
    Future<bool> Function(SharedPreferences prefs) op,
  ) async {
    final bool ok;
    try {
      ok = await op(await _prefsProvider());
    } catch (e) {
      throw StorageWriteException(key, e);
    }
    if (!ok) {
      throw StorageWriteException(key);
    }
  }

  Future<DdaySortMode> loadSortMode() async {
    try {
      final prefs = await _prefsProvider();
      return DdaySortMode.fromStorageKey(prefs.getString(sortModeKey));
    } catch (_) {
      return DdaySortMode.nearest;
    }
  }

  Future<void> saveSortMode(DdaySortMode mode) async {
    await _write(
      sortModeKey,
      (prefs) => prefs.setString(sortModeKey, mode.storageKey),
    );
  }

  Future<ThemeMode> loadThemeMode() async {
    try {
      final prefs = await _prefsProvider();
      return switch (prefs.getString(themeModeKey)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    } catch (_) {
      return ThemeMode.system;
    }
  }

  Future<void> saveThemeMode(ThemeMode mode) async {
    final value = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await _write(themeModeKey, (prefs) => prefs.setString(themeModeKey, value));
  }

  Future<bool> loadOngoingNotification() async {
    try {
      final prefs = await _prefsProvider();
      return prefs.getBool(ongoingNotificationKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> saveOngoingNotification(bool enabled) async {
    await _write(
      ongoingNotificationKey,
      (prefs) => prefs.setBool(ongoingNotificationKey, enabled),
    );
  }

  Future<String> loadReminderTime() async {
    try {
      final prefs = await _prefsProvider();
      final raw = prefs.getString(reminderTimeKey);
      if (raw != null && RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(raw)) {
        return raw;
      }
      return '09:00';
    } catch (_) {
      return '09:00';
    }
  }

  Future<void> saveReminderTime(String hhMm) async {
    await _write(
      reminderTimeKey,
      (prefs) => prefs.setString(reminderTimeKey, hhMm),
    );
  }

  /// Whether the app checks GitHub for updates by itself (default on).
  Future<bool> loadUpdateAutoCheck() async {
    try {
      final prefs = await _prefsProvider();
      return prefs.getBool(updateAutoCheckKey) ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<void> saveUpdateAutoCheck(bool enabled) async {
    await _write(
      updateAutoCheckKey,
      (prefs) => prefs.setBool(updateAutoCheckKey, enabled),
    );
  }

  Future<DateTime?> loadUpdateLastCheck() async {
    try {
      final prefs = await _prefsProvider();
      final raw = prefs.getString(updateLastCheckKey);
      return raw == null ? null : DateTime.tryParse(raw);
    } catch (_) {
      return null;
    }
  }

  /// Best effort: a failed write only means checking again sooner.
  Future<void> saveUpdateLastCheck(DateTime time) async {
    try {
      await _write(
        updateLastCheckKey,
        (prefs) =>
            prefs.setString(updateLastCheckKey, time.toUtc().toIso8601String()),
      );
    } on StorageWriteException {
      // Ignore.
    }
  }
}
