import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/exercise_with_sets.dart';
import 'package:workout_notes/repositories/strength_records_repository.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/utils/strength_workout_format.dart';
import 'package:workout_notes/utils/workout_card_helpers.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// One exercise of a finished workout: totals line and a sets table
/// (warm-ups muted, a star on the sets that set a record).
class StrengthWorkoutExerciseCard extends StatelessWidget {
  final ExerciseWithSets exercise;

  /// Set id -> record kinds earned by that set.
  final Map<String, Set<StrengthRecordKind>> marks;
  final VoidCallback? onOpenExercise;

  const StrengthWorkoutExerciseCard({
    super.key,
    required this.exercise,
    this.marks = const {},
    this.onOpenExercise,
  });

  static bool _isWarmup(Map<String, dynamic> s) =>
      (s['is_warmup'] as int?) == 1;
  static bool _isDone(Map<String, dynamic> s) =>
      (s['is_complete'] as int?) == 1;

  /// Best estimated 1RM among the working sets, if the exercise is loaded.
  static double? bestE1rm(List<Map<String, dynamic>> sets) {
    double? best;
    for (final s in sets) {
      if (_isWarmup(s) || !_isDone(s)) continue;
      final e = strengthE1rm(
        (s['weight'] as num?)?.toDouble() ?? 0,
        (s['reps'] as num?)?.toInt() ?? 0,
      );
      if (e != null && (best == null || e > best)) best = e;
    }
    return best;
  }

  static double volumeOf(List<Map<String, dynamic>> sets) {
    var volume = 0.0;
    for (final s in sets) {
      if (_isWarmup(s) || !_isDone(s)) continue;
      volume +=
          ((s['weight'] as num?)?.toDouble() ?? 0) *
          ((s['reps'] as num?)?.toInt() ?? 0);
    }
    return volume;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final workingSets = exercise.sets
        .where((s) => !_isWarmup(s) && _isDone(s))
        .length;
    final volume = volumeOf(exercise.sets);
    final e1rm = bestE1rm(exercise.sets);
    final summary = [
      loc.strengthHistorySets(workingSets),
      if (e1rm != null)
        loc.workoutDetailE1rmValue(
          // An estimate: one decimal is plenty.
          StrengthWorkoutFormat.weightKg((e1rm * 10).round() / 10),
        ),
    ].join(' · ');

    return AppSectionCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onOpenExercise,
            borderRadius: BorderRadius.circular(8),
            child: Row(
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
                    children: [
                      Text(
                        exercise.localizedName(loc),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${exercise.localizedCategory(loc)} · $summary',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (volume > 0) ...[
                  const SizedBox(width: 8),
                  Text(
                    StrengthWorkoutFormat.volume(volume),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      fontFeatures: AppUi.tabular,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (exercise.sets.isEmpty)
            Text(
              loc.workoutDetailNoSets,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            )
          else
            _SetsTable(exercise: exercise, marks: marks),
        ],
      ),
    );
  }
}

class _SetsTable extends StatelessWidget {
  final ExerciseWithSets exercise;
  final Map<String, Set<StrengthRecordKind>> marks;

  const _SetsTable({required this.exercise, required this.marks});

  static String _value(Map<String, dynamic> set, String key) {
    switch (key) {
      case 'weight':
        final v = (set['weight'] as num?)?.toDouble();
        return v == null ? '-' : StrengthWorkoutFormat.weight(v);
      case 'distance':
        final v = (set['distance'] as num?)?.toDouble();
        return v == null ? '-' : RunFormatters.decimal(v, 2);
      default:
        return formatFieldValue(set, key);
    }
  }

  static String _header(AppLocalizations loc, String key) => switch (key) {
    'weight' => loc.workoutDetailWeight,
    'reps' => loc.commonReps,
    'distance' => loc.workoutDetailDistance,
    'time_seconds' => loc.workoutDetailTime,
    _ => key,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final keys = getFieldsForType(exercise.exerciseType);
    final hasRpe = exercise.sets.any((s) => s['rpe'] != null);
    final header = theme.textTheme.labelSmall?.copyWith(
      color: colors.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    );

    Widget cell(String text, {int flex = 3, TextStyle? style}) => Expanded(
      flex: flex,
      child: Text(
        text,
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    var workingIndex = 0;
    return Column(
      children: [
        Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(loc.workoutDetailSetNumber, style: header),
            ),
            for (final key in keys) cell(_header(loc, key), style: header),
            if (hasRpe) cell(loc.workoutDetailRpe, flex: 2, style: header),
            const SizedBox(width: 24),
          ],
        ),
        Divider(height: 8, color: AppUi.divider(colors)),
        for (final set in exercise.sets)
          Builder(
            builder: (context) {
              final warmup = (set['is_warmup'] as int?) == 1;
              final done = (set['is_complete'] as int?) == 1;
              final muted = warmup || !done;
              if (!warmup) workingIndex++;
              final base = theme.textTheme.bodyMedium?.copyWith(
                fontWeight: warmup ? FontWeight.w500 : FontWeight.w700,
                color: muted ? colors.onSurfaceVariant : colors.onSurface,
                fontFeatures: AppUi.tabular,
                decoration: !warmup && !done
                    ? TextDecoration.lineThrough
                    : null,
              );
              final isRecord = marks.containsKey(set['id']);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 28,
                      child: Text(
                        warmup ? loc.workoutDetailWarmupShort : '$workingIndex',
                        style: base?.copyWith(
                          decoration: null,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    for (final key in keys) cell(_value(set, key), style: base),
                    if (hasRpe)
                      cell(
                        set['rpe'] == null
                            ? '-'
                            : RunFormatters.decimal(
                                (set['rpe'] as num).toDouble(),
                                1,
                              ),
                        flex: 2,
                        style: base,
                      ),
                    SizedBox(
                      width: 24,
                      child: isRecord
                          ? Icon(
                              Icons.emoji_events_rounded,
                              size: 18,
                              color: colors.tertiary,
                              semanticLabel: loc.workoutDetailRecordSet,
                            )
                          : null,
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}
