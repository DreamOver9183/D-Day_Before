import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/dday.dart';

enum BackupImportMode { merge, overwrite }

class BackupFormatException implements Exception {
  const BackupFormatException(this.message);
  final String message;

  @override
  String toString() => message;
}

class ParsedBackup {
  const ParsedBackup({
    required this.schemaVersion,
    required this.items,
    required this.skippedCount,
  });

  final int schemaVersion;
  final List<DdayItem> items;
  final int skippedCount;
}

class BackupApplyResult {
  const BackupApplyResult({
    required this.items,
    required this.added,
    required this.updated,
    required this.total,
  });

  final List<DdayItem> items;
  final int added;
  final int updated;
  final int total;
}

abstract class BackupFileChannel {
  Future<bool> exportJsonFile(String filename, String content);
  Future<String?> importJsonFile();
}

class MethodChannelBackupFileChannel implements BackupFileChannel {
  const MethodChannelBackupFileChannel();

  static const MethodChannel _channel = MethodChannel(
    'com.cytsa.dday_before/native',
  );

  @override
  Future<bool> exportJsonFile(String filename, String content) async {
    final result = await _channel.invokeMethod<bool>(
      'exportJsonFile',
      <String, dynamic>{'filename': filename, 'content': content},
    );
    return result ?? false;
  }

  @override
  Future<String?> importJsonFile() {
    return _channel.invokeMethod<String>('importJsonFile');
  }
}

class BackupService {
  const BackupService();

  static const int supportedSchemaVersion = 1;

  String exportJson(List<DdayItem> items, {DateTime? exportedAt}) {
    final payload = <String, dynamic>{
      'schemaVersion': supportedSchemaVersion,
      'exportedAt': (exportedAt ?? DateTime.now()).toUtc().toIso8601String(),
      'items': items.map((e) => e.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  ParsedBackup parseBackupJson(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw const BackupFormatException('備份內容為空');
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(trimmed);
    } catch (_) {
      throw const BackupFormatException('JSON 格式無效，請確認內容完整');
    }

    if (decoded is! Map) {
      throw const BackupFormatException('備份格式錯誤：最外層必須為 JSON 物件');
    }

    final version = decoded['schemaVersion'];
    if (version is! int) {
      throw const BackupFormatException('備份缺少有效的 schemaVersion');
    }
    if (version != supportedSchemaVersion) {
      throw BackupFormatException('不支援的備份版本：$version');
    }

    final rawItems = decoded['items'];
    if (rawItems is! List) {
      throw const BackupFormatException('備份缺少有效的 items 清單');
    }

    final parsed = <DdayItem>[];
    var skipped = 0;
    for (final entry in rawItems) {
      final item = DdayItem.tryFromJson(entry);
      if (item != null) {
        parsed.add(item);
      } else {
        skipped++;
      }
    }

    return ParsedBackup(
      schemaVersion: version,
      items: parsed,
      skippedCount: skipped,
    );
  }

  BackupApplyResult applyImport(
    List<DdayItem> existing,
    List<DdayItem> incoming,
    BackupImportMode mode,
  ) {
    if (mode == BackupImportMode.overwrite) {
      final byId = <String, DdayItem>{};
      for (final item in incoming) {
        byId[item.id] = item;
      }
      final list = byId.values.toList();
      return BackupApplyResult(
        items: list,
        added: list.length,
        updated: 0,
        total: list.length,
      );
    }

    final result = List<DdayItem>.from(existing);
    final indexById = <String, int>{
      for (var i = 0; i < result.length; i++) result[i].id: i,
    };

    var added = 0;
    var updated = 0;
    for (final item in incoming) {
      final idx = indexById[item.id];
      if (idx != null) {
        result[idx] = item;
        updated++;
      } else {
        indexById[item.id] = result.length;
        result.add(item);
        added++;
      }
    }

    return BackupApplyResult(
      items: result,
      added: added,
      updated: updated,
      total: result.length,
    );
  }
}
