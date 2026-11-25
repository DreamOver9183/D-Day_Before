import 'dart:convert';
import 'dart:io';

import 'package:dday_before/data/backup_service.dart';
import 'package:dday_before/models/dday.dart';
import 'package:dday_before/services/background_images.dart';
import 'package:flutter_test/flutter_test.dart';

const String validName = 'bg_0123456789abcdef0123456789abcdef.jpg';

void main() {
  tearDown(() => BackgroundImages.configure(null));

  group('BackgroundImages names', () {
    test('accept only managed file names', () {
      expect(BackgroundImages.isValidName(validName), isTrue);
      for (final bad in <String>[
        '',
        'bg_0123.jpg',
        '../$validName',
        '/data/data/x/$validName',
        validName.toUpperCase(),
        '$validName.tmp',
        r'..\bg_0123456789abcdef0123456789abcdef.jpg',
      ]) {
        expect(BackgroundImages.isValidName(bad), isFalse, reason: bad);
      }
      expect(BackgroundImages.normalizeName(42), isNull);
      expect(BackgroundImages.normalizeName(null), isNull);
    });

    test('fileFor resolves only existing files inside the folder', () {
      final dir = Directory.systemTemp.createTempSync('dday_bg_');
      addTearDown(() => dir.deleteSync(recursive: true));

      expect(BackgroundImages.fileFor(validName), isNull,
          reason: 'folder not configured yet');
      BackgroundImages.configure(dir.path);
      expect(BackgroundImages.fileFor(validName), isNull,
          reason: 'file missing (e.g. restored on another phone)');

      File('${dir.path}${Platform.pathSeparator}$validName')
          .writeAsBytesSync(<int>[1, 2, 3]);
      expect(BackgroundImages.fileFor(validName), isNotNull);
      expect(BackgroundImages.fileFor('../$validName'), isNull);
      expect(BackgroundImages.fileFor(null), isNull);
    });
  });

  group('DdayItem.backgroundImage', () {
    test('round-trips through JSON and backups', () {
      final item = DdayItem.create(
        id: 'p1',
        title: '交往紀念日',
        date: '2025-11-26',
        backgroundImage: validName,
      );
      expect(item.toJson()['backgroundImage'], validName);
      expect(DdayItem.tryFromJson(jsonDecode(jsonEncode(item.toJson()))), item);

      const service = BackupService();
      final restored = service.parseBackupJson(
        service.exportJson(<DdayItem>[item]),
      );
      expect(restored.items.single.backgroundImage, validName);
    });

    test('invalid names from stored data or backups are dropped', () {
      final raw = <String, Object>{
        'id': 'p2',
        'title': 'X',
        'date': '2026-12-25',
        'backgroundImage': '../../shared_prefs/FlutterSharedPreferences.xml',
      };
      final item = DdayItem.tryFromJson(raw)!;
      expect(item.backgroundImage, isNull);
      expect(item.toJson().containsKey('backgroundImage'), isFalse);
    });

    test('copyWith can set, keep and clear the photo', () {
      final item = DdayItem.create(id: 'p3', title: 'X', date: '2026-12-25');
      final withPhoto = item.copyWith(backgroundImage: validName);
      expect(withPhoto.backgroundImage, validName);
      expect(withPhoto.copyWith(title: 'Y').backgroundImage, validName);
      expect(withPhoto.copyWith(backgroundImage: null).backgroundImage, isNull);
      expect(withPhoto == item, isFalse);
    });
  });
}
