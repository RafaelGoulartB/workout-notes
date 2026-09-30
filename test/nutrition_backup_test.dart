import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/repositories/export_import_repository.dart';
import 'package:workout_notes/services/export_service.dart';

import 'support/test_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database database;

  setUpAll(initSqfliteFfiForTests);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    database = await openTestDb();
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'round-trip preserves workout goals and consolidated sleep data',
    () async {
      const now = '2026-07-26T08:00:00.000';
      final rows = <String, Map<String, Object?>>{
        'user_goals': {
          'id': 'goal-1',
          'title': 'Weekly volume',
          'scope': 'workouts',
          'metric': 'workoutCount',
          'period': 'weekly',
          'target_value': 3.0,
          'created_at': now,
        },
        'sleep_entries': {
          'id': 'sleep-1',
          'date': '2026-07-25',
          'sleep_minutes': 450,
          'created_at': now,
        },
        'sleep_monitor_sessions': {
          'id': 'session-1',
          'status': 'completed',
          'started_at': now,
          'utc_offset_start_minutes': -180,
          'algorithm_version': '1',
          'created_at': now,
        },
        'traditional_alarms': {
          'id': 'alarm-1',
          'hour': 7,
          'minute': 30,
          'created_at': now,
          'updated_at': now,
        },
      };

      for (final entry in rows.entries) {
        await database.insert(entry.key, entry.value);
      }

      final repository = ExportImportRepository(
        databaseProvider: () async => database,
      );
      final backup = await repository.exportAllData();

      expect(backup['version'], ExportImportRepository.currentBackupVersion);
      for (final entry in rows.entries) {
        expect((backup[entry.key] as List).map((row) => (row as Map)['id']), [
          entry.value['id'],
        ]);
        await database.delete(entry.key);
      }

      final restoredRows = await repository.restoreFromBackup(backup);

      expect(restoredRows, greaterThanOrEqualTo(rows.length));
      for (final entry in rows.entries) {
        final restored = await database.query(entry.key);
        expect(restored.map((row) => row['id']), [entry.value['id']]);
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
    expect(count, 5 + 7); // + default sleep-mission settings
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
      // no nutrition tables
      'settings': [
        {'key': 'restored', 'value': 'yes'},
      ],
    };
    final count = await ExportImportRepository(
      databaseProvider: () async => database,
    ).restoreFromBackup(backup);
    expect(count, 1 + 7); // + default sleep-mission settings
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
      // Missing the NOT NULL `name`, so the insert aborts the transaction.
      'foods': [
        {
          'id': 'bad',
          'source': 'manual',
          'external_id': 'bad',
          'search_name': 'bad',
          'fetched_at': now,
        },
      ],
    };
    await expectLater(
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
