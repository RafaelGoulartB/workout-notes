import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'seed_data.dart';

class DatabaseHelper {
  static const _dbName = 'life_notes_workout.db';
  static const _dbVersion = 4;

  static DatabaseHelper? _instance;
  static Database? _database;

  DatabaseHelper._();

  static DatabaseHelper get instance {
    _instance ??= DatabaseHelper._();
    return _instance!;
  }

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, _dbName);
    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      singleInstance: true,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Exercise categories
    await db.execute('''
      CREATE TABLE exercise_categories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        color INTEGER NOT NULL,
        order_index INTEGER NOT NULL DEFAULT 0,
        energy_system TEXT NOT NULL DEFAULT 'anaerobic'
      )
    ''');

    // Exercises
    await db.execute('''
      CREATE TABLE exercises (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        category_id TEXT NOT NULL,
        type TEXT NOT NULL DEFAULT 'weightReps',
        notes TEXT,
        equipment TEXT,
        is_favorite INTEGER NOT NULL DEFAULT 0,
        default_rest_time INTEGER,
        weight_increment REAL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (category_id) REFERENCES exercise_categories(id) ON DELETE CASCADE
      )
    ''');

    // Workouts
    await db.execute('''
      CREATE TABLE workouts (
        id TEXT PRIMARY KEY,
        date TEXT NOT NULL,
        start_time TEXT,
        end_time TEXT,
        duration_seconds INTEGER,
        comment TEXT,
        feeling_rating INTEGER,
        is_from_routine INTEGER NOT NULL DEFAULT 0,
        routine_id TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    // Exercise entries in a workout
    await db.execute('''
      CREATE TABLE exercise_entries (
        id TEXT PRIMARY KEY,
        workout_id TEXT NOT NULL,
        exercise_id TEXT NOT NULL,
        order_index INTEGER NOT NULL DEFAULT 0,
        superset_group_id TEXT,
        notes TEXT,
        rest_time_seconds INTEGER,
        FOREIGN KEY (workout_id) REFERENCES workouts(id) ON DELETE CASCADE,
        FOREIGN KEY (exercise_id) REFERENCES exercises(id) ON DELETE CASCADE
      )
    ''');

    // Sets
    await db.execute('''
      CREATE TABLE sets (
        id TEXT PRIMARY KEY,
        exercise_entry_id TEXT NOT NULL,
        weight REAL,
        reps INTEGER,
        distance REAL,
        time_seconds INTEGER,
        is_complete INTEGER NOT NULL DEFAULT 0,
        is_warmup INTEGER NOT NULL DEFAULT 0,
        rpe REAL,
        comment TEXT,
        order_index INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (exercise_entry_id) REFERENCES exercise_entries(id) ON DELETE CASCADE
      )
    ''');

    // Routines
    await db.execute('''
      CREATE TABLE routines (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        notes TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    // Routine days
    await db.execute('''
      CREATE TABLE routine_days (
        id TEXT PRIMARY KEY,
        routine_id TEXT NOT NULL,
        name TEXT,
        order_index INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (routine_id) REFERENCES routines(id) ON DELETE CASCADE
      )
    ''');

    // Routine exercises
    await db.execute('''
      CREATE TABLE routine_exercises (
        id TEXT PRIMARY KEY,
        routine_day_id TEXT NOT NULL,
        exercise_id TEXT NOT NULL,
        order_index INTEGER NOT NULL DEFAULT 0,
        superset_group_id TEXT,
        rest_time_seconds INTEGER,
        FOREIGN KEY (routine_day_id) REFERENCES routine_days(id) ON DELETE CASCADE,
        FOREIGN KEY (exercise_id) REFERENCES exercises(id) ON DELETE CASCADE
      )
    ''');

    // Predefined sets in routines
    await db.execute('''
      CREATE TABLE predefined_sets (
        id TEXT PRIMARY KEY,
        routine_exercise_id TEXT NOT NULL,
        weight REAL,
        reps INTEGER,
        distance REAL,
        time_seconds INTEGER,
        is_warmup INTEGER NOT NULL DEFAULT 0,
        order_index INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (routine_exercise_id) REFERENCES routine_exercises(id) ON DELETE CASCADE
      )
    ''');

    // Body measurements
    await db.execute('''
      CREATE TABLE body_measurements (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        value REAL NOT NULL,
        unit TEXT NOT NULL DEFAULT 'kg',
        date TEXT NOT NULL,
        comment TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    // App settings
    await db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // Indexes
    await db.execute('CREATE INDEX idx_workouts_date ON workouts(date)');
    await db.execute('CREATE INDEX idx_exercise_entries_workout ON exercise_entries(workout_id)');
    await db.execute('CREATE INDEX idx_sets_entry ON sets(exercise_entry_id)');
    await db.execute('CREATE INDEX idx_measurements_date ON body_measurements(date)');
    await db.execute('CREATE INDEX idx_measurements_type ON body_measurements(type)');

    // Seed data
    await _seedData(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try {
        await db.execute('ALTER TABLE exercise_entries ADD COLUMN rest_time_seconds INTEGER');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE routine_exercises ADD COLUMN rest_time_seconds INTEGER');
      } catch (_) {}
    }
    if (oldVersion < 3) {
      try {
        await db.execute('ALTER TABLE exercise_categories ADD COLUMN energy_system TEXT NOT NULL DEFAULT \'anaerobic\'');
      } catch (_) {}
    }
    if (oldVersion < 4) {
      // Add notification settings defaults for existing users
      final defaults = <String, String>{
        'notification_rest_timer_enabled': 'true',
        'notification_rest_timer_sound': 'true',
        'notification_rest_timer_vibration': 'true',
        'notification_workout_timer_enabled': 'true',
        'notification_workout_timer_sound': 'false',
        'notification_workout_timer_vibration': 'false',
      };
      for (final entry in defaults.entries) {
        try {
          await db.insert('app_settings',
              {'key': entry.key, 'value': entry.value},
              conflictAlgorithm: ConflictAlgorithm.ignore);
        } catch (_) {}
      }
    }
  }

  Future<void> _seedData(Database db) async {
    final batch = db.batch();

    // Insert categories
    for (final cat in SeedData.categories) {
      batch.insert('exercise_categories', {
        'id': cat['id'],
        'name': cat['name'],
        'color': cat['color'],
        'order_index': cat['order_index'],
        'energy_system': cat['energy_system'],
      });
    }

    // Insert exercises
    for (final ex in SeedData.exercises) {
      batch.insert('exercises', {
        'id': ex['id'],
        'name': ex['name'],
        'category_id': ex['category_id'],
        'type': ex['type'],
        'notes': ex['notes'],
        'equipment': ex['equipment'],
        'is_favorite': 0,
        'default_rest_time': ex['default_rest_time'],
        'weight_increment': ex['weight_increment'],
        'created_at': DateTime.now().toIso8601String(),
      });
    }

    // Insert default settings
    batch.insert('app_settings', {'key': 'unit_system', 'value': 'kg'});
    batch.insert('app_settings', {'key': 'theme_mode', 'value': 'system'});
    batch.insert('app_settings', {'key': 'keep_screen_on', 'value': 'false'});
    batch.insert('app_settings', {'key': 'default_rest_time', 'value': '90'});
    batch.insert('app_settings', {'key': 'auto_start_rest_timer', 'value': 'true'});
    batch.insert('app_settings', {'key': 'auto_start_workout_timer', 'value': 'false'});

    // Notification settings defaults
    batch.insert('app_settings', {'key': 'notification_rest_timer_enabled', 'value': 'true'});
    batch.insert('app_settings', {'key': 'notification_rest_timer_sound', 'value': 'true'});
    batch.insert('app_settings', {'key': 'notification_rest_timer_vibration', 'value': 'true'});
    batch.insert('app_settings', {'key': 'notification_workout_timer_enabled', 'value': 'true'});
    batch.insert('app_settings', {'key': 'notification_workout_timer_sound', 'value': 'false'});
    batch.insert('app_settings', {'key': 'notification_workout_timer_vibration', 'value': 'false'});

    await batch.commit(noResult: true);
  }

  // ===================================================================
  // SETTINGS
  // ===================================================================

  Future<String?> getSetting(String key) async {
    final db = await database;
    final result = await db.query('app_settings', where: 'key = ?', whereArgs: [key]);
    if (result.isEmpty) return null;
    return result.first['value'] as String;
  }

  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert('app_settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, String>> getAllSettings() async {
    final db = await database;
    final result = await db.query('app_settings');
    return {for (var row in result) row['key'] as String: row['value'] as String};
  }

  // ===================================================================
  // EXERCISE CATEGORIES
  // ===================================================================

  Future<List<Map<String, dynamic>>> getCategories() async {
    final db = await database;
    return db.query('exercise_categories', orderBy: 'order_index ASC');
  }

  Future<Map<String, dynamic>?> getCategory(String id) async {
    final db = await database;
    final result = await db.query('exercise_categories', where: 'id = ?', whereArgs: [id]);
    return result.isEmpty ? null : result.first;
  }

  Future<String> addCategory(String name, int color) async {
    final db = await database;
    final id = const Uuid().v4();
    final count = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM exercise_categories')) ?? 0;
    await db.insert('exercise_categories', {
      'id': id,
      'name': name,
      'color': color,
      'order_index': count,
    });
    return id;
  }

  Future<void> updateCategory(String id, String name, int color) async {
    final db = await database;
    await db.update('exercise_categories', {'name': name, 'color': color},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteCategory(String id) async {
    final db = await database;
    await db.delete('exercise_categories', where: 'id = ?', whereArgs: [id]);
  }

  // ===================================================================
  // EXERCISES
  // ===================================================================

  Future<List<Map<String, dynamic>>> getExercises({String? categoryId, String? search, bool? favorites}) async {
    final db = await database;
    var query = 'SELECT e.*, ec.name as category_name, ec.color as category_color, ec.energy_system as category_energy '
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

  Future<Map<String, dynamic>?> getExercise(String id) async {
    final db = await database;
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
    final db = await database;
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

  Future<void> updateExercise(String id, {
    String? name,
    String? categoryId,
    String? type,
    String? notes,
    String? equipment,
    double? weightIncrement,
    int? defaultRestTime,
  }) async {
    final db = await database;
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
    final db = await database;
    final ex = await getExercise(id);
    if (ex != null) {
      final current = (ex['is_favorite'] as int?) ?? 0;
      await db.update('exercises', {'is_favorite': current == 0 ? 1 : 0},
          where: 'id = ?', whereArgs: [id]);
    }
  }

  Future<void> deleteExercise(String id) async {
    final db = await database;
    await db.delete('exercises', where: 'id = ?', whereArgs: [id]);
  }

  // ===================================================================
  // WORKOUTS
  // ===================================================================

  Future<String> createWorkout({
    DateTime? date,
    String? routineId,
    List<Map<String, dynamic>>? exercises,
  }) async {
    final db = await database;
    final id = const Uuid().v4();
    final now = DateTime.now();
    await db.insert('workouts', {
      'id': id,
      'date': (date ?? now).toIso8601String().substring(0, 10),
      // start_time is set when user clicks "Iniciar" on the timer card
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
    final db = await database;
    final routineExercises = await getRoutineExercises(routineDayId);

    for (final re in routineExercises) {
      final entryId = const Uuid().v4();
      final count = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM exercise_entries WHERE workout_id = ?', [workoutId])
      ) ?? 0;

      await db.insert('exercise_entries', {
        'id': entryId,
        'workout_id': workoutId,
        'exercise_id': re['exercise_id'],
        'order_index': count,
        'rest_time_seconds': re['rest_time_seconds'],
      });

      final sets = await getPredefinedSets(re['id'] as String);
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

  Future<Map<String, dynamic>?> getWorkout(String id) async {
    final db = await database;
    final results = await db.query('workouts', where: 'id = ?', whereArgs: [id]);
    return results.isEmpty ? null : results.first;
  }

  Future<List<Map<String, dynamic>>> getWorkouts({
    DateTime? startDate,
    DateTime? endDate,
    int? limit,
    int? offset,
  }) async {
    final db = await database;
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
    final db = await database;
    final monthStr = month.toString().padLeft(2, '0');
    return db.rawQuery(
      "SELECT * FROM workouts WHERE date LIKE ? ORDER BY date DESC",
      ['$year-$monthStr%'],
    );
  }

  /// Returns the distinct categories with their colors for each date in a month.
  /// Used by the calendar to show colored dots per category.
  Future<Map<String, List<Map<String, dynamic>>>> getWorkoutCategoriesByDate(int year, int month) async {
    final db = await database;
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
    final db = await database;
    return db.rawQuery(
      'SELECT ee.*, e.name as exercise_name, e.category_id, '
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
    final db = await database;
    return db.query('sets',
        where: 'exercise_entry_id = ?',
        whereArgs: [exerciseEntryId],
        orderBy: 'order_index ASC');
  }

  Future<void> finishWorkout(String id, {String? comment, int? feelingRating}) async {
    final db = await database;
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
      if (comment != null) 'comment': comment,
      if (feelingRating != null) 'feeling_rating': feelingRating,
    }, where: 'id = ?', whereArgs: [id]);
  }

  /// Sets the start_time of a workout (timer start).
  Future<void> startWorkoutTimer(String id) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.update('workouts', {
      'start_time': now,
    }, where: 'id = ?', whereArgs: [id]);
  }

  /// Sets the end_time of a workout (timer stop) and calculates duration.
  Future<void> stopWorkoutTimer(String id) async {
    final db = await database;
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
    }, where: 'id = ?', whereArgs: [id]);
  }

  /// Clears both start_time and end_time of a workout (reset timer).
  Future<void> resetWorkoutTimer(String id) async {
    final db = await database;
    await db.update('workouts', {
      'start_time': null,
      'end_time': null,
      'duration_seconds': null,
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateWorkoutDate(String id, DateTime newDate) async {
    final db = await database;
    await db.update('workouts', {
      'date': newDate.toIso8601String().substring(0, 10),
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> resetWorkoutToInProgress(String id) async {
    final db = await database;
    await db.update('workouts', {
      'end_time': null,
      'duration_seconds': null,
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteWorkout(String id) async {
    final db = await database;
    await db.delete('workouts', where: 'id = ?', whereArgs: [id]);
  }

  // ===================================================================
  // SETS (real-time operations during workout)
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
    final db = await database;
    final id = const Uuid().v4();
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM sets WHERE exercise_entry_id = ?', [exerciseEntryId])
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
    final db = await database;
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
    final db = await database;
    final result = await db.query('sets', where: 'id = ?', whereArgs: [setId]);
    if (result.isEmpty) return;
    final current = (result.first['is_complete'] as int?) ?? 0;
    await db.update('sets', {'is_complete': current == 0 ? 1 : 0},
        where: 'id = ?', whereArgs: [setId]);
  }

  Future<void> deleteSet(String setId) async {
    final db = await database;
    await db.delete('sets', where: 'id = ?', whereArgs: [setId]);
  }

  Future<void> removeExerciseEntryFromWorkout(String workoutId, String exerciseId) async {
    final db = await database;
    // Find the entry
    final entries = await db.query('exercise_entries',
        where: 'workout_id = ? AND exercise_id = ?',
        whereArgs: [workoutId, exerciseId]);
    for (final entry in entries) {
      final entryId = entry['id'] as String;
      // Delete all sets for this entry
      await db.delete('sets', where: 'exercise_entry_id = ?', whereArgs: [entryId]);
      // Delete the entry
      await db.delete('exercise_entries', where: 'id = ?', whereArgs: [entryId]);
    }
  }

  Future<void> updateExerciseEntryRestTime(String exerciseEntryId, int restTimeSeconds) async {
    final db = await database;
    await db.update('exercise_entries',
      {'rest_time_seconds': restTimeSeconds},
      where: 'id = ?', whereArgs: [exerciseEntryId]);
  }

  /// Returns the sets from the **single most recent** workout that had this
  /// exercise, excluding [excludeWorkoutId] (the current workout).
  Future<List<Map<String, dynamic>>> getLastWorkoutSets(
      String exerciseId, {String? excludeWorkoutId}) async {
    final db = await database;

    // First, find the most recent workout ID that has this exercise
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

    // Then, get all sets from that single workout
    return db.rawQuery('''
      SELECT s.* FROM sets s
      JOIN exercise_entries ee ON s.exercise_entry_id = ee.id
      WHERE ee.exercise_id = ? AND ee.workout_id = ?
      ORDER BY s.order_index ASC
    ''', [exerciseId, workoutId]);
  }

  // ===================================================================
  // ROUTINES
  // ===================================================================

  Future<String> createRoutine(String name, {String? notes}) async {
    final db = await database;
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
    final db = await database;
    return db.query('routines', orderBy: 'created_at DESC');
  }

  Future<Map<String, dynamic>?> getRoutine(String id) async {
    final db = await database;
    final result = await db.query('routines', where: 'id = ?', whereArgs: [id]);
    return result.isEmpty ? null : result.first;
  }

  Future<void> updateRoutine(String id, {String? name, String? notes}) async {
    final db = await database;
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (notes != null) updates['notes'] = notes;
    if (updates.isNotEmpty) {
      await db.update('routines', updates, where: 'id = ?', whereArgs: [id]);
    }
  }

  Future<void> deleteRoutine(String id) async {
    final db = await database;
    await db.delete('routines', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getRoutineDays(String routineId) async {
    final db = await database;
    return db.query('routine_days',
        where: 'routine_id = ?',
        whereArgs: [routineId],
        orderBy: 'order_index ASC');
  }

  Future<String> addRoutineDay(String routineId, String name) async {
    final db = await database;
    final id = const Uuid().v4();
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM routine_days WHERE routine_id = ?', [routineId])
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
    final db = await database;
    await db.delete('routine_days', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getRoutineExercises(String routineDayId) async {
    final db = await database;
    return db.rawQuery('''
      SELECT re.*, e.name as exercise_name, e.category_id,
      ec.name as category_name, ec.color as category_color, e.type as exercise_type
      FROM routine_exercises re
      JOIN exercises e ON re.exercise_id = e.id
      LEFT JOIN exercise_categories ec ON e.category_id = ec.id
      WHERE re.routine_day_id = ?
      ORDER BY re.order_index ASC
    ''', [routineDayId]);
  }

  Future<String> addRoutineExercise(String routineDayId, String exerciseId, {int? restTimeSeconds}) async {
    final db = await database;
    final id = const Uuid().v4();
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM routine_exercises WHERE routine_day_id = ?', [routineDayId])
    ) ?? 0;
    await db.insert('routine_exercises', {
      'id': id,
      'routine_day_id': routineDayId,
      'exercise_id': exerciseId,
      'order_index': count,
      if (restTimeSeconds != null) 'rest_time_seconds': restTimeSeconds,
    });
    return id;
  }

  Future<void> removeRoutineExercise(String id) async {
    final db = await database;
    await db.delete('routine_exercises', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateRoutineExerciseRestTime(String routineExerciseId, int restTimeSeconds) async {
    final db = await database;
    await db.update('routine_exercises',
      {'rest_time_seconds': restTimeSeconds},
      where: 'id = ?', whereArgs: [routineExerciseId]);
  }

  Future<List<Map<String, dynamic>>> getPredefinedSets(String routineExerciseId) async {
    final db = await database;
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
    final db = await database;
    final id = const Uuid().v4();
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM predefined_sets WHERE routine_exercise_id = ?', [routineExerciseId])
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
    final db = await database;
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
    final db = await database;
    await db.delete('predefined_sets', where: 'id = ?', whereArgs: [id]);
  }

  // ===================================================================
  // BODY MEASUREMENTS
  // ===================================================================

  Future<void> addBodyMeasurement(String type, double value, String unit, {DateTime? date, String? comment}) async {
    final db = await database;
    await db.insert('body_measurements', {
      'id': const Uuid().v4(),
      'type': type,
      'value': value,
      'unit': unit,
      'date': (date ?? DateTime.now()).toIso8601String().substring(0, 10),
      'comment': comment,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getBodyMeasurements({String? type, int? limit}) async {
    final db = await database;
    var where = '';
    var args = <dynamic>[];
    if (type != null) {
      where = 'WHERE type = ?';
      args = [type];
    }
    var query = 'SELECT * FROM body_measurements $where ORDER BY date DESC';
    if (limit != null) {
      query += ' LIMIT ?';
      args.add(limit);
    }
    return db.rawQuery(query, args);
  }

  Future<void> deleteBodyMeasurement(String id) async {
    final db = await database;
    await db.delete('body_measurements', where: 'id = ?', whereArgs: [id]);
  }

  // ===================================================================
  // STATISTICS & PROGRESS
  // ===================================================================

  Future<Map<String, dynamic>> getExerciseHistory(String exerciseId, {int? limit}) async {
    final db = await database;
    final query = '''
      SELECT s.*, w.date, ee.exercise_id
      FROM sets s
      JOIN exercise_entries ee ON s.exercise_entry_id = ee.id
      JOIN workouts w ON ee.workout_id = w.id
      WHERE ee.exercise_id = ? AND s.is_warmup = 0
      ORDER BY w.date ASC
    ''';

    final results = await db.rawQuery(query, [exerciseId]);
    final effectiveLimit = limit ?? results.length;

    // Group by date
    final Map<String, List<Map<String, dynamic>>> byDate = {};
    for (final row in results) {
      final date = row['date'] as String;
      byDate.putIfAbsent(date, () => []).add(row);
    }

    // Calculate stats per session
    final history = <Map<String, dynamic>>[];
    final entries = byDate.entries.toList();
    final recent = entries.reversed.take(effectiveLimit).toList().reversed.toList();

    for (final entry in recent) {
      final sets = entry.value;
      final weights = sets.map<double>((s) => (s['weight'] as num?)?.toDouble() ?? 0.0).toList();
      final reps = sets.map<int>((s) => (s['reps'] as int?) ?? 0).toList();
      final maxWeight = weights.isEmpty ? 0.0 : weights.reduce((a, b) => a > b ? a : b);
      final totalVolume = weights.asMap().entries.fold<double>(
        0.0, (sum, e) => sum + (e.value * reps[e.key]));
      final bestSetIndex = weights.indexOf(maxWeight);

      double? estimated1RM;
      if (maxWeight > 0 && reps[bestSetIndex] > 0) {
        // Epley formula: 1RM = weight * (1 + reps/30)
        estimated1RM = maxWeight * (1 + (reps[bestSetIndex] / 30));
      }

      history.add({
        'date': entry.key,
        'max_weight': maxWeight,
        'total_volume': totalVolume,
        'total_sets': sets.length,
        'total_reps': reps.fold<int>(0, (a, b) => a + b),
        'estimated_1rm': estimated1RM,
        'best_set': {
          'weight': maxWeight,
          'reps': reps[bestSetIndex],
        },
      });
    }

    // Best records
    double allMaxWeight = 0;
    double allMaxVolume = 0;
    if (history.isNotEmpty) {
      allMaxWeight = history
          .map((h) => (h['max_weight'] as num).toDouble())
          .reduce((a, b) => a > b ? a : b);
      allMaxVolume = history
          .map((h) => (h['total_volume'] as num).toDouble())
          .reduce((a, b) => a > b ? a : b);
    }

    return {
      'exercise_id': exerciseId,
      'history': history,
      'best_weight': allMaxWeight,
      'best_volume': allMaxVolume,
      'best_1rm': history.fold<double>(
        0, (a, b) => (b['estimated_1rm'] as double? ?? 0) > a
            ? (b['estimated_1rm'] as double? ?? 0) : a),
    };
  }

  Future<Map<String, dynamic>> getWeeklyVolume({int weeks = 4}) async {
    final db = await database;
    final now = DateTime.now();
    final results = <String, dynamic>{};

    for (int w = 0; w < weeks; w++) {
      final weekStart = now.subtract(Duration(days: now.weekday - 1 + (w * 7)));
      final weekEnd = weekStart.add(const Duration(days: 6));
      final startStr = weekStart.toIso8601String().substring(0, 10);
      final endStr = weekEnd.toIso8601String().substring(0, 10);

      final rows = await db.rawQuery('''
        SELECT ec.name as category, ec.color as color,
          SUM(s.weight * s.reps) as volume, COUNT(s.id) as total_sets
        FROM sets s
        JOIN exercise_entries ee ON s.exercise_entry_id = ee.id
        JOIN exercises e ON ee.exercise_id = e.id
        JOIN exercise_categories ec ON e.category_id = ec.id
        JOIN workouts w ON ee.workout_id = w.id
        WHERE w.date >= ? AND w.date <= ? AND s.is_warmup = 0
        GROUP BY ec.id
        ORDER BY volume DESC
      ''', [startStr, endStr]);

      results['week_${w + 1}'] = {
        'start': startStr,
        'end': endStr,
        'categories': rows,
      };
    }

    return results;
  }

  // ===================================================================
  // EXPORT / IMPORT
  // ===================================================================

  Future<Map<String, dynamic>> exportAllData() async {
    final db = await database;
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
    final db = await database;
    int count = 0;

    await db.transaction((txn) async {
      // Import in order respecting foreign keys
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
    final db = await database;
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
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('sets');
      await txn.delete('exercise_entries');
      await txn.delete('workouts');
    });
  }

  /// Counts consecutive workout days ending at today (or most recent day ≤ today).
  /// Does NOT count future dates.
  Future<int> _calculateStreak() async {
    final db = await database;
    final today = DateTime.now().toIso8601String().substring(0, 10);

    final rows = await db.rawQuery(
      'SELECT DISTINCT date FROM workouts WHERE date <= ? ORDER BY date DESC',
      [today],
    );

    if (rows.isEmpty) return 0;

    int streak = 1;
    // Parse the first (most recent) date as the starting point
    DateTime prev = DateTime.parse(rows[0]['date'] as String);

    for (int i = 1; i < rows.length; i++) {
      final curr = DateTime.parse(rows[i]['date'] as String);
      // Check if curr is exactly one day before prev
      if (prev.difference(curr).inDays == 1) {
        streak++;
        prev = curr;
      } else {
        break;
      }
    }

    return streak;
  }

  /// Returns overall workout stats for the progress overview.
  Future<Map<String, dynamic>> getWorkoutOverviewStats() async {
    final db = await database;

    final totalWorkouts = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM workouts',
    )) ?? 0;

    final totalSets = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM sets WHERE is_warmup = 0',
    )) ?? 0;

    final totalVolume = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COALESCE(SUM(weight * reps), 0) FROM sets WHERE is_warmup = 0',
    )) ?? 0;

    final currentStreak = await _calculateStreak();

    return {
      'total_workouts': totalWorkouts,
      'total_sets': totalSets,
      'total_volume': totalVolume,
      'current_streak': currentStreak,
    };
  }

  /// Returns monthly volume data for the overview chart.
  Future<List<Map<String, dynamic>>> getMonthlyVolume({int months = 6}) async {
    final db = await database;
    final now = DateTime.now();
    final results = <Map<String, dynamic>>[];

    for (int m = months - 1; m >= 0; m--) {
      final monthDate = DateTime(now.year, now.month - m, 1);
      final monthStr = '${monthDate.year}-${monthDate.month.toString().padLeft(2, '0')}';

      final row = await db.rawQuery('''
        SELECT COALESCE(SUM(s.weight * s.reps), 0) as volume,
          COUNT(DISTINCT w.id) as workouts
        FROM sets s
        JOIN exercise_entries ee ON s.exercise_entry_id = ee.id
        JOIN workouts w ON ee.workout_id = w.id
        WHERE w.date LIKE ? AND s.is_warmup = 0
      ''', ['$monthStr%']);

      if (row.isNotEmpty) {
        results.add({
          'month': '$monthStr-01',
          'volume': (row.first['volume'] as num?)?.toDouble() ?? 0,
          'workouts': row.first['workouts'] as int? ?? 0,
        });
      }
    }

    return results;
  }

  // ===================================================================
  // PROGRESS — FREQUENCY & CONSISTENCY
  // ===================================================================

  /// Returns daily workout data for the year (heatmap).
  Future<Map<String, int>> getYearlyHeatmapData(int year) async {
    final db = await database;
    final startDate = '$year-01-01';
    final endDate = '$year-12-31';
    final rows = await db.rawQuery('''
      SELECT w.date, COALESCE(SUM(s.weight * s.reps), 0) as volume
      FROM workouts w
      LEFT JOIN exercise_entries ee ON w.id = ee.workout_id
      LEFT JOIN sets s ON ee.id = s.exercise_entry_id AND s.is_warmup = 0
      WHERE w.date >= ? AND w.date <= ?
      GROUP BY w.date
      ORDER BY w.date
    ''', [startDate, endDate]);

    final Map<String, int> result = {};
    for (final row in rows) {
      result[row['date'] as String] = ((row['volume'] as num?)?.toDouble() ?? 0).toInt();
    }
    return result;
  }

  /// Returns workout dates within a range for frequency analysis.
  Future<List<Map<String, dynamic>>> getWorkoutDatesInRange(DateTime start) async {
    final db = await database;
    final startStr = start.toIso8601String().substring(0, 10);
    return db.rawQuery('''
      SELECT date, duration_seconds, start_time,
        CAST(strftime('%w', date) AS INTEGER) as day_of_week
      FROM workouts
      WHERE date >= ?
      ORDER BY date ASC
    ''', [startStr]);
  }

  // ===================================================================
  // PROGRESS — VOLUME & MUSCLE GROUPS
  // ===================================================================

  /// Returns total volume per exercise category.
  Future<List<Map<String, dynamic>>> getVolumeByCategory() async {
    final db = await database;
    return db.rawQuery('''
      SELECT ec.id, ec.name, ec.color, ec.energy_system,
        COALESCE(SUM(s.weight * s.reps), 0) as volume,
        COUNT(s.id) as sets_count
      FROM exercise_categories ec
      JOIN exercises e ON e.category_id = ec.id
      JOIN exercise_entries ee ON ee.exercise_id = e.id
      JOIN sets s ON s.exercise_entry_id = ee.id AND s.is_warmup = 0
      GROUP BY ec.id
      ORDER BY volume DESC
    ''');
  }

  /// Returns weekly volume broken down by category for stacked chart.
  Future<List<Map<String, dynamic>>> getWeeklyVolumeByCategory({int weeks = 12}) async {
    final db = await database;
    final start = DateTime.now().subtract(Duration(days: weeks * 7))
        .toIso8601String().substring(0, 10);
    return db.rawQuery('''
      SELECT w.date, ec.id as category_id, ec.name as category_name,
        ec.color as category_color,
        COALESCE(SUM(s.weight * s.reps), 0) as volume
      FROM workouts w
      JOIN exercise_entries ee ON w.id = ee.workout_id
      JOIN exercises e ON ee.exercise_id = e.id
      JOIN exercise_categories ec ON e.category_id = ec.id
      JOIN sets s ON s.exercise_entry_id = ee.id AND s.is_warmup = 0
      WHERE w.date >= ?
      GROUP BY w.date, ec.id
      ORDER BY w.date
    ''', [start]);
  }

  /// Returns top exercises by total volume.
  Future<List<Map<String, dynamic>>> getTopExercisesByVolume({int limit = 10}) async {
    final db = await database;
    return db.rawQuery('''
      SELECT e.id, e.name, ec.name as category_name, ec.color as category_color,
        COALESCE(SUM(s.weight * s.reps), 0) as volume,
        COUNT(s.id) as sets_count
      FROM exercises e
      JOIN exercise_categories ec ON e.category_id = ec.id
      JOIN exercise_entries ee ON ee.exercise_id = e.id
      JOIN sets s ON s.exercise_entry_id = ee.id AND s.is_warmup = 0
      GROUP BY e.id
      ORDER BY volume DESC
      LIMIT ?
    ''', [limit]);
  }

  /// Returns distribution of energy systems (aerobic vs anaerobic).
  Future<List<Map<String, dynamic>>> getEnergySystemDistribution() async {
    final db = await database;
    return db.rawQuery('''
      SELECT ec.energy_system,
        COALESCE(SUM(s.weight * s.reps), 0) as volume,
        COUNT(s.id) as sets_count
      FROM exercise_categories ec
      JOIN exercises e ON e.category_id = ec.id
      JOIN exercise_entries ee ON ee.exercise_id = e.id
      JOIN sets s ON s.exercise_entry_id = ee.id AND s.is_warmup = 0
      GROUP BY ec.energy_system
    ''');
  }

  // ===================================================================
  // PROGRESS — PERFORMANCE & INTENSITY
  // ===================================================================

  /// Returns average RPE per workout over time.
  Future<List<Map<String, dynamic>>> getRpeTrend({int limit = 50}) async {
    final db = await database;
    return db.rawQuery('''
      SELECT w.date, AVG(s.rpe) as avg_rpe,
        COUNT(s.id) as sets_with_rpe
      FROM sets s
      JOIN exercise_entries ee ON s.exercise_entry_id = ee.id
      JOIN workouts w ON ee.workout_id = w.id
      WHERE s.rpe IS NOT NULL AND s.is_warmup = 0
      GROUP BY w.id
      ORDER BY w.date DESC
      LIMIT ?
    ''', [limit]);
  }

  /// Returns workout density (volume per minute) over time.
  Future<List<Map<String, dynamic>>> getWorkoutDensity({int limit = 50}) async {
    final db = await database;
    return db.rawQuery('''
      SELECT w.date, w.duration_seconds,
        COALESCE(SUM(s.weight * s.reps), 0) as volume
      FROM workouts w
      JOIN exercise_entries ee ON w.id = ee.workout_id
      JOIN sets s ON s.exercise_entry_id = ee.id AND s.is_warmup = 0
      WHERE w.duration_seconds IS NOT NULL AND w.duration_seconds > 0
      GROUP BY w.id
      ORDER BY w.date DESC
      LIMIT ?
    ''', [limit]);
  }

  /// Returns personal records (best set by weight) per exercise.
  Future<List<Map<String, dynamic>>> getPersonalRecords({int limit = 20}) async {
    final db = await database;
    return db.rawQuery('''
      SELECT e.id as exercise_id, e.name as exercise_name,
        ec.name as category_name, ec.color as category_color,
        MAX(s.weight) as best_weight,
        (SELECT s2.reps FROM sets s2
          JOIN exercise_entries ee2 ON s2.exercise_entry_id = ee2.id
          WHERE ee2.exercise_id = e.id AND s2.is_warmup = 0
          AND s2.weight = (SELECT MAX(s3.weight) FROM sets s3
            JOIN exercise_entries ee3 ON s3.exercise_entry_id = ee3.id
            WHERE ee3.exercise_id = e.id AND s3.is_warmup = 0)
          LIMIT 1
        ) as best_reps,
        (SELECT w2.date FROM sets s2
          JOIN exercise_entries ee2 ON s2.exercise_entry_id = ee2.id
          JOIN workouts w2 ON ee2.workout_id = w2.id
          WHERE ee2.exercise_id = e.id AND s2.is_warmup = 0
          AND s2.weight = (SELECT MAX(s3.weight) FROM sets s3
            JOIN exercise_entries ee3 ON s3.exercise_entry_id = ee3.id
            WHERE ee3.exercise_id = e.id AND s3.is_warmup = 0)
          LIMIT 1
        ) as date
      FROM exercises e
      JOIN exercise_categories ec ON e.category_id = ec.id
      JOIN exercise_entries ee ON ee.exercise_id = e.id
      JOIN sets s ON s.exercise_entry_id = ee.id AND s.is_warmup = 0
      GROUP BY e.id
      HAVING best_weight > 0
      ORDER BY best_weight DESC
      LIMIT ?
    ''', [limit]);
  }

  // ===================================================================
  // PROGRESS — RECOVERY & FEELING
  // ===================================================================

  /// Returns feeling ratings over time.
  Future<List<Map<String, dynamic>>> getFeelingTrend({int limit = 50}) async {
    final db = await database;
    return db.rawQuery('''
      SELECT date, feeling_rating, duration_seconds
      FROM workouts
      WHERE feeling_rating IS NOT NULL
      ORDER BY date DESC
      LIMIT ?
    ''', [limit]);
  }

  /// Returns average volume grouped by feeling rating.
  Future<List<Map<String, dynamic>>> getFeelingVsVolume() async {
    final db = await database;
    return db.rawQuery('''
      SELECT w.feeling_rating,
        AVG(s.weight * s.reps) as avg_volume,
        COUNT(DISTINCT w.id) as workout_count
      FROM workouts w
      JOIN exercise_entries ee ON w.id = ee.workout_id
      JOIN sets s ON s.exercise_entry_id = ee.id AND s.is_warmup = 0
      WHERE w.feeling_rating IS NOT NULL
      GROUP BY w.feeling_rating
      ORDER BY w.feeling_rating
    ''');
  }

  // ===================================================================
  // PROGRESS — DURATION
  // ===================================================================

  /// Returns workout durations over time.
  Future<List<Map<String, dynamic>>> getDurationTrend({int limit = 50}) async {
    final db = await database;
    return db.rawQuery('''
      SELECT date, duration_seconds
      FROM workouts
      WHERE duration_seconds IS NOT NULL AND duration_seconds > 0
      ORDER BY date DESC
      LIMIT ?
    ''', [limit]);
  }

  // ===================================================================
  // PROGRESS — BODY MEASUREMENTS
  // ===================================================================

  /// Returns body weight measurements with nearby workout volume for overlay.
  Future<List<Map<String, dynamic>>> getBodyWeightWithVolume({int months = 6}) async {
    final db = await database;
    final start = DateTime.now().subtract(Duration(days: months * 30))
        .toIso8601String().substring(0, 10);
    return db.rawQuery('''
      SELECT bm.date, bm.value as weight, bm.unit,
        (SELECT COALESCE(SUM(s2.weight * s2.reps), 0)
         FROM workouts w2
         JOIN exercise_entries ee2 ON w2.id = ee2.workout_id
         JOIN sets s2 ON s2.exercise_entry_id = ee2.id AND s2.is_warmup = 0
         WHERE w2.date = bm.date
        ) as volume
      FROM body_measurements bm
      WHERE bm.type = 'weight' AND bm.date >= ?
      ORDER BY bm.date ASC
    ''', [start]);
  }

  // ===================================================================
  // PROGRESS — MONTHLY REPORT
  // ===================================================================

  /// Returns a comprehensive monthly report.
  Future<Map<String, dynamic>> getMonthlyReport(int year, int month) async {
    final db = await database;
    final monthStr = '$year-${month.toString().padLeft(2, '0')}';

    final workouts = await db.rawQuery('''
      SELECT COUNT(*) as count,
        COALESCE(SUM(duration_seconds), 0) as total_duration,
        AVG(feeling_rating) as avg_feeling,
        COUNT(CASE WHEN feeling_rating IS NOT NULL THEN 1 END) as feeling_count
      FROM workouts
      WHERE date LIKE ?
    ''', ['$monthStr%']);

    final volume = await db.rawQuery('''
      SELECT COALESCE(SUM(s.weight * s.reps), 0) as total_volume,
        COUNT(s.id) as total_sets
      FROM sets s
      JOIN exercise_entries ee ON s.exercise_entry_id = ee.id
      JOIN workouts w ON ee.workout_id = w.id
      WHERE w.date LIKE ? AND s.is_warmup = 0
    ''', ['$monthStr%']);

    final categoryVol = await db.rawQuery('''
      SELECT ec.name, ec.color, COALESCE(SUM(s.weight * s.reps), 0) as volume
      FROM exercise_categories ec
      JOIN exercises e ON e.category_id = ec.id
      JOIN exercise_entries ee ON ee.exercise_id = e.id
      JOIN sets s ON s.exercise_entry_id = ee.id AND s.is_warmup = 0
      JOIN workouts w ON ee.workout_id = w.id
      WHERE w.date LIKE ?
      GROUP BY ec.id
      ORDER BY volume DESC
    ''', ['$monthStr%']);

    final daysWithWorkouts = Sqflite.firstIntValue(await db.rawQuery('''
      SELECT COUNT(DISTINCT date) FROM workouts WHERE date LIKE ?
    ''', ['$monthStr%'])) ?? 0;

    return {
      'workout_count': (workouts.first['count'] as int?) ?? 0,
      'total_duration': (workouts.first['total_duration'] as int?) ?? 0,
      'avg_feeling': (workouts.first['avg_feeling'] as num?)?.toDouble(),
      'total_volume': (volume.first['total_volume'] as num?)?.toDouble() ?? 0,
      'total_sets': (volume.first['total_sets'] as int?) ?? 0,
      'days_with_workouts': daysWithWorkouts,
      'categories': categoryVol,
    };
  }

  /// Returns comparison data between two months.
  Future<Map<String, dynamic>> getMonthComparison(int year, int month) async {
    final current = await getMonthlyReport(year, month);

    DateTime prevDate;
    if (month == 1) {
      prevDate = DateTime(year - 1, 12, 1);
    } else {
      prevDate = DateTime(year, month - 1, 1);
    }
    final previous = await getMonthlyReport(prevDate.year, prevDate.month);

    return {
      'current': current,
      'previous': previous,
      'delta_workouts': (current['workout_count'] as int) - (previous['workout_count'] as int),
      'delta_volume': (current['total_volume'] as double) - (previous['total_volume'] as double),
      'delta_sets': (current['total_sets'] as int) - (previous['total_sets'] as int),
    };
  }
}
