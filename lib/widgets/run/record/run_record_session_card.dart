import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/models/run_session_goal.dart';
import 'package:workout_notes/models/run_voice_settings.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/widgets/run/record/run_record_option_tile.dart';
import 'package:workout_notes/widgets/run/run_plan_ui.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// "This run": voice alerts, goal, the attached workout and the quick
/// interval set. Before the start it is where the run is configured; while
/// recording it only keeps the goal progress visible.
class RunRecordSessionCard extends StatelessWidget {
  final RunSessionGoal goal;
  final RunGoalSnapshot goalSnapshot;
  final bool active;
  final RunPlanWorkout? planWorkout;
  final VoidCallback? onDetachPlan;
  final bool intervalsOn;
  final RunIntervalPreset intervalPreset;
  final ValueChanged<bool>? onIntervalsChanged;
  final VoidCallback? onEditGoal;

  /// Switching the goal tile off clears the distance/time and pace goals.
  final VoidCallback? onClearGoal;
  final bool voiceEnabled;
  final bool headphonesOnly;
  final bool headsetConnected;
  final VoidCallback onOpenVoiceSettings;

  /// False indoors: the quick interval preset needs a GPS clock and distance.
  final bool allowQuickIntervals;

  const RunRecordSessionCard({
    super.key,
    required this.goal,
    required this.goalSnapshot,
    required this.active,
    required this.planWorkout,
    required this.onDetachPlan,
    required this.intervalsOn,
    required this.intervalPreset,
    required this.onIntervalsChanged,
    required this.onEditGoal,
    required this.onClearGoal,
    required this.voiceEnabled,
    required this.headphonesOnly,
    required this.headsetConnected,
    required this.onOpenVoiceSettings,
    this.allowQuickIntervals = true,
  });

  static String _amount(RunIntervalMetric metric, int value) =>
      metric == RunIntervalMetric.time
      ? RunPlanUi.durationLabel(value)
      : RunPlanUi.distanceLabel(value.toDouble());

  String _goalTarget(AppLocalizations loc) {
    final parts = <String>[];
    if (goal.enabled) {
      parts.add(_amount(goal.metric, goal.value));
    }
    if (goal.hasPaceGoal) {
      parts.add(
        loc.runRecordGoalPaceSummary(
          RunPlanUi.paceLabel(goal.paceTargetSecPerKm!.toDouble()),
        ),
      );
    }
    return parts.join(' · ');
  }

  String _goalSubtitle(AppLocalizations loc) {
    if (!goal.hasAnyGoal) {
      return onEditGoal != null && !active
          ? '${loc.runRecordGoalNone} · ${loc.runRecordGoalTapToChange}'
          : loc.runRecordGoalNone;
    }
    if (active && goal.enabled) {
      if (goalSnapshot.completed) return loc.runRecordGoalDone;
      final remaining = goal.metric == RunIntervalMetric.time
          ? RunFormatters.duration(goalSnapshot.remaining.round())
          : RunPlanUi.distanceLabel(goalSnapshot.remaining);
      final tail = goal.hasPaceGoal
          ? ' · ${loc.runRecordGoalPaceSummary(RunPlanUi.paceLabel(goal.paceTargetSecPerKm!.toDouble()))}'
          : '';
      return '${loc.runRecordGoalRemaining(remaining)}$tail';
    }
    final target = _goalTarget(loc);
    return onEditGoal != null && !active
        ? '$target · ${loc.runRecordGoalTapToChange}'
        : target;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final plan = planWorkout;
    final showGoal = !active || goal.hasAnyGoal;
    final showQuickIntervals = allowQuickIntervals && plan == null && !active;
    final voiceSubtitle = !voiceEnabled
        ? loc.runRecordVoiceOff
        : headphonesOnly && !headsetConnected
        ? loc.runRecordVoiceHeadsetMissing
        : loc.runRecordVoiceReady;

    final tiles = <Widget>[
      if (!active)
        RunRecordOptionTile(
          icon: Icons.record_voice_over_outlined,
          title: loc.runRecordVoiceLabel,
          subtitle: voiceSubtitle,
          selected: voiceEnabled && (!headphonesOnly || headsetConnected),
          onTap: onOpenVoiceSettings,
          trailing: Icon(
            Icons.chevron_right_rounded,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      if (showGoal)
        RunRecordOptionTile(
          icon: Icons.flag_rounded,
          title: loc.runRecordGoal,
          subtitle: _goalSubtitle(loc),
          selected: goal.hasAnyGoal,
          onTap: active ? null : onEditGoal,
          trailing: active
              ? null
              : Switch.adaptive(
                  value: goal.hasAnyGoal,
                  onChanged: onEditGoal == null
                      ? null
                      : (on) => on ? onEditGoal!() : onClearGoal?.call(),
                ),
          footer: active && goal.enabled
              ? RunRecordProgressBar(value: goalSnapshot.progress)
              : null,
        ),
      if (plan != null)
        RunRecordPlanTile(plan: plan, onDetach: active ? null : onDetachPlan),
      if (showQuickIntervals)
        RunRecordOptionTile(
          icon: Icons.av_timer_rounded,
          title: loc.runRecordIntervals,
          subtitle: loc.runIntervalPresetSummary(
            _amount(intervalPreset.workMetric, intervalPreset.workValue),
            _amount(intervalPreset.restMetric, intervalPreset.restValue),
            intervalPreset.repeats,
          ),
          selected: intervalsOn,
          onTap: onIntervalsChanged == null
              ? null
              : () => onIntervalsChanged!(!intervalsOn),
          trailing: Switch.adaptive(
            value: intervalsOn,
            onChanged: onIntervalsChanged,
          ),
        ),
    ];
    if (tiles.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSectionHeader(
          loc.runRecordOptionsTitle,
          padding: const EdgeInsets.fromLTRB(4, 0, 0, 6),
        ),
        AppSectionCard(
          padding: EdgeInsets.zero,
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.45,
          ),
          child: Column(
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    indent: 12,
                    endIndent: 12,
                    color: AppUi.divider(theme.colorScheme),
                  ),
                tiles[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The workout attached to this run, with an optional "remove" button.
class RunRecordPlanTile extends StatelessWidget {
  final RunPlanWorkout plan;
  final VoidCallback? onDetach;

  const RunRecordPlanTile({super.key, required this.plan, this.onDetach});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return RunRecordOptionTile(
      icon: RunPlanUi.kindIcon(plan.kind),
      title: plan.name,
      subtitle:
          '${RunPlanUi.kindLabel(loc, plan.kind)} · ${RunPlanUi.sessionSummary(loc, plan)}',
      selected: true,
      trailing: onDetach == null
          ? null
          : IconButton(
              tooltip: loc.runRecordPlanDetach,
              icon: const Icon(Icons.close_rounded, size: 20),
              onPressed: onDetach,
            ),
    );
  }
}
