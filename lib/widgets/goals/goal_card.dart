import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/goal.dart';
import 'package:workout_notes/utils/app_number_format.dart';
import 'package:workout_notes/utils/date_utils.dart';
import 'package:workout_notes/widgets/goals/goal_formatters.dart';
import 'package:workout_notes/widgets/goals/goal_progress_ring.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Where a goal stands against the time already spent in its period.
enum GoalPace { done, onTrack, behind, paused }

/// Goal row for the goals card: progress ring, title with a pace pill, the
/// period and what is left, and the current/target value on the right.
class GoalCard extends StatelessWidget {
  final Goal goal;
  final GoalProgress progress;
  final bool isKm;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onTogglePause;
  final VoidCallback? onDelete;

  const GoalCard({
    super.key,
    required this.goal,
    required this.progress,
    required this.isKm,
    required this.onTap,
    this.onEdit,
    this.onTogglePause,
    this.onDelete,
  });

  /// Behind means the goal trails the share of the period already elapsed by
  /// more than a small margin (so day one never reads as late).
  static GoalPace paceOf(Goal goal, GoalProgress progress) {
    if (!goal.isActive) return GoalPace.paused;
    if (progress.isComplete) return GoalPace.done;
    final total = daysBetween(progress.periodStart, progress.periodEnd) + 1;
    if (total <= 0) return GoalPace.onTrack;
    final expected = (progress.daysElapsed / total).clamp(0.0, 1.0);
    return progress.percent + 0.1 >= expected
        ? GoalPace.onTrack
        : GoalPace.behind;
  }

  Color _accent(ColorScheme colors) {
    if (progress.isComplete) return const Color(0xFF43A047);
    if (goal.color != null) return Color(goal.color!);
    return goal.scope == GoalScope.aerobic
        ? const Color(0xFFE53935)
        : colors.primary;
  }

  String _metricLabel(AppLocalizations loc) {
    switch (goal.metric) {
      case GoalMetric.volume:
        return loc.goalMetricVolume;
      case GoalMetric.days:
        return loc.goalMetricDays;
      case GoalMetric.distance:
        return loc.goalMetricDistance;
      case GoalMetric.time:
        return loc.goalMetricTime;
    }
  }

  String _value(double value) => goal.metric == GoalMetric.days
      ? AppNumberFormat.decimal(value, 0)
      : GoalFormatters.formatValueShort(goal.metric, value, isKm: isKm);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final pace = paceOf(goal, progress);
    final accent = pace == GoalPace.paused
        ? colors.onSurfaceVariant
        : _accent(colors);
    final title = goal.title.isNotEmpty ? goal.title : _metricLabel(loc);
    final period = goal.period == GoalPeriod.weekly
        ? loc.goalPeriodWeekly
        : loc.goalPeriodMonthly;
    final left = progress.targetValue - progress.currentValue;
    final subtitle = [
      if (goal.title.isNotEmpty) _metricLabel(loc),
      period,
      if (pace != GoalPace.done && pace != GoalPace.paused)
        loc.goalDaysRemaining(progress.daysRemaining),
    ].join(' · ');

    return InkWell(
      onTap: onTap,
      onLongPress: () => _showContextMenu(context),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            GoalProgressRing(
              percent: progress.percent,
              color: accent,
              trackColor: accent.withAlpha(35),
              size: 44,
              strokeWidth: 4.5,
              child: pace == GoalPace.done
                  ? Icon(Icons.check_rounded, size: 20, color: accent)
                  : pace == GoalPace.paused
                  ? Icon(Icons.pause_rounded, size: 18, color: accent)
                  : Text(
                      '${(progress.percent.clamp(0.0, 1.0) * 100).round()}%',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontFeatures: AppUi.tabular,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      _PacePill(pace: pace),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: _value(progress.currentValue)),
                      TextSpan(
                        text: '/${_value(progress.targetValue)}',
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontFeatures: AppUi.tabular,
                  ),
                ),
                Text(
                  pace == GoalPace.done || left <= 0
                      ? (goal.metric == GoalMetric.days
                            ? loc.goalRowDaysUnit
                            : _metricLabel(loc).toLowerCase())
                      : goal.metric == GoalMetric.days
                      ? loc.goalRowLeftDays(left.ceil())
                      : loc.goalRowLeft(_value(left)),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontFeatures: AppUi.tabular,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showContextMenu(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onEdit != null)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(loc.goalEditTitle),
                onTap: () {
                  Navigator.of(ctx).pop();
                  onEdit?.call();
                },
              ),
            if (onTogglePause != null)
              ListTile(
                leading: Icon(
                  goal.isActive
                      ? Icons.pause_circle_outline
                      : Icons.play_circle_outline,
                ),
                title: Text(goal.isActive ? loc.goalPause : loc.goalResume),
                onTap: () {
                  Navigator.of(ctx).pop();
                  onTogglePause?.call();
                },
              ),
            if (onDelete != null)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: Text(
                  loc.goalDelete,
                  style: const TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  onDelete?.call();
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _PacePill extends StatelessWidget {
  final GoalPace pace;

  const _PacePill({required this.pace});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final (label, color) = switch (pace) {
      GoalPace.done => (loc.goalStatusDone, const Color(0xFF43A047)),
      GoalPace.onTrack => (loc.goalStatusOnTrack, colors.primary),
      GoalPace.behind => (loc.goalStatusBehind, colors.tertiary),
      GoalPace.paused => (loc.goalStatusPaused, colors.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          fontSize: 10.5,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
