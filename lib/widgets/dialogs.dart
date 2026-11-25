import 'package:flutter/material.dart';

/// Asks the user to confirm deleting the D-Day titled [title].
/// Returns true only when the user pressed 刪除.
Future<bool> showDeleteConfirmDialog(BuildContext context, String title) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      return AlertDialog(
        title: const Text('刪除 D-Day'),
        content: Text('確定要刪除「$title」嗎？此動作無法復原。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            child: const Text('刪除'),
          ),
        ],
      );
    },
  );
  return confirmed == true;
}

/// Shows a short message, replacing any SnackBar currently visible.
void showAppSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Message shown whenever a local write fails.
const String storageWriteFailedMessage = '儲存失敗，請再試一次';
