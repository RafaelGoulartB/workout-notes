import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';

/// Cancel / confirm dialog. Resolves to `true` only when the user confirms;
/// cancelling, tapping outside or the back button all resolve to `false`.
///
/// [destructive] paints the confirm button with the error colours (delete,
/// discard, wipe). [cancelLabel] defaults to the localised "Cancel".
Future<bool> showConfirmDialog(
  BuildContext context, {
  String? title,
  String? message,
  required String confirmLabel,
  String? cancelLabel,
  bool destructive = false,
  IconData? icon,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final colors = Theme.of(dialogContext).colorScheme;
      return AlertDialog(
        icon: icon == null ? null : Icon(icon),
        title: title == null ? null : Text(title),
        content: message == null ? null : Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              cancelLabel ?? AppLocalizations.of(dialogContext)!.commonCancel,
            ),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: colors.error,
                    foregroundColor: colors.onError,
                  )
                : null,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return result ?? false;
}
