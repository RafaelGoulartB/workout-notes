import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'base_repository.dart';

/// Repository for workouts, exercise entries, and sets CRUD operations.
class WorkoutRepository extends BaseRepository {
  // ===================================================================
  // WORKOUTS
  // ===================================================================

  Future<String> createWorkout({
    DateTime? date,
    String? routineId,
    List<Map<String, dynamic>>? exercises,
  }) async {
    final db = await this.db;
    final id = const Uuid().v4();
    final now = DateTime.now();
    await db.insert('workouts', {
      'id': id,
      'date': (date ?? now).toIso8601String().substring(0, 10),
      'is_from_routine': routineId != null ? 1 : 0,
      'routine_id': routineId,
      'created_at': now.toIso8601String(),
    });

    if (exercises != null) {
      for (int i = 0; i < exercises.length; i++) {
        final entryId = const Uuid().v4();
        await db.insert('exercise_entries', {
          'id': entryId,
          'workout_id': id,
          'exercise_id': exercises[i]['exercise_id'],
          'order_index': i,
          'notes': exercises[i]['notes'],
          'rest_time_seconds': exercises[i]['rest_time_seconds'],
        });

        final sets = exercises[i]['sets'] as List<Map<String, dynamic>>? ?? [];
        for (int j = 0; j < sets.length; j++) {
          final s = sets[j];
          await db.insert('sets', {
            'id': const Uuid().v4(),
            'exercise_entry_id': entryId,
            'weight': s['weight'],
            'reps': s['reps'],
            'distance': s['distance'],
            'time_seconds': s['time_seconds'],
            'is_complete': 0,
            'is_warmup': s['is_warmup'] ?? 0,
            'rpe': s['rpe'],
            'comment': s['comment'],
            'order_index': j,
          });
        }
      }
    }

    return id;
  }

