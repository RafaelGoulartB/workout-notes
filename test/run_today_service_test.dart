import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/database/database_periodization_schema.dart';
import 'package:workout_notes/database/database_run_plan_schema.dart';
import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/models/run_plan.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/models/scheduled_run.dart';
import 'package:workout_notes/repositories/run_plan_repository.dart';
import 'package:workout_notes/services/run_today_service.dart';
import 'support/test_db.dart';

// 2026-08-19 is a Wednesday.
final _wednesday = DateTime(2026, 8, 19);

RunPlanWorkout _session(
  String id, {
  int week = 0,
  int? day,
  double meters = 8000,
  RunWorkoutKind kind = RunWorkoutKind.easy,
  String? name,
}) => RunPlanWorkout(
  id: id,
  runPlanId: 'plan',
  weekIndex: week,
  dayOfWeek: day,
  orderIndex: 0,
  kind: kind,
  name: name ?? 'Session $id',
  targetDistanceMeters: meters,
  createdAt: DateTime(2026),
);

ScheduledRun _scheduled(
  String id,
  DateTime date,
  RunPlanWorkout workout, {
  ScheduledRunStatus status = ScheduledRunStatus.planned,
  String? activityId,
}) => ScheduledRun(
  id: id,
  date: date,
  runPlanId: 'plan',
  runPlanWorkoutId: workout.id,
  status: status,
  runActivityId: activityId,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  workout: workout,
);

RunPlan _plan(List<RunPlanWorkout> workouts, {DateTime? activatedAt}) =>
    RunPlan(
      id: 'plan',
      name: '10 km',
      goalKind: RunPlanGoalKind.tenK,
      weeks: 4,
      status: RunPlanStatus.active,
      activatedAt: activatedAt ?? DateTime(2026, 8, 17),
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      workouts: workouts,
    );

RunActivity _activity(String id, DateTime startedAt) => RunActivity(
  id: id,
  startedAt: startedAt,
  endedAt: startedAt.add(const Duration(minutes: 30)),
  durationSeconds: 1800,
  movingTimeSeconds: 1800,
  distanceMeters: 5000,
  avgPaceSecPerKm: 360,
  maxPaceSecPerKm: null,
  calories: null,
  title: null,
  notes: null,
  status: 'completed',
  polylineSummary: null,
  createdAt: startedAt,
  updatedAt: startedAt,
);

