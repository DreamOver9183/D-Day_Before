import 'dart:async';

import 'package:flutter/material.dart';

import '../data/backup_service.dart';
import '../data/dday_store.dart';
import '../models/dday.dart';
import '../theme/dday_colors.dart';
import '../utils/day_calc.dart';
import '../utils/dday_sorter.dart';
import 'backup_screen.dart';
import 'edit_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.store,
    this.backupService = const BackupService(),
    this.fileChannel = const MethodChannelBackupFileChannel(),
    this.themeMode = ThemeMode.system,
    this.onThemeModeChanged,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  final DdayStore store;
  final BackupService backupService;
  final BackupFileChannel fileChannel;
  final ThemeMode themeMode;
  final Future<void> Function(ThemeMode mode)? onThemeModeChanged;
  final DateTime Function() clock;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  List<DdayItem> _items = <DdayItem>[];
  DdaySortMode _sortMode = DdaySortMode.nearest;
  bool _loading = true;
  Timer? _midnightTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadInitial();
    _scheduleMidnightRefresh();
  }

  @override
  void dispose() {
    _midnightTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {});
      _scheduleMidnightRefresh();
    }
  }

  void _scheduleMidnightRefresh() {
    _midnightTimer?.cancel();
    final now = widget.clock();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1, 0, 0, 1);
    final delay = nextMidnight.difference(now);
    final safeDelay = delay.isNegative ? const Duration(seconds: 1) : delay;
    _midnightTimer = Timer(safeDelay, () {
      if (!mounted) return;
      setState(() {});
      _scheduleMidnightRefresh();
    });
  }

  Future<void> _loadInitial() async {
    final results = await Future.wait<dynamic>([
      widget.store.loadItems(),
      widget.store.loadSortMode(),
    ]);
    if (!mounted) return;
    setState(() {
      _items = results[0] as List<DdayItem>;
      _sortMode = results[1] as DdaySortMode;
      _loading = false;
    });
  }

  Future<void> _persistItems(List<DdayItem> updated) async {
    setState(() {
      _items = updated;
    });
    await widget.store.saveItems(updated);
  }

  Future<void> _changeSortMode(DdaySortMode mode) async {
    if (_sortMode == mode) return;
    setState(() {
      _sortMode = mode;
    });
    await widget.store.saveSortMode(mode);
  }

  Future<void> _openBackup() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => BackupScreen(
          initialItems: _items,
          onSaveItems: _persistItems,
          backupService: widget.backupService,
          fileChannel: widget.fileChannel,
          clock: widget.clock,
        ),
      ),
    );
  }

  Future<void> _openEditor([DdayItem? item]) async {
    final result = await Navigator.of(context).push<EditResult>(
      MaterialPageRoute<EditResult>(
        builder: (_) => EditScreen(
          initialItem: item,
          clock: widget.clock,
        ),
      ),
    );
    if (!mounted || result == null) return;

    switch (result) {
      case EditSaveResult(:final item):
        final index = _items.indexWhere((e) => e.id == item.id);
        final updated = List<DdayItem>.from(_items);
        if (index >= 0) {
          updated[index] = item;
        } else {
          updated.add(item);
        }
        await _persistItems(updated);
      case EditDeleteResult(:final id):
        final updated = _items.where((e) => e.id != id).toList();
        await _persistItems(updated);
    }
  }

  Future<void> _togglePin(DdayItem item) async {
    final updated = _items
        .map((e) => e.id == item.id ? e.copyWith(pinned: !e.pinned) : e)
        .toList();
    await _persistItems(updated);
  }

  Future<void> _confirmAndDelete(DdayItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('刪除 D-Day'),
        content: Text('確定要刪除「${item.title}」嗎？此動作無法復原。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('刪除'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final updated = _items.where((e) => e.id != item.id).toList();
      await _persistItems(updated);
    }
  }

  Future<void> _showItemActions(DdayItem item) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('action_toggle_pin'),
              leading: Icon(
                item.pinned ? Icons.push_pin_outlined : Icons.push_pin,
              ),
              title: Text(item.pinned ? '取消置頂' : '置頂'),
              onTap: () => Navigator.of(context).pop('pin'),
            ),
            ListTile(
              key: const Key('action_delete'),
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                '刪除',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () => Navigator.of(context).pop('delete'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || action == null) return;
    if (action == 'pin') {
      await _togglePin(item);
    } else if (action == 'delete') {
      await _confirmAndDelete(item);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = widget.clock();
    final sorted = sortDdays(_items, _sortMode, today: now);

    return Scaffold(
      appBar: AppBar(
        title: const Text('D-Day Before'),
        actions: [
          PopupMenuButton<ThemeMode>(
            key: const Key('theme_menu_button'),
            tooltip: '外觀主題',
            icon: Icon(
              switch (widget.themeMode) {
                ThemeMode.light => Icons.light_mode_outlined,
                ThemeMode.dark => Icons.dark_mode_outlined,
                ThemeMode.system => Icons.brightness_auto_outlined,
              },
            ),
            initialValue: widget.themeMode,
            onSelected: (mode) {
              widget.onThemeModeChanged?.call(mode);
            },
            itemBuilder: (context) => [
              (ThemeMode.system, '跟隨系統', 'system'),
              (ThemeMode.light, '淺色模式', 'light'),
              (ThemeMode.dark, '深色模式', 'dark'),
            ]
                .map(
                  (entry) => PopupMenuItem<ThemeMode>(
                    key: Key('theme_option_${entry.$3}'),
                    value: entry.$1,
                    child: Row(
                      children: [
                        Icon(
                          widget.themeMode == entry.$1 ? Icons.check : null,
                          size: 18,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(entry.$2),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
          IconButton(
            key: const Key('backup_button'),
            tooltip: '備份與還原',
            icon: const Icon(Icons.import_export),
            onPressed: _openBackup,
          ),
          PopupMenuButton<DdaySortMode>(
            key: const Key('sort_menu_button'),
            tooltip: '排序方式',
            icon: const Icon(Icons.sort),
            initialValue: _sortMode,
            onSelected: _changeSortMode,
            itemBuilder: (context) => DdaySortMode.values
                .map(
                  (mode) => PopupMenuItem<DdaySortMode>(
                    key: Key('sort_option_${mode.storageKey}'),
                    value: mode,
                    child: Row(
                      children: [
                        Icon(
                          _sortMode == mode ? Icons.check : null,
                          size: 18,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(mode.label),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : sorted.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.event_note_outlined,
                            size: 64,
                            color: theme.colorScheme.outline,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '還沒有 D-Day',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '點擊右下角 ＋ 新增第一個重要日子',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                    itemCount: sorted.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = sorted[index];
                      final badge = formatCountdown(item, today: now);
                      final diff = effectiveDayDiff(item, today: now);
                      final isToday = diff == 0 && !item.countFromOne;
                      final displayDate = formatDisplayDateZh(
                        effectiveTargetDate(item, today: now),
                      );
                      final repeatNote = anniversarySubtitle(item, today: now);
                      final colors = DdayColors.byKey(item.colorKey).resolve(
                        theme.colorScheme,
                        isPinned: item.pinned,
                        isToday: isToday,
                      );

                      return Card(
                        key: Key('dday_card_${item.id}'),
                        elevation: 0,
                        color: colors.cardBackground,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: colors.borderColor),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => _openEditor(item),
                          onLongPress: () => _showItemActions(item),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            child: Row(
                              children: [
                                if (item.colorKey != null) ...[
                                  Container(
                                    width: 4,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: colors.accentColor,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                ],
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          if (item.pinned) ...[
                                            Icon(
                                              Icons.push_pin,
                                              size: 16,
                                              color: colors.accentColor,
                                            ),
                                            const SizedBox(width: 6),
                                          ],
                                          Expanded(
                                            child: Text(
                                              item.title,
                                              style: theme.textTheme.titleMedium
                                                  ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          if (item.repeatYearly) ...[
                                            Icon(
                                              Icons.repeat,
                                              size: 14,
                                              color: colors.accentColor,
                                            ),
                                            const SizedBox(width: 4),
                                          ],
                                          Flexible(
                                            child: Text(
                                              repeatNote == null
                                                  ? displayDate
                                                  : '$displayDate・$repeatNote',
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                color: theme.colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colors.badgeBackground,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    badge,
                                    style:
                                        theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: colors.badgeForeground,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('fab_add'),
        tooltip: '新增 D-Day',
        onPressed: () => _openEditor(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
