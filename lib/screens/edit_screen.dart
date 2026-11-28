import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/dday.dart';
import '../services/background_images.dart';
import '../services/native_bridge.dart';
import '../theme/dday_colors.dart';
import '../theme/dday_icons.dart';
import '../utils/day_calc.dart';
import '../widgets/soft_card.dart';
import '../widgets/dday_card.dart';
import '../widgets/dialogs.dart';

/// Maximum title length in user-perceived characters (grapheme clusters).
const int maxTitleLength = 50;

/// Validates a D-Day title. Length is counted in characters as the user sees
/// them (an emoji counts as one), matching the text field's counter.
String? validateTitle(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) {
    return '請輸入標題';
  }
  if (trimmed.characters.length > maxTitleLength) {
    return '標題最多 $maxTitleLength 個字';
  }
  return null;
}

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
    this.nativeBridge = const MethodChannelNativeBridge(),
  }) : clock = clock ?? DateTime.now;

  final DdayItem? initialItem;
  final DateTime Function() clock;
  final NativeBridge nativeBridge;

  @override
  State<EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends State<EditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late DateTime _selectedDate;
  late bool _countFromOne;
  late bool _repeatYearly;
  String? _colorKey;
  String? _iconKey;
  String? _backgroundImage;
  bool _pickingPhoto = false;
  late List<int> _reminderDaysBefore;

  late final String _initialTitle;
  late final String _initialDateIso;
  late final bool _initialCountFromOne;
  late final bool _initialRepeatYearly;
  late final String? _initialColorKey;
  late final String? _initialIconKey;
  late final String? _initialBackgroundImage;
  late final List<int> _initialReminderDaysBefore;

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
      _initialRepeatYearly = item.repeatYearly;
      _initialColorKey = item.colorKey;
      _initialIconKey = item.iconKey;
      _initialBackgroundImage = item.backgroundImage;
      _initialReminderDaysBefore = List<int>.from(item.reminderDaysBefore);
      _selectedDate = parseIsoDate(item.date);
    } else {
      _initialTitle = '';
      final today = localToday(widget.clock());
      _initialDateIso = formatIsoDate(today);
      _initialCountFromOne = false;
      _initialRepeatYearly = false;
      _initialColorKey = null;
      _initialIconKey = null;
      _initialBackgroundImage = null;
      _initialReminderDaysBefore = const <int>[];
      _selectedDate = today;
    }
    _titleController = TextEditingController(text: _initialTitle);
    _titleController.addListener(_onFormChanged);
    _countFromOne = _initialCountFromOne;
    _repeatYearly = _initialRepeatYearly;
    _colorKey = _initialColorKey;
    _iconKey = _initialIconKey;
    _backgroundImage = _initialBackgroundImage;
    _reminderDaysBefore = List<int>.from(_initialReminderDaysBefore);
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
    final sortedCurrent = List<int>.from(_reminderDaysBefore)..sort();
    return _titleController.text.trim() != _initialTitle ||
        formatIsoDate(_selectedDate) != _initialDateIso ||
        _countFromOne != _initialCountFromOne ||
        _repeatYearly != _initialRepeatYearly ||
        _colorKey != _initialColorKey ||
        _iconKey != _initialIconKey ||
        _backgroundImage != _initialBackgroundImage ||
        !listEquals(sortedCurrent, _initialReminderDaysBefore);
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
            countFromOne: _repeatYearly ? false : _countFromOne,
            repeatYearly: _repeatYearly,
            colorKey: _colorKey,
            iconKey: _iconKey,
            backgroundImage: _backgroundImage,
            reminderDaysBefore: _reminderDaysBefore,
          )
        : DdayItem.create(
            title: title,
            date: isoDate,
            countFromOne: _repeatYearly ? false : _countFromOne,
            repeatYearly: _repeatYearly,
            colorKey: _colorKey,
            iconKey: _iconKey,
            backgroundImage: _backgroundImage,
            reminderDaysBefore: _reminderDaysBefore,
            now: widget.clock(),
          );

    _allowPop = true;
    Navigator.of(context).pop(EditSaveResult(resultItem));
  }

  Future<void> _pickPhoto() async {
    if (_pickingPhoto) return;
    setState(() => _pickingPhoto = true);
    try {
      final name = await widget.nativeBridge.pickBackgroundImage();
      if (!mounted || name == null) return;
      setState(() => _backgroundImage = name);
    } catch (e) {
      debugPrint('pickBackgroundImage failed: $e');
      if (mounted) {
        showAppSnackBar(context, '無法讀取這張照片，請換一張試試');
      }
    } finally {
      if (mounted) setState(() => _pickingPhoto = false);
    }
  }

  /// The two counting modes are mutually exclusive, so they share one
  /// selector that defaults to off.
  _CountMode get _mode => _repeatYearly
      ? _CountMode.repeatYearly
      : _countFromOne
      ? _CountMode.countFromOne
      : _CountMode.off;

  Widget _buildModeSection(ThemeData theme) {
    return SoftCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('模式設定', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<_CountMode>(
                key: const Key('mode_selector'),
                showSelectedIcon: false,
                segments: const <ButtonSegment<_CountMode>>[
                  ButtonSegment<_CountMode>(
                    value: _CountMode.off,
                    label: Text('關閉', key: Key('mode_off')),
                  ),
                  ButtonSegment<_CountMode>(
                    value: _CountMode.countFromOne,
                    label: Text('紀念日', key: Key('mode_count_from_one')),
                  ),
                  ButtonSegment<_CountMode>(
                    value: _CountMode.repeatYearly,
                    label: Text('每年重複', key: Key('mode_repeat_yearly')),
                  ),
                ],
                selected: <_CountMode>{_mode},
                onSelectionChanged: (selection) {
                  final mode = selection.first;
                  setState(() {
                    _countFromOne = mode == _CountMode.countFromOne;
                    _repeatYearly = mode == _CountMode.repeatYearly;
                  });
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoSection(ThemeData theme) {
    final file = BackgroundImages.fileFor(_backgroundImage);
    final busy = _pickingPhoto
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : null;
    return SoftCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('背景照片', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            if (file == null)
              OutlinedButton.icon(
                key: const Key('pick_background_button'),
                onPressed: _pickingPhoto ? null : _pickPhoto,
                icon: busy ?? const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('選擇照片'),
              )
            else
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 72,
                      height: 48,
                      child: DdayPhoto(
                        file: file,
                        fallbackColor: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          key: const Key('change_background_button'),
                          onPressed: _pickingPhoto ? null : _pickPhoto,
                          child: busy ?? const Text('更換'),
                        ),
                        TextButton(
                          key: const Key('remove_background_button'),
                          onPressed: _pickingPhoto
                              ? null
                              : () => setState(() => _backgroundImage = null),
                          child: const Text('移除'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final item = widget.initialItem;
    if (item == null) return;
    final confirmed = await showDeleteConfirmDialog(context, item.title);
    if (confirmed && mounted) {
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
      repeatYearly: _repeatYearly,
      today: now,
    );
    final previewDisplayDate = _repeatYearly
        ? formatDisplayDateZh(nextYearlyOccurrence(isoDate, today: now))
        : formatDisplayDateZh(_selectedDate);
    final previewTitle = _titleController.text.trim().isEmpty
        ? '（未命名項目）'
        : _titleController.text.trim();
    final resolvedColors = DdayColors.byKey(
      _colorKey,
    ).resolve(theme.colorScheme);

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
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DdayCard(
                    variant: DdayCardVariant.editPreview,
                    title: previewTitle,
                    subtitle: previewDisplayDate,
                    badge: previewBadge,
                    colors: resolvedColors,
                    iconKey: _iconKey,
                    photo: BackgroundImages.fileFor(_backgroundImage),
                    highlighted: previewBadge == 'D-Day',
                    badgeKey: const Key('edit_preview_badge'),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    key: const Key('title_field'),
                    controller: _titleController,
                    maxLength: maxTitleLength,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: '標題',
                      hintText: '例如：期末考、交往紀念日',
                      border: OutlineInputBorder(),
                    ),
                    validator: validateTitle,
                  ),
                  const SizedBox(height: 12),
                  SoftCard(
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
                  _buildModeSection(theme),
                  const SizedBox(height: 12),
                  _buildPhotoSection(theme),
                  const SizedBox(height: 12),
                  SoftCard(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('分類圖示', style: theme.textTheme.titleMedium),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 12,
                            children: DdayIcons.presets.map((preset) {
                              final selected = _iconKey == preset.key;
                              return Semantics(
                                label: '圖示：${preset.label}',
                                selected: selected,
                                button: true,
                                child: InkWell(
                                  key: Key(
                                    'icon_option_${preset.key ?? 'default'}',
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () {
                                    setState(() {
                                      _iconKey = preset.key;
                                    });
                                  },
                                  child: ExcludeSemantics(
                                    child: SizedBox(
                                      width: 56,
                                      child: Column(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(2),
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: selected
                                                    ? resolvedColors.accent
                                                    : Colors.transparent,
                                                width: 2,
                                              ),
                                            ),
                                            child: DdayIconBubble(
                                              iconKey: preset.key,
                                              colors: resolvedColors,
                                              size: 40,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            preset.label,
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                                  color: selected
                                                      ? resolvedColors.accent
                                                      : theme
                                                            .colorScheme
                                                            .onSurfaceVariant,
                                                  fontWeight: selected
                                                      ? FontWeight.bold
                                                      : null,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SoftCard(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('卡片配色', style: theme.textTheme.titleMedium),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: DdayColors.presets.map((preset) {
                              final selected = _colorKey == preset.key;
                              final swatchColor = preset.key == null
                                  ? theme.colorScheme.primary
                                  : preset.accentColor;
                              final checkColor = preset.key == null
                                  ? theme.colorScheme.onPrimary
                                  : Colors.white;
                              return Semantics(
                                label: '配色：${preset.label}',
                                selected: selected,
                                button: true,
                                child: InkWell(
                                  key: Key(
                                    'color_swatch_${preset.key ?? 'default'}',
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                  onTap: () {
                                    setState(() {
                                      _colorKey = preset.key;
                                    });
                                  },
                                  child: Tooltip(
                                    message: preset.label,
                                    child: Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: swatchColor,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: selected
                                              ? theme.colorScheme.onSurface
                                              : theme
                                                    .colorScheme
                                                    .outlineVariant,
                                          width: selected ? 2.5 : 1,
                                        ),
                                      ),
                                      child: selected
                                          ? Icon(
                                              Icons.check,
                                              size: 18,
                                              color: checkColor,
                                            )
                                          : null,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SoftCard(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('提醒通知', style: theme.textTheme.titleMedium),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children:
                                const <(int, String)>[
                                  (0, '當天'),
                                  (1, '前 1 天'),
                                  (3, '前 3 天'),
                                  (7, '前 7 天'),
                                ].map((option) {
                                  final selected = _reminderDaysBefore.contains(
                                    option.$1,
                                  );
                                  return FilterChip(
                                    key: Key('reminder_chip_${option.$1}'),
                                    label: Text(option.$2),
                                    selected: selected,
                                    onSelected: (value) {
                                      setState(() {
                                        if (value) {
                                          _reminderDaysBefore = <int>{
                                            ..._reminderDaysBefore,
                                            option.$1,
                                          }.toList()..sort();
                                        } else {
                                          _reminderDaysBefore =
                                              _reminderDaysBefore
                                                  .where((d) => d != option.$1)
                                                  .toList();
                                        }
                                      });
                                    },
                                  );
                                }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: FilledButton.icon(
              key: const Key('save_button'),
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: const Text('儲存'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _CountMode { off, countFromOne, repeatYearly }
