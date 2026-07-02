import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/workout_stats.dart';

void main() {
  test('calculates strength workout stats from completed non-warmup sets', () {
    final stats = WorkoutStats.calculate(
      workoutId: 'workout-1',
      durationSeconds: 30 * 60,
      exercises: const [
        WorkoutStatsExerciseInput(
          exerciseId: 'bench',
          name: 'Bench Press',
          categoryId: 'chest',
          categoryName: 'Chest',
          categoryColor: Colors.blue,
          sets: [
            WorkoutStatsSetInput(
              weight: 40,
              reps: 10,
              isComplete: true,
              isWarmup: true,
              rpe: 5,
            ),
            WorkoutStatsSetInput(
              weight: 80,
              reps: 10,
              isComplete: true,
              isWarmup: false,
              rpe: 8,
            ),
            WorkoutStatsSetInput(
              weight: 80,
              reps: 8,
              isComplete: true,
              isWarmup: false,
              rpe: 9,
            ),
            WorkoutStatsSetInput(
              weight: 85,
              reps: 8,
              isComplete: false,
              isWarmup: false,
              rpe: 9,
            ),
          ],
        ),
        WorkoutStatsExerciseInput(
          exerciseId: 'row',
          name: 'Row',
          categoryId: 'back',
          categoryName: 'Back',
          categoryColor: Colors.green,
          sets: [
            WorkoutStatsSetInput(
              weight: 70,
              reps: 10,
              isComplete: true,
              isWarmup: false,
              rpe: 7,
            ),
          ],
        ),
      ],
    );

    expect(stats.totalVolume, 2140);
    expect(stats.completedSets, 3);
    expect(stats.totalSets, 4);
    expect(stats.densityKgPerMinute, closeTo(71.333, 0.01));
    expect(stats.averageRpe, closeTo(8, 0.01));
    expect(stats.topSet?.exerciseId, 'bench');
    expect(stats.topSet?.volume, 800);
    expect(stats.highestVolumeExercise?.exerciseId, 'bench');
    expect(stats.categories, hasLength(2));
    expect(stats.categories.first.categoryId, 'chest');
  });

  test('does not calculate density without duration or volume', () {
    final noDuration = WorkoutStats.calculate(
      workoutId: 'workout-1',
      durationSeconds: 0,
      exercises: const [
        WorkoutStatsExerciseInput(
          exerciseId: 'bench',
          name: 'Bench Press',
          categoryName: 'Chest',
          categoryColor: Colors.blue,
          sets: [
            WorkoutStatsSetInput(
              weight: 80,
              reps: 10,
              isComplete: true,
              isWarmup: false,
            ),
          ],
        ),
      ],
    );

    final noVolume = WorkoutStats.calculate(
      workoutId: 'workout-2',
      durationSeconds: 1800,
      exercises: const [],
    );

    expect(noDuration.densityKgPerMinute, isNull);
    expect(noVolume.densityKgPerMinute, isNull);
  });
}
