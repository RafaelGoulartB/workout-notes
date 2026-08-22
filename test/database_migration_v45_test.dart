import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:workout_notes/database/database_schema.dart';

/// Version 45 adds the structured running plans (plans → sessions → steps),
/// the dated schedule and the per-step results, plus
/// `run_activities.plan_workout_id`.
///
/// The upgrade must land for devices sitting on any earlier version, must be
/// idempotent (the `CREATE TABLE IF NOT EXISTS` / `ALTER TABLE` pair is
/// best-effort), and must never drop the runs already recorded.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  /// Minimal pre-v45 schema: just enough of `run_activities` for the ALTER and
  /// the FK from `scheduled_runs` to bite.
  Future<Database> openLegacyRunDb({
    required int version,
    bool withPlanColumn = false,
  }) async {
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: version,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, v) async {
          await db.execute('''
            CREATE TABLE run_activities (
              id TEXT PRIMARY KEY,
              started_at TEXT NOT NULL,
              ended_at TEXT,
              duration_seconds INTEGER NOT NULL DEFAULT 0,
              moving_time_seconds INTEGER NOT NULL DEFAULT 0,
              distance_meters REAL NOT NULL DEFAULT 0,
              status TEXT NOT NULL DEFAULT 'completed',
              ${withPlanColumn ? 'plan_workout_id TEXT,' : ''}
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
        },
      ),
    );
    addTearDown(database.close);

    await database.insert('run_activities', {
      'id': 'run-1',
      'started_at': '2026-08-01T06:00:00.000',
      'distance_meters': 10000.0,
      'moving_time_seconds': 2700,
      'status': 'completed',
      'created_at': '2026-08-01T07:00:00.000',
      'updated_at': '2026-08-01T07:00:00.000',
    });
    return database;
  }

  Future<Set<String>> tables(Database database) async {
    final rows = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    return rows.map((row) => row['name'] as String).toSet();
  }

  Future<Set<String>> columns(Database database, String table) async {
    final rows = await database.rawQuery('PRAGMA table_info($table)');
    return rows.map((row) => row['name'] as String).toSet();
  }

  Future<void> expectRunPlanSchema(Database database) async {
    final names = await tables(database);
    expect(
      names,
      containsAll([
        'run_plans',
        'run_plan_workouts',
        'run_workout_steps',
        'scheduled_runs',
        'run_activity_steps',
      ]),
    );
    expect(await columns(database, 'run_activities'), contains('plan_workout_id'));
    // The run recorded before the upgrade survives it.
    final runs = await database.query('run_activities');
    expect(runs, hasLength(1));
    expect(runs.single['distance_meters'], 10000.0);
  }

  test('upgrade from v44 creates the run plan tables', () async {
    final database = await openLegacyRunDb(version: 44);
    await DatabaseSchema.onUpgrade(database, 44, 45);
    await expectRunPlanSchema(database);
  });

  test('upgrade from v43 also lands the run plan tables', () async {
    // A device that skipped a release must still receive the v45 step.
    final database = await openLegacyRunDb(version: 43);
    await DatabaseSchema.onUpgrade(database, 43, 45);
    await expectRunPlanSchema(database);
  });

  test('migration is idempotent when the column already exists', () async {
    final database = await openLegacyRunDb(version: 44, withPlanColumn: true);
    await DatabaseSchema.onUpgrade(database, 44, 45);
    await expectRunPlanSchema(database);
    // Running it twice must not throw either.
    await DatabaseSchema.onUpgrade(database, 44, 45);
    await expectRunPlanSchema(database);
  });

  test('the upgraded schema accepts a full plan → schedule → result chain', () async {
    final database = await openLegacyRunDb(version: 44);
    await DatabaseSchema.onUpgrade(database, 44, 45);

    const now = '2026-08-01T00:00:00.000';
    await database.insert('run_plans', {
      'id': 'plan-1',
      'name': '10 km',
      'goal_kind': '10k',
      'weeks': 12,
      'status': 'active',
      'created_at': now,
      'updated_at': now,
    });
    await database.insert('run_plan_workouts', {
      'id': 'session-1',
      'run_plan_id': 'plan-1',
      'week_index': 0,
      'day_of_week': 2,
      'order_index': 0,
      'kind': 'interval',
      'name': '6x800 m',
      'created_at': now,
    });
    await database.insert('run_workout_steps', {
      'id': 'step-1',
      'run_plan_workout_id': 'session-1',
      'order_index': 0,
      'role': 'work',
      'metric': 'distance',
      'value': 800,
      'repeat_group': 1,
      'repeat_count': 6,
    });
    await database.insert('scheduled_runs', {
      'id': 'scheduled-1',
      'date': '2026-08-04',
      'run_plan_id': 'plan-1',
      'run_plan_workout_id': 'session-1',
      'status': 'completed',
      'run_activity_id': 'run-1',
      'created_at': now,
      'updated_at': now,
    });
    await database.insert('run_activity_steps', {
      'id': 'result-1',
      'run_activity_id': 'run-1',
      'order_index': 0,
      'role': 'work',
      'rep_index': 1,
      'planned_metric': 'distance',
      'planned_value': 800,
      'actual_distance_meters': 800.0,
      'actual_duration_seconds': 188,
    });

    // Deleting the plan cascades sessions, steps and the schedule, but the
    // recorded activity and its step results stay.
    await database.delete('run_plans', where: 'id = ?', whereArgs: ['plan-1']);
    expect(await database.query('run_plan_workouts'), isEmpty);
    expect(await database.query('run_workout_steps'), isEmpty);
    expect(await database.query('scheduled_runs'), isEmpty);
    expect(await database.query('run_activities'), hasLength(1));
    expect(await database.query('run_activity_steps'), hasLength(1));
  });

  test('a fresh database ships the run plan schema from onCreate', () async {
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 45,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: DatabaseSchema.onCreate,
      ),
    );
    addTearDown(database.close);

    final names = await tables(database);
    expect(
      names,
      containsAll([
        'run_plans',
        'run_plan_workouts',
        'run_workout_steps',
        'scheduled_runs',
        'run_activity_steps',
      ]),
    );
    expect(
      await columns(database, 'run_activities'),
      contains('plan_workout_id'),
    );
  });
}
