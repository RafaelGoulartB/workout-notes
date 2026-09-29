import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/widgets/run/run_plan_ui.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';

/// Header card of the session editor: kind, weekday, profile bar and totals.
class RunPlanEditorSummary extends StatelessWidget {
  final RunPlanWorkout workout;

  const RunPlanEditorSummary({super.key, required this.workout});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final color = RunPlanUi.kindColor(theme.colorScheme, workout.kind);
    final estimate = RunPlanUi.estimatedTotalSeconds(workout);
    final distance = workout.plannedDistanceMeters > 0
        ? workout.plannedDistanceMeters
        : (workout.targetDistanceMeters ?? 0);
    final reps = RunPlanUi.repsLabel(workout);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withAlpha(24),
        borderRadius: BorderRadius.circular(RunUi.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(RunPlanUi.kindIcon(workout.kind), color: color, size: 18),
              const SizedBox(width: 8),
              Text(
                RunPlanUi.kindLabel(loc, workout.kind),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                RunPlanUi.weekdayLabel(loc, workout.dayOfWeek),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          RunWorkoutProfileBar(workout: workout, height: 12),
          const SizedBox(height: 12),
          Wrap(
            spacing: 18,
            runSpacing: 10,
            children: [
              if (distance > 0)
                _SummaryStat(
                  label: loc.commonTotal,
                  value: RunPlanUi.distanceLabel(distance),
                ),
              if (estimate > 0)
                _SummaryStat(
                  label: loc.runWorkoutEstimatedTime,
                  value: '~${RunPlanUi.durationRoughLabel(estimate)}',
                ),
              if (reps != null)
                _SummaryStat(label: loc.runWorkoutStepRepeats, value: reps),
              if (workout.targetPaceSecPerKm != null)
                _SummaryStat(
                  label: loc.commonPace,
                  value:
                      '${RunPlanUi.paceLabel(workout.targetPaceSecPerKm)}/km',
                ),
            ],
          ),
          if (workout.notes != null && workout.notes!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(workout.notes!, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            fontFeatures: RunUi.tabular,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
