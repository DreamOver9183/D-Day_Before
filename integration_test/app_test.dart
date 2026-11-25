import 'package:dday_before/data/dday_store.dart';
import 'package:dday_before/main.dart';
import 'package:dday_before/models/dday.dart';
import 'package:dday_before/utils/day_calc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

    // Open zh_TW date picker and advance to next month -> pick day 25
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

    // Edit and save
    await tester.tap(find.text('期末考'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('title_field')), '期末考複習');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save_button')));
    await tester.pumpAndSettle();
    expect(find.text('期末考複習'), findsOneWidget);

    // 8. Verify persisted data in SharedPreferences survives widget rebuild
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

    // 9. Delete one item via long-press dialog and the other via edit screen
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
}
