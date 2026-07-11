import 'package:flutter/material.dart';

import '../../screens/workout/ai_settings_screen.dart';
import '../../navigation/ai_coach_navigation.dart';
import '../../l10n/app_localizations.dart';

class AiEmptyState extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const AiEmptyState({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon = Icons.smart_toy_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 80,
              color: theme.colorScheme.primary.withAlpha(80),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      AiCoachNavigation.route(
                        kind: AiCoachRouteKind.aiFlow,
                        builder: (_) => const AiSettingsScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.settings_rounded),
                  label: Text(l10n.aiEmptyConfigure),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
