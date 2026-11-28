import 'package:flutter/material.dart';

import '../data/backup_service.dart';
import '../data/dday_store.dart';
import '../models/dday.dart';
import '../services/background_images.dart';
import '../services/native_bridge.dart';
import '../services/update_service.dart';
import '../theme/dday_colors.dart';
import '../utils/day_calc.dart';
import '../widgets/soft_card.dart';
import '../widgets/update_flow.dart';
import '../utils/dday_sorter.dart';
import '../widgets/dday_card.dart';
import '../widgets/dialogs.dart';
import '../widgets/section_header.dart';
import 'backup_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.store,
    required this.nativeBridge,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.currentItems,
    this.sortMode = DdaySortMode.nearest,
    required this.onSaveItems,
    required this.backupService,
    required this.fileChannel,
    required this.clock,
    this.updateFlow,
  });

  final DdayStore store;
  final NativeBridge nativeBridge;
  final ThemeMode themeMode;
  final Future<void> Function(ThemeMode mode) onThemeModeChanged;
  final List<DdayItem> currentItems;
  final DdaySortMode sortMode;
  final Future<bool> Function(List<DdayItem> items) onSaveItems;
  final BackupService backupService;
  final BackupFileChannel fileChannel;
  final DateTime Function() clock;

  /// Update checker; null hides the update controls (e.g. in tests).
  final UpdateFlow? updateFlow;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late ThemeMode _themeMode;
  bool _ongoingEnabled = false;
  String _reminderTime = '09:00';
  bool _hasPermission = false;
  bool _loading = true;
  AppVersion? _version;
  bool _autoUpdate = true;
  bool _checkingUpdate = false;
  late List<DdayItem> _items;

  @override
  void initState() {
    super.initState();
    _themeMode = widget.themeMode;
    _items = List<DdayItem>.from(widget.currentItems);
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final results = await Future.wait<dynamic>([
      widget.store.loadOngoingNotification(),
      widget.store.loadReminderTime(),
      widget.nativeBridge.hasNotificationPermission(),
      widget.nativeBridge.getAppVersion(),
      widget.store.loadUpdateAutoCheck(),
    ]);
    if (!mounted) return;
    setState(() {
      _ongoingEnabled = results[0] as bool;
      _reminderTime = results[1] as String;
      _hasPermission = results[2] as bool;
      _version = results[3] as AppVersion?;
      _autoUpdate = results[4] as bool;
      _loading = false;
    });
  }

  Future<void> _toggleOngoing(bool enabled) async {
    if (enabled && !_hasPermission) {
      final granted = await widget.nativeBridge.requestNotificationPermission();
      if (!mounted) return;
      setState(() {
        _hasPermission = granted;
      });
      if (!granted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('尚未取得通知權限，請於系統設定開啟')));
        return;
      }
    }

    final previous = _ongoingEnabled;
    setState(() {
      _ongoingEnabled = enabled;
    });
    try {
      await widget.store.saveOngoingNotification(enabled);
    } on StorageWriteException {
      if (!mounted) return;
      setState(() {
        _ongoingEnabled = previous;
      });
      showAppSnackBar(context, storageWriteFailedMessage);
      return;
    }
    await widget.nativeBridge.syncNotifications();
  }

  Future<void> _pickReminderTime() async {
    final parts = _reminderTime.split(':');
    final initialHour = int.tryParse(parts.first) ?? 9;
    final initialMinute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;

    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initialHour, minute: initialMinute),
    );
    if (picked == null || !mounted) return;

    final formatted =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    final previous = _reminderTime;
    setState(() {
      _reminderTime = formatted;
    });
    try {
      await widget.store.saveReminderTime(formatted);
    } on StorageWriteException {
      if (!mounted) return;
      setState(() {
        _reminderTime = previous;
      });
      showAppSnackBar(context, storageWriteFailedMessage);
      return;
    }
    await widget.nativeBridge.syncNotifications();
  }

  Future<void> _checkForUpdate() async {
    final flow = widget.updateFlow;
    if (flow == null) return;
    setState(() => _checkingUpdate = true);
    void done() {
      if (mounted && _checkingUpdate) setState(() => _checkingUpdate = false);
    }

    try {
      await flow.manualCheck(context, onChecked: done);
    } finally {
      done();
    }
  }

  Future<void> _toggleAutoUpdate(bool enabled) async {
    final previous = _autoUpdate;
    setState(() => _autoUpdate = enabled);
    try {
      await widget.store.saveUpdateAutoCheck(enabled);
    } on StorageWriteException {
      if (!mounted) return;
      setState(() => _autoUpdate = previous);
      showAppSnackBar(context, storageWriteFailedMessage);
    }
  }

  Future<void> _requestPermission() async {
    final granted = await widget.nativeBridge.requestNotificationPermission();
    if (!mounted) return;
    setState(() {
      _hasPermission = granted;
    });
    await widget.nativeBridge.syncNotifications();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const SectionHeader('通知與提醒'),
                  const SizedBox(height: 8),
                  SoftCard(
                    child: Column(
                      children: [
                        ListTile(
                          key: const Key('reminder_time_tile'),
                          leading: const Icon(Icons.schedule),
                          title: const Text('預設提醒時間'),
                          subtitle: Text(_reminderTime),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _pickReminderTime,
                        ),
                        const Divider(height: 1),
                        SwitchListTile(
                          key: const Key('ongoing_notification_switch'),
                          secondary: const Icon(
                            Icons.notifications_active_outlined,
                          ),
                          title: const Text('通知列常駐顯示'),
                          value: _ongoingEnabled,
                          onChanged: _toggleOngoing,
                        ),
                        const Divider(height: 1),
                        ListTile(
                          key: const Key(
                            'request_notification_permission_button',
                          ),
                          leading: Icon(
                            _hasPermission
                                ? Icons.verified_user_outlined
                                : Icons.notifications_off_outlined,
                            color: _hasPermission
                                ? theme.colorScheme.primary
                                : theme.colorScheme.error,
                          ),
                          title: const Text('Android 通知權限'),
                          subtitle: Text(_hasPermission ? '已授權' : '未授權'),
                          trailing: _hasPermission ? null : const Text('授權'),
                          onTap: _hasPermission ? null : _requestPermission,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  const SectionHeader('外觀與資料'),
                  const SizedBox(height: 8),
                  SoftCard(
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('外觀主題'),
                              const SizedBox(height: 8),
                              SegmentedButton<ThemeMode>(
                                segments: const <ButtonSegment<ThemeMode>>[
                                  ButtonSegment<ThemeMode>(
                                    value: ThemeMode.system,
                                    label: Text('系統'),
                                  ),
                                  ButtonSegment<ThemeMode>(
                                    value: ThemeMode.light,
                                    label: Text('淺色'),
                                  ),
                                  ButtonSegment<ThemeMode>(
                                    value: ThemeMode.dark,
                                    label: Text('深色'),
                                  ),
                                ],
                                selected: <ThemeMode>{_themeMode},
                                onSelectionChanged: (selection) async {
                                  final mode = selection.first;
                                  setState(() => _themeMode = mode);
                                  await widget.onThemeModeChanged(mode);
                                },
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.import_export),
                          title: const Text('備份與還原'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            await Navigator.of(context).push<void>(
                              MaterialPageRoute<void>(
                                builder: (_) => BackupScreen(
                                  initialItems: _items,
                                  onSaveItems: (updated) async {
                                    final saved = await widget.onSaveItems(
                                      updated,
                                    );
                                    if (saved && mounted) {
                                      setState(() => _items = updated);
                                    }
                                    return saved;
                                  },
                                  backupService: widget.backupService,
                                  fileChannel: widget.fileChannel,
                                  clock: widget.clock,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const SectionHeader('桌面小工具'),
                  const SizedBox(height: 8),
                  _buildWidgetPreviewCard(theme),
                  const SizedBox(height: 20),
                  const SectionHeader('關於 D-Day Before'),
                  const SizedBox(height: 8),
                  SoftCard(
                    child: Column(
                      children: [
                        ListTile(
                          key: const Key('about_version_tile'),
                          leading: const Icon(Icons.info_outline),
                          title: const Text('D-Day Before'),
                          subtitle: Text(
                            _version == null ? '版本 —' : '版本 v${_version!.name}',
                          ),
                        ),
                        if (widget.updateFlow != null) ...[
                          const Divider(height: 1),
                          ListTile(
                            key: const Key('check_update_button'),
                            leading: const Icon(Icons.system_update_outlined),
                            title: const Text('檢查更新'),
                            trailing: _checkingUpdate
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.chevron_right),
                            onTap: _checkingUpdate ? null : _checkForUpdate,
                          ),
                          const Divider(height: 1),
                          SwitchListTile(
                            key: const Key('auto_update_switch'),
                            secondary: const Icon(Icons.autorenew),
                            title: const Text('自動檢查更新'),
                            value: _autoUpdate,
                            onChanged: _toggleAutoUpdate,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildWidgetPreviewCard(ThemeData theme) {
    final now = widget.clock();
    final sorted = sortDdays(_items, widget.sortMode, today: now);
    final top = sorted.isNotEmpty ? sorted.first : null;
    final title = top == null ? 'D-Day Before' : top.title;
    final subtitle = top == null
        ? '點擊新增重要日子'
        : () {
            final dateText = formatDisplayDateZh(
              effectiveTargetDate(top, today: now),
            );
            final repeatText = anniversarySubtitle(top, today: now);
            return repeatText == null ? dateText : '$dateText・$repeatText';
          }();
    final countdown = top == null ? 'D-Day' : formatCountdown(top, today: now);
    final colors = DdayColors.byKey(top?.colorKey).resolve(theme.colorScheme);

    return SoftCard(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: DdayCard(
              variant: DdayCardVariant.widgetPreview,
              boxKey: const Key('widget_preview_box'),
              photo: BackgroundImages.fileFor(top?.backgroundImage),
              title: title,
              subtitle: subtitle,
              badge: countdown,
              colors: colors,
              pinned: top?.pinned ?? false,
            ),
          ),
          const Divider(height: 1),
          ListTile(
            key: const Key('sync_widget_button'),
            leading: const Icon(Icons.widgets_outlined),
            title: const Text('立即同步桌面小工具'),
            onTap: () async {
              await widget.nativeBridge.refreshWidgets();
              if (!mounted) return;
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(const SnackBar(content: Text('已同步桌面小工具')));
            },
          ),
        ],
      ),
    );
  }
}
