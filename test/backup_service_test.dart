import 'dart:convert';

import 'package:dday_before/data/backup_service.dart';
import 'package:dday_before/models/dday.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = BackupService();

  final item1 = DdayItem(
    id: 'id-1',
    title: '期末考',
    date: '2026-12-25',
    countFromOne: false,
    pinned: false,
    createdAt: '2026-11-25T07:40:00.000Z',
  );
  final item2 = DdayItem(
    id: 'id-2',
    title: '紀念日',
    date: '2026-11-25',
    countFromOne: true,
    pinned: true,
    createdAt: '2026-11-25T08:00:00.000Z',
  );

  group('BackupService', () {
    test('exportJson includes schemaVersion 1, exportedAt UTC, and items', () {
      final raw = service.exportJson(
        <DdayItem>[item1],
        exportedAt: DateTime.utc(2026, 11, 25, 9, 0),
      );
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      expect(decoded['schemaVersion'], 1);
      expect(decoded['exportedAt'], '2026-11-25T09:00:00.000Z');
      expect(decoded['items'], hasLength(1));

      final parsed = service.parseBackupJson(raw);
      expect(parsed.items, <DdayItem>[item1]);
      expect(parsed.skippedCount, 0);
    });

    test('parseBackupJson throws descriptive errors on invalid inputs', () {
      expect(
        () => service.parseBackupJson('   '),
        throwsA(isA<BackupFormatException>()),
      );
      expect(
        () => service.parseBackupJson('{bad'),
        throwsA(isA<BackupFormatException>()),
      );
      expect(
        () => service.parseBackupJson('[]'),
        throwsA(isA<BackupFormatException>()),
      );
      expect(
        () => service.parseBackupJson('{"schemaVersion": 99, "items": []}'),
        throwsA(isA<BackupFormatException>()),
      );
      expect(
        () => service.parseBackupJson('{"schemaVersion": 1, "items": "no"}'),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('parseBackupJson skips invalid item entries and counts them', () {
      final raw = jsonEncode(<String, dynamic>{
        'schemaVersion': 1,
        'items': <dynamic>[
          item1.toJson(),
          <String, dynamic>{'id': 'broken'},
        ],
      });
      final parsed = service.parseBackupJson(raw);
      expect(parsed.items, <DdayItem>[item1]);
      expect(parsed.skippedCount, 1);
    });

    test('applyImport merge updates matching IDs and adds new ones', () {
      final updatedItem1 = item1.copyWith(title: '期末考 (已更新)');
      final result = service.applyImport(
        <DdayItem>[item1],
        <DdayItem>[updatedItem1, item2],
        BackupImportMode.merge,
      );

      expect(result.added, 1);
      expect(result.updated, 1);
      expect(result.total, 2);
      expect(result.items.first.title, '期末考 (已更新)');
      expect(result.items.last, item2);
    });

    test('applyImport overwrite replaces existing items completely', () {
      final result = service.applyImport(
        <DdayItem>[item1],
        <DdayItem>[item2],
        BackupImportMode.overwrite,
      );

      expect(result.items, <DdayItem>[item2]);
      expect(result.total, 1);
    });

    test('exportJson & parseBackupJson preserve repeatYearly', () {
      final repeating = item1.copyWith(repeatYearly: true);
      final raw = service.exportJson(<DdayItem>[repeating]);
      final parsed = service.parseBackupJson(raw);
      expect(parsed.items.single.repeatYearly, isTrue);
    });
  });
}
