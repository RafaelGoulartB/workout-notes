import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'database_schema.dart';
import '../repositories/settings_repository.dart';
import '../repositories/exercise_repository.dart';
import '../repositories/workout_repository.dart';
import '../repositories/routine_repository.dart';
import '../repositories/body_measurement_repository.dart';
import '../repositories/analytics_repository.dart';
import '../repositories/export_import_repository.dart';
import '../repositories/goal_repository.dart';
import '../repositories/sleep_repository.dart';
import '../repositories/sleep_monitor_repository.dart';
import '../repositories/nutrition_repository.dart';
import '../repositories/traditional_alarm_repository.dart';
import '../models/sleep_entry.dart';
import '../models/sleep_monitor_segment.dart';
import '../models/sleep_monitor_session.dart';
import '../models/nutrition/daily_nutrition_summary.dart';
import '../models/nutrition/food.dart';
import '../models/nutrition/food_serving.dart';
import '../models/nutrition/food_variant.dart';
import '../models/nutrition/meal_log.dart';
import '../models/nutrition/meal_log_item.dart';
import '../models/nutrition/nutrition_goal.dart';
import '../models/nutrition/nutrition_values.dart';
import '../utils/nutrition_conversion.dart';

class DatabaseHelper {
  static const _dbName = 'workout_notes.db';
  static const _dbVersion = 36;

  static DatabaseHelper? _instance;
  static Database? _database;
  static Database? _overrideDatabase;

  /// Repository instances (lazy-loaded)
  late final SettingsRepository settingsRepo = SettingsRepository();
  late final ExerciseRepository exerciseRepo = ExerciseRepository();
  late final WorkoutRepository workoutRepo = WorkoutRepository();
  late final RoutineRepository routineRepo = RoutineRepository();
  late final BodyMeasurementRepository bodyMeasurementRepo =
      BodyMeasurementRepository();
  late final AnalyticsRepository analyticsRepo = AnalyticsRepository();
  late final ExportImportRepository exportImportRepo = ExportImportRepository();
  late final GoalRepository goalRepo = GoalRepository();
  late final SleepRepository sleepRepo = SleepRepository();
  late final SleepMonitorRepository sleepMonitorRepo = SleepMonitorRepository();
  late final NutritionRepository nutritionRepo = NutritionRepository();
  late final TraditionalAlarmRepository traditionalAlarmRepo =
      TraditionalAlarmRepository();

  DatabaseHelper._();

  static DatabaseHelper get instance {
    _instance ??= DatabaseHelper._();
    return _instance!;
  }

  Future<Database> get database async {
    if (_overrideDatabase != null) return _overrideDatabase!;
    _database ??= await _initDatabase();
    return _database!;
  }

