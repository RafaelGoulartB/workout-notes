import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/database/database_schema.dart';
import 'package:workout_notes/database/migrations/database_migrations.dart';
import 'package:workout_notes/services/run_route_codec.dart';

import 'support/schema_snapshot.dart';
import 'support/test_db.dart';

const _latest = 56;
const _now = '2026-08-01T08:00:00.000';

/// Upgrade coverage for every step from the v37 migration floor to the current
/// schema. Databases start from a captured v37 schema (see
/// `support/schema_v37_fixture.dart`) holding a small amount of user data.
void main() {
  setUpAll(initSqfliteFfiForTests);

  /// A v37 database with representative rows, upgraded one version at a time
  /// up to [version] (37 means "no upgrade").
  Future<Database> openAt(int version) async {
    final database = await openV37Database();
    addTearDown(database.close);
    await _seedV37(database);
    for (var v = 38; v <= version; v++) {
      await DatabaseSchema.onUpgrade(database, v - 1, v);
    }
    return database;
  }

  Future<Set<String>> tableNames(Database db) async => {
    for (final row in await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    ))
      row['name'] as String,
  };

  Future<Set<String>> indexNames(Database db) async => {
    for (final row in await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'index'",
    ))
      row['name'] as String,
  };

  Future<Set<String>> columnNames(Database db, String table) async => {
    for (final row in await db.rawQuery('PRAGMA table_info($table)'))
      row['name'] as String,
  };

  Future<void> expectUserDataIntact(Database db) async {
    expect(await db.query('workouts'), hasLength(1));
    expect(await db.query('exercise_entries'), hasLength(1));
    expect(await db.query('sets'), hasLength(2));
    expect(await db.query('routine_days'), hasLength(1));
    expect(await db.query('body_measurements'), hasLength(1));
    expect(await db.query('sleep_entries'), hasLength(1));
    expect(await db.query('foods'), hasLength(1));
    expect(await db.query('meal_log_items'), hasLength(1));
    expect(await db.query('periodization_plans'), hasLength(1));
  }

  group('whole upgrade path', () {
    test('v37 to latest yields exactly the fresh-install schema', () async {
      final fresh = await openTestDb();
      addTearDown(fresh.close);
      final upgraded = await openAt(_latest);

      expect(
        schemaDifferences(
          await schemaSnapshot(fresh),
          await schemaSnapshot(upgraded),
        ),
        isEmpty,
      );
    });

    test('v37 to latest in one jump preserves data and cascades', () async {
      final database = await openV37Database();
      addTearDown(database.close);
      await _seedV37(database);

      await DatabaseSchema.onUpgrade(database, 37, _latest);

      await expectUserDataIntact(database);
      // The v40 backfill keeps the existing calorie goal exact.
      final goal = (await database.query('nutrition_goals')).single;
      expect(goal['tdee'], 2000.0);
      expect(goal['adjustment_kind'], 'maintenance');
      // Cascades from the v37 schema still work after the upgrade.
      await database.delete('workouts', where: 'id = ?', whereArgs: ['w1']);
      expect(await database.query('exercise_entries'), isEmpty);
      expect(await database.query('sets'), isEmpty);
      await database.delete('routines');
      expect(await database.query('routine_days'), isEmpty);
    });

    test('upgrading twice changes nothing', () async {
      final database = await openV37Database();
      addTearDown(database.close);
      await _seedV37(database);

      await DatabaseSchema.onUpgrade(database, 37, _latest);
      final once = await schemaSnapshot(database);
      final rowsOnce = (await database.query('sets')).length;
      await DatabaseSchema.onUpgrade(database, 37, _latest);

      expect(schemaDifferences(once, await schemaSnapshot(database)), isEmpty);
      expect(await database.query('sets'), hasLength(rowsOnce));
      await expectUserDataIntact(database);
    });

    test('a database below the floor is rebuilt from scratch', () async {
      final database = await openTestDb();
      addTearDown(database.close);
      await database.execute('CREATE TABLE ancient_leftover (id TEXT)');
      await database.insert('exercise_categories', {
        'id': 'stale',
        'name': 'Stale',
        'color': 1,
      });

      await DatabaseSchema.onUpgrade(database, 30, _latest);

      final fresh = await openTestDb(seed: true);
      addTearDown(fresh.close);
      expect(await tableNames(database), isNot(contains('ancient_leftover')));
      expect(
        schemaDifferences(
          await schemaSnapshot(fresh),
          await schemaSnapshot(database),
        ),
        isEmpty,
      );
      expect(
        await database.query(
          'exercise_categories',
          where: 'id = ?',
          whereArgs: ['stale'],
        ),
        isEmpty,
      );
      expect(await database.query('exercise_categories'), isNotEmpty);
    });
  });

  group('tryExecute', () {
    test('ignores changes that are already applied', () async {
      final database = await openAt(37);
      await DatabaseMigrations.tryExecute(
        database,
        'ALTER TABLE workouts ADD COLUMN comment TEXT',
      );
      await DatabaseMigrations.tryExecute(
        database,
        'CREATE TABLE workouts (id TEXT)',
      );
    });

    test('rethrows every other failure', () async {
      final database = await openAt(37);
      await expectLater(
        DatabaseMigrations.tryExecute(
          database,
          'ALTER TABLE missing_table ADD COLUMN x TEXT',
        ),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        DatabaseMigrations.tryExecute(database, 'NOT VALID SQL'),
        throwsA(isA<DatabaseException>()),
      );
    });
  });

  group('individual versions', () {
    test('v40 adds TDEE and adjustment, backfilling existing goals', () async {
      final before = await openAt(39);
      expect(
        await columnNames(before, 'nutrition_goals'),
        isNot(contains('tdee')),
      );
      await DatabaseSchema.onUpgrade(before, 39, 40);

      expect(
        await columnNames(before, 'nutrition_goals'),
        containsAll(['tdee', 'adjustment_kind', 'adjustment_percent']),
      );
      final goal = (await before.query('nutrition_goals')).single;
      expect(goal['tdee'], 2000.0);
      expect(goal['adjustment_kind'], 'maintenance');
      expect(goal['adjustment_percent'], 0.0);
      expect(goal['calories'], 2000.0);
      await before.insert('nutrition_goals', {
        'id': 'goal-2',
        'calories': 2000.0,
        'tdee': 2500.0,
        'adjustment_kind': 'cut',
        'adjustment_percent': -20.0,
        'created_at': _now,
        'updated_at': _now,
      });
    });

    test('v41 introduces run activities', () async {
      final database = await openAt(40);
      expect(await tableNames(database), isNot(contains('run_activities')));
      await DatabaseSchema.onUpgrade(database, 40, 41);
      expect(
        await tableNames(database),
        containsAll(['run_activities', 'run_track_points']),
      );
      expect(
        await indexNames(database),
        contains('idx_run_activities_started'),
      );
    });

    test('v42 adds the secondary measurement value', () async {
      final database = await openAt(41);
      await DatabaseSchema.onUpgrade(database, 41, 42);
      expect(
        await columnNames(database, 'body_measurements'),
        contains('secondary_value'),
      );
      expect(await database.query('body_measurements'), hasLength(1));
    });

    test('v43 adds cached run efforts', () async {
      final database = await openAt(42);
      await DatabaseSchema.onUpgrade(database, 42, 43);
      expect(
        await columnNames(database, 'run_activities'),
        containsAll(['best_effort_5k_sec', 'efforts_computed']),
      );
    });

    test(
      'v44 adds the composite workout, set and measurement indexes',
      () async {
        final database = await openAt(43);
        await DatabaseSchema.onUpgrade(database, 43, 44);
        expect(
          await indexNames(database),
          containsAll([
            'idx_workouts_date_end',
            'idx_sets_entry_state',
            'idx_measurements_type_date',
          ]),
        );
      },
    );

    test('v45 adds structured running plans', () async {
      final database = await openAt(44);
      await DatabaseSchema.onUpgrade(database, 44, 45);
      expect(
        await tableNames(database),
        containsAll([
          'run_plans',
          'run_plan_workouts',
          'run_workout_steps',
          'scheduled_runs',
          'run_activity_steps',
        ]),
      );
      expect(
        await columnNames(database, 'run_activities'),
        contains('plan_workout_id'),
      );
    });

    test('v46 and v47 add plan activation and completion count', () async {
      final database = await openAt(45);
      await DatabaseSchema.onUpgrade(database, 45, 46);
      await DatabaseSchema.onUpgrade(database, 46, 47);
      expect(
        await columnNames(database, 'run_plans'),
        containsAll(['activated_at', 'completion_count']),
      );
    });

    test('v48 adds the post-run review columns', () async {
      final database = await openAt(47);
      await DatabaseSchema.onUpgrade(database, 47, 48);
      expect(
        await columnNames(database, 'run_activities'),
        containsAll(['rpe', 'feeling_rating']),
      );
    });

    test('v49 adds the activity type, defaulting existing runs', () async {
      final database = await openAt(48);
      await database.insert('run_activities', _runActivity('early-run'));
      await DatabaseSchema.onUpgrade(database, 48, 49);
      expect(
        (await database.query('run_activities')).single['activity_type'],
        'running',
      );
      expect(
        await indexNames(database),
        contains('idx_run_activities_type_started'),
      );
    });

    test('v50 adds AI thread summaries', () async {
      final database = await openAt(49);
      await DatabaseSchema.onUpgrade(database, 49, 50);
      expect(await tableNames(database), contains('ai_chat_thread_summaries'));
    });

    test('v51 adds compact routes and activity route metadata', () async {
      final database = await openAt(50);
      await database.insert('run_activities', _runActivity('run-1'));
      await DatabaseSchema.onUpgrade(database, 50, 51);
      expect(
        await tableNames(database),
        containsAll(['run_route_data', 'run_splits']),
      );
      expect(
        await columnNames(database, 'run_activities'),
        containsAll(['elevation_gain_meters', 'route_codec_version']),
      );
      expect(await database.query('run_activities'), hasLength(1));
    });

    test('v52 adds plan config and the adaptation log', () async {
      final database = await openAt(51);
      await database.insert('run_plans', _runPlan('legacy-plan'));
      await DatabaseSchema.onUpgrade(database, 51, 52);
      expect(
        await columnNames(database, 'run_plans'),
        containsAll(['template_key', 'config_json']),
      );
      expect(await tableNames(database), contains('run_plan_adaptations'));
      final plan = (await database.query('run_plans')).single;
      expect(plan['id'], 'legacy-plan');
      expect(plan['config_json'], isNull);
    });

    test('v53 adds gear, laps and the activity gear link', () async {
      final database = await openAt(52);
      await database.insert('run_activities', _runActivity('run-1'));
      await DatabaseSchema.onUpgrade(database, 52, 53);
      expect(await tableNames(database), containsAll(['run_gear', 'run_laps']));
      expect(
        await columnNames(database, 'run_activities'),
        contains('gear_id'),
      );
      expect(await indexNames(database), contains('idx_run_activities_gear'));

      // Laps are deleted with their activity.
      await database.insert('run_laps', {
        'activity_id': 'run-1',
        'lap_index': 1,
        'start_distance_meters': 0.0,
        'distance_meters': 1000.0,
        'duration_seconds': 300,
      });
      await database.delete('run_activities');
      expect(await database.query('run_laps'), isEmpty);
    });

    test('v54 links workouts to the routine day they trained', () async {
      final database = await openAt(53);
      await DatabaseSchema.onUpgrade(database, 53, 54);
      expect(
        await columnNames(database, 'workouts'),
        contains('routine_day_id'),
      );
      expect(
        (await database.query('workouts')).single['routine_day_id'],
        isNull,
      );
      await database.update('workouts', {'routine_day_id': 'day-1'});
      expect(
        (await database.query('workouts')).single['routine_day_id'],
        'day-1',
      );
    });

    test('v55 adds medications with a cascading dose log', () async {
      final database = await openAt(54);
      await DatabaseSchema.onUpgrade(database, 54, 55);
      expect(
        await tableNames(database),
        containsAll(['medications', 'medication_doses']),
      );
      await database.insert('medications', {
        'id': 'med-1',
        'name': 'Vitamin D',
        'times_json': '["08:00"]',
        'weekdays_json': '[1,2,3,4,5,6,7]',
        'created_at': _now,
        'updated_at': _now,
      });
      await database.insert('medication_doses', {
        'id': 'dose-1',
        'medication_id': 'med-1',
        'dose_key': '2026-08-01T08:00',
        'scheduled_at': _now,
        'status': 'taken',
        'recorded_at': _now,
      });
      await expectLater(
        database.insert('medication_doses', {
          'id': 'dose-2',
          'medication_id': 'med-1',
          'dose_key': '2026-08-01T08:00',
          'scheduled_at': _now,
          'status': 'skipped',
          'recorded_at': _now,
        }),
        throwsA(isA<DatabaseException>()),
      );
      await database.delete('medications');
      expect(await database.query('medication_doses'), isEmpty);
    });
  });

  group('v56', () {
    test('drops the dead tables and redundant indexes', () async {
      final before = await openAt(55);
      expect(
        await tableNames(before),
        containsAll([
          'sleep_monitor_segments',
          'sleep_stage_epochs',
          'phase_routine_links',
          'run_track_points',
        ]),
      );
      expect(
        await indexNames(before),
        containsAll([
          'idx_sleep_entries_date',
          'idx_workouts_date',
          'idx_sets_entry',
          'idx_measurements_type',
          'idx_foods_search_name',
          'idx_foods_brand',
        ]),
      );

      await DatabaseSchema.onUpgrade(before, 55, 56);

      final tables = await tableNames(before);
      for (final dead in [
        'sleep_monitor_segments',
        'sleep_stage_epochs',
        'phase_routine_links',
        'run_track_points',
      ]) {
        expect(tables, isNot(contains(dead)));
      }
      final indexes = await indexNames(before);
      for (final redundant in [
        'idx_sleep_entries_date',
        'idx_workouts_date',
        'idx_sets_entry',
        'idx_measurements_type',
        'idx_foods_search_name',
        'idx_foods_brand',
        'idx_sleep_stage_epochs_session_started',
        'idx_sleep_monitor_segments_session_started',
        'idx_phase_routine_links_dates',
        'idx_run_track_points_activity_seq',
      ]) {
        expect(indexes, isNot(contains(redundant)));
      }
      await expectUserDataIntact(before);
    });

    test('adds the foreign key lookup indexes', () async {
      final database = await openAt(55);
      await DatabaseSchema.onUpgrade(database, 55, 56);
      expect(
        await indexNames(database),
        containsAll([
          'idx_exercise_entries_exercise',
          'idx_workouts_routine',
          'idx_workouts_routine_day',
          'idx_meal_log_items_food',
          'idx_meal_log_items_variant',
          'idx_routine_days_routine',
          'idx_routine_exercises_day',
          'idx_predefined_sets_exercise',
        ]),
      );
    });

    test(
      'lookups use the new indexes and never needed the dropped ones',
      () async {
        final database = await openAt(_latest);
        Future<String> plan(String sql, [List<Object?> args = const []]) async {
          final rows = await database.rawQuery('EXPLAIN QUERY PLAN $sql', args);
          return rows.map((row) => row['detail']).join(' | ');
        }

        expect(
          await plan('SELECT * FROM exercise_entries WHERE exercise_id = ?', [
            'e',
          ]),
          contains('idx_exercise_entries_exercise'),
        );
        expect(
          await plan('SELECT * FROM workouts WHERE routine_id = ?', ['r']),
          contains('idx_workouts_routine'),
        );
        expect(
          await plan('SELECT * FROM workouts WHERE routine_day_id = ?', ['d']),
          contains('idx_workouts_routine_day'),
        );
        expect(
          await plan('SELECT * FROM meal_log_items WHERE food_id = ?', ['f']),
          contains('idx_meal_log_items_food'),
        );
        expect(
          await plan('SELECT * FROM meal_log_items WHERE food_variant_id = ?', [
            'v',
          ]),
          contains('idx_meal_log_items_variant'),
        );
        expect(
          await plan('SELECT * FROM routine_days WHERE routine_id = ?', ['r']),
          contains('idx_routine_days_routine'),
        );
        expect(
          await plan(
            'SELECT * FROM routine_exercises WHERE routine_day_id = ?',
            ['d'],
          ),
          contains('idx_routine_exercises_day'),
        );
        expect(
          await plan(
            'SELECT * FROM predefined_sets WHERE routine_exercise_id = ?',
            ['x'],
          ),
          contains('idx_predefined_sets_exercise'),
        );
        // Queries the dropped indexes used to serve keep an index.
        expect(
          await plan('SELECT * FROM sleep_entries WHERE date = ?', ['d']),
          contains('USING INDEX'),
        );
        expect(
          await plan('SELECT * FROM workouts WHERE date = ?', ['d']),
          contains('idx_workouts_date_end'),
        );
        expect(
          await plan('SELECT * FROM sets WHERE exercise_entry_id = ?', ['x']),
          contains('idx_sets_entry_state'),
        );
        expect(
          await plan('SELECT * FROM body_measurements WHERE type = ?', [
            'weight',
          ]),
          contains('idx_measurements_type_date'),
        );
      },
    );

    test(
      'compacts legacy point rows into routes before dropping them',
      () async {
        final database = await openAt(55);
        const startedAt = '2025-01-01T10:00:00.000Z';
        await database.insert('run_activities', {
          ..._runActivity('legacy-run'),
          'started_at': startedAt,
        });
        await database.insert('run_activities', _runActivity('no-points-run'));
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

        await DatabaseSchema.onUpgrade(database, 55, 56);

        expect(await tableNames(database), isNot(contains('run_track_points')));
        final routes = await database.query('run_route_data');
        expect(routes, hasLength(1));
        expect(routes.single['activity_id'], 'legacy-run');
        final decoded = RunRouteCodec.decode(
          activityId: 'legacy-run',
          payload: Uint8List.fromList(
            (routes.single['payload']! as List).cast<int>(),
          ),
          expectedChecksum: routes.single['checksum']! as int,
        );
        expect(decoded.length, greaterThanOrEqualTo(2));
        final activity = (await database.query(
          'run_activities',
          where: 'id = ?',
          whereArgs: ['legacy-run'],
        )).single;
        expect(activity['efforts_computed'], 1);
        expect(activity['stored_point_count'], routes.single['point_count']);
        expect(activity['route_codec_version'], RunRouteCodec.version);
        // Activities without legacy points are untouched.
        expect(await database.query('run_activities'), hasLength(2));
      },
    );
  });
}

