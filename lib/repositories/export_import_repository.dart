import 'dart:convert';
import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';
import 'base_repository.dart';
import 'package:workout_notes/services/run_route_codec.dart';

/// Repository for data export and import operations.
///
/// Export produces a JSON map with every table's rows plus a version
/// marker. Import performs a full restore: it clears all tables, then
/// inserts the backup rows inside a single transaction so the database
/// ends up in an exact copy of the exported state.
class ExportImportRepository extends BaseRepository {
  static const int currentBackupVersion = 19;
  static const int minimumSupportedBackupVersion = 2;
  static const String backupType = 'workout_notes_full_backup';

  /// Collections that must be present in backups produced by this version.
  /// Keeping the manifest explicit prevents a newly-created but truncated JSON
  /// object from being interpreted as an intentionally empty database.
  static const List<String> currentCollectionKeys = [
    'categories',
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
    'foods',
    'food_variants',
    'food_servings',
    'meal_types',
    'meal_logs',
    'meal_log_items',
    'nutrition_goals',
    'saved_meals',
    'saved_meal_items',
    'traditional_alarms',
    'periodization_plans',
    'periodization_phases',
    'phase_targets',
    'periodization_checkins',
    'run_activities',
    'run_route_data',
    'run_splits',
    'run_plans',
    'run_plan_workouts',
    'run_workout_steps',
    'scheduled_runs',
    'run_activity_steps',
    'run_plan_adaptations',
    'run_gear',
    'run_laps',
    'medications',
    'medication_doses',
    'settings',
  ];

  /// Backup version that first exported each collection added after the
  /// strict v15 manifest. Older backups legitimately lack these keys.
  static const Map<String, int> _collectionIntroducedIn = {
    'run_route_data': 16,
    'run_splits': 16,
    'run_plan_adaptations': 17,
    'run_gear': 18,
    'run_laps': 18,
    'medications': 19,
    'medication_doses': 19,
  };

  /// Collections a backup of [version] is expected to carry.
  static List<String> collectionKeysForVersion(int version) =>
      currentCollectionKeys
          .where((key) => (_collectionIntroducedIn[key] ?? 0) <= version)
          .toList(growable: false);

  final Future<Database> Function()? _databaseProvider;

  ExportImportRepository({this._databaseProvider});

  @override
  Future<Database> get db => _databaseProvider?.call() ?? super.db;

  // ------------------------------------------------------------------
  // Export
  // ------------------------------------------------------------------

  /// Exports all user-modifiable data as a JSON-serialisable map.
  Future<Map<String, dynamic>> exportAllData() async {
    final db = await this.db;
    final nutrition = await _exportNutrition(db);
    final data = <String, dynamic>{
      'backup_type': backupType,
      'version': currentBackupVersion,
      'exported_at': DateTime.now().toIso8601String(),
      'categories': await db.query('exercise_categories'),
      'exercises': await db.query('exercises'),
      'workouts': await db.query('workouts'),
      'exercise_entries': await db.query('exercise_entries'),
      'sets': await db.query('sets'),
      'routines': await db.query('routines'),
      'routine_days': await db.query('routine_days'),
      'routine_exercises': await db.query('routine_exercises'),
      'predefined_sets': await db.query('predefined_sets'),
      'body_measurements': await db.query('body_measurements'),
      'user_goals': await db.query('user_goals'),
      'sleep_entries': await db.query('sleep_entries'),
      'sleep_monitor_sessions': await _exportSleepSessions(db),
      'foods': nutrition['foods'],
      'food_variants': nutrition['food_variants'],
      'food_servings': nutrition['food_servings'],
      'meal_types': await db.query('meal_types'),
      'meal_logs': await db.query('meal_logs'),
      'meal_log_items': await db.query('meal_log_items'),
      'nutrition_goals': await db.query('nutrition_goals'),
      'saved_meals': await db.query('saved_meals'),
      'saved_meal_items': await db.query('saved_meal_items'),
      'traditional_alarms': await db.query('traditional_alarms'),
      'periodization_plans': await db.query('periodization_plans'),
      'periodization_phases': await db.query('periodization_phases'),
      'phase_targets': await db.query('phase_targets'),
      'periodization_checkins': await db.query('periodization_checkins'),
      // Runs and running plans (backup v14). Activities and track points are
      // included because `scheduled_runs` and `run_activity_steps` reference
      // them — restoring the plans without them would break the FKs.
      'run_activities': await db.query('run_activities'),
      'run_route_data': await _exportRunRoutes(db),
      'run_splits': await db.query('run_splits'),
      'run_plans': await db.query('run_plans'),
      'run_plan_workouts': await db.query('run_plan_workouts'),
      'run_workout_steps': await db.query('run_workout_steps'),
      'scheduled_runs': await db.query('scheduled_runs'),
      'run_activity_steps': await db.query('run_activity_steps'),
      'run_plan_adaptations': await db.query('run_plan_adaptations'),
      // Shoes and manual laps (backup v18).
      'run_gear': await db.query('run_gear'),
      'run_laps': await db.query('run_laps'),
      // Medication reminders and the dose log (backup v19).
      'medications': await db.query('medications'),
      'medication_doses': await db.query('medication_doses'),
      'settings': await db.query('app_settings'),
      // Platform preferences and portable file bytes are filled by
      // ExportService. Empty defaults keep this envelope valid for repository
      // callers and database-only tests.
      'preferences': const <String, Object>{},
      'preference_count': 0,
      'media_files': const <Map<String, Object?>>[],
      'media_count': 0,
      'excluded_data': const [
        'api_tokens',
        'runtime_permissions',
        'active_background_sessions',
        'ai_chat_threads',
        'ai_chat_messages',
        'ai_chat_thread_summaries',
        'ai_routine_proposals',
        'unused_remote_food_cache',
      ],
    };
    data['record_counts'] = {
      for (final key in currentCollectionKeys) key: (data[key] as List).length,
    };
    return data;
  }

