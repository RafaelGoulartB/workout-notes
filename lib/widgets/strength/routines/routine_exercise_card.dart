import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/l10n/exercise_locale_helper.dart';
import 'package:workout_notes/utils/strength_routine_format.dart';
import 'package:workout_notes/utils/strength_routine_summary.dart';
import 'package:workout_notes/utils/workout_card_helpers.dart';
import 'package:workout_notes/utils/workout_estimator.dart';
import 'package:workout_notes/widgets/strength/routines/routine_muscle_widgets.dart';
import 'package:workout_notes/widgets/strength/routines/routine_set_sheets.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Summary on top of the day editor: exercises, sets, time and volume plus
/// the muscle split of the day.
class RoutineDaySummaryCard extends StatelessWidget {
  final RoutineDaySummary summary;

  const RoutineDaySummaryCard({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final duration = WorkoutEstimateCalculator.formatDuration(
      summary.estimatedSeconds,
    );
    return AppHeroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppStatRow(
            children: [
              AppStatTile(
                icon: Icons.fitness_center_rounded,
                label: loc.routineStatExercises,
                value: '${summary.exerciseCount}',
              ),
              AppStatTile(
                icon: Icons.stacked_bar_chart_rounded,
                label: loc.commonSets,
                value: '${summary.workingSets}',
              ),
              AppStatTile(
                icon: Icons.timer_outlined,
                label: loc.routineStatSession,
                value: duration ?? '--',
              ),
              if (summary.volumeKg > 0)
                AppStatTile(
                  icon: Icons.scale_rounded,
                  label: loc.commonVolume,
                  value: StrengthRoutineFormat.volume(summary.volumeKg),
                  unit: 'kg',
                ),
            ],
          ),
          if (summary.muscles.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              loc.routineDayMusclesTitle.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            RoutineMuscleBar(muscles: summary.muscles, height: 8),
            const SizedBox(height: 8),
            RoutineMuscleChips(
              muscles: summary.muscles,
              max: 6,
              showSets: true,
            ),
          ],
        ],
      ),
    );
  }
}

/// Callbacks of one exercise card of the day editor.
class RoutineExerciseCardActions {
  final VoidCallback onRest;
  final VoidCallback onDetails;
  final VoidCallback onRemove;
  final VoidCallback onAddSet;
  final void Function(Map<String, dynamic> set, int number) onEditSet;
  final void Function(Map<String, dynamic> set) onRemoveSet;

  const RoutineExerciseCardActions({
    required this.onRest,
    required this.onDetails,
    required this.onRemove,
    required this.onAddSet,
    required this.onEditSet,
    required this.onRemoveSet,
  });
}

/// An exercise of the day with its preset sets. The whole card is a drag
/// target (long-press) in the reorderable list.
class RoutineExerciseCard extends StatelessWidget {
  final Map<String, dynamic> exercise;
  final List<Map<String, dynamic>> sets;
  final RoutineExerciseCardActions actions;

  const RoutineExerciseCard({
    super.key,
    required this.exercise,
    required this.sets,
    required this.actions,
  });

  String _name(AppLocalizations loc) => ExerciseLocaleHelper.exerciseName(loc, {
    'locale_key': exercise['exercise_locale_key'],
    'name': exercise['exercise_name'],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final exerciseType = exercise['exercise_type'] as String? ?? 'weightReps';
    final keys = getFieldsForType(exerciseType);
    final color = Color(exercise['category_color'] as int? ?? 0xFF757575);
    final categoryName = ExerciseLocaleHelper.categoryName(loc, exercise);
    final restSeconds = (exercise['rest_time_seconds'] as int?) ?? 90;
    final workingSets = sets.where((s) => (s['is_warmup'] as int?) != 1).length;
    final headerStyle = theme.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w700,
      color: scheme.onSurfaceVariant,
    );
    // Working sets are numbered 1..n; warm-ups get a letter instead.
    final workingNumbers = <int>[];
    var counter = 0;
    for (final s in sets) {
      if ((s['is_warmup'] as int?) != 1) counter++;
      workingNumbers.add(counter);
    }

    return AppSectionCard(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.drag_indicator,
                size: 20,
                color: scheme.onSurfaceVariant.withAlpha(140),
              ),
              const SizedBox(width: 4),
              Container(
                width: 4,
                height: 34,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _name(loc),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '$categoryName · ${loc.routinesSetsValue(workingSets)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: actions.onRest,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: AppPill(
                    icon: Icons.timer_outlined,
                    label: StrengthRoutineFormat.rest(restSeconds),
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: loc.commonMoreOptions,
                onSelected: (value) {
                  if (value == 'details') actions.onDetails();
                  if (value == 'remove') actions.onRemove();
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: 'details',
                    child: Text(loc.routineExerciseDetails),
                  ),
                  PopupMenuItem(
                    value: 'remove',
                    child: Text(
                      loc.routineExerciseRemove,
                      style: TextStyle(color: scheme.error),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (sets.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: Text(
                loc.routineSetNoSets,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            )
          else ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Row(
                children: [
                  SizedBox(width: 28, child: Text('#', style: headerStyle)),
                  for (final key in keys)
                    Expanded(
                      child: Text(
                        workoutFieldLabel(loc, key),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: headerStyle,
                      ),
                    ),
                  const SizedBox(width: 32),
                ],
              ),
            ),
            for (var i = 0; i < sets.length; i++)
              Builder(
                builder: (context) {
                  final set = sets[i];
                  final warmup = (set['is_warmup'] as int?) == 1;
                  return InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => actions.onEditSet(set, i + 1),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 0, 0),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 28,
                            child: Text(
                              warmup
                                  ? loc.routineSetWarmupLetter
                                  : '${workingNumbers[i]}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: warmup ? Colors.orange : null,
                              ),
                            ),
                          ),
                          for (final key in keys)
                            Expanded(
                              child: Text(
                                routineSetCell(set, key),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontFeatures: AppUi.tabular,
                                ),
                              ),
                            ),
                          IconButton(
                            tooltip: loc.routineSetRemove,
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            padding: EdgeInsets.zero,
                            icon: Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: scheme.error.withAlpha(190),
                            ),
                            onPressed: () => actions.onRemoveSet(set),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: actions.onAddSet,
              icon: const Icon(Icons.add, size: 18),
              label: Text(loc.activeWorkoutAddSet),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ),
        ],
      ),
    );
  }
}
