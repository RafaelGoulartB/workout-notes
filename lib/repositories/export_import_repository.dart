import 'package:sqflite/sqflite.dart';
import 'base_repository.dart';

/// Repository for data export and import operations.
class ExportImportRepository extends BaseRepository {
  Future<Map<String, dynamic>> exportAllData() async {
    final db = await this.db;
    return {
      'version': 1,
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

  Future<int> importData(Map<String, dynamic> data) async {
    final db = await this.db;
    int count = 0;

    await db.transaction((txn) async {
      if (data['categories'] != null) {
        for (final row in data['categories'] as List) {
          await txn.insert('exercise_categories', row as Map<String, dynamic>,
              conflictAlgorithm: ConflictAlgorithm.replace);
          count++;
        }
      }
      if (data['exercises'] != null) {
        for (final row in data['exercises'] as List) {
          await txn.insert('exercises', row as Map<String, dynamic>,
              conflictAlgorithm: ConflictAlgorithm.replace);
          count++;
        }
      }
      if (data['workouts'] != null) {
        for (final row in data['workouts'] as List) {
          await txn.insert('workouts', row as Map<String, dynamic>,
              conflictAlgorithm: ConflictAlgorithm.replace);
          count++;
        }
      }
      if (data['exercise_entries'] != null) {
        for (final row in data['exercise_entries'] as List) {
          await txn.insert('exercise_entries', row as Map<String, dynamic>,
              conflictAlgorithm: ConflictAlgorithm.replace);
          count++;
        }
      }
      if (data['sets'] != null) {
        for (final row in data['sets'] as List) {
          await txn.insert('sets', row as Map<String, dynamic>,
              conflictAlgorithm: ConflictAlgorithm.replace);
          count++;
        }
      }
      if (data['routines'] != null) {
        for (final row in data['routines'] as List) {
          await txn.insert('routines', row as Map<String, dynamic>,
              conflictAlgorithm: ConflictAlgorithm.replace);
          count++;
        }
      }
      if (data['routine_days'] != null) {
        for (final row in data['routine_days'] as List) {
          await txn.insert('routine_days', row as Map<String, dynamic>,
              conflictAlgorithm: ConflictAlgorithm.replace);
          count++;
        }
      }
      if (data['routine_exercises'] != null) {
        for (final row in data['routine_exercises'] as List) {
          await txn.insert('routine_exercises', row as Map<String, dynamic>,
              conflictAlgorithm: ConflictAlgorithm.replace);
          count++;
        }
      }
      if (data['predefined_sets'] != null) {
        for (final row in data['predefined_sets'] as List) {
          await txn.insert('predefined_sets', row as Map<String, dynamic>,
              conflictAlgorithm: ConflictAlgorithm.replace);
          count++;
        }
      }
      if (data['body_measurements'] != null) {
        for (final row in data['body_measurements'] as List) {
          await txn.insert('body_measurements', row as Map<String, dynamic>,
              conflictAlgorithm: ConflictAlgorithm.replace);
          count++;
        }
      }
    });

    return count;
  }

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

  Future<void> deleteAllWorkoutData() async {
    final db = await this.db;
    await db.transaction((txn) async {
      await txn.delete('sets');
      await txn.delete('exercise_entries');
      await txn.delete('workouts');
      await txn.delete('body_measurements');
    });
  }
}
