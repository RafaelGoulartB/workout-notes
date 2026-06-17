import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/goal.dart';
import 'package:workout_notes/widgets/goals/goal_formatters.dart';
import 'package:workout_notes/widgets/goals/goal_progress_ring.dart';

/// Card widget for a single goal, displayed in the goals section grid.
///
/// Modern, borderless design:
/// - Solid colored background (scope color) with a subtle dark overlay
///   for legibility of white text
/// - Large progress ring on the left with translucent track
/// - White text and translucent pills for metadata
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
    if (goal.color != null) return Color(goal.color!);
    return goal.scope == GoalScope.aerobic
        ? const Color(0xFFE53935)
        : const Color(0xFF1565C0); // deep blue, distinct from theme primary
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
    final loc = AppLocalizations.of(context)!;
    final color = _scopeColor(context);
    final percent = progress.percent;
    final isComplete = progress.isComplete;
    final isPaused = !goal.isActive;

    // For complete goals, use green; otherwise use the scope color.
    final accent = isComplete ? const Color(0xFF2E7D32) : color;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: () => _showContextMenu(context),
        borderRadius: BorderRadius.circular(20),
        child: Opacity(
          opacity: isPaused ? 0.6 : 1.0,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Container(
              // Solid color background with subtle dark overlay for legibility.
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: accent.withAlpha(80),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // Subtle dark overlay at the bottom for text legibility.
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withAlpha(0),
                            Colors.black.withAlpha(40),
                          ],
                          stops: const [0.5, 1.0],
                        ),
                      ),
                    ),
                  ),
                  // Content
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Top row: ring + status pill
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GoalProgressRing(
                              percent: percent,
                              color: Colors.white,
                              trackColor: Colors.white.withAlpha(40),
                              size: 44,
                              strokeWidth: 5,
                              child: Text(
                                '${(percent * 100).clamp(0, 999).toInt()}%',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 9,
                                  color: Colors.white,
                                  height: 1.0,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _StatusPill(
                                icon: isComplete
                                    ? Icons.check_circle
                                    : (isPaused
                                        ? Icons.pause_circle
                                        : _metricIcon()),
                                label: _metricLabel(loc),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // Title (custom or default)
                        Text(
                          goal.title.isNotEmpty
                              ? goal.title
                              : _periodShort(loc),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            height: 1.1,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 1),
                        // Values
                        Text(
                          '${GoalFormatters.formatValueShort(goal.metric, progress.currentValue, isKm: isKm)} / ${GoalFormatters.formatValueShort(goal.metric, progress.targetValue, isKm: isKm)}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withAlpha(220),
                            height: 1.1,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        // Translucent bar
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: percent.clamp(0.0, 1.0),
                            minHeight: 4,
                            backgroundColor: Colors.white.withAlpha(40),
                            valueColor:
                                const AlwaysStoppedAnimation<Color>(
                                    Colors.white),
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Footer
                        Row(
                          children: [
                            Icon(
                              isComplete
                                  ? Icons.emoji_events
                                  : Icons.hourglass_bottom,
                              size: 10,
                              color: Colors.white.withAlpha(220),
                            ),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                isComplete
                                    ? loc.goalCompleted
                                    : loc.goalDaysRemaining(
                                        progress.daysRemaining),
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white.withAlpha(220),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
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

/// Translucent pill displayed in the top-right of the card.
class _StatusPill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _StatusPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(30),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 9, color: Colors.white),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
