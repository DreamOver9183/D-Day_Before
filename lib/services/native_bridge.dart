import 'package:flutter/services.dart';

abstract class NativeBridge {
  Future<bool> hasNotificationPermission();
  Future<bool> requestNotificationPermission();
  Future<void> syncNotifications();
  Future<void> refreshWidgets();
}

class MethodChannelNativeBridge implements NativeBridge {
  const MethodChannelNativeBridge();

  static const MethodChannel _channel =
      MethodChannel('com.cytsa.dday_before/native');

  @override
  Future<bool> hasNotificationPermission() async {
    try {
      final result =
          await _channel.invokeMethod<bool>('hasNotificationPermission');
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
      final result =
          await _channel.invokeMethod<bool>('requestNotificationPermission');
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