  // ------------------------------------------------------------------
  // Full restore (clear + import)
  // ------------------------------------------------------------------

  /// Completely replaces all data with the contents of [data].
  ///
  /// This is a destructive operation – existing rows are deleted before
  /// the backup rows are inserted. The whole process runs inside a
  /// single transaction so that an error rolls back everything.
  ///
  /// Returns the total number of rows inserted.
  Future<int> restoreFromBackup(Map<String, dynamic> data) async {
    validateBackup(data);
    final db = await this.db;
    int totalRows = 0;

    await db.transaction((txn) async {
      // Checked at commit instead of per insert, after dangling references
      // left by older app versions are resolved (see _resolveDanglingRefs).
      await txn.execute('PRAGMA defer_foreign_keys = ON');

      // 1. Clear all tables (order matters because of FKs)
      for (final table in [
        'ai_routine_proposals',
        'ai_chat_thread_summaries',
        'ai_chat_messages',
        'ai_chat_threads',
        'periodization_checkins',
        'phase_targets',
        'periodization_phases',
        'periodization_plans',
        // Children before parents: schedule and step rows reference both the
        // plan sessions and the recorded activities.
        'run_activity_steps',
        'scheduled_runs',
        'run_workout_steps',
        'run_plan_workouts',
        'run_plan_adaptations',
        'run_plans',
        'run_laps',
        'run_splits',
        'run_route_data',
        'run_activities',
        'run_gear',
      ]) {
        await txn.delete(table);
      }
      await txn.delete('predefined_sets');
      await txn.delete('routine_exercises');
      await txn.delete('routine_days');
      await txn.delete('routines');
      await txn.delete('sets');
      await txn.delete('exercise_entries');
      await txn.delete('workouts');
      await txn.delete('body_measurements');
      await txn.delete('user_goals');
      await txn.delete('sleep_monitor_sessions');
      await txn.delete('sleep_entries');
      for (final table in [
        'meal_log_items',
        'meal_logs',
        'meal_types',
        'food_servings',
        'food_variants',
        'foods',
        'nutrition_goals',
        'saved_meal_items',
        'saved_meals',
      ]) {
        await txn.delete(table);
      }
      await txn.delete('traditional_alarms');
      for (final table in ['medication_doses', 'medications']) {
        await txn.delete(table);
      }
      await txn.delete('exercises');
      await txn.delete('exercise_categories');
      await txn.delete('app_settings');

      // 2. Insert backup rows in FK-safe order
      totalRows += await _insertAll(
        txn,
        'exercise_categories',
        data['categories'],
      );
      totalRows += await _insertAll(txn, 'exercises', data['exercises']);
      totalRows += await _insertAll(txn, 'workouts', data['workouts']);
      totalRows += await _insertAll(
        txn,
        'exercise_entries',
        data['exercise_entries'],
      );
      totalRows += await _insertAll(txn, 'sets', data['sets']);
      totalRows += await _insertAll(txn, 'routines', data['routines']);
      totalRows += await _insertAll(txn, 'routine_days', data['routine_days']);
      totalRows += await _insertAll(
        txn,
        'routine_exercises',
        data['routine_exercises'],
      );
      totalRows += await _insertAll(
        txn,
        'predefined_sets',
        data['predefined_sets'],
      );
      for (final table in [
        'periodization_plans',
        'periodization_phases',
        'phase_targets',
        'periodization_checkins',
        // Parents before children, mirroring the clear order above.
        'run_gear',
        'run_activities',
      ]) {
        totalRows += await _insertAll(txn, table, data[table]);
      }
      totalRows += await _insertRunRoutes(txn, data['run_route_data']);
      totalRows += await _insertAll(txn, 'run_splits', data['run_splits']);
      totalRows += await _insertAll(txn, 'run_laps', data['run_laps']);
      for (final table in [
        'run_plans',
        'run_plan_workouts',
        'run_workout_steps',
        'scheduled_runs',
        'run_activity_steps',
        'run_plan_adaptations',
      ]) {
        totalRows += await _insertAll(txn, table, data[table]);
      }
      totalRows += await _insertAll(
        txn,
        'body_measurements',
        data['body_measurements'],
      );
      totalRows += await _insertAll(txn, 'user_goals', data['user_goals']);
      totalRows += await _insertAll(
        txn,
        'sleep_entries',
        data['sleep_entries'],
      );
      totalRows += await _insertSleepSessions(
        txn,
        data['sleep_monitor_sessions'],
      );
      for (final table in [
        'foods',
        'food_variants',
        'food_servings',
        'meal_types',
        'meal_logs',
        'meal_log_items',
        'nutrition_goals',
        'saved_meals',
        'saved_meal_items',
      ]) {
        totalRows += await _insertAll(txn, table, data[table]);
      }
      totalRows += await _insertAll(
        txn,
        'traditional_alarms',
        data['traditional_alarms'],
      );
      for (final table in ['medications', 'medication_doses']) {
        totalRows += await _insertAll(txn, table, data[table]);
      }
      totalRows += await _insertAll(txn, 'app_settings', data['settings']);
      // Backups before v6 had no mission settings; add the safe disabled
      // defaults for any that are missing.
      totalRows += await _insertMissingSleepSettings(txn);
      totalRows -= await _resolveDanglingRefs(txn);
    });

    return totalRows;
  }

