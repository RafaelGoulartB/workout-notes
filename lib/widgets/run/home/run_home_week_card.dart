import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/services/run_today_service.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/utils/run_progress_analytics.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';
import 'package:workout_notes/widgets/run/run_week_strip.dart';

/// "This week": distance so far against the weekly goal (ring), the
/// Monday-to-Sunday strip with planned sessions, and one comparison line.
class RunWeekCard extends StatelessWidget {
  final RunProgressAnalytics analytics;
  final RunHomeSnapshot? snapshot;

  /// Called to edit the weekly goal (null hides the edit affordance).
  final VoidCallback? onEditGoal;

  const RunWeekCard({
    super.key,
    required this.analytics,
    required this.snapshot,
    this.onEditGoal,
  });

  static String comparisonLabel(AppLocalizations loc, double deltaMeters) {
    final abs = RunFormatters.distanceWithUnit(deltaMeters.abs());
    if (deltaMeters > 50) return loc.runStatsWeekUp(abs);
    if (deltaMeters < -50) return loc.runStatsWeekDown(abs);
    return loc.runStatsWeekFlat;
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final done = analytics.thisWeekDistanceMeters;
    final goal = RunWeekGoal.resolve(
      planMeters: snapshot?.plan?.weekPlannedMeters,
      userMeters: snapshot?.userWeeklyGoalMeters,
      averageMeters: analytics.avgWeeklyDistanceMeters,
    );
    final ratio = goal == null ? null : done / goal.meters;
    final reached = ratio != null && ratio >= 1;
    final editable =
        onEditGoal != null && goal?.source != RunWeekGoalSource.plan;

    return RunSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RunValueUnit(
                      value: RunFormatters.distanceKm(done),
                      unit: 'km',
                    ),
                    const SizedBox(height: 2),
                    Text(
                      analytics.thisWeekRunCount == 0
                          ? loc.runStatsWeekNoRuns
                          : loc.runHomeWeekRunCount(analytics.thisWeekRunCount),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    if (analytics.weekStreak > 0) ...[
                      const SizedBox(height: 8),
                      RunPill(
                        label: loc.runStatsStreakWeeks(analytics.weekStreak),
                        icon: Icons.local_fire_department_rounded,
                        color: colors.tertiary,
                      ),
                    ],
                  ],
                ),
              ),
              if (goal != null && ratio != null)
                _GoalRing(ratio: ratio, reached: reached),
            ],
          ),
          const SizedBox(height: 16),
          RunWeekStrip(
            days: analytics.thisWeekDays,
            today: analytics.now,
            planned: snapshot?.weekPlan ?? const [],
          ),
          const SizedBox(height: 14),
          if (goal != null)
            _GoalLine(
              goal: goal,
              done: done,
              reached: reached,
              onEdit: editable ? onEditGoal : null,
            )
          else if (onEditGoal != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onEditGoal,
                icon: const Icon(Icons.flag_outlined, size: 18),
                label: Text(loc.runHomeWeekGoalEdit),
              ),
            ),
          if (analytics.hasWeekComparison) ...[
            const SizedBox(height: 6),
            Text(
              comparisonLabel(loc, analytics.distanceDeltaVsLastWeek),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _GoalRing extends StatelessWidget {
  final double ratio;
  final bool reached;

  const _GoalRing({required this.ratio, required this.reached});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final percent = (ratio * 100).round();

    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 72,
            height: 72,
            child: CircularProgressIndicator(
              value: ratio.clamp(0.0, 1.0),
              strokeWidth: 7,
              strokeCap: StrokeCap.round,
              backgroundColor: colors.surfaceContainerHighest,
              color: reached ? colors.tertiary : colors.primary,
            ),
          ),
          if (reached)
            Icon(Icons.check_rounded, color: colors.tertiary, size: 28)
          else
            Text(
              '$percent%',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                fontFeatures: RunUi.tabular,
              ),
            ),
        ],
      ),
    );
  }
}

class _GoalLine extends StatelessWidget {
  final RunWeekGoal goal;
  final double done;
  final bool reached;
  final VoidCallback? onEdit;

  const _GoalLine({
    required this.goal,
    required this.done,
    required this.reached,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final source = switch (goal.source) {
      RunWeekGoalSource.plan => loc.runHomeWeekGoalPlan,
      RunWeekGoalSource.user => loc.runHomeWeekGoalUser,
      RunWeekGoalSource.average => loc.runHomeWeekGoalAverage,
    };
    final remaining = goal.meters - done;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                loc.runHomeWeekGoalOf(
                  RunFormatters.distanceWithUnit(done),
                  RunFormatters.distanceWithUnit(goal.meters),
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: RunUi.tabular,
                ),
              ),
              Text(
                reached
                    ? '$source · ${loc.runHomeWeekGoalReached}'
                    : '$source · ${loc.runHomeWeekGoalRemaining(RunFormatters.distanceWithUnit(remaining))}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: reached ? colors.tertiary : colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (onEdit != null)
          IconButton(
            tooltip: loc.runHomeWeekGoalEdit,
            visualDensity: VisualDensity.compact,
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 20),
          ),
      ],
    );
  }
}

/// Result of [showRunWeeklyGoalDialog]: [km] null means "remove the goal".
class RunWeeklyGoalEdit {
  final double? km;

  const RunWeeklyGoalEdit(this.km);
}

/// Small dialog to set (or clear) the weekly distance goal in km. Returns
/// null when cancelled.
Future<RunWeeklyGoalEdit?> showRunWeeklyGoalDialog(
  BuildContext context, {
  double? currentKm,
}) {
  return showDialog<RunWeeklyGoalEdit>(
    context: context,
    builder: (_) => _WeeklyGoalDialog(currentKm: currentKm),
  );
}

class _WeeklyGoalDialog extends StatefulWidget {
  final double? currentKm;

  const _WeeklyGoalDialog({this.currentKm});

  @override
  State<_WeeklyGoalDialog> createState() => _WeeklyGoalDialogState();
}

class _WeeklyGoalDialogState extends State<_WeeklyGoalDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    final km = widget.currentKm;
    _controller = TextEditingController(
      text: km == null
          ? ''
          : RunFormatters.decimal(km, km == km.roundToDouble() ? 0 : 1),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final km = double.tryParse(_controller.text.trim().replaceAll(',', '.'));
    if (km == null || km <= 0 || km > 1000) {
      setState(
        () => _error = AppLocalizations.of(context)!.runHomeWeekGoalInvalid,
      );
      return;
    }
    Navigator.pop(context, RunWeeklyGoalEdit(km));
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final material = MaterialLocalizations.of(context);
    return AlertDialog(
      title: Text(loc.runHomeWeekGoalEdit),
      content: TextField(
        key: const Key('run-weekly-goal-field'),
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: loc.runHomeWeekGoalField,
          hintText: loc.runHomeWeekGoalHint,
          errorText: _error,
          suffixText: 'km',
        ),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        if (widget.currentKm != null)
          TextButton(
            onPressed: () =>
                Navigator.pop(context, const RunWeeklyGoalEdit(null)),
            child: Text(loc.runHomeWeekGoalClear),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(material.cancelButtonLabel),
        ),
        FilledButton(onPressed: _save, child: Text(material.saveButtonLabel)),
      ],
    );
  }
}
