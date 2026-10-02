import 'package:flutter/material.dart';

/// Shows [message] in a snack bar, replacing any snack bar still on screen.
///
/// Does nothing when [context] is no longer mounted, so it is safe to call
/// after an `await`. Pass [action] for an inline "Undo" style button.
void showAppSnack(
  BuildContext context,
  String message, {
  SnackBarAction? action,
}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), action: action));
}
