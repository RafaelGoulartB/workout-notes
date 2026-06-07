import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 4,
                    height: 36,
                    decoration: BoxDecoration(
                      color: exercise.categoryColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          exercise.localizedName(
                              AppLocalizations.of(context)!),
                          style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 1),
                        Text(
                          exercise.localizedCategory(
                              AppLocalizations.of(context)!),
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
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
                  if (onRemoveExercise != null) ...[
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => onRemoveExercise!(),
                      child: Container(
                        padding: const EdgeInsets.all(6),
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
              const SizedBox(height: 10),
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
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            onToggleSet(set['id'] as String);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isComplete
                                  ? theme.colorScheme.primary
                                  : Colors.transparent,
                              border: Border.all(
                                color: isComplete
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.outline
                                        .withAlpha(150),
                                width: 1.5,
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
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 32,
                          child: isWarmup
                              ? Align(
                                  alignment: Alignment.center,
                                  child: Container(
                                    padding: const EdgeInsets
                                        .symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.orange
                                          .withAlpha(35),
                                      borderRadius:
                                          BorderRadius.circular(6),
                                    ),
                                    child: Icon(
                                      Icons.local_fire_department,
                                      size: 14,
                                      color:
                                          Colors.orange.shade700,
                                    ),
                                  ),
                                )
                              : Text(
                                  '${i + 1}',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium
                                      ?.copyWith(
                                    fontWeight: FontWeight.w600,
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
              const SizedBox(height: 6),
              _buildAddSetButton(theme, context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddSetButton(ThemeData theme, BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: theme.colorScheme.primary.withAlpha(15),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onAddSet();
          },
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  AppLocalizations.of(context)!.activeWorkoutAddSet,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
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
        const SizedBox(width: 26),
        const SizedBox(width: 10),
        const SizedBox(width: 32, child: SizedBox.shrink()),
        ..._buildHeaderFieldColumns(theme, fields, keys),
        const SizedBox(width: 32),
      ],
    );
  }

  List<Widget> _buildHeaderFieldColumns(
      ThemeData theme, Map<String, String> fields, List<String> keys) {
    final hasRpe = exercise.sets.any((s) => s['rpe'] != null);
    return [
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
      if (hasRpe)
        Expanded(
          flex: 2,
          child: Text('RPE',
              style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600)),
        ),
    ];
  }

  List<Widget> _buildSetColumns(
      ExerciseWithSets ex, Map<String, dynamic> set, ThemeData theme) {
    final fields = getFieldsForType(ex.exerciseType);
    final keys = fields.keys.toList();
    final hasRpe = ex.sets.any((s) => s['rpe'] != null);
    return [
      Expanded(
        flex: 3,
        child: Text(
          formatFieldValue(set, keys[0]),
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: (set['is_complete'] as int?) == 1
                ? theme.colorScheme.onSurface
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      if (keys.length > 1)
        Expanded(
          flex: 3,
          child: Text(
            formatFieldValue(set, keys[1]),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: (set['is_complete'] as int?) == 1
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      if (hasRpe)
        Expanded(
          flex: 2,
          child: Text(
              (set['rpe'] as num?)?.toStringAsFixed(1) ?? '-',
              style: theme.textTheme.bodyMedium),
        ),
      SizedBox(
        width: 32,
        child: GestureDetector(
          onTap: () => onDeleteSet(set['id'] as String),
          behavior: HitTestBehavior.opaque,
          child: Icon(Icons.close,
              size: 18,
              color: theme.colorScheme.error.withAlpha(180)),
        ),
      ),
    ];
  }
}
