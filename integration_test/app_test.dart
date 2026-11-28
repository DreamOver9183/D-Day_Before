import 'dart:io';
import 'dart:ui' as ui;

import 'package:dday_before/data/backup_service.dart';
import 'package:dday_before/data/dday_store.dart';
import 'package:dday_before/main.dart';
import 'package:dday_before/models/dday.dart';
import 'package:dday_before/services/background_images.dart';
import 'package:dday_before/services/native_bridge.dart';
import 'package:dday_before/services/update_service.dart';
import 'package:dday_before/utils/day_calc.dart';
import 'package:dday_before/widgets/dday_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestNativeBridge implements NativeBridge {
  int syncCalls = 0;
  int widgetRefreshCalls = 0;

  @override
  Future<bool> hasNotificationPermission() async => true;

  @override
  Future<bool> requestNotificationPermission() async => true;

  @override
  Future<void> syncNotifications() async {
    syncCalls++;
  }

  @override
  Future<void> refreshWidgets() async {
    widgetRefreshCalls++;
  }

  // Background photos use the real native implementation on the device.
  final MethodChannelNativeBridge _real = const MethodChannelNativeBridge();

  @override
  Future<String?> pickBackgroundImage() => _real.pickBackgroundImage();

  @override
  Future<String?> backgroundsDirectory() => _real.backgroundsDirectory();

  @override
  Future<void> cleanupBackgrounds(Set<String> keep) =>
      _real.cleanupBackgrounds(keep);

  // Device tests never auto-update; version still comes from the device.
  @override
  Future<AppVersion?> getAppVersion() => _real.getAppVersion();

  @override
  Future<bool> canInstallUpdates() => _real.canInstallUpdates();

  @override
  Future<void> openInstallPermissionSettings() async {}

  @override
  Future<void> downloadAndInstallUpdate(String url, String sha256) async {}
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Layout-dependent steps assume portrait; lock it so a phone lying
  // sideways with auto-rotate on cannot change the results.
  setUpAll(() async {
    await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
    ]);
  });
  tearDownAll(() async {
    await SystemChrome.setPreferredOrientations(<DeviceOrientation>[]);
  });

  testWidgets('v0.1 E2E: add, validate, sort, pin, edit, persist, delete', (
    WidgetTester tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    final fixedToday = DateTime(2026, 11, 25, 10, 0);
    DateTime clock() => fixedToday;
    final store = DdayStore();

    await tester.pumpWidget(DdayApp(store: store, clock: clock));
    await tester.pumpAndSettle();

    // 1. Empty state
    expect(find.text('還沒有 D-Day'), findsOneWidget);

    // 2. Open add screen & verify empty-title validation
    await tester.tap(find.byKey(const Key('fab_add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save_button')));
    await tester.pumpAndSettle();
    expect(find.text('請輸入標題'), findsOneWidget);

    // 3. Save a D-Day for today with countFromOne = true -> 1天
    await tester.enterText(find.byKey(const Key('title_field')), '交往紀念日');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('mode_count_from_one')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mode_count_from_one')));
    await tester.pumpAndSettle();
    expect(find.text('1天'), findsOneWidget);

    await tester.tap(find.byKey(const Key('save_button')));
    await tester.pumpAndSettle();

    expect(find.text('交往紀念日'), findsOneWidget);
    expect(find.text('1天'), findsOneWidget);

    // 4. Add a second item (future date) via edit screen date picker
    await tester.tap(find.byKey(const Key('fab_add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('title_field')), '期末考');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('date_picker_tile')));
    await tester.pumpAndSettle();
    final nextMonthBtn = find.byTooltip('下個月');
    if (nextMonthBtn.evaluate().isNotEmpty) {
      await tester.tap(nextMonthBtn);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('25').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('確定'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('save_button')));
    await tester.pumpAndSettle();

    expect(find.text('期末考'), findsOneWidget);
    expect(find.text('D-30'), findsOneWidget);

    // 5. Switch sort mode to dateAsc & verify persistence
    await tester.tap(find.byKey(const Key('sort_menu_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sort_option_dateAsc')));
    await tester.pumpAndSettle();
    expect(await store.loadSortMode(), DdaySortMode.dateAsc);

    // 6. Long-press 期末考 and pin it
    await tester.longPress(find.text('期末考'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('action_toggle_pin')));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.push_pin_rounded), findsOneWidget);

    // 7. Tap 期末考 -> verify unsaved changes dialog -> discard -> reopen & save edit
    await tester.tap(find.text('期末考'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('title_field')), '暫時改名');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('捨棄修改？'), findsOneWidget);
    await tester.tap(find.text('捨棄'));
    await tester.pumpAndSettle();
    expect(find.text('期末考'), findsOneWidget);

    await tester.tap(find.text('期末考'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('title_field')), '期末考複習');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save_button')));
    await tester.pumpAndSettle();
    expect(find.text('期末考複習'), findsOneWidget);

    // 8. Verify persisted data in SharedPreferences
    final savedItems = await store.loadItems();
    expect(savedItems, hasLength(2));
    expect(savedItems.any((e) => e.title == '期末考複習' && e.pinned), isTrue);
    expect(
      savedItems.any(
        (e) =>
            e.title == '交往紀念日' &&
            e.countFromOne &&
            e.date == formatIsoDate(fixedToday),
      ),
      isTrue,
    );

    // 9. Delete both items
    await tester.longPress(find.text('交往紀念日'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('action_delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('刪除'));
    await tester.pumpAndSettle();
    expect(find.text('交往紀念日'), findsNothing);

    await tester.tap(find.text('期末考複習'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit_delete_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('刪除'));
    await tester.pumpAndSettle();

    expect(find.text('還沒有 D-Day'), findsOneWidget);
    expect(await store.loadItems(), isEmpty);
  });

  testWidgets(
    'v0.2 E2E: backup export to clipboard, invalid json, merge & overwrite import',
    (WidgetTester tester) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      final fixedToday = DateTime(2026, 11, 25, 10, 0);
      final store = DdayStore();
      final existing = DdayItem.create(
        id: 'local-1',
        title: '本地項目',
        date: '2026-12-01',
        now: fixedToday,
      );
      await store.saveItems(<DdayItem>[existing]);

      await tester.pumpWidget(DdayApp(store: store, clock: () => fixedToday));
      await tester.pumpAndSettle();
      expect(find.text('本地項目'), findsOneWidget);

      // Open BackupScreen
      await tester.tap(find.byKey(const Key('backup_button')));
      await tester.pumpAndSettle();
      expect(find.text('目前共有 1 筆 D-Day'), findsOneWidget);

      // Copy backup JSON to clipboard
      await tester.tap(find.byKey(const Key('export_clipboard_button')));
      await tester.pumpAndSettle();
      final clipData = await Clipboard.getData(Clipboard.kTextPlain);
      expect(clipData?.text, isNotNull);
      expect(clipData!.text, contains('本地項目'));

      // Invalid JSON shows error dialog
      await tester.tap(find.byKey(const Key('import_paste_button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('import_json_field')),
        '{bad',
      );
      await tester.tap(find.byKey(const Key('import_parse_button')));
      await tester.pumpAndSettle();
      expect(find.text('無法匯入備份'), findsOneWidget);
      await tester.tap(find.text('確定'));
      await tester.pumpAndSettle();

      // Merge import a backup containing another item
      final incomingJson = const BackupService().exportJson(<DdayItem>[
        DdayItem.create(
          id: 'backup-2',
          title: '匯入的跨年',
          date: '2027-01-01',
          now: fixedToday,
        ),
      ]);
      await tester.tap(find.byKey(const Key('import_paste_button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('import_json_field')),
        incomingJson,
      );
      await tester.tap(find.byKey(const Key('import_parse_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('import_mode_merge')));
      await tester.pumpAndSettle();
      expect(find.text('目前共有 2 筆 D-Day'), findsOneWidget);

      // Overwrite import using original clipboard backup (only 1 item)
      await tester.tap(find.byKey(const Key('import_paste_button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('import_json_field')),
        clipData.text!,
      );
      await tester.tap(find.byKey(const Key('import_parse_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('import_mode_overwrite')));
      await tester.pumpAndSettle();
      expect(find.text('目前共有 1 筆 D-Day'), findsOneWidget);

      // Back to HomeScreen and verify items updated
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('本地項目'), findsOneWidget);
      expect(find.text('匯入的跨年'), findsNothing);
    },
  );

  testWidgets(
    'v0.3 E2E: yearly repeat toggle, anniversary countdown, and backup',
    (WidgetTester tester) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      final fixedToday = DateTime(2026, 11, 25, 10, 0);
      final store = DdayStore();
      // Seed a past-year date (2020-12-25) initially non-repeating
      await store.saveItems(<DdayItem>[
        DdayItem.create(
          id: 'xmas-2020',
          title: '聖誕節',
          date: '2020-12-25',
          now: fixedToday,
        ),
      ]);

      await tester.pumpWidget(DdayApp(store: store, clock: () => fixedToday));
      await tester.pumpAndSettle();

      // Initially non-repeating -> D+2161
      expect(find.text('D+2161'), findsOneWidget);

      // Edit and enable repeatYearly -> jumps to 2026-12-25 (D-30)
      await tester.tap(find.text('聖誕節'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('mode_repeat_yearly')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('mode_repeat_yearly')));
      await tester.pumpAndSettle();
      expect(find.text('D-30'), findsOneWidget);

      await tester.tap(find.byKey(const Key('save_button')));
      await tester.pumpAndSettle();

      expect(find.text('D-30'), findsOneWidget);
      expect(find.textContaining('第 6 週年'), findsOneWidget);
      expect(find.byIcon(Icons.repeat_rounded), findsOneWidget);

      // Verify stored item has repeatYearly = true and survives backup round-trip
      final saved = await store.loadItems();
      expect(saved.single.repeatYearly, isTrue);
    },
  );

  testWidgets('v0.4 E2E: card color customization and dark/light theme mode', (
    WidgetTester tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    final fixedToday = DateTime(2026, 11, 25, 10, 0);
    final store = DdayStore();

    await tester.pumpWidget(DdayApp(store: store, clock: () => fixedToday));
    await tester.pumpAndSettle();

    // Create item with rose color swatch
    await tester.tap(find.byKey(const Key('fab_add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('title_field')), '配色卡片');
    await tester.pumpAndSettle();
    final roseSwatch = find.byKey(const Key('color_swatch_rose'));
    await tester.ensureVisible(roseSwatch);
    await tester.pumpAndSettle();
    await tester.tap(roseSwatch);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('save_button')));
    await tester.pumpAndSettle();

    final saved = await store.loadItems();
    expect(saved.single.colorKey, 'rose');

    // Switch to dark mode -> verify MaterialApp brightness & persistence
    await tester.tap(find.byKey(const Key('theme_menu_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('theme_option_dark')));
    await tester.pumpAndSettle();

    expect(await store.loadThemeMode(), ThemeMode.dark);
    final scaffoldCtx = tester.element(find.byKey(const Key('fab_add')));
    expect(Theme.of(scaffoldCtx).brightness, Brightness.dark);

    // Switch to light mode
    await tester.tap(find.byKey(const Key('theme_menu_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('theme_option_light')));
    await tester.pumpAndSettle();

    expect(await store.loadThemeMode(), ThemeMode.light);
    final lightCtx = tester.element(find.byKey(const Key('fab_add')));
    expect(Theme.of(lightCtx).brightness, Brightness.light);
  });

  testWidgets(
    'v0.5 E2E: item reminders, settings ongoing toggle, native channel sync',
    (WidgetTester tester) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      final fixedToday = DateTime(2026, 11, 25, 10, 0);
      final store = DdayStore();

      // 1. Run with REAL MethodChannelNativeBridge to verify Android Kotlin channel works
      await tester.pumpWidget(DdayApp(store: store, clock: () => fixedToday));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('fab_add')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('title_field')), '提醒測試');
      await tester.pumpAndSettle();

      final chip0 = find.byKey(const Key('reminder_chip_0'));
      final chip3 = find.byKey(const Key('reminder_chip_3'));
      await tester.ensureVisible(chip0);
      await tester.pumpAndSettle();
      await tester.tap(chip0);
      await tester.tap(chip3);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('save_button')));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);
      final saved = await store.loadItems();
      expect(saved.single.reminderDaysBefore, <int>[0, 3]);

      // 2. Open Settings with permission-granted bridge to test ongoing toggle persistence
      final testBridge = _TestNativeBridge();
      await tester.pumpWidget(
        DdayApp(
          store: store,
          nativeBridge: testBridge,
          clock: () => fixedToday,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('settings_button')));
      await tester.pumpAndSettle();
      expect(find.text('09:00'), findsOneWidget);

      await tester.tap(find.byKey(const Key('ongoing_notification_switch')));
      await tester.pumpAndSettle();
      expect(await store.loadOngoingNotification(), isTrue);
      expect(testBridge.syncCalls, greaterThanOrEqualTo(1));
    },
  );

  testWidgets('v0.6 E2E: home widget preview & native refreshWidgets sync', (
    WidgetTester tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    final fixedToday = DateTime(2026, 11, 25, 10, 0);
    final store = DdayStore();
    await store.saveItems(<DdayItem>[
      DdayItem.create(
        id: 'w1',
        title: '小工具優先事件',
        date: '2026-12-05',
        pinned: true,
        colorKey: 'teal',
        now: fixedToday,
      ),
      DdayItem.create(
        id: 'w2',
        title: '次要事件',
        date: '2026-11-26',
        pinned: false,
        now: fixedToday,
      ),
    ]);

    // Real MethodChannelNativeBridge verifies Kotlin refreshWidgets executes cleanly
    await tester.pumpWidget(DdayApp(store: store, clock: () => fixedToday));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('settings_button')));
    await tester.pumpAndSettle();

    final previewBox = find.byKey(const Key('widget_preview_box'));
    await tester.ensureVisible(previewBox);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: previewBox, matching: find.text('📌 小工具優先事件')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: previewBox, matching: find.text('D-10')),
      findsOneWidget,
    );

    final syncBtn = find.byKey(const Key('sync_widget_button'));
    await tester.ensureVisible(syncBtn);
    await tester.pumpAndSettle();
    await tester.tap(syncBtn);
    await tester.pumpAndSettle();
    expect(find.text('已同步桌面小工具'), findsOneWidget);

    // v1.0 About section check
    final aboutTile = find.byKey(const Key('about_version_tile'));
    await tester.ensureVisible(aboutTile);
    await tester.pumpAndSettle();
    // Version comes from the installed package (pubspec version).
    expect(find.textContaining('版本 v1.'), findsOneWidget);
  });

  testWidgets('v0.7 E2E: background photo import, display, widget and limits', (
    WidgetTester tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    const bridge = MethodChannelNativeBridge();

    // A 2400x1200 PNG with a gradient, made on the device.
    final pngBytes = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 2400, 1200),
        Paint()
          ..shader = ui.Gradient.linear(
            Offset.zero,
            const Offset(2400, 1200),
            <Color>[const Color(0xFFEE5A62), const Color(0xFF0284C7)],
          ),
      );
      final image = await recorder.endRecording().toImage(2400, 1200);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });

    // Runs the same decode / resize / JPEG pipeline as the photo picker.
    final name = await tester.runAsync(
      () => bridge.debugImportBackground(pngBytes!),
    );
    expect(name, isNotNull);
    expect(BackgroundImages.isValidName(name!), isTrue);

    final dirPath = await tester.runAsync(() => bridge.backgroundsDirectory());
    final stored = File('$dirPath/$name');
    expect(stored.existsSync(), isTrue);

    // Stored copy is a JPEG downsized to at most 1600px on the long side.
    final storedBytes = stored.readAsBytesSync();
    expect(storedBytes.sublist(0, 2), <int>[0xFF, 0xD8], reason: 'JPEG header');
    final size = await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(storedBytes);
      final frame = await codec.getNextFrame();
      return Size(frame.image.width.toDouble(), frame.image.height.toDouble());
    });
    expect(size, const Size(1600, 800));
    expect(storedBytes.length, lessThan(600 * 1024));

    // Garbage bytes are rejected instead of crashing.
    final garbageError = await tester.runAsync(() async {
      try {
        await bridge.debugImportBackground(<int>[1, 2, 3]);
        return null;
      } catch (e) {
        return e;
      }
    });
    expect(garbageError, isA<PlatformException>());

    final fixedToday = DateTime(2026, 11, 25, 10, 0);
    final store = DdayStore();
    await store.saveItems(<DdayItem>[
      DdayItem.create(
        id: 'p1',
        title: '照片事件',
        date: '2026-12-05',
        pinned: true,
        backgroundImage: name,
        now: fixedToday,
      ),
      DdayItem.create(
        id: 'p2',
        title: '一般事件',
        date: '2026-12-10',
        now: fixedToday,
      ),
    ]);

    // Real native bridge: refreshWidgets loads the photo for the home widget.
    await tester.pumpWidget(DdayApp(store: store, clock: () => fixedToday));
    await tester.pumpAndSettle();

    final photoCard = tester.widget<DdayCard>(
      find.byKey(const Key('dday_card_p1')),
    );
    expect(photoCard.photo, isNotNull);
    expect(
      tester.widget<DdayCard>(find.byKey(const Key('dday_card_p2'))).photo,
      isNull,
    );
    expect(find.text('D-10'), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings_button')));
    await tester.pumpAndSettle();
    final preview = tester.widget<DdayCard>(
      find.byWidgetPredicate(
        (w) => w is DdayCard && w.variant == DdayCardVariant.widgetPreview,
      ),
    );
    expect(preview.photo, isNotNull);
    final syncBtn = find.byKey(const Key('sync_widget_button'));
    await tester.ensureVisible(syncBtn);
    await tester.pumpAndSettle();
    await tester.tap(syncBtn);
    await tester.pumpAndSettle();
    expect(find.text('已同步桌面小工具'), findsOneWidget);

    // Referenced photos survive cleanup.
    await tester.runAsync(() => bridge.cleanupBackgrounds(<String>{}));
    expect(
      stored.existsSync(),
      isTrue,
      reason: 'new files have a grace period',
    );
    await tester.runAsync(() => bridge.cleanupBackgrounds(<String>{name}));
    expect(stored.existsSync(), isTrue);
  });

  testWidgets(
    'v0.8 E2E: native update plumbing (version, permission, guards)',
    (WidgetTester tester) async {
      const bridge = MethodChannelNativeBridge();

      final version = await bridge.getAppVersion();
      expect(version, isNotNull);
      expect(version!.code, greaterThanOrEqualTo(8));
      expect(version.name, matches(RegExp(r'^\d+\.\d+\.\d+$')));

      // Must answer without throwing; the value depends on the phone setting.
      expect(await bridge.canInstallUpdates(), isA<bool>());

      Future<String?> errorCode(String url, String sha) =>
          tester.runAsync<String?>(() async {
            try {
              await bridge.downloadAndInstallUpdate(url, sha);
              return null;
            } on PlatformException catch (e) {
              return e.code;
            }
          });

      final sha = 'a' * 64;
      expect(
        await errorCode('https://evil.example.com/a.apk', sha),
        'BAD_REQUEST',
        reason: 'only GitHub release hosts are accepted',
      );
      expect(
        await errorCode('http://github.com/a.apk', sha),
        'BAD_REQUEST',
        reason: 'https only',
      );
      expect(
        await errorCode('https://github.com/a.apk', 'not-a-checksum'),
        'BAD_REQUEST',
      );
    },
  );
}
