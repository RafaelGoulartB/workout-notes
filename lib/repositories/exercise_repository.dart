import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'base_repository.dart';

/// How often and how recently an exercise was actually trained.
class ExerciseUsage {
  final String exerciseId;
  final DateTime? lastDate;

  /// Finished workouts with at least one completed working set.
  final int sessions;

  const ExerciseUsage({
    required this.exerciseId,
    required this.lastDate,
    required this.sessions,
  });
}

/// Repository for exercise categories and exercises CRUD operations.
class ExerciseRepository extends BaseRepository {
  // ===================================================================
  // EXERCISE CATEGORIES
  // ===================================================================

  Future<List<Map<String, dynamic>>> getCategories() async {
    final db = await this.db;
    return db.query('exercise_categories', orderBy: 'order_index ASC');
  }

  Future<Map<String, dynamic>?> getCategory(String id) async {
    final db = await this.db;
    final result = await db.query(
      'exercise_categories',
      where: 'id = ?',
      whereArgs: [id],
    );
    return result.isEmpty ? null : result.first;
  }

  Future<String> addCategory(String name, int color) async {
    final db = await this.db;
    final id = const Uuid().v4();
    final count =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM exercise_categories'),
        ) ??
        0;
    await db.insert('exercise_categories', {
      'id': id,
      'name': name,
      'color': color,
      'order_index': count,
    });
    return id;
  }

  Future<void> updateCategory(String id, String name, int color) async {
    final db = await this.db;
    await db.update(
      'exercise_categories',
      {'name': name, 'color': color},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteCategory(String id) async {
    final db = await this.db;
    await db.delete('exercise_categories', where: 'id = ?', whereArgs: [id]);
  }

  // ===================================================================
  // EXERCISES
  // ===================================================================

  Future<List<Map<String, dynamic>>> getExercises({
    String? categoryId,
    String? search,
    bool? favorites,
  }) async {
    final db = await this.db;
    var query =
        'SELECT e.*, ec.name as category_name, ec.color as category_color, ec.energy_system as category_energy '
        'FROM exercises e '
        'JOIN exercise_categories ec ON e.category_id = ec.id '
        'WHERE 1=1';
    final args = <dynamic>[];

    if (categoryId != null) {
      query += ' AND e.category_id = ?';
      args.add(categoryId);
    }
    if (search != null && search.isNotEmpty) {
      query += ' AND e.name LIKE ?';
      args.add('%$search%');
    }
    if (favorites == true) {
      query += ' AND e.is_favorite = 1';
    }

    query += ' ORDER BY ec.order_index ASC, e.name ASC';
    return db.rawQuery(query, args);
  }

  /// Last trained date and session count for every exercise that has been
  /// trained, in one query. Only finished workouts and completed non-warm-up
  /// sets count.
  Future<Map<String, ExerciseUsage>> getExerciseUsage() async {
    final db = await this.db;
    final rows = await db.rawQuery('''
      SELECT ee.exercise_id AS exercise_id,
        MAX(w.date) AS last_date,
        COUNT(DISTINCT w.id) AS sessions
      FROM exercise_entries ee
      JOIN workouts w ON w.id = ee.workout_id
      JOIN sets s ON s.exercise_entry_id = ee.id
      WHERE w.end_time IS NOT NULL AND s.is_complete = 1 AND s.is_warmup = 0
      GROUP BY ee.exercise_id
    ''');
    return {
      for (final row in rows)
        row['exercise_id'] as String: ExerciseUsage(
          exerciseId: row['exercise_id'] as String,
          lastDate: DateTime.tryParse((row['last_date'] as String?) ?? ''),
          sessions: (row['sessions'] as num?)?.toInt() ?? 0,
        ),
    };
  }

  Future<Map<String, dynamic>?> getExercise(String id) async {
    final db = await this.db;
    final result = await db.rawQuery(
      'SELECT e.*, ec.name as category_name, ec.color as category_color, ec.energy_system as category_energy '
      'FROM exercises e '
      'JOIN exercise_categories ec ON e.category_id = ec.id '
      'WHERE e.id = ?',
      [id],
    );
    return result.isEmpty ? null : result.first;
  }

  Future<String> addExercise({
    required String name,
    required String categoryId,
    String type = 'weightReps',
    String? notes,
    String? equipment,
    double? weightIncrement,
    int? defaultRestTime,
  }) async {
    final db = await this.db;
    final id = const Uuid().v4();
    await db.insert('exercises', {
      'id': id,
      'name': name,
      'category_id': categoryId,
      'type': type,
      'notes': notes,
      'equipment': equipment,
      'is_favorite': 0,
      'default_rest_time': defaultRestTime,
      'weight_increment': weightIncrement,
      'created_at': DateTime.now().toIso8601String(),
    });
    return id;
  }

  Future<void> updateExercise(
    String id, {
    String? name,
    String? categoryId,
    String? type,
    String? notes,
    String? equipment,
    double? weightIncrement,
    int? defaultRestTime,
  }) async {
    final db = await this.db;
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (categoryId != null) updates['category_id'] = categoryId;
    if (type != null) updates['type'] = type;
    if (notes != null) updates['notes'] = notes;
    if (equipment != null) updates['equipment'] = equipment;
    if (weightIncrement != null) updates['weight_increment'] = weightIncrement;
    if (defaultRestTime != null) updates['default_rest_time'] = defaultRestTime;
    if (updates.isNotEmpty) {
      await db.update('exercises', updates, where: 'id = ?', whereArgs: [id]);
    }
  }

  Future<void> toggleFavorite(String id) async {
    final db = await this.db;
    final ex = await getExercise(id);
    if (ex != null) {
      final current = (ex['is_favorite'] as int?) ?? 0;
      await db.update(
        'exercises',
        {'is_favorite': current == 0 ? 1 : 0},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  Future<void> deleteExercise(String id) async {
    final db = await this.db;
    await db.delete('exercises', where: 'id = ?', whereArgs: [id]);
  }
}
