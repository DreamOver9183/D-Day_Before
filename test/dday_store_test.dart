import 'dart:convert';

import 'package:dday_before/data/dday_store.dart';
import 'package:dday_before/models/dday.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('DdayItem & DdayStore', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('saveItems writes schemaVersion 1 envelope and round-trips', () async {
      final store = DdayStore();
      final item = DdayItem.create(
        id: 'uuid-1',
        title: '期末考',
        date: '2026-12-25',
        countFromOne: false,
        pinned: true,
        now: DateTime.utc(2026, 11, 25, 7, 40),
      );

      await store.saveItems(<DdayItem>[item]);

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(DdayStore.itemsKey);
      expect(raw, isNotNull);

      final decoded = jsonDecode(raw!) as Map<String, dynamic>;
      expect(decoded['schemaVersion'], 1);
      expect(decoded['items'], hasLength(1));

      final loaded = await store.loadItems();
      expect(loaded, <DdayItem>[item]);
    });

    test('tryFromJson tolerates missing optional fields and unknown fields',
        () {
      final parsed = DdayItem.tryFromJson(<String, dynamic>{
        'id': 'legacy-1',
        'title': '生日',
        'date': '2026-05-20',
        'repeatYearly': true,
        'color': 'blue',
      });

      expect(parsed, isNotNull);
      expect(parsed!.countFromOne, isFalse);
      expect(parsed.pinned, isFalse);
      expect(parsed.createdAt.endsWith('Z'), isTrue);
    });

    test('loadItems gracefully handles corrupt JSON and malformed entries',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        DdayStore.itemsKey: '{not valid json',
      });
      final store = DdayStore();
      expect(await store.loadItems(), isEmpty);

      SharedPreferences.setMockInitialValues(<String, Object>{
        DdayStore.itemsKey: jsonEncode(<String, dynamic>{
          'schemaVersion': 1,
          'items': <dynamic>[
            <String, dynamic>{'id': 'bad_no_date', 'title': 'Bad'},
            <String, dynamic>{
              'id': 'bad_date',
              'title': 'BadDate',
              'date': '2025-02-29',
            },
            <String, dynamic>{
              'id': 'ok',
              'title': 'Valid',
              'date': '2026-12-25',
            },
          ],
        }),
      });
      final loaded = await store.loadItems();
      expect(loaded, hasLength(1));
      expect(loaded.first.id, 'ok');
    });

    test('sortMode persists across store instances', () async {
      final store = DdayStore();
      expect(await store.loadSortMode(), DdaySortMode.nearest);

      await store.saveSortMode(DdaySortMode.createdDesc);
      expect(await DdayStore().loadSortMode(), DdaySortMode.createdDesc);
    });

    test('generateUuidV4 generates distinct v4 UUIDs', () {
      final a = generateUuidV4();
      final b = generateUuidV4();
      expect(a, isNot(equals(b)));
      expect(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(a),
        isTrue,
      );
    });
  });
}
