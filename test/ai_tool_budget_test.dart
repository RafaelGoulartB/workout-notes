import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/services/ai_tool_registry.dart';

import 'support/ai_heavy_user_fixture.dart';
import 'support/test_db.dart';

/// Every read tool, called with default and typical arguments against the
/// "heavy user" database, must answer with valid JSON of at most
/// [_budget] characters, and a default call must not need trimming.
const int _budget = 6000;

void main() {
  late AiToolRegistry registry;
  late HeavyUserFixture fixture;

  setUp(() async {
    final db = await installTestDb(seed: true);
    fixture = await seedHeavyUser(db);
    registry = AiToolRegistry();
  });

  tearDown(uninstallTestDb);

  Map<String, List<Map<String, dynamic>>> calls() => {
    'get_workout_history': [
      {},
      {'status': 'all', 'limit': 30},
      {'status': 'planned'},
    ],
    'get_workout_detail': [
      {'workout_id': fixture.completedWorkoutId},
      {'workout_id': fixture.plannedWorkoutId},
      {'workout_id': fixture.inProgressWorkoutId},
    ],
    'list_exercises': [
      {},
      {'sort': 'least_recent'},
      {'name_contains': 'bench', 'limit': 50},
    ],
    'get_exercise_history': [
      {'exercise_id': fixture.benchExerciseId},
      {'exercise_id': fixture.benchExerciseId, 'limit': 30},
    ],
    'get_personal_records': [
      {},
      {'exercise_id': fixture.benchExerciseId},
      {'days': 366, 'limit': 40},
    ],
    'get_training_summary': [
      {},
      {'days': 90, 'group_by': 'week'},
      {'days': 366, 'group_by': 'category'},
    ],
    'list_routines': [{}],
    'get_routine_detail': [
      {'routine_id': fixture.routineId},
      {'routine_id': fixture.routineId, 'day_id': fixture.routineDayId},
    ],
    'list_body_measurements': [
      {},
      {'latest_per_type': true},
      {'type': 'weight', 'limit': 60},
    ],
    'get_profile': [{}],
    'list_run_activities': [
      {},
      {'activity_type': 'all', 'limit': 40},
    ],
    'get_run_activity_detail': [
      {'activity_id': fixture.runActivityId},
      {'activity_id': fixture.bikeActivityId},
    ],
    'get_run_progress': [
      {},
      {'period': 'year'},
      {'period': 'all'},
    ],
    'get_cardio_summary': [
      {},
      {'days': 366},
    ],
    'get_run_achievements': [{}],
    'get_run_plan': [
      {},
      {'plan_id': fixture.runPlanId, 'weeks': 6},
    ],
    'get_run_schedule': [
      {},
      {'limit': 40},
    ],
    'list_goals': [
      {},
      {'history_periods': 12},
    ],
    'get_sleep': [
      {},
      {'detail': 'nightly', 'days': 90},
      {'detail': 'night', 'end_date': fixture.sleepNightDate},
    ],
    'get_nutrition': [
      {},
      {'detail': 'daily', 'days': 90},
      {'detail': 'micros', 'days': 90},
      {'detail': 'foods'},
      {'detail': 'day', 'end_date': fixture.diaryDate},
    ],
    'search_food_library': [
      {},
      {'limit': 30},
      {'food_id': fixture.foodId},
    ],
    'list_saved_meals': [
      {},
      {'limit': 40},
      {'saved_meal_id': fixture.savedMealId},
    ],
    'analyze_sleep_performance': [
      {},
      {'days': 90},
    ],
    'analyze_nutrition_body_trend': [
      {},
      {'days': 180},
    ],
    'get_weekly_recovery_trend': [
      {},
      {'weeks': 12},
    ],
    'get_training_plan': [
      {},
      {'review': 'week'},
      {'review': 'phase'},
    ],
  };

  test('every read tool is covered by this test', () {
    expect(calls().keys.toSet(), registry.readToolNames);
  });

  test('every call answers with valid JSON within the budget', () async {
    final sizes = <String, int>{};
    final defaults = <String, int>{};
    for (final entry in calls().entries) {
      for (final args in entry.value) {
        final result = await registry.executeRead(
          toolName: entry.key,
          args: args,
        );
        final label = '${entry.key} ${jsonEncode(args)}';
        expect(result.ok, isTrue, reason: '$label -> ${result.message}');
        final encoded = jsonEncode(result.toMap());
        expect(
          jsonDecode(encoded),
          isA<Map>(),
          reason: '$label is not valid JSON',
        );
        expect(
          encoded.length,
          lessThanOrEqualTo(_budget),
          reason: '$label is ${encoded.length} chars',
        );
        final data = result.data as Map;
        if (args.isEmpty) {
          expect(
            data.containsKey('truncated_rows'),
            isFalse,
            reason: 'default call of ${entry.key} needed trimming',
          );
        }
        defaults.putIfAbsent(entry.key, () => encoded.length);
        final size = sizes[entry.key] ?? 0;
        if (encoded.length > size) sizes[entry.key] = encoded.length;
      }
    }
    // The table is printed so the measured sizes land in the test log.
    // ignore: avoid_print
    print(
      sizes.entries
          .map((e) => '${e.key}: default ${defaults[e.key]}, max ${e.value}')
          .join('\n'),
    );
  });
}
