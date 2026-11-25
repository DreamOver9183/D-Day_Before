import 'package:flutter/material.dart';

import '../models/dday.dart';
import '../utils/day_calc.dart';

sealed class EditResult {
  const EditResult();
}

class EditSaveResult extends EditResult {
  const EditSaveResult(this.item);
  final DdayItem item;
}

class EditDeleteResult extends EditResult {
  const EditDeleteResult(this.id);
  final String id;
}

class EditScreen extends StatefulWidget {
  const EditScreen({
    super.key,
    this.initialItem,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  final DdayItem? initialItem;
  final DateTime Function() clock;

  @override
  State<EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends State<EditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late DateTime _selectedDate;
  late bool _countFromOne;

  late final String _initialTitle;
  late final String _initialDateIso;
  late final bool _initialCountFromOne;

  bool _allowPop = false;

  bool get _isEditing => widget.initialItem != null;

  @override
  void initState() {
    super.initState();
    final item = widget.initialItem;
    if (item != null) {
      _initialTitle = item.title;
      _initialDateIso = item.date;
      _initialCountFromOne = item.countFromOne;
      _selectedDate = parseIsoDate(item.date);
    } else {
      _initialTitle = '';
      final today = localToday(widget.clock());
      _initialDateIso = formatIsoDate(today);
      _initialCountFromOne = false;
      _selectedDate = today;
    }
    _titleController = TextEditingController(text: _initialTitle);
    _titleController.addListener(_onFormChanged);
    _countFromOne = _initialCountFromOne;
  }

  @override
  void dispose() {
    _titleController.removeListener(_onFormChanged);
    _titleController.dispose();
    super.dispose();
  }

  void _onFormChanged() {
    setState(() {});
  }

  bool get _hasUnsavedChanges {
    return _titleController.text.trim() != _initialTitle ||
        formatIsoDate(_selectedDate) != _initialDateIso ||
        _countFromOne != _initialCountFromOne;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
      ),
      firstDate: DateTime(1900, 1, 1),
      lastDate: DateTime(2100, 12, 31),
      locale: const Locale('zh', 'TW'),
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedDate = DateTime.utc(picked.year, picked.month, picked.day);
      });
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final title = _titleController.text.trim();
    final isoDate = formatIsoDate(_selectedDate);

    final resultItem = widget.initialItem != null
        ? widget.initialItem!.copyWith(
            title: title,
            date: isoDate,
            countFromOne: _countFromOne,
          )
        : DdayItem.create(
            title: title,
            date: isoDate,
            countFromOne: _countFromOne,
            now: widget.clock(),
          );

    _allowPop = true;
    Navigator.of(context).pop(EditSaveResult(resultItem));
  }

  Future<void> _confirmDelete() async {
    final item = widget.initialItem;
    if (item == null) return;

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
      _allowPop = true;
      Navigator.of(context).pop(EditDeleteResult(item.id));
    }
  }

  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('捨棄修改？'),
        content: const Text('您有尚未儲存的變更，確定要離開嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('繼續編輯'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('捨棄'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      setState(() {
        _allowPop = true;
      });
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = widget.clock();
    final isoDate = formatIsoDate(_selectedDate);
    final previewBadge = formatCountdownFromValues(
      date: isoDate,
      countFromOne: _countFromOne,
      today: now,
    );
    final previewTitle = _titleController.text.trim().isEmpty
        ? '（未命名項目）'
        : _titleController.text.trim();

    return PopScope(
      canPop: _allowPop || !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _hasUnsavedChanges) {
          _confirmDiscard();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEditing ? '編輯 D-Day' : '新增 D-Day'),
          actions: [
            if (_isEditing)
              IconButton(
                key: const Key('edit_delete_button'),
                tooltip: '刪除',
                onPressed: _confirmDelete,
                icon: const Icon(Icons.delete_outline),
              ),
          ],
        ),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '即時預覽',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                previewTitle,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                formatDisplayDateZh(_selectedDate),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          previewBadge,
                          key: const Key('edit_preview_badge'),
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  key: const Key('title_field'),
                  controller: _titleController,
                  maxLength: 50,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: '標題',
                    hintText: '例如：期末考、交往紀念日',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '請輸入標題';
                    }
                    if (value.trim().length > 50) {
                      return '標題最多 50 個字';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                  child: ListTile(
                    key: const Key('date_picker_tile'),
                    leading: const Icon(Icons.calendar_today_outlined),
                    title: const Text('目標日期'),
                    subtitle: Text(formatDisplayDateZh(_selectedDate)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _pickDate,
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                  child: SwitchListTile(
                    key: const Key('count_from_one_switch'),
                    title: const Text('當天算第 1 天'),
                    subtitle: const Text('紀念日模式：起始日當天顯示第 1 天'),
                    value: _countFromOne,
                    onChanged: (value) {
                      setState(() {
                        _countFromOne = value;
                      });
                    },
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  key: const Key('save_button'),
                  onPressed: _save,
                  icon: const Icon(Icons.check),
                  label: const Text('儲存'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
