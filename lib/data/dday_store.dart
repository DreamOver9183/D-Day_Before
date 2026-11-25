import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/dday.dart';

/// Persists D-Day entries and user preferences in legacy XML SharedPreferences
/// so future native Android widgets can read the same file directly.
class DdayStore {
  DdayStore({Future<SharedPreferences> Function()? prefsProvider})
      : _prefsProvider = prefsProvider ?? SharedPreferences.getInstance;

  static const int currentSchemaVersion = 1;
  static const String itemsKey = 'dday_items_v1';
  static const String sortModeKey = 'dday_sort_mode';

  final Future<SharedPreferences> Function() _prefsProvider;

  Future<List<DdayItem>> loadItems() async {
    try {
      final prefs = await _prefsProvider();
      final raw = prefs.getString(itemsKey);
      if (raw == null || raw.trim().isEmpty) {
        return <DdayItem>[];
      }

      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return <DdayItem>[];
      }

      final rawItems = decoded['items'];
      if (rawItems is! List) {
        return <DdayItem>[];
      }

      final result = <DdayItem>[];
      for (final entry in rawItems) {
        final item = DdayItem.tryFromJson(entry);
        if (item != null) {
          result.add(item);
        }
      }
      return result;
    } catch (_) {
      return <DdayItem>[];
    }
  }

  Future<void> saveItems(List<DdayItem> items) async {
    final prefs = await _prefsProvider();
    final payload = <String, dynamic>{
      'schemaVersion': currentSchemaVersion,
      'items': items.map((item) => item.toJson()).toList(),
    };
    await prefs.setString(itemsKey, jsonEncode(payload));
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
    final prefs = await _prefsProvider();
    await prefs.setString(sortModeKey, mode.storageKey);
  }
}
