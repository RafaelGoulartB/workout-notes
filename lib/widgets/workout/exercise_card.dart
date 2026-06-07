import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/exercise_with_sets.dart';
import 'package:workout_notes/screens/workout/exercise_detail_tabs_screen.dart';
import 'package:workout_notes/utils/workout_card_helpers.dart';

/// Card widget for an exercise during an active workout.
/// Displays set rows, rest timer, and controls.
class ExerciseCard extends StatelessWidget {
  final ExerciseWithSets exercise;
  final VoidCallback onAddSet;
  final Function(String) onToggleSet;
  final void Function(String, Map<String, dynamic>, int) onEditSet;
  final Function(String) onDeleteSet;
  final ThemeData theme;
  final ValueChanged<int> onChangeRestTime;
  final VoidCallback? onRemoveExercise;

  const ExerciseCard({
    super.key,
    required this.exercise,
    required this.onAddSet,
    required this.onToggleSet,
    required this.onEditSet,
    required this.onDeleteSet,
    required this.theme,
    required this.onChangeRestTime,
    this.onRemoveExercise,
  });

  void _showExerciseModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Icon(Icons.fitness_center,
                      size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      exercise.localizedName(
                          AppLocalizations.of(context)!),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: Text(
                  AppLocalizations.of(context)!.workoutDetailViewExercise),
              subtitle: Text(exercise.localizedName(
                  AppLocalizations.of(context)!)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ExerciseDetailTabsScreen(
                      exerciseId: exercise.exerciseId,
                      exerciseName: exercise.localizedName(
                          AppLocalizations.of(context)!),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final restMin = exercise.restTimeSeconds ~/ 60;
    final restSec = exercise.restTimeSeconds % 60;
    final restStr =
        restMin > 0 ? '${restMin}min$restSec' : '${restSec}s';

    return GestureDetector(
      onLongPress: () => _showExerciseModal(context),
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
              color: theme.colorScheme.outlineVariant.withAlpha(80)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 4,
                    height: 24,
                    decoration: BoxDecoration(
                      color: exercise.categoryColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      exercise.localizedName(
                          AppLocalizations.of(context)!),
                      style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  GestureDetector(
                    onTap: () =>
                        onChangeRestTime(exercise.restTimeSeconds),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.timer_outlined,
                              size: 14,
                              color: theme.colorScheme.primary),
                          const SizedBox(width: 4),
                          Text(
                            restStr,
                            style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    exercise.localizedCategory(AppLocalizations.of(context)!),
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                  if (onRemoveExercise != null) ...[
                    const SizedBox(width: 2),
                    GestureDetector(
                      onTap: () => onRemoveExercise!(),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.error.withAlpha(20),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.close,
                            size: 16, color: theme.colorScheme.error),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              _buildHeaderRow(theme),
              const Divider(height: 4),
              ...List.generate(exercise.sets.length, (i) {
                final set = exercise.sets[i];
                final isComplete =
                    (set['is_complete'] as int?) == 1;
                final isWarmup = (set['is_warmup'] as int?) == 1;
                return InkWell(
                  onTap: () =>
                      onEditSet(set['id'] as String, set, i + 1),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () =>
                              onToggleSet(set['id'] as String),
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isComplete
                                  ? theme.colorScheme.primary
                                  : null,
                              border: Border.all(
                                color: isComplete
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.outline,
                              ),
                            ),
                            child: isComplete
                                ? Icon(Icons.check,
                                    size: 16,
                                    color: theme
                                        .colorScheme.onPrimary)
                                : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: Text(
                            isWarmup ? 'W' : '${i + 1}',
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: isWarmup
                                  ? Colors.orange
                                  : null,
                            ),
                          ),
                        ),
                        ..._buildSetColumns(
                            exercise, set, theme),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: onAddSet,
                icon: const Icon(Icons.add, size: 18),
                label: Text(AppLocalizations.of(context)!
                    .activeWorkoutAddSet),
                style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderRow(ThemeData theme) {
    final fields = getFieldsForType(exercise.exerciseType);
    final keys = fields.keys.toList();
    return Row(
      children: [
        const SizedBox(width: 24),
        Expanded(
          flex: 2,
          child: Text('#',
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
        ),
        Expanded(
          flex: 3,
          child: Text(fields[keys[0]] ?? '',
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
        ),
        if (keys.length > 1)
          Expanded(
            flex: 3,
            child: Text(fields[keys[1]] ?? '',
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ),
        if (exercise.sets.any((s) => s['rpe'] != null))
          Expanded(
            flex: 2,
            child: Text('RPE',
                style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600)),
          ),
        const SizedBox(width: 40),
      ],
    );
  }

  List<Widget> _buildSetColumns(
      ExerciseWithSets ex, Map<String, dynamic> set, ThemeData theme) {
    final fields = getFieldsForType(ex.exerciseType);
    final keys = fields.keys.toList();
    return [
      Expanded(
        flex: 3,
        child: Text(formatFieldValue(set, keys[0]),
            style: theme.textTheme.bodyMedium),
      ),
      if (keys.length > 1)
        Expanded(
          flex: 3,
          child: Text(formatFieldValue(set, keys[1]),
              style: theme.textTheme.bodyMedium),
        ),
      if (ex.sets.any((s) => s['rpe'] != null))
        Expanded(
          flex: 2,
          child: Text(
              (set['rpe'] as num?)?.toStringAsFixed(1) ?? '-',
              style: theme.textTheme.bodyMedium),
        ),
      GestureDetector(
        onTap: () => onDeleteSet(set['id'] as String),
        child: Icon(Icons.close,
            size: 16,
            color: theme.colorScheme.error.withAlpha(180)),
      ),
    ];
  }
}
