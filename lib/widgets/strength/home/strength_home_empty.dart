import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';

/// Shown to lifters without a single finished gym workout.
class StrengthHomeEmpty extends StatelessWidget {
  final VoidCallback onStartWorkout;
  final VoidCallback onCreateRoutine;

  const StrengthHomeEmpty({
    super.key,
    required this.onStartWorkout,
    required this.onCreateRoutine,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return RunSectionCard(
      child: Column(
        children: [
          const Icon(Icons.fitness_center, size: 48),
          const SizedBox(height: 12),
          Text(
            loc.strengthHomeEmptyTitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            loc.strengthHomeEmptySubtitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton(
            key: const Key('strength-empty-start'),
            onPressed: onStartWorkout,
            child: Text(loc.strengthHomeBlankWorkout),
          ),
          const SizedBox(height: 4),
          TextButton(
            key: const Key('strength-empty-routine'),
            onPressed: onCreateRoutine,
            child: Text(loc.strengthHomeCreateRoutine),
          ),
        ],
      ),
    );
  }
}
