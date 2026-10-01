import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/models/goal.dart';
import 'package:workout_notes/models/periodization_schedule.dart';
import 'package:workout_notes/models/periodization_target.dart';
import 'package:workout_notes/services/ai_goal_tool_service.dart';
import 'package:workout_notes/services/ai_planning_tool_service.dart';
import 'package:workout_notes/services/ai_profile_tool_service.dart';
import 'package:workout_notes/utils/date_utils.dart';

import 'support/ai_test_db.dart';
import 'support/strength_workout_seed.dart';

void main() {
  late Database db;
  final today = dayOf(DateTime.now());

  setUp(() async {
    db = await installAiTestDb();
  });

  tearDown(uninstallAiTestDb);

  group('list_body_measurements', () {
    Future<void> measure(
      String type,
      double value,
      String unit,
      int daysAgo, {
      double? secondary,
      String? side,
      bool fasted = false,
    }) => DatabaseHelper.instance.bodyMeasurementRepo.addBodyMeasurement(
      type,
      value,
      unit,
      secondaryValue: secondary,
      date: addDays(today, -daysAgo),
      side: side,
      isFasted: fasted,
      timeOfDay: fasted ? 'morning' : null,
    );

    test(
      'exposes secondary value, side and fasting; filters by date',
      () async {
        await measure('weight', 84, 'kg', 30, fasted: true);
        await measure('weight', 83, 'kg', 10, fasted: true);
        await measure('weight', 82.5, 'kg', 1);
        await measure('bloodPressure', 120, 'mmHg', 5, secondary: 80);
        await measure('arm', 36, 'cm', 2, side: 'left');
        final service = AiProfileToolService();

        final all = await service.measurements();
        final rows = (all['measurements'] as List).cast<Map>();
        expect(rows.first['date'], dateKey(addDays(today, -1)));
        expect(all['total'], 5);
        final pressure = rows.firstWhere((r) => r['type'] == 'bloodPressure');
        expect(pressure['secondary_value'], 80);
        expect(rows.firstWhere((r) => r['type'] == 'arm')['side'], 'left');
        expect(rows.firstWhere((r) => r['value'] == 83)['is_fasted'], isTrue);

        final window = await service.measurements(
          startDate: dateKey(addDays(today, -12)),
          endDate: dateKey(addDays(today, -2)),
        );
        expect(
          (window['measurements'] as List).map((r) => (r as Map)['type']),
          containsAll(['weight', 'bloodPressure', 'arm']),
        );
        expect(window['total'], 3);
      },
    );

    test('latest_per_type gives one row per type and side', () async {
      await measure('weight', 84, 'kg', 30);
      await measure('weight', 82.5, 'kg', 1);
      await measure('arm', 36, 'cm', 20, side: 'left');
      await measure('arm', 36.5, 'cm', 3, side: 'left');
      await measure('arm', 37, 'cm', 3, side: 'right');
      final latest = await AiProfileToolService().measurements(
        latestPerType: true,
      );
      final rows = (latest['measurements'] as List).cast<Map>();
      expect(rows, hasLength(3));
      expect(
        {for (final r in rows) '${r['type']}-${r['side']}': r['value']},
        {'arm-left': 36.5, 'arm-right': 37, 'weight-null': 82.5},
      );
    });

    test('one type adds the change over the range', () async {
      await measure('weight', 84, 'kg', 30);
      await measure('weight', 82, 'kg', 1);
      final result = await AiProfileToolService().measurements(type: 'weight');
      final change = result['change'] as Map;
      expect(change['from'], 84);
      expect(change['to'], 82);
      expect(change['change'], -2);
      expect(change['change_pct'], closeTo(-2.381, 0.001));
    });
  });

  test('get_profile gathers body basics, units and goals', () async {
    for (final entry in {
      'nutrition_profile_sex': 'female',
      'nutrition_profile_age': '29',
      'nutrition_profile_height_cm': '165',
      'nutrition_profile_activity': 'active',
      'unit_system': 'lbs',
      'distance_unit': 'mi',
      'sleep_goal_minutes': '450',
    }.entries) {
      await db.insert('app_settings', {'key': entry.key, 'value': entry.value});
    }
    await DatabaseHelper.instance.bodyMeasurementRepo.addBodyMeasurement(
      'weight',
      61.2,
      'kg',
    );
    await db.insert('nutrition_goals', {
      'id': 'g',
      'calories': 2100.0,
      'protein_g': 130.0,
      'carbs_g': 240.0,
      'fat_g': 60.0,
      'created_at': '2026-01-01',
      'updated_at': '2026-01-01',
      'is_active': 1,
    });
    final profile = await AiProfileToolService().profile();
    expect(profile['sex'], 'female');
    expect(profile['age'], 29);
    expect(profile['height_cm'], 165);
    expect(profile['units'], {'weight': 'lbs', 'distance': 'mi'});
    expect(profile['latest_weight'], containsPair('value', 61.2));
    expect((profile['nutrition_goal'] as Map)['calories'], 2100);
    expect((profile['nutrition_goal'] as Map)['source'], 'settings');
    expect(profile['sleep_goal_min'], 450);
    expect(profile['sleep_goal_source'], 'user');
  });

  group('list_goals', () {
    Future<void> goal(
      String id,
      GoalScope scope,
      GoalMetric metric,
      GoalPeriod period,
      double target,
    ) => DatabaseHelper.instance.goalRepo.insert(
      Goal(
        id: id,
        title: id,
        scope: scope,
        metric: metric,
        period: period,
        targetValue: target,
        createdAt: DateTime(2026, 1, 1),
      ),
    );

    test(
      'progress_pct is a real percent and values carry their unit',
      () async {
        await seedStrengthBasics(db);
        await seedWorkout(
          db,
          'w',
          date: dateKey(today),
          exercises: [
            ('bench', [seedSet(80, 10)]),
          ],
        );
        await goal(
          'volume',
          GoalScope.anaerobic,
          GoalMetric.volume,
          GoalPeriod.weekly,
          10000,
        );
        await goal(
          'distance',
          GoalScope.aerobic,
          GoalMetric.distance,
          GoalPeriod.monthly,
          80,
        );
        final service = AiGoalToolService();

        final result = await service.listGoals();
        final goals = {
          for (final row in (result['goals'] as List).cast<Map>())
            row['id']: row,
        };
        final volume = goals['volume']!;
        expect(volume['current'], 800);
        expect(volume['target'], 10000);
        expect(
          volume['progress_pct'],
          closeTo(8, 0.001),
          reason: '800/10000 is 8 percent, not 0.08',
        );
        expect(volume['unit'], 'kg');
        expect(goals['distance']!['unit'], 'km');

        await db.insert('app_settings', {
          'key': 'distance_unit',
          'value': 'mi',
        });
        final miles = await service.listGoals(metric: 'distance');
        expect(((miles['goals'] as List).single as Map)['unit'], 'mi');
        expect((miles['goals'] as List), hasLength(1));
      },
    );

    test('filters, active-only and history periods', () async {
      await goal(
        'a',
        GoalScope.anaerobic,
        GoalMetric.days,
        GoalPeriod.weekly,
        3,
      );
      await goal(
        'b',
        GoalScope.aerobic,
        GoalMetric.time,
        GoalPeriod.weekly,
        3600,
      );
      await DatabaseHelper.instance.goalRepo.toggleActive('b', false);
      final service = AiGoalToolService();
      expect(
        ((await service.listGoals())['goals'] as List).map(
          (g) => (g as Map)['id'],
        ),
        ['a'],
      );
      expect(
        ((await service.listGoals(activeOnly: false))['goals'] as List),
        hasLength(2),
      );
      expect(
        ((await service.listGoals(scope: 'aerobic', activeOnly: false))['goals']
            as List),
        hasLength(1),
      );
      final withHistory = await service.listGoals(historyPeriods: 3);
      final history =
          ((withHistory['goals'] as List).single as Map)['history'] as List;
      expect(history, hasLength(3));
      expect((history.first as Map)['achieved'], isFalse);
      expect(
        ((await service.listGoals())['goals'] as List)
            .cast<Map>()
            .single['history'],
        isNull,
      );
    });
  });

  group('get_training_plan', () {
    PeriodizationTarget target({
      required double calories,
      double? restCalories,
      String? label,
    }) => PeriodizationTarget(
      id: '',
      phaseId: '',
      version: 1,
      validFrom: today,
      calories: calories,
      proteinG: 150,
      restCalories: restCalories,
      workoutsPerWeek: 3,
      routineIds: const ['ppl'],
      strengthDays: const [1, 3, 5],
      weekLabel: label,
      createdAt: today,
    );

    test('without an active plan it says so', () async {
      final result = await AiPlanningToolService().trainingPlan(date: today);
      expect(result['active_plan'], isFalse);
      expect(result['date'], dateKey(today));
    });

    test(
      'shows phase, day type, nutrition target and next routine day',
      () async {
        await seedStrengthBasics(db);
        final monday = mondayOf(addDays(today, -14));
        await DatabaseHelper.instance.periodizationRepo.createChainedPlan(
          name: 'Plano',
          startDate: monday,
          phases: [
            PhaseScheduleEntry(
              name: 'Base',
              templateKey: 'maintenance',
              color: 0xFF43A047,
              weeks: 2,
              seedTarget: target(calories: 2500),
            ),
            PhaseScheduleEntry(
              name: 'Corte',
              templateKey: 'cutting',
              color: 0xFF1E88E5,
              weeks: 4,
              seedTarget: target(
                calories: 2200,
                restCalories: 1900,
                label: 'Déficit',
              ),
            ),
          ],
        );
        final service = AiPlanningToolService();
        final training = addDays(
          monday,
          14,
        ); // Monday of phase 2, a strength day
        final rest = addDays(monday, 15); // Tuesday, no session planned

        final onTraining = await service.trainingPlan(date: training);
        expect((onTraining['plan'] as Map)['name'], 'Plano');
        expect(onTraining['in_plan'], isTrue);
        final phase = onTraining['phase'] as Map;
        expect(phase['name'], 'Corte');
        expect(phase['week'], 1);
        expect(phase['total_weeks'], 4);
        expect(phase['week_label'], 'Déficit');
        final day = onTraining['day'] as Map;
        expect(day['training_day'], isTrue);
        expect(day['calories'], 2200);
        expect((onTraining['phases'] as List), hasLength(2));
        final template = (onTraining['week_template'] as List).cast<Map>();
        expect(template, hasLength(7));
        expect(template[0]['strength'], isTrue);
        expect(template[1]['calories'], 1900);
        expect((onTraining['targets'] as Map)['rest_day_calories'], 1900);
        final routine = onTraining['next_routine_day'] as Map;
        expect(routine['routine'], 'Push Pull Legs');
        expect(routine['days'], 2);

        final onRest = await service.trainingPlan(date: rest);
        expect((onRest['day'] as Map)['training_day'], isFalse);
        expect((onRest['day'] as Map)['calories'], 1900);

        final outside = await service.trainingPlan(date: addDays(monday, -30));
        expect(outside['in_plan'], isFalse);
        expect(outside['phase'], isNull);
        expect(outside['phases'], isNotEmpty);
      },
    );

    test('review adds the metrics of the week or the whole phase', () async {
      await seedStrengthBasics(db);
      final monday = mondayOf(addDays(today, -7));
      await DatabaseHelper.instance.periodizationRepo.createChainedPlan(
        name: 'Plano',
        startDate: monday,
        phases: [
          PhaseScheduleEntry(
            name: 'Fase',
            templateKey: 'strength',
            color: 0xFFE53935,
            weeks: 4,
            seedTarget: target(calories: 2500),
          ),
        ],
      );
      await seedWorkout(
        db,
        'done',
        date: dateKey(addDays(monday, 1)),
        routineId: 'ppl',
        exercises: [
          ('bench', [seedSet(50, 10), seedSet(50, 10)]),
        ],
      );
      await seedWorkout(
        db,
        'planned',
        date: dateKey(addDays(monday, 2)),
        routineId: 'ppl',
        finished: false,
        exercises: [
          ('bench', [seedSet(50, 10, done: false)]),
        ],
      );
      final service = AiPlanningToolService();
      final week = await service.trainingPlan(
        date: addDays(monday, 1),
        review: 'week',
      );
      final review = week['review'] as Map;
      expect(review['scope'], 'week');
      expect(review['start_date'], dateKey(monday));
      final metrics = review['metrics'] as Map;
      expect(
        metrics['plan_routine_workout_count'],
        1,
        reason: 'planned work never counts',
      );
      expect(metrics['all_finished_workout_count'], isA<int>());
      expect(metrics['plan_routine_completed_sets'], 2);
      expect(metrics['planned_workouts'], 3);

      final phase = await service.trainingPlan(date: today, review: 'phase');
      expect((phase['review'] as Map)['scope'], 'phase');
      expect(
        ((phase['review'] as Map)['metrics']
            as Map)['plan_routine_workout_count'],
        1,
      );
      expect((await service.trainingPlan(date: today))['review'], isNull);
    });
  });
}
