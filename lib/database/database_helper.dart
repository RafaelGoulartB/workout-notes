import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'seed_data.dart';
import '../repositories/settings_repository.dart';
import '../repositories/exercise_repository.dart';
import '../repositories/workout_repository.dart';
import '../repositories/routine_repository.dart';
import '../repositories/body_measurement_repository.dart';
import '../repositories/analytics_repository.dart';
import '../repositories/export_import_repository.dart';

class DatabaseHelper {
  static const _dbName = 'workout_notes.db';
  static const _dbVersion = 8;

  static DatabaseHelper? _instance;
  static Database? _database;

  /// Repository instances (lazy-loaded)
  late final SettingsRepository settingsRepo = SettingsRepository();
  late final ExerciseRepository exerciseRepo = ExerciseRepository();
  late final WorkoutRepository workoutRepo = WorkoutRepository();
  late final RoutineRepository routineRepo = RoutineRepository();
  late final BodyMeasurementRepository bodyMeasurementRepo = BodyMeasurementRepository();
  late final AnalyticsRepository analyticsRepo = AnalyticsRepository();
  late final ExportImportRepository exportImportRepo = ExportImportRepository();

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
        time_of_day TEXT,
        is_fasted INTEGER DEFAULT 0,
        photos_paths TEXT,
        side TEXT,
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
    if (oldVersion < 5) {
      try {
        await db.execute('ALTER TABLE body_measurements ADD COLUMN time_of_day TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE body_measurements ADD COLUMN is_fasted INTEGER DEFAULT 0');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE body_measurements ADD COLUMN photos_paths TEXT');
      } catch (_) {}
    }
    if (oldVersion < 6) {
      try {
        await db.execute('ALTER TABLE exercises ADD COLUMN locale_key TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE exercise_categories ADD COLUMN locale_key TEXT');
      } catch (_) {}
      final seedIds = [
        'bench_press','incl_bench','decl_bench','db_bench','db_incl',
        'cable_fly','pec_deck','pushup','chest_dip','sm_bench',
        'pullup','chinup','lat_pulldown','bent_row','db_row',
        'seated_row','tbar_row','face_pull','deadlift','rdl','hyperextension',
        'ohp','db_ohp','lat_raise','front_raise','rear_delt_fly',
        'upright_row','arnold_press','shrug',
        'bb_curl','db_curl','hammer_curl','preacher_curl','cable_curl','concentration_curl',
        'triceps_pushdown','skull_crusher','close_grip','triceps_extension','bench_dip','kickback',
        'squat','front_squat','leg_press','romanian_dl','leg_curl','leg_ext',
        'bulgarian_split','lunge','calf_raise','goblet_squat','hack_squat','hip_thrust',
        'crunch','leg_raise','plank','russian_twist','cable_crunch','ab_roller','hanging_raise',
        'treadmill','cycling','jump_rope','rowing','swimming','walking','running',
      ];
      for (final id in seedIds) {
        try {
          await db.rawUpdate(
            'UPDATE exercises SET locale_key = ? WHERE id = ?',
            [id, id],
          );
        } catch (_) {}
      }
      final catIds = ['chest','back','shoulders','biceps','triceps','legs','core','cardio','fullbody'];
      for (final id in catIds) {
        try {
          await db.rawUpdate(
            'UPDATE exercise_categories SET locale_key = ? WHERE id = ?',
            [id, id],
          );
        } catch (_) {}
      }
    }
    if (oldVersion < 7) {
      try {
        await db.insert('exercises', {
          'id': 'running',
          'name': 'Corrida',
          'locale_key': 'running',
          'category_id': 'cardio',
          'type': 'distanceTime',
          'notes': 'Corrida ao ar livre ou esteira',
          'equipment': 'Bodyweight',
          'is_favorite': 0,
          'default_rest_time': 0,
          'weight_increment': 0,
          'created_at': DateTime.now().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      } catch (_) {}
    }
    if (oldVersion < 8) {
      try {
        await db.execute('ALTER TABLE body_measurements ADD COLUMN side TEXT');
      } catch (_) {}
    }
  }

  Future<void> _seedData(Database db) async {
    final batch = db.batch();

    for (final cat in SeedData.categories) {
      batch.insert('exercise_categories', {
        'id': cat['id'],
        'name': cat['name'],
        'locale_key': cat['locale_key'],
        'color': cat['color'],
        'order_index': cat['order_index'],
        'energy_system': cat['energy_system'],
      });
    }

    for (final ex in SeedData.exercises) {
      batch.insert('exercises', {
        'id': ex['id'],
        'name': ex['name'],
        'locale_key': ex['locale_key'],
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

    batch.insert('app_settings', {'key': 'unit_system', 'value': 'kg'});
    batch.insert('app_settings', {'key': 'theme_mode', 'value': 'system'});
    batch.insert('app_settings', {'key': 'keep_screen_on', 'value': 'false'});
    batch.insert('app_settings', {'key': 'default_rest_time', 'value': '90'});
    batch.insert('app_settings', {'key': 'auto_start_rest_timer', 'value': 'true'});
    batch.insert('app_settings', {'key': 'auto_start_workout_timer', 'value': 'false'});
    batch.insert('app_settings', {'key': 'notification_rest_timer_enabled', 'value': 'true'});
    batch.insert('app_settings', {'key': 'notification_rest_timer_sound', 'value': 'true'});
    batch.insert('app_settings', {'key': 'notification_rest_timer_vibration', 'value': 'true'});
    batch.insert('app_settings', {'key': 'notification_workout_timer_enabled', 'value': 'true'});
    batch.insert('app_settings', {'key': 'notification_workout_timer_sound', 'value': 'false'});
    batch.insert('app_settings', {'key': 'notification_workout_timer_vibration', 'value': 'false'});

    await batch.commit(noResult: true);
  }

  // ===================================================================
  // DELEGATION METHODS (backward compatibility)
  // ===================================================================
  // These methods delegate to the appropriate repository.
  // Screens should migrate to using the repositories directly.
  // ===================================================================

  // -- SETTINGS --
  Future<String?> getSetting(String key) => settingsRepo.getSetting(key);
  Future<void> setSetting(String key, String value) => settingsRepo.setSetting(key, value);
  Future<Map<String, String>> getAllSettings() => settingsRepo.getAllSettings();

  // -- CATEGORIES --
  Future<List<Map<String, dynamic>>> getCategories() => exerciseRepo.getCategories();
  Future<Map<String, dynamic>?> getCategory(String id) => exerciseRepo.getCategory(id);
  Future<String> addCategory(String name, int color) => exerciseRepo.addCategory(name, color);
  Future<void> updateCategory(String id, String name, int color) => exerciseRepo.updateCategory(id, name, color);
  Future<void> deleteCategory(String id) => exerciseRepo.deleteCategory(id);

  // -- EXERCISES --
  Future<List<Map<String, dynamic>>> getExercises({String? categoryId, String? search, bool? favorites}) =>
      exerciseRepo.getExercises(categoryId: categoryId, search: search, favorites: favorites);
  Future<Map<String, dynamic>?> getExercise(String id) => exerciseRepo.getExercise(id);
  Future<String> addExercise({required String name, required String categoryId, String type = 'weightReps', String? notes, String? equipment, double? weightIncrement, int? defaultRestTime}) =>
      exerciseRepo.addExercise(name: name, categoryId: categoryId, type: type, notes: notes, equipment: equipment, weightIncrement: weightIncrement, defaultRestTime: defaultRestTime);
  Future<void> updateExercise(String id, {String? name, String? categoryId, String? type, String? notes, String? equipment, double? weightIncrement, int? defaultRestTime}) =>
      exerciseRepo.updateExercise(id, name: name, categoryId: categoryId, type: type, notes: notes, equipment: equipment, weightIncrement: weightIncrement, defaultRestTime: defaultRestTime);
  Future<void> toggleFavorite(String id) => exerciseRepo.toggleFavorite(id);
  Future<void> deleteExercise(String id) => exerciseRepo.deleteExercise(id);

  // -- WORKOUTS --
  Future<String> createWorkout({DateTime? date, String? routineId, List<Map<String, dynamic>>? exercises}) =>
      workoutRepo.createWorkout(date: date, routineId: routineId, exercises: exercises);
  Future<void> importRoutineDayToWorkout(String workoutId, String routineDayId) =>
      workoutRepo.importRoutineDayToWorkout(workoutId, routineDayId);
  Future<String> copyWorkoutToDate(String sourceWorkoutId, DateTime newDate) =>
      workoutRepo.copyWorkoutToDate(sourceWorkoutId, newDate);
  Future<Map<String, dynamic>?> getWorkout(String id) => workoutRepo.getWorkout(id);
  Future<List<Map<String, dynamic>>> getWorkouts({DateTime? startDate, DateTime? endDate, int? limit, int? offset}) =>
      workoutRepo.getWorkouts(startDate: startDate, endDate: endDate, limit: limit, offset: offset);
  Future<List<Map<String, dynamic>>> getWorkoutsByMonth(int year, int month) =>
      workoutRepo.getWorkoutsByMonth(year, month);
  Future<Map<String, List<Map<String, dynamic>>>> getWorkoutCategoriesByDate(int year, int month) =>
      workoutRepo.getWorkoutCategoriesByDate(year, month);
  Future<List<Map<String, dynamic>>> getWorkoutExercises(String workoutId) =>
      workoutRepo.getWorkoutExercises(workoutId);
  Future<List<Map<String, dynamic>>> getExerciseSets(String exerciseEntryId) =>
      workoutRepo.getExerciseSets(exerciseEntryId);
  Future<void> finishWorkout(String id, {String? comment, int? feelingRating}) =>
      workoutRepo.finishWorkout(id, comment: comment, feelingRating: feelingRating);
  Future<void> startWorkoutTimer(String id) => workoutRepo.startWorkoutTimer(id);
  Future<void> stopWorkoutTimer(String id) => workoutRepo.stopWorkoutTimer(id);
  Future<void> resetWorkoutTimer(String id) => workoutRepo.resetWorkoutTimer(id);
  Future<void> updateWorkoutDate(String id, DateTime newDate) => workoutRepo.updateWorkoutDate(id, newDate);
  Future<void> resetWorkoutToInProgress(String id) => workoutRepo.resetWorkoutToInProgress(id);
  Future<void> deleteWorkout(String id) => workoutRepo.deleteWorkout(id);

  // -- SETS --
  Future<String> addSet({required String exerciseEntryId, double? weight, int? reps, double? distance, int? timeSeconds, bool isWarmup = false, double? rpe, String? comment}) =>
      workoutRepo.addSet(exerciseEntryId: exerciseEntryId, weight: weight, reps: reps, distance: distance, timeSeconds: timeSeconds, isWarmup: isWarmup, rpe: rpe, comment: comment);
  Future<void> updateSet(String setId, {double? weight, int? reps, double? distance, int? timeSeconds, bool? isComplete, bool? isWarmup, double? rpe, String? comment}) =>
      workoutRepo.updateSet(setId, weight: weight, reps: reps, distance: distance, timeSeconds: timeSeconds, isComplete: isComplete, isWarmup: isWarmup, rpe: rpe, comment: comment);
  Future<void> toggleSetComplete(String setId) => workoutRepo.toggleSetComplete(setId);
  Future<void> deleteSet(String setId) => workoutRepo.deleteSet(setId);
  Future<void> removeExerciseEntryFromWorkout(String workoutId, String exerciseId) =>
      workoutRepo.removeExerciseEntryFromWorkout(workoutId, exerciseId);
  Future<void> deleteExerciseEntry(String entryId) => workoutRepo.deleteExerciseEntry(entryId);
  Future<void> updateExerciseEntryRestTime(String exerciseEntryId, int restTimeSeconds) =>
      workoutRepo.updateExerciseEntryRestTime(exerciseEntryId, restTimeSeconds);
  Future<List<Map<String, dynamic>>> getLastWorkoutSets(String exerciseId, {String? excludeWorkoutId}) =>
      workoutRepo.getLastWorkoutSets(exerciseId, excludeWorkoutId: excludeWorkoutId);

  // -- ROUTINES --
  Future<String> createRoutine(String name, {String? notes}) => routineRepo.createRoutine(name, notes: notes);
  Future<List<Map<String, dynamic>>> getRoutines() => routineRepo.getRoutines();
  Future<Map<String, dynamic>?> getRoutine(String id) => routineRepo.getRoutine(id);
  Future<void> updateRoutine(String id, {String? name, String? notes}) => routineRepo.updateRoutine(id, name: name, notes: notes);
  Future<void> deleteRoutine(String id) => routineRepo.deleteRoutine(id);
  Future<List<Map<String, dynamic>>> getRoutineDays(String routineId) => routineRepo.getRoutineDays(routineId);
  Future<String> addRoutineDay(String routineId, String name) => routineRepo.addRoutineDay(routineId, name);
  Future<void> deleteRoutineDay(String id) => routineRepo.deleteRoutineDay(id);
  Future<List<Map<String, dynamic>>> getRoutineExercises(String routineDayId) => routineRepo.getRoutineExercises(routineDayId);
  Future<String> addRoutineExercise(String routineDayId, String exerciseId, {int? restTimeSeconds}) =>
      routineRepo.addRoutineExercise(routineDayId, exerciseId, restTimeSeconds: restTimeSeconds);
  Future<void> removeRoutineExercise(String id) => routineRepo.removeRoutineExercise(id);
  Future<void> updateRoutineExerciseRestTime(String routineExerciseId, int restTimeSeconds) =>
      routineRepo.updateRoutineExerciseRestTime(routineExerciseId, restTimeSeconds);
  Future<List<Map<String, dynamic>>> getPredefinedSets(String routineExerciseId) => routineRepo.getPredefinedSets(routineExerciseId);
  Future<String> addPredefinedSet(String routineExerciseId, {double? weight, int? reps, double? distance, int? timeSeconds, bool isWarmup = false}) =>
      routineRepo.addPredefinedSet(routineExerciseId, weight: weight, reps: reps, distance: distance, timeSeconds: timeSeconds, isWarmup: isWarmup);
  Future<void> updatePredefinedSet(String id, {double? weight, int? reps, double? distance, int? timeSeconds, bool? isWarmup}) =>
      routineRepo.updatePredefinedSet(id, weight: weight, reps: reps, distance: distance, timeSeconds: timeSeconds, isWarmup: isWarmup);
  Future<void> deletePredefinedSet(String id) => routineRepo.deletePredefinedSet(id);

  // -- BODY MEASUREMENTS --
  Future<void> addBodyMeasurement(String type, double value, String unit, {DateTime? date, String? comment, String? timeOfDay, bool isFasted = false, List<String>? photosPaths, String? side}) =>
      bodyMeasurementRepo.addBodyMeasurement(type, value, unit, date: date, comment: comment, timeOfDay: timeOfDay, isFasted: isFasted, photosPaths: photosPaths, side: side);
  Future<void> addBodyMeasurementsBatch(List<Map<String, dynamic>> measurements) =>
      bodyMeasurementRepo.addBodyMeasurementsBatch(measurements);
  Future<List<Map<String, dynamic>>> getBodyMeasurements({String? type, int? limit}) =>
      bodyMeasurementRepo.getBodyMeasurements(type: type, limit: limit);
  Future<void> deleteBodyMeasurement(String id) => bodyMeasurementRepo.deleteBodyMeasurement(id);
  Future<List<Map<String, dynamic>>> getBodyMeasurementsSummary() => bodyMeasurementRepo.getBodyMeasurementsSummary();
  Future<Map<String, dynamic>?> getPreviousBodyMeasurement(String type, {String? beforeDate}) =>
      bodyMeasurementRepo.getPreviousBodyMeasurement(type, beforeDate: beforeDate);
  Future<List<Map<String, dynamic>>> getBodyMeasurementsTrend(String type, {int months = 6}) =>
      bodyMeasurementRepo.getBodyMeasurementsTrend(type, months: months);
  Future<List<Map<String, dynamic>>> getBodyMeasurementsByDate(String date) =>
      bodyMeasurementRepo.getBodyMeasurementsByDate(date);
  Future<List<Map<String, dynamic>>> getBodyCompositionTrend({int months = 6}) =>
      bodyMeasurementRepo.getBodyCompositionTrend(months: months);
  Future<Map<String, int>> getBodyMeasurementFrequency({int months = 6}) =>
      bodyMeasurementRepo.getBodyMeasurementFrequency(months: months);
  Future<List<Map<String, dynamic>>> getBodyMeasurementsWithPhotos(String type, {int limit = 50}) =>
      bodyMeasurementRepo.getBodyMeasurementsWithPhotos(type, limit: limit);

  // -- ANALYTICS --
  Future<Map<String, dynamic>> getExerciseHistory(String exerciseId, {int? limit}) =>
      analyticsRepo.getExerciseHistory(exerciseId, limit: limit);
  Future<Map<String, dynamic>> getWeeklyVolume({int weeks = 4}) =>
      analyticsRepo.getWeeklyVolume(weeks: weeks);
  Future<List<Map<String, dynamic>>> getMonthlyVolume({int months = 6}) =>
      analyticsRepo.getMonthlyVolume(months: months);
  Future<Map<String, int>> getYearlyHeatmapData(int year) =>
      analyticsRepo.getYearlyHeatmapData(year);
  Future<List<Map<String, dynamic>>> getWorkoutDatesInRange(DateTime start) =>
      analyticsRepo.getWorkoutDatesInRange(start);
  Future<List<Map<String, dynamic>>> getVolumeByCategory() =>
      analyticsRepo.getVolumeByCategory();
  Future<List<Map<String, dynamic>>> getWeeklyVolumeByCategory({int weeks = 12}) =>
      analyticsRepo.getWeeklyVolumeByCategory(weeks: weeks);
  Future<List<Map<String, dynamic>>> getTopExercisesByVolume({int limit = 10}) =>
      analyticsRepo.getTopExercisesByVolume(limit: limit);
  Future<List<Map<String, dynamic>>> getEnergySystemDistribution() =>
      analyticsRepo.getEnergySystemDistribution();
  Future<List<Map<String, dynamic>>> getRpeTrend({int limit = 50}) =>
      analyticsRepo.getRpeTrend(limit: limit);
  Future<List<Map<String, dynamic>>> getWorkoutDensity({int limit = 50}) =>
      analyticsRepo.getWorkoutDensity(limit: limit);
  Future<List<Map<String, dynamic>>> getPersonalRecords({int limit = 20}) =>
      analyticsRepo.getPersonalRecords(limit: limit);
  Future<List<Map<String, dynamic>>> getFeelingTrend({int limit = 50}) =>
      analyticsRepo.getFeelingTrend(limit: limit);
  Future<List<Map<String, dynamic>>> getFeelingVsVolume() =>
      analyticsRepo.getFeelingVsVolume();
  Future<List<Map<String, dynamic>>> getDurationTrend({int limit = 50}) =>
      analyticsRepo.getDurationTrend(limit: limit);
  Future<List<Map<String, dynamic>>> getBodyWeightWithVolume({int months = 6}) =>
      analyticsRepo.getBodyWeightWithVolume(months: months);
  Future<Map<String, dynamic>> getMonthlyReport(int year, int month) =>
      analyticsRepo.getMonthlyReport(year, month);
  Future<Map<String, dynamic>> getMonthComparison(int year, int month) =>
      analyticsRepo.getMonthComparison(year, month);
  Future<Map<String, dynamic>> getWorkoutOverviewStats() =>
      analyticsRepo.getWorkoutOverviewStats();

  // -- EXPORT / IMPORT --
  Future<Map<String, dynamic>> exportAllData() => exportImportRepo.exportAllData();
  Future<int> restoreFromBackup(Map<String, dynamic> data) => exportImportRepo.restoreFromBackup(data);
  Future<List<Map<String, dynamic>>> exportWorkoutsCsvData({String? exerciseId, DateTime? startDate, DateTime? endDate}) =>
      exportImportRepo.exportWorkoutsCsvData(exerciseId: exerciseId, startDate: startDate, endDate: endDate);
  Future<void> deleteAllWorkoutData() => exportImportRepo.deleteAllWorkoutData();
}
