import 'package:sqflite/sqflite.dart';
import 'base_repository.dart';

/// Repository for data export and import operations.
///
/// Export produces a JSON map with every table's rows plus a version
/// marker. Import performs a full restore: it clears all tables, then
/// inserts the backup rows inside a single transaction so the database
/// ends up in an exact copy of the exported state.
class ExportImportRepository extends BaseRepository {
  static const int currentBackupVersion = 11;
  static const int minimumSupportedBackupVersion = 2;

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
    return {
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
      'user_goals': await _queryIfExists(db, 'user_goals'),
      'sleep_entries': await db.query('sleep_entries'),
      'sleep_monitor_sessions': await db.query('sleep_monitor_sessions'),
      'sleep_monitor_segments': await db.query('sleep_monitor_segments'),
      'foods': await _queryIfExists(db, 'foods'),
      'food_variants': await _queryIfExists(db, 'food_variants'),
      'food_servings': await _queryIfExists(db, 'food_servings'),
      'meal_logs': await _queryIfExists(db, 'meal_logs'),
      'meal_log_items': await _queryIfExists(db, 'meal_log_items'),
      'nutrition_goals': await _queryIfExists(db, 'nutrition_goals'),
      'saved_meals': await _queryIfExists(db, 'saved_meals'),
      'saved_meal_items': await _queryIfExists(db, 'saved_meal_items'),
      'sleep_stage_epochs': await _queryIfExists(db, 'sleep_stage_epochs'),
      'traditional_alarms': await _queryIfExists(db, 'traditional_alarms'),
      'settings': await db.query('app_settings'),
    };
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
    final db = await this.db;
    int totalRows = 0;

    await db.transaction((txn) async {
      // 1. Clear all tables (order matters because of FKs)
      await txn.delete('predefined_sets');
      await txn.delete('routine_exercises');
      await txn.delete('routine_days');
      await txn.delete('routines');
      await txn.delete('sets');
      await txn.delete('exercise_entries');
      await txn.delete('workouts');
      await txn.delete('body_measurements');
      if (await _tableExists(txn, 'user_goals')) {
        await txn.delete('user_goals');
      }
      if (await _tableExists(txn, 'sleep_stage_epochs')) {
        await txn.delete('sleep_stage_epochs');
      }
      await txn.delete('sleep_monitor_segments');
      await txn.delete('sleep_monitor_sessions');
      await txn.delete('sleep_entries');
      // Nutrition tables exist only on databases migrated past the
      // nutrition schema version, so clear them defensively.
      for (final table in [
        'meal_log_items',
        'meal_logs',
        'food_servings',
        'food_variants',
        'foods',
        'nutrition_goals',
        'saved_meal_items',
        'saved_meals',
      ]) {
        if (await _tableExists(txn, table)) {
          await txn.delete(table);
        }
      }
      if (await _tableExists(txn, 'traditional_alarms')) {
        await txn.delete('traditional_alarms');
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
      totalRows += await _insertAll(
        txn,
        'body_measurements',
        data['body_measurements'],
      );
      if (await _tableExists(txn, 'user_goals')) {
        totalRows += await _insertAll(txn, 'user_goals', data['user_goals']);
      }
      totalRows += await _insertAll(
        txn,
        'sleep_entries',
        data['sleep_entries'],
      );
      totalRows += await _insertSleepSessions(
        txn,
        data['sleep_monitor_sessions'],
      );
      totalRows += await _insertAll(
        txn,
        'sleep_monitor_segments',
        data['sleep_monitor_segments'],
      );
      for (final table in [
        'foods',
        'food_variants',
        'food_servings',
        'meal_logs',
        'meal_log_items',
        'nutrition_goals',
        'saved_meals',
        'saved_meal_items',
      ]) {
        if (await _tableExists(txn, table)) {
          totalRows += await _insertAll(txn, table, data[table]);
        }
      }
      if (await _tableExists(txn, 'sleep_stage_epochs')) {
        totalRows += await _insertAll(
          txn,
          'sleep_stage_epochs',
          data['sleep_stage_epochs'],
        );
      }
      if (await _tableExists(txn, 'traditional_alarms')) {
        totalRows += await _insertAll(
          txn,
          'traditional_alarms',
          data['traditional_alarms'],
        );
      }
      totalRows += await _insertAll(txn, 'app_settings', data['settings']);
      // Backups before v6 had no mission settings. Add the safe disabled
      // defaults only on the production schema; the schema check keeps
      // compatibility with older lightweight test/import databases.
      final sessionColumns = (await txn.rawQuery(
        'PRAGMA table_info(sleep_monitor_sessions)',
      )).map((row) => row['name'] as String).toSet();
      if (sessionColumns.contains('monitor_mode')) {
        totalRows += await _insertMissingSleepSettings(txn);
      }
    });

    return totalRows;
  }

