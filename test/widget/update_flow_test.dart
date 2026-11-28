import 'package:dday_before/data/backup_service.dart';
import 'package:dday_before/data/dday_store.dart';
import 'package:dday_before/models/dday.dart';
import 'package:dday_before/screens/home_screen.dart';
import 'package:dday_before/screens/settings_screen.dart';
import 'package:dday_before/services/update_service.dart';
import 'package:dday_before/widgets/update_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_prefs.dart';
import '../helpers/fakes.dart';

final DateTime _now = DateTime(2026, 11, 26, 9);
final UpdateInfo _newer = UpdateInfo(
  versionName: '1.0.2',
  versionCode: 9,
  apkUrl: 'https://github.com/o/r/releases/download/v1.0.2/a.apk',
  sha256: 'ab' * 32,
  notes: '新功能說明',
);
const AppVersion _installed = AppVersion(name: '1.0.1', code: 8);

void main() {
  late FakePrefs prefs;
  late FakeNativeBridge bridge;
  late FakeUpdateSource source;

  setUp(() {
    prefs = FakePrefs();
    bridge = FakeNativeBridge()..appVersion = _installed;
    source = FakeUpdateSource(latest: _newer);
  });

  DdayStore store() => DdayStore(prefsProvider: () async => prefs);

  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          store: store(),
          nativeBridge: bridge,
          themeMode: ThemeMode.light,
          onThemeModeChanged: (_) async {},
          currentItems: const <DdayItem>[],
          onSaveItems: (_) async => true,
          backupService: const BackupService(),
          fileChannel: FakeBackupFileChannel(),
          clock: () => _now,
          updateFlow: UpdateFlow(
            source: source,
            bridge: bridge,
            store: store(),
            clock: () => _now,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapCheck(WidgetTester tester) async {
    final button = find.byKey(const Key('check_update_button'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  group('settings', () {
    testWidgets('shows the installed version', (tester) async {
      await pumpSettings(tester);
      expect(find.text('版本 v1.0.1'), findsOneWidget);
    });

    testWidgets('up to date', (tester) async {
      source.latest = null;
      await pumpSettings(tester);
      await tapCheck(tester);
      expect(find.text('已是最新版本'), findsOneWidget);
      expect(prefs.data[DdayStore.updateLastCheckKey], isNotNull);
    });

    testWidgets('network error is reported', (tester) async {
      source.error = const UpdateCheckException('offline');
      await pumpSettings(tester);
      await tapCheck(tester);
      expect(find.text('無法檢查更新，請確認網路連線'), findsOneWidget);
    });

    testWidgets('newer version: confirm downloads and installs',
        (tester) async {
      await pumpSettings(tester);
      await tapCheck(tester);
      expect(find.text('有新版本 v1.0.2'), findsOneWidget);
      expect(find.text('新功能說明'), findsOneWidget);

      await tester.tap(find.byKey(const Key('update_confirm')));
      await tester.pumpAndSettle();
      expect(bridge.installCalls, <(String, String)>[
        (_newer.apkUrl, _newer.sha256),
      ]);
      expect(find.byKey(const Key('update_progress')), findsNothing,
          reason: 'progress dialog closes after handing off to Android');
    });

    testWidgets('later does nothing', (tester) async {
      await pumpSettings(tester);
      await tapCheck(tester);
      await tester.tap(find.text('稍後'));
      await tester.pumpAndSettle();
      expect(bridge.installCalls, isEmpty);
    });

    testWidgets('missing install permission opens the system page',
        (tester) async {
      bridge.installAllowed = false;
      await pumpSettings(tester);
      await tapCheck(tester);
      await tester.tap(find.byKey(const Key('update_confirm')));
      await tester.pumpAndSettle();
      expect(find.text('需要允許安裝更新'), findsOneWidget);
      await tester.tap(find.byKey(const Key('update_open_settings')));
      await tester.pumpAndSettle();
      expect(bridge.openInstallSettingsCalls, 1);
      expect(bridge.installCalls, isEmpty);
    });

    testWidgets('checksum failure is reported', (tester) async {
      bridge.installError = PlatformException(
        code: UpdateErrorCodes.checksumMismatch,
      );
      await pumpSettings(tester);
      await tapCheck(tester);
      await tester.tap(find.byKey(const Key('update_confirm')));
      await tester.pumpAndSettle();
      expect(find.text('下載的檔案不完整，請稍後再試'), findsOneWidget);
      expect(find.byKey(const Key('update_progress')), findsNothing);
    });

    testWidgets('auto-check switch persists', (tester) async {
      await pumpSettings(tester);
      final toggle = find.byKey(const Key('auto_update_switch'));
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(prefs.data[DdayStore.updateAutoCheckKey], isFalse);
    });
  });

  group('automatic check on launch', () {
    Future<void> pumpHome(WidgetTester tester, {required bool auto}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            store: store(),
            nativeBridge: bridge,
            updateSource: source,
            autoCheckUpdates: auto,
            clock: () => _now,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('offers the update once a day', (tester) async {
      await pumpHome(tester, auto: true);
      expect(source.calls, 1);
      expect(find.text('有新版本 v1.0.2'), findsOneWidget);
      await tester.tap(find.text('稍後'));
      await tester.pumpAndSettle();

      // Relaunch the same day: no second check.
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpHome(tester, auto: true);
      expect(source.calls, 1);
      expect(find.text('有新版本 v1.0.2'), findsNothing);
    });

    testWidgets('respects the setting and debug builds', (tester) async {
      prefs.data[DdayStore.updateAutoCheckKey] = false;
      await pumpHome(tester, auto: true);
      expect(source.calls, 0);

      prefs.data.remove(DdayStore.updateAutoCheckKey);
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpHome(tester, auto: false);
      expect(source.calls, 0, reason: 'debug/test builds never auto-check');
    });

    testWidgets('errors stay silent', (tester) async {
      source.error = const UpdateCheckException('offline');
      await pumpHome(tester, auto: true);
      expect(source.calls, 1);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });
}
