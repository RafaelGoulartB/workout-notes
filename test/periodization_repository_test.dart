import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:workout_notes/models/periodization_checkin.dart';
import 'package:workout_notes/models/periodization_phase_draft.dart';
import 'package:workout_notes/models/periodization_plan.dart';
import 'package:workout_notes/models/periodization_target.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';
import 'support/periodization_fixtures.dart';
import 'support/sql_capture.dart';
import 'support/test_db.dart';

void main() {
  late Database database;
  late SqlLog sqlLog;
  late PeriodizationRepository repository;

  setUpAll(initSqfliteFfiForTests);

  setUp(() async {
    (database, sqlLog) = await installCountingTestDb();
    repository = PeriodizationRepository();
  });

  tearDown(uninstallTestDb);

  PeriodizationTarget target({
    double calories = 2200,
    int workouts = 4,
    double? targetWeight,
    double? weeklyWeightChange,
    String? routineId,
  }) => PeriodizationTarget(
    id: '',
    phaseId: '',
    version: 0,
    validFrom: DateTime(2026, 1, 1),
    calories: calories,
    proteinG: 180,
    workoutsPerWeek: workouts,
    minSetsPerWeek: 40,
    maxSetsPerWeek: 55,
    routineId: routineId,
    targetWeightKg: targetWeight,
    weeklyWeightChangePercent: weeklyWeightChange,
    sleepHours: 8,
    createdAt: DateTime(2026, 1, 1),
  );

  test('run days and phase run volume use calendar-day ranges', () async {
    final plan = await repository.createPlan(
      name: 'Runs',
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 1, 31),
    );
    final phase = await addPhaseFixture(
      repository,
      planId: plan.id,
      name: 'Base',
      startDate: DateTime(2026, 1, 5),
      endDate: DateTime(2026, 1, 5),
      color: 1,
      target: target(),
    );
    Future<void> run(String id, String startedAt) =>
        database.insert('run_activities', {
          'id': id,
          'started_at': startedAt,
          'distance_meters': 5000.0,
          'moving_time_seconds': 1500,
          'status': 'completed',
          'created_at': startedAt,
          'updated_at': startedAt,
        });
    await run('before-midnight', '2026-01-04T23:59:00.000');
    await run('first-minute', '2026-01-05T00:01:00.000');
    await run('last-minute', '2026-01-05T23:59:00.000');
    await run('after-midnight', '2026-01-06T00:01:00.000');

    final dates = await repository.getActivityDates(
      DateTime(2026, 1, 5),
      DateTime(2026, 1, 5),
    );
    final metrics = await repository.getPhaseMetrics(phase);

    expect(dates.runs, {'2026-01-05'});
    expect(metrics.runCount, 2);
    expect(metrics.runDistanceMeters, 10000.0);
  });

  test('creates an integrated active plan', () async {
    await database.insert('routines', {
      'id': 'routine-1',
      'name': 'Upper / Lower',
      'created_at': DateTime(2026).toIso8601String(),
    });
    final plan = await repository.createPlanWithPhases(
      name: 'Recomposition',
      startDate: DateTime(2026, 1, 1),
      phases: [
        PeriodizationPhaseDraft(
          name: 'Cutting',
          color: 0xFF4F8EF7,
          startDate: DateTime(2026, 1, 1),
          endDate: DateTime(2026, 2, 28),
          target: target(routineId: 'routine-1'),
        ),
        PeriodizationPhaseDraft(
          name: 'Deload',
          color: 0xFFF5B942,
          startDate: DateTime(2026, 3, 1),
          endDate: DateTime(2026, 3, 7),
        ),
      ],
    );

    expect(await repository.getActivePlan(), isNull);
    expect(
      (await repository.getPlan(plan.id))?.status,
      PeriodizationPlanStatus.completed,
    );
    final phases = await repository.getPhases(plan.id);
    expect(phases, hasLength(2));
    expect(
      (await repository.getEffectiveTarget(phases.first.id))?.calories,
      2200,
    );
    expect(
      (await repository.getEffectiveTarget(phases.first.id))?.routineId,
      'routine-1',
    );
  });

  test(
    'computes planned versus actual and persists check-in snapshots',
    () async {
      final plan = await repository.createPlan(
        name: 'Metrics',
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 1, 7),
      );
      final phase = await addPhaseFixture(
        repository,
        planId: plan.id,
        name: 'Week',
        startDate: plan.startDate,
        endDate: plan.endDate,
        color: 1,
        target: target(),
      );
      await database.insert('workouts', {
        'id': 'w1',
        'date': '2026-01-02',
        'end_time': '2026-01-02T11:00:00',
        'created_at': '2026-01-02T10:00:00',
      });
      await database.insert('exercise_categories', {
        'id': 'category',
        'name': 'Category',
        'color': 1,
      });
      await database.insert('exercises', {
        'id': 'exercise',
        'name': 'Exercise',
        'category_id': 'category',
        'created_at': '2026-01-01T08:00:00',
      });
      await database.insert('exercise_entries', {
        'id': 'e1',
        'workout_id': 'w1',
        'exercise_id': 'exercise',
        'order_index': 0,
      });
      await database.insert('sets', {
        'id': 's1',
        'exercise_entry_id': 'e1',
        'weight': 100,
        'reps': 5,
        'is_complete': 1,
        'is_warmup': 0,
      });
      await database.insert('meal_logs', {
        'id': 'm1',
        'date': '2026-01-02',
        'meal_type': 'lunch',
        'created_at': '2026-01-01T08:00:00',
      });
      await database.insert('meal_log_items', {
        'id': 'mi1',
        'meal_log_id': 'm1',
        'food_name_snapshot': 'Food',
        'quantity': 1,
        'unit': 'serving',
        'nutrition_snapshot_json': '{}',
        'created_at': '2026-01-01T08:00:00',
        'calories': 2100,
        'protein_g': 170,
      });
      await database.insert('body_measurements', {
        'id': 'b1',
        'type': 'weight',
        'value': 80,
        'unit': 'kg',
        'date': '2026-01-01',
        'created_at': '2026-01-01T08:00:00',
      });
      await database.insert('body_measurements', {
        'id': 'b2',
        'type': 'weight',
        'value': 79.5,
        'unit': 'kg',
        'date': '2026-01-07',
        'created_at': '2026-01-07T08:00:00',
      });
      await database.insert('sleep_entries', {
        'id': 'sl1',
        'date': '2026-01-02',
        'sleep_minutes': 480,
        'created_at': '2026-01-02T08:00:00',
      });

      final metrics = await repository.getPhaseMetrics(
        phase,
        rangeEnd: phase.endDate,
      );
      expect(metrics.workoutCount, 1);
      expect(metrics.completedSets, 1);
      expect(metrics.volume, 500);
      expect(metrics.averageCalories, 2100);
      expect(metrics.weightChangeKg, -0.5);
      expect(metrics.averageSleepHours, 8);

      await repository.saveCheckin(
        PeriodizationCheckin(
          id: 'checkin',
          phaseId: phase.id,
          weekStart: DateTime(2025, 12, 29),
          energy: 4,
          hunger: 3,
          recovery: 4,
          performance: 'stable',
          decision: PeriodizationDecision.maintain,
          metricsSnapshot: metrics.toSnapshot(),
          targetsSnapshot: target().toSnapshot(),
          createdAt: DateTime(2026, 1, 7),
        ),
      );
      final saved = await repository.getCheckins(phase.id);
      expect(saved.single.metricsSnapshot['workout_count'], 1);
      expect(saved.single.decision, PeriodizationDecision.maintain);
    },
  );

  test('validates initial targets and phases against the plan start', () async {
    await expectLater(
      repository.createPlanWithPhases(
        name: 'Invalid target',
        startDate: DateTime(2026, 1, 1),
        phases: [
          PeriodizationPhaseDraft(
            name: 'Base',
            color: 1,
            startDate: DateTime(2026, 1, 1),
            endDate: DateTime(2026, 1, 7),
            target: target(workouts: 20),
          ),
        ],
      ),
      throwsA(isA<PeriodizationValidationException>()),
    );
    await expectLater(
      repository.createPlanWithPhases(
        name: 'Invalid dates',
        startDate: DateTime(2026, 1, 8),
        phases: [
          PeriodizationPhaseDraft(
            name: 'Base',
            color: 1,
            startDate: DateTime(2026, 1, 1),
            endDate: DateTime(2026, 1, 14),
          ),
        ],
      ),
      throwsA(
        isA<PeriodizationValidationException>().having(
          (error) => error.code,
          'code',
          'phase_outside_plan',
        ),
      ),
    );
  });

  test(
    'nutrition adherence includes missing days and exposes coverage',
    () async {
      final plan = await repository.createPlan(
        name: 'Adherence',
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 1, 7),
      );
      final phase = await addPhaseFixture(
        repository,
        planId: plan.id,
        name: 'Week',
        startDate: plan.startDate,
        endDate: plan.endDate,
        color: 1,
        target: target(),
      );
      await database.insert('meal_logs', {
        'id': 'meal-only',
        'date': '2026-01-01',
        'meal_type': 'lunch',
        'created_at': '2026-01-01T08:00:00',
      });
      await database.insert('meal_log_items', {
        'id': 'item-only',
        'meal_log_id': 'meal-only',
        'food_name_snapshot': 'Food',
        'quantity': 1,
        'unit': 'serving',
        'nutrition_snapshot_json': '{}',
        'created_at': '2026-01-01T08:00:00',
        'calories': 2200,
        'protein_g': 180,
      });

      final metrics = await repository.getPhaseMetrics(phase);
      expect(metrics.nutritionTargetDays, 7);
      expect(metrics.nutritionCoveragePercent, closeTo(100 / 7, 0.01));
      expect(metrics.nutritionAdherencePercent, closeTo(100 / 7, 0.01));
    },
  );

  test(
    'planned totals respect the target version effective on each day',
    () async {
      final plan = await repository.createPlan(
        name: 'Versions',
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 1, 14),
      );
      final phase = await addPhaseFixture(
        repository,
        planId: plan.id,
        name: 'Two weeks',
        startDate: plan.startDate,
        endDate: plan.endDate,
        color: 1,
        weeklyTargets: [target(workouts: 4), target(workouts: 6)],
      );

      final metrics = await repository.getPhaseMetrics(phase);
      expect(metrics.plannedWorkouts, 10);
    },
  );

  test(
    'suggests the next day of the routine linked to the active phase',
    () async {
      final today = DateTime.now();
      final start = DateTime(today.year, today.month, today.day - 2);
      final end = DateTime(today.year, today.month, today.day + 2);
      await database.insert('routines', {
        'id': 'linked-routine',
        'name': 'Upper / Lower',
        'created_at': today.toIso8601String(),
      });
      await database.insert('routine_days', {
        'id': 'upper',
        'routine_id': 'linked-routine',
        'name': 'Upper',
        'order_index': 0,
      });
      await database.insert('routine_days', {
        'id': 'lower',
        'routine_id': 'linked-routine',
        'name': 'Lower',
        'order_index': 1,
      });
      await repository.createPlanWithPhases(
        name: 'Current',
        startDate: start,
        phases: [
          PeriodizationPhaseDraft(
            name: 'Current phase',
            color: 1,
            startDate: start,
            endDate: end,
            target: PeriodizationTarget(
              id: '',
              phaseId: '',
              version: 0,
              validFrom: start,
              routineId: 'linked-routine',
              createdAt: today,
            ),
          ),
        ],
      );
      await database.insert('workouts', {
        'id': 'completed-routine-workout',
        'date': _testDate(today),
        'start_time': today
            .subtract(const Duration(hours: 1))
            .toIso8601String(),
        'end_time': today.toIso8601String(),
        'is_from_routine': 1,
        'routine_id': 'linked-routine',
        'created_at': today.toIso8601String(),
      });

      final suggestion = await repository.getRoutineSuggestion(today);
      expect(suggestion?.routineDayId, 'lower');
      expect(suggestion?.completedWorkouts, 1);
    },
  );

  test('suggests the next session across multiple weekly routines', () async {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day - 2);
    final end = DateTime(today.year, today.month, today.day + 2);
    for (final routine in [('routine-a', 'Push'), ('routine-b', 'Pull')]) {
      await database.insert('routines', {
        'id': routine.$1,
        'name': routine.$2,
        'created_at': today.toIso8601String(),
      });
      await database.insert('routine_days', {
        'id': '${routine.$1}-day',
        'routine_id': routine.$1,
        'name': routine.$2,
        'order_index': 0,
      });
    }
    await repository.createPlanWithPhases(
      name: 'Multiple routines',
      startDate: start,
      phases: [
        PeriodizationPhaseDraft(
          name: 'Current phase',
          color: 1,
          startDate: start,
          endDate: end,
          target: PeriodizationTarget(
            id: '',
            phaseId: '',
            version: 0,
            validFrom: start,
            routineIds: const ['routine-a', 'routine-b'],
            createdAt: today,
          ),
        ),
      ],
    );
    await database.insert('workouts', {
      'id': 'completed-push',
      'date': _testDate(today),
      'end_time': today.toIso8601String(),
      'routine_id': 'routine-a',
      'created_at': today.toIso8601String(),
    });

    final suggestion = await repository.getRoutineSuggestion(today);

    expect(suggestion?.routineId, 'routine-b');
    expect(suggestion?.routineDayId, 'routine-b-day');
    expect(suggestion?.routineDayCount, 2);
    expect(suggestion?.completedWorkouts, 1);
  });

  test('routine suggestion reads routines in bulk, not one by one', () async {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day - 2);
    final end = DateTime(today.year, today.month, today.day + 2);
    final routineIds = [for (var i = 0; i < 4; i++) 'routine-$i'];
    for (final id in routineIds) {
      await database.insert('routines', {
        'id': id,
        'name': 'Routine $id',
        'created_at': today.toIso8601String(),
      });
      for (var d = 0; d < 2; d++) {
        await database.insert('routine_days', {
          'id': '$id-day$d',
          'routine_id': id,
          'name': 'Day $d',
          'order_index': d,
        });
      }
    }
    await repository.createPlanWithPhases(
      name: 'Many routines',
      startDate: start,
      phases: [
        PeriodizationPhaseDraft(
          name: 'Current phase',
          color: 1,
          startDate: start,
          endDate: end,
          target: PeriodizationTarget(
            id: '',
            phaseId: '',
            version: 0,
            validFrom: start,
            routineIds: routineIds,
            createdAt: today,
          ),
        ),
      ],
    );
    // Three finished sessions: the fourth day of the sequence is next.
    for (var i = 0; i < 3; i++) {
      await database.insert('workouts', {
        'id': 'done-$i',
        'date': _testDate(today),
        'end_time': today.toIso8601String(),
        'routine_id': routineIds[i],
        'created_at': today.toIso8601String(),
      });
    }

    sqlLog.clear();
    final suggestion = await repository.getRoutineSuggestion(today);
    final reads = sqlLog.reads;

    expect(suggestion?.routineId, 'routine-1');
    expect(suggestion?.routineDayId, 'routine-1-day1');
    expect(suggestion?.routineDayCount, 8);
    expect(suggestion?.completedWorkouts, 3);
    // Same query count as with a single routine (phase, target, routines,
    // days, completed count): nothing scales with the routine count.
    expect(reads, lessThanOrEqualTo(6));
  });

  test(
    'weekly targets collapse identical weeks into versioned blocks',
    () async {
      final plan = await repository.createPlan(
        name: 'Weekly',
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 1, 31),
      );
      final phase = await addPhaseFixture(
        repository,
        planId: plan.id,
        name: 'Base',
        startDate: plan.startDate,
        endDate: plan.endDate,
        color: 1,
        weeklyTargets: [
          target(calories: 2200),
          target(calories: 2200),
          target(calories: 2200),
          target(calories: 2400),
          target(calories: 2400),
        ],
      );

      final history = await repository.getTargetHistory(phase.id);
      expect(history, hasLength(2));
      final ascending = [...history]
        ..sort((a, b) => a.version.compareTo(b.version));
      expect(ascending.first.validFrom, DateTime(2026, 1, 1));
      expect(ascending.last.validFrom, DateTime(2026, 1, 22));
      expect(
        (await repository.getEffectiveTarget(
          phase.id,
          date: DateTime(2026, 1, 15),
        ))?.calories,
        2200,
      );
      expect(
        (await repository.getEffectiveTarget(
          phase.id,
          date: DateTime(2026, 1, 25),
        ))?.calories,
        2400,
      );
    },
  );

  test(
    'does not activate an empty plan and expires active plans on read',
    () async {
      final empty = await repository.createPlan(
        name: 'Empty',
        startDate: DateTime.now(),
        endDate: DateTime.now().add(const Duration(days: 7)),
        activate: false,
      );
      await expectLater(
        repository.setPlanStatus(empty.id, PeriodizationPlanStatus.active),
        throwsA(
          isA<PeriodizationValidationException>().having(
            (error) => error.code,
            'code',
            'plan_requires_phase',
          ),
        ),
      );

      final expired = await repository.createPlan(
        name: 'Expired',
        startDate: DateTime.now().subtract(const Duration(days: 8)),
        endDate: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(await repository.getActivePlan(), isNull);
      expect(
        (await repository.getPlan(expired.id))?.status,
        PeriodizationPlanStatus.completed,
      );
    },
  );

  test('weekly targets keep g/kg metadata on the persisted version', () async {
    final plan = await repository.createPlan(
      name: 'Ratios',
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 1, 14),
    );
    final phase = await addPhaseFixture(
      repository,
      planId: plan.id,
      name: 'Base',
      startDate: plan.startDate,
      endDate: plan.endDate,
      color: 1,
      weeklyTargets: [
        PeriodizationTarget(
          id: '',
          phaseId: '',
          version: 0,
          validFrom: plan.startDate,
          calories: 2400,
          proteinG: 165,
          carbsG: 245,
          fatG: 60,
          proteinGPerKg: 2.2,
          fatGPerKg: 0.8,
          weightKgUsed: 75,
          createdAt: DateTime(2026, 1, 1),
        ),
      ],
    );

    final saved = await repository.getEffectiveTarget(phase.id);
    expect(saved?.proteinGPerKg, 2.2);
    expect(saved?.fatGPerKg, 0.8);
    expect(saved?.weightKgUsed, 75);
    expect(saved?.carbsG, 245);
  });

  test(
    'replaceFrom preserves locked history and rewrites later weeks',
    () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final start = today.subtract(const Duration(days: 14));
      final end = today.add(const Duration(days: 13));
      final plan = await repository.createPlan(
        name: 'Replace',
        startDate: start,
        endDate: end,
      );
      final phase = await addPhaseFixture(
        repository,
        planId: plan.id,
        name: 'Base',
        startDate: start,
        endDate: end,
        color: 1,
        weeklyTargets: List.filled(4, target(calories: 2200)),
      );
      expect(await repository.getTargetHistory(phase.id), hasLength(1));

      await repository.savePhaseSetup(
        phase.id,
        name: 'Base',
        templateKey: '',
        color: 1,
        weeks: [target(calories: 2000), target(calories: 2000)],
        fromWeek: 2,
      );
      final history = await repository.getTargetHistory(phase.id);
      expect(history, hasLength(2));
      expect(
        (await repository.getEffectiveTarget(
          phase.id,
          date: today.subtract(const Duration(days: 1)),
        ))?.calories,
        2200,
      );
      expect(
        (await repository.getEffectiveTarget(phase.id, date: today))?.calories,
        2000,
      );
      expect(
        (await repository.getEffectiveTarget(
          phase.id,
          date: today.add(const Duration(days: 7)),
        ))?.calories,
        2000,
      );

      // Saving weeks equal to the retained baseline removes the override
      // without touching the locked version.
      await repository.savePhaseSetup(
        phase.id,
        name: 'Base',
        templateKey: '',
        color: 1,
        weeks: [target(calories: 2200)],
        fromWeek: 2,
      );
      expect(await repository.getTargetHistory(phase.id), hasLength(1));
      expect(
        (await repository.getEffectiveTarget(
          phase.id,
          date: today.add(const Duration(days: 7)),
        ))?.calories,
        2200,
      );
    },
  );

  test('weekly window beyond the phase end is rejected', () async {
    final plan = await repository.createPlan(
      name: 'Window',
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 1, 28),
    );
    await expectLater(
      addPhaseFixture(
        repository,
        planId: plan.id,
        name: 'Too long',
        startDate: plan.startDate,
        endDate: plan.endDate,
        color: 1,
        weeklyTargets: List.filled(5, target()),
      ),
      throwsA(
        isA<PeriodizationValidationException>().having(
          (error) => error.code,
          'code',
          'target_outside_phase',
        ),
      ),
    );
  });

  test('all-empty weekly targets persist no versions', () async {
    final plan = await repository.createPlan(
      name: 'Empty',
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 1, 14),
    );
    final phase = await addPhaseFixture(
      repository,
      planId: plan.id,
      name: 'Base',
      startDate: plan.startDate,
      endDate: plan.endDate,
      color: 1,
      weeklyTargets: List.filled(
        2,
        PeriodizationTarget(
          id: '',
          phaseId: '',
          version: 0,
          validFrom: plan.startDate,
          createdAt: DateTime(2026, 1, 1),
        ),
      ),
    );
    expect(await repository.getTargetHistory(phase.id), isEmpty);
    expect(await repository.getEffectiveTarget(phase.id), isNull);
  });

  test('createPlanWithPhases persists weekly targets per phase', () async {
    final plan = await repository.createPlanWithPhases(
      name: 'Weekly wizard',
      startDate: DateTime(2026, 1, 1),
      phases: [
        PeriodizationPhaseDraft(
          name: 'Base',
          color: 1,
          startDate: DateTime(2026, 1, 1),
          endDate: DateTime(2026, 1, 28),
          weeklyTargets: [
            target(calories: 2200),
            target(calories: 2200),
            target(calories: 2200),
            target(calories: 2500),
          ],
        ),
        PeriodizationPhaseDraft(
          name: 'Second',
          color: 2,
          startDate: DateTime(2026, 1, 29),
          endDate: DateTime(2026, 2, 11),
        ),
      ],
    );

    final phases = await repository.getPhases(plan.id);
    expect(phases, hasLength(2));
    final history = await repository.getTargetHistory(phases.first.id);
    expect(history, hasLength(2));
    final ascending = [...history]
      ..sort((a, b) => a.version.compareTo(b.version));
    expect(ascending.first.validFrom, DateTime(2026, 1, 1));
    expect(ascending.last.validFrom, DateTime(2026, 1, 22));
    expect(
      (await repository.getEffectiveTarget(
        phases.first.id,
        date: DateTime(2026, 1, 10),
      ))?.calories,
      2200,
    );
    expect(
      (await repository.getEffectiveTarget(
        phases.first.id,
        date: DateTime(2026, 1, 25),
      ))?.calories,
      2500,
    );
    expect(await repository.getTargetHistory(phases.last.id), isEmpty);
  });
}

String _testDate(DateTime date) => DateTime(
  date.year,
  date.month,
  date.day,
).toIso8601String().substring(0, 10);
