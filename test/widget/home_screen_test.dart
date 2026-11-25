import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dday_before/data/dday_store.dart';
import 'package:dday_before/models/dday.dart';
import 'package:dday_before/screens/home_screen.dart';
import 'package:dday_before/widgets/dday_card.dart';
import 'package:dday_before/widgets/dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_prefs.dart';
import '../helpers/fakes.dart';

final String _fixtureRaw =
    File('test/fixtures/v1_0_0_items.json').readAsStringSync();

/// Fixture without the deliberately malformed entry.
String _cleanFixture() {
  final decoded = jsonDecode(_fixtureRaw) as Map<String, dynamic>;
  decoded['items'] = (decoded['items'] as List)
      .where((e) => (e as Map)['id'] != 'g-bad')
      .toList();
  return jsonEncode(decoded);
}

class _Harness {
  _Harness({Map<String, Object>? data})
      : prefs = FakePrefs(data ?? <String, Object>{DdayStore.itemsKey: _cleanFixture()}),
        bridge = FakeNativeBridge(),
        clock = TestClock(DateTime(2026, 11, 25, 10));

  final FakePrefs prefs;
  final FakeNativeBridge bridge;
  final TestClock clock;
  late final DdayStore store = DdayStore(prefsProvider: () async => prefs);

  Widget app({
    Key? key,
    ThemeMode themeMode = ThemeMode.light,
    double textScale = 1.0,
  }) {
    return MaterialApp(
      key: key,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: HomeScreen(
        store: store,
        nativeBridge: bridge,
        clock: clock.call,
        themeMode: themeMode,
      ),
    );
  }

  Future<void> pump(WidgetTester tester, {Key? key, double textScale = 1.0}) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(key: key, textScale: textScale));
    await tester.pumpAndSettle();
  }

  List<String> storedIds() {
    final raw = prefs.data[DdayStore.itemsKey] as String;
    final items = (jsonDecode(raw) as Map)['items'] as List;
    return items.map((e) => (e as Map)['id'] as String).toList();
  }
}

List<String> _visibleOrder(WidgetTester tester) {
  return tester
      .widgetList<DdayCard>(find.byType(DdayCard))
      .map((card) => (card.key! as ValueKey<String>).value.replaceFirst('dday_card_', ''))
      .toList();
}