  /// Older app versions could leave child rows whose parent was already gone
  /// (e.g. exercise entries of a deleted workout). The UI never reached them,
  /// but with foreign keys enforced they would abort the whole restore. Each
  /// dangling reference is resolved as its key's ON DELETE action would have:
  /// SET NULL keys are cleared, every other orphan row is deleted.
  ///
  /// Returns the number of rows deleted.
  static Future<int> _resolveDanglingRefs(Transaction txn) async {
    var deleted = 0;
    // Deleting an orphan can orphan its own children (entry -> sets) when
    // cascades are off, so repeat until the check is clean. Anything left
    // after the cap fails the commit as a regular FK violation.
    for (var pass = 0; pass < 8; pass++) {
      final violations = await txn.rawQuery('PRAGMA foreign_key_check');
      if (violations.isEmpty) break;
      final keysByTable = <String, Set<Object?>>{};
      for (final row in violations) {
        keysByTable
            .putIfAbsent(row['table'] as String, () => {})
            .add(row['fkid']);
      }
      for (final MapEntry(key: table, value: keyIds) in keysByTable.entries) {
        // Identifiers come from SQLite's own catalog, never from the backup.
        final keys = await txn.rawQuery('PRAGMA foreign_key_list("$table")');
        for (final key in keys.where((k) => keyIds.contains(k['id']))) {
          final from = key['from'];
          final orphan =
              '"$from" IS NOT NULL AND "$from" NOT IN '
              '(SELECT "${key['to']}" FROM "${key['table']}")';
          if (key['on_delete'] == 'SET NULL') {
            await txn.rawUpdate(
              'UPDATE "$table" SET "$from" = NULL WHERE $orphan',
            );
          } else {
            deleted += await txn.rawDelete(
              'DELETE FROM "$table" WHERE $orphan',
            );
          }
        }
      }
    }
    return deleted;
  }

