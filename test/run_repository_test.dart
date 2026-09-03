import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/database/database_run_route_schema.dart';
import 'package:workout_notes/models/cardio_activity_type.dart';
import 'package:workout_notes/repositories/run_repository.dart';

void main() {
  late Database database;
  late RunRepository repository;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    database = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE run_activities (
              id TEXT PRIMARY KEY,
              activity_type TEXT NOT NULL DEFAULT 'running',
              started_at TEXT NOT NULL,
              ended_at TEXT,
              duration_seconds INTEGER NOT NULL DEFAULT 0,
              moving_time_seconds INTEGER NOT NULL DEFAULT 0,
              distance_meters REAL NOT NULL DEFAULT 0,
              avg_pace_sec_per_km REAL,
              max_pace_sec_per_km REAL,
              calories INTEGER,
              title TEXT,
              notes TEXT,
              rpe REAL,
              feeling_rating INTEGER,
              status TEXT NOT NULL DEFAULT 'completed',
              polyline_summary TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              best_split_pace_sec_per_km REAL,
              best_effort_1k_sec INTEGER,
              best_effort_3k_sec INTEGER,
              best_effort_5k_sec INTEGER,
              best_effort_10k_sec INTEGER,
              best_effort_half_sec INTEGER,
              best_effort_marathon_sec INTEGER,
              efforts_computed INTEGER NOT NULL DEFAULT 0,
              elevation_gain_meters REAL,
              elevation_loss_meters REAL,
              minimum_altitude_meters REAL,
              maximum_altitude_meters REAL,
              gps_accuracy_mean_meters REAL,
              gps_accuracy_good_fraction REAL,
              raw_point_count INTEGER,
              stored_point_count INTEGER,
              route_quality TEXT,
              route_codec_version INTEGER
            )
          ''');
          await db.execute('''
            CREATE TABLE run_track_points (
              id TEXT PRIMARY KEY,
              activity_id TEXT NOT NULL,
              seq INTEGER NOT NULL,
              lat REAL NOT NULL,
              lng REAL NOT NULL,
              altitude REAL,
              accuracy REAL,
              speed REAL,
              recorded_at TEXT NOT NULL,
              FOREIGN KEY (activity_id) REFERENCES run_activities(id) ON DELETE CASCADE
            )
          ''');
          await DatabaseRunRouteSchema.create(db);
        },
      ),
    );
    DatabaseHelper.overrideDatabase = database;
    repository = RunRepository();
  });

  tearDown(() async {
    DatabaseHelper.overrideDatabase = null;
    await database.close();
  });

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
    expect(await database.rawQuery('SELECT COUNT(*) c FROM run_track_points'), [
      containsPair('c', 0),
    ]);
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

  test('migrates legacy point rows transactionally', () async {
    const startedAt = '2025-01-01T10:00:00.000Z';
    await database.insert('run_activities', {
      'id': 'legacy-run',
      'activity_type': 'running',
      'started_at': startedAt,
      'ended_at': '2025-01-01T10:10:00.000Z',
      'duration_seconds': 600,
      'moving_time_seconds': 600,
      'distance_meters': 1000.0,
      'status': 'completed',
      'created_at': startedAt,
      'updated_at': startedAt,
    });
    for (var index = 0; index < 121; index++) {
      await database.insert('run_track_points', {
        'id': 'legacy-$index',
        'activity_id': 'legacy-run',
        'seq': index,
        'lat': -23.5,
        'lng': -46.6 + index * 0.00003,
        'altitude': 700 + index / 20,
        'accuracy': 6.0,
        'speed': 3.0,
        'recorded_at': DateTime.parse(
          startedAt,
        ).add(Duration(seconds: index * 5)).toIso8601String(),
      });
    }

    expect(await repository.migrateLegacyRoutes(limit: 1), 1);
    expect(await database.query('run_track_points'), isEmpty);
    expect(await database.query('run_route_data'), hasLength(1));
    expect(await repository.getTrackPoints('legacy-run'), isNotEmpty);
    expect(await repository.migrateLegacyRoutes(limit: 1), 0);
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
}
