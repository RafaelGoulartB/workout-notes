import 'dart:ui';

class WorkoutStatsSetInput {
  final double weight;
  final int reps;
  final bool isComplete;
  final bool isWarmup;
  final double? rpe;

  const WorkoutStatsSetInput({
    required this.weight,
    required this.reps,
    required this.isComplete,
    required this.isWarmup,
    this.rpe,
  });

  double get volume => weight * reps;
}

class WorkoutStatsExerciseInput {
  final String exerciseId;
  final String name;
  final String? localeKey;
  final String? categoryId;
  final String categoryName;
  final Color categoryColor;
  final List<WorkoutStatsSetInput> sets;

  const WorkoutStatsExerciseInput({
    required this.exerciseId,
    required this.name,
    this.localeKey,
    this.categoryId,
    required this.categoryName,
    required this.categoryColor,
    required this.sets,
  });
}

class WorkoutTopSet {
  final String exerciseId;
  final String exerciseName;
  final String? exerciseLocaleKey;
  final double weight;
  final int reps;
  final double volume;

  const WorkoutTopSet({
    required this.exerciseId,
    required this.exerciseName,
    this.exerciseLocaleKey,
    required this.weight,
    required this.reps,
    required this.volume,
  });
}

class ExerciseWorkoutStats {
  final String exerciseId;
  final String name;
  final String? localeKey;
  final String? categoryId;
  final String categoryName;
  final Color categoryColor;
  final double volume;
  final int completedSets;
  final WorkoutTopSet? topSet;

  const ExerciseWorkoutStats({
    required this.exerciseId,
    required this.name,
    this.localeKey,
    this.categoryId,
    required this.categoryName,
    required this.categoryColor,
    required this.volume,
    required this.completedSets,
    this.topSet,
  });
}

class CategoryWorkoutStats {
  final String? categoryId;
  final String categoryName;
  final Color categoryColor;
  final double volume;
  final int completedSets;

  const CategoryWorkoutStats({
    this.categoryId,
    required this.categoryName,
    required this.categoryColor,
    required this.volume,
    required this.completedSets,
  });
}

class WorkoutStats {
  final String workoutId;
  final int durationSeconds;
  final double totalVolume;
  final int completedSets;
  final int totalSets;
  final double? averageRpe;
  final WorkoutTopSet? topSet;
  final ExerciseWorkoutStats? highestVolumeExercise;
  final List<ExerciseWorkoutStats> exercises;
  final List<CategoryWorkoutStats> categories;

  const WorkoutStats({
    required this.workoutId,
    required this.durationSeconds,
    required this.totalVolume,
    required this.completedSets,
    required this.totalSets,
    this.averageRpe,
    this.topSet,
    this.highestVolumeExercise,
    this.exercises = const [],
    this.categories = const [],
  });

  double? get densityKgPerMinute {
    if (durationSeconds <= 0 || totalVolume <= 0) return null;
    return totalVolume / (durationSeconds / 60.0);
  }

  bool get hasStrengthData => totalVolume > 0 || completedSets > 0;

  static WorkoutStats calculate({
    required String workoutId,
    required int durationSeconds,
    required List<WorkoutStatsExerciseInput> exercises,
  }) {
    var totalVolume = 0.0;
    var completedSets = 0;
    var totalSets = 0;
    final rpes = <double>[];
    WorkoutTopSet? workoutTopSet;
    final exerciseStats = <ExerciseWorkoutStats>[];
    final categoryAccumulators = <String, _CategoryAccumulator>{};

    for (final exercise in exercises) {
      var exerciseVolume = 0.0;
      var exerciseCompletedSets = 0;
      WorkoutTopSet? exerciseTopSet;

      for (final set in exercise.sets) {
        if (set.isWarmup) continue;
        totalSets++;
        if (!set.isComplete) continue;

        completedSets++;
        exerciseCompletedSets++;
        totalVolume += set.volume;
        exerciseVolume += set.volume;
        if (set.rpe != null) rpes.add(set.rpe!);

        if (set.volume > 0 &&
            (exerciseTopSet == null || set.volume > exerciseTopSet.volume)) {
          exerciseTopSet = WorkoutTopSet(
            exerciseId: exercise.exerciseId,
            exerciseName: exercise.name,
            exerciseLocaleKey: exercise.localeKey,
            weight: set.weight,
            reps: set.reps,
            volume: set.volume,
          );
        }
      }

      if (exerciseCompletedSets > 0 || exerciseVolume > 0) {
        if (exerciseTopSet != null &&
            (workoutTopSet == null ||
                exerciseTopSet.volume > workoutTopSet.volume)) {
          workoutTopSet = exerciseTopSet;
        }

        exerciseStats.add(
          ExerciseWorkoutStats(
            exerciseId: exercise.exerciseId,
            name: exercise.name,
            localeKey: exercise.localeKey,
            categoryId: exercise.categoryId,
            categoryName: exercise.categoryName,
            categoryColor: exercise.categoryColor,
            volume: exerciseVolume,
            completedSets: exerciseCompletedSets,
            topSet: exerciseTopSet,
          ),
        );

        final categoryKey = exercise.categoryId ?? exercise.categoryName;
        final category = categoryAccumulators.putIfAbsent(
          categoryKey,
          () => _CategoryAccumulator(
            categoryId: exercise.categoryId,
            categoryName: exercise.categoryName,
            categoryColor: exercise.categoryColor,
          ),
        );
        category.volume += exerciseVolume;
        category.completedSets += exerciseCompletedSets;
      }
    }

    exerciseStats.sort((a, b) => b.volume.compareTo(a.volume));
    final categoryStats =
        categoryAccumulators.values
            .map(
              (category) => CategoryWorkoutStats(
                categoryId: category.categoryId,
                categoryName: category.categoryName,
                categoryColor: category.categoryColor,
                volume: category.volume,
                completedSets: category.completedSets,
              ),
            )
            .toList()
          ..sort((a, b) => b.volume.compareTo(a.volume));

    return WorkoutStats(
      workoutId: workoutId,
      durationSeconds: durationSeconds,
      totalVolume: totalVolume,
      completedSets: completedSets,
      totalSets: totalSets,
      averageRpe: rpes.isEmpty
          ? null
          : rpes.fold<double>(0, (sum, rpe) => sum + rpe) / rpes.length,
      topSet: workoutTopSet,
      highestVolumeExercise: exerciseStats.isEmpty ? null : exerciseStats.first,
      exercises: exerciseStats,
      categories: categoryStats,
    );
  }
}

class WorkoutStatsComparison {
  final WorkoutStats current;
  final WorkoutStats previous;

  const WorkoutStatsComparison({required this.current, required this.previous});

  double get volumeDelta => current.totalVolume - previous.totalVolume;

  double? get densityDelta {
    final currentDensity = current.densityKgPerMinute;
    final previousDensity = previous.densityKgPerMinute;
    if (currentDensity == null || previousDensity == null) return null;
    return currentDensity - previousDensity;
  }

  int get setsDelta => current.completedSets - previous.completedSets;

  int get durationDelta => current.durationSeconds - previous.durationSeconds;

  bool get hasAnyDelta =>
      previous.hasStrengthData ||
      previous.durationSeconds > 0 ||
      previous.completedSets > 0;
}

class _CategoryAccumulator {
  final String? categoryId;
  final String categoryName;
  final Color categoryColor;
  double volume = 0;
  int completedSets = 0;

  _CategoryAccumulator({
    this.categoryId,
    required this.categoryName,
    required this.categoryColor,
  });
}
