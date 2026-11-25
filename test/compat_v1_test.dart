import 'dart:convert';
import 'dart:io';

import 'package:dday_before/data/backup_service.dart';
import 'package:dday_before/data/dday_store.dart';
import 'package:dday_before/models/dday.dart';
import 'package:dday_before/utils/day_calc.dart';
import 'package:dday_before/utils/dday_sorter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Locks the observable behaviour of v1.0.0 data so refactors cannot silently
/// change what existing users see. Expected values were produced by v1.0.0,
/// except the count-up label, intentionally changed from `第 N 天` to `N天`.
void main() {
  final fixture =
      File('test/fixtures/v1_0_0_items.json').readAsStringSync();
  final today = DateTime(2026, 11, 25, 10);

  Future<List<DdayItem>> loadFixture() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      DdayStore.itemsKey: fixture,
    });
    return DdayStore().loadItems();
  }

  group('v1.0.0 compatibility', () {
    test('fixture keeps schemaVersion 1 and loads valid items only', () async {
      final decoded = jsonDecode(fixture) as Map<String, dynamic>;
      expect(decoded['schemaVersion'], 1);
      expect(DdayStore.currentSchemaVersion, 1);
      expect(BackupService.supportedSchemaVersion, 1);

      final items = await loadFixture();
      expect(items.map((e) => e.id), <String>[
        'a-exam',
        'b-couple',
        'c-birthday',
        'd-move',
        'e-today',
        'f-trip',
      ]);
      final birthday = items.firstWhere((e) => e.id == 'c-birthday');
      expect(birthday.colorKey, 'emerald', reason: 'legacy "color" field');
    });

    test('countdown labels and anniversary subtitles are unchanged', () async {
      final items = await loadFixture();
      final labels = <String, String>{
        for (final item in items) item.id: formatCountdown(item, today: today),
      };
      expect(labels, <String, String>{
        'a-exam': 'D-30',
        'b-couple': '365天',
        'c-birthday': 'D-95',
        'd-move': 'D+5',
        'e-today': 'D-Day',
        'f-trip': 'D-46',
      });

      final subtitles = <String, String?>{
        for (final item in items)
          item.id: anniversarySubtitle(item, today: today),
      };
      expect(subtitles['c-birthday'], '每年重複・第 27 週年');
      expect(
        subtitles.entries.where((e) => e.key != 'c-birthday').map((e) => e.value),
        everyElement(isNull),
      );

      final birthday = items.firstWhere((e) => e.id == 'c-birthday');
      expect(
        formatDisplayDateZh(effectiveTargetDate(birthday, today: today)),
        '2027/02/28 (日)',
      );
    });

    test('sort order for all three modes is unchanged', () async {
      final items = await loadFixture();
      List<String> order(DdaySortMode mode) =>
          sortDdays(items, mode, today: today).map((e) => e.id).toList();

      expect(order(DdaySortMode.nearest), <String>[
        'e-today',
        'a-exam',
        'f-trip',
        'c-birthday',
        'd-move',
        'b-couple',
      ]);
      expect(order(DdaySortMode.dateAsc), <String>[
        'e-today',
        'a-exam',
        'b-couple',
        'd-move',
        'f-trip',
        'c-birthday',
      ]);
      expect(order(DdaySortMode.createdDesc), <String>[
        'a-exam',
        'e-today',
        'f-trip',
        'd-move',
        'b-couple',
        'c-birthday',
      ]);
    });

    test('backup file imports with merge and overwrite', () async {
      const service = BackupService();
      final parsed = service.parseBackupJson(fixture);
      expect(parsed.schemaVersion, 1);
      expect(parsed.items, hasLength(6));
      expect(parsed.skippedCount, 1);

      final loaded = await loadFixture();
      expect(parsed.items, loaded);

      final existing = <DdayItem>[
        DdayItem(
          id: 'a-exam',
          title: '舊標題',
          date: '2026-12-24',
          countFromOne: false,
          pinned: false,
          createdAt: '2026-01-01T00:00:00.000Z',
        ),
        DdayItem(
          id: 'z-local',
          title: '本機項目',
          date: '2026-12-31',
          countFromOne: false,
          pinned: false,
          createdAt: '2026-01-01T00:00:00.000Z',
        ),
      ];

      final merged =
          service.applyImport(existing, parsed.items, BackupImportMode.merge);
      expect(merged.added, 5);
      expect(merged.updated, 1);
      expect(merged.total, 7);
      expect(merged.items.first.title, '期末考');
      expect(merged.items.map((e) => e.id), contains('z-local'));

      final overwritten = service.applyImport(
        existing,
        parsed.items,
        BackupImportMode.overwrite,
      );
      expect(overwritten.total, 6);
      expect(overwritten.items.map((e) => e.id), isNot(contains('z-local')));

      final reExported = service.parseBackupJson(
        service.exportJson(parsed.items, exportedAt: today),
      );
      expect(reExported.items, parsed.items);
      expect(reExported.skippedCount, 0);
    });
  });
}
