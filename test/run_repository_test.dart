import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:workout_notes/models/cardio_activity_type.dart';
import 'package:workout_notes/models/goal.dart';
import 'package:workout_notes/repositories/goal_repository.dart';
import 'package:workout_notes/repositories/run_repository.dart';
import 'support/test_db.dart';

void main() {
  late Database database;
  late RunRepository repository;

  setUpAll(initSqfliteFfiForTests);

  setUp(() async {
    database = await installTestDb();
    repository = RunRepository();
  });

  tearDown(uninstallTestDb);

  test('imports native spool idempotently and lists completed runs', () async {
    final spool = {
      'activity': {
        'id': 'run-1',
        'status': 'completed',
        'started_at': '2026-08-18T10:00:00.000Z',
        'ended_at': '2026-08-18T10:30:00.000Z',
        'duration_seconds': 1800,
        'moving_time_seconds': 1700,
        'distance_meters': 5000.0,
        'avg_pace_sec_per_km': 340.0,
        'max_pace_sec_per_km': 300.0,
        'calories': 350,
        'title': 'Test Run',
      },
      'points': [
        {
          'id': 'p1',
          'seq': 0,
          'lat': -23.55,
          'lng': -46.63,
          'recorded_at': '2026-08-18T10:00:00.000Z',
        },
        {
          'id': 'p2',
          'seq': 1,
          'lat': -23.56,
          'lng': -46.64,
          'recorded_at': '2026-08-18T10:15:00.000Z',
        },
      ],
    };

    final first = await repository.importNativeSpool(spool);
    final second = await repository.importNativeSpool(spool);
    expect(first.id, 'run-1');
    expect(second.id, first.id);
    expect(await repository.listActivities(), hasLength(1));

    final points = await repository.getTrackPoints('run-1');
    expect(points, hasLength(2));
    expect(points.first.lat, -23.55);
    expect(await database.query('run_route_data'), hasLength(1));

    await repository.updateActivityMeta(
      id: 'run-1',
      title: 'Evening Run',
      notes: 'Felt good',
      rpe: 7,
      feelingRating: 4,
    );
    final updated = await repository.getActivity('run-1');
    expect(updated!.title, 'Evening Run');
    expect(updated.notes, 'Felt good');
    expect(updated.rpe, 7);
    expect(updated.feelingRating, 4);

    await repository.deleteActivity('run-1');
    expect(await repository.listActivities(), isEmpty);
  });

  test('keeps stationary bike sessions out of run-only queries', () async {
    final bike = await repository.importNativeSpool({
      'activity': {
        'id': 'bike-1',
        'activity_type': 'stationary_bike',
        'status': 'completed',
        'started_at': '2026-08-18T10:00:00.000Z',
        'ended_at': '2026-08-18T10:40:00.000Z',
        'duration_seconds': 2400,
        'moving_time_seconds': 2400,
        'distance_meters': 15000.0,
      },
      'points': <Map<String, dynamic>>[],
    });

    expect(bike.activityType, CardioActivityType.stationaryBike);
    expect(bike.avgPaceSecPerKm, isNull);
    expect(bike.averageSpeedKmh, closeTo(22.5, 0.001));
    expect(bike.calories, greaterThan(0));
    expect(await repository.listActivities(), isEmpty);
    expect(await repository.listActivities(activityType: null), hasLength(1));
  });

  test('route maintenance runs at most once per week', () async {
    final now = DateTime.utc(2026, 9, 1, 12);
    expect(await repository.runRouteMaintenance(now: now), isTrue);
    expect(
      await repository.runRouteMaintenance(
        now: now.add(const Duration(days: 3)),
      ),
      isFalse,
    );
    expect(
      await repository.runRouteMaintenance(
        now: now.add(const Duration(days: 8)),
      ),
      isTrue,
    );
  });

  test('archives old compact routes only when explicitly forced', () async {
    await repository.importNativeSpool({
      'activity': {
        'id': 'archive-run',
        'status': 'completed',
        'started_at': '2025-01-01T10:00:00.000Z',
        'ended_at': '2025-01-01T10:10:00.000Z',
        'duration_seconds': 600,
        'moving_time_seconds': 600,
        'distance_meters': 1800.0,
      },
      'points': [
        for (var index = 0; index <= 600; index++)
          {
            'id': 'archive-$index',
            'seq': index,
            'lat': -23.5,
            'lng': -46.6 + index * 0.00003,
            'recorded_at': DateTime.utc(
              2025,
              1,
              1,
              10,
            ).add(Duration(seconds: index)).toIso8601String(),
          },
      ],
    });

    expect(
      await repository.optimizeOldRoutes(
        olderThan: DateTime.utc(2026),
        force: true,
        limit: 1,
      ),
      1,
    );
    final row = (await database.query('run_route_data')).single;
    expect(row['quality'], 'archived');
    expect(
      row['point_count'] as int,
      lessThan(row['original_point_count'] as int),
    );
  });

  group('local day attribution of native (UTC) timestamps', () {
    // 21:30 local imported as a UTC instant: in UTC-3 that is 00:30Z of the
    // next day, which used to be filed under the wrong calendar day.
    Map<String, dynamic> eveningSpool(String id, DateTime localStart) => {
      'activity': {
        'id': id,
        'status': 'completed',
        'started_at': localStart.toUtc().toIso8601String(),
        'ended_at': localStart
            .add(const Duration(minutes: 30))
            .toUtc()
            .toIso8601String(),
        'duration_seconds': 1800,
        'moving_time_seconds': 1800,
        'distance_meters': 5000.0,
      },
      'points': const <Map<String, dynamic>>[],
    };

    test('stores local ISO strings without an offset', () async {
      final start = DateTime(2026, 5, 10, 21, 30);
      final imported = await repository.importNativeSpool(
        eveningSpool('evening', start),
      );
      expect(imported.startedAt, start);
      expect(imported.startedAt.isUtc, isFalse);

      final row = (await database.query(
        'run_activities',
        where: 'id = ?',
        whereArgs: ['evening'],
      )).single;
      expect(row['started_at'], start.toIso8601String());
      expect(row['ended_at'], DateTime(2026, 5, 10, 22).toIso8601String());
      expect(row['started_at'], isNot(endsWith('Z')));
    });

    test('a 21:30 run belongs to that local day in the calendar', () async {
      await repository.importNativeSpool(
        eveningSpool('evening', DateTime(2026, 5, 10, 21, 30)),
      );
      final byDay = await repository.getActivitiesByMonth(2026, 5);
      expect(byDay.keys, ['2026-05-10']);
      final range = await repository.listActivities(
        startedFrom: DateTime(2026, 5, 10),
        startedBefore: DateTime(2026, 5, 11),
      );
      expect(range.map((a) => a.id), ['evening']);
    });

    test('goal contributions use the local day of the run', () async {
      final today = DateTime.now();
      final start = DateTime(today.year, today.month, today.day, 21, 30);
      await repository.importNativeSpool(eveningSpool('evening', start));
      final goal = Goal(
        id: 'g',
        title: 'Cardio',
        scope: GoalScope.aerobic,
        metric: GoalMetric.days,
        period: GoalPeriod.weekly,
        targetValue: 3,
        createdAt: today,
      );
      final contributions = await GoalRepository().getContributingWorkouts(
        goal,
      );
      expect(contributions.map((c) => c.workoutId), contains('evening'));
      final key = start.toIso8601String().substring(0, 10);
      expect(
        contributions.firstWhere((c) => c.workoutId == 'evening').date,
        key,
      );
    });
  });
}
