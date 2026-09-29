import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_voice_settings.dart';
import 'package:workout_notes/models/run_workout_step.dart';
import 'package:workout_notes/services/run_interval_engine.dart';
import 'package:workout_notes/services/run_workout_step_engine.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/widgets/run/record/run_record_option_tile.dart';
import 'package:workout_notes/widgets/run/run_plan_ui.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';

/// Live progress of a structured workout (or the quick interval set) with a
/// preview of the next step and a "Skip step" button.
class RunRecordStepCard extends StatelessWidget {
  final RunStepSnapshot stepSnapshot;
  final RunIntervalSnapshot intervalSnapshot;
  final bool intervalsOn;
  final VoidCallback? onSkip;

  const RunRecordStepCard({
    super.key,
    required this.stepSnapshot,
    required this.intervalSnapshot,
    required this.intervalsOn,
    this.onSkip,
  });

  static String _amount(RunIntervalMetric metric, int value) =>
      metric == RunIntervalMetric.time
      ? RunPlanUi.durationLabel(value)
      : RunPlanUi.distanceLabel(value.toDouble());

  static String _remaining(RunIntervalMetric metric, double remaining) =>
      metric == RunIntervalMetric.time
      ? RunFormatters.duration(remaining.round())
      : '${remaining.round()} m';

  /// Whether there is a running step or interval phase to show.
  static bool isVisible(
    RunStepSnapshot steps,
    RunIntervalSnapshot intervals,
    bool intervalsOn,
  ) =>
      steps.isActive ||
      steps.isDone && steps.totalSteps > 0 ||
      (intervalsOn &&
          (intervals.isActive || intervals.phase == RunIntervalPhase.done));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final colors = theme.colorScheme;

    final String title;
    final String? detail;
    final IconData icon;
    final Color tint;
    final RunIntervalMetric? metric;
    final double remaining;
    final double progress;
    final String? next;
    final bool canSkip;

    if (stepSnapshot.isActive) {
      title = _stepName(
        loc,
        stepSnapshot.role,
        stepSnapshot.repIndex,
        stepSnapshot.repTotal,
      );
      final pace = RunPlanUi.paceRangeLabel(
        stepSnapshot.targetPaceMinSecPerKm,
        stepSnapshot.targetPaceMaxSecPerKm,
      );
      detail = pace == null
          ? _amount(stepSnapshot.metric, stepSnapshot.target)
          : '${_amount(stepSnapshot.metric, stepSnapshot.target)} · $pace /km';
      icon = _roleIcon(stepSnapshot.role);
      tint = RunPlanUi.roleColor(colors, stepSnapshot.role);
      metric = stepSnapshot.metric;
      remaining = stepSnapshot.remaining;
      progress = stepSnapshot.progress;
      next = stepSnapshot.hasNext
          ? loc.runRecordNextStep(
              _stepLabel(
                loc,
                stepSnapshot.nextRole!,
                stepSnapshot.nextMetric!,
                stepSnapshot.nextTarget!,
                stepSnapshot.nextRepIndex,
                stepSnapshot.nextRepTotal,
              ),
            )
          : loc.runRecordNextStepLast;
      canSkip = true;
    } else if (intervalsOn && intervalSnapshot.isActive) {
      final isWork = intervalSnapshot.phase == RunIntervalPhase.work;
      title = isWork
          ? loc.runRecordIntervalWork(
              intervalSnapshot.workIndex,
              intervalSnapshot.totalWorks,
            )
          : loc.runRecordIntervalRest;
      detail = _amount(
        intervalSnapshot.currentMetric,
        intervalSnapshot.currentTarget,
      );
      icon = isWork ? Icons.bolt_rounded : Icons.self_improvement_rounded;
      tint = isWork ? colors.error : colors.tertiary;
      metric = intervalSnapshot.currentMetric;
      remaining = intervalSnapshot.remaining;
      progress = intervalSnapshot.progress;
      final nextPhase = intervalSnapshot.nextPhase;
      next = nextPhase == null
          ? loc.runRecordNextStepLast
          : loc.runRecordNextStep(
              '${nextPhase == RunIntervalPhase.work ? loc.runIntervalWork : loc.runRecordIntervalRest} '
              '${_amount(intervalSnapshot.nextMetric!, intervalSnapshot.nextTarget!)}',
            );
      canSkip = true;
    } else {
      // Finished: keep the confirmation visible until the run is stopped.
      title = loc.runRecordIntervalDone;
      detail = null;
      icon = Icons.check_circle_rounded;
      tint = colors.primary;
      metric = null;
      remaining = 0;
      progress = 1;
      next = null;
      canSkip = false;
    }

    return RunSectionCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
      color: tint.withAlpha(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              RunIconBadge(icon, color: tint),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (detail != null)
                      Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (metric != null)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    _remaining(metric, remaining),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      fontFeatures: RunUi.tabular,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: RunRecordProgressBar(value: progress),
          ),
          if (next != null || canSkip)
            Row(
              children: [
                Expanded(
                  child: Text(
                    next ?? '',
                    key: const ValueKey('run-next-step'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                if (canSkip && onSkip != null)
                  TextButton.icon(
                    key: const ValueKey('run-skip-step'),
                    onPressed: onSkip,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.skip_next_rounded, size: 18),
                    label: Text(loc.runRecordSkipStep),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  static IconData _roleIcon(RunStepRole role) => switch (role) {
    RunStepRole.warmup => Icons.local_fire_department_outlined,
    RunStepRole.work => Icons.bolt_rounded,
    RunStepRole.recovery => Icons.self_improvement_rounded,
    RunStepRole.steady => Icons.directions_run_rounded,
    RunStepRole.cooldown => Icons.ac_unit_rounded,
  };

  /// `Tiro 2 de 6`, `Recuperação · Tiro 2 de 6`, `Aquecimento`.
  static String _stepName(
    AppLocalizations loc,
    RunStepRole role,
    int repIndex,
    int repTotal,
  ) {
    if (repTotal <= 1) return RunPlanUi.roleLabel(loc, role);
    final rep = loc.runRecordPlanRepOf(repIndex, repTotal);
    return role == RunStepRole.work
        ? rep
        : '${RunPlanUi.roleLabel(loc, role)} · $rep';
  }

  /// `Recuperação 1:30`, `Tiro 2 de 6 400 m` — the "up next" description.
  static String _stepLabel(
    AppLocalizations loc,
    RunStepRole role,
    RunIntervalMetric metric,
    int target,
    int repIndex,
    int repTotal,
  ) {
    return '${_stepName(loc, role, repIndex, repTotal)} ${_amount(metric, target)}';
  }
}
