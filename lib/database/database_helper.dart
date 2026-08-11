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
  static const _dbVersion = 33;

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
        locale_key TEXT,
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
        locale_key TEXT,
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
        estimated_calories REAL,
        comment TEXT,
        feeling_rating INTEGER,
        is_from_routine INTEGER NOT NULL DEFAULT 0,
        routine_id TEXT,
        pause_start_time TEXT,
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
        notes TEXT,
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

    // Nightly sleep records (v20)
    await db.execute('''
      CREATE TABLE sleep_entries (
        id TEXT PRIMARY KEY,
        date TEXT NOT NULL UNIQUE,
        sleep_minutes INTEGER NOT NULL,
        actual_sleep_minutes INTEGER,
        bedtime_minutes INTEGER,
        wake_time_minutes INTEGER,
        comment TEXT,
        source TEXT NOT NULL DEFAULT 'manual',
        time_in_bed_minutes INTEGER,
        estimated_sleep_minutes INTEGER,
        created_at TEXT NOT NULL
      )
    ''');

    // Native audio-monitoring sessions and their 30-second aggregates.
    await db.execute('''
      CREATE TABLE sleep_monitor_sessions (
        id TEXT PRIMARY KEY,
        sleep_entry_id TEXT,
        status TEXT NOT NULL,
        started_at TEXT NOT NULL,
        ended_at TEXT,
        alarm_at TEXT,
        monitor_mode TEXT,
        mission_type TEXT,
        alarm_dismiss_method TEXT,
        alarm_dismissed_at TEXT,
        utc_offset_start_minutes INTEGER NOT NULL,
        utc_offset_end_minutes INTEGER,
        sensor_mode TEXT NOT NULL DEFAULT 'audio',
        algorithm_version TEXT NOT NULL,
        time_in_bed_minutes INTEGER,
        quiet_minutes INTEGER,
        noisy_minutes INTEGER,
        estimated_sleep_minutes INTEGER,
        noise_event_count INTEGER NOT NULL DEFAULT 0,
        signal_quality_score REAL,
        analysis_status TEXT NOT NULL DEFAULT 'legacy_unavailable',
        sleep_onset_at TEXT,
        final_wake_at TEXT,
        sleep_latency_minutes INTEGER,
        awake_minutes INTEGER,
        sleeping_minutes INTEGER,
        deep_sleep_minutes INTEGER,
        unknown_minutes INTEGER,
        awakening_count INTEGER,
        sleep_efficiency REAL,
        stage_confidence REAL,
        stage_algorithm_version TEXT,
        end_reason TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (sleep_entry_id) REFERENCES sleep_entries(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE sleep_monitor_segments (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        started_at TEXT NOT NULL,
        duration_seconds INTEGER NOT NULL,
        audio_rms_dbfs REAL,
        audio_peak_dbfs REAL,
        noise_score REAL,
        classification TEXT NOT NULL,
        valid_fraction REAL NOT NULL,
        noise_burst_count INTEGER NOT NULL DEFAULT 0,
        spectral_band_energy_0 REAL,
        spectral_band_energy_1 REAL,
        spectral_band_energy_2 REAL,
        spectral_band_energy_3 REAL,
        spectral_band_energy_4 REAL,
        spectral_flatness REAL,
        spectral_centroid_hz REAL,
        breathing_regularity REAL,
        breathing_rate_hz REAL,
        motion_active_seconds REAL,
        motion_mean_deviation_g REAL,
        motion_max_deviation_g REAL,
        FOREIGN KEY (session_id) REFERENCES sleep_monitor_sessions(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE sleep_stage_epochs (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        started_at TEXT NOT NULL,
        duration_seconds INTEGER NOT NULL,
        stage TEXT NOT NULL,
        confidence REAL NOT NULL,
        awake_probability REAL,
        sleeping_probability REAL,
        deep_probability REAL,
        algorithm_version TEXT NOT NULL,
        source TEXT NOT NULL DEFAULT 'acoustic_model',
        FOREIGN KEY (session_id) REFERENCES sleep_monitor_sessions(id) ON DELETE CASCADE
      )
    ''');

    // Standalone wake-up alarms.
    await db.execute('''
      CREATE TABLE traditional_alarms (
        id TEXT PRIMARY KEY,
        hour INTEGER NOT NULL,
        minute INTEGER NOT NULL,
        weekdays_json TEXT NOT NULL DEFAULT '[]',
        enabled INTEGER NOT NULL DEFAULT 1,
        snooze_enabled INTEGER NOT NULL DEFAULT 1,
        snooze_minutes INTEGER NOT NULL DEFAULT 5,
        max_snoozes INTEGER NOT NULL DEFAULT 3,
        requires_mission INTEGER NOT NULL DEFAULT 0,
        next_trigger_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    // App settings
    await db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // User goals (v13)
    await db.execute('''
      CREATE TABLE user_goals (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        scope TEXT NOT NULL,
        metric TEXT NOT NULL,
        period TEXT NOT NULL,
        target_value REAL NOT NULL,
        created_at TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        color INTEGER
      )
    ''');

    // AI chat threads (v15)
    await db.execute('''
      CREATE TABLE ai_chat_threads (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        last_message_preview TEXT,
        archived INTEGER NOT NULL DEFAULT 0,
        is_pinned INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // AI chat messages (v15)
    await db.execute('''
      CREATE TABLE ai_chat_messages (
        id TEXT PRIMARY KEY,
        thread_id TEXT NOT NULL,
        role TEXT NOT NULL,
        content TEXT,
        tool_call_id TEXT,
        tool_name TEXT,
        tool_calls_json TEXT,
        attachments_json TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (thread_id) REFERENCES ai_chat_threads(id) ON DELETE CASCADE
      )
    ''');

    // AI routine proposals (v17). These are drafts only until user approval.
    await db.execute('''
      CREATE TABLE ai_routine_proposals (
        id TEXT PRIMARY KEY,
        thread_id TEXT NOT NULL,
        tool_call_id TEXT NOT NULL,
        action TEXT NOT NULL,
        routine_id TEXT,
        before_json TEXT,
        target_json TEXT NOT NULL,
        diff_json TEXT NOT NULL,
        status TEXT NOT NULL,
        applied_routine_id TEXT,
        error_code TEXT,
        error_message TEXT,
        created_at TEXT NOT NULL,
        resolved_at TEXT,
        FOREIGN KEY (thread_id) REFERENCES ai_chat_threads(id) ON DELETE CASCADE
      )
    ''');

    // Nutrition module (v22). Foods, variants, servings, meal logs and
    // goals share a single helper so `_onCreate` and `_onUpgrade` use
    // the same definition.
    await _createNutritionSchema(db);

    // Indexes
    await db.execute('CREATE INDEX idx_workouts_date ON workouts(date)');
    await db.execute(
      'CREATE INDEX idx_exercise_entries_workout ON exercise_entries(workout_id)',
    );
    await db.execute('CREATE INDEX idx_sets_entry ON sets(exercise_entry_id)');
    await db.execute(
      'CREATE INDEX idx_measurements_date ON body_measurements(date)',
    );
    await db.execute(
      'CREATE INDEX idx_measurements_type ON body_measurements(type)',
    );
    await db.execute(
      'CREATE INDEX idx_sleep_entries_date ON sleep_entries(date DESC)',
    );
    await db.execute(
      'CREATE INDEX idx_sleep_monitor_sessions_status_started ON sleep_monitor_sessions(status, started_at DESC)',
    );
    await db.execute(
      'CREATE INDEX idx_sleep_monitor_sessions_entry ON sleep_monitor_sessions(sleep_entry_id)',
    );
    await db.execute(
      'CREATE INDEX idx_sleep_monitor_segments_session_started ON sleep_monitor_segments(session_id, started_at ASC)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX idx_sleep_stage_epochs_session_started ON sleep_stage_epochs(session_id, started_at ASC)',
    );
    await db.execute(
      'CREATE INDEX idx_ai_chat_messages_thread ON ai_chat_messages(thread_id, created_at ASC)',
    );
    await db.execute(
      'CREATE INDEX idx_traditional_alarms_next_trigger ON traditional_alarms(enabled, next_trigger_at ASC)',
    );
    await db.execute(
      'CREATE INDEX idx_ai_chat_threads_updated ON ai_chat_threads(updated_at DESC)',
    );
    await db.execute(
      'CREATE INDEX idx_ai_chat_threads_pinned_updated ON ai_chat_threads(is_pinned DESC, updated_at DESC)',
    );
    await db.execute(
      'CREATE INDEX idx_ai_routine_proposals_thread_status ON ai_routine_proposals(thread_id, status, created_at ASC)',
    );

    // Seed data
    await _seedMealTypes(db);
    await _seedData(db);
  }

  /// Seeds the four legacy meal types (breakfast → snacks) so upgraded
  /// and fresh databases always have a working catalog. `name` stays
  /// NULL: the UI resolves those keys to localized labels, and the user
  /// can rename them later. Idempotent via `INSERT OR IGNORE` on `key`.
  static Future<void> _seedMealTypes(Database db) async {
    final now = DateTime.now().toIso8601String();
    final rows = <Map<String, dynamic>>[
      {'key': 'breakfast', 'order_index': 0},
      {'key': 'lunch', 'order_index': 1},
      {'key': 'dinner', 'order_index': 2},
      {'key': 'snacks', 'order_index': 3},
    ];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      try {
        await db.insert(
          'meal_types',
          {
            'id': row['key'],
            'key': row['key'],
            'name': null,
            'order_index': row['order_index'],
            'created_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      } catch (_) {}
    }
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try {
        await db.execute(
          'ALTER TABLE exercise_entries ADD COLUMN rest_time_seconds INTEGER',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE routine_exercises ADD COLUMN rest_time_seconds INTEGER',
        );
      } catch (_) {}
    }
    if (oldVersion < 3) {
      try {
        await db.execute(
          'ALTER TABLE exercise_categories ADD COLUMN energy_system TEXT NOT NULL DEFAULT \'anaerobic\'',
        );
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
          await db.insert('app_settings', {
            'key': entry.key,
            'value': entry.value,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        } catch (_) {}
      }
    }
    if (oldVersion < 5) {
      try {
        await db.execute(
          'ALTER TABLE body_measurements ADD COLUMN time_of_day TEXT',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE body_measurements ADD COLUMN is_fasted INTEGER DEFAULT 0',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE body_measurements ADD COLUMN photos_paths TEXT',
        );
      } catch (_) {}
    }
    if (oldVersion < 6) {
      try {
        await db.execute('ALTER TABLE exercises ADD COLUMN locale_key TEXT');
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE exercise_categories ADD COLUMN locale_key TEXT',
        );
      } catch (_) {}
      final seedIds = [
        'bench_press',
        'incl_bench',
        'decl_bench',
        'db_bench',
        'db_incl',
        'cable_fly',
        'pec_deck',
        'pushup',
        'chest_dip',
        'sm_bench',
        'pullup',
        'chinup',
        'lat_pulldown',
        'bent_row',
        'db_row',
        'seated_row',
        'tbar_row',
        'face_pull',
        'deadlift',
        'rdl',
        'hyperextension',
        'ohp',
        'db_ohp',
        'lat_raise',
        'front_raise',
        'rear_delt_fly',
        'upright_row',
        'arnold_press',
        'shrug',
        'bb_curl',
        'db_curl',
        'hammer_curl',
        'preacher_curl',
        'cable_curl',
        'concentration_curl',
        'triceps_pushdown',
        'skull_crusher',
        'close_grip',
        'triceps_extension',
        'bench_dip',
        'kickback',
        'squat',
        'front_squat',
        'leg_press',
        'romanian_dl',
        'leg_curl',
        'leg_ext',
        'bulgarian_split',
        'lunge',
        'calf_raise',
        'goblet_squat',
        'hack_squat',
        'hip_thrust',
        'crunch',
        'leg_raise',
        'plank',
        'russian_twist',
        'cable_crunch',
        'ab_roller',
        'hanging_raise',
        'treadmill',
        'cycling',
        'jump_rope',
        'rowing',
        'swimming',
        'walking',
        'running',
      ];
      for (final id in seedIds) {
        try {
          await db.rawUpdate(
            'UPDATE exercises SET locale_key = ? WHERE id = ?',
            [id, id],
          );
        } catch (_) {}
      }
      final catIds = [
        'chest',
        'back',
        'shoulders',
        'biceps',
        'triceps',
        'legs',
        'core',
        'cardio',
        'fullbody',
      ];
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
    if (oldVersion < 9) {
      try {
        await db.execute(
          'ALTER TABLE workouts ADD COLUMN pause_start_time TEXT',
        );
      } catch (_) {}
    }
    if (oldVersion < 10) {
      try {
        await db.execute('ALTER TABLE routine_days ADD COLUMN notes TEXT');
      } catch (_) {}
    }
    if (oldVersion < 12) {
      // New category: forearms
      try {
        await db.insert('exercise_categories', {
          'id': 'forearms',
          'name': 'Antebraço',
          'locale_key': 'forearms',
          'color': 0xFF8D6E63,
          'order_index': 9,
          'energy_system': 'anaerobic',
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      } catch (_) {}

      // New exercises for all categories
      final v12Exercises = [
        // === FULLBODY ===
        {
          'id': 'kettlebell_swing',
          'name': 'Kettlebell Swing',
          'locale_key': 'kettlebell_swing',
          'category_id': 'fullbody',
          'type': 'weightReps',
          'notes': 'Balanço com kettlebell, cadeia posterior + cardio',
          'equipment': 'Kettlebell',
          'default_rest_time': 90,
          'weight_increment': 2.0,
        },
        {
          'id': 'thruster',
          'name': 'Thruster',
          'locale_key': 'thruster',
          'category_id': 'fullbody',
          'type': 'weightReps',
          'notes': 'Agachamento frontal + desenvolvimento acima da cabeça',
          'equipment': 'Barbell',
          'default_rest_time': 120,
          'weight_increment': 2.5,
        },
        {
          'id': 'clean_press',
          'name': 'Clean and Press',
          'locale_key': 'clean_press',
          'category_id': 'fullbody',
          'type': 'weightReps',
          'notes': 'Arranque do chão até os ombros + desenvolvimento',
          'equipment': 'Barbell',
          'default_rest_time': 120,
          'weight_increment': 2.5,
        },
        {
          'id': 'turkish_getup',
          'name': 'Turkish Get-Up',
          'locale_key': 'turkish_getup',
          'category_id': 'fullbody',
          'type': 'weightReps',
          'notes': 'Levantar do chão com peso acima da cabeça, cada lado',
          'equipment': 'Kettlebell',
          'default_rest_time': 90,
          'weight_increment': 2.0,
        },
        {
          'id': 'snatch',
          'name': 'Snatch (Arranco)',
          'locale_key': 'snatch',
          'category_id': 'fullbody',
          'type': 'weightReps',
          'notes':
              'Levantamento olímpico do chão até acima da cabeça em um movimento',
          'equipment': 'Barbell',
          'default_rest_time': 120,
          'weight_increment': 2.5,
        },
        {
          'id': 'bear_crawl',
          'name': 'Bear Crawl',
          'locale_key': 'bear_crawl',
          'category_id': 'fullbody',
          'type': 'distanceTime',
          'notes': 'Engatinhar em quatro apoios, joelhos fora do chão',
          'equipment': 'Bodyweight',
          'default_rest_time': 60,
          'weight_increment': 0,
        },
        {
          'id': 'devils_press',
          'name': "Devil's Press",
          'locale_key': 'devils_press',
          'category_id': 'fullbody',
          'type': 'weightReps',
          'notes': 'Burpee + desenvolvimento com halteres',
          'equipment': 'Dumbbell',
          'default_rest_time': 90,
          'weight_increment': 1.0,
        },
        {
          'id': 'man_maker',
          'name': 'Man Maker',
          'locale_key': 'man_maker',
          'category_id': 'fullbody',
          'type': 'weightReps',
          'notes': 'Burpee + remada + desenvolvimento com halteres',
          'equipment': 'Dumbbell',
          'default_rest_time': 90,
          'weight_increment': 1.0,
        },
        {
          'id': 'wall_ball',
          'name': 'Wall Ball',
          'locale_key': 'wall_ball',
          'category_id': 'fullbody',
          'type': 'weightReps',
          'notes': 'Agachar e arremessar bola medicinal na parede',
          'equipment': 'Medicine Ball',
          'default_rest_time': 60,
          'weight_increment': 1.0,
        },
        {
          'id': 'burpee_full',
          'name': 'Burpee Completo',
          'locale_key': 'burpee_full',
          'category_id': 'fullbody',
          'type': 'weightReps',
          'notes': 'Agachar, flexão, pular e bater palma acima da cabeça',
          'equipment': 'Bodyweight',
          'default_rest_time': 60,
          'weight_increment': 0,
        },
        // === FOREARMS ===
        {
          'id': 'wrist_curl',
          'name': 'Rosca de Punho',
          'locale_key': 'wrist_curl',
          'category_id': 'forearms',
          'type': 'weightReps',
          'notes': 'Antebraços apoiados no banco ou coxas, flexionar punhos',
          'equipment': 'Barbell',
          'default_rest_time': 45,
          'weight_increment': 1.0,
        },
        {
          'id': 'reverse_wrist_curl',
          'name': 'Rosca de Punho Invertida',
          'locale_key': 'reverse_wrist_curl',
          'category_id': 'forearms',
          'type': 'weightReps',
          'notes': 'Antebraços apoiados, palmas para baixo, estender punhos',
          'equipment': 'Barbell',
          'default_rest_time': 45,
          'weight_increment': 1.0,
        },
        {
          'id': 'farmer_walk',
          'name': "Farmer's Walk",
          'locale_key': 'farmer_walk',
          'category_id': 'forearms',
          'type': 'distanceTime',
          'notes': 'Caminhar segurando pesos pesados em cada mão',
          'equipment': 'Dumbbell',
          'default_rest_time': 60,
          'weight_increment': 2.0,
        },
        {
          'id': 'pinch_grip',
          'name': 'Pinch Grip Hold',
          'locale_key': 'pinch_grip',
          'category_id': 'forearms',
          'type': 'timeOnly',
          'notes': 'Segurar anilhas juntas apenas com a pinça dos dedos',
          'equipment': 'Plates',
          'default_rest_time': 60,
          'weight_increment': 1.0,
        },
        // === ADDITIONAL CHEST ===
        {
          'id': 'cable_crossover',
          'name': 'Crossover na Polia',
          'locale_key': 'cable_crossover',
          'category_id': 'chest',
          'type': 'weightReps',
          'notes':
              'Polias altas, puxar para frente e baixo, contrair no centro',
          'equipment': 'Cable',
          'default_rest_time': 60,
          'weight_increment': 2.5,
        },
        {
          'id': 'parallel_dip',
          'name': 'Dips nas Paralelas',
          'locale_key': 'parallel_dip',
          'category_id': 'chest',
          'type': 'weightReps',
          'notes': 'Tronco inclinado para frente foca peito; reto foca tríceps',
          'equipment': 'Bodyweight',
          'default_rest_time': 90,
          'weight_increment': 0,
        },
        {
          'id': 'decline_pushup',
          'name': 'Flexão Declinada',
          'locale_key': 'decline_pushup',
          'category_id': 'chest',
          'type': 'weightReps',
          'notes': 'Pés elevados, mãos no chão, foco no peitoral superior',
          'equipment': 'Bodyweight',
          'default_rest_time': 60,
          'weight_increment': 0,
        },
        {
          'id': 'floor_press',
          'name': 'Supino no Solo',
          'locale_key': 'floor_press',
          'category_id': 'chest',
          'type': 'weightReps',
          'notes': 'Deitado no chão, amplitude reduzida, protege ombros',
          'equipment': 'Barbell',
          'default_rest_time': 90,
          'weight_increment': 2.5,
        },
        // === ADDITIONAL BACK ===
        {
          'id': 'seal_row',
          'name': 'Remada Cavalinho',
          'locale_key': 'seal_row',
          'category_id': 'back',
          'type': 'weightReps',
          'notes': 'Deitado de bruços em banco elevado, remada com barra',
          'equipment': 'Barbell',
          'default_rest_time': 90,
          'weight_increment': 2.5,
        },
        {
          'id': 'vbar_pulldown',
          'name': 'Puxada Alta Triângulo',
          'locale_key': 'vbar_pulldown',
          'category_id': 'back',
          'type': 'weightReps',
          'notes': 'Pegada neutra com triângulo, puxar até o peito',
          'equipment': 'Cable',
          'default_rest_time': 90,
          'weight_increment': 2.5,
        },
        {
          'id': 'renegade_row',
          'name': 'Remada Renegada',
          'locale_key': 'renegade_row',
          'category_id': 'back',
          'type': 'weightReps',
          'notes': 'Em posição de prancha, remar um halter de cada vez',
          'equipment': 'Dumbbell',
          'default_rest_time': 60,
          'weight_increment': 2.0,
        },
        {
          'id': 'superman',
          'name': 'Superman',
          'locale_key': 'superman',
          'category_id': 'back',
          'type': 'weightReps',
          'notes': 'Deitado de bruços, elevar braços e pernas simultaneamente',
          'equipment': 'Bodyweight',
          'default_rest_time': 45,
          'weight_increment': 0,
        },
        // === ADDITIONAL SHOULDERS ===
        {
          'id': 'db_rear_delt_fly',
          'name': 'Crucifixo Invertido Halteres',
          'locale_key': 'db_rear_delt_fly',
          'category_id': 'shoulders',
          'type': 'weightReps',
          'notes':
              'Tronco inclinado, halteres abrindo lateralmente para deltoide posterior',
          'equipment': 'Dumbbell',
          'default_rest_time': 60,
          'weight_increment': 1.0,
        },
        {
          'id': 'cable_rear_delt_fly',
          'name': 'Crucifixo Invertido na Polia',
          'locale_key': 'cable_rear_delt_fly',
          'category_id': 'shoulders',
          'type': 'weightReps',
          'notes': 'Polias altas cruzadas, puxar para trás e lateral',
          'equipment': 'Cable',
          'default_rest_time': 60,
          'weight_increment': 1.0,
        },
        // === ADDITIONAL BICEPS ===
        {
          'id': 'cable_rope_curl',
          'name': 'Rosca Corda na Polia',
          'locale_key': 'cable_rope_curl',
          'category_id': 'biceps',
          'type': 'weightReps',
          'notes': 'Polia baixa com corda, pegada neutra',
          'equipment': 'Cable',
          'default_rest_time': 60,
          'weight_increment': 2.5,
        },
        {
          'id': 'bayesian_curl',
          'name': 'Rosca Bayesian',
          'locale_key': 'bayesian_curl',
          'category_id': 'biceps',
          'type': 'weightReps',
          'notes': 'Polia alta, de costas, braços estendidos para trás',
          'equipment': 'Cable',
          'default_rest_time': 60,
          'weight_increment': 2.5,
        },
        {
          'id': 'drag_curl',
          'name': 'Rosca Arrastada',
          'locale_key': 'drag_curl',
          'category_id': 'biceps',
          'type': 'weightReps',
          'notes': 'Barra rente ao corpo, cotovelos indo para trás',
          'equipment': 'Barbell',
          'default_rest_time': 60,
          'weight_increment': 1.0,
        },
        // === ADDITIONAL TRICEPS ===
        {
          'id': 'triceps_parallel_dip',
          'name': 'Tríceps na Paralela',
          'locale_key': 'triceps_parallel_dip',
          'category_id': 'triceps',
          'type': 'weightReps',
          'notes': 'Tronco reto, cotovelos para trás, foco total no tríceps',
          'equipment': 'Bodyweight',
          'default_rest_time': 90,
          'weight_increment': 0,
        },
        {
          'id': 'cable_kickback',
          'name': 'Tríceps Coice na Polia',
          'locale_key': 'cable_kickback',
          'category_id': 'triceps',
          'type': 'weightReps',
          'notes': 'Polia baixa, cotovelo fixo, estender o braço para trás',
          'equipment': 'Cable',
          'default_rest_time': 60,
          'weight_increment': 1.0,
        },
        {
          'id': 'tate_press',
          'name': 'Tate Press',
          'locale_key': 'tate_press',
          'category_id': 'triceps',
          'type': 'weightReps',
          'notes':
              'Deitado, halteres juntos acima do peito, cotovelos abrindo para os lados',
          'equipment': 'Dumbbell',
          'default_rest_time': 60,
          'weight_increment': 1.0,
        },
        // === ADDITIONAL LEGS ===
        {
          'id': 'sumo_squat',
          'name': 'Agachamento Sumô',
          'locale_key': 'sumo_squat',
          'category_id': 'legs',
          'type': 'weightReps',
          'notes':
              'Pés bem afastados, pontas para fora, ênfase em adutores e glúteos',
          'equipment': 'Barbell',
          'default_rest_time': 120,
          'weight_increment': 5.0,
        },
        {
          'id': 'seated_leg_curl',
          'name': 'Cadeira Flexora',
          'locale_key': 'seated_leg_curl',
          'category_id': 'legs',
          'type': 'weightReps',
          'notes': 'Sentado, flexionar as pernas contra a resistência',
          'equipment': 'Machine',
          'default_rest_time': 90,
          'weight_increment': 2.5,
        },
        {
          'id': 'pistol_squat',
          'name': 'Pistol Squat',
          'locale_key': 'pistol_squat',
          'category_id': 'legs',
          'type': 'weightReps',
          'notes': 'Agachamento unilateral, uma perna estendida à frente',
          'equipment': 'Bodyweight',
          'default_rest_time': 90,
          'weight_increment': 0,
        },
        {
          'id': 'wall_sit',
          'name': 'Wall Sit',
          'locale_key': 'wall_sit',
          'category_id': 'legs',
          'type': 'timeOnly',
          'notes': 'Costas na parede, joelhos 90°, manter posição isométrica',
          'equipment': 'Bodyweight',
          'default_rest_time': 60,
          'weight_increment': 0,
        },
        {
          'id': 'box_jump',
          'name': 'Box Jump',
          'locale_key': 'box_jump',
          'category_id': 'legs',
          'type': 'weightReps',
          'notes': 'Salto pliométrico sobre caixa, aterrissar suavemente',
          'equipment': 'Bodyweight',
          'default_rest_time': 90,
          'weight_increment': 0,
        },
        {
          'id': 'glute_kickback',
          'name': 'Coice de Glúteo na Polia',
          'locale_key': 'glute_kickback',
          'category_id': 'legs',
          'type': 'weightReps',
          'notes': 'Polia baixa, estender a perna para trás, foco no glúteo',
          'equipment': 'Cable',
          'default_rest_time': 60,
          'weight_increment': 2.5,
        },
        // === ADDITIONAL CORE ===
        {
          'id': 'mountain_climbers',
          'name': 'Mountain Climbers',
          'locale_key': 'mountain_climbers',
          'category_id': 'core',
          'type': 'weightReps',
          'notes':
              'Em posição de prancha, alternar joelhos em direção ao peito',
          'equipment': 'Bodyweight',
          'default_rest_time': 45,
          'weight_increment': 0,
        },
        {
          'id': 'flutter_kicks',
          'name': 'Flutter Kicks',
          'locale_key': 'flutter_kicks',
          'category_id': 'core',
          'type': 'weightReps',
          'notes':
              'Deitado, pernas esticadas, alternar batidas curtas para cima e baixo',
          'equipment': 'Bodyweight',
          'default_rest_time': 45,
          'weight_increment': 0,
        },
        {
          'id': 'woodchopper',
          'name': 'Woodchopper',
          'locale_key': 'woodchopper',
          'category_id': 'core',
          'type': 'weightReps',
          'notes':
              'Polia alta, girar tronco diagonalmente como se cortasse lenha',
          'equipment': 'Cable',
          'default_rest_time': 60,
          'weight_increment': 2.5,
        },
        {
          'id': 'l_sit',
          'name': 'L-Sit',
          'locale_key': 'l_sit',
          'category_id': 'core',
          'type': 'timeOnly',
          'notes': 'Apoiado nas mãos, pernas esticadas à frente formando um L',
          'equipment': 'Bodyweight',
          'default_rest_time': 60,
          'weight_increment': 0,
        },
        // === ADDITIONAL CARDIO ===
        {
          'id': 'hiit',
          'name': 'HIIT',
          'locale_key': 'hiit',
          'category_id': 'cardio',
          'type': 'timeOnly',
          'notes': 'Treino intervalado de alta intensidade (genérico)',
          'equipment': 'Bodyweight',
          'default_rest_time': 30,
          'weight_increment': 0,
        },
        {
          'id': 'jumping_jacks',
          'name': 'Polichinelos',
          'locale_key': 'jumping_jacks',
          'category_id': 'cardio',
          'type': 'weightReps',
          'notes': 'Abrir e fechar pernas e braços simultaneamente saltando',
          'equipment': 'Bodyweight',
          'default_rest_time': 30,
          'weight_increment': 0,
        },
        {
          'id': 'sprint',
          'name': 'Sprint / Tiro',
          'locale_key': 'sprint',
          'category_id': 'cardio',
          'type': 'distanceTime',
          'notes': 'Corrida curta em máxima velocidade',
          'equipment': 'Bodyweight',
          'default_rest_time': 120,
          'weight_increment': 0,
        },
        {
          'id': 'skater_jumps',
          'name': 'Skater Jumps',
          'locale_key': 'skater_jumps',
          'category_id': 'cardio',
          'type': 'weightReps',
          'notes':
              'Salto lateral de uma perna para a outra, tocando o pé atrás',
          'equipment': 'Bodyweight',
          'default_rest_time': 45,
          'weight_increment': 0,
        },
      ];
      for (final ex in v12Exercises) {
        try {
          await db.insert('exercises', {
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
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        } catch (_) {}
      }
    }
    if (oldVersion < 11) {
      final newExercises = [
        {
          'id': 'db_fly',
          'name': 'Crucifixo com Halteres',
          'locale_key': 'db_fly',
          'category_id': 'chest',
          'type': 'weightReps',
          'notes': 'Deitado no banco, halteres abertos e fechando no centro',
          'equipment': 'Dumbbell',
          'default_rest_time': 60,
          'weight_increment': 1.0,
        },
        {
          'id': 'pullover',
          'name': 'Pullover',
          'locale_key': 'pullover',
          'category_id': 'chest',
          'type': 'weightReps',
          'notes': 'Deitado no banco, halter atrás da cabeça',
          'equipment': 'Dumbbell',
          'default_rest_time': 90,
          'weight_increment': 2.0,
        },
        {
          'id': 'straight_arm_pulldown',
          'name': 'Puxada Braço Reto',
          'locale_key': 'straight_arm_pulldown',
          'category_id': 'back',
          'type': 'weightReps',
          'notes': 'Polia alta, braços esticados puxando até a coxa',
          'equipment': 'Cable',
          'default_rest_time': 60,
          'weight_increment': 2.5,
        },
        {
          'id': 'good_morning',
          'name': 'Good Morning',
          'locale_key': 'good_morning',
          'category_id': 'back',
          'type': 'weightReps',
          'notes': 'Barra nas costas, tronco inclinando para frente',
          'equipment': 'Barbell',
          'default_rest_time': 90,
          'weight_increment': 2.5,
        },
        {
          'id': 'inverted_row',
          'name': 'Remada Invertida',
          'locale_key': 'inverted_row',
          'category_id': 'back',
          'type': 'weightReps',
          'notes': 'Barra baixa, puxar o peito até a barra',
          'equipment': 'Bodyweight',
          'default_rest_time': 60,
          'weight_increment': 0,
        },
        {
          'id': 'cable_lat_raise',
          'name': 'Elevação Lateral na Polia',
          'locale_key': 'cable_lat_raise',
          'category_id': 'shoulders',
          'type': 'weightReps',
          'notes': 'Polia baixa, elevar lateralmente',
          'equipment': 'Cable',
          'default_rest_time': 60,
          'weight_increment': 1.0,
        },
        {
          'id': 'machine_ohp',
          'name': 'Desenvolvimento na Máquina',
          'locale_key': 'machine_ohp',
          'category_id': 'shoulders',
          'type': 'weightReps',
          'notes': 'Máquina de ombro sentado',
          'equipment': 'Machine',
          'default_rest_time': 90,
          'weight_increment': 2.5,
        },
        {
          'id': 'landmine_press',
          'name': 'Desenvolvimento com Barra no Chão',
          'locale_key': 'landmine_press',
          'category_id': 'shoulders',
          'type': 'weightReps',
          'notes': 'Barra apoiada no chão, pressionar em ângulo',
          'equipment': 'Barbell',
          'default_rest_time': 90,
          'weight_increment': 2.5,
        },
        {
          'id': 'incline_curl',
          'name': 'Rosca Inclinada',
          'locale_key': 'incline_curl',
          'category_id': 'biceps',
          'type': 'weightReps',
          'notes': 'Banco inclinado a 45°, braços pendurados para trás',
          'equipment': 'Dumbbell',
          'default_rest_time': 60,
          'weight_increment': 1.0,
        },
        {
          'id': 'reverse_curl',
          'name': 'Rosca Inversa',
          'locale_key': 'reverse_curl',
          'category_id': 'biceps',
          'type': 'weightReps',
          'notes': 'Barra com pegada pronada, foco no braquial',
          'equipment': 'Barbell',
          'default_rest_time': 60,
          'weight_increment': 1.0,
        },
        {
          'id': 'spider_curl',
          'name': 'Rosca Spider',
          'locale_key': 'spider_curl',
          'category_id': 'biceps',
          'type': 'weightReps',
          'notes': 'Banco inclinado, braços pendurados na vertical',
          'equipment': 'Dumbbell',
          'default_rest_time': 60,
          'weight_increment': 1.0,
        },
        {
          'id': 'overhead_cable_ext',
          'name': 'Tríceps Polia Alta',
          'locale_key': 'overhead_cable_ext',
          'category_id': 'triceps',
          'type': 'weightReps',
          'notes': 'Corda ou barra atrás da cabeça, estender acima',
          'equipment': 'Cable',
          'default_rest_time': 60,
          'weight_increment': 2.5,
        },
        {
          'id': 'single_pushdown',
          'name': 'Tríceps Polia Unilateral',
          'locale_key': 'single_pushdown',
          'category_id': 'triceps',
          'type': 'weightReps',
          'notes': 'Cada braço de cada vez, maior foco',
          'equipment': 'Cable',
          'default_rest_time': 60,
          'weight_increment': 1.0,
        },
        {
          'id': 'diamond_pushup',
          'name': 'Flexão Diamante',
          'locale_key': 'diamond_pushup',
          'category_id': 'triceps',
          'type': 'weightReps',
          'notes': 'Mãos juntas formando um diamante, foco no tríceps',
          'equipment': 'Bodyweight',
          'default_rest_time': 60,
          'weight_increment': 0,
        },
        {
          'id': 'adductor_machine',
          'name': 'Máquina de Adutor',
          'locale_key': 'adductor_machine',
          'category_id': 'legs',
          'type': 'weightReps',
          'notes': 'Fechar as pernas contra a resistência',
          'equipment': 'Machine',
          'default_rest_time': 60,
          'weight_increment': 2.5,
        },
        {
          'id': 'abductor_machine',
          'name': 'Máquina de Abdutor',
          'locale_key': 'abductor_machine',
          'category_id': 'legs',
          'type': 'weightReps',
          'notes': 'Abrir as pernas contra a resistência',
          'equipment': 'Machine',
          'default_rest_time': 60,
          'weight_increment': 2.5,
        },
        {
          'id': 'seated_calf',
          'name': 'Panturrilha Sentado',
          'locale_key': 'seated_calf',
          'category_id': 'legs',
          'type': 'weightReps',
          'notes': 'Joelhos a 90°, elevar os calcanhares',
          'equipment': 'Machine',
          'default_rest_time': 60,
          'weight_increment': 5.0,
        },
        {
          'id': 'glute_bridge',
          'name': 'Ponte de Glúteo',
          'locale_key': 'glute_bridge',
          'category_id': 'legs',
          'type': 'weightReps',
          'notes': 'Deitado, joelhos flexionados, elevar o quadril',
          'equipment': 'Bodyweight',
          'default_rest_time': 60,
          'weight_increment': 0,
        },
        {
          'id': 'step_up',
          'name': 'Step Up',
          'locale_key': 'step_up',
          'category_id': 'legs',
          'type': 'weightReps',
          'notes': 'Subir em um banco ou caixa, halteres nas mãos',
          'equipment': 'Dumbbell',
          'default_rest_time': 60,
          'weight_increment': 2.0,
        },
        {
          'id': 'nordic_curl',
          'name': 'Flexão Nórdica',
          'locale_key': 'nordic_curl',
          'category_id': 'legs',
          'type': 'weightReps',
          'notes': 'Joelhos no chão, pés presos, descer controlado',
          'equipment': 'Bodyweight',
          'default_rest_time': 90,
          'weight_increment': 0,
        },
        {
          'id': 'reverse_lunge',
          'name': 'Afundo Reverso',
          'locale_key': 'reverse_lunge',
          'category_id': 'legs',
          'type': 'weightReps',
          'notes': 'Passo para trás em vez de frente',
          'equipment': 'Dumbbell',
          'default_rest_time': 60,
          'weight_increment': 2.0,
        },
        {
          'id': 'side_plank',
          'name': 'Prancha Lateral',
          'locale_key': 'side_plank',
          'category_id': 'core',
          'type': 'timeOnly',
          'notes': 'Corpo reto de lado, antebraço no chão',
          'equipment': 'Bodyweight',
          'default_rest_time': 45,
          'weight_increment': 0,
        },
        {
          'id': 'bicycle_crunch',
          'name': 'Abdominal Bicicleta',
          'locale_key': 'bicycle_crunch',
          'category_id': 'core',
          'type': 'weightReps',
          'notes': 'Deitado, joelho ao cotovelo oposto alternado',
          'equipment': 'Bodyweight',
          'default_rest_time': 45,
          'weight_increment': 0,
        },
        {
          'id': 'reverse_crunch',
          'name': 'Reverse Crunch',
          'locale_key': 'reverse_crunch',
          'category_id': 'core',
          'type': 'weightReps',
          'notes': 'Elevar o quadril do chão contraindo o abdômen',
          'equipment': 'Bodyweight',
          'default_rest_time': 45,
          'weight_increment': 0,
        },
        {
          'id': 'dead_bug',
          'name': 'Dead Bug',
          'locale_key': 'dead_bug',
          'category_id': 'core',
          'type': 'weightReps',
          'notes': 'Braço e perna opostos estendendo simultaneamente',
          'equipment': 'Bodyweight',
          'default_rest_time': 45,
          'weight_increment': 0,
        },
        {
          'id': 'pallof_press',
          'name': 'Pallof Press',
          'locale_key': 'pallof_press',
          'category_id': 'core',
          'type': 'weightReps',
          'notes': 'Polia lateral, empurrar para frente sem girar o tronco',
          'equipment': 'Cable',
          'default_rest_time': 60,
          'weight_increment': 2.5,
        },
        {
          'id': 'elliptical',
          'name': 'Elíptico',
          'locale_key': 'elliptical',
          'category_id': 'cardio',
          'type': 'distanceTime',
          'notes': '',
          'equipment': 'Machine',
          'default_rest_time': 0,
          'weight_increment': 0,
        },
        {
          'id': 'stair_climber',
          'name': 'Escada',
          'locale_key': 'stair_climber',
          'category_id': 'cardio',
          'type': 'timeOnly',
          'notes': 'Simulador de escada',
          'equipment': 'Machine',
          'default_rest_time': 0,
          'weight_increment': 0,
        },
        {
          'id': 'burpee',
          'name': 'Burpee',
          'locale_key': 'burpee',
          'category_id': 'cardio',
          'type': 'weightReps',
          'notes': 'Agachar, pular para trás, flexão, voltar e saltar',
          'equipment': 'Bodyweight',
          'default_rest_time': 60,
          'weight_increment': 0,
        },
        {
          'id': 'battle_ropes',
          'name': 'Corda de Batalha',
          'locale_key': 'battle_ropes',
          'category_id': 'cardio',
          'type': 'timeOnly',
          'notes': 'Ondular as cordas alternadamente ou simultaneamente',
          'equipment': 'Bodyweight',
          'default_rest_time': 60,
          'weight_increment': 0,
        },
      ];
      for (final ex in newExercises) {
        try {
          await db.insert('exercises', {
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
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        } catch (_) {}
      }
    }
    if (oldVersion < 13) {
      // User goals table
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS user_goals (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            scope TEXT NOT NULL,
            metric TEXT NOT NULL,
            period TEXT NOT NULL,
            target_value REAL NOT NULL,
            created_at TEXT NOT NULL,
            is_active INTEGER NOT NULL DEFAULT 1,
            color INTEGER
          )
        ''');
      } catch (_) {}
    }
    if (oldVersion < 14) {
      // Update cardio category color to red (was brown in earlier seeds).
      try {
        await db.rawUpdate(
          'UPDATE exercise_categories SET color = ? WHERE id = ?',
          [0xFFE53935, 'cardio'],
        );
      } catch (_) {}
    }
    if (oldVersion < 15) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS ai_chat_threads (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            last_message_preview TEXT,
            archived INTEGER NOT NULL DEFAULT 0
          )
        ''');
      } catch (_) {}
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS ai_chat_messages (
            id TEXT PRIMARY KEY,
            thread_id TEXT NOT NULL,
            role TEXT NOT NULL,
            content TEXT,
            tool_call_id TEXT,
            tool_name TEXT,
            tool_calls_json TEXT,
            created_at TEXT NOT NULL,
            FOREIGN KEY (thread_id) REFERENCES ai_chat_threads(id) ON DELETE CASCADE
          )
        ''');
      } catch (_) {}
      try {
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_ai_chat_messages_thread ON ai_chat_messages(thread_id, created_at ASC)',
        );
      } catch (_) {}
      try {
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_ai_chat_threads_updated ON ai_chat_threads(updated_at DESC)',
        );
      } catch (_) {}
    }
    if (oldVersion < 16) {
      try {
        await db.execute(
          'ALTER TABLE ai_chat_threads ADD COLUMN is_pinned INTEGER NOT NULL DEFAULT 0',
        );
      } catch (_) {}
      try {
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_ai_chat_threads_pinned_updated ON ai_chat_threads(is_pinned DESC, updated_at DESC)',
        );
      } catch (_) {}
    }
    if (oldVersion < 17) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS ai_routine_proposals (
            id TEXT PRIMARY KEY,
            thread_id TEXT NOT NULL,
            tool_call_id TEXT NOT NULL,
            action TEXT NOT NULL,
            routine_id TEXT,
            before_json TEXT,
            target_json TEXT NOT NULL,
            diff_json TEXT NOT NULL,
            status TEXT NOT NULL,
            applied_routine_id TEXT,
            error_code TEXT,
            error_message TEXT,
            created_at TEXT NOT NULL,
            resolved_at TEXT,
            FOREIGN KEY (thread_id) REFERENCES ai_chat_threads(id) ON DELETE CASCADE
          )
        ''');
      } catch (_) {}
      try {
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_ai_routine_proposals_thread_status ON ai_routine_proposals(thread_id, status, created_at ASC)',
        );
      } catch (_) {}
    }
    if (oldVersion < 18) {
      try {
        await db.execute(
          'ALTER TABLE workouts ADD COLUMN estimated_calories REAL',
        );
      } catch (_) {}
    }
    if (oldVersion < 19) {
      // Repair databases created by versions whose initial schema omitted
      // locale_key even though the seed data and queries already use it.
      try {
        await db.execute(
          'ALTER TABLE exercise_categories ADD COLUMN locale_key TEXT',
        );
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE exercises ADD COLUMN locale_key TEXT');
      } catch (_) {}
    }
    if (oldVersion < 20) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS sleep_entries (
            id TEXT PRIMARY KEY,
            date TEXT NOT NULL UNIQUE,
            sleep_minutes INTEGER NOT NULL,
            actual_sleep_minutes INTEGER,
            bedtime_minutes INTEGER,
            wake_time_minutes INTEGER,
            comment TEXT,
            created_at TEXT NOT NULL
          )
        ''');
      } catch (_) {}
      try {
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_sleep_entries_date ON sleep_entries(date DESC)',
        );
      } catch (_) {}
    }
    if (oldVersion < 21) {
      for (final statement in [
        "ALTER TABLE sleep_entries ADD COLUMN source TEXT NOT NULL DEFAULT 'manual'",
        'ALTER TABLE sleep_entries ADD COLUMN time_in_bed_minutes INTEGER',
        'ALTER TABLE sleep_entries ADD COLUMN estimated_sleep_minutes INTEGER',
      ]) {
        try {
          await db.execute(statement);
        } catch (_) {}
      }
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS sleep_monitor_sessions (
            id TEXT PRIMARY KEY,
            sleep_entry_id TEXT,
            status TEXT NOT NULL,
            started_at TEXT NOT NULL,
            ended_at TEXT,
            utc_offset_start_minutes INTEGER NOT NULL,
            utc_offset_end_minutes INTEGER,
            sensor_mode TEXT NOT NULL DEFAULT 'audio',
            algorithm_version TEXT NOT NULL,
            time_in_bed_minutes INTEGER,
            quiet_minutes INTEGER,
            noisy_minutes INTEGER,
            estimated_sleep_minutes INTEGER,
            noise_event_count INTEGER NOT NULL DEFAULT 0,
            signal_quality_score REAL,
            end_reason TEXT,
            created_at TEXT NOT NULL,
            FOREIGN KEY (sleep_entry_id) REFERENCES sleep_entries(id) ON DELETE CASCADE
          )
        ''');
      } catch (_) {}
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS sleep_monitor_segments (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            started_at TEXT NOT NULL,
            duration_seconds INTEGER NOT NULL,
            audio_rms_dbfs REAL,
            audio_peak_dbfs REAL,
            noise_score REAL,
            classification TEXT NOT NULL,
            valid_fraction REAL NOT NULL,
            noise_burst_count INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (session_id) REFERENCES sleep_monitor_sessions(id) ON DELETE CASCADE
          )
        ''');
      } catch (_) {}
      for (final statement in [
        'CREATE INDEX IF NOT EXISTS idx_sleep_monitor_sessions_status_started ON sleep_monitor_sessions(status, started_at DESC)',
        'CREATE INDEX IF NOT EXISTS idx_sleep_monitor_sessions_entry ON sleep_monitor_sessions(sleep_entry_id)',
        'CREATE INDEX IF NOT EXISTS idx_sleep_monitor_segments_session_started ON sleep_monitor_segments(session_id, started_at ASC)',
      ]) {
        try {
          await db.execute(statement);
        } catch (_) {}
      }
    }
    if (oldVersion < 22) {
      try {
        await db.execute(
          'ALTER TABLE sleep_monitor_sessions ADD COLUMN alarm_at TEXT',
        );
      } catch (_) {}
    }
    if (oldVersion < 23) {
      for (final statement in [
        'ALTER TABLE sleep_monitor_sessions ADD COLUMN monitor_mode TEXT',
        'ALTER TABLE sleep_monitor_sessions ADD COLUMN mission_type TEXT',
        'ALTER TABLE sleep_monitor_sessions ADD COLUMN alarm_dismiss_method TEXT',
        'ALTER TABLE sleep_monitor_sessions ADD COLUMN alarm_dismissed_at TEXT',
      ]) {
        try {
          await db.execute(statement);
        } catch (_) {}
      }
      try {
        await db.execute('''
          UPDATE sleep_monitor_sessions
          SET monitor_mode = CASE
            WHEN alarm_at IS NULL THEN 'monitoring_only'
            ELSE 'alarm_without_mission'
          END
          WHERE monitor_mode IS NULL
        ''');
      } catch (_) {}
      // Mission settings are additive as well. INSERT OR IGNORE keeps this
      // migration safe for databases that were partially upgraded already.
      for (final entry in const <String, String>{
        'sleep_mission_enabled': 'false',
        'sleep_mission_type': 'barcode',
        'sleep_mission_barcode_hash': '',
        'sleep_mission_barcode_salt': '',
        'sleep_mission_barcode_format': '',
        'sleep_mission_registered_at': '',
        'sleep_monitor_default_mode': 'alarm_without_mission',
      }.entries) {
        try {
          await db.insert('app_settings', {
            'key': entry.key,
            'value': entry.value,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        } catch (_) {}
      }
    }
    if (oldVersion < 24) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS traditional_alarms (
            id TEXT PRIMARY KEY,
            hour INTEGER NOT NULL,
            minute INTEGER NOT NULL,
            weekdays_json TEXT NOT NULL DEFAULT '[]',
            enabled INTEGER NOT NULL DEFAULT 1,
            snooze_enabled INTEGER NOT NULL DEFAULT 1,
            snooze_minutes INTEGER NOT NULL DEFAULT 5,
            max_snoozes INTEGER NOT NULL DEFAULT 3,
            requires_mission INTEGER NOT NULL DEFAULT 0,
            next_trigger_at TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_traditional_alarms_next_trigger ON traditional_alarms(enabled, next_trigger_at ASC)',
        );
      } catch (_) {}
    }
    if (oldVersion < 25) {
      try {
        await db.execute(
          'ALTER TABLE traditional_alarms ADD COLUMN max_snoozes INTEGER NOT NULL DEFAULT 3',
        );
      } catch (_) {}
      try {
        await db.insert('app_settings', {
          'key': 'alarm_global_max_snoozes',
          'value': '3',
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      } catch (_) {}
    }
    if (oldVersion < 26) {
      try {
        await db.insert('app_settings', {
          'key': 'alarm_global_snooze_enabled',
          'value': 'true',
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      } catch (_) {}
    }
    if (oldVersion < 27) {
      for (final statement in [
        "ALTER TABLE sleep_monitor_sessions ADD COLUMN analysis_status TEXT NOT NULL DEFAULT 'legacy_unavailable'",
        'ALTER TABLE sleep_monitor_sessions ADD COLUMN sleep_onset_at TEXT',
        'ALTER TABLE sleep_monitor_sessions ADD COLUMN final_wake_at TEXT',
        'ALTER TABLE sleep_monitor_sessions ADD COLUMN sleep_latency_minutes INTEGER',
        'ALTER TABLE sleep_monitor_sessions ADD COLUMN awake_minutes INTEGER',
        'ALTER TABLE sleep_monitor_sessions ADD COLUMN sleeping_minutes INTEGER',
        'ALTER TABLE sleep_monitor_sessions ADD COLUMN deep_sleep_minutes INTEGER',
        'ALTER TABLE sleep_monitor_sessions ADD COLUMN unknown_minutes INTEGER',
        'ALTER TABLE sleep_monitor_sessions ADD COLUMN awakening_count INTEGER',
        'ALTER TABLE sleep_monitor_sessions ADD COLUMN sleep_efficiency REAL',
        'ALTER TABLE sleep_monitor_sessions ADD COLUMN stage_confidence REAL',
        'ALTER TABLE sleep_monitor_sessions ADD COLUMN stage_algorithm_version TEXT',
      ]) {
        try {
          await db.execute(statement);
        } catch (_) {}
      }
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS sleep_stage_epochs (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            started_at TEXT NOT NULL,
            duration_seconds INTEGER NOT NULL,
            stage TEXT NOT NULL,
            confidence REAL NOT NULL,
            awake_probability REAL,
            sleeping_probability REAL,
            deep_probability REAL,
            algorithm_version TEXT NOT NULL,
            source TEXT NOT NULL DEFAULT 'acoustic_model',
            FOREIGN KEY (session_id) REFERENCES sleep_monitor_sessions(id) ON DELETE CASCADE
          )
        ''');
      } catch (_) {}
      try {
        await db.execute(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_sleep_stage_epochs_session_started ON sleep_stage_epochs(session_id, started_at ASC)',
        );
      } catch (_) {}
    }
    if (oldVersion < 28) {
      for (final statement in const [
        'ALTER TABLE sleep_monitor_segments ADD COLUMN spectral_band_energy_0 REAL',
        'ALTER TABLE sleep_monitor_segments ADD COLUMN spectral_band_energy_1 REAL',
        'ALTER TABLE sleep_monitor_segments ADD COLUMN spectral_band_energy_2 REAL',
        'ALTER TABLE sleep_monitor_segments ADD COLUMN spectral_band_energy_3 REAL',
        'ALTER TABLE sleep_monitor_segments ADD COLUMN spectral_band_energy_4 REAL',
        'ALTER TABLE sleep_monitor_segments ADD COLUMN spectral_flatness REAL',
        'ALTER TABLE sleep_monitor_segments ADD COLUMN spectral_centroid_hz REAL',
        'ALTER TABLE sleep_monitor_segments ADD COLUMN breathing_regularity REAL',
        'ALTER TABLE sleep_monitor_segments ADD COLUMN breathing_rate_hz REAL',
        'ALTER TABLE sleep_monitor_segments ADD COLUMN motion_active_seconds REAL',
        'ALTER TABLE sleep_monitor_segments ADD COLUMN motion_mean_deviation_g REAL',
        'ALTER TABLE sleep_monitor_segments ADD COLUMN motion_max_deviation_g REAL',
      ]) {
        try {
          await db.execute(statement);
        } catch (_) {}
      }
    }
    if (oldVersion < 29) {
      // Nutrition module schema. `calories-track` migrated it at version 22
      // while `main` used version 22 for the `alarm_at` column, so the two
      // branches collided on the same version number. Re-gated at 29 (above
      // both branches) so every upgraded database gets the tables; the
      // helper is idempotent (`IF NOT EXISTS`).
      try {
        await _createNutritionSchema(db);
      } catch (_) {}
      // Databases coming from `calories-track` v22 already have the
      // nutrition tables but never ran `main`'s v22 migration (alarm_at).
      // Add the column here as an idempotent safety net.
      try {
        await db.execute(
          'ALTER TABLE sleep_monitor_sessions ADD COLUMN alarm_at TEXT',
        );
      } catch (_) {}
    }
    if (oldVersion < 30) {
      // Nutrition v30: food favorites + saved meal templates. The schema
      // helper is idempotent (`IF NOT EXISTS`), so new tables are created
      // here; the `is_favorite` column is additive and guarded.
      try {
        await _createNutritionSchema(db);
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE foods ADD COLUMN is_favorite INTEGER NOT NULL DEFAULT 0',
        );
      } catch (_) {}
    }
    if (oldVersion < 31) {
      // Nutrition v31: user-defined meal types catalog. The table is
      // created by the idempotent schema helper; the legacy four types
      // are seeded so existing meal_logs keep their sections.
      try {
        await _createNutritionSchema(db);
      } catch (_) {}
      await _seedMealTypes(db);
    }
    if (oldVersion < 32) {
      try {
        await db.execute(
          'ALTER TABLE ai_chat_messages ADD COLUMN attachments_json TEXT',
        );
      } catch (_) {}
    }
    if (oldVersion < 33) {
      // Fresh databases before v33 accidentally omitted this column from
      // _onCreate even though the v10 migration and routine UI use it.
      try {
        await db.execute('ALTER TABLE routine_days ADD COLUMN notes TEXT');
      } catch (_) {}
    }
  }

  /// Creates the full nutrition module schema (v22) using
  /// `IF NOT EXISTS` so it can be invoked both from `_onCreate` and
  /// `_onUpgrade` without duplicating SQL.
  static Future<void> _createNutritionSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS foods (
        id TEXT PRIMARY KEY,
        source TEXT NOT NULL,
        external_id TEXT NOT NULL,
        name TEXT NOT NULL,
        search_name TEXT NOT NULL,
        brand TEXT,
        barcode TEXT,
        source_url TEXT,
        fetched_at TEXT NOT NULL,
        last_used_at TEXT,
        is_favorite INTEGER NOT NULL DEFAULT 0,
        UNIQUE(source, external_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS food_variants (
        id TEXT PRIMARY KEY,
        food_id TEXT NOT NULL,
        label TEXT,
        reference_amount REAL NOT NULL,
        reference_unit TEXT NOT NULL,
        calories REAL,
        protein_g REAL,
        carbs_g REAL,
        fat_g REAL,
        fiber_g REAL,
        sugars_g REAL,
        sodium_mg REAL,
        extra_nutrients_json TEXT,
        is_estimated INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (food_id) REFERENCES foods(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS food_servings (
        id TEXT PRIMARY KEY,
        food_variant_id TEXT NOT NULL,
        label TEXT NOT NULL,
        quantity REAL NOT NULL DEFAULT 1,
        unit TEXT NOT NULL,
        grams_equivalent REAL,
        ml_equivalent REAL,
        FOREIGN KEY (food_variant_id) REFERENCES food_variants(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS meal_logs (
        id TEXT PRIMARY KEY,
        date TEXT NOT NULL,
        meal_type TEXT NOT NULL,
        name TEXT,
        notes TEXT,
        created_at TEXT NOT NULL,
        UNIQUE(date, meal_type)
      )
    ''');
    // User-defined meal types (v31). The catalog is managed in the
    // nutrition settings; the diary renders one section per type. The
    // four legacy keys are seeded with `name = NULL`, which resolves to
    // a localized label; renamed/custom types carry their own name.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS meal_types (
        id TEXT PRIMARY KEY,
        key TEXT UNIQUE NOT NULL,
        name TEXT,
        order_index INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS meal_log_items (
        id TEXT PRIMARY KEY,
        meal_log_id TEXT NOT NULL,
        food_id TEXT,
        food_variant_id TEXT,
        food_name_snapshot TEXT NOT NULL,
        brand_snapshot TEXT,
        quantity REAL NOT NULL,
        unit TEXT NOT NULL,
        calories REAL,
        protein_g REAL,
        carbs_g REAL,
        fat_g REAL,
        fiber_g REAL,
        sugars_g REAL,
        sodium_mg REAL,
        nutrition_snapshot_json TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (meal_log_id) REFERENCES meal_logs(id) ON DELETE CASCADE,
        FOREIGN KEY (food_id) REFERENCES foods(id) ON DELETE SET NULL,
        FOREIGN KEY (food_variant_id) REFERENCES food_variants(id) ON DELETE SET NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS nutrition_goals (
        id TEXT PRIMARY KEY,
        calories REAL,
        protein_g REAL,
        carbs_g REAL,
        fat_g REAL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS saved_meals (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        meal_type TEXT,
        portions REAL NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS saved_meal_items (
        id TEXT PRIMARY KEY,
        saved_meal_id TEXT NOT NULL,
        food_id TEXT,
        food_variant_id TEXT,
        food_name_snapshot TEXT NOT NULL,
        brand_snapshot TEXT,
        quantity REAL NOT NULL,
        unit TEXT NOT NULL,
        order_index INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (saved_meal_id) REFERENCES saved_meals(id) ON DELETE CASCADE,
        FOREIGN KEY (food_id) REFERENCES foods(id) ON DELETE SET NULL,
        FOREIGN KEY (food_variant_id) REFERENCES food_variants(id) ON DELETE SET NULL
      )
    ''');

    for (final statement in <String>[
      'CREATE INDEX IF NOT EXISTS idx_foods_search_name ON foods(search_name)',
      'CREATE INDEX IF NOT EXISTS idx_foods_brand ON foods(brand)',
      'CREATE INDEX IF NOT EXISTS idx_foods_barcode ON foods(barcode)',
      'CREATE INDEX IF NOT EXISTS idx_food_variants_food ON food_variants(food_id)',
      'CREATE INDEX IF NOT EXISTS idx_food_servings_variant ON food_servings(food_variant_id)',
      'CREATE INDEX IF NOT EXISTS idx_meal_logs_date ON meal_logs(date)',
      'CREATE INDEX IF NOT EXISTS idx_meal_log_items_meal ON meal_log_items(meal_log_id, created_at ASC)',
      'CREATE INDEX IF NOT EXISTS idx_meal_types_order ON meal_types(order_index)',
      'CREATE INDEX IF NOT EXISTS idx_nutrition_goals_active ON nutrition_goals(is_active)',
      'CREATE INDEX IF NOT EXISTS idx_saved_meal_items_meal ON saved_meal_items(saved_meal_id, order_index ASC)',
    ]) {
      try {
        await db.execute(statement);
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
    batch.insert('app_settings', {
      'key': 'auto_start_rest_timer',
      'value': 'true',
    });
    batch.insert('app_settings', {
      'key': 'auto_start_workout_timer',
      'value': 'false',
    });
    batch.insert('app_settings', {'key': 'sleep_goal_minutes', 'value': '480'});
    batch.insert('app_settings', {
      'key': 'sleep_mission_enabled',
      'value': 'false',
    });
    batch.insert('app_settings', {
      'key': 'sleep_mission_type',
      'value': 'barcode',
    });
    batch.insert('app_settings', {
      'key': 'sleep_mission_barcode_hash',
      'value': '',
    });
    batch.insert('app_settings', {
      'key': 'sleep_mission_barcode_salt',
      'value': '',
    });
    batch.insert('app_settings', {
      'key': 'sleep_mission_barcode_format',
      'value': '',
    });
    batch.insert('app_settings', {
      'key': 'sleep_mission_registered_at',
      'value': '',
    });
    batch.insert('app_settings', {
      'key': 'sleep_monitor_default_mode',
      'value': 'alarm_without_mission',
    });
    batch.insert('app_settings', {
      'key': 'alarm_global_max_snoozes',
      'value': '3',
    });
    batch.insert('app_settings', {
      'key': 'alarm_global_snooze_enabled',
      'value': 'true',
    });
    batch.insert('app_settings', {
      'key': 'notification_rest_timer_enabled',
      'value': 'true',
    });
    batch.insert('app_settings', {
      'key': 'notification_rest_timer_sound',
      'value': 'true',
    });
    batch.insert('app_settings', {
      'key': 'notification_rest_timer_vibration',
      'value': 'true',
    });
    batch.insert('app_settings', {
      'key': 'notification_workout_timer_enabled',
      'value': 'true',
    });
    batch.insert('app_settings', {
      'key': 'notification_workout_timer_sound',
      'value': 'false',
    });
    batch.insert('app_settings', {
      'key': 'notification_workout_timer_vibration',
      'value': 'false',
    });
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
    await db.insert('ai_chat_threads', {
      'id': id,
      'title': title,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'last_message_preview': lastMessagePreview,
      'archived': archived ? 1 : 0,
      'is_pinned': isPinned ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
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
