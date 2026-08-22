import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/goal.dart';
import 'package:workout_notes/widgets/goals/goal_formatters.dart';

/// Compact full-width goal row matching progress chart card styling.
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

  Color _accent(BuildContext context) {
    if (progress.isComplete) return const Color(0xFF43A047);
    if (goal.color != null) return Color(goal.color!);
    final theme = Theme.of(context);
    return goal.scope == GoalScope.aerobic
        ? const Color(0xFFE53935)
        : theme.colorScheme.primary;
  }

  IconData _metricIcon() {
    switch (goal.metric) {
      case GoalMetric.volume:
        return Icons.auto_graph;
      case GoalMetric.days:
        return Icons.calendar_today_outlined;
      case GoalMetric.distance:
        return Icons.map_outlined;
      case GoalMetric.time:
        return Icons.timer_outlined;
    }
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final accent = _accent(context);
    final percent = progress.percent.clamp(0.0, 1.0);
    final isComplete = progress.isComplete;
    final isPaused = !goal.isActive;
    final title = goal.title.isNotEmpty ? goal.title : _metricLabel(loc);
    final current = GoalFormatters.formatValueShort(
      goal.metric,
      progress.currentValue,
      isKm: isKm,
    );
    final target = GoalFormatters.formatValueShort(
      goal.metric,
      progress.targetValue,
      isKm: isKm,
    );
    final periodLabel = goal.period == GoalPeriod.weekly
        ? loc.goalPeriodWeekly
        : loc.goalPeriodMonthly;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: () => _showContextMenu(context),
        borderRadius: BorderRadius.circular(14),
        child: Opacity(
          opacity: isPaused ? 0.55 : 1,
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withAlpha(80),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: accent.withAlpha(28),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        isComplete
                            ? Icons.check_rounded
                            : (isPaused ? Icons.pause_rounded : _metricIcon()),
                        size: 18,
                        color: accent,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              height: 1.15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${_metricLabel(loc)} · $periodLabel',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${(percent * 100).round()}%',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: accent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: percent,
                    minHeight: 6,
                    backgroundColor: accent.withAlpha(28),
                    valueColor: AlwaysStoppedAnimation<Color>(accent),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$current / $target',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Icon(
                      isComplete
                          ? Icons.emoji_events_outlined
                          : Icons.schedule_outlined,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isComplete
                          ? loc.goalCompleted
                          : loc.goalDaysRemaining(progress.daysRemaining),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
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
