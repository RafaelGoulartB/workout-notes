import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/widgets/run/run_plan_ui.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// "Today's workout": the session the running plan scheduled for today, one
/// tap away from being attached to this run.
class RunTodayWorkoutCard extends StatelessWidget {
  final RunPlanWorkout workout;
  final VoidCallback onUse;

  const RunTodayWorkoutCard({
    super.key,
    required this.workout,
    required this.onUse,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final colors = theme.colorScheme;
    final tint = RunPlanUi.kindColor(colors, workout.kind);
    return AppSectionCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      color: tint.withAlpha(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppIconBadge(RunPlanUi.kindIcon(workout.kind), color: tint),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loc.runRecordTodayWorkout.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      workout.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${RunPlanUi.kindLabel(loc, workout.kind)} · ${RunPlanUi.sessionSummary(loc, workout)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            key: const ValueKey('run-use-today-workout'),
            onPressed: onUse,
            icon: const Icon(Icons.playlist_add_check_rounded, size: 20),
            label: Text(loc.runRecordTodayUse),
          ),
        ],
      ),
    );
  }
}
