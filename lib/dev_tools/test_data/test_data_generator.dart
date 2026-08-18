import 'package:flutter/foundation.dart';
import 'package:workout_notes/database/database_helper.dart';

import 'test_data_context.dart';
import 'test_data_fitness_generator.dart';
import 'test_data_periodization_generator.dart';
import 'test_data_wellness_generator.dart';

/// Debug-only entry point for a complete, disposable usage scenario.
///
/// Generated rows use [devDataPrefix]. A new run first removes only rows from
/// the previous generated scenario, so repeated taps refresh the timeline
/// without duplicating data or deleting anything entered by the user.
class TestDataGenerator {
  final DatabaseHelper _databaseHelper;
  final DateTime Function() _clock;
  final int? _randomSeed;

  TestDataGenerator({
    DatabaseHelper? databaseHelper,
    DateTime Function()? clock,
    this._randomSeed,
  }) : _databaseHelper = databaseHelper ?? DatabaseHelper.instance,
       _clock = clock ?? DateTime.now;

  Future<TestDataReport> generate({int historyDays = 126}) async {
    if (!kDebugMode) {
      throw StateError('Test data can only be generated in debug builds.');
    }
    if (historyDays < 35) {
      throw ArgumentError.value(historyDays, 'historyDays', 'minimum is 35');
    }

    final db = await _databaseHelper.database;
    final now = _clock();
    final seed =
        _randomSeed ??
        now.microsecondsSinceEpoch ^ now.millisecondsSinceEpoch.hashCode;

    return db.transaction((txn) async {
      final context = TestDataContext(
        database: txn,
        now: now,
        historyDays: historyDays,
        randomSeed: seed,
      );
      await _clearPreviousScenario(context);

      final fitness = TestDataFitnessGenerator(context);
      final wellness = TestDataWellnessGenerator(context);
      final fitnessResult = await fitness.generate();
      final wellnessResult = await wellness.generate();
      final periodizationResult = await TestDataPeriodizationGenerator(
        context,
      ).generate();

      return TestDataReport(
        workouts: fitnessResult.workouts,
        routines: fitnessResult.routines,
        measurements: fitnessResult.measurements,
        sleepNights: wellnessResult.sleepNights,
        monitoredNights: wellnessResult.monitoredNights,
        nutritionDays: wellnessResult.nutritionDays,
        meals: wellnessResult.meals,
        goals: fitnessResult.goals + wellnessResult.goals,
        periodizationPlans: periodizationResult.plans,
        periodizationPhases: periodizationResult.phases,
        periodizationCheckins: periodizationResult.checkins,
      );
    });
  }

  Future<void> _clearPreviousScenario(TestDataContext context) async {
    final db = context.database;
    final like = '$devDataPrefix%';
    // Parent deletes cascade through workout, routine, food, sleep-monitor and
    // meal trees. Tables without a generated parent are removed explicitly.
    for (final table in <String>[
      'periodization_plans',
      'workouts',
      'routines',
      'sleep_entries',
      'meal_logs',
      'saved_meals',
      'foods',
      'nutrition_goals',
      'user_goals',
      'body_measurements',
    ]) {
      await db.delete(table, where: 'id LIKE ?', whereArgs: [like]);
    }
  }
}
