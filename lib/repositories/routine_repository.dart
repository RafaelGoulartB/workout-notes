import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'base_repository.dart';

/// Repository for routines, routine days, routine exercises, and predefined sets.
class RoutineRepository extends BaseRepository {
  Future<String> createRoutine(String name, {String? notes}) async {
    final db = await this.db;
    final id = const Uuid().v4();
    await db.insert('routines', {
      'id': id,
      'name': name,
      'notes': notes,
      'created_at': DateTime.now().toIso8601String(),
    });
    return id;
  }

  Future<List<Map<String, dynamic>>> getRoutines() async {
    final db = await this.db;
    return db.query('routines', orderBy: 'created_at DESC');
  }

  Future<Map<String, dynamic>?> getRoutine(String id) async {
    final db = await this.db;
    final result = await db.query('routines', where: 'id = ?', whereArgs: [id]);
    return result.isEmpty ? null : result.first;
  }

  Future<void> updateRoutine(String id, {String? name, String? notes}) async {
    final db = await this.db;
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (notes != null) updates['notes'] = notes;
    if (updates.isNotEmpty) {
      await db.update('routines', updates, where: 'id = ?', whereArgs: [id]);
    }
  }

  Future<void> deleteRoutine(String id) async {
    final db = await this.db;
    await db.delete('routines', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getRoutineDays(String routineId) async {
    final db = await this.db;
    return db.query('routine_days',
        where: 'routine_id = ?',
        whereArgs: [routineId],
        orderBy: 'order_index ASC');
  }

  Future<String> addRoutineDay(String routineId, String name) async {
    final db = await this.db;
    final id = const Uuid().v4();
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM routine_days WHERE routine_id = ?', [routineId]),
    ) ?? 0;
    await db.insert('routine_days', {
      'id': id,
      'routine_id': routineId,
      'name': name,
      'order_index': count,
    });
    return id;
  }

  Future<void> deleteRoutineDay(String id) async {
    final db = await this.db;
    await db.delete('routine_days', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getRoutineExercises(String routineDayId) async {
    final db = await this.db;
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

  Future<String> addRoutineExercise(String routineDayId, String exerciseId, {int? restTimeSeconds}) async {
    final db = await this.db;
    final id = const Uuid().v4();
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM routine_exercises WHERE routine_day_id = ?', [routineDayId]),
    ) ?? 0;
    await db.insert('routine_exercises', {
      'id': id,
      'routine_day_id': routineDayId,
      'exercise_id': exerciseId,
      'order_index': count,
      'rest_time_seconds': ?restTimeSeconds,
    });
    return id;
  }

  Future<void> removeRoutineExercise(String id) async {
    final db = await this.db;
    await db.delete('routine_exercises', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateRoutineExerciseRestTime(String routineExerciseId, int restTimeSeconds) async {
    final db = await this.db;
    await db.update('routine_exercises',
      {'rest_time_seconds': restTimeSeconds},
      where: 'id = ?', whereArgs: [routineExerciseId]);
  }

  Future<List<Map<String, dynamic>>> getPredefinedSets(String routineExerciseId) async {
    final db = await this.db;
    return db.query('predefined_sets',
        where: 'routine_exercise_id = ?',
        whereArgs: [routineExerciseId],
        orderBy: 'order_index ASC');
  }

  Future<String> addPredefinedSet(String routineExerciseId, {
    double? weight,
    int? reps,
    double? distance,
    int? timeSeconds,
    bool isWarmup = false,
  }) async {
    final db = await this.db;
    final id = const Uuid().v4();
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM predefined_sets WHERE routine_exercise_id = ?', [routineExerciseId]),
    ) ?? 0;
    await db.insert('predefined_sets', {
      'id': id,
      'routine_exercise_id': routineExerciseId,
      'weight': weight,
      'reps': reps,
      'distance': distance,
      'time_seconds': timeSeconds,
      'is_warmup': isWarmup ? 1 : 0,
      'order_index': count,
    });
    return id;
  }

  Future<void> updatePredefinedSet(String id, {
    double? weight,
    int? reps,
    double? distance,
    int? timeSeconds,
    bool? isWarmup,
  }) async {
    final db = await this.db;
    final updates = <String, dynamic>{};
    if (weight != null) updates['weight'] = weight;
    if (reps != null) updates['reps'] = reps;
    if (distance != null) updates['distance'] = distance;
    if (timeSeconds != null) updates['time_seconds'] = timeSeconds;
    if (isWarmup != null) updates['is_warmup'] = isWarmup ? 1 : 0;
    if (updates.isNotEmpty) {
      await db.update('predefined_sets', updates, where: 'id = ?', whereArgs: [id]);
    }
  }

  Future<void> deletePredefinedSet(String id) async {
    final db = await this.db;
    await db.delete('predefined_sets', where: 'id = ?', whereArgs: [id]);
  }
}