  /// Validates the envelope and all row collections before any data is
  /// deleted. Version 15 introduced a strict manifest; older backups retain
  /// their historical optional-table compatibility.
  static void validateBackup(Map<String, dynamic> data) {
    final version = data['version'];
    if (version is! int ||
        version < minimumSupportedBackupVersion ||
        version > currentBackupVersion) {
      throw FormatException('Unsupported backup version: $version.');
    }

    if (version >= 15) {
      if (data['backup_type'] != backupType) {
        throw const FormatException('This is not a Workout Notes backup.');
      }
      final counts = data['record_counts'];
      if (counts is! Map) {
        throw const FormatException('Backup record counts are missing.');
      }
      for (final key in collectionKeysForVersion(version)) {
        final rows = data[key];
        if (rows is! List) {
          throw FormatException('Backup collection "$key" is missing.');
        }
        if (counts[key] is! int || counts[key] != rows.length) {
          throw FormatException('Backup collection "$key" is incomplete.');
        }
      }
    }

    for (final key in collectionKeysForVersion(version)) {
      final rows = data[key];
      if (rows == null) continue;
      if (rows is! List || rows.any((row) => row is! Map)) {
        throw FormatException('Invalid rows in backup collection "$key".');
      }
    }
  }

  /// Preserves the monitored-night record and alarm metadata without carrying
  /// the low-priority sleep-stage analysis. The database defaults the restored
  /// session to `legacy_unavailable`, matching the intentionally absent epochs.
  static Future<List<Map<String, Object?>>> _exportSleepSessions(
    Database database,
  ) async {
    final rows = await database.query('sleep_monitor_sessions');
    const stageAnalysisColumns = {
      'analysis_status',
      'sleep_onset_at',
      'final_wake_at',
      'sleep_latency_minutes',
      'awake_minutes',
      'sleeping_minutes',
      'deep_sleep_minutes',
      'unknown_minutes',
      'awakening_count',
      'sleep_efficiency',
      'stage_confidence',
      'stage_algorithm_version',
    };
    return rows
        .map((raw) {
          final row = Map<String, Object?>.from(raw);
          for (final column in stageAnalysisColumns) {
            row.remove(column);
          }
          return row;
        })
        .toList(growable: false);
  }

  /// Keeps manual/favorite/used foods while omitting disposable remote search
  /// cache rows. Referenced variants and servings are retained with parents so
  /// meal history and saved meals remain fully usable after restoration.
  static Future<Map<String, List<Map<String, Object?>>>> _exportNutrition(
    Database database,
  ) async {
    final foods = await database.query('foods');
    final variants = await database.query('food_variants');
    final servings = await database.query('food_servings');
    if (foods.isEmpty) {
      return {
        'foods': const [],
        'food_variants': const [],
        'food_servings': const [],
      };
    }

    final referencedFoodIds = <String>{};
    final referencedVariantIds = <String>{};
    for (final table in ['meal_log_items', 'saved_meal_items']) {
      for (final row in await database.query(table)) {
        final foodId = row['food_id'];
        final variantId = row['food_variant_id'];
        if (foodId is String) referencedFoodIds.add(foodId);
        if (variantId is String) referencedVariantIds.add(variantId);
      }
    }
    for (final variant in variants) {
      if (referencedVariantIds.contains(variant['id'])) {
        final foodId = variant['food_id'];
        if (foodId is String) referencedFoodIds.add(foodId);
      }
    }

    final keptFoods = foods
        .where((food) {
          return food['source'] == 'manual' ||
              food['is_favorite'] == 1 ||
              referencedFoodIds.contains(food['id']);
        })
        .toList(growable: false);
    final keptFoodIds = keptFoods
        .map((food) => food['id'])
        .whereType<String>()
        .toSet();
    final keptVariants = variants
        .where((variant) => keptFoodIds.contains(variant['food_id']))
        .toList(growable: false);
    final keptVariantIds = keptVariants
        .map((variant) => variant['id'])
        .whereType<String>()
        .toSet();
    final keptServings = servings
        .where((serving) => keptVariantIds.contains(serving['food_variant_id']))
        .toList(growable: false);
    return {
      'foods': keptFoods,
      'food_variants': keptVariants,
      'food_servings': keptServings,
    };
  }

  static Future<List<Map<String, Object?>>> _exportRunRoutes(
    Database database,
  ) async {
    final rows = await database.query('run_route_data');
    return rows
        .map((row) {
          final copy = Map<String, Object?>.from(row);
          final payload = copy.remove('payload');
          if (payload is List<int>) {
            copy['payload_base64'] = base64Encode(payload);
          } else {
            throw const FormatException('Invalid compact run route payload.');
          }
          return copy;
        })
        .toList(growable: false);
  }

