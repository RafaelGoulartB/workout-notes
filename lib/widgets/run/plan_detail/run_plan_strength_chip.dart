import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';

/// Runner strength suggested on a day: start it, or see it done.
class RunPlanStrengthChip extends StatelessWidget {
  final String label;
  final bool done;
  final VoidCallback onStart;

  const RunPlanStrengthChip({
    super.key,
    required this.label,
    required this.done,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.surfaceContainerHighest.withAlpha(90),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: done ? null : onStart,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.fitness_center_rounded,
                  size: 18,
                  color: scheme.secondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    loc.runPlanStrengthRow(label),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                if (done)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle,
                        size: 16,
                        color: scheme.tertiary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        loc.runPlanStrengthDone,
                        style: theme.textTheme.labelMedium,
                      ),
                    ],
                  )
                else
                  Text(
                    loc.runPlanStrengthStart,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.primary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
