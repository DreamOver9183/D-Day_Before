import 'package:flutter/services.dart';

import 'update_service.dart';

abstract class NativeBridge {
  Future<bool> hasNotificationPermission();
  Future<bool> requestNotificationPermission();
  Future<void> syncNotifications();
  Future<void> refreshWidgets();

  /// Opens the system photo picker and stores the chosen photo; returns its
  /// file name, or null if the user cancelled. Throws [PlatformException] if
  /// the photo could not be read.
  Future<String?> pickBackgroundImage();

  /// Folder where background photos are stored, or null if unavailable.
  Future<String?> backgroundsDirectory();

  /// Deletes stored photos that are no longer referenced by [keep].
  Future<void> cleanupBackgrounds(Set<String> keep);

  /// Installed app version, or null if unavailable.
  Future<AppVersion?> getAppVersion();

  /// Whether Android allows this app to install updates.
  Future<bool> canInstallUpdates();

  /// Opens the system page where the user allows installing updates.
  Future<void> openInstallPermissionSettings();

  /// Downloads the APK, verifies [sha256] and opens the system installer.
  /// Throws [PlatformException] with an [UpdateErrorCodes] code on failure.
  Future<void> downloadAndInstallUpdate(String url, String sha256);
}

class MethodChannelNativeBridge implements NativeBridge {
  const MethodChannelNativeBridge();

  static const MethodChannel _channel = MethodChannel(
    'com.cytsa.dday_before/native',
  );

  @override
  Future<bool> hasNotificationPermission() async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'hasNotificationPermission',
      );
      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> requestNotificationPermission() async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'requestNotificationPermission',
      );
      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> syncNotifications() async {
    try {
      await _channel.invokeMethod<bool>('syncNotifications');
    } on MissingPluginException {
      // Ignore in unit tests without Android host.
    } on PlatformException {
      // Best-effort sync.
    }
  }

  @override
  Future<String?> pickBackgroundImage() async {
    try {
      return await _channel.invokeMethod<String>('pickBackgroundImage');
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<String?> backgroundsDirectory() async {
    try {
      return await _channel.invokeMethod<String>('getBackgroundsDir');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<void> cleanupBackgrounds(Set<String> keep) async {
    try {
      await _channel.invokeMethod<int>('cleanupBackgrounds', <String, Object>{
        'keep': keep.toList(),
      });
    } on MissingPluginException {
      // Ignore in unit tests without Android host.
    } on PlatformException {
      // Best-effort cleanup.
    }
  }

  @override
  Future<AppVersion?> getAppVersion() async {
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>(
        'getAppVersion',
      );
      final name = raw?['versionName'];
      final code = raw?['versionCode'];
      if (name is String && code is int) {
        return AppVersion(name: name, code: code);
      }
      return null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<bool> canInstallUpdates() async {
    try {
      return await _channel.invokeMethod<bool>('canInstallUpdates') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> openInstallPermissionSettings() async {
    try {
      await _channel.invokeMethod<bool>('openInstallPermissionSettings');
    } on MissingPluginException {
      // No Android host.
    }
  }

  @override
  Future<void> downloadAndInstallUpdate(String url, String sha256) async {
    await _channel.invokeMethod<bool>(
      'downloadAndInstallUpdate',
      <String, Object>{'url': url, 'sha256': sha256},
    );
  }

  /// Debug builds only: runs the real import pipeline on raw image bytes so
  /// device tests can add a photo without driving the system picker.
  Future<String?> debugImportBackground(List<int> bytes) {
    return _channel.invokeMethod<String>(
      'debugImportBackground',
      <String, Object>{'bytes': Uint8List.fromList(bytes)},
    );
  }

  @override
  Future<void> refreshWidgets() async {
    try {
      await _channel.invokeMethod<bool>('refreshWidgets');
    } on MissingPluginException {
      // Ignore in unit tests without Android host.
    } on PlatformException {
      // Best-effort sync.
    }
  }
}
