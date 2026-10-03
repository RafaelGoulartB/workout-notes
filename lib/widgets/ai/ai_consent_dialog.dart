import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';

/// Asks, before the first message, whether the coach may send the user's
/// messages, images and the data it reads to [providerName]. Resolves to true
/// only when the user agrees.
Future<bool> showAiConsentDialog(
  BuildContext context, {
  String? providerName,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final l10n = AppLocalizations.of(dialogContext)!;
      final name = (providerName == null || providerName.trim().isEmpty)
          ? l10n.aiConsentProviderFallback
          : providerName.trim();
      return AlertDialog(
        icon: const Icon(Icons.shield_outlined),
        title: Text(l10n.aiConsentTitle(name)),
        content: SingleChildScrollView(child: Text(l10n.aiConsentBody(name))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.aiConsentAccept),
          ),
        ],
      );
    },
  );
  return result ?? false;
}
