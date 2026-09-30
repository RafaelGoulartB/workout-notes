import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/l10n/exercise_locale_helper.dart';
import 'package:workout_notes/models/strength_workout_summary.dart';
import 'package:workout_notes/widgets/strength/home/strength_home_format.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Latest finished gym workouts: routine day, date, duration, volume, sets
/// and how the session felt. Runs are not listed here.
class StrengthRecentWorkouts extends StatelessWidget {
  final List<StrengthWorkoutSummary> workouts;
  final Map<String, StrengthCategoryInfo> categories;
  final ValueChanged<String> onOpen;

  const StrengthRecentWorkouts({
    super.key,
    required this.workouts,
    required this.onOpen,
    this.categories = const {},
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;

    return AppSectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: AppDividedList(
        children: [
          for (final workout in workouts)
            AppListRow(
              leading: AppIconBadge(
                Icons.fitness_center,
                size: 40,
                color: workout.dominantCategoryId == null
                    ? colors.primary
                    : Color(
                        categories[workout.dominantCategoryId]?.color ??
                            colors.primary.toARGB32(),
                      ),
              ),
              title:
                  workout.routineLabel ??
                  _muscleLabel(loc, workout, categories) ??
                  loc.strengthHomeFreeWorkout,
              titleTrailing: workout.feelingRating > 0
                  ? _Stars(rating: workout.feelingRating)
                  : null,
              subtitle: [
                StrengthHomeFormat.dayLabel(context, workout.date),
                if (workout.durationSeconds > 0)
                  StrengthHomeFormat.duration(workout.durationSeconds),
              ].join(' · '),
              value: StrengthHomeFormat.volume(workout.volumeKg),
              valueCaption: loc.strengthHomeSetsCount(workout.workingSets),
              onTap: () => onOpen(workout.id),
            ),
        ],
      ),
    );
  }
}

class _Stars extends StatelessWidget {
  final int rating;

  const _Stars({required this.rating});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < rating.clamp(0, 5); i++)
          const Icon(Icons.star_rounded, size: 11, color: Color(0xFFFFB300)),
      ],
    );
  }
}

/// Compact list of planned (future-dated) workouts.
class StrengthUpcomingWorkouts extends StatelessWidget {
  final List<StrengthUpcomingWorkout> workouts;
  final ValueChanged<String> onOpen;

  const StrengthUpcomingWorkouts({
    super.key,
    required this.workouts,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;

    return AppSectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: AppDividedList(
        children: [
          for (final workout in workouts)
            AppListRow(
              leading: const AppIconBadge(Icons.event_outlined, size: 40),
              title: workout.label ?? loc.strengthHomeFreeWorkout,
              subtitle: [
                StrengthHomeFormat.dayLabel(context, workout.date),
                if (workout.exerciseCount > 0)
                  loc.strengthHomeExercisesCount(workout.exerciseCount),
              ].join(' · '),
              onTap: () => onOpen(workout.id),
            ),
        ],
      ),
    );
  }
}

/// "Costas · Bíceps" for workouts without a routine day (categories are
/// already ordered by working sets).
String? _muscleLabel(
  AppLocalizations loc,
  StrengthWorkoutSummary workout,
  Map<String, StrengthCategoryInfo> categories,
) {
  final names = [
    for (final id in workout.categoryIds.take(2))
      if (categories[id] != null)
        ExerciseLocaleHelper.categoryName(loc, categories[id]!.row),
  ];
  return names.isEmpty ? null : names.join(' · ');
}
