import 'dart:async';

import 'package:flutter/material.dart';

import '../data/dday_store.dart';
import '../models/dday.dart';
import '../utils/day_calc.dart';
import '../utils/dday_sorter.dart';
import 'edit_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.store,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  final DdayStore store;
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
                      final diff = dayDiff(item.date, today: now);
                      final isToday = diff == 0 && !item.countFromOne;

                      return Card(
                        key: Key('dday_card_${item.id}'),
                        elevation: 0,
                        color: theme.colorScheme.surfaceContainerLow,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: item.pinned
                                ? theme.colorScheme.primary.withValues(alpha: 0.45)
                                : theme.colorScheme.outlineVariant,
                          ),
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
                                              color: theme.colorScheme.primary,
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
                                      Text(
                                        formatDisplayIsoDateZh(item.date),
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                          color: theme
                                              .colorScheme.onSurfaceVariant,
                                        ),
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
                                    color: isToday
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    badge,
                                    style:
                                        theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: isToday
                                          ? theme.colorScheme.onPrimary
                                          : theme.colorScheme
                                              .onPrimaryContainer,
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
