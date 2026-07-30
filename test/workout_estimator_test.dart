import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/utils/workout_estimator.dart';

void main() {
  test('uses reps, explicit time, and rest between exercises', () {
    final duration = WorkoutEstimateCalculator.estimateDurationSeconds([
      const WorkoutEstimateExercise(
        restTimeSeconds: 60,
        sets: [WorkoutEstimateSet(reps: 10), WorkoutEstimateSet(reps: 10)],
      ),
      const WorkoutEstimateExercise(
        restTimeSeconds: 90,
        sets: [WorkoutEstimateSet(reps: 5, timeSeconds: 30)],
      ),
    ]);

    // 40 + 60 + 40 + 60 + 30; no rest after the final set.
    expect(duration, 230);
  });

  test('includes warm-up sets and uses fallback execution time', () {
    final duration = WorkoutEstimateCalculator.estimateDurationSeconds([
      const WorkoutEstimateExercise(
        restTimeSeconds: 60,
        sets: [WorkoutEstimateSet(reps: 5), WorkoutEstimateSet()],
      ),
    ]);

    // 20 + 60 + 30; the warm-up is part of the planned workout.
    expect(duration, 110);
  });

  test(
    'uses the default rest time when configured rest is missing or invalid',
    () {
      final duration = WorkoutEstimateCalculator.estimateDurationSeconds([
        const WorkoutEstimateExercise(
          restTimeSeconds: 0,
          sets: [WorkoutEstimateSet(reps: 1), WorkoutEstimateSet(reps: 1)],
        ),
      ]);

      expect(duration, 8 + WorkoutEstimateCalculator.defaultRestSeconds);
    },
  );

  test('formats planned duration rounded up to whole minutes', () {
    expect(WorkoutEstimateCalculator.formatDuration(1), '1 min');
    expect(WorkoutEstimateCalculator.formatDuration(42 * 60), '42 min');
    expect(WorkoutEstimateCalculator.formatDuration(65 * 60), '1h 05min');
    expect(WorkoutEstimateCalculator.formatDuration(0), isNull);
  });

  test('calculates calories with the configured MET equation', () {
    final calories = WorkoutEstimateCalculator.estimateCalories(
      durationSeconds: 60 * 60,
      bodyWeightKg: 70,
    );

    expect(calories, closeTo(367.5, 0.001));
  });

  test('does not calculate calories without a valid body weight', () {
    expect(
      WorkoutEstimateCalculator.estimateCalories(
        durationSeconds: 60 * 60,
        bodyWeightKg: null,
      ),
      isNull,
    );
    expect(
      WorkoutEstimateCalculator.estimateCalories(
        durationSeconds: 0,
        bodyWeightKg: 70,
      ),
      isNull,
    );
  });
}
