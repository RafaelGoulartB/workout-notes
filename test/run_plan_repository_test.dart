import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/database/database_periodization_schema.dart';
import 'package:workout_notes/database/database_run_plan_schema.dart';
import 'package:workout_notes/models/run_plan.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/models/run_voice_settings.dart';
import 'package:workout_notes/models/run_workout_step.dart';
import 'package:workout_notes/models/scheduled_run.dart';
import 'package:workout_notes/repositories/run_plan_repository.dart';

void main() {
  late Database database;
  late RunPlanRepository repository;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    database = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 45,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE routines (id TEXT PRIMARY KEY, name TEXT NOT NULL, notes TEXT, created_at TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE run_activities (id TEXT PRIMARY KEY, started_at TEXT NOT NULL, ended_at TEXT, '
            'duration_seconds INTEGER NOT NULL DEFAULT 0, moving_time_seconds INTEGER NOT NULL DEFAULT 0, '
            'distance_meters REAL NOT NULL DEFAULT 0, avg_pace_sec_per_km REAL, max_pace_sec_per_km REAL, '
            'calories INTEGER, title TEXT, notes TEXT, status TEXT NOT NULL DEFAULT \'completed\', '
            'polyline_summary TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, plan_workout_id TEXT)',
          );
          await DatabasePeriodizationSchema.create(db);
          await DatabaseRunPlanSchema.create(db);
        },
      ),
    );
    DatabaseHelper.overrideDatabase = database;
    repository = RunPlanRepository();
  });

  tearDown(() async {
    DatabaseHelper.overrideDatabase = null;
    await database.close();
  });

  Future<RunPlan> seedPlan({int weeks = 4}) => repository.createPlan(
    name: '10 km em 12 semanas',
    goalKind: RunPlanGoalKind.tenK,
    weeks: weeks,
  );

  /// Builds `2 km aquecimento + 6×(800 m / 2 min) + 1 km desaquecimento`.
  Future<RunPlanWorkout> seedIntervalSession(String planId) async {
    final session = await repository.addWorkout(
      planId: planId,
      weekIndex: 0,
      name: '6x800m',
      kind: RunWorkoutKind.interval,
      dayOfWeek: 2,
    );
    await repository.addStep(
      workoutId: session.id,
      role: RunStepRole.warmup,
      metric: RunIntervalMetric.distance,
      value: 2000,
    );
    await repository.addStep(
      workoutId: session.id,
      role: RunStepRole.work,
      metric: RunIntervalMetric.distance,
      value: 800,
      repeatGroup: 1,
      repeatCount: 6,
      targetPaceMinSecPerKm: 230,
      targetPaceMaxSecPerKm: 245,
    );
    await repository.addStep(
      workoutId: session.id,
      role: RunStepRole.recovery,
      metric: RunIntervalMetric.time,
      value: 120,
      repeatGroup: 1,
      repeatCount: 6,
    );
    await repository.addStep(
      workoutId: session.id,
      role: RunStepRole.cooldown,
      metric: RunIntervalMetric.distance,
      value: 1000,
    );
    return (await repository.getWorkout(session.id))!;
  }

  group('plans', () {
    test('creates, lists and loads a plan with sessions and steps', () async {
      final plan = await seedPlan();
      await seedIntervalSession(plan.id);
      await repository.addWorkout(
        planId: plan.id,
        weekIndex: 0,
        name: 'Longão 14 km',
        kind: RunWorkoutKind.long,
        dayOfWeek: 7,
        targetDistanceMeters: 14000,
      );

      final plans = await repository.listPlans();
      expect(plans.single.name, '10 km em 12 semanas');

      final loaded = (await repository.getPlan(plan.id))!;
      expect(loaded.workouts.length, 2);
      final week = loaded.workoutsForWeek(0);
      // Ordered by weekday: Tuesday interval before Sunday long run.
      expect(week.first.kind, RunWorkoutKind.interval);
      expect(week.last.kind, RunWorkoutKind.long);
      expect(week.first.steps.length, 4);
      expect(week.first.workRepCount, 6);
    });

    test('weekly aggregates read the expanded steps', () async {
      final plan = await seedPlan();
      await seedIntervalSession(plan.id);
      await repository.addWorkout(
        planId: plan.id,
        weekIndex: 0,
        name: 'Longão 14 km',
        kind: RunWorkoutKind.long,
        dayOfWeek: 7,
        targetDistanceMeters: 14000,
      );

      final loaded = (await repository.getPlan(plan.id))!;
      // 2000 + 6x800 + 1000 = 7800, plus the 14 km long run.
      expect(loaded.weeklyDistanceMeters(0), closeTo(7800 + 14000, 0.01));
      expect(loaded.longRunForWeek(0)!.name, 'Longão 14 km');
      expect(loaded.qualitySessionsForWeek(0), 1);
    });

    test('archived plans are hidden unless asked for', () async {
      final plan = await seedPlan();
      await repository.updatePlan(plan.id, status: RunPlanStatus.archived);
      expect(await repository.listPlans(), isEmpty);
      expect(
        (await repository.listPlans(includeArchived: true)).single.id,
        plan.id,
      );
    });

    test('shrinking the week count drops unreachable sessions', () async {
      final plan = await seedPlan(weeks: 4);
      await repository.addWorkout(
        planId: plan.id,
        weekIndex: 3,
        name: 'Semana 4',
      );
      await repository.updatePlan(plan.id, weeks: 2);
      final loaded = (await repository.getPlan(plan.id))!;
      expect(loaded.weeks, 2);
      expect(loaded.workouts, isEmpty);
    });

    test('deleting a plan cascades sessions and steps', () async {
      final plan = await seedPlan();
      final session = await seedIntervalSession(plan.id);
      await repository.deletePlan(plan.id);

      expect(await repository.getPlan(plan.id), isNull);
      expect(
        await database.query(
          'run_workout_steps',
          where: 'run_plan_workout_id = ?',
          whereArgs: [session.id],
        ),
        isEmpty,
      );
    });

    test(
      'deleting a plan clears it from weekly periodization targets',
      () async {
        final plan = await seedPlan();
        final now = DateTime.now().toIso8601String();
        await database.insert('periodization_plans', {
          'id': 'pp1',
          'name': 'Base',
          'start_date': '2026-01-05',
          'end_date': '2026-03-01',
          'status': 'active',
          'created_at': now,
          'updated_at': now,
        });
        await database.insert('periodization_phases', {
          'id': 'ph1',
          'plan_id': 'pp1',
          'name': 'Acumulação',
          'color': 0xFF00FF00,
          'start_date': '2026-01-05',
          'end_date': '2026-02-01',
          'order_index': 0,
          'created_at': now,
          'updated_at': now,
        });
        await database.insert('phase_targets', {
          'id': 'pt1',
          'phase_id': 'ph1',
          'nutrition_json': '{}',
          'training_json': jsonEncode({
            'workouts_per_week': 4,
            'run': {
              'run_sessions_per_week': 3,
              'run_plan_ids': [plan.id, 'outro'],
            },
          }),
          'body_json': '{}',
          'sleep_json': '{}',
          'version': 1,
          'valid_from': '2026-01-05',
          'created_at': now,
        });

        await repository.deletePlan(plan.id);

        final row = (await database.query(
          'phase_targets',
          where: 'id = ?',
          whereArgs: ['pt1'],
        )).single;
        final training =
            jsonDecode(row['training_json'] as String) as Map<String, dynamic>;
        expect((training['run'] as Map)['run_plan_ids'], ['outro']);
        expect(training['workouts_per_week'], 4);
      },
    );

    test('duplicating a plan deep-copies sessions and steps', () async {
      final plan = await seedPlan();
      await seedIntervalSession(plan.id);
      final copy = await repository.duplicatePlan(plan.id, 'Cópia');

      expect(copy.name, 'Cópia');
      expect(copy.workouts.single.steps.length, 4);
      expect(copy.workouts.single.id, isNot(plan.id));
      // The original is untouched.
      expect((await repository.getPlan(plan.id))!.workouts.length, 1);
    });

    test('copyWeek replaces the target weeks', () async {
      final plan = await seedPlan(weeks: 4);
      await seedIntervalSession(plan.id);
      await repository.addWorkout(
        planId: plan.id,
        weekIndex: 1,
        name: 'Descartável',
      );

      final applied = await repository.copyWeek(
        plan.id,
        sourceWeek: 0,
        targetWeeks: {1, 2},
      );
      expect(applied, 2);

      final loaded = (await repository.getPlan(plan.id))!;
      expect(loaded.workoutsForWeek(1).single.name, '6x800m');
      expect(loaded.workoutsForWeek(1).single.steps.length, 4);
      expect(loaded.workoutsForWeek(2).single.name, '6x800m');
      // Out-of-range weeks are ignored, the source week is never touched.
      expect(loaded.workoutsForWeek(0).single.name, '6x800m');
    });
  });

  group('library data', () {
    test('listPlans only hydrates sessions when asked', () async {
      final plan = await seedPlan();
      await seedIntervalSession(plan.id);

      final bare = await repository.listPlans();
      expect(bare.single.workouts, isEmpty);

      final full = await repository.listPlans(hydrate: true);
      expect(full.single.workouts.length, 1);
      expect(full.single.workouts.single.steps.length, 4);
      expect(full.single.weeklyDistanceMeters(0), 7800);
    });

    test('duplicateWorkout copies the steps into the chosen week', () async {
      final plan = await seedPlan();
      final session = await seedIntervalSession(plan.id);

      await repository.duplicateWorkout(session.id, weekIndex: 2);

      final reloaded = (await repository.getPlan(plan.id))!;
      expect(reloaded.workoutsForWeek(0).length, 1);
      final copy = reloaded.workoutsForWeek(2).single;
      expect(copy.id, isNot(session.id));
      expect(copy.name, session.name);
      expect(copy.steps.length, 4);
      expect(copy.workRepCount, 6);
    });

    test(
      'getScheduledWeeks reports the weeks already on the calendar',
      () async {
        final plan = await seedPlan();
        await seedIntervalSession(plan.id);
        await repository.copyWeek(plan.id, sourceWeek: 0, targetWeeks: {2});

        expect(await repository.getScheduledWeeks(plan.id), isEmpty);

        await repository.materializeWeek(
          planId: plan.id,
          weekIndex: 2,
          weekStart: DateTime(2026, 3, 2),
        );

        expect(await repository.getScheduledWeeks(plan.id), {2});
      },
    );
  });

  group('steps', () {
    test('reorder persists a new order', () async {
      final plan = await seedPlan();
      final session = await seedIntervalSession(plan.id);
      final reversed = session.steps.reversed.map((s) => s.id).toList();
      await repository.reorderSteps(session.id, reversed);

      final steps = await repository.getSteps(session.id);
      expect(steps.first.role, RunStepRole.cooldown);
      expect(steps.last.role, RunStepRole.warmup);
    });

    test('replaceSteps swaps the whole block and renumbers', () async {
      final plan = await seedPlan();
      final session = await seedIntervalSession(plan.id);
      await repository.replaceSteps(session.id, [
        RunWorkoutStep(
          id: '',
          runPlanWorkoutId: session.id,
          orderIndex: 9,
          role: RunStepRole.steady,
          metric: RunIntervalMetric.time,
          value: 1800,
        ),
      ]);

      final steps = await repository.getSteps(session.id);
      expect(steps.length, 1);
      expect(steps.single.orderIndex, 0);
      expect(steps.single.value, 1800);
    });

    test('deleting a step leaves the rest intact', () async {
      final plan = await seedPlan();
      final session = await seedIntervalSession(plan.id);
      await repository.deleteStep(session.steps.first.id);
      expect((await repository.getSteps(session.id)).length, 3);
    });
  });

  group('schedule', () {
    test('materializeWeek maps weekdays onto real dates', () async {
      final plan = await seedPlan();
      await seedIntervalSession(plan.id); // Tuesday
      await repository.addWorkout(
        planId: plan.id,
        weekIndex: 0,
        name: 'Longão',
        kind: RunWorkoutKind.long,
        dayOfWeek: 7,
        targetDistanceMeters: 14000,
      );

      // 2026-01-05 is a Monday.
      final created = await repository.materializeWeek(
        planId: plan.id,
        weekIndex: 0,
        weekStart: DateTime(2026, 1, 7), // mid-week input still snaps to Monday
      );
      expect(created, 2);

      final scheduled = await repository.getScheduledRuns(
        DateTime(2026, 1, 5),
        DateTime(2026, 1, 11),
      );
      expect(scheduled.length, 2);
      expect(scheduled.first.date, DateTime(2026, 1, 6)); // Tuesday
      expect(scheduled.last.date, DateTime(2026, 1, 11)); // Sunday
      expect(scheduled.first.workout!.name, '6x800m');
      expect(scheduled.first.workout!.steps.length, 4);
    });

    test('materializeWeek is idempotent', () async {
      final plan = await seedPlan();
      await seedIntervalSession(plan.id);
      final first = await repository.materializeWeek(
        planId: plan.id,
        weekIndex: 0,
        weekStart: DateTime(2026, 1, 5),
      );
      final second = await repository.materializeWeek(
        planId: plan.id,
        weekIndex: 0,
        weekStart: DateTime(2026, 1, 5),
      );
      expect(first, 1);
      expect(second, 0);
      expect(
        (await repository.getScheduledRunsForDate(DateTime(2026, 1, 6))).length,
        1,
      );
    });

    test('attaching an activity marks the scheduled run completed', () async {
      final plan = await seedPlan();
      final session = await seedIntervalSession(plan.id);
      final scheduled = await repository.scheduleRun(
        date: DateTime(2026, 1, 6),
        runPlanId: plan.id,
        runPlanWorkoutId: session.id,
      );
      final now = DateTime.now().toIso8601String();
      await database.insert('run_activities', {
        'id': 'act1',
        'started_at': now,
        'created_at': now,
        'updated_at': now,
        'status': 'completed',
        'distance_meters': 7800.0,
      });

      await repository.attachActivity(
        scheduledRunId: scheduled.id,
        runActivityId: 'act1',
      );

      final reloaded = (await repository.getScheduledRun(scheduled.id))!;
      expect(reloaded.status, ScheduledRunStatus.completed);
      expect(reloaded.runActivityId, 'act1');
    });

    test(
      'deleting the activity clears the link but keeps the schedule',
      () async {
        final plan = await seedPlan();
        final scheduled = await repository.scheduleRun(
          date: DateTime(2026, 1, 6),
          runPlanId: plan.id,
        );
        final now = DateTime.now().toIso8601String();
        await database.insert('run_activities', {
          'id': 'act1',
          'started_at': now,
          'created_at': now,
          'updated_at': now,
          'status': 'completed',
        });
        await repository.attachActivity(
          scheduledRunId: scheduled.id,
          runActivityId: 'act1',
        );

        await database.delete(
          'run_activities',
          where: 'id = ?',
          whereArgs: ['act1'],
        );

        final reloaded = (await repository.getScheduledRun(scheduled.id))!;
        expect(reloaded.runActivityId, isNull);
      },
    );

    test('a skipped run keeps its status', () async {
      final plan = await seedPlan();
      final scheduled = await repository.scheduleRun(
        date: DateTime(2026, 1, 6),
        runPlanId: plan.id,
      );
      await repository.updateScheduledRun(
        scheduled.id,
        status: ScheduledRunStatus.skipped,
        notes: 'Canela dolorida',
      );
      final reloaded = (await repository.getScheduledRun(scheduled.id))!;
      expect(reloaded.isSkipped, isTrue);
      expect(reloaded.notes, 'Canela dolorida');
    });

    test('deleting a plan cascades its scheduled runs', () async {
      final plan = await seedPlan();
      final session = await seedIntervalSession(plan.id);
      await repository.scheduleRun(
        date: DateTime(2026, 1, 6),
        runPlanId: plan.id,
        runPlanWorkoutId: session.id,
      );
      await repository.deletePlan(plan.id);
      expect(
        await repository.getScheduledRunsForDate(DateTime(2026, 1, 6)),
        isEmpty,
      );
    });
  });

  group('step results', () {
    test('saving step results is idempotent per activity', () async {
      final now = DateTime.now().toIso8601String();
      await database.insert('run_activities', {
        'id': 'act1',
        'started_at': now,
        'created_at': now,
        'updated_at': now,
        'status': 'completed',
      });

      RunActivityStep result(int order, double distance, int seconds) =>
          RunActivityStep(
            id: '',
            runActivityId: 'act1',
            orderIndex: order,
            role: 'work',
            repIndex: order + 1,
            plannedMetric: 'distance',
            plannedValue: 800,
            plannedPaceSecPerKm: 230,
            actualDistanceMeters: distance,
            actualDurationSeconds: seconds,
            actualPaceSecPerKm: seconds / (distance / 1000),
          );

      await repository.saveActivitySteps('act1', [
        result(0, 800, 188),
        result(1, 800, 192),
      ]);
      await repository.saveActivitySteps('act1', [result(0, 800, 188)]);

      final steps = await repository.getActivitySteps('act1');
      expect(steps.length, 1);
      expect(steps.single.paceDeltaSecPerKm, closeTo(235 - 230, 0.5));
    });

    test('links an ad-hoc activity to the plan session it came from', () async {
      final plan = await seedPlan();
      final session = await seedIntervalSession(plan.id);
      final now = DateTime.now().toIso8601String();
      await database.insert('run_activities', {
        'id': 'act1',
        'started_at': now,
        'created_at': now,
        'updated_at': now,
        'status': 'completed',
      });

      await repository.setActivityPlanWorkout(
        activityId: 'act1',
        planWorkoutId: session.id,
      );

      final row = (await database.query(
        'run_activities',
        where: 'id = ?',
        whereArgs: ['act1'],
      )).single;
      expect(row['plan_workout_id'], session.id);
    });
  });
}
