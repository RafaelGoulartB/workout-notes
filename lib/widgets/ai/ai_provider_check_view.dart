import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/ai_provider.dart';
import 'package:workout_notes/utils/ai_error_localizer.dart';

/// What a connection test found: works or not, whether the model can call
/// tools (the coach needs them to read data), whether answers stream, and the
/// latency. A failure shows its localized reason.
class AiProviderCheckView extends StatelessWidget {
  final AiProviderCheck check;

  const AiProviderCheckView({super.key, required this.check});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final rows = <(IconData, Color, String)>[
      if (check.ok) ...[
        (
          check.toolsSupported
              ? Icons.check_circle_outline_rounded
              : Icons.warning_amber_rounded,
          check.toolsSupported ? colors.primary : colors.tertiary,
          check.toolsSupported
              ? l10n.aiSettingsCheckTools
              : l10n.aiSettingsCheckNoTools,
        ),
        (
          check.streamingSupported
              ? Icons.check_circle_outline_rounded
              : Icons.info_outline_rounded,
          check.streamingSupported ? colors.primary : colors.outline,
          check.streamingSupported
              ? l10n.aiSettingsCheckStreaming
              : l10n.aiSettingsCheckNoStreaming,
        ),
      ] else
        (
          Icons.error_outline_rounded,
          colors.error,
          localizeAiError(check.errorCode, l10n),
        ),
    ];

    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: check.ok
              ? colors.primaryContainer.withAlpha(90)
              : colors.errorContainer.withAlpha(150),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              check.ok ? l10n.aiSettingsCheckOk : l10n.aiSettingsCheckFailed,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            for (final (icon, color, text) in rows)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 16, color: color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(text, style: theme.textTheme.bodySmall),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            Text(
              [
                if (check.model.isNotEmpty)
                  l10n.aiSettingsCheckModel(check.model),
                if (check.ok) l10n.aiSettingsCheckLatency(check.latencyMs),
              ].join(' · '),
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
