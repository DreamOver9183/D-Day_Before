import 'dart:convert';
import 'dart:io';

import 'package:dday_before/data/dday_store.dart';
import 'package:dday_before/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fakes.dart';

/// Golden baselines generated from v1.0.0 before the UI refactor. The refactor
/// must keep these pixel-identical (same machine, same Flutter version).
void main() {
  // Drop the deliberately malformed entry: v1.0.0 skipped it silently, so the
  // baseline is unaffected, while the new build would show a recovery banner
  // (covered by widget tests) that is not what these goldens check.
  final decoded = jsonDecode(
    File('test/fixtures/v1_0_0_items.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  decoded['items'] = (decoded['items'] as List)
      .where((e) => (e as Map)['id'] != 'g-bad')
      .toList();
  final fixture = jsonEncode(decoded);

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues(<String, Object>{
      DdayStore.itemsKey: fixture,
      DdayStore.themeModeKey: 'light',
    });
    await tester.pumpWidget(
      DdayApp(
        store: DdayStore(),
        nativeBridge: FakeNativeBridge(),
        clock: () => DateTime(2026, 11, 25, 10),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tearDownApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
  }

  testWidgets('home list', (tester) async {
    await pumpApp(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/home_list.png'),
    );
    await tearDownApp(tester);
  });

  testWidgets('edit screen with existing item', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const Key('dday_card_a-exam')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/edit_screen.png'),
    );
    await tearDownApp(tester);
  });

  testWidgets('settings widget preview', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const Key('settings_button')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('widget_preview_box')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const Key('widget_preview_box')),
      matchesGoldenFile('goldens/settings_widget_preview.png'),
    );
    await tearDownApp(tester);
  });
}
