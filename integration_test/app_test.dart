import 'package:dday_before/data/backup_service.dart';
import 'package:dday_before/data/dday_store.dart';
import 'package:dday_before/main.dart';
import 'package:dday_before/models/dday.dart';
import 'package:dday_before/services/native_bridge.dart';
import 'package:dday_before/utils/day_calc.dart';
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
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('v0.1 E2E: add, validate, sort, pin, edit, persist, delete',
      (WidgetTester tester) async {
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

    // 3. Save a D-Day for today with countFromOne = true -> 第 1 天
    await tester.enterText(find.byKey(const Key('title_field')), '交往紀念日');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('count_from_one_switch')));
    await tester.pumpAndSettle();
    expect(find.text('第 1 天'), findsOneWidget);

    await tester.tap(find.byKey(const Key('save_button')));
    await tester.pumpAndSettle();

    expect(find.text('交往紀念日'), findsOneWidget);
    expect(find.text('第 1 天'), findsOneWidget);

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
    expect(find.byIcon(Icons.push_pin), findsOneWidget);

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
    expect(
      savedItems.any((e) => e.title == '期末考複習' && e.pinned),
      isTrue,
    );
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

  testWidgets('v0.2 E2E: backup export to clipboard, invalid json, merge & overwrite import',
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
    await tester.enterText(find.byKey(const Key('import_json_field')), '{bad');
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
  });

  testWidgets('v0.3 E2E: yearly repeat toggle, anniversary countdown, and backup',
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
    await tester.tap(find.byKey(const Key('repeat_yearly_switch')));
    await tester.pumpAndSettle();
    expect(find.text('D-30'), findsOneWidget);

    await tester.tap(find.byKey(const Key('save_button')));
    await tester.pumpAndSettle();

    expect(find.text('D-30'), findsOneWidget);
    expect(find.textContaining('每年重複・第 6 週年'), findsOneWidget);
    expect(find.byIcon(Icons.repeat), findsOneWidget);

    // Verify stored item has repeatYearly = true and survives backup round-trip
    final saved = await store.loadItems();
    expect(saved.single.repeatYearly, isTrue);
  });

  testWidgets('v0.4 E2E: card color customization and dark/light theme mode',
      (WidgetTester tester) async {
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

  testWidgets('v0.5 E2E: item reminders, settings ongoing toggle, native channel sync',
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
    await tester.tap(chip0);
    await tester.tap(chip3);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('save_button')));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.notifications_active_outlined), findsOneWidget);
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
  });
}
