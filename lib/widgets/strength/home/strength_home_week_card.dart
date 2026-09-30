import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/strength_workout_summary.dart';
import 'package:workout_notes/services/strength_today_service.dart';
import 'package:workout_notes/utils/strength_week_analytics.dart';
import 'package:workout_notes/widgets/strength/home/strength_home_format.dart';
import 'package:workout_notes/widgets/strength/home/strength_home_week_strip.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// "This week": sessions against the weekly goal (ring), the Monday-to-Sunday
/// strip with planned strength days, working sets against the plan's range
/// and one comparison line with last week.
class StrengthWeekCard extends StatelessWidget {
  final StrengthWeekAnalytics analytics;
  final StrengthHomeSnapshot? snapshot;
  final Map<String, StrengthCategoryInfo> categories;

  /// Called to edit the weekly goal (null hides the edit affordance).
  final VoidCallback? onEditGoal;

  const StrengthWeekCard({
    super.key,
    required this.analytics,
    required this.snapshot,
    this.categories = const {},
    this.onEditGoal,
  });

  static String comparisonLabel(
    AppLocalizations loc,
    StrengthWeekAnalytics analytics,
  ) {
    final last = analytics.lastWeekVolumeKg;
    final now = analytics.thisWeekVolumeKg;
    if (last > 0 && now > 0) {
      final ratio = now / last - 1;
      final percent = (ratio.abs() * 100).round();
      if (percent == 0) return loc.strengthHomeWeekVolumeFlat;
      return ratio > 0
          ? loc.strengthHomeWeekVolumeUp(percent)
          : loc.strengthHomeWeekVolumeDown(percent);
    }
    return loc.strengthHomeWeekLastWeek(
      loc.strengthHomeWorkoutsCount(analytics.lastWeekSessions),
      StrengthHomeFormat.volume(analytics.lastWeekVolumeKg),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final done = analytics.thisWeekSessions;
    final goal = StrengthWeekGoal.resolve(
      planSessions: snapshot?.planSessionsPerWeek,
      userSessions: snapshot?.userWeeklyGoalSessions,
      averageSessions: analytics.avgWeeklySessions,
    );
    final ratio = goal == null ? null : done / goal.sessions;
    final reached = ratio != null && ratio >= 1;
    final editable =
        onEditGoal != null && goal?.source != StrengthWeekGoalSource.plan;
    final setsRange = StrengthHomeFormat.setsRange(
      snapshot?.planMinSetsPerWeek,
      snapshot?.planMaxSetsPerWeek,
    );

    return AppSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppValueUnit(
                      value: '$done',
                      unit: loc.strengthHomeWorkoutsUnit(done),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      done == 0
                          ? loc.strengthHomeWeekCount(0)
                          : [
                              loc.strengthHomeSetsCount(analytics.thisWeekSets),
                              StrengthHomeFormat.volume(
                                analytics.thisWeekVolumeKg,
                              ),
                            ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    if (analytics.weekStreak > 0) ...[
                      const SizedBox(height: 8),
                      AppPill(
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
          StrengthWeekStrip(
            days: analytics.thisWeekDays,
            today: analytics.now,
            plannedWeekdays: snapshot?.plannedStrengthDays ?? const [],
            categories: categories,
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
                label: Text(loc.strengthHomeWeekGoalEdit),
              ),
            ),
          if (setsRange != null) ...[
            const SizedBox(height: 10),
            _SetsTarget(
              done: analytics.thisWeekSets,
              range: setsRange,
              min: snapshot?.planMinSetsPerWeek,
              max: snapshot?.planMaxSetsPerWeek,
            ),
          ],
          if (analytics.hasWeekComparison) ...[
            const SizedBox(height: 8),
            Text(
              comparisonLabel(loc, analytics),
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
                fontFeatures: AppUi.tabular,
              ),
            ),
        ],
      ),
    );
  }
}

class _GoalLine extends StatelessWidget {
  final StrengthWeekGoal goal;
  final int done;
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
      StrengthWeekGoalSource.plan => loc.strengthHomeWeekGoalPlan,
      StrengthWeekGoalSource.user => loc.strengthHomeWeekGoalUser,
      StrengthWeekGoalSource.average => loc.strengthHomeWeekGoalAverage,
    };
    final remaining = (goal.sessions - done).clamp(0, 99);

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                loc.strengthHomeWeekGoalOf(done, goal.sessions),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: AppUi.tabular,
                ),
              ),
              Text(
                reached
                    ? '$source · ${loc.strengthHomeWeekGoalReached}'
                    : '$source · ${loc.strengthHomeWeekGoalRemaining(remaining)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: reached ? colors.tertiary : colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (onEdit != null)
          IconButton(
            tooltip: loc.strengthHomeWeekGoalEdit,
            visualDensity: VisualDensity.compact,
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 20),
          ),
      ],
    );
  }
}

/// Working sets so far against the plan's weekly range.
class _SetsTarget extends StatelessWidget {
  final int done;
  final String range;
  final int? min;
  final int? max;

  const _SetsTarget({
    required this.done,
    required this.range,
    required this.min,
    required this.max,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final scale = (max ?? min ?? 1).clamp(1, 1 << 20);
    final inRange =
        (min == null || done >= min!) && (max == null || done <= max!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                loc.strengthHomeWeekSetsLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
            Text(
              loc.strengthHomeWeekSetsOf(done, range),
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                fontFeatures: AppUi.tabular,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (done / scale).clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: colors.surfaceContainerHighest,
            color: inRange ? colors.tertiary : colors.primary,
          ),
        ),
      ],
    );
  }
}

/// Result of [showStrengthWeeklyGoalDialog]: [sessions] null means "remove".
class StrengthWeeklyGoalEdit {
  final int? sessions;

  const StrengthWeeklyGoalEdit(this.sessions);
}

/// Small dialog to set (or clear) the weekly workouts goal. Returns null
/// when cancelled.
Future<StrengthWeeklyGoalEdit?> showStrengthWeeklyGoalDialog(
  BuildContext context, {
  int? current,
}) {
  return showDialog<StrengthWeeklyGoalEdit>(
    context: context,
    builder: (_) => _WeeklyGoalDialog(current: current),
  );
}

class _WeeklyGoalDialog extends StatefulWidget {
  final int? current;

  const _WeeklyGoalDialog({this.current});

  @override
  State<_WeeklyGoalDialog> createState() => _WeeklyGoalDialogState();
}

class _WeeklyGoalDialogState extends State<_WeeklyGoalDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.current?.toString() ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final sessions = int.tryParse(_controller.text.trim());
    if (sessions == null || sessions < 1 || sessions > 14) {
      setState(
        () =>
            _error = AppLocalizations.of(context)!.strengthHomeWeekGoalInvalid,
      );
      return;
    }
    Navigator.pop(context, StrengthWeeklyGoalEdit(sessions));
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final material = MaterialLocalizations.of(context);
    return AlertDialog(
      title: Text(loc.strengthHomeWeekGoalEdit),
      content: TextField(
        key: const Key('strength-weekly-goal-field'),
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: loc.strengthHomeWeekGoalField,
          hintText: loc.strengthHomeWeekGoalHint,
          errorText: _error,
        ),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        if (widget.current != null)
          TextButton(
            onPressed: () =>
                Navigator.pop(context, const StrengthWeeklyGoalEdit(null)),
            child: Text(loc.strengthHomeWeekGoalClear),
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