  Future<void> importRoutineDayToWorkout(String workoutId, String routineDayId) async {
    final db = await this.db;
    final routineExercises = await _getRoutineExercises(db, routineDayId);

    for (final re in routineExercises) {
      final entryId = const Uuid().v4();
      final count = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM exercise_entries WHERE workout_id = ?', [workoutId]),
      ) ?? 0;

      await db.insert('exercise_entries', {
        'id': entryId,
        'workout_id': workoutId,
        'exercise_id': re['exercise_id'],
        'order_index': count,
        'rest_time_seconds': re['rest_time_seconds'],
      });

      final sets = await _getPredefinedSets(db, re['id'] as String);
      for (int j = 0; j < sets.length; j++) {
        final s = sets[j];
        await db.insert('sets', {
          'id': const Uuid().v4(),
          'exercise_entry_id': entryId,
          'weight': s['weight'],
          'reps': s['reps'],
          'distance': s['distance'],
          'time_seconds': s['time_seconds'],
          'is_complete': 0,
          'is_warmup': s['is_warmup'] ?? 0,
          'order_index': j,
        });
      }
    }
  }

  Future<String> copyWorkoutToDate(String sourceWorkoutId, DateTime newDate) async {
    final db = await this.db;
    final sourceWorkout = await _getWorkout(db, sourceWorkoutId);
    if (sourceWorkout == null) throw Exception('Source workout not found');

    final newId = const Uuid().v4();
    final now = DateTime.now().toIso8601String();
    await db.insert('workouts', {
      'id': newId,
      'date': newDate.toIso8601String().substring(0, 10),
      'start_time': null,
      'end_time': null,
      'duration_seconds': null,
      'comment': null,
      'feeling_rating': null,
      'is_from_routine': sourceWorkout['is_from_routine'] ?? 0,
      'routine_id': sourceWorkout['routine_id'],
      'created_at': now,
    });

    final entries = await db.query('exercise_entries',
        where: 'workout_id = ?',
        whereArgs: [sourceWorkoutId],
        orderBy: 'order_index ASC');

    for (final entry in entries) {
      final newEntryId = const Uuid().v4();
      await db.insert('exercise_entries', {
        'id': newEntryId,
        'workout_id': newId,
        'exercise_id': entry['exercise_id'],
        'order_index': entry['order_index'],
        'superset_group_id': entry['superset_group_id'],
        'notes': entry['notes'],
        'rest_time_seconds': entry['rest_time_seconds'],
      });

      final sets = await db.query('sets',
          where: 'exercise_entry_id = ?',
          whereArgs: [entry['id']],
          orderBy: 'order_index ASC');

      for (final s in sets) {
        await db.insert('sets', {
          'id': const Uuid().v4(),
          'exercise_entry_id': newEntryId,
          'weight': s['weight'],
          'reps': s['reps'],
          'distance': s['distance'],
          'time_seconds': s['time_seconds'],
          'is_complete': 0,
          'is_warmup': s['is_warmup'] ?? 0,
          'rpe': s['rpe'],
          'comment': s['comment'],
          'order_index': s['order_index'],
        });
      }
    }

    return newId;
  }

  Future<Map<String, dynamic>?> getWorkout(String id) async {
    final db = await this.db;
    final results = await db.query('workouts', where: 'id = ?', whereArgs: [id]);
    return results.isEmpty ? null : results.first;
  }
  /// Returns workouts that are currently active (no end_time, from today,
  /// and with at least one exercise entry).
  Future<List<Map<String, dynamic>>> getActiveWorkouts() async {
    final db = await this.db;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return db.rawQuery('''
      SELECT DISTINCT w.* FROM workouts w
      JOIN exercise_entries ee ON ee.workout_id = w.id
      WHERE w.end_time IS NULL AND w.date = ?
      ORDER BY w.created_at DESC
    ''', [today]);
  }

  Future<List<Map<String, dynamic>>> getWorkouts({
    DateTime? startDate,
    DateTime? endDate,
    int? limit,
    int? offset,
  }) async {
    final db = await this.db;
    var query = 'SELECT * FROM workouts WHERE 1=1';
    final args = <dynamic>[];

    if (startDate != null) {
      query += ' AND date >= ?';
      args.add(startDate.toIso8601String().substring(0, 10));
    }
    if (endDate != null) {
      query += ' AND date <= ?';
      args.add(endDate.toIso8601String().substring(0, 10));
    }

    query += ' ORDER BY date DESC, start_time DESC';

    if (limit != null) {
      query += ' LIMIT ?';
      args.add(limit);
    }
    if (offset != null) {
      query += ' OFFSET ?';
      args.add(offset);
    }

    return db.rawQuery(query, args);
  }

  Future<List<Map<String, dynamic>>> getWorkoutsByMonth(int year, int month) async {
    final db = await this.db;
    final monthStr = month.toString().padLeft(2, '0');
    return db.rawQuery(
      "SELECT * FROM workouts WHERE date LIKE ? ORDER BY date DESC",
      ['$year-$monthStr%'],
    );
  }

  Future<Map<String, List<Map<String, dynamic>>>> getWorkoutCategoriesByDate(int year, int month) async {
    final db = await this.db;
    final monthStr = month.toString().padLeft(2, '0');
    final rows = await db.rawQuery('''
      SELECT DISTINCT w.date, ec.id as category_id, ec.name as category_name, ec.color as category_color
      FROM workouts w
      JOIN exercise_entries ee ON w.id = ee.workout_id
      JOIN exercises e ON ee.exercise_id = e.id
      JOIN exercise_categories ec ON e.category_id = ec.id
      WHERE w.date LIKE ?
      ORDER BY w.date, ec.name
    ''', ['$year-$monthStr%']);

    final Map<String, List<Map<String, dynamic>>> result = {};
    for (final row in rows) {
      final date = row['date'] as String;
      result.putIfAbsent(date, () => []).add({
        'id': row['category_id'],
        'name': row['category_name'],
        'color': row['category_color'],
      });
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> getWorkoutExercises(String workoutId) async {
    final db = await this.db;
    return db.rawQuery(
      'SELECT ee.*, e.name as exercise_name, e.locale_key as exercise_locale_key, e.category_id, '
      'ec.name as category_name, ec.color as category_color, ec.energy_system as category_energy, e.type as exercise_type '
      'FROM exercise_entries ee '
      'JOIN exercises e ON ee.exercise_id = e.id '
      'LEFT JOIN exercise_categories ec ON e.category_id = ec.id '
      'WHERE ee.workout_id = ? '
      'ORDER BY ee.order_index ASC',
      [workoutId],
    );
  }

  Future<List<Map<String, dynamic>>> getExerciseSets(String exerciseEntryId) async {
    final db = await this.db;
    return db.query('sets',
        where: 'exercise_entry_id = ?',
        whereArgs: [exerciseEntryId],
        orderBy: 'order_index ASC');
  }

  Future<void> finishWorkout(String id, {String? comment, int? feelingRating}) async {
    final db = await this.db;
    final now = DateTime.now();
    final workout = await getWorkout(id);
    if (workout == null) return;

    int duration = 0;
    final startTimeStr = workout['start_time'] as String?;
    if (startTimeStr != null) {
      final startTime = DateTime.parse(startTimeStr);
      duration = now.difference(startTime).inSeconds;
    }

    await db.update('workouts', {
      'end_time': now.toIso8601String(),
      'duration_seconds': duration,
      'start_time': startTimeStr ?? now.toIso8601String(),
      'comment': ?comment,
      'feeling_rating': ?feelingRating,
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> startWorkoutTimer(String id) async {
    final db = await this.db;
    final now = DateTime.now().toIso8601String();
    await db.update('workouts', {
      'start_time': now,
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> stopWorkoutTimer(String id) async {
    final db = await this.db;
    final now = DateTime.now();
    final workout = await getWorkout(id);
    if (workout == null) return;
    final startTimeStr = workout['start_time'] as String?;
    int duration = 0;
    if (startTimeStr != null) {
      final startTime = DateTime.parse(startTimeStr);
      duration = now.difference(startTime).inSeconds;
    }
    await db.update('workouts', {
      'end_time': now.toIso8601String(),
      'duration_seconds': duration,
      'start_time': startTimeStr ?? now.toIso8601String(),
      'pause_start_time': null,
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> resetWorkoutTimer(String id) async {
    final db = await this.db;
    await db.update('workouts', {
      'start_time': null,
      'end_time': null,
      'duration_seconds': null,
      'pause_start_time': null,
    }, where: 'id = ?', whereArgs: [id]);
  }

  /// Persists the workout pause start time.
  Future<void> setWorkoutPause(String id, DateTime pauseStart) async {
    final db = await this.db;
    await db.update('workouts', {
      'pause_start_time': pauseStart.toIso8601String(),
    }, where: 'id = ?', whereArgs: [id]);
  }

  /// Clears the pause state and shifts the start time forward by the
  /// accumulated pause duration, so the elapsed time excludes the pause.
  Future<void> clearWorkoutPause(String id, DateTime newStartTime) async {
    final db = await this.db;
    await db.update('workouts', {
      'pause_start_time': null,
      'start_time': newStartTime.toIso8601String(),
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateWorkoutDate(String id, DateTime newDate) async {
    final db = await this.db;
    await db.update('workouts', {
      'date': newDate.toIso8601String().substring(0, 10),
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> resetWorkoutToInProgress(String id) async {
    final db = await this.db;
    await db.update('workouts', {
      'end_time': null,
      'duration_seconds': null,
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteWorkout(String id) async {
    final db = await this.db;
    await db.delete('workouts', where: 'id = ?', whereArgs: [id]);
  }

  // ===================================================================
  // SETS
  // ===================================================================

  Future<String> addSet({
    required String exerciseEntryId,
    double? weight,
    int? reps,
    double? distance,
    int? timeSeconds,
    bool isWarmup = false,
    double? rpe,
    String? comment,
  }) async {
    final db = await this.db;
    final id = const Uuid().v4();
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM sets WHERE exercise_entry_id = ?', [exerciseEntryId]),
    ) ?? 0;

    await db.insert('sets', {
      'id': id,
      'exercise_entry_id': exerciseEntryId,
      'weight': weight,
      'reps': reps,
      'distance': distance,
      'time_seconds': timeSeconds,
      'is_complete': 0,
      'is_warmup': isWarmup ? 1 : 0,
      'rpe': rpe,
      'comment': comment,
      'order_index': count,
    });
    return id;
  }

  Future<void> updateSet(String setId, {
    double? weight,
    int? reps,
    double? distance,
    int? timeSeconds,
    bool? isComplete,
    bool? isWarmup,
    double? rpe,
    String? comment,
  }) async {
    final db = await this.db;
    final updates = <String, dynamic>{};
    if (weight != null) updates['weight'] = weight;
    if (reps != null) updates['reps'] = reps;
    if (distance != null) updates['distance'] = distance;
    if (timeSeconds != null) updates['time_seconds'] = timeSeconds;
    if (isComplete != null) updates['is_complete'] = isComplete ? 1 : 0;
    if (isWarmup != null) updates['is_warmup'] = isWarmup ? 1 : 0;
    if (rpe != null) updates['rpe'] = rpe;
    if (comment != null) updates['comment'] = comment;

    if (updates.isNotEmpty) {
      await db.update('sets', updates, where: 'id = ?', whereArgs: [setId]);
    }
  }

  Future<void> toggleSetComplete(String setId) async {
    final db = await this.db;
    final result = await db.query('sets', where: 'id = ?', whereArgs: [setId]);
    if (result.isEmpty) return;
    final current = (result.first['is_complete'] as int?) ?? 0;
    await db.update('sets', {'is_complete': current == 0 ? 1 : 0},
        where: 'id = ?', whereArgs: [setId]);
  }

  Future<void> deleteSet(String setId) async {
    final db = await this.db;
    await db.delete('sets', where: 'id = ?', whereArgs: [setId]);
  }

  Future<void> removeExerciseEntryFromWorkout(String workoutId, String exerciseId) async {
    final db = await this.db;
    final entries = await db.query('exercise_entries',
        where: 'workout_id = ? AND exercise_id = ?',
        whereArgs: [workoutId, exerciseId]);
    for (final entry in entries) {
      final entryId = entry['id'] as String;
      await db.delete('sets', where: 'exercise_entry_id = ?', whereArgs: [entryId]);
      await db.delete('exercise_entries', where: 'id = ?', whereArgs: [entryId]);
    }
  }

  Future<void> deleteExerciseEntry(String entryId) async {
    final db = await this.db;
    await db.delete('sets', where: 'exercise_entry_id = ?', whereArgs: [entryId]);
    await db.delete('exercise_entries', where: 'id = ?', whereArgs: [entryId]);
  }

  Future<void> updateExerciseEntryRestTime(String exerciseEntryId, int restTimeSeconds) async {
    final db = await this.db;
    await db.update('exercise_entries',
      {'rest_time_seconds': restTimeSeconds},
      where: 'id = ?', whereArgs: [exerciseEntryId]);
  }

  Future<List<Map<String, dynamic>>> getLastWorkoutSets(
      String exerciseId, {String? excludeWorkoutId}) async {
    final db = await this.db;

    String where = 'ee.exercise_id = ?';
    final args = <dynamic>[exerciseId];
    if (excludeWorkoutId != null) {
      where += ' AND w.id != ?';
      args.add(excludeWorkoutId);
    }
    final lastWid = await db.rawQuery('''
      SELECT ee.workout_id FROM exercise_entries ee
      JOIN workouts w ON ee.workout_id = w.id
      WHERE $where
      ORDER BY w.date DESC, w.start_time DESC
      LIMIT 1
    ''', args);

    if (lastWid.isEmpty) return [];
    final workoutId = lastWid.first['workout_id'] as String;

    return db.rawQuery('''
      SELECT s.* FROM sets s
      JOIN exercise_entries ee ON s.exercise_entry_id = ee.id
      WHERE ee.exercise_id = ? AND ee.workout_id = ?
      ORDER BY s.order_index ASC
    ''', [exerciseId, workoutId]);
  }

  // ===================================================================
  // INTERNAL HELPERS (used by importRoutineDayToWorkout)
  // ===================================================================

  Future<List<Map<String, dynamic>>> _getRoutineExercises(Database db, String routineDayId) async {
    return db.rawQuery('''
      SELECT re.*, e.name as exercise_name, e.locale_key as exercise_locale_key, e.category_id,
      ec.name as category_name, ec.color as category_color, e.type as exercise_type
      FROM routine_exercises re
      JOIN exercises e ON re.exercise_id = e.id
      LEFT JOIN exercise_categories ec ON e.category_id = ec.id
      WHERE re.routine_day_id = ?
      ORDER BY re.order_index ASC
    ''', [routineDayId]);
  }

  Future<List<Map<String, dynamic>>> _getPredefinedSets(Database db, String routineExerciseId) async {
    return db.query('predefined_sets',
        where: 'routine_exercise_id = ?',
        whereArgs: [routineExerciseId],
        orderBy: 'order_index ASC');
  }

  Future<Map<String, dynamic>?> _getWorkout(Database db, String id) async {
    final results = await db.query('workouts', where: 'id = ?', whereArgs: [id]);
    return results.isEmpty ? null : results.first;
  }
}