  /// Inserts [rows] into [table], returning the count.
  Future<int> _insertAll(Transaction txn, String table, dynamic rows) async {
    if (rows == null || rows is! List || rows.isEmpty) return 0;
    int count = 0;
    for (final row in rows) {
      await txn.insert(
        table,
        row as Map<String, dynamic>,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      count++;
    }
    return count;
  }

  Future<int> _insertRunRoutes(Transaction txn, dynamic rows) async {
    if (rows == null || rows is! List || rows.isEmpty) return 0;
    var count = 0;
    for (final raw in rows) {
      final row = Map<String, dynamic>.from(raw as Map);
      final encoded = row.remove('payload_base64');
      if (encoded is! String) {
        throw const FormatException('Invalid compact run route backup.');
      }
      try {
        row['payload'] = base64Decode(encoded);
      } on FormatException {
        throw const FormatException('Invalid compact run route backup.');
      }
      final expectedChecksum = row['checksum'];
      final payload = row['payload'];
      if (expectedChecksum is! int ||
          payload is! List<int> ||
          RunRouteCodec.checksum(
                payload is Uint8List ? payload : Uint8List.fromList(payload),
              ) !=
              expectedChecksum) {
        throw const FormatException('Invalid compact run route checksum.');
      }
      await txn.insert(
        'run_route_data',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      count++;
    }
    return count;
  }

  Future<int> _insertSleepSessions(Transaction txn, dynamic rows) async {
    if (rows == null || rows is! List || rows.isEmpty) return 0;
    final columns = (await txn.rawQuery(
      'PRAGMA table_info(sleep_monitor_sessions)',
    )).map((row) => row['name'] as String).toSet();
    var count = 0;
    for (final raw in rows) {
      final row = Map<String, dynamic>.from(raw as Map);
      row['monitor_mode'] ??= row['alarm_at'] == null
          ? 'monitoring_only'
          : 'alarm_without_mission';
      // Older backups may carry columns this schema no longer has.
      row.removeWhere((key, _) => !columns.contains(key));
      await txn.insert(
        'sleep_monitor_sessions',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      count++;
    }
    return count;
  }

  Future<int> _insertMissingSleepSettings(Transaction txn) async {
    const defaults = <String, String>{
      'sleep_mission_enabled': 'false',
      'sleep_mission_type': 'barcode',
      'sleep_mission_barcode_hash': '',
      'sleep_mission_barcode_salt': '',
      'sleep_mission_barcode_format': '',
      'sleep_mission_registered_at': '',
      'sleep_monitor_default_mode': 'alarm_without_mission',
    };
    var inserted = 0;
    for (final entry in defaults.entries) {
      final existing = await txn.query(
        'app_settings',
        where: 'key = ?',
        whereArgs: [entry.key],
        limit: 1,
      );
      if (existing.isEmpty) {
        await txn.insert('app_settings', {
          'key': entry.key,
          'value': entry.value,
        });
        inserted++;
      }
    }
    return inserted;
  }

  // ------------------------------------------------------------------
  // Delete all user data (keeps seed categories & exercises)
  // ------------------------------------------------------------------

  Future<void> deleteAllWorkoutData() async {
    final db = await this.db;
    await db.transaction((txn) async {
      for (final table in [
        'periodization_checkins',
        'phase_targets',
        'periodization_phases',
        'periodization_plans',
        // Children before parents: schedule and step rows reference both the
        // plan sessions and the recorded activities.
        'run_activity_steps',
        'scheduled_runs',
        'run_workout_steps',
        'run_plan_workouts',
        'run_plan_adaptations',
        'run_plans',
        'run_laps',
        'run_splits',
        'run_route_data',
        'run_activities',
        'run_gear',
      ]) {
        await txn.delete(table);
      }
      await txn.delete('predefined_sets');
      await txn.delete('routine_exercises');
      await txn.delete('routine_days');
      await txn.delete('routines');
      await txn.delete('sets');
      await txn.delete('exercise_entries');
      await txn.delete('workouts');
      await txn.delete('body_measurements');
      await txn.delete('sleep_monitor_sessions');
      await txn.delete('sleep_entries');
      await txn.delete('traditional_alarms');
      for (final table in ['medication_doses', 'medications']) {
        await txn.delete(table);
      }
    });
  }

  /// Removes user-generated nutrition data (foods, meal logs, goals).
  /// Food cache rows created from manual entries are also dropped, but
  /// the user can re-enter them. Used by the "delete everything" path
  /// so the action really represents full app reset.
  Future<void> deleteAllNutritionData() async {
    final db = await this.db;
    await db.transaction((txn) async {
      await txn.delete('meal_log_items');
      await txn.delete('meal_logs');
      await txn.delete('meal_types');
      await txn.delete('food_servings');
      await txn.delete('food_variants');
      await txn.delete('foods');
      await txn.delete('nutrition_goals');
      await txn.delete('saved_meal_items');
      await txn.delete('saved_meals');
    });
  }
}
