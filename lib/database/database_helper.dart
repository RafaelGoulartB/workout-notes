import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/database/database_schema.dart';
import 'package:workout_notes/repositories/ai_chat_repository.dart';
import 'package:workout_notes/repositories/ai_routine_mutation_repository.dart';
import 'package:workout_notes/repositories/analytics_repository.dart';
import 'package:workout_notes/repositories/body_measurement_repository.dart';
import 'package:workout_notes/repositories/exercise_repository.dart';
import 'package:workout_notes/repositories/export_import_repository.dart';
import 'package:workout_notes/repositories/goal_repository.dart';
import 'package:workout_notes/repositories/medication_repository.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';
import 'package:workout_notes/repositories/routine_repository.dart';
import 'package:workout_notes/repositories/run_gear_repository.dart';
import 'package:workout_notes/repositories/run_insights_repository.dart';
import 'package:workout_notes/repositories/run_plan_repository.dart';
import 'package:workout_notes/repositories/run_repository.dart';
import 'package:workout_notes/repositories/settings_repository.dart';
import 'package:workout_notes/repositories/sleep_monitor_repository.dart';
import 'package:workout_notes/repositories/sleep_repository.dart';
import 'package:workout_notes/repositories/strength_history_repository.dart';
import 'package:workout_notes/repositories/strength_records_repository.dart';
import 'package:workout_notes/repositories/strength_repository.dart';
import 'package:workout_notes/repositories/traditional_alarm_repository.dart';
import 'package:workout_notes/repositories/workout_repository.dart';

class DatabaseHelper {
  static const _dbName = 'workout_notes.db';
  static const _dbVersion = 58;

  static DatabaseHelper? _instance;
  static Database? _database;
  static Future<Database>? _openingDatabase;
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
  late final PeriodizationRepository periodizationRepo =
      PeriodizationRepository();
  late final RunRepository runRepo = RunRepository();
  late final RunPlanRepository runPlanRepo = RunPlanRepository();
  late final RunGearRepository runGearRepo = RunGearRepository();
  late final StrengthRepository strengthRepo = StrengthRepository();
  late final StrengthRecordsRepository strengthRecordsRepo =
      StrengthRecordsRepository();
  late final StrengthHistoryRepository strengthHistoryRepo =
      StrengthHistoryRepository();
  late final RunInsightsRepository runInsightsRepo = RunInsightsRepository();
  late final MedicationRepository medicationRepo = MedicationRepository();
  late final AiChatRepository aiChatRepo = AiChatRepository();
  late final AiRoutineMutationRepository aiRoutineMutationRepo =
      AiRoutineMutationRepository();

  DatabaseHelper._();

  static DatabaseHelper get instance {
    _instance ??= DatabaseHelper._();
    return _instance!;
  }

  Future<Database> get database async {
    if (_overrideDatabase != null) return _overrideDatabase!;
    final existing = _database;
    if (existing != null) return existing;
    final opening = _openingDatabase ??= _initDatabase();
    try {
      final opened = await opening;
      _database = opened;
      return opened;
    } finally {
      if (identical(_openingDatabase, opening)) {
        _openingDatabase = null;
      }
    }
  }

  /// Test-only hook. Sets an external [Database] to be returned by
  /// [database] instead of the singleton. Pass `null` to clear.
  static set overrideDatabase(Database? db) {
    _overrideDatabase = db;
    _openingDatabase = null;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, _dbName);
    return openDatabase(
      path,
      version: _dbVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        // Effective for newly-created databases. Existing databases keep
        // their current mode until a user-approved full compaction, but can
        // still reuse pages released by compact-route migration.
        await db.execute('PRAGMA auto_vacuum = INCREMENTAL');
      },
      onCreate: DatabaseSchema.onCreate,
      onUpgrade: DatabaseSchema.onUpgrade,
      singleInstance: true,
    );
  }
}
