import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/goal.dart';
import 'package:workout_notes/widgets/goals/goal_formatters.dart';

/// Card listing the workouts that contributed to the current goal's progress.
/// Tapping a row navigates to the workout detail screen.
class GoalContributingWorkouts extends StatelessWidget {
  final List<ContributingWorkout> workouts;
  final Goal goal;
  final bool isKm;
  final void Function(String workoutId) onTapWorkout;

  /// The goal detail screen labels the card with its own section header, so it
  /// hides the inner title row.
  final bool showHeader;

  const GoalContributingWorkouts({
    super.key,
    required this.workouts,
    required this.goal,
    required this.isKm,
    required this.onTapWorkout,
    this.showHeader = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final isPortuguese = Localizations.localeOf(context).languageCode == 'pt';

    if (workouts.isEmpty) {
      return Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side:
              BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          child: Column(
            children: [
              Icon(Icons.fitness_center,
                  size: 36,
                  color: theme.colorScheme.onSurfaceVariant.withAlpha(100)),
              const SizedBox(height: 8),
              Text(
                loc.goalNoContributors,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(14, showHeader ? 12 : 4, 14, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showHeader) Row(
              children: [
                Icon(Icons.list_alt, size: 18, color: theme.colorScheme.onSurface),
                const SizedBox(width: 8),
                Text(
                  loc.goalContributingWorkouts,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${workouts.length}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            if (showHeader) const SizedBox(height: 8),
            for (var i = 0; i < workouts.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  color: theme.colorScheme.outlineVariant.withAlpha(60),
                ),
              _WorkoutTile(
                workout: workouts[i],
                goal: goal,
                isKm: isKm,
                isPortuguese: isPortuguese,
                onTap: () => onTapWorkout(workouts[i].workoutId),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WorkoutTile extends StatelessWidget {
  final ContributingWorkout workout;
  final Goal goal;
  final bool isKm;
  final bool isPortuguese;
  final VoidCallback onTap;

  const _WorkoutTile({
    required this.workout,
    required this.goal,
    required this.isKm,
    required this.isPortuguese,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final date = DateTime.parse(workout.date);
    final dateStr = isPortuguese
        ? DateFormat("d 'de' MMM", 'pt_BR').format(date)
        : DateFormat('MMM d').format(date);
    final dayOfWeek = isPortuguese
        ? DateFormat('EEE', 'pt_BR').format(date)
        : DateFormat('EEE').format(date);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            // Date block
            Container(
              width: 44,
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Text(
                    dayOfWeek,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                      letterSpacing: 0.4,
                    ),
                  ),
                  Text(
                    DateFormat('d').format(date),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.onSurface,
                      height: 1.0,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Workout info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dateStr,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _subtitle(loc),
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
            // Contribution — a day-count goal always contributes exactly one
            // day, so a check reads better than "1d".
            if (goal.metric == GoalMetric.days)
              Icon(
                Icons.check_circle_rounded,
                size: 18,
                color: theme.colorScheme.primary,
              )
            else
              Text(
                GoalFormatters.formatValueShort(
                    goal.metric, workout.contributedValue, isKm: isKm),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.primary,
                ),
              ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 18, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  String _subtitle(AppLocalizations loc) {
    if (goal.metric == GoalMetric.days) {
      return loc.goalWorkoutCompletedLabel;
    }
    if (workout.setCount > 0) {
      return loc.goalWorkoutSets(workout.setCount);
    }
    return loc.goalWorkoutLabel;
  }
}