Map<String, Object?> _runActivity(String id) => {
  'id': id,
  'started_at': '2026-08-01T06:00:00.000',
  'distance_meters': 10000.0,
  'moving_time_seconds': 2700,
  'status': 'completed',
  'created_at': _now,
  'updated_at': _now,
};

Map<String, Object?> _runPlan(String id) => {
  'id': id,
  'name': 'Legacy plan',
  'created_at': _now,
  'updated_at': _now,
};

/// Representative user data for a v37 database. Column names follow the v37
/// schema, so this must only use columns that existed then.
Future<void> _seedV37(Database db) async {
  await db.insert('exercise_categories', {
    'id': 'chest',
    'name': 'Chest',
    'color': 1,
    'order_index': 0,
    'energy_system': 'anaerobic',
  });
  await db.insert('exercises', {
    'id': 'bench',
    'name': 'Bench press',
    'category_id': 'chest',
    'type': 'weightReps',
    'created_at': _now,
  });
  await db.insert('workouts', {
    'id': 'w1',
    'date': '2026-08-01',
    'start_time': _now,
    'end_time': _now,
    'created_at': _now,
  });
  await db.insert('exercise_entries', {
    'id': 'entry-1',
    'workout_id': 'w1',
    'exercise_id': 'bench',
    'order_index': 0,
  });
  for (var i = 0; i < 2; i++) {
    await db.insert('sets', {
      'id': 'set-$i',
      'exercise_entry_id': 'entry-1',
      'weight': 100.0,
      'reps': 5,
      'is_complete': 1,
      'order_index': i,
    });
  }
  await db.insert('routines', {
    'id': 'routine-1',
    'name': 'Push',
    'created_at': _now,
  });
  await db.insert('routine_days', {
    'id': 'day-1',
    'routine_id': 'routine-1',
    'name': 'Day A',
    'order_index': 0,
  });
  await db.insert('body_measurements', {
    'id': 'bm-1',
    'type': 'weight',
    'value': 80.0,
    'unit': 'kg',
    'date': '2026-08-01',
    'created_at': _now,
  });
  await db.insert('sleep_entries', {
    'id': 'sleep-1',
    'date': '2026-07-31',
    'sleep_minutes': 450,
    'created_at': _now,
  });
  await db.insert('foods', {
    'id': 'food-1',
    'source': 'manual',
    'external_id': 'food-1',
    'name': 'Oats',
    'search_name': 'oats',
    'fetched_at': _now,
  });
  await db.insert('meal_logs', {
    'id': 'log-1',
    'date': '2026-08-01',
    'meal_type': 'breakfast',
    'created_at': _now,
  });
  await db.insert('meal_log_items', {
    'id': 'item-1',
    'meal_log_id': 'log-1',
    'food_id': 'food-1',
    'food_name_snapshot': 'Oats',
    'quantity': 50.0,
    'unit': 'g',
    'nutrition_snapshot_json': '{}',
    'created_at': _now,
  });
  await db.insert('nutrition_goals', {
    'id': 'goal-1',
    'calories': 2000.0,
    'protein_g': 150.0,
    'carbs_g': 200.0,
    'fat_g': 60.0,
    'created_at': _now,
    'updated_at': _now,
  });
  await db.insert('periodization_plans', {
    'id': 'plan-1',
    'name': 'Cut',
    'start_date': '2026-08-03',
    'end_date': '2026-09-27',
    'created_at': _now,
    'updated_at': _now,
  });
  await db.insert('periodization_phases', {
    'id': 'phase-1',
    'plan_id': 'plan-1',
    'name': 'Phase 1',
    'color': 1,
    'start_date': '2026-08-03',
    'end_date': '2026-08-30',
    'created_at': _now,
    'updated_at': _now,
  });
  // Rows of a table v56 drops: they must not block the upgrade.
  await db.insert('phase_routine_links', {
    'id': 'link-1',
    'phase_id': 'phase-1',
    'routine_id': 'routine-1',
    'starts_on': '2026-08-03',
    'ends_on': '2026-08-30',
    'created_at': _now,
  });
}