  static Future<List<Map<String, Object?>>> _queryIfExists(
    Database database,
    String table,
  ) async {
    return await _tableExists(database, table)
        ? database.query(table)
        : const [];
  }

  static Future<bool> _tableExists(
    DatabaseExecutor database,
    String table,
  ) async {
    final rows = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      [table],
    );
    return rows.isNotEmpty;
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

  Future<int> _insertSleepSessions(Transaction txn, dynamic rows) async {
    if (rows == null || rows is! List || rows.isEmpty) return 0;
    final columns = (await txn.rawQuery(
      'PRAGMA table_info(sleep_monitor_sessions)',
    )).map((row) => row['name'] as String).toSet();
    var count = 0;
    for (final raw in rows) {
      final row = Map<String, dynamic>.from(raw as Map);
      if (columns.contains('monitor_mode')) {
        row['monitor_mode'] ??= row['alarm_at'] == null
            ? 'monitoring_only'
            : 'alarm_without_mission';
      }
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
  // CSV export (read-only query, unchanged)
  // ------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> exportWorkoutsCsvData({
    String? exerciseId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final db = await this.db;
    var query = '''
      SELECT w.date, e.name as exercise, ec.name as category,
        s.weight, s.reps, s.distance, s.time_seconds,
        s.is_warmup, s.rpe, s.comment as set_comment,
        w.comment as workout_comment
      FROM sets s
      JOIN exercise_entries ee ON s.exercise_entry_id = ee.id
      JOIN exercises e ON ee.exercise_id = e.id
      LEFT JOIN exercise_categories ec ON e.category_id = ec.id
      JOIN workouts w ON ee.workout_id = w.id
      WHERE 1=1
    ''';
    final args = <dynamic>[];

    if (exerciseId != null) {
      query += ' AND e.id = ?';
      args.add(exerciseId);
    }
    if (startDate != null) {
      query += ' AND w.date >= ?';
      args.add(startDate.toIso8601String().substring(0, 10));
    }
    if (endDate != null) {
      query += ' AND w.date <= ?';
      args.add(endDate.toIso8601String().substring(0, 10));
    }

    query += ' ORDER BY w.date DESC, s.order_index ASC';
    return db.rawQuery(query, args);
  }

  // ------------------------------------------------------------------
  // Delete all user data (keeps seed categories & exercises)
  // ------------------------------------------------------------------

  Future<void> deleteAllWorkoutData() async {
    final db = await this.db;
    await db.transaction((txn) async {
      await txn.delete('predefined_sets');
      await txn.delete('routine_exercises');
      await txn.delete('routine_days');
      await txn.delete('routines');
      await txn.delete('sets');
      await txn.delete('exercise_entries');
      await txn.delete('workouts');
      await txn.delete('body_measurements');
      if (await _tableExists(txn, 'sleep_stage_epochs')) {
        await txn.delete('sleep_stage_epochs');
      }
      await txn.delete('sleep_monitor_segments');
      await txn.delete('sleep_monitor_sessions');
      await txn.delete('sleep_entries');
      if (await _tableExists(txn, 'traditional_alarms')) {
        await txn.delete('traditional_alarms');
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
      await txn.delete('food_servings');
      await txn.delete('food_variants');
      await txn.delete('foods');
      await txn.delete('nutrition_goals');
      if (await _tableExists(txn, 'saved_meal_items')) {
        await txn.delete('saved_meal_items');
      }
      if (await _tableExists(txn, 'saved_meals')) {
        await txn.delete('saved_meals');
      }
    });
  }
}