Future<void> _longPressAction(
  WidgetTester tester,
  String id,
  String actionKey,
) async {
  await tester.longPress(find.byKey(Key('dday_card_$id')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key(actionKey)));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    HomeScreen.debugViewModelBuildCount = 0;
  });

  group('rendering', () {
    testWidgets('empty state', (tester) async {
      final h = _Harness(data: <String, Object>{});
      await h.pump(tester);
      expect(find.text('還沒有 D-Day'), findsOneWidget);
      expect(find.byType(DdayCard), findsNothing);
    });

    testWidgets('cards keep their keys and nearest order', (tester) async {
      final h = _Harness();
      await h.pump(tester);
      final expected = <String>[
        'e-today',
        'a-exam',
        'f-trip',
        'c-birthday',
        'd-move',
        'b-couple',
      ];
      expect(_visibleOrder(tester), expected);
      for (final id in expected) {
        expect(find.byKey(Key('dday_card_$id')), findsOneWidget);
      }
      expect(find.text('D-30'), findsOneWidget);
      expect(find.text('365天'), findsOneWidget);
    });

    testWidgets('cards expose one summary label and a long-press hint',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final h = _Harness();
      await h.pump(tester);

      final node = tester.getSemantics(find.byKey(const Key('dday_card_a-exam')));
      expect(
        node,
        isSemantics(
          label: '期末考，2026/12/25 (五)，D-30，已置頂',
          isButton: true,
          hasTapAction: true,
          hasLongPressAction: true,
        ),
      );
      final hintId = CustomSemanticsAction.getIdentifier(
        const CustomSemanticsAction.overridingAction(
          hint: DdayCard.longPressHint,
          action: SemanticsAction.longPress,
        ),
      );
      expect(node.getSemanticsData().customSemanticsActionIds, contains(hintId));
      semantics.dispose();
    });

    testWidgets('large text scales the badge instead of overflowing',
        (tester) async {
      final h = _Harness();
      await h.pump(tester, textScale: 2.0);
      expect(tester.takeException(), isNull);
      expect(find.byType(DdayCard), findsWidgets);
    });

    testWidgets('changing sort mode reorders and persists', (tester) async {
      final h = _Harness();
      await h.pump(tester);
      await tester.tap(find.byKey(const Key('sort_menu_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sort_option_dateAsc')));
      await tester.pumpAndSettle();
      expect(_visibleOrder(tester), <String>[
        'e-today',
        'a-exam',
        'b-couple',
        'd-move',
        'f-trip',
        'c-birthday',
      ]);
      expect(h.prefs.data[DdayStore.sortModeKey], 'dateAsc');
    });

    testWidgets('unrelated rebuilds reuse the sorted cache', (tester) async {
      final h = _Harness();
      await h.pump(tester);
      final before = HomeScreen.debugViewModelBuildCount;
      expect(before, greaterThan(0));

      await tester.pumpWidget(h.app(themeMode: ThemeMode.dark));
      await tester.pumpAndSettle();
      showAppSnackBar(
        tester.element(find.byType(HomeScreen)),
        'hello',
      );
      await tester.pumpAndSettle();
      expect(HomeScreen.debugViewModelBuildCount, before);
    });
  });

  group('native sync', () {
    testWidgets('runs after startup and on resume', (tester) async {
      final h = _Harness();
      await h.pump(tester);
      expect(h.bridge.syncCalls, 1);
      expect(h.bridge.widgetRefreshCalls, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(h.bridge.syncCalls, 2);
      expect(h.bridge.widgetRefreshCalls, 2);
    });

    testWidgets('native errors never reach the UI', (tester) async {
      final h = _Harness();
      h.bridge.throwOnSync = true;
      await h.pump(tester);
      expect(tester.takeException(), isNull);
      expect(h.bridge.widgetRefreshCalls, 1,
          reason: 'widget refresh still runs when notification sync fails');
      expect(find.byType(DdayCard), findsNWidgets(6));
    });

    testWidgets('overlapping requests collapse into one extra run',
        (tester) async {
      final h = _Harness();
      final gate = Completer<void>();
      h.bridge.syncGate = gate;
      await h.pump(tester);
      expect(h.bridge.syncCalls, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(h.bridge.syncCalls, 1, reason: 'still waiting on the first run');

      h.bridge.syncGate = null;
      gate.complete();
      await tester.pumpAndSettle();
      expect(h.bridge.syncCalls, 2);
    });

    testWidgets('midnight timer refreshes badges and syncs', (tester) async {
      final h = _Harness();
      await h.pump(tester);
      expect(find.text('D-30'), findsOneWidget);
      final syncsBefore = h.bridge.syncCalls;

      h.clock.now = DateTime(2026, 11, 26, 0, 0, 2);
      await tester.pump(const Duration(hours: 14, seconds: 2));
      await tester.pumpAndSettle();

      expect(find.text('D-29'), findsOneWidget);
      expect(h.bridge.syncCalls, syncsBefore + 1);
    });

    testWidgets('resume on a new day refreshes badges and order',
        (tester) async {
      final h = _Harness();
      await h.pump(tester);
      expect(_visibleOrder(tester).first, 'e-today');

      // Two days later, without the timer firing (e.g. device asleep).
      h.clock.now = DateTime(2026, 11, 27, 9);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.text('D-28'), findsOneWidget);
      expect(find.text('D+2'), findsOneWidget, reason: 'e-today is now past');
      expect(_visibleOrder(tester).take(2), <String>['a-exam', 'e-today']);
    });
  });

  group('write failures', () {
    testWidgets('a failed delete restores the list with one SnackBar',
        (tester) async {
      final h = _Harness();
      await h.pump(tester);
      h.prefs.rejectKeys.add(DdayStore.itemsKey);

      await _longPressAction(tester, 'd-move', 'action_delete');
      expect(find.text('刪除 D-Day'), findsOneWidget, reason: 'shared dialog');
      await tester.tap(find.widgetWithText(FilledButton, '刪除'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('dday_card_d-move')), findsOneWidget);
      expect(find.text(storageWriteFailedMessage), findsOneWidget);
      expect(h.storedIds(), contains('d-move'));
    });

    testWidgets('success then failure keeps the first change',
        (tester) async {
      final h = _Harness();
      await h.pump(tester);
      final syncsBefore = h.bridge.syncCalls;

      final gates = <Completer<void>>[];
      h.prefs.beforeWrite = (key) {
        if (key != DdayStore.itemsKey) return Future<void>.value();
        final gate = Completer<void>();
        gates.add(gate);
        return gate.future;
      };

      await _longPressAction(tester, 'f-trip', 'action_toggle_pin');
      await _longPressAction(tester, 'd-move', 'action_toggle_pin');
      expect(gates, hasLength(1), reason: 'second write waits for the first');

      gates[0].complete();
      await tester.pumpAndSettle();
      expect(gates, hasLength(2));
      h.prefs.rejectKeys.add(DdayStore.itemsKey);
      gates[1].complete();
      await tester.pumpAndSettle();

      final pinned = tester
          .widgetList<DdayCard>(find.byType(DdayCard))
          .where((c) => c.pinned)
          .map((c) => (c.key! as ValueKey<String>).value)
          .toSet();
      expect(pinned, <String>{
        'dday_card_a-exam',
        'dday_card_e-today',
        'dday_card_f-trip',
      });
      expect(find.text(storageWriteFailedMessage), findsOneWidget);
      expect(h.bridge.syncCalls, syncsBefore + 1,
          reason: 'only the successful write syncs');
    });

    testWidgets('two failures fall back to the original list',
        (tester) async {
      final h = _Harness();
      await h.pump(tester);
      final gates = <Completer<void>>[];
      h.prefs.beforeWrite = (key) {
        if (key != DdayStore.itemsKey) return Future<void>.value();
        final gate = Completer<void>();
        gates.add(gate);
        return gate.future;
      };
      h.prefs.rejectKeys.add(DdayStore.itemsKey);

      await _longPressAction(tester, 'f-trip', 'action_toggle_pin');
      await _longPressAction(tester, 'd-move', 'action_toggle_pin');
      gates[0].complete();
      await tester.pumpAndSettle();
      gates[1].complete();
      await tester.pumpAndSettle();

      final pinned = tester
          .widgetList<DdayCard>(find.byType(DdayCard))
          .where((c) => c.pinned)
          .length;
      expect(pinned, 2);
      expect(find.text(storageWriteFailedMessage), findsOneWidget);
    });

    testWidgets('a failed sort change reverts the sort mode', (tester) async {
      final h = _Harness();
      await h.pump(tester);
      final before = _visibleOrder(tester);
      h.prefs.rejectKeys.add(DdayStore.sortModeKey);

      await tester.tap(find.byKey(const Key('sort_menu_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sort_option_createdDesc')));
      await tester.pumpAndSettle();

      expect(_visibleOrder(tester), before);
      expect(find.text(storageWriteFailedMessage), findsOneWidget);
    });
  });

  group('recovery banner', () {
    testWidgets('shows for damaged data, copies, and clears for good',
        (tester) async {
      final h = _Harness(data: <String, Object>{DdayStore.itemsKey: _fixtureRaw});
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      await h.pump(tester);
      expect(find.byKey(const Key('recovery_banner')), findsOneWidget);
      expect(find.byType(DdayCard), findsNWidgets(6));
      expect(h.prefs.data[DdayStore.itemsKey], _fixtureRaw,
          reason: 'nothing overwrites the damaged data automatically');

      await tester.tap(find.byKey(const Key('recovery_copy')));
      await tester.pumpAndSettle();
      expect(copied, _fixtureRaw);

      await tester.tap(find.byKey(const Key('recovery_dismiss')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('recovery_confirm_clear')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('recovery_banner')), findsNothing);
      expect(h.prefs.data.containsKey(DdayStore.recoveryKey), isFalse);
      expect(h.storedIds(), hasLength(6));
      expect(h.storedIds(), isNot(contains('g-bad')));

      // Restart: the banner must not come back.
      await tester.pumpWidget(h.app(key: UniqueKey()));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recovery_banner')), findsNothing);
      expect(find.byType(DdayCard), findsNWidgets(6));
    });

    testWidgets('cancelling the confirmation keeps everything',
        (tester) async {
      final h = _Harness(data: <String, Object>{DdayStore.itemsKey: '{broken'});
      await h.pump(tester);
      await tester.tap(find.byKey(const Key('recovery_dismiss')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('recovery_banner')), findsOneWidget);
      expect(h.prefs.data[DdayStore.itemsKey], '{broken');
      expect(h.prefs.data[DdayStore.recoveryKey], '{broken');
    });

    testWidgets('banner stays if clearing recovery fails', (tester) async {
      final h = _Harness(data: <String, Object>{DdayStore.itemsKey: '{broken'});
      await h.pump(tester);
      h.prefs.rejectKeys.add(DdayStore.recoveryKey);

      await tester.tap(find.byKey(const Key('recovery_dismiss')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('recovery_confirm_clear')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('recovery_banner')), findsOneWidget);
      expect(find.text(storageWriteFailedMessage), findsOneWidget);
      expect(h.prefs.data[DdayStore.recoveryKey], '{broken');
    });

    testWidgets('banner survives restarts until acknowledged', (tester) async {
      final h = _Harness(data: <String, Object>{DdayStore.itemsKey: '{broken'});
      await h.pump(tester);

      // User adds data before acknowledging: main key becomes healthy.
      await h.store.saveItems(<DdayItem>[
        DdayItem.create(title: '新項目', date: '2026-12-01', id: 'new'),
      ]);
      await tester.pumpWidget(h.app(key: UniqueKey()));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recovery_banner')), findsOneWidget);
    });
  });
}