  /// Test-only hook. Sets an external [Database] to be returned by
  /// [database] instead of the singleton. Pass `null` to clear.
  static set overrideDatabase(Database? db) {
    _overrideDatabase = db;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, _dbName);
    return openDatabase(
      path,
      version: _dbVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: DatabaseSchema.onCreate,
      onUpgrade: DatabaseSchema.onUpgrade,
      singleInstance: true,
    );
  }
  // ===================================================================
  // DELEGATION METHODS (backward compatibility)
  // ===================================================================
  // These methods delegate to the appropriate repository.
  // Screens should migrate to using the repositories directly.
  // ===================================================================

  // -- SETTINGS --
  Future<String?> getSetting(String key) => settingsRepo.getSetting(key);
  Future<void> setSetting(String key, String value) =>
      settingsRepo.setSetting(key, value);
  Future<Map<String, String>> getAllSettings() => settingsRepo.getAllSettings();

  // -- CATEGORIES --
  Future<List<Map<String, dynamic>>> getCategories() =>
      exerciseRepo.getCategories();
  Future<Map<String, dynamic>?> getCategory(String id) =>
      exerciseRepo.getCategory(id);
  Future<String> addCategory(String name, int color) =>
      exerciseRepo.addCategory(name, color);
  Future<void> updateCategory(String id, String name, int color) =>
      exerciseRepo.updateCategory(id, name, color);
  Future<void> deleteCategory(String id) => exerciseRepo.deleteCategory(id);

  // -- EXERCISES --
  Future<List<Map<String, dynamic>>> getExercises({
    String? categoryId,
    String? search,
    bool? favorites,
  }) => exerciseRepo.getExercises(
    categoryId: categoryId,
    search: search,
    favorites: favorites,
  );
  Future<Map<String, dynamic>?> getExercise(String id) =>
      exerciseRepo.getExercise(id);
  Future<String> addExercise({
    required String name,
    required String categoryId,
    String type = 'weightReps',
    String? notes,
    String? equipment,
    double? weightIncrement,
    int? defaultRestTime,
  }) => exerciseRepo.addExercise(
    name: name,
    categoryId: categoryId,
    type: type,
    notes: notes,
    equipment: equipment,
    weightIncrement: weightIncrement,
    defaultRestTime: defaultRestTime,
  );
  Future<void> updateExercise(
    String id, {
    String? name,
    String? categoryId,
    String? type,
    String? notes,
    String? equipment,
    double? weightIncrement,
    int? defaultRestTime,
  }) => exerciseRepo.updateExercise(
    id,
    name: name,
    categoryId: categoryId,
    type: type,
    notes: notes,
    equipment: equipment,
    weightIncrement: weightIncrement,
    defaultRestTime: defaultRestTime,
  );
  Future<void> toggleFavorite(String id) => exerciseRepo.toggleFavorite(id);
  Future<void> deleteExercise(String id) => exerciseRepo.deleteExercise(id);

  // -- WORKOUTS --
  Future<String> createWorkout({
    DateTime? date,
    String? routineId,
    List<Map<String, dynamic>>? exercises,
  }) => workoutRepo.createWorkout(
    date: date,
    routineId: routineId,
    exercises: exercises,
  );
  Future<void> importRoutineDayToWorkout(
    String workoutId,
    String routineDayId,
  ) => workoutRepo.importRoutineDayToWorkout(workoutId, routineDayId);
  Future<String> copyWorkoutToDate(String sourceWorkoutId, DateTime newDate) =>
      workoutRepo.copyWorkoutToDate(sourceWorkoutId, newDate);
  Future<Map<String, dynamic>?> getWorkout(String id) =>
      workoutRepo.getWorkout(id);
  Future<List<Map<String, dynamic>>> getWorkouts({
    DateTime? startDate,
    DateTime? endDate,
    int? limit,
    int? offset,
  }) => workoutRepo.getWorkouts(
    startDate: startDate,
    endDate: endDate,
    limit: limit,
    offset: offset,
  );
  Future<List<Map<String, dynamic>>> getWorkoutsByMonth(int year, int month) =>
      workoutRepo.getWorkoutsByMonth(year, month);
  Future<Map<String, List<Map<String, dynamic>>>> getWorkoutCategoriesByDate(
    int year,
    int month,
  ) => workoutRepo.getWorkoutCategoriesByDate(year, month);
  Future<List<Map<String, dynamic>>> getWorkoutExercises(String workoutId) =>
      workoutRepo.getWorkoutExercises(workoutId);
  Future<List<Map<String, dynamic>>> getExerciseSets(String exerciseEntryId) =>
      workoutRepo.getExerciseSets(exerciseEntryId);
  Future<void> finishWorkout(
    String id, {
    String? comment,
    int? feelingRating,
    double? estimatedCalories,
  }) => workoutRepo.finishWorkout(
    id,
    comment: comment,
    feelingRating: feelingRating,
    estimatedCalories: estimatedCalories,
  );
  Future<void> startWorkoutTimer(String id) =>
      workoutRepo.startWorkoutTimer(id);
  Future<void> stopWorkoutTimer(String id) => workoutRepo.stopWorkoutTimer(id);
  Future<void> resetWorkoutTimer(String id) =>
      workoutRepo.resetWorkoutTimer(id);
  Future<void> updateWorkoutDate(String id, DateTime newDate) =>
      workoutRepo.updateWorkoutDate(id, newDate);
  Future<void> resetWorkoutToInProgress(String id) =>
      workoutRepo.resetWorkoutToInProgress(id);
  Future<void> deleteWorkout(String id) => workoutRepo.deleteWorkout(id);

  // -- SETS --
  Future<String> addSet({
    required String exerciseEntryId,
    double? weight,
    int? reps,
    double? distance,
    int? timeSeconds,
    bool isWarmup = false,
    double? rpe,
    String? comment,
  }) => workoutRepo.addSet(
    exerciseEntryId: exerciseEntryId,
    weight: weight,
    reps: reps,
    distance: distance,
    timeSeconds: timeSeconds,
    isWarmup: isWarmup,
    rpe: rpe,
    comment: comment,
  );
  Future<void> updateSet(
    String setId, {
    double? weight,
    int? reps,
    double? distance,
    int? timeSeconds,
    bool? isComplete,
    bool? isWarmup,
    double? rpe,
    String? comment,
  }) => workoutRepo.updateSet(
    setId,
    weight: weight,
    reps: reps,
    distance: distance,
    timeSeconds: timeSeconds,
    isComplete: isComplete,
    isWarmup: isWarmup,
    rpe: rpe,
    comment: comment,
  );
  Future<void> toggleSetComplete(String setId) =>
      workoutRepo.toggleSetComplete(setId);
  Future<void> deleteSet(String setId) => workoutRepo.deleteSet(setId);
  Future<void> removeExerciseEntryFromWorkout(
    String workoutId,
    String exerciseId,
  ) => workoutRepo.removeExerciseEntryFromWorkout(workoutId, exerciseId);
  Future<void> reorderWorkoutExercises(
    String workoutId,
    List<String> orderedEntryIds,
  ) => workoutRepo.reorderWorkoutExercises(workoutId, orderedEntryIds);
  Future<void> deleteExerciseEntry(String entryId) =>
      workoutRepo.deleteExerciseEntry(entryId);
  Future<void> updateExerciseEntryRestTime(
    String exerciseEntryId,
    int restTimeSeconds,
  ) =>
      workoutRepo.updateExerciseEntryRestTime(exerciseEntryId, restTimeSeconds);
  Future<List<Map<String, dynamic>>> getLastWorkoutSets(
    String exerciseId, {
    String? excludeWorkoutId,
  }) => workoutRepo.getLastWorkoutSets(
    exerciseId,
    excludeWorkoutId: excludeWorkoutId,
  );

  // -- ROUTINES --
  Future<String> createRoutine(String name, {String? notes}) =>
      routineRepo.createRoutine(name, notes: notes);
  Future<List<Map<String, dynamic>>> getRoutines() => routineRepo.getRoutines();
  Future<Map<String, dynamic>?> getRoutine(String id) =>
      routineRepo.getRoutine(id);
  Future<void> updateRoutine(String id, {String? name, String? notes}) =>
      routineRepo.updateRoutine(id, name: name, notes: notes);
  Future<void> deleteRoutine(String id) => routineRepo.deleteRoutine(id);
  Future<List<Map<String, dynamic>>> getRoutineDays(String routineId) =>
      routineRepo.getRoutineDays(routineId);
  Future<String> addRoutineDay(String routineId, String name) =>
      routineRepo.addRoutineDay(routineId, name);
  Future<void> deleteRoutineDay(String id) => routineRepo.deleteRoutineDay(id);
  Future<void> updateRoutineDay(String id, {String? name, String? notes}) =>
      routineRepo.updateRoutineDay(id, name: name, notes: notes);
  Future<List<Map<String, dynamic>>> getRoutineExercises(String routineDayId) =>
      routineRepo.getRoutineExercises(routineDayId);
  Future<String> addRoutineExercise(
    String routineDayId,
    String exerciseId, {
    int? restTimeSeconds,
  }) => routineRepo.addRoutineExercise(
    routineDayId,
    exerciseId,
    restTimeSeconds: restTimeSeconds,
  );
  Future<void> removeRoutineExercise(String id) =>
      routineRepo.removeRoutineExercise(id);
  Future<void> reorderRoutineExercises(
    String routineDayId,
    List<String> orderedIds,
  ) => routineRepo.reorderRoutineExercises(routineDayId, orderedIds);
  Future<void> updateRoutineExerciseRestTime(
    String routineExerciseId,
    int restTimeSeconds,
  ) => routineRepo.updateRoutineExerciseRestTime(
    routineExerciseId,
    restTimeSeconds,
  );
  Future<List<Map<String, dynamic>>> getPredefinedSets(
    String routineExerciseId,
  ) => routineRepo.getPredefinedSets(routineExerciseId);
  Future<String> addPredefinedSet(
    String routineExerciseId, {
    double? weight,
    int? reps,
    double? distance,
    int? timeSeconds,
    bool isWarmup = false,
  }) => routineRepo.addPredefinedSet(
    routineExerciseId,
    weight: weight,
    reps: reps,
    distance: distance,
    timeSeconds: timeSeconds,
    isWarmup: isWarmup,
  );
  Future<void> updatePredefinedSet(
    String id, {
    double? weight,
    int? reps,
    double? distance,
    int? timeSeconds,
    bool? isWarmup,
  }) => routineRepo.updatePredefinedSet(
    id,
    weight: weight,
    reps: reps,
    distance: distance,
    timeSeconds: timeSeconds,
    isWarmup: isWarmup,
  );
  Future<void> deletePredefinedSet(String id) =>
      routineRepo.deletePredefinedSet(id);

  // -- AI ROUTINE PROPOSALS --
  Future<void> insertAiRoutineProposal(Map<String, dynamic> row) async {
    final db = await database;
    await db.insert('ai_routine_proposals', row);
  }

  Future<Map<String, dynamic>?> getAiRoutineProposal(String id) async {
    final db = await database;
    final rows = await db.query(
      'ai_routine_proposals',
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, dynamic>>> getAiRoutineProposalsThread(
    String threadId,
  ) async {
    final db = await database;
    return db.query(
      'ai_routine_proposals',
      where: 'thread_id = ?',
      whereArgs: [threadId],
      orderBy: 'created_at ASC',
    );
  }

  Future<void> updateAiRoutineProposal(
    String id,
    Map<String, dynamic> values,
  ) async {
    final db = await database;
    await db.update(
      'ai_routine_proposals',
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // -- BODY MEASUREMENTS --
  Future<void> addBodyMeasurement(
    String type,
    double value,
    String unit, {
    DateTime? date,
    String? comment,
    String? timeOfDay,
    bool isFasted = false,
    List<String>? photosPaths,
    String? side,
  }) => bodyMeasurementRepo.addBodyMeasurement(
    type,
    value,
    unit,
    date: date,
    comment: comment,
    timeOfDay: timeOfDay,
    isFasted: isFasted,
    photosPaths: photosPaths,
    side: side,
  );
  Future<void> addBodyMeasurementsBatch(
    List<Map<String, dynamic>> measurements,
  ) => bodyMeasurementRepo.addBodyMeasurementsBatch(measurements);
  Future<List<Map<String, dynamic>>> getBodyMeasurements({
    String? type,
    int? limit,
  }) => bodyMeasurementRepo.getBodyMeasurements(type: type, limit: limit);
  Future<void> deleteBodyMeasurement(String id) =>
      bodyMeasurementRepo.deleteBodyMeasurement(id);
  Future<List<Map<String, dynamic>>> getBodyMeasurementsSummary() =>
      bodyMeasurementRepo.getBodyMeasurementsSummary();
  Future<Map<String, dynamic>?> getPreviousBodyMeasurement(
    String type, {
    String? beforeDate,
  }) => bodyMeasurementRepo.getPreviousBodyMeasurement(
    type,
    beforeDate: beforeDate,
  );
  Future<List<Map<String, dynamic>>> getBodyMeasurementsTrend(
    String type, {
    int months = 6,
  }) => bodyMeasurementRepo.getBodyMeasurementsTrend(type, months: months);
  Future<List<Map<String, dynamic>>> getBodyMeasurementsByDate(String date) =>
      bodyMeasurementRepo.getBodyMeasurementsByDate(date);
  Future<List<Map<String, dynamic>>> getBodyCompositionTrend({
    int months = 6,
  }) => bodyMeasurementRepo.getBodyCompositionTrend(months: months);
  Future<Map<String, int>> getBodyMeasurementFrequency({int months = 6}) =>
      bodyMeasurementRepo.getBodyMeasurementFrequency(months: months);
  Future<List<Map<String, dynamic>>> getBodyMeasurementsWithPhotos(
    String type, {
    int limit = 50,
  }) => bodyMeasurementRepo.getBodyMeasurementsWithPhotos(type, limit: limit);

  // -- ANALYTICS --
  Future<Map<String, dynamic>> getExerciseHistory(
    String exerciseId, {
    int? limit,
  }) => analyticsRepo.getExerciseHistory(exerciseId, limit: limit);
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
  Future<List<Map<String, dynamic>>> getWeeklyVolumeByCategory({
    int weeks = 12,
  }) => analyticsRepo.getWeeklyVolumeByCategory(weeks: weeks);
  Future<List<Map<String, dynamic>>> getTopExercisesByVolume({
    int limit = 10,
  }) => analyticsRepo.getTopExercisesByVolume(limit: limit);
  Future<List<Map<String, dynamic>>> getEnergySystemDistribution() =>
      analyticsRepo.getEnergySystemDistribution();
  Future<List<Map<String, dynamic>>> getAnaerobicVolumeByCategory(
    DateTime start,
    DateTime end, {
    required bool bySets,
  }) => analyticsRepo.getAnaerobicVolumeByCategory(start, end, bySets: bySets);
  Future<List<Map<String, dynamic>>> getAnaerobicTopExercises(
    DateTime start,
    DateTime end, {
    required bool bySets,
    int limit = 5,
  }) => analyticsRepo.getAnaerobicTopExercises(
    start,
    end,
    bySets: bySets,
    limit: limit,
  );
  Future<List<Map<String, dynamic>>> getAnaerobicVolumeTrend(
    DateTime end,
    AnaerobicTrendBucket bucket, {
    required bool bySets,
  }) => analyticsRepo.getAnaerobicVolumeTrend(end, bucket, bySets: bySets);
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
  Future<List<Map<String, dynamic>>> getBodyWeightWithVolume({
    int months = 6,
  }) => analyticsRepo.getBodyWeightWithVolume(months: months);
  Future<Map<String, dynamic>> getMonthlyReport(int year, int month) =>
      analyticsRepo.getMonthlyReport(year, month);
  Future<Map<String, dynamic>> getMonthComparison(int year, int month) =>
      analyticsRepo.getMonthComparison(year, month);
  Future<Map<String, dynamic>> getWorkoutOverviewStats() =>
      analyticsRepo.getWorkoutOverviewStats();
  Future<List<Map<String, dynamic>>> getCardioWeeklyDistance({
    int weeks = 12,
  }) => analyticsRepo.getCardioWeeklyDistance(weeks: weeks);
  Future<List<Map<String, dynamic>>> getCardioDistanceByModality() =>
      analyticsRepo.getCardioDistanceByModality();

  // -- EXPORT / IMPORT --
  Future<Map<String, dynamic>> exportAllData() =>
      exportImportRepo.exportAllData();
  Future<int> restoreFromBackup(Map<String, dynamic> data) =>
      exportImportRepo.restoreFromBackup(data);
  Future<List<Map<String, dynamic>>> exportWorkoutsCsvData({
    String? exerciseId,
    DateTime? startDate,
    DateTime? endDate,
  }) => exportImportRepo.exportWorkoutsCsvData(
    exerciseId: exerciseId,
    startDate: startDate,
    endDate: endDate,
  );
  Future<void> deleteAllWorkoutData() =>
      exportImportRepo.deleteAllWorkoutData();

  // -- SLEEP --
  Future<List<SleepEntry>> getSleepEntries({
    DateTime? from,
    DateTime? to,
    int? limit,
  }) => sleepRepo.getEntries(from: from, to: to, limit: limit);
  Future<SleepEntry?> getLatestSleepEntry() => sleepRepo.getLatest();
  Future<SleepEntry?> getSleepEntryByDate(DateTime date) =>
      sleepRepo.getByDate(date);
  Future<void> deleteSleepEntry(String id) => sleepRepo.delete(id);
  Future<SleepEntry?> getSleepEntryById(String id) => sleepRepo.getById(id);
  Future<SleepDashboardStats> getSleepDashboardStats({
    DateTime? referenceDate,
  }) => sleepRepo.getDashboardStats(referenceDate: referenceDate);

  // -- SLEEP MONITOR --
  Future<List<SleepMonitorSession>> getSleepMonitorSessions({int? limit}) =>
      sleepMonitorRepo.getSessions(limit: limit);
  Future<SleepMonitorSession?> getSleepMonitorSession(String id) =>
      sleepMonitorRepo.getSession(id);
  Future<List<SleepMonitorSegment>> getSleepMonitorSegments(String sessionId) =>
      sleepMonitorRepo.getSegments(sessionId);

  // -- NUTRITION --
  NutritionRepository get nutritionRepository => nutritionRepo;
  Future<List<FoodSearchResultLite>> searchLocalFoods(
    String query, {
    int limit = 30,
  }) => nutritionRepo.searchLocalFoods(query, limit: limit);
  Future<FoodWithDetails?> getFoodWithDetails(String id) =>
      nutritionRepo.getFoodWithDetails(id);
  Future<FoodWithDetails?> getFoodBySource({
    required String source,
    required String externalId,
  }) => nutritionRepo.getFoodBySource(source: source, externalId: externalId);
  Future<Food> upsertFoodWithDetails({
    required Food food,
    required List<FoodVariant> variants,
    Map<String, List<FoodServing>>? servings,
  }) => nutritionRepo.upsertFoodWithDetails(
    food: food,
    variants: variants,
    servings: servings,
  );
  Future<Food> createManualFood({
    required String name,
    String? brand,
    String? barcode,
    required double referenceAmount,
    required String referenceUnit,
    required NutritionValues referenceValues,
    bool isEstimated = false,
    List<ManualServingInput> servings = const [],
  }) => nutritionRepo.createManualFood(
    name: name,
    brand: brand,
    barcode: barcode,
    referenceAmount: referenceAmount,
    referenceUnit: referenceUnit,
    referenceValues: referenceValues,
    isEstimated: isEstimated,
    servings: servings,
  );
  Future<Food> updateManualFood({
    required String foodId,
    required String name,
    String? brand,
    String? barcode,
    required double referenceAmount,
    required String referenceUnit,
    required NutritionValues referenceValues,
    bool isEstimated = false,
    List<ManualServingInput> servings = const [],
  }) => nutritionRepo.updateManualFood(
    foodId: foodId,
    name: name,
    brand: brand,
    barcode: barcode,
    referenceAmount: referenceAmount,
    referenceUnit: referenceUnit,
    referenceValues: referenceValues,
    isEstimated: isEstimated,
    servings: servings,
  );
  Future<void> deleteManualFood(String foodId) =>
      nutritionRepo.deleteManualFood(foodId);
  Future<MealLog> ensureMealLog({
    required String date,
    required String mealType,
  }) => nutritionRepo.ensureMealLog(date: date, mealType: mealType);
  Future<MealLogItem> addMealLogItem({
    required String date,
    required String mealType,
    required Food food,
    required FoodVariant variant,
    required NutritionConversion conversion,
    List<FoodServing> availableServings = const [],
  }) => nutritionRepo.addMealLogItem(
    date: date,
    mealType: mealType,
    food: food,
    variant: variant,
    conversion: conversion,
    availableServings: availableServings,
  );
  Future<MealLogItem> updateMealLogItem({
    required String itemId,
    required NutritionConversion conversion,
    required FoodVariant variant,
  }) => nutritionRepo.updateMealLogItem(
    itemId: itemId,
    conversion: conversion,
    variant: variant,
  );
  Future<void> deleteMealLogItem(String id) =>
      nutritionRepo.deleteMealLogItem(id);
  Future<List<MealLogWithItems>> getDayMeals(String date) =>
      nutritionRepo.getDayMeals(date);
  Future<DailyNutritionSummary> getDailyNutritionSummary(String date) =>
      nutritionRepo.getDailySummary(date);
  Future<NutritionGoal?> getActiveNutritionGoal() =>
      nutritionRepo.getActiveGoal();
  Future<NutritionGoal> saveNutritionGoal({
    double? calories,
    double? proteinG,
    double? carbsG,
    double? fatG,
  }) => nutritionRepo.saveGoal(
    calories: calories,
    proteinG: proteinG,
    carbsG: carbsG,
    fatG: fatG,
  );
  Future<void> clearActiveNutritionGoal() => nutritionRepo.clearActiveGoal();
  Future<List<NutritionExportRow>> exportNutritionRows({
    DateTime? startDate,
    DateTime? endDate,
  }) => nutritionRepo.exportRows(startDate: startDate, endDate: endDate);

  // -- AI CHAT --
  Future<String> upsertAiChatThread({
    required String id,
    required String title,
    required DateTime createdAt,
    required DateTime updatedAt,
    String? lastMessagePreview,
    bool archived = false,
    bool isPinned = false,
  }) async {
    final db = await database;
    final values = {
      'title': title,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'last_message_preview': lastMessagePreview,
      'archived': archived ? 1 : 0,
      'is_pinned': isPinned ? 1 : 0,
    };
    await db.transaction((txn) async {
      final updated = await txn.update(
        'ai_chat_threads',
        values,
        where: 'id = ?',
        whereArgs: [id],
      );
      if (updated == 0) {
        await txn.insert('ai_chat_threads', {'id': id, ...values});
      }
    });
    return id;
  }

  Future<void> replaceAiChatMessages(
    String threadId,
    List<Map<String, dynamic>> messages,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        'ai_chat_messages',
        where: 'thread_id = ?',
        whereArgs: [threadId],
      );
      for (final m in messages) {
        await txn.insert('ai_chat_messages', m);
      }
    });
  }

  Future<List<Map<String, dynamic>>> getAiChatThreads() async {
    final db = await database;
    return db.query(
      'ai_chat_threads',
      where: 'archived = 0',
      orderBy: 'is_pinned DESC, updated_at DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getAiChatMessagesThread(
    String threadId,
  ) async {
    final db = await database;
    return db.query(
      'ai_chat_messages',
      where: 'thread_id = ?',
      whereArgs: [threadId],
      orderBy: 'created_at ASC',
    );
  }

  Future<void> renameAiChatThread(String threadId, String title) async {
    final db = await database;
    await db.update(
      'ai_chat_threads',
      {'title': title},
      where: 'id = ?',
      whereArgs: [threadId],
    );
  }

  Future<void> setAiChatThreadPinned(String threadId, bool isPinned) async {
    final db = await database;
    await db.update(
      'ai_chat_threads',
      {'is_pinned': isPinned ? 1 : 0},
      where: 'id = ?',
      whereArgs: [threadId],
    );
  }

  Future<void> deleteAiChatThread(String threadId) async {
    final db = await database;
    await db.delete('ai_chat_threads', where: 'id = ?', whereArgs: [threadId]);
  }
}
