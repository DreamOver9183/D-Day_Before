import 'dart:convert';

import 'package:dday_before/data/dday_store.dart';
import 'package:dday_before/models/dday.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_prefs.dart';

void main() {
  final validItem = <String, Object>{
    'id': 'ok-1',
    'title': '期末考',
    'date': '2026-12-25',
    'countFromOne': false,
    'pinned': false,
    'createdAt': '2026-11-25T00:00:00.000Z',
  };
  final partlyBroken = jsonEncode(<String, Object>{
    'schemaVersion': 1,
    'items': <Object>[
      validItem,
      <String, Object>{'id': 'bad', 'date': '2026-01-01'},
    ],
  });
  final healthy = jsonEncode(<String, Object>{
    'schemaVersion': 1,
    'items': <Object>[validItem],
  });

  DdayStore storeWith(FakePrefs prefs) =>
      DdayStore(prefsProvider: () async => prefs);

  group('loadItemsDetailed recovery', () {
    test('corrupt JSON is preserved and reported', () async {
      final prefs = FakePrefs(<String, Object>{DdayStore.itemsKey: '{broken'});
      final result = await storeWith(prefs).loadItemsDetailed();

      expect(result.items, isEmpty);
      expect(result.recoveryRaw, '{broken');
      expect(prefs.data[DdayStore.recoveryKey], '{broken');
      expect(prefs.data[DdayStore.itemsKey], '{broken',
          reason: 'loading must never touch the main key');
    });

    test('a single malformed entry triggers recovery, valid ones load',
        () async {
      final prefs = FakePrefs(<String, Object>{DdayStore.itemsKey: partlyBroken});
      final result = await storeWith(prefs).loadItemsDetailed();

      expect(result.items.map((e) => e.id), <String>['ok-1']);
      expect(result.recoveryRaw, partlyBroken);
      expect(prefs.data[DdayStore.recoveryKey], partlyBroken);
    });

    test('wrong top-level structure triggers recovery', () async {
      final prefs = FakePrefs(<String, Object>{DdayStore.itemsKey: '[1,2,3]'});
      final result = await storeWith(prefs).loadItemsDetailed();
      expect(result.items, isEmpty);
      expect(result.recoveryRaw, '[1,2,3]');
    });

    test('existing recovery text is never overwritten', () async {
      final prefs = FakePrefs(<String, Object>{
        DdayStore.itemsKey: '{newer-broken',
        DdayStore.recoveryKey: '{older-broken',
      });
      final result = await storeWith(prefs).loadItemsDetailed();

      expect(result.recoveryRaw, '{older-broken');
      expect(prefs.data[DdayStore.recoveryKey], '{older-broken');
    });

    test('recovery is still reported after the main key became healthy',
        () async {
      final prefs = FakePrefs(<String, Object>{
        DdayStore.itemsKey: healthy,
        DdayStore.recoveryKey: '{older-broken',
      });
      final result = await storeWith(prefs).loadItemsDetailed();

      expect(result.items, hasLength(1));
      expect(result.recoveryRaw, '{older-broken');
    });

    test('healthy data does not create recovery', () async {
      final prefs = FakePrefs(<String, Object>{DdayStore.itemsKey: healthy});
      final result = await storeWith(prefs).loadItemsDetailed();

      expect(result.items, hasLength(1));
      expect(result.recoveryRaw, isNull);
      expect(prefs.data.containsKey(DdayStore.recoveryKey), isFalse);
    });

    test('empty storage loads nothing and needs no recovery', () async {
      final result = await storeWith(FakePrefs()).loadItemsDetailed();
      expect(result.items, isEmpty);
      expect(result.recoveryRaw, isNull);
    });

    test('raw text is returned even if writing recovery fails', () async {
      final prefs = FakePrefs(<String, Object>{DdayStore.itemsKey: '{broken'})
        ..throwKeys.add(DdayStore.recoveryKey);
      final result = await storeWith(prefs).loadItemsDetailed();
      expect(result.recoveryRaw, '{broken');

      final rejecting = FakePrefs(<String, Object>{DdayStore.itemsKey: '{x'})
        ..rejectKeys.add(DdayStore.recoveryKey);
      final second = await storeWith(rejecting).loadItemsDetailed();
      expect(second.recoveryRaw, '{x');
    });

    test('clearRecoveryRaw removes the preserved text', () async {
      final prefs = FakePrefs(<String, Object>{
        DdayStore.recoveryKey: '{older-broken',
      });
      await storeWith(prefs).clearRecoveryRaw();
      expect(prefs.data.containsKey(DdayStore.recoveryKey), isFalse);
    });

    test('loadItems keeps its old contract', () async {
      final prefs = FakePrefs(<String, Object>{DdayStore.itemsKey: partlyBroken});
      final items = await storeWith(prefs).loadItems();
      expect(items.map((e) => e.id), <String>['ok-1']);
    });
  });

  group('write failures raise StorageWriteException', () {
    final item = DdayItem.create(title: 'A', date: '2026-12-25', id: 'a');

    Future<void> expectFails(
      String key,
      Future<void> Function(DdayStore store) write,
    ) async {
      final rejecting = FakePrefs()..rejectKeys.add(key);
      await expectLater(
        write(storeWith(rejecting)),
        throwsA(isA<StorageWriteException>()),
      );
      final throwing = FakePrefs()..throwKeys.add(key);
      await expectLater(
        write(storeWith(throwing)),
        throwsA(isA<StorageWriteException>()),
      );
    }

    test('every save method reports failures', () async {
      await expectFails(DdayStore.itemsKey, (s) => s.saveItems(<DdayItem>[item]));
      await expectFails(
        DdayStore.sortModeKey,
        (s) => s.saveSortMode(DdaySortMode.dateAsc),
      );
      await expectFails(
        DdayStore.themeModeKey,
        (s) => s.saveThemeMode(ThemeMode.dark),
      );
      await expectFails(
        DdayStore.ongoingNotificationKey,
        (s) => s.saveOngoingNotification(true),
      );
      await expectFails(
        DdayStore.reminderTimeKey,
        (s) => s.saveReminderTime('08:30'),
      );
      await expectFails(DdayStore.recoveryKey, (s) => s.clearRecoveryRaw());
    });

    test('successful writes still work', () async {
      final prefs = FakePrefs();
      final store = storeWith(prefs);
      await store.saveItems(<DdayItem>[item]);
      await store.saveSortMode(DdaySortMode.dateAsc);
      expect(await store.loadItems(), <DdayItem>[item]);
      expect(await store.loadSortMode(), DdaySortMode.dateAsc);
    });
  });
}
