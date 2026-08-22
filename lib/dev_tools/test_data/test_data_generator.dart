import 'package:flutter/foundation.dart';
import 'package:workout_notes/database/database_helper.dart';

import 'test_data_context.dart';
import 'test_data_fitness_generator.dart';
import 'test_data_periodization_generator.dart';
import 'test_data_run_generator.dart';
import 'test_data_run_plan_generator.dart';
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
      final runResult = await TestDataRunGenerator(context).generate();
      final runPlanResult = await TestDataRunPlanGenerator(context).generate();
      final fitnessResult = await fitness.generate();
      final wellnessResult = await wellness.generate();
      final periodizationResult = await TestDataPeriodizationGenerator(
        context,
      ).generate();

      return TestDataReport(
        workouts: fitnessResult.workouts,
        routines: fitnessResult.routines,
        runs: runResult.runs,
        runPlans: runPlanResult.plans,
        completedRunPlans: runPlanResult.completedPlans,
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
    // Delete children before parents so the clear works even when
    // foreign_keys is temporarily off or the DB is in a partially-migrated
    // state. Parents are still deleted for cascade coverage, but every
    // generated table is cleared explicitly to avoid PK/UNIQUE leftovers
    // on a second generation (e.g. periodization child ids reused across runs).
    for (final table in <String>[
      // Periodization children -> parent
      'periodization_checkins',
      'phase_routine_links',
      'phase_targets',
      'periodization_phases',
      'periodization_plans',
      // Workout tree
      'sets',
      'exercise_entries',
      'workouts',
      // Routine tree
      'predefined_sets',
      'routine_exercises',
      'routine_days',
      'routines',
      // Run tree
      'scheduled_runs',
      'run_workout_steps',
      'run_plan_workouts',
      'run_plans',
      'run_track_points',
      'run_activities',
      // Sleep monitor tree (sessions/epochs/segments cascade from sleep_entries,
      // but delete explicitly for FK-off safety)
      'sleep_stage_epochs',
      'sleep_monitor_segments',
      'sleep_monitor_sessions',
      'sleep_entries',
      // Nutrition diary
      'meal_log_items',
      'meal_logs',
      'saved_meal_items',
      'saved_meals',
      'food_servings',
      'food_variants',
      'foods',
      'nutrition_goals',
      // Standalone
      'user_goals',
      'body_measurements',
    ]) {
      try {
        await db.delete(table, where: 'id LIKE ?', whereArgs: [like]);
      } catch (_) {
        // Table may not exist on older migrated DBs - ignore.
      }
    }
  }
}
