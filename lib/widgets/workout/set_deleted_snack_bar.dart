import 'dart:async';

import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';

/// Shows "Set deleted" with an Undo action. [onUndo] runs when the user taps
/// Undo; it may outlive the screen, so it must check `mounted` itself.
/// Pass [messenger] when the screen hosts its own [ScaffoldMessenger].
void showSetDeletedSnackBar(
  BuildContext context, {
  required Future<void> Function() onUndo,
  ScaffoldMessengerState? messenger,
}) {
  final loc = AppLocalizations.of(context)!;
  messenger ??= ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: Text(loc.workoutSetDeleted),
      behavior: SnackBarBehavior.floating,
      action: SnackBarAction(
        label: loc.commonUndo,
        onPressed: () => unawaited(onUndo()),
      ),
    ),
  );
}
