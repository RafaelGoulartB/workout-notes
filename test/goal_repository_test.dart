import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/models/goal.dart';
import 'package:workout_notes/repositories/goal_repository.dart';
import 'package:workout_notes/utils/date_utils.dart';

import 'support/sql_capture.dart';
import 'support/test_db.dart';

void main() {
  late Database db;
  late SqlLog sqlLog;
  late GoalRepository goals;

  setUpAll(initSqfliteFfiForTests);

  setUp(() async {
    (db, sqlLog) = await installCountingTestDb();
    goals = GoalRepository();
    await db.insert('exercise_categories', {
      'id': 'chest',
      'name': 'Chest',
      'color': 1,
      'energy_system': 'anaerobic',
    });
    await db.insert('exercise_categories', {
      'id': 'cardio',
      'name': 'Cardio',
      'color': 2,
      'energy_system': 'aerobic',
    });
    await _exercise(db, 'bench', 'chest');
    await _exercise(db, 'treadmill', 'cardio');
  });

  tearDown(uninstallTestDb);

  final today = dayOf(DateTime.now());
  final todayKey = dateKey(today);

  group('strength goals count only performed work (A02)', () {
    Future<void> seedMixedWorkouts() async {
      // Finished session: one performed set, one unchecked, one warm-up.
      await _workout(db, 'finished', todayKey);
      await _set(db, 'finished', 'bench', weight: 100, reps: 10);
      await _set(db, 'finished', 'bench', weight: 50, reps: 10, done: false);
      await _set(db, 'finished', 'bench', weight: 20, reps: 10, warmup: true);
      // Started but never finished.
      await _workout(db, 'open', todayKey, finished: false);
      await _set(db, 'open', 'bench', weight: 100, reps: 10);
      // Planned for later: nothing performed yet.
      await _workout(db, 'planned', todayKey, finished: false, started: false);
      await _set(db, 'planned', 'bench', weight: 100, reps: 10, done: false);
    }

    test('volume ignores planned, open, unchecked and warm-up sets', () async {
      await seedMixedWorkouts();
      final goal = _goal(GoalScope.anaerobic, GoalMetric.volume, target: 5000);

      final progress = await goals.getProgress(goal);

      expect(progress.currentValue, 1000.0);
      final contributors = await goals.getContributingWorkouts(goal);
      expect(contributors, hasLength(1));
      expect(contributors.single.workoutId, 'finished');
      expect(contributors.single.contributedValue, 1000.0);
      expect(contributors.single.setCount, 1);
    });

    test('days needs a finished workout with a performed set', () async {
      await seedMixedWorkouts();
      // A finished session with only unchecked sets is not a training day.
      final other = dateKey(addDays(today, today.weekday == 1 ? 1 : -1));
      await _workout(db, 'skipped-sets', other);
      await _set(db, 'skipped-sets', 'bench', weight: 80, reps: 8, done: false);
      final goal = _goal(GoalScope.anaerobic, GoalMetric.days, target: 3);

      expect((await goals.getProgress(goal)).currentValue, 1.0);
      final contributors = await goals.getContributingWorkouts(goal);
      expect(contributors.map((c) => c.workoutId), ['finished']);
    });

    test(
      'two finished sessions on one day are one day, both volumes',
      () async {
        await _workout(db, 'morning', todayKey);
        await _set(db, 'morning', 'bench', weight: 100, reps: 5);
        await _workout(db, 'evening', todayKey);
        await _set(db, 'evening', 'bench', weight: 60, reps: 10);

        final days = _goal(GoalScope.anaerobic, GoalMetric.days, target: 3);
        final volume = _goal(
          GoalScope.anaerobic,
          GoalMetric.volume,
          target: 5000,
        );

        expect((await goals.getProgress(days)).currentValue, 1.0);
        expect((await goals.getProgress(volume)).currentValue, 1100.0);
        // Contributions stay per workout; only the day count merges them.
        expect(await goals.getContributingWorkouts(days), hasLength(2));
        expect(await goals.getContributingWorkouts(volume), hasLength(2));
      },
    );

    test('cardio sets need to be performed too', () async {
      await _workout(db, 'cardio', todayKey);
      await _set(db, 'cardio', 'treadmill', distance: 5, seconds: 1800);
      await _set(
        db,
        'cardio',
        'treadmill',
        distance: 10,
        seconds: 3600,
        done: false,
      );
      await _workout(db, 'cardio-open', todayKey, finished: false);
      await _set(db, 'cardio-open', 'treadmill', distance: 8, seconds: 2400);

      final distance = _goal(
        GoalScope.aerobic,
        GoalMetric.distance,
        target: 20,
      );
      final time = _goal(GoalScope.aerobic, GoalMetric.time, target: 7200);
      final days = _goal(GoalScope.aerobic, GoalMetric.days, target: 3);

      expect((await goals.getProgress(distance)).currentValue, 5.0);
      expect((await goals.getProgress(time)).currentValue, 1800.0);
      expect((await goals.getProgress(days)).currentValue, 1.0);
    });
  });

  group('run activities are matched by local calendar day (A18)', () {
    // The current period of a weekly goal is Monday..Sunday. Runs are stored
    // as local ISO text; the day boundaries must not leak either way.
    final (weekStart, weekEnd) = GoalRepository.currentPeriod(
      GoalPeriod.weekly,
    );
    final lastSunday = addDays(weekStart, -1);
    final nextMonday = addDays(weekEnd, 1);

    Future<void> seedBoundaryRuns() async {
      await _run(db, 'prev-late', '${dateKey(lastSunday)}T23:59:00.000');
      await _run(db, 'first-minute', '${dateKey(weekStart)}T00:01:00.000');
      await _run(db, 'last-minute', '${dateKey(weekEnd)}T23:59:00.000');
      await _run(db, 'next-early', '${dateKey(nextMonday)}T00:01:00.000');
    }

    test('23:59 on the last day counts, 00:01 the next day does not', () async {
      await seedBoundaryRuns();
      final distance = _goal(
        GoalScope.aerobic,
        GoalMetric.distance,
        target: 50,
      );
      final days = _goal(GoalScope.aerobic, GoalMetric.days, target: 7);

      expect((await goals.getProgress(distance)).currentValue, 2 * 5.0);
      expect((await goals.getProgress(days)).currentValue, 2.0);
      final contributors = await goals.getContributingWorkouts(distance);
      expect(contributors.map((c) => c.workoutId).toSet(), {
        'first-minute',
        'last-minute',
      });
    });

    test('history buckets boundary runs into the right week', () async {
      await seedBoundaryRuns();
      final distance = _goal(
        GoalScope.aerobic,
        GoalMetric.distance,
        target: 50,
      );

      final (current, history) = await goals.getProgressWithHistory(
        distance,
        historyCount: 2,
      );

      expect(current.currentValue, 10.0);
      expect(history, hasLength(2));
      expect(history.first.end, lastSunday);
      expect(history.first.value, 5.0);
      expect(history.last.value, 0.0);
    });

    test('a run range query can use the started_at index', () async {
      final rows = await db.rawQuery(
        'EXPLAIN QUERY PLAN SELECT id FROM run_activities '
        "WHERE status = 'completed' AND started_at >= ? AND started_at < ?",
        ['2026-01-01', '2026-01-08'],
      );
      expect(rows.map((r) => r['detail']).join(' '), contains('USING INDEX'));
    });
  });

  group('batched progress', () {
    Future<void> seedHistory() async {
      for (var week = 0; week < 4; week++) {
        final day = addDays(mondayOf(today), -7 * week);
        await _workout(db, 'w$week', dateKey(day));
        await _set(db, 'w$week', 'bench', weight: 100, reps: 10 + week);
        await _run(db, 'r$week', '${dateKey(day)}T07:00:00.000');
      }
    }

    test('history matches per-period results', () async {
      await seedHistory();
      final goal = _goal(GoalScope.anaerobic, GoalMetric.volume, target: 2000);

      final (current, history) = await goals.getProgressWithHistory(
        goal,
        historyCount: 3,
      );

      expect(current.currentValue, 1000.0);
      expect(history.map((r) => r.value), [1100.0, 1200.0, 1300.0]);
      expect(history.map((r) => r.wasCompleted), everyElement(isFalse));
    });

    test(
      'several goals share one query per scope, metric and period',
      () async {
        await seedHistory();
        final list = [
          _goal(GoalScope.anaerobic, GoalMetric.volume, target: 900, id: 'a'),
          _goal(GoalScope.anaerobic, GoalMetric.volume, target: 5000, id: 'b'),
          _goal(GoalScope.anaerobic, GoalMetric.days, target: 3, id: 'c'),
          _goal(GoalScope.aerobic, GoalMetric.distance, target: 30, id: 'd'),
        ];

        sqlLog.clear();
        final batched = await goals.getProgressForGoals(list);
        final reads = sqlLog.reads;

        for (final goal in list) {
          final single = await goals.getProgress(goal);
          expect(batched[goal.id]!.currentValue, single.currentValue);
          expect(batched[goal.id]!.isComplete, single.isComplete);
        }
        expect(batched['a']!.isComplete, isTrue);
        expect(batched['b']!.isComplete, isFalse);
        expect(reads, 3);
      },
    );

    test('suggested target averages the past periods', () async {
      await seedHistory();
      final suggestion = await goals.suggestTarget(
        GoalScope.anaerobic,
        GoalMetric.volume,
        GoalPeriod.weekly,
        multiplier: 1.0,
        periods: 4,
      );

      // Weeks (oldest first): 1300, 1200, 1100 and the current 1000.
      expect(suggestion, 1150.0);
    });
  });
}

