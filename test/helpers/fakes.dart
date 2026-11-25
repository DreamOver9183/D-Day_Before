import 'dart:async';

import 'package:dday_before/data/backup_service.dart';
import 'package:dday_before/services/native_bridge.dart';

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
