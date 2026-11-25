import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/backup_service.dart';
import '../data/dday_store.dart';
import '../models/dday.dart';
import '../services/native_bridge.dart';
import '../theme/dday_colors.dart';
import '../utils/day_calc.dart';
import '../utils/dday_sorter.dart';
import '../widgets/dday_card.dart';
import '../widgets/dialogs.dart';
import 'backup_screen.dart';
import 'edit_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.store,
    this.backupService = const BackupService(),
    this.fileChannel = const MethodChannelBackupFileChannel(),
    this.nativeBridge = const MethodChannelNativeBridge(),
    this.themeMode = ThemeMode.system,
    this.onThemeModeChanged,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  final DdayStore store;
  final BackupService backupService;
  final BackupFileChannel fileChannel;
  final NativeBridge nativeBridge;
  final ThemeMode themeMode;
  final Future<void> Function(ThemeMode mode)? onThemeModeChanged;
  final DateTime Function() clock;

  /// How many times the sorted card list has been (re)computed. Tests use it
  /// to check that unrelated rebuilds reuse the cache.
  @visibleForTesting
  static int debugViewModelBuildCount = 0;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  List<DdayItem> _items = <DdayItem>[];

  /// Last list known to be on disk; restored when the newest write fails.
  List<DdayItem> _lastPersistedItems = <DdayItem>[];
  DdaySortMode _sortMode = DdaySortMode.nearest;
  bool _loading = true;
  String? _recoveryRaw;
  Timer? _midnightTimer;

  // Serialized writes.
  Future<void> _writeChain = Future<void>.value();
  int _writeSeq = 0;

  // Native sync re-entrancy guard.
  bool _syncing = false;
  bool _syncAgain = false;

  // Sorted view-model cache.
  List<DdayCardData>? _cache;
  List<DdayItem>? _cacheItems;
  DdaySortMode? _cacheSortMode;
  DateTime? _cacheDay;

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
    if (state != AppLifecycleState.resumed || !mounted) return;
    // A changed day is picked up by the cache check in build().
    setState(() {});
    _scheduleMidnightRefresh();
    _syncNativeBestEffort();
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
      _syncNativeBestEffort();
    });
  }

  Future<void> _loadInitial() async {
    final results = await Future.wait<Object>([
      widget.store.loadItemsDetailed(),
      widget.store.loadSortMode(),
    ]);
    if (!mounted) return;
    final loaded = results[0] as LoadItemsResult;
    setState(() {
      _items = loaded.items;
      _lastPersistedItems = loaded.items;
      _recoveryRaw = loaded.recoveryRaw;
      _sortMode = results[1] as DdaySortMode;
      _loading = false;
    });
    _syncNativeBestEffort();
  }

  /// Pushes current data to notifications and home widgets. Never throws;
  /// overlapping calls collapse into one extra run.
  Future<void> _syncNativeBestEffort() async {
    if (_syncing) {
      _syncAgain = true;
      return;
    }
    _syncing = true;
    try {
      do {
        _syncAgain = false;
        try {
          await widget.nativeBridge.syncNotifications();
        } catch (e) {
          debugPrint('syncNotifications failed: $e');
        }
        try {
          await widget.nativeBridge.refreshWidgets();
        } catch (e) {
          debugPrint('refreshWidgets failed: $e');
        }
      } while (_syncAgain && mounted);
    } finally {
      _syncing = false;
    }
  }

  /// Shows [updated] immediately and saves it after any earlier writes.
  ///
  /// Returns whether this write reached disk. If the newest write fails the
  /// list falls back to the last saved state and a single SnackBar is shown;
  /// failures of writes that were already superseded are left to the newer
  /// write, which saves the complete list again.
  Future<bool> _persistItems(List<DdayItem> updated) async {
    final seq = ++_writeSeq;
    setState(() {
      _items = updated;
    });

    final done = Completer<bool>();
    _writeChain = _writeChain.then((_) async {
      var ok = false;
      try {
        await widget.store.saveItems(updated);
        ok = true;
      } catch (e) {
        debugPrint('saveItems failed: $e');
      }
      if (ok) {
        _lastPersistedItems = updated;
      } else if (seq == _writeSeq && mounted) {
        setState(() {
          _items = _lastPersistedItems;
        });
        showAppSnackBar(context, storageWriteFailedMessage);
      }
      done.complete(ok);
    });

    final ok = await done.future;
    if (ok) {
      unawaited(_syncNativeBestEffort());
    }
    return ok;
  }

  Future<void> _changeSortMode(DdaySortMode mode) async {
    if (_sortMode == mode) return;
    final previous = _sortMode;
    setState(() {
      _sortMode = mode;
    });
    try {
      await widget.store.saveSortMode(mode);
    } on StorageWriteException {
      if (!mounted) return;
      setState(() {
        _sortMode = previous;
      });
      showAppSnackBar(context, storageWriteFailedMessage);
      return;
    }
    unawaited(_syncNativeBestEffort());
  }

  Future<void> _copyRecoveryRaw() async {
    final raw = _recoveryRaw;
    if (raw == null) return;
    await Clipboard.setData(ClipboardData(text: raw));
    if (!mounted) return;
    showAppSnackBar(context, '已複製原始內容，可貼到記事本保存');
  }

  Future<void> _acknowledgeRecovery() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除另存的原始內容？'),
        content: const Text('清除後將無法再取回原始內容，確定已保存？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('recovery_confirm_clear'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('確定清除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // Rewrite the readable items first so the damaged text is gone from the
    // main key; otherwise the next launch would flag it again.
    final saved = await _persistItems(_items);
    if (!saved || !mounted) return;
    try {
      await widget.store.clearRecoveryRaw();
    } on StorageWriteException {
      if (!mounted) return;
      showAppSnackBar(context, storageWriteFailedMessage);
      return;
    }
    if (!mounted) return;
    setState(() {
      _recoveryRaw = null;
    });
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          store: widget.store,
          nativeBridge: widget.nativeBridge,
          themeMode: widget.themeMode,
          onThemeModeChanged: widget.onThemeModeChanged ?? (_) async {},
          currentItems: _items,
          sortMode: _sortMode,
          onSaveItems: _persistItems,
          backupService: widget.backupService,
          fileChannel: widget.fileChannel,
          clock: widget.clock,
        ),
      ),
    );
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
    final confirmed = await showDeleteConfirmDialog(context, item.title);
    if (confirmed && mounted) {
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

  /// Sorted card data, recomputed only when items, sort mode or day change.
  List<DdayCardData> _viewModels(DateTime now) {
    final day = localToday(now);
    final cached = _cache;
    if (cached != null &&
        identical(_cacheItems, _items) &&
        _cacheSortMode == _sortMode &&
        _cacheDay == day) {
      return cached;
    }
    HomeScreen.debugViewModelBuildCount++;
    final sorted = sortDdays(_items, _sortMode, today: day);
    final models = <DdayCardData>[
      for (final item in sorted) DdayCardData.fromItem(item, day),
    ];
    _cache = models;
    _cacheItems = _items;
    _cacheSortMode = _sortMode;
    _cacheDay = day;
    return models;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final models = _viewModels(widget.clock());

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
          IconButton(
            key: const Key('settings_button'),
            tooltip: '設定',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
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
            : Column(
                children: [
                  if (_recoveryRaw != null) _buildRecoveryBanner(),
                  Expanded(
                    child: models.isEmpty
                        ? _buildEmptyState(theme)
                        : _buildList(theme, models),
                  ),
                ],
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

  Widget _buildRecoveryBanner() {
    return MaterialBanner(
      key: const Key('recovery_banner'),
      leading: const Icon(Icons.warning_amber_rounded),
      content: const Text('有資料讀取失敗，原始內容已另存。'),
      actions: [
        TextButton(
          key: const Key('recovery_copy'),
          onPressed: _copyRecoveryRaw,
          child: const Text('複製原始內容'),
        ),
        TextButton(
          key: const Key('recovery_dismiss'),
          onPressed: _acknowledgeRecovery,
          child: const Text('知道了'),
        ),
      ],
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
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
    );
  }

  Widget _buildList(ThemeData theme, List<DdayCardData> models) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      itemCount: models.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final model = models[index];
        final item = model.item;
        final colors = DdayColors.byKey(item.colorKey).resolve(
          theme.colorScheme,
          isPinned: item.pinned,
          isToday: model.isToday,
        );
        return DdayCard(
          key: Key('dday_card_${item.id}'),
          variant: DdayCardVariant.list,
          title: item.title,
          subtitle: model.subtitle,
          badge: model.badge,
          colors: colors,
          pinned: item.pinned,
          showAccentBar: item.colorKey != null,
          repeatYearly: item.repeatYearly,
          hasReminders: item.reminderDaysBefore.isNotEmpty,
          onTap: () => _openEditor(item),
          onLongPress: () => _showItemActions(item),
        );
      },
    );
  }
}
