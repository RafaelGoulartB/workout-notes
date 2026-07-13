import 'package:sqflite/sqflite.dart';
import 'base_repository.dart';

/// Repository for data export and import operations.
///
/// Export produces a JSON map with every table's rows plus a version
/// marker. Import performs a full restore: it clears all tables, then
/// inserts the backup rows inside a single transaction so the database
/// ends up in an exact copy of the exported state.
class ExportImportRepository extends BaseRepository {
  static const int currentBackupVersion = 2;

  /// Tables that form a complete backup, in their dependency-safe order.
  static const backupTables = <String>[
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
    'settings',
  ];

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
    final rows = validateBackup(data);
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
      await txn.delete('exercises');
      await txn.delete('exercise_categories');
      await txn.delete('app_settings');

      // 2. Insert backup rows in FK-safe order
      totalRows += await _insertAll(
        txn,
        'exercise_categories',
        rows['categories']!,
      );
      totalRows += await _insertAll(txn, 'exercises', rows['exercises']!);
      totalRows += await _insertAll(txn, 'workouts', rows['workouts']!);
      totalRows += await _insertAll(
        txn,
        'exercise_entries',
        rows['exercise_entries']!,
      );
      totalRows += await _insertAll(txn, 'sets', rows['sets']!);
      totalRows += await _insertAll(txn, 'routines', rows['routines']!);
      totalRows += await _insertAll(txn, 'routine_days', rows['routine_days']!);
      totalRows += await _insertAll(
        txn,
        'routine_exercises',
        rows['routine_exercises']!,
      );
      totalRows += await _insertAll(
        txn,
        'predefined_sets',
        rows['predefined_sets']!,
      );
      totalRows += await _insertAll(
        txn,
        'body_measurements',
        rows['body_measurements']!,
      );
      totalRows += await _insertAll(txn, 'app_settings', rows['settings']!);
    });

    return totalRows;
  }

  /// Validates the entire document before a restore transaction deletes data.
  /// Dynamic maps stay confined to this persistence boundary.
  static Map<String, List<Map<String, dynamic>>> validateBackup(
    Map<String, dynamic> data,
  ) {
    final version = data['version'];
    if (version != currentBackupVersion) {
      throw FormatException(
        'Unsupported backup version: $version (expected '
        '$currentBackupVersion).',
      );
    }

    final validated = <String, List<Map<String, dynamic>>>{};
    for (final key in backupTables) {
      final value = data[key];
      if (value is! List) {
        throw FormatException('Backup table "$key" must be a list.');
      }

      final rows = <Map<String, dynamic>>[];
      for (var index = 0; index < value.length; index++) {
        final row = value[index];
        if (row is! Map) {
          throw FormatException('Backup row $key[$index] must be an object.');
        }
        final normalized = <String, dynamic>{};
        for (final entry in row.entries) {
          if (entry.key is! String) {
            throw FormatException(
              'Backup row $key[$index] contains a non-text column name.',
            );
          }
          normalized[entry.key as String] = entry.value;
        }
        rows.add(normalized);
      }
      validated[key] = rows;
    }
    return validated;
  }

  /// Inserts validated [rows] into [table], returning the count.
  Future<int> _insertAll(
    Transaction txn,
    String table,
    List<Map<String, dynamic>> rows,
  ) async {
    int count = 0;
    for (final row in rows) {
      await txn.insert(
        table,
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      count++;
    }
    return count;
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
    });
  }
}
