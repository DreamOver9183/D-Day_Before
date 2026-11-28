import 'dart:convert';
import 'dart:io';

import 'package:dday_before/data/backup_service.dart';
import 'package:dday_before/data/dday_store.dart';
import 'package:dday_before/models/dday.dart';
import 'package:dday_before/screens/edit_screen.dart';
import 'package:dday_before/screens/home_screen.dart';
import 'package:dday_before/screens/settings_screen.dart';
import 'package:dday_before/services/background_images.dart';
import 'package:dday_before/widgets/dday_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_prefs.dart';
import '../helpers/fakes.dart';

const String photoA = 'bg_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.jpg';
const String photoB = 'bg_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.jpg';
const String photoMissing = 'bg_cccccccccccccccccccccccccccccccc.jpg';

final DateTime _now = DateTime(2026, 11, 25, 10);

DdayItem _item(
  String id,
  String date, {
  String? photo,
  bool pinned = false,
}) =>
    DdayItem(
      id: id,
      title: '項目$id',
      date: date,
      countFromOne: false,
      pinned: pinned,
      createdAt: '2026-11-01T00:00:00.000Z',
      backgroundImage: photo,
    );

String _encode(List<DdayItem> items) => jsonEncode(<String, Object>{
      'schemaVersion': 1,
      'items': items.map((e) => e.toJson()).toList(),
    });

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dday_bg_widget_');
    for (final name in <String>[photoA, photoB]) {
      File('${dir.path}${Platform.pathSeparator}$name')
          .writeAsBytesSync(<int>[0, 1, 2, 3]);
    }
  });

  tearDown(() {
    BackgroundImages.configure(null);
    dir.deleteSync(recursive: true);
  });

  void phoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
  }

  DdayCard cardFor(WidgetTester tester, String id) =>
      tester.widget<DdayCard>(find.byKey(Key('dday_card_$id')));

  group('home list', () {
    testWidgets('items with a photo become photo cards, order is kept',
        (tester) async {
      phoneSize(tester);
      final prefs = FakePrefs(<String, Object>{
        DdayStore.itemsKey: _encode(<DdayItem>[
          _item('1', '2026-11-30'),
          _item('2', '2026-12-05', photo: photoA),
          _item('3', '2026-12-10'),
          _item('4', '2026-12-20', photo: photoMissing),
        ]),
      });
      final bridge = FakeNativeBridge()..backgroundsDir = dir.path;
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            store: DdayStore(prefsProvider: () async => prefs),
            nativeBridge: bridge,
            clock: () => _now,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(cardFor(tester, '2').photo, isNotNull);
      expect(cardFor(tester, '1').photo, isNull);
      expect(cardFor(tester, '3').photo, isNull);
      expect(cardFor(tester, '4').photo, isNull,
          reason: 'missing file (restored on another phone) falls back');

      final order = tester
          .widgetList<DdayCard>(find.byType(DdayCard))
          .map((c) => (c.key! as ValueKey<String>).value)
          .toList();
      expect(order, <String>[
        'dday_card_1',
        'dday_card_2',
        'dday_card_3',
        'dday_card_4',
      ]);

      // Photo cards stay tappable and keep the summary label.
      final semantics = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.byKey(const Key('dday_card_2'))),
        isSemantics(label: '項目2，2026/12/05 (六)，D-10', isButton: true),
      );
      semantics.dispose();

      await tester.tap(find.byKey(const Key('dday_card_2')));
      await tester.pumpAndSettle();
      expect(find.byType(EditScreen), findsOneWidget);
    });

    testWidgets('unused photos are cleaned up after load and after saving',
        (tester) async {
      phoneSize(tester);
      final prefs = FakePrefs(<String, Object>{
        DdayStore.itemsKey: _encode(<DdayItem>[
          _item('1', '2026-12-05', photo: photoA),
          _item('2', '2026-12-10', photo: photoB),
        ]),
      });
      final bridge = FakeNativeBridge()..backgroundsDir = dir.path;
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            store: DdayStore(prefsProvider: () async => prefs),
            nativeBridge: bridge,
            clock: () => _now,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(bridge.cleanupCalls.last, <String>{photoA, photoB});

      // Delete item 2 via the long-press menu.
      await tester.longPress(find.byKey(const Key('dday_card_2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('action_delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '刪除'));
      await tester.pumpAndSettle();

      expect(bridge.cleanupCalls.last, <String>{photoA},
          reason: 'the deleted item\'s photo is no longer kept');
    });
  });

  group('edit screen', () {
    Future<EditResult?> runEditor(
      WidgetTester tester,
      FakeNativeBridge bridge,
      Future<void> Function() interact, {
      DdayItem? item,
    }) async {
      phoneSize(tester);
      BackgroundImages.configure(dir.path);
      EditResult? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    result = await Navigator.of(context).push(
                      MaterialPageRoute<EditResult>(
                        builder: (_) => EditScreen(
                          initialItem: item ?? _item('1', '2026-12-25'),
                          clock: () => _now,
                          nativeBridge: bridge,
                        ),
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await interact();
      await tester.tap(find.byKey(const Key('save_button')));
      await tester.pumpAndSettle();
      return result;
    }

    Future<void> tapVisible(WidgetTester tester, Key key) async {
      final finder = find.byKey(key);
      await tester.scrollUntilVisible(finder, 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    testWidgets('picking a photo updates the preview and is saved',
        (tester) async {
      final bridge = FakeNativeBridge()..nextPickedImage = photoA;
      final result = await runEditor(tester, bridge, () async {
        await tapVisible(tester, const Key('pick_background_button'));
        expect(bridge.pickCalls, 1);
        final preview = tester.widget<DdayCard>(
          find.byWidgetPredicate(
            (w) => w is DdayCard && w.variant == DdayCardVariant.editPreview,
          ),
        );
        expect(preview.photo, isNotNull);
        expect(find.byKey(const Key('change_background_button')), findsOneWidget);
      });
      expect((result! as EditSaveResult).item.backgroundImage, photoA);
    });

    testWidgets('cancelling the picker changes nothing', (tester) async {
      final bridge = FakeNativeBridge()..nextPickedImage = null;
      final result = await runEditor(tester, bridge, () async {
        await tapVisible(tester, const Key('pick_background_button'));
        expect(find.byKey(const Key('pick_background_button')), findsOneWidget);
      });
      expect((result! as EditSaveResult).item.backgroundImage, isNull);
    });

    testWidgets('an unreadable photo shows a message', (tester) async {
      final bridge = FakeNativeBridge()
        ..pickError = PlatformException(code: 'IMAGE_IMPORT_FAILED');
      final result = await runEditor(tester, bridge, () async {
        await tapVisible(tester, const Key('pick_background_button'));
        expect(find.text('無法讀取這張照片，請換一張試試'), findsOneWidget);
      });
      expect((result! as EditSaveResult).item.backgroundImage, isNull);
    });

    testWidgets('removing the photo clears it', (tester) async {
      final bridge = FakeNativeBridge();
      final result = await runEditor(
        tester,
        bridge,
        () async {
          await tapVisible(tester, const Key('remove_background_button'));
          expect(find.byKey(const Key('pick_background_button')), findsOneWidget);
        },
        item: _item('1', '2026-12-25', photo: photoA),
      );
      expect((result! as EditSaveResult).item.backgroundImage, isNull);
    });
  });

  testWidgets('settings widget preview shows the top item photo',
      (tester) async {
    phoneSize(tester);
    BackgroundImages.configure(dir.path);
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          store: DdayStore(prefsProvider: () async => FakePrefs()),
          nativeBridge: FakeNativeBridge(),
          themeMode: ThemeMode.light,
          onThemeModeChanged: (_) async {},
          currentItems: <DdayItem>[_item('1', '2026-12-05', photo: photoA)],
          onSaveItems: (_) async => true,
          backupService: const BackupService(),
          fileChannel: FakeBackupFileChannel(),
          clock: () => _now,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final preview = tester.widget<DdayCard>(
      find.byWidgetPredicate(
        (w) => w is DdayCard && w.variant == DdayCardVariant.widgetPreview,
      ),
    );
    expect(preview.photo, isNotNull);
  });
}
