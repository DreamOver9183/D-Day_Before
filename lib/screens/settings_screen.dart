import 'package:flutter/material.dart';

import '../data/backup_service.dart';
import '../data/dday_store.dart';
import '../models/dday.dart';
import '../services/native_bridge.dart';
import '../theme/dday_colors.dart';
import '../utils/day_calc.dart';
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

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late ThemeMode _themeMode;
  bool _ongoingEnabled = false;
  String _reminderTime = '09:00';
  bool _hasPermission = false;
  bool _loading = true;
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
    ]);
    if (!mounted) return;
    setState(() {
      _ongoingEnabled = results[0] as bool;
      _reminderTime = results[1] as String;
      _hasPermission = results[2] as bool;
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
          ..showSnackBar(
            const SnackBar(content: Text('尚未取得通知權限，請於系統設定開啟')),
          );
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
      appBar: AppBar(
        title: const Text('設定'),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const SectionHeader('通知與提醒'),
                  const SizedBox(height: 8),
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: theme.colorScheme.outlineVariant),
                    ),
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
                          secondary: const Icon(Icons.notifications_active_outlined),
                          title: const Text('通知列常駐顯示'),
                          subtitle: const Text('顯示目前最優先（置頂或最近）的 D-Day'),
                          value: _ongoingEnabled,
                          onChanged: _toggleOngoing,
                        ),
                        const Divider(height: 1),
                        ListTile(
                          key: const Key('request_notification_permission_button'),
                          leading: Icon(
                            _hasPermission
                                ? Icons.verified_user_outlined
                                : Icons.notifications_off_outlined,
                            color: _hasPermission
                                ? theme.colorScheme.primary
                                : theme.colorScheme.error,
                          ),
                          title: const Text('Android 通知權限'),
                          subtitle: Text(_hasPermission ? '已授權' : '未授權，點擊請求授權'),
                          trailing: _hasPermission
                              ? null
                              : const Text('授權'),
                          onTap: _hasPermission ? null : _requestPermission,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    elevation: 0,
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        '提醒限制說明：Android 13+ 需允許通知權限；Android 14+ 常駐通知仍可手動滑掉，'
                        'APP 會在下次開啟或跨午夜自動補回；重開機後會自動重建排程，'
                        '部分省電模式可能會略微延後通知。',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const SectionHeader('外觀與資料'),
                  const SizedBox(height: 8),
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: theme.colorScheme.outlineVariant),
                    ),
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
                          subtitle: const Text('匯出或匯入 JSON 備份'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            await Navigator.of(context).push<void>(
                              MaterialPageRoute<void>(
                                builder: (_) => BackupScreen(
                                  initialItems: _items,
                                  onSaveItems: (updated) async {
                                    final saved =
                                        await widget.onSaveItems(updated);
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
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: theme.colorScheme.outlineVariant),
                    ),
                    child: const Column(
                      children: [
                        ListTile(
                          key: Key('about_version_tile'),
                          leading: Icon(Icons.info_outline),
                          title: Text('D-Day Before'),
                          subtitle: Text('版本 v1.0.0'),
                        ),
                        Divider(height: 1),
                        ListTile(
                          leading: Icon(Icons.lock_outline),
                          title: Text('離線隱私設計'),
                          subtitle: Text('完全離線儲存於本機，無帳號、無廣告、不要求網路權限'),
                        ),
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
    final countdown =
        top == null ? 'D-Day' : formatCountdown(top, today: now);
    final colors = DdayColors.byKey(top?.colorKey).resolve(theme.colorScheme);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: DdayCard(
              variant: DdayCardVariant.widgetPreview,
              boxKey: const Key('widget_preview_box'),
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
            subtitle: const Text('長按手機桌面 → 新增「D-Day Before 倒數卡片」'),
            onTap: () async {
              await widget.nativeBridge.refreshWidgets();
              if (!mounted) return;
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  const SnackBar(content: Text('已同步桌面小工具')),
                );
            },
          ),
        ],
      ),
    );
  }
}
