import 'dart:async';

import 'package:dday_before/data/backup_service.dart';
import 'package:dday_before/services/native_bridge.dart';
import 'package:dday_before/services/update_service.dart';

/// Records native calls and can be told to throw or to block until released.
class FakeNativeBridge implements NativeBridge {
  FakeNativeBridge({this.permissionGranted = true});

  bool permissionGranted;
  int syncCalls = 0;
  int widgetRefreshCalls = 0;
  bool throwOnSync = false;

  /// When non-null, [syncNotifications] waits on this before returning.
  Completer<void>? syncGate;

  @override
  Future<bool> hasNotificationPermission() async => permissionGranted;

  @override
  Future<bool> requestNotificationPermission() async => permissionGranted;

  @override
  Future<void> syncNotifications() async {
    syncCalls++;
    final gate = syncGate;
    if (gate != null) {
      await gate.future;
    }
    if (throwOnSync) {
      throw StateError('native sync failed');
    }
  }

  @override
  Future<void> refreshWidgets() async {
    widgetRefreshCalls++;
  }

  /// Name returned by the next [pickBackgroundImage] (null = cancelled).
  String? nextPickedImage;
  Object? pickError;
  int pickCalls = 0;
  String? backgroundsDir;
  final List<Set<String>> cleanupCalls = <Set<String>>[];

  @override
  Future<String?> pickBackgroundImage() async {
    pickCalls++;
    final error = pickError;
    if (error != null) throw error;
    return nextPickedImage;
  }

  @override
  Future<String?> backgroundsDirectory() async => backgroundsDir;

  @override
  Future<void> cleanupBackgrounds(Set<String> keep) async {
    cleanupCalls.add(keep);
  }

  AppVersion? appVersion;
  bool installAllowed = true;
  int openInstallSettingsCalls = 0;
  Object? installError;
  final List<(String, String)> installCalls = <(String, String)>[];

  @override
  Future<AppVersion?> getAppVersion() async => appVersion;

  @override
  Future<bool> canInstallUpdates() async => installAllowed;

  @override
  Future<void> openInstallPermissionSettings() async {
    openInstallSettingsCalls++;
  }

  @override
  Future<void> downloadAndInstallUpdate(String url, String sha256) async {
    installCalls.add((url, sha256));
    final error = installError;
    if (error != null) throw error;
  }
}

/// Update source returning a fixed result or error.
class FakeUpdateSource implements UpdateSource {
  FakeUpdateSource({this.latest, this.error});

  UpdateInfo? latest;
  Object? error;
  int calls = 0;

  @override
  Future<UpdateInfo?> fetchLatest() async {
    calls++;
    final e = error;
    if (e != null) throw e;
    return latest;
  }
}

/// File channel stub for backup tests.
class FakeBackupFileChannel implements BackupFileChannel {
  String? importResult;
  Object? importError;
  String? lastExportName;
  String? lastExportContent;

  @override
  Future<bool> exportJsonFile(String filename, String content) async {
    lastExportName = filename;
    lastExportContent = content;
    return true;
  }

  @override
  Future<String?> importJsonFile() async {
    final error = importError;
    if (error != null) {
      throw error;
    }
    return importResult;
  }
}

/// Mutable clock for widget tests.
class TestClock {
  TestClock(this.now);

  DateTime now;

  DateTime call() => now;
}
