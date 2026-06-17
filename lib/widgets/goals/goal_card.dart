import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/goal.dart';
import 'package:workout_notes/widgets/goals/goal_formatters.dart';
import 'package:workout_notes/widgets/goals/goal_progress_ring.dart';

/// Card widget for a single goal, displayed in the goals section grid.
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

  Color _scopeColor(BuildContext context) {
    final theme = Theme.of(context);
    if (goal.color != null) return Color(goal.color!);
    return goal.scope == GoalScope.aerobic
        ? const Color(0xFFE53935)
        : theme.colorScheme.primary;
  }

  IconData _metricIcon() {
    switch (goal.metric) {
      case GoalMetric.volume:
        return Icons.auto_graph;
      case GoalMetric.days:
        return Icons.calendar_today;
      case GoalMetric.distance:
        return Icons.map;
      case GoalMetric.time:
        return Icons.timer;
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
    final color = _scopeColor(context);
    final percent = progress.percent;
    final isComplete = progress.isComplete;
    final isPaused = !goal.isActive;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: () => _showContextMenu(context),
        borderRadius: BorderRadius.circular(16),
        child: Opacity(
          opacity: isPaused ? 0.6 : 1.0,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [
                  color.withAlpha(isComplete ? 60 : 25),
                  theme.colorScheme.surface,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                color: color.withAlpha(isComplete ? 180 : 80),
                width: isComplete ? 1.5 : 1,
              ),
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    GoalProgressRing(
                      percent: percent,
                      color: isComplete ? Colors.green : color,
                      size: 64,
                      strokeWidth: 7,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isComplete ? Icons.check : _metricIcon(),
                            size: 14,
                            color: isComplete ? Colors.green : color,
                          ),
                          Text(
                            '${(percent * 100).clamp(0, 999).toInt()}%',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                              color: isComplete ? Colors.green : color,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            goal.title.isNotEmpty
                                ? goal.title
                                : '${_metricLabel(loc)} · ${_periodShort(loc)}',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${_metricLabel(loc)} · ${_periodShort(loc)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 10,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${GoalFormatters.formatValueShort(goal.metric, progress.currentValue, isKm: isKm)} / ${GoalFormatters.formatValueShort(goal.metric, progress.targetValue, isKm: isKm)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (isPaused)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          loc.goalPausedBadge,
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: percent.clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: color.withAlpha(25),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isComplete ? Colors.green : color,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isComplete
                          ? loc.goalCompleted
                          : loc.goalDaysRemaining(progress.daysRemaining),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 10,
                        color: isComplete
                            ? Colors.green
                            : theme.colorScheme.onSurfaceVariant,
                        fontWeight: isComplete ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    if (isComplete)
                      const Icon(Icons.emoji_events, color: Colors.amber, size: 14),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _periodShort(AppLocalizations loc) {
    return goal.period == GoalPeriod.weekly
        ? loc.goalPeriodWeekly
        : loc.goalPeriodMonthly;
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
                leading: const Icon(Icons.edit),
                title: Text(loc.goalEditTitle),
                onTap: () {
                  Navigator.of(ctx).pop();
                  onEdit?.call();
                },
              ),
            if (onTogglePause != null)
              ListTile(
                leading: Icon(goal.isActive ? Icons.pause : Icons.play_arrow),
                title: Text(goal.isActive ? loc.goalPause : loc.goalResume),
                onTap: () {
                  Navigator.of(ctx).pop();
                  onTogglePause?.call();
                },
              ),
            if (onDelete != null)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: Text(loc.goalDelete,
                    style: const TextStyle(color: Colors.red)),
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
