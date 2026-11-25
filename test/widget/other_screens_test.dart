import 'dart:convert';
import 'dart:io';

import 'package:dday_before/data/backup_service.dart';
import 'package:dday_before/data/dday_store.dart';
import 'package:dday_before/main.dart';
import 'package:dday_before/models/dday.dart';
import 'package:dday_before/screens/backup_screen.dart';
import 'package:dday_before/screens/edit_screen.dart';
import 'package:dday_before/screens/settings_screen.dart';
import 'package:dday_before/widgets/dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_prefs.dart';
import '../helpers/fakes.dart';

final DateTime _now = DateTime(2026, 11, 25, 10);

final DdayItem _exam = DdayItem(
  id: 'a-exam',
  title: '期末考',
  date: '2026-12-25',
  countFromOne: false,
  pinned: true,
  createdAt: '2026-11-01T00:00:00.000Z',
  colorKey: 'rose',
);

void _phoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

void main() {
  group('EditScreen', () {
    Future<void> openEditor(WidgetTester tester, {DdayItem? item}) async {
      _phoneSize(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<EditResult>(
                      builder: (_) =>
                          EditScreen(initialItem: item, clock: () => _now),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('blank title is rejected', (tester) async {
      await openEditor(tester);
      await tester.enterText(find.byKey(const Key('title_field')), '   ');
      await tester.tap(find.byKey(const Key('save_button')));
      await tester.pumpAndSettle();
      expect(find.text('請輸入標題'), findsOneWidget);
      expect(find.byType(EditScreen), findsOneWidget);
    });

    testWidgets('emoji title at the limit saves', (tester) async {
      await openEditor(tester);
      await tester.enterText(find.byKey(const Key('title_field')), '🎂' * 50);
      await tester.tap(find.byKey(const Key('save_button')));
      await tester.pumpAndSettle();
      expect(find.text('標題最多 50 個字'), findsNothing);
      expect(find.byType(EditScreen), findsNothing);
    });

    testWidgets('leaving with unsaved changes asks first', (tester) async {
      await openEditor(tester, item: _exam);
      await tester.enterText(find.byKey(const Key('title_field')), '改過');
      await tester.pump();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('捨棄修改？'), findsOneWidget);
      await tester.tap(find.text('捨棄'));
      await tester.pumpAndSettle();
      expect(find.byType(EditScreen), findsNothing);
    });

    testWidgets('preview keeps its key and a read-only summary',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await openEditor(tester, item: _exam);
      expect(find.byKey(const Key('edit_preview_badge')), findsOneWidget);
      expect(
        tester.getSemantics(find.byKey(const Key('edit_preview_badge'))),
        isSemantics(label: '期末考，2026/12/25 (五)，D-30'),
      );
      semantics.dispose();
    });

    testWidgets('delete uses the shared confirmation dialog', (tester) async {
      await openEditor(tester, item: _exam);
      await tester.tap(find.byKey(const Key('edit_delete_button')));
      await tester.pumpAndSettle();
      expect(find.text('確定要刪除「期末考」嗎？此動作無法復原。'), findsOneWidget);
    });
  });

  group('SettingsScreen', () {
    late FakePrefs prefs;
    late FakeNativeBridge bridge;

    Future<void> pumpSettings(WidgetTester tester) async {
      _phoneSize(tester);
      prefs = FakePrefs();
      bridge = FakeNativeBridge();
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            store: DdayStore(prefsProvider: () async => prefs),
            nativeBridge: bridge,
            themeMode: ThemeMode.light,
            onThemeModeChanged: (_) async {},
            currentItems: <DdayItem>[_exam],
            onSaveItems: (_) async => true,
            backupService: const BackupService(),
            fileChannel: FakeBackupFileChannel(),
            clock: () => _now,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('widget preview keeps its key and is not a button',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpSettings(tester);
      final box = find.byKey(const Key('widget_preview_box'));
      await tester.scrollUntilVisible(box, 200,
          scrollable: find.byType(Scrollable).first);
      final node = tester.getSemantics(box);
      expect(node.label, '期末考，2026/12/25 (五)，D-30，已置頂');
      expect(node.getSemanticsData().flagsCollection.isButton, isFalse);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
      semantics.dispose();
    });

    testWidgets('ongoing switch reverts when saving fails', (tester) async {
      await pumpSettings(tester);
      prefs.rejectKeys.add(DdayStore.ongoingNotificationKey);
      await tester.tap(find.byKey(const Key('ongoing_notification_switch')));
      await tester.pumpAndSettle();

      final tile = tester.widget<SwitchListTile>(
        find.byKey(const Key('ongoing_notification_switch')),
      );
      expect(tile.value, isFalse);
      expect(find.text(storageWriteFailedMessage), findsOneWidget);
      expect(bridge.syncCalls, 0);
    });

    testWidgets('reminder time reverts when saving fails', (tester) async {
      await pumpSettings(tester);
      prefs.rejectKeys.add(DdayStore.reminderTimeKey);
      await tester.tap(find.byKey(const Key('reminder_time_tile')));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.keyboard_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '10');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('09:00'), findsOneWidget);
      expect(find.text('10:00'), findsNothing);
      expect(find.text(storageWriteFailedMessage), findsOneWidget);
    });

    testWidgets('reminder time saves normally', (tester) async {
      await pumpSettings(tester);
      await tester.tap(find.byKey(const Key('reminder_time_tile')));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.keyboard_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '10');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('10:00'), findsOneWidget);
      expect(prefs.data[DdayStore.reminderTimeKey], '10:00');
    });
  });

  group('BackupScreen', () {
    late FakeBackupFileChannel channel;
    late int importCalls;

    Future<void> pumpBackup(
      WidgetTester tester, {
      required Future<bool> Function(List<DdayItem>) onSave,
    }) async {
      _phoneSize(tester);
      importCalls = 0;
      channel = _CountingChannel(() => importCalls++);
      await tester.pumpWidget(
        MaterialApp(
          home: BackupScreen(
            initialItems: <DdayItem>[_exam],
            onSaveItems: onSave,
            fileChannel: channel,
            clock: () => _now,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> tapImportFile(WidgetTester tester) async {
      final button = find.byKey(const Key('import_file_button'));
      await tester.scrollUntilVisible(button, 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    testWidgets('import button works again after an error or cancel',
        (tester) async {
      await pumpBackup(tester, onSave: (_) async => true);

      channel.importError = StateError('no file');
      await tapImportFile(tester);
      expect(find.textContaining('讀取檔案失敗'), findsOneWidget);

      channel.importError = null;
      channel.importResult = null; // user cancelled
      await tapImportFile(tester);

      await tapImportFile(tester);
      expect(importCalls, 3);
    });

    testWidgets('failed save shows no success and keeps the count',
        (tester) async {
      await pumpBackup(tester, onSave: (_) async => false);
      channel.importResult =
          File('test/fixtures/v1_0_0_items.json').readAsStringSync();

      await tapImportFile(tester);
      await tester.tap(find.byKey(const Key('import_mode_merge')));
      await tester.pumpAndSettle();

      expect(find.textContaining('匯入完成'), findsNothing);
      expect(find.text('目前共有 1 筆 D-Day'), findsOneWidget);
    });

    testWidgets('successful import updates the count', (tester) async {
      await pumpBackup(tester, onSave: (_) async => true);
      channel.importResult =
          File('test/fixtures/v1_0_0_items.json').readAsStringSync();

      await tapImportFile(tester);
      await tester.tap(find.byKey(const Key('import_mode_merge')));
      await tester.pumpAndSettle();

      expect(find.textContaining('匯入完成'), findsOneWidget);
      expect(find.text('目前共有 6 筆 D-Day'), findsOneWidget);
    });
  });

  group('DdayApp theme', () {
    testWidgets('theme reverts and warns when saving fails', (tester) async {
      _phoneSize(tester);
      final prefs = FakePrefs(<String, Object>{
        DdayStore.themeModeKey: 'light',
        DdayStore.itemsKey: jsonEncode(<String, Object>{
          'schemaVersion': 1,
          'items': <Object>[_exam.toJson()],
        }),
      })
        ..rejectKeys.add(DdayStore.themeModeKey);

      await tester.pumpWidget(
        DdayApp(
          store: DdayStore(prefsProvider: () async => prefs),
          nativeBridge: FakeNativeBridge(),
          clock: () => _now,
        ),
      );
      await tester.pumpAndSettle();
      ThemeMode current() =>
          tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode!;
      expect(current(), ThemeMode.light);

      await tester.tap(find.byKey(const Key('theme_menu_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('theme_option_dark')));
      await tester.pumpAndSettle();

      expect(current(), ThemeMode.light);
      expect(find.text(storageWriteFailedMessage), findsOneWidget);
      expect(prefs.data[DdayStore.themeModeKey], 'light');
    });
  });
}

class _CountingChannel extends FakeBackupFileChannel {
  _CountingChannel(this.onImport);

  final void Function() onImport;

  @override
  Future<String?> importJsonFile() {
    onImport();
    return super.importJsonFile();
  }
}
