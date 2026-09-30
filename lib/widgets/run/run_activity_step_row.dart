import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_workout_step.dart';
import 'package:workout_notes/models/scheduled_run.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/widgets/run/run_plan_ui.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// One planned-vs-actual row of an interval session. The pace delta is the
/// number that matters: did rep 5 hold the target of rep 1?
class RunActivityStepRow extends StatelessWidget {
  final RunActivityStep step;

  const RunActivityStepRow({super.key, required this.step});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final role = RunStepRole.fromString(step.role);
    final color = RunPlanUi.roleColor(theme.colorScheme, role);
    final planned = step.plannedValue == null
        ? '—'
        : step.plannedMetric == 'time'
        ? RunPlanUi.durationLabel(step.plannedValue!)
        : RunPlanUi.distanceLabel(step.plannedValue!.toDouble());
    final actual = step.plannedMetric == 'time'
        ? RunPlanUi.durationLabel(step.actualDurationSeconds ?? 0)
        : RunPlanUi.distanceLabel(step.actualDistanceMeters ?? 0);
    final delta = step.paceDeltaSecPerKm;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 30,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  role == RunStepRole.work
                      ? '${RunPlanUi.roleLabel(loc, role)} ${step.repIndex}'
                      : RunPlanUi.roleLabel(loc, role),
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${loc.runDetailPlanStepPlanned} $planned · '
                  '${loc.runDetailPlanStepActual} $actual',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                RunFormatters.paceWithUnit(step.actualPaceSecPerKm),
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: AppUi.tabular,
                ),
              ),
              if (delta != null)
                Text(
                  // Negative delta means faster than planned.
                  RunFormatters.paceDelta(delta),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: delta <= 0
                        ? theme.colorScheme.primary
                        : theme.colorScheme.error,
                    fontWeight: FontWeight.w700,
                    fontFeatures: AppUi.tabular,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