void main() {
  group('RunTodayResolver.resolve', () {
    final tempo = _session('tempo', day: 3, kind: RunWorkoutKind.tempo);
    final long = _session('long', day: 7, meters: 14000);

    test('a pending scheduled session is planned for today', () {
      final info = RunTodayResolver.resolve(
        today: _wednesday,
        scheduledToday: [_scheduled('s1', _wednesday, tempo)],
      );
      expect(info.status, RunTodayStatus.planned);
      expect(info.session?.workout.id, 'tempo');
      expect(info.session?.scheduled?.id, 's1');
    });

    test('a completed session shows the run that fulfilled it', () {
      final run = _activity('run1', DateTime(2026, 8, 19, 7));
      final info = RunTodayResolver.resolve(
        today: _wednesday,
        scheduledToday: [
          _scheduled(
            's1',
            _wednesday,
            tempo,
            status: ScheduledRunStatus.completed,
            activityId: 'run1',
          ),
        ],
        todayActivities: [_activity('other', DateTime(2026, 8, 19, 6)), run],
        upcoming: [_scheduled('s2', DateTime(2026, 8, 23), long)],
      );
      expect(info.status, RunTodayStatus.done);
      expect(info.doneActivity?.id, 'run1');
      expect(info.session?.workout.id, 'tempo');
      expect(info.next?.workout.id, 'long');
    });

    test('a skipped session makes today a rest day with the next session', () {
      final info = RunTodayResolver.resolve(
        today: _wednesday,
        scheduledToday: [
          _scheduled(
            's1',
            _wednesday,
            tempo,
            status: ScheduledRunStatus.skipped,
          ),
        ],
        upcoming: [_scheduled('s2', DateTime(2026, 8, 23), long)],
      );
      expect(info.status, RunTodayStatus.rest);
      expect(info.next?.workout.id, 'long');
      expect(info.next?.date, DateTime(2026, 8, 23));
    });

    test('with no session today, a followed plan gives a rest day', () {
      final plan = _plan([long]);
      final info = RunTodayResolver.resolve(
        today: _wednesday,
        followedPlan: plan,
      );
      expect(info.status, RunTodayStatus.rest);
      // Read from the plan definition: Sunday is the next long run.
      expect(info.next?.workout.id, 'long');
      expect(info.next?.date, DateTime(2026, 8, 23));
    });

    test('reads the session from the plan when the calendar is empty', () {
      final plan = _plan([tempo, long]);
      final info = RunTodayResolver.resolve(
        today: _wednesday,
        followedPlan: plan,
      );
      expect(info.status, RunTodayStatus.planned);
      expect(info.session?.workout.id, 'tempo');
      expect(info.session?.scheduled, isNull);
      expect(info.session?.planName, '10 km');
    });

    test('a free run today is shown as done', () {
      final info = RunTodayResolver.resolve(
        today: _wednesday,
        todayActivities: [_activity('free', DateTime(2026, 8, 19, 18))],
      );
      expect(info.status, RunTodayStatus.done);
      expect(info.doneActivity?.id, 'free');
      expect(info.session, isNull);
    });

    test('yesterday runs do not count as done today', () {
      final info = RunTodayResolver.resolve(
        today: _wednesday,
        todayActivities: [_activity('old', DateTime(2026, 8, 18, 18))],
      );
      expect(info.status, RunTodayStatus.none);
    });

    test('no plan and no history is the no-plan state', () {
      final info = RunTodayResolver.resolve(today: _wednesday);
      expect(info.status, RunTodayStatus.none);
      expect(info.next, isNull);
    });

    test('a pending session still wins over a free run already recorded', () {
      final info = RunTodayResolver.resolve(
        today: _wednesday,
        scheduledToday: [_scheduled('s1', _wednesday, tempo)],
        todayActivities: [_activity('free', DateTime(2026, 8, 19, 6))],
      );
      expect(info.status, RunTodayStatus.planned);
    });
  });

  group('RunTodayResolver.weekPlan', () {
    final tempo = _session('tempo', day: 3, kind: RunWorkoutKind.tempo);
    final easy = _session('easy', day: 1, meters: 5000);
    final long = _session('long', day: 7, meters: 14000);

    test('maps calendar rows to done, missed, skipped and pending', () {
      final days = RunTodayResolver.weekPlan(
        today: _wednesday,
        scheduledThisWeek: [
          _scheduled(
            'a',
            DateTime(2026, 8, 17),
            easy,
            status: ScheduledRunStatus.completed,
          ),
          _scheduled('b', DateTime(2026, 8, 18), easy),
          _scheduled('c', _wednesday, tempo),
          _scheduled(
            'd',
            DateTime(2026, 8, 20),
            easy,
            status: ScheduledRunStatus.skipped,
          ),
          _scheduled('e', DateTime(2026, 8, 23), long),
        ],
      );
      expect(days.map((d) => d.state), [
        RunPlannedDayState.done,
        RunPlannedDayState.missed,
        RunPlannedDayState.pending,
        RunPlannedDayState.skipped,
        RunPlannedDayState.pending,
      ]);
      expect(days.last.plannedMeters, 14000);
    });

    test('falls back to the plan definition when nothing is scheduled', () {
      final days = RunTodayResolver.weekPlan(
        today: _wednesday,
        scheduledThisWeek: const [],
        followedPlan: _plan([easy, tempo, long]),
      );
      expect(days.map((d) => d.date.weekday), [1, 3, 7]);
      expect(days.first.state, RunPlannedDayState.missed);
      expect(days[1].state, RunPlannedDayState.pending);
      expect(days.last.state, RunPlannedDayState.pending);
    });

    test('a free run on a missed planned day counts as done', () {
      final planned = RunTodayResolver.weekPlan(
        today: _wednesday,
        scheduledThisWeek: [_scheduled('b', DateTime(2026, 8, 18), easy)],
      );
      final reconciled = RunTodayResolver.reconcileWithRuns(planned, [
        RunDayRuns(DateTime(2026, 8, 18), 1),
      ]);
      expect(reconciled.single.state, RunPlannedDayState.done);
    });

    test('no plan, no rows: nothing planned', () {
      expect(
        RunTodayResolver.weekPlan(
          today: _wednesday,
          scheduledThisWeek: const [],
        ),
        isEmpty,
      );
    });
  });

  group('RunWeekGoal.resolve', () {
    test('prefers the plan, then the user goal, then the average', () {
      expect(
        RunWeekGoal.resolve(
          planMeters: 30000,
          userMeters: 20000,
          averageMeters: 10000,
        )?.source,
        RunWeekGoalSource.plan,
      );
      final user = RunWeekGoal.resolve(userMeters: 20000, averageMeters: 10000);
      expect(user?.source, RunWeekGoalSource.user);
      expect(user?.meters, 20000);
      expect(
        RunWeekGoal.resolve(averageMeters: 10000)?.source,
        RunWeekGoalSource.average,
      );
    });

    test('ignores zero values and returns null when nothing is left', () {
      expect(
        RunWeekGoal.resolve(planMeters: 0, userMeters: 0, averageMeters: 0),
        isNull,
      );
      expect(RunWeekGoal.resolve(), isNull);
    });
  });

  group('RunTodayService with a database', () {
    late Database database;
    late RunPlanRepository plans;
    late RunTodayService service;

    setUpAll(initSqfliteFfiForTests);

    setUp(() async {
      database = await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, version) async {
            await db.execute(
              'CREATE TABLE routines (id TEXT PRIMARY KEY, name TEXT NOT NULL, notes TEXT, created_at TEXT NOT NULL)',
            );
            await db.execute(
              'CREATE TABLE run_activities (id TEXT PRIMARY KEY, '
              "activity_type TEXT NOT NULL DEFAULT 'running', "
              'started_at TEXT NOT NULL, ended_at TEXT, '
              'duration_seconds INTEGER NOT NULL DEFAULT 0, '
              'moving_time_seconds INTEGER NOT NULL DEFAULT 0, '
              'distance_meters REAL NOT NULL DEFAULT 0, '
              'avg_pace_sec_per_km REAL, max_pace_sec_per_km REAL, '
              'calories INTEGER, title TEXT, notes TEXT, '
              "status TEXT NOT NULL DEFAULT 'completed', "
              'polyline_summary TEXT, created_at TEXT NOT NULL, '
              'updated_at TEXT NOT NULL, plan_workout_id TEXT)',
            );
            await db.execute(
              'CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
            );
            await DatabasePeriodizationSchema.create(db);
            await DatabaseRunPlanSchema.create(db);
          },
        ),
      );
      DatabaseHelper.overrideDatabase = database;
      plans = RunPlanRepository();
      service = RunTodayService();
    });

    tearDown(() async {
      DatabaseHelper.overrideDatabase = null;
      await database.close();
    });

    test('no plan yields the no-plan state', () async {
      final snapshot = await service.load(now: _wednesday);
      expect(snapshot.today.status, RunTodayStatus.none);
      expect(snapshot.plan, isNull);
      expect(snapshot.weekPlan, isEmpty);
      expect(snapshot.userWeeklyGoalMeters, isNull);
    });

    test('a followed plan drives today, the week and the plan card', () async {
      final plan = await plans.createPlan(
        name: '10 km',
        goalKind: RunPlanGoalKind.tenK,
        weeks: 4,
      );
      await plans.addWorkout(
        planId: plan.id,
        weekIndex: 0,
        name: 'Tempo 6 km',
        kind: RunWorkoutKind.tempo,
        dayOfWeek: DateTime.wednesday,
        targetDistanceMeters: 6000,
      );
      await plans.addWorkout(
        planId: plan.id,
        weekIndex: 0,
        name: 'Longão',
        kind: RunWorkoutKind.long,
        dayOfWeek: DateTime.sunday,
        targetDistanceMeters: 14000,
      );
      await plans.activatePlan(plan.id, from: DateTime(2026, 8, 17));

      final snapshot = await service.load(now: _wednesday);

      expect(snapshot.today.status, RunTodayStatus.planned);
      expect(snapshot.today.session?.workout.name, 'Tempo 6 km');
      expect(snapshot.today.session?.scheduled, isNotNull);
      expect(snapshot.plan?.plan.id, plan.id);
      expect(snapshot.plan?.weekNumber, 1);
      expect(snapshot.plan?.weekPlannedMeters, 20000);
      expect(snapshot.nextSession?.workout.name, 'Longão');
      expect(snapshot.weekPlan.map((d) => d.date.weekday), [3, 7]);
      expect(snapshot.weekPlan.first.state, RunPlannedDayState.pending);
    });

    test('a run recorded for the session turns today into done', () async {
      final plan = await plans.createPlan(
        name: '10 km',
        goalKind: RunPlanGoalKind.tenK,
        weeks: 4,
      );
      final workout = await plans.addWorkout(
        planId: plan.id,
        weekIndex: 0,
        name: 'Tempo 6 km',
        kind: RunWorkoutKind.tempo,
        dayOfWeek: DateTime.wednesday,
        targetDistanceMeters: 6000,
      );
      await plans.activatePlan(plan.id, from: DateTime(2026, 8, 17));
      final started = DateTime(2026, 8, 19, 7);
      await database.insert('run_activities', {
        'id': 'run1',
        'started_at': started.toIso8601String(),
        'duration_seconds': 1800,
        'moving_time_seconds': 1800,
        'distance_meters': 6000.0,
        'status': 'completed',
        'created_at': started.toIso8601String(),
        'updated_at': started.toIso8601String(),
      });
      await plans.markPlanWorkoutCompleted(
        planWorkoutId: workout.id,
        date: _wednesday,
        runActivityId: 'run1',
      );

      final snapshot = await service.load(now: _wednesday);

      expect(snapshot.today.status, RunTodayStatus.done);
      expect(snapshot.today.doneActivity?.id, 'run1');
      expect(snapshot.today.session?.workout.id, workout.id);
      expect(snapshot.weekPlan.single.state, RunPlannedDayState.done);
    });

    test(
      'the weekly goal is stored in app_settings and can be cleared',
      () async {
        expect(await service.readWeeklyGoalMeters(), isNull);
        await service.setWeeklyGoalKm(25);
        expect(await service.readWeeklyGoalMeters(), 25000);
        expect(
          (await service.load(now: _wednesday)).userWeeklyGoalMeters,
          25000,
        );
        await service.setWeeklyGoalKm(null);
        expect(await service.readWeeklyGoalMeters(), isNull);
      },
    );
  });
}
