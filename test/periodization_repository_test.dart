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
            'CREATE TABLE workouts (id TEXT PRIMARY KEY, date TEXT NOT NULL, start_time TEXT, end_time TEXT, duration_seconds INTEGER, estimated_calories REAL, comment TEXT, feeling_rating INTEGER, is_from_routine INTEGER DEFAULT 0, routine_id TEXT, pause_start_time TEXT, created_at TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE exercise_entries (id TEXT PRIMARY KEY, workout_id TEXT NOT NULL, exercise_id TEXT NOT NULL, order_index INTEGER, FOREIGN KEY (workout_id) REFERENCES workouts(id) ON DELETE CASCADE)',
          );
          await db.execute(
            'CREATE TABLE sets (id TEXT PRIMARY KEY, exercise_entry_id TEXT NOT NULL, weight REAL, reps INTEGER, is_complete INTEGER DEFAULT 0, is_warmup INTEGER DEFAULT 0, order_index INTEGER, FOREIGN KEY (exercise_entry_id) REFERENCES exercise_entries(id) ON DELETE CASCADE)',
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
            'CREATE TABLE meal_log_items (id TEXT PRIMARY KEY, meal_log_id TEXT, calories REAL, protein_g REAL, FOREIGN KEY (meal_log_id) REFERENCES meal_logs(id) ON DELETE CASCADE)',
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
}
