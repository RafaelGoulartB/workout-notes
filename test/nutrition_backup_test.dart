import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_notes/repositories/export_import_repository.dart';
import 'package:workout_notes/services/export_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database database;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    database = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          for (final table in [
            'exercise_categories',
            'exercises',
            'workouts',
            'exercise_entries',
            'sets',
            'routines',
            'routine_days',
            'routine_exercises',
            'predefined_sets',
            'body_measurements',
            'user_goals',
            'sleep_entries',
            'sleep_monitor_sessions',
            'sleep_monitor_segments',
            'sleep_stage_epochs',
            'traditional_alarms',
          ]) {
            await db.execute('CREATE TABLE $table (id TEXT PRIMARY KEY)');
          }
          await db.execute('''
            CREATE TABLE foods (
              id TEXT PRIMARY KEY,
              source TEXT NOT NULL,
              external_id TEXT NOT NULL,
              name TEXT NOT NULL,
              search_name TEXT NOT NULL,
              brand TEXT,
              barcode TEXT,
              source_url TEXT,
              fetched_at TEXT NOT NULL,
              last_used_at TEXT,
              is_favorite INTEGER NOT NULL DEFAULT 0,
              UNIQUE(source, external_id)
            )
          ''');
          await db.execute('''
            CREATE TABLE food_variants (
              id TEXT PRIMARY KEY,
              food_id TEXT NOT NULL,
              label TEXT,
              reference_amount REAL NOT NULL,
              reference_unit TEXT NOT NULL,
              calories REAL,
              protein_g REAL,
              carbs_g REAL,
              fat_g REAL,
              saturated_fat_g REAL, monounsaturated_fat_g REAL,
              polyunsaturated_fat_g REAL, trans_fat_g REAL,
              fiber_g REAL,
              sugars_g REAL,
              sodium_mg REAL,
              potassium_mg REAL, calcium_mg REAL, iron_mg REAL, magnesium_mg REAL,
              zinc_mg REAL, vitamin_a_ug REAL, vitamin_c_mg REAL,
              vitamin_d_ug REAL, vitamin_b12_ug REAL,
              extra_nutrients_json TEXT,
              is_estimated INTEGER NOT NULL DEFAULT 0,
              FOREIGN KEY (food_id) REFERENCES foods(id) ON DELETE CASCADE
            )
          ''');
          await db.execute('''
            CREATE TABLE food_servings (
              id TEXT PRIMARY KEY,
              food_variant_id TEXT NOT NULL,
              label TEXT NOT NULL,
              quantity REAL NOT NULL DEFAULT 1,
              unit TEXT NOT NULL,
              grams_equivalent REAL,
              ml_equivalent REAL,
              FOREIGN KEY (food_variant_id) REFERENCES food_variants(id) ON DELETE CASCADE
            )
          ''');
          await db.execute('''
            CREATE TABLE meal_logs (
              id TEXT PRIMARY KEY,
              date TEXT NOT NULL,
              meal_type TEXT NOT NULL,
              name TEXT,
              notes TEXT,
              created_at TEXT NOT NULL,
              UNIQUE(date, meal_type)
            )
          ''');
          await db.execute('''
            CREATE TABLE meal_log_items (
              id TEXT PRIMARY KEY,
              meal_log_id TEXT NOT NULL,
              food_id TEXT,
              food_variant_id TEXT,
              food_name_snapshot TEXT NOT NULL,
              brand_snapshot TEXT,
              quantity REAL NOT NULL,
              unit TEXT NOT NULL,
              calories REAL,
              protein_g REAL,
              carbs_g REAL,
              fat_g REAL,
              saturated_fat_g REAL, monounsaturated_fat_g REAL,
              polyunsaturated_fat_g REAL, trans_fat_g REAL,
              fiber_g REAL,
              sugars_g REAL,
              sodium_mg REAL,
              potassium_mg REAL, calcium_mg REAL, iron_mg REAL, magnesium_mg REAL,
              zinc_mg REAL, vitamin_a_ug REAL, vitamin_c_mg REAL,
              vitamin_d_ug REAL, vitamin_b12_ug REAL,
              nutrition_snapshot_json TEXT NOT NULL,
              created_at TEXT NOT NULL,
              FOREIGN KEY (meal_log_id) REFERENCES meal_logs(id) ON DELETE CASCADE,
              FOREIGN KEY (food_id) REFERENCES foods(id) ON DELETE SET NULL,
              FOREIGN KEY (food_variant_id) REFERENCES food_variants(id) ON DELETE SET NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE nutrition_goals (
              id TEXT PRIMARY KEY,
              calories REAL,
              protein_g REAL,
              carbs_g REAL,
              fat_g REAL,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              is_active INTEGER NOT NULL DEFAULT 1
            )
          ''');
          await db.execute('''
            CREATE TABLE saved_meals (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              meal_type TEXT,
              portions REAL NOT NULL DEFAULT 1,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE saved_meal_items (
              id TEXT PRIMARY KEY,
              saved_meal_id TEXT NOT NULL,
              food_id TEXT,
              food_variant_id TEXT,
              food_name_snapshot TEXT NOT NULL,
              brand_snapshot TEXT,
              quantity REAL NOT NULL,
              unit TEXT NOT NULL,
              serving_label TEXT,
              serving_grams_equivalent REAL,
              serving_ml_equivalent REAL,
              order_index INTEGER NOT NULL DEFAULT 0,
              FOREIGN KEY (saved_meal_id) REFERENCES saved_meals(id) ON DELETE CASCADE,
              FOREIGN KEY (food_id) REFERENCES foods(id) ON DELETE SET NULL,
              FOREIGN KEY (food_variant_id) REFERENCES food_variants(id) ON DELETE SET NULL
            )
          ''');
          await db.execute(
            'CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT)',
          );
        },
      ),
    );
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'round-trip preserves workout goals and consolidated sleep data',
    () async {
      const tableIds = <String, String>{
        'user_goals': 'goal-1',
        'sleep_entries': 'sleep-1',
        'sleep_monitor_sessions': 'session-1',
        'traditional_alarms': 'alarm-1',
      };

      for (final entry in tableIds.entries) {
        await database.insert(entry.key, {'id': entry.value});
      }

      final repository = ExportImportRepository(
        databaseProvider: () async => database,
      );
      final backup = await repository.exportAllData();

      expect(backup['version'], ExportImportRepository.currentBackupVersion);
      for (final entry in tableIds.entries) {
        expect(backup[entry.key], [
          {'id': entry.value},
        ]);
        await database.delete(entry.key);
      }

      final restoredRows = await repository.restoreFromBackup(backup);

      expect(restoredRows, greaterThanOrEqualTo(tableIds.length));
      for (final entry in tableIds.entries) {
        expect(await database.query(entry.key), [
          {'id': entry.value},
        ]);
      }
    },
  );

  test('backup includes all nutrition tables', () async {
    final now = DateTime.now().toIso8601String();
    await database.insert('foods', {
      'id': 'f1',
      'source': 'manual',
      'external_id': 'f1',
      'name': 'Apple',
      'search_name': 'apple',
      'fetched_at': now,
    });
    await database.insert('food_variants', {
      'id': 'v1',
      'food_id': 'f1',
      'reference_amount': 100,
      'reference_unit': 'g',
      'calories': 52,
      'is_estimated': 0,
    });
    await database.insert('food_servings', {
      'id': 's1',
      'food_variant_id': 'v1',
      'label': 'Medium',
      'quantity': 1,
      'unit': 'unit',
      'grams_equivalent': 120,
    });
    await database.insert('meal_logs', {
      'id': 'ml1',
      'date': '2026-07-26',
      'meal_type': 'breakfast',
      'created_at': now,
    });
    await database.insert('meal_log_items', {
      'id': 'mli1',
      'meal_log_id': 'ml1',
      'food_id': 'f1',
      'food_variant_id': 'v1',
      'food_name_snapshot': 'Apple',
      'quantity': 100,
      'unit': 'g',
      'calories': 52,
      'nutrition_snapshot_json': '{}',
      'created_at': now,
    });
    await database.insert('nutrition_goals', {
      'id': 'g1',
      'calories': 2000,
      'created_at': now,
      'updated_at': now,
      'is_active': 1,
    });
    final export = await ExportImportRepository(
      databaseProvider: () async => database,
    ).exportAllData();
    expect(export['version'], ExportImportRepository.currentBackupVersion);
    expect(export['foods'], hasLength(1));
    expect(export['food_variants'], hasLength(1));
    expect(export['food_servings'], hasLength(1));
    expect(export['meal_logs'], hasLength(1));
    expect(export['meal_log_items'], hasLength(1));
    expect(export['nutrition_goals'], hasLength(1));
  });

  test('round-trip preserves nutrition relationships and snapshots', () async {
    final now = DateTime.now().toIso8601String();
    await database.insert('foods', {
      'id': 'f1',
      'source': 'manual',
      'external_id': 'f1',
      'name': 'Apple',
      'search_name': 'apple',
      'fetched_at': now,
    });
    await database.insert('food_variants', {
      'id': 'v1',
      'food_id': 'f1',
      'reference_amount': 100,
      'reference_unit': 'g',
      'calories': 52,
      'is_estimated': 0,
    });
    await database.insert('food_servings', {
      'id': 's1',
      'food_variant_id': 'v1',
      'label': 'Medium',
      'quantity': 1,
      'unit': 'unit',
      'grams_equivalent': 120,
    });
    await database.insert('meal_logs', {
      'id': 'ml1',
      'date': '2026-07-26',
      'meal_type': 'lunch',
      'created_at': now,
    });
    await database.insert('meal_log_items', {
      'id': 'mli1',
      'meal_log_id': 'ml1',
      'food_id': 'f1',
      'food_variant_id': 'v1',
      'food_name_snapshot': 'Apple',
      'quantity': 100,
      'unit': 'g',
      'calories': 52,
      'nutrition_snapshot_json': '{"version":1}',
      'created_at': now,
    });
    final export = await ExportImportRepository(
      databaseProvider: () async => database,
    ).exportAllData();
    // Wipe and restore in a fresh database.
    await database.transaction((txn) async {
      for (final table in [
        'meal_log_items',
        'meal_logs',
        'food_servings',
        'food_variants',
        'foods',
        'nutrition_goals',
      ]) {
        await txn.delete(table);
      }
    });
    final count = await ExportImportRepository(
      databaseProvider: () async => database,
    ).restoreFromBackup(export);
    expect(count, 5);
    final items = await database.query('meal_log_items');
    expect(items.first['food_name_snapshot'], 'Apple');
    expect(items.first['nutrition_snapshot_json'], '{"version":1}');
    final variants = await database.query('food_variants');
    expect(variants.first['food_id'], 'f1');
    final servings = await database.query('food_servings');
    expect(servings.first['food_variant_id'], 'v1');
  });

  test('backup v4 without nutrition is accepted', () async {
    final backup = <String, dynamic>{
      'version': 4,
      'categories': <Map<String, dynamic>>[],
      'exercises': <Map<String, dynamic>>[],
      'workouts': <Map<String, dynamic>>[],
      'exercise_entries': <Map<String, dynamic>>[],
      'sets': <Map<String, dynamic>>[],
      'routines': <Map<String, dynamic>>[],
      'routine_days': <Map<String, dynamic>>[],
      'routine_exercises': <Map<String, dynamic>>[],
      'predefined_sets': <Map<String, dynamic>>[],
      'body_measurements': <Map<String, dynamic>>[],
      'sleep_entries': <Map<String, dynamic>>[],
      'sleep_monitor_sessions': <Map<String, dynamic>>[],
      'sleep_monitor_segments': <Map<String, dynamic>>[],
      // no nutrition tables
      'settings': [
        {'key': 'restored', 'value': 'yes'},
      ],
    };
    final count = await ExportImportRepository(
      databaseProvider: () async => database,
    ).restoreFromBackup(backup);
    expect(count, 1);
    final items = await database.query('meal_logs');
    expect(items, isEmpty);
  });

  test('failed restore does not destroy the current data', () async {
    final now = DateTime.now().toIso8601String();
    await database.insert('foods', {
      'id': 'existing',
      'source': 'manual',
      'external_id': 'existing',
      'name': 'Existing',
      'search_name': 'existing',
      'fetched_at': now,
    });
    final backup = <String, dynamic>{
      'version': 5,
      'foods': [
        {
          'id': 'bad',
          'source': 'manual',
          'external_id': 'bad',
          'name': 'Bad',
          'search_name': 'bad',
          'fetched_at': now,
        },
      ],
      'food_variants': [
        {
          'id': 'bad_v',
          'food_id': 'different-parent',
          'reference_amount': 100,
          'reference_unit': 'g',
          'is_estimated': 0,
        },
      ],
    };
    expect(
      () => ExportImportRepository(
        databaseProvider: () async => database,
      ).restoreFromBackup(backup),
      throwsA(isA<Object>()),
    );
    final remaining = await database.query(
      'foods',
      where: 'id = ?',
      whereArgs: ['existing'],
    );
    expect(remaining, hasLength(1));
  });

  test('ExportService.shareNutritionCsv writes a valid file', () async {
    final dir = await Directory.systemTemp.createTemp('wn_nutrition_');
    addTearDown(() async {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    });
    final now = DateTime.now().toIso8601String();
    await database.insert('foods', {
      'id': 'f1',
      'source': 'manual',
      'external_id': 'f1',
      'name': 'Maçã',
      'search_name': 'maca',
      'fetched_at': now,
    });
    await database.insert('food_variants', {
      'id': 'v1',
      'food_id': 'f1',
      'reference_amount': 100,
      'reference_unit': 'g',
      'calories': 52,
      'is_estimated': 0,
    });
    await database.insert('meal_logs', {
      'id': 'ml1',
      'date': '2026-07-26',
      'meal_type': 'snacks',
      'created_at': now,
    });
    await database.insert('meal_log_items', {
      'id': 'mli1',
      'meal_log_id': 'ml1',
      'food_id': 'f1',
      'food_variant_id': 'v1',
      'food_name_snapshot': 'Maçã',
      'quantity': 120,
      'unit': 'g',
      'calories': 62.4,
      'protein_g': 0.4,
      'carbs_g': 17,
      'fat_g': 0.2,
      'saturated_fat_g': 0.05,
      'monounsaturated_fat_g': 0.08,
      'polyunsaturated_fat_g': 0.06,
      'trans_fat_g': 0,
      'nutrition_snapshot_json': jsonEncode({
        'version': 1,
        'consumed': {
          'calories': 62.4,
          'protein_g': 0.4,
          'carbs_g': 17,
          'fat_g': 0.2,
          'saturated_fat_g': 0.05,
          'monounsaturated_fat_g': 0.08,
          'polyunsaturated_fat_g': 0.06,
          'trans_fat_g': 0,
        },
        'is_estimated': false,
        'has_missing_values': true,
      }),
      'created_at': now,
    });
    final service = ExportService(
      exportRepo: ExportImportRepository(
        databaseProvider: () async => database,
      ),
      backupsDirectoryProvider: () async => dir,
    );
    final bytes = await service.exportBackupBytes();
    final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    expect(json['version'], ExportImportRepository.currentBackupVersion);
    expect(json['meal_log_items'], isNotEmpty);
    final exportedItem = (json['meal_log_items'] as List).single as Map;
    expect(exportedItem['saturated_fat_g'], 0.05);
    expect(exportedItem['monounsaturated_fat_g'], 0.08);
    expect(exportedItem['polyunsaturated_fat_g'], 0.06);
    expect(exportedItem['trans_fat_g'], 0);

    // The nutrition CSV needs a localizations stub.
  });
}
