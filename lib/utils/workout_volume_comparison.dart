import 'package:workout_notes/models/exercise_with_sets.dart';

/// Volume of the running workout against the previous session of each
/// exercise, per exercise and per muscle group.
class WorkoutVolumeComparisons {
  final Map<String, ExerciseVolumeComparison> exercises;
  final List<CategoryVolumeComparison> categories;

  const WorkoutVolumeComparisons({
    this.exercises = const {},
    this.categories = const [],
  });

  static const empty = WorkoutVolumeComparisons();

  /// The current side comes from the in-memory sets (every non-warm-up set
  /// with a weight and reps, done or not); [lastVolumes] is the previous
  /// finished session's completed volume per exercise id (see
  /// `WorkoutRepository.getLastCompletedVolumes`), which does not change while
  /// the workout is edited. So set edits refresh the comparison without
  /// touching the database.
  factory WorkoutVolumeComparisons.compute(
    List<ExerciseWithSets> exercises,
    Map<String, double> lastVolumes,
  ) {
    final current = <String, double>{};
    final order = <String>[];
    final byExercise = <String, ExerciseWithSets>{};
    for (final exercise in exercises) {
      if (exercise.exerciseType != 'weightReps') continue;
      final id = exercise.exerciseId;
      if (!byExercise.containsKey(id)) {
        byExercise[id] = exercise;
        order.add(id);
      }
      current[id] = (current[id] ?? 0) + _workingVolume(exercise);
    }

    final perExercise = <String, ExerciseVolumeComparison>{};
    final perCategory = <String, _CategoryTotal>{};
    for (final id in order) {
      final currentVolume = current[id] ?? 0;
      final lastVolume = lastVolumes[id] ?? 0;
      perExercise[id] = ExerciseVolumeComparison(
        exerciseId: id,
        currentVolume: currentVolume,
        lastVolume: lastVolume,
      );
      final exercise = byExercise[id]!;
      final total = perCategory.putIfAbsent(
        exercise.categoryId ?? '',
        () => _CategoryTotal(exercise),
      );
      total.current += currentVolume;
      total.last += lastVolume;
    }

    final categories =
        perCategory.entries
            .where((e) => e.value.current > 0 || e.value.last > 0)
            .map(
              (e) => CategoryVolumeComparison(
                categoryId: e.key,
                categoryName: e.value.sample.categoryName,
                categoryColor: e.value.sample.categoryColor,
                currentVolume: e.value.current,
                lastVolume: e.value.last,
              ),
            )
            .toList()
          ..sort((a, b) {
            final byCurrent = b.currentVolume.compareTo(a.currentVolume);
            if (byCurrent != 0) return byCurrent;
            return b.lastVolume.compareTo(a.lastVolume);
          });
    return WorkoutVolumeComparisons(
      exercises: perExercise,
      categories: categories,
    );
  }

  static double _workingVolume(ExerciseWithSets exercise) {
    var volume = 0.0;
    for (final set in exercise.sets) {
      if ((set['is_warmup'] as int?) == 1) continue;
      final weight = (set['weight'] as num?)?.toDouble();
      final reps = (set['reps'] as num?)?.toInt();
      if (weight == null || reps == null) continue;
      volume += weight * reps;
    }
    return volume;
  }
}

class _CategoryTotal {
  final ExerciseWithSets sample;
  double current = 0;
  double last = 0;

  _CategoryTotal(this.sample);
}
