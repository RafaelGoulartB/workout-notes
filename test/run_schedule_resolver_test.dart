import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/database/database_periodization_schema.dart';
import 'package:workout_notes/database/database_run_plan_schema.dart';
import 'package:workout_notes/models/periodization_plan.dart';
import 'package:workout_notes/models/periodization_target.dart';
import 'package:workout_notes/models/run_plan.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/models/run_voice_settings.dart';
import 'package:workout_notes/models/run_workout_step.dart';
import 'package:workout_notes/models/scheduled_run.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';
import 'package:workout_notes/repositories/run_plan_repository.dart';

/// Covers how the periodization plan resolves "which run is due today" and how
/// the running targets feed phase adherence.
void main() {
  late Database database;
  late PeriodizationRepository periodization;
  late RunPlanRepository runPlans;

  // 2026-01-05 is a Monday, so weekday arithmetic stays readable.
  final phaseStart = DateTime(2026, 1, 5);
  final phaseEnd = DateTime(2026, 2, 1);

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
            'CREATE TABLE routine_days (id TEXT PRIMARY KEY, routine_id TEXT NOT NULL, name TEXT NOT NULL, order_index INTEGER NOT NULL DEFAULT 0, FOREIGN KEY (routine_id) REFERENCES routines(id) ON DELETE CASCADE)',
          );
          await db.execute(
            'CREATE TABLE workouts (id TEXT PRIMARY KEY, date TEXT NOT NULL, start_time TEXT, end_time TEXT, duration_seconds INTEGER, routine_id TEXT, created_at TEXT NOT NULL)',
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
          await db.execute(
            'CREATE TABLE run_activities (id TEXT PRIMARY KEY, started_at TEXT NOT NULL, ended_at TEXT, '
            'duration_seconds INTEGER NOT NULL DEFAULT 0, moving_time_seconds INTEGER NOT NULL DEFAULT 0, '
            'distance_meters REAL NOT NULL DEFAULT 0, status TEXT NOT NULL DEFAULT \'completed\', '
            'created_at TEXT NOT NULL, updated_at TEXT NOT NULL, plan_workout_id TEXT)',
          );
          await DatabasePeriodizationSchema.create(db);
          await DatabaseRunPlanSchema.create(db);
        },
      ),
    );
    DatabaseHelper.overrideDatabase = database;
    periodization = PeriodizationRepository();
    runPlans = RunPlanRepository();
  });

  tearDown(() async {
    DatabaseHelper.overrideDatabase = null;
    await database.close();
  });

  /// Creates an active plan with one phase covering [phaseStart]..[phaseEnd],
  /// whose weekly target links [runPlanIds] and carries the given run volume.
  Future<String> seedPhase({
    List<String> runPlanIds = const [],
    int? runPlanStartWeek,
    int? runSessionsPerWeek,
    double? runWeeklyDistanceMeters,
    double? longRunDistanceMeters,
    int? qualitySessionsPerWeek,
  }) async {
    final plan = await periodization.createPlan(
      name: 'Base',
      startDate: phaseStart,
      endDate: phaseEnd,
    );
    final phase = await periodization.addPhase(
      planId: plan.id,
      name: 'Acumulação',
      color: 0xFF00FF00,
      startDate: phaseStart,
      endDate: phaseEnd,
      target: PeriodizationTarget(
        id: '',
        phaseId: '',
        version: 0,
        validFrom: phaseStart,
        workoutsPerWeek: 3,
        runPlanIds: runPlanIds,
        runPlanStartWeek: runPlanStartWeek,
        runSessionsPerWeek: runSessionsPerWeek,
        runWeeklyDistanceMeters: runWeeklyDistanceMeters,
        longRunDistanceMeters: longRunDistanceMeters,
        qualitySessionsPerWeek: qualitySessionsPerWeek,
        createdAt: phaseStart,
      ),
    );
    // A plan only activates once it holds a phase.
    await periodization.setPlanStatus(plan.id, PeriodizationPlanStatus.active);
    return phase.id;
  }

  /// `2 km warmup + 6x(800 m / 2 min) + 1 km cooldown` on [dayOfWeek].
  Future<RunPlanWorkout> seedIntervalSession(
    String planId, {
    required int weekIndex,
    required int dayOfWeek,
    String name = '6x800m',
  }) async {
    final session = await runPlans.addWorkout(
      planId: planId,
      weekIndex: weekIndex,
      name: name,
      kind: RunWorkoutKind.interval,
      dayOfWeek: dayOfWeek,
    );
    await runPlans.addStep(
      workoutId: session.id,
      role: RunStepRole.warmup,
      metric: RunIntervalMetric.distance,
      value: 2000,
    );
    await runPlans.addStep(
      workoutId: session.id,
      role: RunStepRole.work,
      metric: RunIntervalMetric.distance,
      value: 800,
      repeatGroup: 1,
      repeatCount: 6,
      targetPaceMinSecPerKm: 235,
    );
    await runPlans.addStep(
      workoutId: session.id,
      role: RunStepRole.recovery,
      metric: RunIntervalMetric.time,
      value: 120,
      repeatGroup: 1,
      repeatCount: 6,
    );
    await runPlans.addStep(
      workoutId: session.id,
      role: RunStepRole.cooldown,
      metric: RunIntervalMetric.distance,
      value: 1000,
    );
    return (await runPlans.getWorkout(session.id))!;
  }

  Future<void> insertRun({
    required DateTime date,
    required double meters,
    String? planWorkoutId,
    String status = 'completed',
  }) async {
    final id = 'run-${date.toIso8601String()}-$meters';
    await database.insert('run_activities', {
      'id': id,
      'started_at': DateTime(
        date.year,
        date.month,
        date.day,
        6,
      ).toIso8601String(),
      'distance_meters': meters,
      'moving_time_seconds': (meters / 1000 * 300).round(),
      'status': status,
      'plan_workout_id': planWorkoutId,
      'created_at': date.toIso8601String(),
      'updated_at': date.toIso8601String(),
    });
  }

  group('getRunSuggestion', () {
    test('returns nothing when the phase links no running plan', () async {
      await seedPhase();
      expect(await periodization.getRunSuggestion(phaseStart), isNull);
    });

    test('matches the session by weekday inside the phase week', () async {
      final plan = await runPlans.createPlan(name: '10 km', weeks: 4);
      // Tuesday intervals, Sunday long run.
      await seedIntervalSession(plan.id, weekIndex: 0, dayOfWeek: 2);
      await runPlans.addWorkout(
        planId: plan.id,
        weekIndex: 0,
        name: 'Longão',
        kind: RunWorkoutKind.long,
        dayOfWeek: 7,
        targetDistanceMeters: 14000,
      );
      await seedPhase(runPlanIds: [plan.id]);

      final tuesday = await periodization.getRunSuggestion(
        DateTime(2026, 1, 6),
      );
      expect(tuesday!.workout.name, '6x800m');
      expect(tuesday.workout.workRepCount, 6);
      expect(tuesday.runPlanName, '10 km');
      expect(tuesday.weekIndex, 0);

      final sunday = await periodization.getRunSuggestion(
        DateTime(2026, 1, 11),
      );
      expect(sunday!.workout.name, 'Longão');

      // Wednesday has no session.
      expect(
        await periodization.getRunSuggestion(DateTime(2026, 1, 7)),
        isNull,
      );
    });

    test('advances to the plan week matching the phase week', () async {
      final plan = await runPlans.createPlan(name: 'Progressivo', weeks: 4);
      for (var week = 0; week < 4; week++) {
        await runPlans.addWorkout(
          planId: plan.id,
          weekIndex: week,
          name: 'Longão semana ${week + 1}',
          kind: RunWorkoutKind.long,
          dayOfWeek: 7,
          targetDistanceMeters: 10000 + week * 2000,
        );
      }
      await seedPhase(runPlanIds: [plan.id]);

      final week1 = await periodization.getRunSuggestion(DateTime(2026, 1, 11));
      final week3 = await periodization.getRunSuggestion(DateTime(2026, 1, 25));
      expect(week1!.workout.name, 'Longão semana 1');
      expect(week3!.workout.name, 'Longão semana 3');
      expect(week3.weekIndex, 2);
    });

    test('a one-week plan repeats across every phase week', () async {
      final plan = await runPlans.createPlan(name: 'Manutenção', weeks: 1);
      await runPlans.addWorkout(
        planId: plan.id,
        weekIndex: 0,
        name: 'Longão fixo',
        kind: RunWorkoutKind.long,
        dayOfWeek: 7,
        targetDistanceMeters: 12000,
      );
      await seedPhase(runPlanIds: [plan.id]);

      for (final date in [
        DateTime(2026, 1, 11),
        DateTime(2026, 1, 18),
        DateTime(2026, 1, 25),
      ]) {
        final suggestion = await periodization.getRunSuggestion(date);
        expect(suggestion!.workout.name, 'Longão fixo');
      }
    });

    test('a session without a weekday is offered on any day', () async {
      final plan = await runPlans.createPlan(name: 'Livre', weeks: 1);
      await runPlans.addWorkout(
        planId: plan.id,
        weekIndex: 0,
        name: 'Rodagem livre',
        kind: RunWorkoutKind.easy,
        targetDistanceMeters: 6000,
      );
      await seedPhase(runPlanIds: [plan.id]);
      final suggestion = await periodization.getRunSuggestion(
        DateTime(2026, 1, 7),
      );
      expect(suggestion!.workout.name, 'Rodagem livre');
    });

    test('an already scheduled run wins, carrying its status', () async {
      final plan = await runPlans.createPlan(name: '10 km', weeks: 4);
      final session = await seedIntervalSession(
        plan.id,
        weekIndex: 0,
        dayOfWeek: 2,
      );
      await seedPhase(runPlanIds: [plan.id]);
      // Moved from Tuesday to Wednesday.
      final scheduled = await runPlans.scheduleRun(
        date: DateTime(2026, 1, 7),
        runPlanId: plan.id,
        runPlanWorkoutId: session.id,
      );
      await runPlans.updateScheduledRun(
        scheduled.id,
        status: ScheduledRunStatus.skipped,
      );

      final wednesday = await periodization.getRunSuggestion(
        DateTime(2026, 1, 7),
      );
      expect(wednesday!.scheduled, isNotNull);
      expect(wednesday.isSkipped, isTrue);
      expect(wednesday.workout.name, '6x800m');
    });

    test('reports completed runs of the week', () async {
      final plan = await runPlans.createPlan(name: '10 km', weeks: 4);
      await seedIntervalSession(plan.id, weekIndex: 0, dayOfWeek: 2);
      await seedPhase(runPlanIds: [plan.id]);
      await insertRun(date: DateTime(2026, 1, 5), meters: 6000);
      await insertRun(date: DateTime(2026, 1, 6), meters: 7800);
      // Outside the week — must not be counted.
      await insertRun(date: DateTime(2026, 1, 13), meters: 5000);

      final suggestion = await periodization.getRunSuggestion(
        DateTime(2026, 1, 6),
      );
      expect(suggestion!.completedRunsThisWeek, 2);
    });

    test('returns nothing outside any phase', () async {
      final plan = await runPlans.createPlan(name: '10 km', weeks: 4);
      await seedIntervalSession(plan.id, weekIndex: 0, dayOfWeek: 2);
      await seedPhase(runPlanIds: [plan.id]);
      expect(
        await periodization.getRunSuggestion(DateTime(2026, 3, 3)),
        isNull,
      );
    });
  });

  group('running metrics', () {
    test('sums logged volume and compares it to the weekly target', () async {
      final phaseId = await seedPhase(
        runSessionsPerWeek: 3,
        runWeeklyDistanceMeters: 30000,
        longRunDistanceMeters: 14000,
        qualitySessionsPerWeek: 1,
      );
      final phase = (await periodization.getPhase(phaseId))!;

      await insertRun(date: DateTime(2026, 1, 5), meters: 6000);
      await insertRun(date: DateTime(2026, 1, 6), meters: 7800);
      await insertRun(date: DateTime(2026, 1, 11), meters: 12000);
      // Discarded runs never count.
      await insertRun(
        date: DateTime(2026, 1, 8),
        meters: 5000,
        status: 'discarded',
      );

      final metrics = await periodization.getWeekMetrics(
        phase,
        DateTime(2026, 1, 5),
      );
      expect(metrics.runCount, 3);
      expect(metrics.runDistanceMeters, closeTo(25800, 0.01));
      expect(metrics.longestRunMeters, closeTo(12000, 0.01));
      expect(metrics.plannedRunSessions, 3);
      expect(metrics.plannedRunDistanceMeters, closeTo(30000, 0.01));
      expect(metrics.runVolumeAdherencePercent, closeTo(86, 1));
      expect(metrics.longRunAdherencePercent, closeTo(85.7, 1));
    });

    test('counts a quality session only when it came from a plan', () async {
      final plan = await runPlans.createPlan(name: '10 km', weeks: 4);
      final interval = await seedIntervalSession(
        plan.id,
        weekIndex: 0,
        dayOfWeek: 2,
      );
      final easy = await runPlans.addWorkout(
        planId: plan.id,
        weekIndex: 0,
        name: 'Rodagem',
        kind: RunWorkoutKind.easy,
        dayOfWeek: 4,
        targetDistanceMeters: 6000,
      );
      final phaseId = await seedPhase(
        runPlanIds: [plan.id],
        runSessionsPerWeek: 3,
        qualitySessionsPerWeek: 1,
      );
      final phase = (await periodization.getPhase(phaseId))!;

      await insertRun(
        date: DateTime(2026, 1, 6),
        meters: 7800,
        planWorkoutId: interval.id,
      );
      await insertRun(
        date: DateTime(2026, 1, 8),
        meters: 6000,
        planWorkoutId: easy.id,
      );
      // Ad-hoc run: volume, but not quality.
      await insertRun(date: DateTime(2026, 1, 9), meters: 5000);

      final metrics = await periodization.getWeekMetrics(
        phase,
        DateTime(2026, 1, 5),
      );
      expect(metrics.runCount, 3);
      expect(metrics.qualityRunCount, 1);
    });

    test('a phase without running targets reports null adherence', () async {
      final phaseId = await seedPhase();
      final phase = (await periodization.getPhase(phaseId))!;
      await insertRun(date: DateTime(2026, 1, 6), meters: 7800);

      final metrics = await periodization.getWeekMetrics(
        phase,
        DateTime(2026, 1, 5),
      );
      // Volume is still reported — only the comparison is absent.
      expect(metrics.runDistanceMeters, closeTo(7800, 0.01));
      expect(metrics.plannedRunDistanceMeters, isNull);
      expect(metrics.runVolumeAdherencePercent, isNull);
    });

    test('weekly targets are not multiplied across the days of a phase', () async {
      final phaseId = await seedPhase(runWeeklyDistanceMeters: 30000);
      final phase = (await periodization.getPhase(phaseId))!;

      // Two full weeks of the phase → 60 km planned, not 30 km x 14 days.
      final metrics = await periodization.getPhaseMetrics(
        phase,
        rangeStart: DateTime(2026, 1, 5),
        rangeEnd: DateTime(2026, 1, 18),
      );
      expect(metrics.plannedRunDistanceMeters, closeTo(60000, 0.01));
    });
  });

  group('run targets persistence', () {
    test('saveTargetVersion keeps the routine and running links', () async {
      final routine = 'routine-1';
      await database.insert('routines', {
        'id': routine,
        'name': 'Full body',
        'created_at': phaseStart.toIso8601String(),
      });
      final phaseId = await seedPhase();
      final saved = await periodization.saveTargetVersion(
        phaseId,
        PeriodizationTarget(
          id: '',
          phaseId: phaseId,
          version: 0,
          validFrom: phaseStart,
          calories: 2400,
          routineIds: [routine],
          runPlanIds: ['plan-y'],
          runSessionsPerWeek: 4,
          runWeeklyDistanceMeters: 40000,
          longRunDistanceMeters: 16000,
          qualitySessionsPerWeek: 2,
          runPlanStartWeek: 3,
          createdAt: phaseStart,
        ),
        validFrom: phaseStart,
      );

      // A new version used to be written with only the nutrition/strength
      // numbers, silently unlinking the routine and the running plan.
      expect(saved.routineIds, [routine]);
      expect(saved.runPlanIds, ['plan-y']);
      expect(saved.runSessionsPerWeek, 4);
      expect(saved.runPlanStartWeek, 3);

      final reread = await periodization.getEffectiveTarget(
        phaseId,
        date: phaseStart,
      );
      expect(reread!.routineIds, [routine]);
      expect(reread.runPlanIds, ['plan-y']);
      expect(reread.longRunDistanceMeters, 16000);
      expect(reread.runPlanStartWeek, 3);
    });

    test('survive a save/read round trip inside training_json', () async {
      final phaseId = await seedPhase(
        runPlanIds: ['plan-x'],
        runSessionsPerWeek: 4,
        runWeeklyDistanceMeters: 42000,
        longRunDistanceMeters: 18000,
        qualitySessionsPerWeek: 2,
      );
      final target = await periodization.getEffectiveTarget(phaseId);
      expect(target!.runSessionsPerWeek, 4);
      expect(target.runWeeklyDistanceMeters, 42000);
      expect(target.longRunDistanceMeters, 18000);
      expect(target.qualitySessionsPerWeek, 2);
      expect(target.runPlanIds, ['plan-x']);
      // The strength side is untouched.
      expect(target.workoutsPerWeek, 3);
    });

    test('a target with no running block leaves the run key absent', () async {
      final phaseId = await seedPhase();
      final target = await periodization.getEffectiveTarget(phaseId);
      expect(target!.runJson, isEmpty);
      expect(target.trainingJson.containsKey('run'), isFalse);
      expect(target.runPlanIds, isEmpty);
    });

    test('rejects more quality sessions than total runs', () async {
      expect(
        () => seedPhase(runSessionsPerWeek: 2, qualitySessionsPerWeek: 4),
        throwsA(isA<PeriodizationValidationException>()),
      );
    });
  });
  group('plan week alignment', () {
    test('the offset starts the phase mid-plan', () async {
      final runPlan = await runPlans.createPlan(
        name: 'Meia maratona',
        goalKind: RunPlanGoalKind.half,
        weeks: 4,
      );
      for (var week = 0; week < 4; week++) {
        await seedIntervalSession(
          runPlan.id,
          weekIndex: week,
          dayOfWeek: 2,
          name: 'Tiros semana ${week + 1}',
        );
      }
      // The phase joins the plan already on its third week (index 2).
      await seedPhase(runPlanIds: [runPlan.id], runPlanStartWeek: 2);

      // Phase week 1 → plan week 3.
      final first = await periodization.getRunSuggestion(DateTime(2026, 1, 6));
      expect(first!.workout.name, 'Tiros semana 3');
      expect(first.weekIndex, 2);

      // Phase week 2 → plan week 4, the last one.
      final second = await periodization.getRunSuggestion(
        DateTime(2026, 1, 13),
      );
      expect(second!.workout.name, 'Tiros semana 4');

      // Phase week 3 wraps back to the start of the plan.
      final third = await periodization.getRunSuggestion(DateTime(2026, 1, 20));
      expect(third!.workout.name, 'Tiros semana 1');
    });

    test('no offset keeps the plan and the phase starting together', () async {
      final runPlan = await runPlans.createPlan(
        name: 'Base',
        goalKind: RunPlanGoalKind.base,
        weeks: 2,
      );
      await seedIntervalSession(
        runPlan.id,
        weekIndex: 0,
        dayOfWeek: 2,
        name: 'Semana 1',
      );
      await seedIntervalSession(
        runPlan.id,
        weekIndex: 1,
        dayOfWeek: 2,
        name: 'Semana 2',
      );
      await seedPhase(runPlanIds: [runPlan.id]);

      final first = await periodization.getRunSuggestion(DateTime(2026, 1, 6));
      expect(first!.workout.name, 'Semana 1');
      final second = await periodization.getRunSuggestion(
        DateTime(2026, 1, 13),
      );
      expect(second!.workout.name, 'Semana 2');
    });
  });

  group('scheduleRunPlanForPhase', () {
    test('materialises every phase week through the offset', () async {
      final runPlan = await runPlans.createPlan(
        name: 'Base',
        goalKind: RunPlanGoalKind.base,
        weeks: 2,
      );
      await seedIntervalSession(
        runPlan.id,
        weekIndex: 0,
        dayOfWeek: 2,
        name: 'Semana 1',
      );
      await seedIntervalSession(
        runPlan.id,
        weekIndex: 1,
        dayOfWeek: 2,
        name: 'Semana 2',
      );
      final phaseId = await seedPhase(runPlanIds: [runPlan.id]);
      final phase = (await periodization.getPhase(phaseId))!;

      final result = await periodization.scheduleRunPlanForPhase(
        phase,
        from: phaseStart,
      );

      // The phase spans 4 weeks and the 2-week plan repeats across them.
      expect(result.weeksCovered, 4);
      expect(result.created, 4);
      final scheduled = await runPlans.getScheduledRuns(phaseStart, phaseEnd);
      expect(scheduled.map((run) => run.workout?.name).toList(), [
        'Semana 1',
        'Semana 2',
        'Semana 1',
        'Semana 2',
      ]);

      // Idempotent — re-running adds nothing.
      final again = await periodization.scheduleRunPlanForPhase(
        phase,
        from: phaseStart,
      );
      expect(again.created, 0);
    });

    test('skips weeks before "from" so the past is not back-filled', () async {
      final runPlan = await runPlans.createPlan(
        name: 'Base',
        goalKind: RunPlanGoalKind.base,
        weeks: 1,
      );
      await seedIntervalSession(runPlan.id, weekIndex: 0, dayOfWeek: 2);
      final phaseId = await seedPhase(runPlanIds: [runPlan.id]);
      final phase = (await periodization.getPhase(phaseId))!;

      final result = await periodization.scheduleRunPlanForPhase(
        phase,
        from: DateTime(2026, 1, 19), // week 3 of the phase
      );

      expect(result.weeksCovered, 2);
      final scheduled = await runPlans.getScheduledRuns(phaseStart, phaseEnd);
      expect(
        scheduled.map((run) => run.date).toList(),
        [DateTime(2026, 1, 20), DateTime(2026, 1, 27)],
      );
    });

    test('does nothing when the phase links no plan', () async {
      final phaseId = await seedPhase();
      final phase = (await periodization.getPhase(phaseId))!;
      final result = await periodization.scheduleRunPlanForPhase(phase);
      expect(result.isEmpty, isTrue);
      expect(result.weeksCovered, 0);
    });
  });
}
