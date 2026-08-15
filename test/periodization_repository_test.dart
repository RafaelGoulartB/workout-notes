import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/database/database_periodization_schema.dart';
import 'package:workout_notes/models/periodization_checkin.dart';
import 'package:workout_notes/models/periodization_phase_draft.dart';
import 'package:workout_notes/models/periodization_phase.dart';
import 'package:workout_notes/models/periodization_target.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';

void main() {
  late Database database;
  late PeriodizationRepository repository;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    database = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 37,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE routines (id TEXT PRIMARY KEY, name TEXT NOT NULL, notes TEXT, created_at TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE routine_days (id TEXT PRIMARY KEY, routine_id TEXT NOT NULL, name TEXT NOT NULL, order_index INTEGER NOT NULL DEFAULT 0, FOREIGN KEY (routine_id) REFERENCES routines(id) ON DELETE CASCADE)',
          );
          await db.execute(
            'CREATE TABLE workouts (id TEXT PRIMARY KEY, date TEXT NOT NULL, start_time TEXT, end_time TEXT, duration_seconds INTEGER, estimated_calories REAL, comment TEXT, feeling_rating INTEGER, is_from_routine INTEGER DEFAULT 0, routine_id TEXT, pause_start_time TEXT, created_at TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE exercise_entries (id TEXT PRIMARY KEY, workout_id TEXT NOT NULL, exercise_id TEXT NOT NULL, order_index INTEGER, FOREIGN KEY (workout_id) REFERENCES workouts(id) ON DELETE CASCADE)',
          );
          await db.execute(
            'CREATE TABLE sets (id TEXT PRIMARY KEY, exercise_entry_id TEXT NOT NULL, weight REAL, reps INTEGER, rpe REAL, is_complete INTEGER DEFAULT 0, is_warmup INTEGER DEFAULT 0, order_index INTEGER, FOREIGN KEY (exercise_entry_id) REFERENCES exercise_entries(id) ON DELETE CASCADE)',
          );
          await db.execute(
            'CREATE TABLE body_measurements (id TEXT PRIMARY KEY, type TEXT, value REAL, unit TEXT, date TEXT, created_at TEXT)',
          );
          await db.execute(
            'CREATE TABLE sleep_entries (id TEXT PRIMARY KEY, date TEXT, sleep_minutes INTEGER, actual_sleep_minutes INTEGER, estimated_sleep_minutes INTEGER)',
          );
          await db.execute(
            'CREATE TABLE meal_logs (id TEXT PRIMARY KEY, date TEXT, meal_type TEXT)',
          );
          await db.execute(
            'CREATE TABLE meal_log_items (id TEXT PRIMARY KEY, meal_log_id TEXT, calories REAL, protein_g REAL, carbs_g REAL, fat_g REAL, FOREIGN KEY (meal_log_id) REFERENCES meal_logs(id) ON DELETE CASCADE)',
          );
          await DatabasePeriodizationSchema.create(db);
        },
      ),
    );
    DatabaseHelper.overrideDatabase = database;
    repository = PeriodizationRepository();
  });

  tearDown(() async {
    DatabaseHelper.overrideDatabase = null;
    await database.close();
  });

  PeriodizationTarget target({double calories = 2200, int workouts = 4}) =>
      PeriodizationTarget(
        id: '',
        phaseId: '',
        version: 0,
        validFrom: DateTime(2026, 1, 1),
        calories: calories,
        proteinG: 180,
        workoutsPerWeek: workouts,
        minSetsPerWeek: 40,
        maxSetsPerWeek: 55,
        sleepHours: 8,
        createdAt: DateTime(2026, 1, 1),
      );

  test('creates an integrated active plan and prevents overlap', () async {
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
          target: target(),
          routineId: 'routine-1',
        ),
        PeriodizationPhaseDraft(
          name: 'Deload',
          color: 0xFFF5B942,
          startDate: DateTime(2026, 3, 1),
          endDate: DateTime(2026, 3, 7),
        ),
      ],
    );

    expect((await repository.getActivePlan())?.id, plan.id);
    final phases = await repository.getPhases(plan.id);
    expect(phases, hasLength(2));
    expect(
      (await repository.getEffectiveTarget(phases.first.id))?.calories,
      2200,
    );
    expect(await repository.getRoutineLinks(phases.first.id), hasLength(1));

    await expectLater(
      repository.addPhase(
        planId: plan.id,
        name: 'Overlap',
        startDate: DateTime(2026, 2, 15),
        endDate: DateTime(2026, 3, 2),
        color: 0xFF000000,
      ),
      throwsA(
        isA<PeriodizationValidationException>().having(
          (error) => error.code,
          'code',
          'phase_overlap',
        ),
      ),
    );
  });

  test(
    'versions targets and resolves the historical effective target',
    () async {
      final plan = await repository.createPlan(
        name: 'Plan',
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 3, 31),
      );
      final phase = await repository.addPhase(
        planId: plan.id,
        name: 'Base',
        startDate: plan.startDate,
        endDate: plan.endDate,
        color: 0xFF4F8EF7,
        target: target(),
      );
      await repository.saveTargetVersion(
        phase.id,
        target(calories: 2400),
        validFrom: DateTime(2026, 2, 1),
      );

      expect(
        (await repository.getEffectiveTarget(
          phase.id,
          date: DateTime(2026, 1, 20),
        ))?.calories,
        2200,
      );
      expect(
        (await repository.getEffectiveTarget(
          phase.id,
          date: DateTime(2026, 2, 20),
        ))?.calories,
        2400,
      );
      expect(await repository.getTargetHistory(phase.id), hasLength(2));
    },
  );

  test('cascading replan shifts following phases and plan end', () async {
    final plan = await repository.createPlanWithPhases(
      name: 'Cycle',
      startDate: DateTime(2026, 1, 1),
      phases: [
        PeriodizationPhaseDraft(
          name: 'One',
          color: 1,
          startDate: DateTime(2026, 1, 1),
          endDate: DateTime(2026, 1, 14),
        ),
        PeriodizationPhaseDraft(
          name: 'Two',
          color: 2,
          startDate: DateTime(2026, 1, 15),
          endDate: DateTime(2026, 1, 28),
          target: target(calories: 2500),
        ),
      ],
    );
    final phases = await repository.getPhases(plan.id);
    final first = phases.first;
    await repository.updatePhase(
      PeriodizationPhase(
        id: first.id,
        planId: first.planId,
        name: first.name,
        color: first.color,
        startDate: first.startDate,
        endDate: DateTime(2026, 1, 21),
        orderIndex: first.orderIndex,
        createdAt: first.createdAt,
        updatedAt: DateTime.now(),
      ),
      shiftFollowingPhases: true,
    );

    final shifted = await repository.getPhases(plan.id);
    expect(shifted[1].startDate, DateTime(2026, 1, 22));
    expect((await repository.getPlan(plan.id))?.endDate, DateTime(2026, 2, 4));
    expect(
      (await repository.getTargetHistory(shifted[1].id)).single.validFrom,
      DateTime(2026, 1, 22),
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
      final phase = await repository.addPhase(
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
      });
      await database.insert('meal_log_items', {
        'id': 'mi1',
        'meal_log_id': 'm1',
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

  test('phase, target and routine edit rolls back atomically', () async {
    final plan = await repository.createPlan(
      name: 'Atomic',
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 1, 31),
    );
    final phase = await repository.addPhase(
      planId: plan.id,
      name: 'Original',
      startDate: plan.startDate,
      endDate: plan.endDate,
      color: 1,
      target: target(),
    );
    final updated = PeriodizationPhase(
      id: phase.id,
      planId: phase.planId,
      name: 'Changed',
      color: phase.color,
      startDate: phase.startDate,
      endDate: phase.endDate,
      orderIndex: phase.orderIndex,
      createdAt: phase.createdAt,
      updatedAt: DateTime.now(),
    );

    await expectLater(
      repository.updatePhaseWithTargetAndRoutine(
        updated,
        shiftFollowingPhases: false,
        targetChanged: false,
        target: target(),
        routineId: 'missing-routine',
        routineLinkId: null,
      ),
      throwsA(isA<DatabaseException>()),
    );
    expect((await repository.getPhase(phase.id))?.name, 'Original');
    expect(await repository.getTargetHistory(phase.id), hasLength(1));
  });

  test(
    'replan refuses to move a phase away from historical check-ins',
    () async {
      final plan = await repository.createPlan(
        name: 'History',
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 1, 31),
      );
      final phase = await repository.addPhase(
        planId: plan.id,
        name: 'Base',
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 1, 14),
        color: 1,
        target: target(),
      );
      await repository.saveCheckin(
        PeriodizationCheckin(
          id: 'history-checkin',
          phaseId: phase.id,
          weekStart: DateTime(2026, 1, 5),
          energy: 3,
          hunger: 3,
          recovery: 3,
          performance: 'stable',
          decision: PeriodizationDecision.maintain,
          createdAt: DateTime(2026, 1, 11),
        ),
      );

      await expectLater(
        repository.updatePhase(
          PeriodizationPhase(
            id: phase.id,
            planId: phase.planId,
            name: phase.name,
            color: phase.color,
            startDate: DateTime(2026, 1, 12),
            endDate: DateTime(2026, 1, 25),
            orderIndex: phase.orderIndex,
            createdAt: phase.createdAt,
            updatedAt: DateTime.now(),
          ),
        ),
        throwsA(
          isA<PeriodizationValidationException>().having(
            (error) => error.code,
            'code',
            'replan_excludes_checkins',
          ),
        ),
      );
    },
  );

  test(
    'nutrition adherence includes missing days and exposes coverage',
    () async {
      final plan = await repository.createPlan(
        name: 'Adherence',
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 1, 7),
      );
      final phase = await repository.addPhase(
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
      });
      await database.insert('meal_log_items', {
        'id': 'item-only',
        'meal_log_id': 'meal-only',
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
      final phase = await repository.addPhase(
        planId: plan.id,
        name: 'Two weeks',
        startDate: plan.startDate,
        endDate: plan.endDate,
        color: 1,
        target: target(workouts: 4),
      );
      await repository.saveTargetVersion(
        phase.id,
        target(workouts: 6),
        validFrom: DateTime(2026, 1, 8),
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
            routineId: 'linked-routine',
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
}

String _testDate(DateTime date) => DateTime(
  date.year,
  date.month,
  date.day,
).toIso8601String().substring(0, 10);
