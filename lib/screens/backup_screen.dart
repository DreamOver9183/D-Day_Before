import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/backup_service.dart';
import '../models/dday.dart';
import '../utils/day_calc.dart';
import '../widgets/soft_card.dart';
import '../widgets/section_header.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({
    super.key,
    required this.initialItems,
    required this.onSaveItems,
    this.backupService = const BackupService(),
    this.fileChannel = const MethodChannelBackupFileChannel(),
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  final List<DdayItem> initialItems;
  final Future<bool> Function(List<DdayItem> items) onSaveItems;
  final BackupService backupService;
  final BackupFileChannel fileChannel;
  final DateTime Function() clock;

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  late List<DdayItem> _items;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _items = List<DdayItem>.from(widget.initialItems);
  }

  String _defaultBackupFilename() {
    final date = formatIsoDate(localToday(widget.clock()));
    return 'dday_before_backup_$date.json';
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _exportToFile() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final json = widget.backupService.exportJson(
        _items,
        exportedAt: widget.clock(),
      );
      final saved = await widget.fileChannel.exportJsonFile(
        _defaultBackupFilename(),
        json,
      );
      if (saved) {
        _showSnack('已匯出 ${_items.length} 筆資料');
      }
    } catch (e) {
      _showSnack('匯出失敗：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyToClipboard() async {
    final json = widget.backupService.exportJson(
      _items,
      exportedAt: widget.clock(),
    );
    await Clipboard.setData(ClipboardData(text: json));
    _showSnack('已複製備份 JSON（共 ${_items.length} 筆）');
  }

  Future<void> _importFromFile() async {
    if (_busy) return;
    setState(() => _busy = true);
    String? raw;
    try {
      raw = await widget.fileChannel.importJsonFile();
    } catch (e) {
      _showSnack('讀取檔案失敗：$e');
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }

    if (raw == null || !mounted) return;
    await _handleRawImport(raw);
  }

  Future<void> _importFromPaste() async {
    final raw = await showDialog<String>(
      context: context,
      builder: (_) => const _PasteBackupDialog(),
    );

    if (raw == null || !mounted) return;
    await _handleRawImport(raw);
  }

  Future<void> _handleRawImport(String raw) async {
    final ParsedBackup parsed;
    try {
      parsed = widget.backupService.parseBackupJson(raw);
    } on BackupFormatException catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('無法匯入備份'),
          content: Text(e.message),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('確定'),
            ),
          ],
        ),
      );
      return;
    }

    if (!mounted) return;
    final skippedNote = parsed.skippedCount > 0
        ? '\n（已略過 ${parsed.skippedCount} 筆格式不完整的資料）'
        : '';

    final mode = await showDialog<BackupImportMode>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('選擇匯入方式'),
        content: Text(
          '共讀取到 ${parsed.items.length} 筆 D-Day 資料$skippedNote。\n\n'
          '• 合併匯入：保留現有資料，新增或更新同 ID 項目\n'
          '• 覆蓋全部：清除現有資料，完全以備份取代',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          OutlinedButton(
            key: const Key('import_mode_overwrite'),
            onPressed: () =>
                Navigator.of(context).pop(BackupImportMode.overwrite),
            child: const Text('覆蓋全部'),
          ),
          FilledButton(
            key: const Key('import_mode_merge'),
            onPressed: () => Navigator.of(context).pop(BackupImportMode.merge),
            child: const Text('合併匯入'),
          ),
        ],
      ),
    );

    if (mode == null || !mounted) return;

    final applied = widget.backupService.applyImport(
      _items,
      parsed.items,
      mode,
    );
    // On failure the home screen already restored its list and told the user.
    final saved = await widget.onSaveItems(applied.items);
    if (!saved || !mounted) return;

    setState(() {
      _items = applied.items;
    });

    if (mode == BackupImportMode.overwrite) {
      _showSnack('已覆蓋還原 ${applied.total} 筆資料');
    } else {
      _showSnack(
        '匯入完成：新增 ${applied.added} 筆、更新 ${applied.updated} 筆（共 ${applied.total} 筆）',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('備份與還原')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerHighest,
              child: ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: Text('目前共有 ${_items.length} 筆 D-Day'),
              ),
            ),
            const SizedBox(height: 20),
            const SectionHeader('匯出備份'),
            const SizedBox(height: 8),
            SoftCard(
              child: Column(
                children: [
                  ListTile(
                    key: const Key('export_file_button'),
                    leading: const Icon(Icons.save_alt),
                    title: const Text('匯出至檔案 (.json)'),
                    onTap: _busy ? null : _exportToFile,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    key: const Key('export_clipboard_button'),
                    leading: const Icon(Icons.copy_all_outlined),
                    title: const Text('複製備份 JSON'),
                    onTap: _busy ? null : _copyToClipboard,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const SectionHeader('匯入還原'),
            const SizedBox(height: 8),
            SoftCard(
              child: Column(
                children: [
                  ListTile(
                    key: const Key('import_file_button'),
                    leading: const Icon(Icons.file_open_outlined),
                    title: const Text('從檔案匯入 (.json)'),
                    onTap: _busy ? null : _importFromFile,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    key: const Key('import_paste_button'),
                    leading: const Icon(Icons.paste_outlined),
                    title: const Text('貼上備份 JSON 匯入'),
                    onTap: _busy ? null : _importFromPaste,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PasteBackupDialog extends StatefulWidget {
  const _PasteBackupDialog();

  @override
  State<_PasteBackupDialog> createState() => _PasteBackupDialogState();
}

class _PasteBackupDialogState extends State<_PasteBackupDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('貼上備份 JSON'),
      content: TextField(
        key: const Key('import_json_field'),
        controller: _controller,
        maxLines: 8,
        minLines: 4,
        decoration: const InputDecoration(
          hintText: '請貼上匯出的 JSON 備份內容',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('import_parse_button'),
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('下一步'),
        ),
      ],
    );
  }
}