Goal _goal(
  GoalScope scope,
  GoalMetric metric, {
  required double target,
  String id = 'goal',
  GoalPeriod period = GoalPeriod.weekly,
}) => Goal(
  id: id,
  title: 'Goal',
  scope: scope,
  metric: metric,
  period: period,
  targetValue: target,
  createdAt: DateTime(2026),
);

Future<void> _exercise(Database db, String id, String categoryId) =>
    db.insert('exercises', {
      'id': id,
      'name': id,
      'category_id': categoryId,
      'created_at': '2026-01-01T00:00:00.000',
    });

var _sequence = 0;

Future<void> _workout(
  Database db,
  String id,
  String date, {
  bool finished = true,
  bool started = true,
}) async {
  await db.insert('workouts', {
    'id': id,
    'date': date,
    'start_time': started ? '${date}T08:00:00.000' : null,
    'end_time': finished ? '${date}T09:00:00.000' : null,
    'created_at': '${date}T07:00:00.000',
  });
}

/// Adds a set of [exerciseId] to [workoutId] (creating the entry lazily).
Future<void> _set(
  Database db,
  String workoutId,
  String exerciseId, {
  double? weight,
  int? reps,
  double? distance,
  int? seconds,
  bool done = true,
  bool warmup = false,
}) async {
  final entryId = 'entry-$workoutId-$exerciseId';
  await db.insert('exercise_entries', {
    'id': entryId,
    'workout_id': workoutId,
    'exercise_id': exerciseId,
    'order_index': 0,
  }, conflictAlgorithm: ConflictAlgorithm.ignore);
  await db.insert('sets', {
    'id': 'set-${_sequence++}',
    'exercise_entry_id': entryId,
    'weight': weight,
    'reps': reps,
    'distance': distance,
    'time_seconds': seconds,
    'is_complete': done ? 1 : 0,
    'is_warmup': warmup ? 1 : 0,
    'order_index': _sequence,
  });
}

Future<void> _run(Database db, String id, String startedAt) =>
    db.insert('run_activities', {
      'id': id,
      'started_at': startedAt,
      'ended_at': startedAt,
      'duration_seconds': 1500,
      'moving_time_seconds': 1500,
      'distance_meters': 5000.0,
      'status': 'completed',
      'created_at': startedAt,
      'updated_at': startedAt,
    });
