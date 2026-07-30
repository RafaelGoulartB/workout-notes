/// Shared calculations for planned workout duration and calorie estimates.
///
/// The duration estimate intentionally works on normalized input objects so
/// routine screens and active workouts use exactly the same rules.
class WorkoutEstimateSet {
  final int? reps;
  final int? timeSeconds;

  const WorkoutEstimateSet({this.reps, this.timeSeconds});
}

class WorkoutEstimateExercise {
  final List<WorkoutEstimateSet> sets;
  final int? restTimeSeconds;

  const WorkoutEstimateExercise({required this.sets, this.restTimeSeconds});

  int get normalizedRestTimeSeconds {
    final rest =
        restTimeSeconds ?? WorkoutEstimateCalculator.defaultRestSeconds;
    return rest > 0 ? rest : WorkoutEstimateCalculator.defaultRestSeconds;
  }
}

class WorkoutEstimateCalculator {
  static const int secondsPerRep = 4;
  static const int fallbackSetExecutionSeconds = 30;
  static const int defaultRestSeconds = 90;
  static const double defaultMet = 5.0;

  const WorkoutEstimateCalculator._();

  /// Calculates execution time plus rests for all ordered sets.
  ///
  /// Rest is included between every pair of sets, including the transition
  /// between exercises, but never after the final set of the workout. The
  /// transition rest uses the rest configured on the preceding exercise.
  static int estimateDurationSeconds(
    Iterable<WorkoutEstimateExercise> exercises,
  ) {
    final normalizedExercises = exercises
        .where((exercise) => exercise.sets.isNotEmpty)
        .toList(growable: false);
    final totalSets = normalizedExercises.fold<int>(
      0,
      (total, exercise) => total + exercise.sets.length,
    );
    if (totalSets == 0) return 0;

    var duration = 0;
    var setIndex = 0;
    for (final exercise in normalizedExercises) {
      for (final set in exercise.sets) {
        duration += estimateSetExecutionSeconds(set);
        if (setIndex < totalSets - 1) {
          duration += exercise.normalizedRestTimeSeconds;
        }
        setIndex++;
      }
    }
    return duration;
  }

  /// Uses explicit duration first, then repetitions, then a conservative
  /// fallback for set types that do not carry either field.
  static int estimateSetExecutionSeconds(WorkoutEstimateSet set) {
    final explicitTime = set.timeSeconds;
    if (explicitTime != null && explicitTime > 0) return explicitTime;

    final reps = set.reps;
    if (reps != null && reps > 0) return reps * secondsPerRep;

    return fallbackSetExecutionSeconds;
  }

  /// Calculates calories using the standard MET equation.
  static double? estimateCalories({
    required int durationSeconds,
    required double? bodyWeightKg,
    double met = defaultMet,
  }) {
    if (durationSeconds <= 0 || bodyWeightKg == null || bodyWeightKg <= 0) {
      return null;
    }
    if (met <= 0) return null;

    final durationMinutes = durationSeconds / 60.0;
    return met * 3.5 * bodyWeightKg / 200.0 * durationMinutes;
  }

  /// Formats an estimate using whole minutes rounded up for display.
  static String? formatDuration(int durationSeconds) {
    if (durationSeconds <= 0) return null;

    final totalMinutes = (durationSeconds / 60).ceil();
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours > 0) {
      return '${hours}h ${minutes.toString().padLeft(2, '0')}min';
    }
    return '$totalMinutes min';
  }
}
