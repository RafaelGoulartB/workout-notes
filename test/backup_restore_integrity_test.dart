import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/repositories/export_import_repository.dart';
import 'package:workout_notes/repositories/run_repository.dart';

import 'support/test_db.dart';

void main() {
  late Database database;
  late ExportImportRepository repository;

  setUpAll(initSqfliteFfiForTests);

  setUp(() async {
    database = await installTestDb(seedMealTypes: true);
    repository = DatabaseHelper.instance.exportImportRepo;
  });

  tearDown(uninstallTestDb);

  Future<int> count(String table) async => Sqflite.firstIntValue(
    await database.rawQuery('SELECT COUNT(*) FROM $table'),
  )!;

  group('restore', () {
    test('inserts many rows in chunks and counts them', () async {
      final backup = await repository.exportAllData();
      backup['categories'] = [
        for (var i = 0; i < 450; i++)
          {
            'id': 'cat-$i',
            'name': 'Category $i',
            'color': i,
            'order_index': i,
            'energy_system': 'anaerobic',
          },
      ];
      (backup['record_counts'] as Map)['categories'] = 450;

      final inserted = await repository.restoreFromBackup(backup);

      expect(await count('exercise_categories'), 450);
      expect(inserted, greaterThanOrEqualTo(450));
      final last = await database.query(
        'exercise_categories',
        where: 'id = ?',
        whereArgs: ['cat-449'],
      );
      expect(last.single['name'], 'Category 449');
    });

    test('ignores columns that do not exist in any table', () async {
      final backup = await repository.exportAllData();
      backup['categories'] = [
        {
          'id': 'cat-1',
          'name': 'Legs',
          'color': 1,
          'order_index': 0,
          'energy_system': 'anaerobic',
          'not_a_column': 'x',
          // A crafted key must be dropped, never reach the SQL text.
          'id) VALUES (1); DROP TABLE workouts; --': 'x',
        },
      ];
      backup['settings'] = [
        {'key': 'k', 'value': 'v', 'extra': 1},
      ];
      (backup['record_counts'] as Map)['categories'] = 1;
      (backup['record_counts'] as Map)['settings'] = 1;

      await repository.restoreFromBackup(backup);

      expect(
        (await database.query('exercise_categories')).single['name'],
        'Legs',
      );
      final settings = await database.query(
        'app_settings',
        where: 'key = ?',
        whereArgs: ['k'],
      );
      expect(settings.single['value'], 'v');
      // The table the crafted key tried to drop is still there.
      expect(await count('workouts'), 0);
    });

    test('keeps the sleep stage analysis of a monitored night', () async {
      await database.insert('sleep_entries', {
        'id': 'entry',
        'date': '2026-09-01',
        'sleep_minutes': 400,
        'source': 'monitored',
        'created_at': '2026-09-01T07:00:00.000',
      });
      await database.insert('sleep_monitor_sessions', {
        'id': 'night',
        'sleep_entry_id': 'entry',
        'status': 'completed',
        'started_at': '2026-08-31T23:00:00.000Z',
        'utc_offset_start_minutes': 0,
        'sensor_mode': 'audio',
        'algorithm_version': 'audio-features-v5',
        'analysis_status': 'available',
        'snore_minutes': 12,
        'restless_sleep_minutes': 7,
        'awakening_count': 3,
        'sleep_efficiency': 0.88,
        'stage_algorithm_version': 'sleep-wake-bedside-v6',
        'stage_timeline': 'timeline',
        'created_at': '2026-09-01T07:00:00.000',
      });

      final backup = await repository.exportAllData();
      await repository.deleteAllWorkoutData();
      expect(await count('sleep_monitor_sessions'), 0);
      await repository.restoreFromBackup(backup);

      final night = (await database.query('sleep_monitor_sessions')).single;
      expect(night['analysis_status'], 'available');
      expect(night['snore_minutes'], 12);
      expect(night['restless_sleep_minutes'], 7);
      expect(night['awakening_count'], 3);
      expect(night['sleep_efficiency'], 0.88);
      expect(night['stage_algorithm_version'], 'sleep-wake-bedside-v6');
      expect(night['stage_timeline'], 'timeline');
    });

    test(
      'an older backup without analysis columns restores as legacy',
      () async {
        final backup = await repository.exportAllData();
        backup['sleep_monitor_sessions'] = [
          {
            'id': 'old-night',
            'status': 'completed',
            'started_at': '2026-08-31T23:00:00.000Z',
            'utc_offset_start_minutes': 0,
            'sensor_mode': 'audio',
            'algorithm_version': 'audio-v1',
            'created_at': '2026-09-01T07:00:00.000',
          },
        ];
        (backup['record_counts'] as Map)['sleep_monitor_sessions'] = 1;

        await repository.restoreFromBackup(backup);

        final night = (await database.query('sleep_monitor_sessions')).single;
        expect(night['analysis_status'], 'legacy_unavailable');
        expect(night['stage_timeline'], isNull);
      },
    );

    test('a bad row rolls the whole restore back', () async {
      await database.insert('app_settings', {'key': 'keep', 'value': 'me'});
      final backup = await repository.exportAllData();
      backup['categories'] = List.generate(
        300,
        (i) => {
          'id': 'cat-$i',
          'name': 'Category $i',
          'color': i,
          // A NULL in a NOT NULL column fails the 250th row, in a later chunk.
          if (i != 250) 'order_index': i,
          if (i == 250) 'name': null,
        },
      );
      (backup['record_counts'] as Map)['categories'] = 300;

      await expectLater(
        repository.restoreFromBackup(backup),
        throwsA(isA<DatabaseException>()),
      );

      expect(await count('exercise_categories'), 0);
      expect(
        (await database.query('app_settings', where: "key = 'keep'")),
        hasLength(1),
      );
    });
  });

  group('delete all data', () {
    Future<void> seedData() async {
      await database.insert('sleep_entries', {
        'id': 'entry',
        'date': '2026-09-01',
        'sleep_minutes': 400,
        'source': 'manual',
        'created_at': '2026-09-01T07:00:00.000',
      });
      await database.insert('traditional_alarms', {
        'id': 'alarm',
        'hour': 7,
        'minute': 0,
        'created_at': '2026-09-01T07:00:00.000',
        'updated_at': '2026-09-01T07:00:00.000',
      });
    }

    test('wipes workouts and nutrition and reseeds the meal types', () async {
      await seedData();
      await database.insert('meal_types', {
        'id': 'custom',
        'key': 'custom',
        'name': 'Custom',
        'order_index': 9,
        'created_at': '2026-09-01T07:00:00.000',
      });

      await repository.deleteAllData();

      expect(await count('sleep_entries'), 0);
      expect(await count('traditional_alarms'), 0);
      final types = await database.query('meal_types', orderBy: 'order_index');
      expect(types.map((row) => row['key']), [
        'breakfast',
        'lunch',
        'dinner',
        'snacks',
      ]);
    });

    test('nutrition-only deletion also keeps a usable meal catalog', () async {
      await repository.deleteAllNutritionData();

      expect(await count('meal_types'), 4);
    });

    test(
      'is atomic: a failure in the nutrition part keeps the workouts',
      () async {
        await seedData();
        await database.execute('''
        CREATE TRIGGER block_meal_type_delete BEFORE DELETE ON meal_types
        BEGIN SELECT RAISE(ABORT, 'blocked'); END
      ''');

        await expectLater(
          repository.deleteAllData(),
          throwsA(isA<DatabaseException>()),
        );

        expect(await count('sleep_entries'), 1);
        expect(await count('traditional_alarms'), 1);
      },
    );
  });

  group('run activity deletion', () {
    Future<void> seedRun() async {
      await database.execute('PRAGMA foreign_keys = OFF');
      await database.insert('run_activities', {
        'id': 'run',
        'started_at': '2026-09-01T07:00:00.000',
        'created_at': '2026-09-01T07:00:00.000',
        'updated_at': '2026-09-01T07:00:00.000',
      });
      await database.insert('scheduled_runs', {
        'id': 'session',
        'date': '2026-09-01',
        'status': 'completed',
        'run_activity_id': 'run',
        'created_at': '2026-09-01T07:00:00.000',
        'updated_at': '2026-09-01T07:00:00.000',
      });
    }

    test('puts the plan session back to planned and deletes the run', () async {
      await seedRun();

      await RunRepository().deleteActivity('run');

      expect(await count('run_activities'), 0);
      final session = (await database.query('scheduled_runs')).single;
      expect(session['status'], 'planned');
      expect(session['run_activity_id'], isNull);
    });

    test('rolls the session back if the run cannot be deleted', () async {
      await seedRun();
      await database.execute('''
        CREATE TRIGGER block_run_delete BEFORE DELETE ON run_activities
        BEGIN SELECT RAISE(ABORT, 'blocked'); END
      ''');

      await expectLater(
        RunRepository().deleteActivity('run'),
        throwsA(isA<DatabaseException>()),
      );

      final session = (await database.query('scheduled_runs')).single;
      expect(session['status'], 'completed');
      expect(session['run_activity_id'], 'run');
    });
  });
}
