import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';

/// Shown instead of an empty state when a screen could not read its data, so
/// a failed read never looks like "no records yet".
class LoadErrorView extends StatelessWidget {
  final VoidCallback onRetry;

  /// Defaults to the generic "could not load your data" text.
  final String? message;

  const LoadErrorView({super.key, required this.onRetry, this.message});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 48, color: colors.outline),
            const SizedBox(height: 16),
            Text(
              message ?? loc.commonLoadError,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              key: const Key('load-error-retry'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(loc.commonRetry),
            ),
          ],
        ),
      ),
    );
  }
}

/// A discreet strip above content that is still on screen from an earlier
/// load: the refresh failed, the data shown is stale.
class LoadErrorBanner extends StatelessWidget {
  final VoidCallback onRetry;
  final String? message;

  const LoadErrorBanner({super.key, required this.onRetry, this.message});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Material(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
          child: Row(
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 18,
                color: colors.onErrorContainer,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message ?? loc.commonRefreshFailed,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onErrorContainer,
                  ),
                ),
              ),
              TextButton(
                key: const Key('load-error-banner-retry'),
                onPressed: onRetry,
                child: Text(loc.commonRetry),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
