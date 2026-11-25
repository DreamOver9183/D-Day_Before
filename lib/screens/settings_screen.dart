import 'package:flutter/material.dart';

import '../data/backup_service.dart';
import '../data/dday_store.dart';
import '../models/dday.dart';
import '../services/native_bridge.dart';
import '../theme/dday_colors.dart';
import '../utils/day_calc.dart';
import '../utils/dday_sorter.dart';
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
  final Future<void> Function(List<DdayItem> items) onSaveItems;
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

    setState(() {
      _ongoingEnabled = enabled;
    });
    await widget.store.saveOngoingNotification(enabled);
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
    setState(() {
      _reminderTime = formatted;
    });
    await widget.store.saveReminderTime(formatted);
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
                  Text(
                    '通知與提醒',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
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
                  Text(
                    '外觀與資料',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
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
                                    await widget.onSaveItems(updated);
                                    if (mounted) {
                                      setState(() => _items = updated);
                                    }
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
                  Text(
                    '桌面小工具',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildWidgetPreviewCard(theme),
                ],
              ),
      ),
    );
  }

  Widget _buildWidgetPreviewCard(ThemeData theme) {
    final now = widget.clock();
    final sorted = sortDdays(_items, widget.sortMode, today: now);
    final top = sorted.isNotEmpty ? sorted.first : null;
    final title = top == null
        ? 'D-Day Before'
        : (top.pinned ? '📌 ${top.title}' : top.title);
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
            child: Container(
              key: const Key('widget_preview_box'),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.cardBackground,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.borderColor),
              ),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 36,
                    decoration: BoxDecoration(
                      color: colors.accentColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: colors.badgeBackground,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      countdown,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colors.badgeForeground,
                      ),
                    ),
                  ),
                ],
              ),
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
