import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/dday_store.dart';
import '../services/native_bridge.dart';
import '../services/update_service.dart';
import 'dialogs.dart';

/// Checks GitHub for a newer release and walks the user through installing
/// it. Shared by the automatic check on launch and the manual button.
class UpdateFlow {
  UpdateFlow({
    required this.source,
    required this.bridge,
    required this.store,
    required this.clock,
  });

  final UpdateSource source;
  final NativeBridge bridge;
  final DdayStore store;
  final DateTime Function() clock;

  bool _busy = false;

  /// Silent check: at most once a day, only if enabled; errors are ignored.
  Future<void> autoCheck(BuildContext context) async {
    if (_busy) return;
    if (!await store.loadUpdateAutoCheck()) return;
    final last = await store.loadUpdateLastCheck();
    final now = clock();
    if (!shouldAutoCheck(lastCheck: last, now: now)) return;

    final current = await bridge.getAppVersion();
    if (current == null) return;

    _busy = true;
    try {
      final latest = await source.fetchLatest();
      await store.saveUpdateLastCheck(now);
      if (latest == null || !latest.isNewerThan(current)) return;
      if (!context.mounted) return;
      await _offer(context, latest);
    } catch (e) {
      debugPrint('auto update check failed: $e');
    } finally {
      _busy = false;
    }
  }

  /// Manual check from settings; always reports the outcome.
  /// [onChecked] runs once GitHub has answered (before any dialog), so a
  /// caller's progress indicator stops while the user reads the result.
  Future<void> manualCheck(
    BuildContext context, {
    VoidCallback? onChecked,
  }) async {
    if (_busy) return;
    _busy = true;
    try {
      final AppVersion? current;
      final UpdateInfo? latest;
      try {
        current = await bridge.getAppVersion();
        latest = await source.fetchLatest();
      } finally {
        onChecked?.call();
      }
      await store.saveUpdateLastCheck(clock());
      if (!context.mounted) return;
      if (current == null || latest == null || !latest.isNewerThan(current)) {
        showAppSnackBar(context, '已是最新版本');
        return;
      }
      await _offer(context, latest);
    } catch (e) {
      debugPrint('manual update check failed: $e');
      if (context.mounted) {
        showAppSnackBar(context, '無法檢查更新，請確認網路連線');
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _offer(BuildContext context, UpdateInfo info) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('有新版本 v${info.versionName}'),
        content: info.notes.isEmpty
            ? null
            : ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: SingleChildScrollView(child: Text(info.notes)),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('稍後'),
          ),
          FilledButton(
            key: const Key('update_confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('更新'),
          ),
        ],
      ),
    );
    if (accepted != true || !context.mounted) return;
    await _install(context, info);
  }

  Future<void> _install(BuildContext context, UpdateInfo info) async {
    if (!await bridge.canInstallUpdates()) {
      if (context.mounted) await _askInstallPermission(context);
      return;
    }
    if (!context.mounted) return;

    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
          key: Key('update_progress'),
          content: Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              SizedBox(width: 16),
              Text('下載更新中…'),
            ],
          ),
        ),
      ),
    );

    String? errorCode;
    try {
      await bridge.downloadAndInstallUpdate(info.apkUrl, info.sha256);
    } on PlatformException catch (e) {
      errorCode = e.code;
    } catch (_) {
      errorCode = UpdateErrorCodes.downloadFailed;
    } finally {
      navigator.pop();
    }

    if (errorCode == null || !context.mounted) return;
    if (errorCode == UpdateErrorCodes.installNotAllowed) {
      await _askInstallPermission(context);
    } else if (errorCode == UpdateErrorCodes.checksumMismatch) {
      showAppSnackBar(context, '下載的檔案不完整，請稍後再試');
    } else {
      showAppSnackBar(context, '下載失敗，請確認網路連線');
    }
  }

  Future<void> _askInstallPermission(BuildContext context) async {
    final open = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('需要允許安裝更新'),
        content: const Text('請在下一頁允許「D-Day Before」安裝應用程式，返回後再按一次更新。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('update_open_settings'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('前往設定'),
          ),
        ],
      ),
    );
    if (open == true) {
      await bridge.openInstallPermissionSettings();
    }
  }
}
