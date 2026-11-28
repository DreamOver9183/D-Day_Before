import 'dart:convert';

import 'package:dday_before/data/backup_service.dart';
import 'package:dday_before/models/dday.dart';
import 'package:dday_before/theme/dday_icons.dart';
import 'package:dday_before/utils/day_calc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('iconKey', () {
    test('round-trips through JSON and backups', () {
      final item = DdayItem.create(
        id: 'i1',
        title: '生日',
        date: '2000-05-01',
        iconKey: 'birthday',
      );
      expect(item.iconKey, 'birthday');
      expect(item.toJson()['iconKey'], 'birthday');
      expect(DdayItem.tryFromJson(jsonDecode(jsonEncode(item.toJson()))), item);

      const service = BackupService();
      final parsed = service.parseBackupJson(
        service.exportJson(<DdayItem>[item]),
      );
      expect(parsed.items.single.iconKey, 'birthday');
    });

    test('is optional and omitted when unset', () {
      final item = DdayItem.create(id: 'i2', title: '一般', date: '2026-12-25');
      expect(item.iconKey, isNull);
      expect(item.toJson().containsKey('iconKey'), isFalse);
    });

    test('unknown or invalid keys fall back to the default icon', () {
      final raw = <String, Object>{
        'id': 'i3',
        'title': 'X',
        'date': '2026-12-25',
        'iconKey': 'spaceship',
      };
      expect(DdayItem.tryFromJson(raw)!.iconKey, isNull);
      expect(DdayItem.tryFromJson(<String, Object>{...raw, 'iconKey': 3})!.iconKey,
          isNull);
      expect(DdayIcons.byKey('spaceship'), DdayIcons.defaultPreset);
    });

    test('copyWith can set and clear the icon', () {
      final item = DdayItem.create(id: 'i4', title: 'X', date: '2026-12-25');
      final withIcon = item.copyWith(iconKey: 'travel');
      expect(withIcon.iconKey, 'travel');
      expect(withIcon.copyWith(title: 'Y').iconKey, 'travel');
      expect(withIcon.copyWith(iconKey: null).iconKey, isNull);
      expect(withIcon == item, isFalse);
    });

    test('every preset key is unique', () {
      final keys = DdayIcons.presets.map((p) => p.key).toList();
      expect(keys.toSet().length, keys.length);
    });
  });

  test('count-up label uses the N天 format', () {
    final today = DateTime(2026, 11, 25, 10);
    expect(
      formatCountdownFromValues(
        date: '2025-11-26',
        countFromOne: true,
        today: today,
      ),
      '365天',
    );
    expect(
      formatCountdownFromValues(date: '2026-11-20', countFromOne: false, today: today),
      'D+5',
      reason: 'plain past dates keep D+N',
    );
  });
}
