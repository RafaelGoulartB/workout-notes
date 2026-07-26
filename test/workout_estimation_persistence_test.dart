import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/repositories/body_measurement_repository.dart';
import 'package:workout_notes/repositories/workout_repository.dart';

import 'support/ai_test_db.dart';

void main() {
  late Database db;
  setUp(() async {
    db = await installAiTestDb();
  });
  tearDown(uninstallAiTestDb);

  test('persists estimated calories when a workout is finished', () async {
    final now = DateTime.now();
    await db.insert('workouts', {
      'id': 'workout-1',
      'date': now.toIso8601String().substring(0, 10),
      'start_time': now.subtract(const Duration(minutes: 45)).toIso8601String(),
      'created_at': now.toIso8601String(),
    });

    final repository = WorkoutRepository();
    await repository.finishWorkout('workout-1', estimatedCalories: 275.5);

    final workout = await repository.getWorkout('workout-1');
    expect(workout?['estimated_calories'], closeTo(275.5, 0.001));
    expect(workout?['end_time'], isNotNull);
  });

  test('returns the latest body weight normalized to kilograms', () async {
    final now = DateTime.now();
    await db.insert('body_measurements', {
      'id': 'weight-old',
      'type': 'weight',
      'value': 70,
      'unit': 'kg',
      'date': now
          .subtract(const Duration(days: 1))
          .toIso8601String()
          .substring(0, 10),
      'created_at': now.subtract(const Duration(days: 1)).toIso8601String(),
    });
    await db.insert('body_measurements', {
      'id': 'weight-new',
      'type': 'weight',
      'value': 154.324,
      'unit': 'lb',
      'date': now.toIso8601String().substring(0, 10),
      'created_at': now.toIso8601String(),
    });

    final weight = await BodyMeasurementRepository().getLatestWeightKg();
    expect(weight, closeTo(70, 0.01));
  });
}
