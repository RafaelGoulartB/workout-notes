import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/l10n/exercise_locale_helper.dart';

/// Displays a categorized list of exercises with tap-to-view-history.
class PerformanceSection extends StatelessWidget {
  final List<Map<String, dynamic>> allExercises;
  final void Function(String exerciseId, String exerciseName, ThemeData theme)
      onExerciseTap;

  const PerformanceSection({
    super.key,
    required this.allExercises,
    required this.onExerciseTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;

    if (allExercises.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(Icons.fitness_center_outlined,
                  size: 32,
                  color: theme.colorScheme.onSurfaceVariant
                      .withAlpha(80)),
              const SizedBox(height: 8),
              Text(
                loc.progressNoExercises,
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    // Group exercises by category
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final ex in allExercises) {
      final catName =
          ExerciseLocaleHelper.categoryName(loc, ex);
      grouped.putIfAbsent(catName, () => []).add(ex);
    }
    final sortedKeys = grouped.keys.toList()..sort();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            loc.progressTapForHistory,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          ...sortedKeys.map((catName) {
            final exercises = grouped[catName]!;
            final catColor = Color(exercises.first['category_color']
                    as int? ??
                0xFF757575);
            return ExpansionTile(
              initiallyExpanded: false,
              tilePadding: const EdgeInsets.symmetric(
                  horizontal: 4, vertical: 0),
              childrenPadding: EdgeInsets.zero,
              shape: const Border(),
              collapsedShape: const Border(),
              collapsedBackgroundColor: Colors.transparent,
              backgroundColor: Colors.transparent,
              iconColor: catColor,
              collapsedIconColor: catColor.withAlpha(150),
              title: Row(
                children: [
                  Container(
                    width: 4,
                    height: 16,
                    decoration: BoxDecoration(
                      color: catColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    catName,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: catColor,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: catColor.withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${exercises.length}',
                      style: TextStyle(
                        fontSize: 10,
                        color: catColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              children: exercises
                  .map((ex) => _ExerciseCard(
                        exercise: ex,
                        onTap: (id, name) =>
                            onExerciseTap(id, name, theme),
                      ))
                  .toList(),
            );
          }),
        ],
      ),
    );
  }
}

/// A single exercise card in the performance list.
class _ExerciseCard extends StatelessWidget {
  final Map<String, dynamic> exercise;
  final void Function(String id, String name) onTap;

  const _ExerciseCard({
    required this.exercise,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final catColor =
        Color(exercise['category_color'] as int? ?? 0xFF757575);
    final name =
        ExerciseLocaleHelper.exerciseName(AppLocalizations.of(context)!, exercise);
    final type = exercise['type'] as String? ?? 'weightReps';
    final icon = type == 'weightReps'
        ? Icons.fitness_center
        : type == 'cardio'
            ? Icons.directions_run
            : type == 'duration'
                ? Icons.timer
                : Icons.fitness_center;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 2),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () =>
            onTap(exercise['id'] as String, name),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: catColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: catColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  name,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
              Icon(Icons.chevron_right,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
