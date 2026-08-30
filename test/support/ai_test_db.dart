import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/database/database_run_plan_schema.dart';

Database? _currentDb;

/// Opens a new in-memory FFI database with the minimum schema the AI services
/// need, installs it as [DatabaseHelper.overrideDatabase], and returns the
/// handle. Tests should call [uninstallAiTestDb] in `tearDown`.
Future<Database> installAiTestDb({bool includeRoutineDayNotes = true}) async {
  sqfliteFfiInit();
  if (_currentDb != null && _currentDb!.isOpen) {
    await _currentDb!.close();
  }
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 18,
      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE exercise_categories (id TEXT PRIMARY KEY, name TEXT, color INTEGER, order_index INTEGER, energy_system TEXT, locale_key TEXT)',
        );
        await db.execute(
          'CREATE TABLE exercises (id TEXT PRIMARY KEY, name TEXT, category_id TEXT, type TEXT DEFAULT \'weightReps\', notes TEXT, equipment TEXT, is_favorite INTEGER DEFAULT 0, default_rest_time INTEGER, weight_increment REAL, created_at TEXT, locale_key TEXT)',
        );
        await db.execute(
          'CREATE TABLE workouts (id TEXT PRIMARY KEY, date TEXT, start_time TEXT, end_time TEXT, duration_seconds INTEGER, estimated_calories REAL, comment TEXT, feeling_rating INTEGER, is_from_routine INTEGER DEFAULT 0, routine_id TEXT, pause_start_time TEXT, created_at TEXT)',
        );
        await db.execute(
          'CREATE TABLE exercise_entries (id TEXT PRIMARY KEY, workout_id TEXT, exercise_id TEXT, order_index INTEGER, superset_group_id TEXT, notes TEXT, rest_time_seconds INTEGER, FOREIGN KEY (workout_id) REFERENCES workouts(id) ON DELETE CASCADE, FOREIGN KEY (exercise_id) REFERENCES exercises(id) ON DELETE CASCADE)',
        );
        await db.execute(
          'CREATE TABLE sets (id TEXT PRIMARY KEY, exercise_entry_id TEXT, weight REAL, reps INTEGER, distance REAL, time_seconds INTEGER, is_complete INTEGER DEFAULT 0, is_warmup INTEGER DEFAULT 0, rpe REAL, comment TEXT, order_index INTEGER, FOREIGN KEY (exercise_entry_id) REFERENCES exercise_entries(id) ON DELETE CASCADE)',
        );
        await db.execute(
          'CREATE TABLE routines (id TEXT PRIMARY KEY, name TEXT, notes TEXT, created_at TEXT)',
        );
        await db.execute(
          'CREATE TABLE routine_days (id TEXT PRIMARY KEY, routine_id TEXT, name TEXT, order_index INTEGER${includeRoutineDayNotes ? ', notes TEXT' : ''}, FOREIGN KEY (routine_id) REFERENCES routines(id) ON DELETE CASCADE)',
        );
        await db.execute(
          'CREATE TABLE routine_exercises (id TEXT PRIMARY KEY, routine_day_id TEXT, exercise_id TEXT, order_index INTEGER, superset_group_id TEXT, rest_time_seconds INTEGER, FOREIGN KEY (routine_day_id) REFERENCES routine_days(id) ON DELETE CASCADE, FOREIGN KEY (exercise_id) REFERENCES exercises(id) ON DELETE CASCADE)',
        );
        await db.execute(
          'CREATE TABLE predefined_sets (id TEXT PRIMARY KEY, routine_exercise_id TEXT, weight REAL, reps INTEGER, distance REAL, time_seconds INTEGER, is_warmup INTEGER DEFAULT 0, order_index INTEGER, FOREIGN KEY (routine_exercise_id) REFERENCES routine_exercises(id) ON DELETE CASCADE)',
        );
        await db.execute(
          'CREATE TABLE body_measurements (id TEXT PRIMARY KEY, type TEXT, value REAL, unit TEXT DEFAULT \'kg\', date TEXT, comment TEXT, time_of_day TEXT, is_fasted INTEGER, photos_paths TEXT, side TEXT, created_at TEXT)',
        );
        await db.execute(
          'CREATE TABLE user_goals (id TEXT PRIMARY KEY, title TEXT, scope TEXT, metric TEXT, period TEXT, target_value REAL, created_at TEXT, is_active INTEGER DEFAULT 1, color INTEGER)',
        );
        await db.execute(
          'CREATE TABLE ai_chat_threads (id TEXT PRIMARY KEY, title TEXT, created_at TEXT, updated_at TEXT, last_message_preview TEXT, archived INTEGER DEFAULT 0, is_pinned INTEGER DEFAULT 0)',
        );
        await db.execute(
          'CREATE TABLE ai_chat_messages (id TEXT PRIMARY KEY, thread_id TEXT, role TEXT, content TEXT, tool_call_id TEXT, tool_name TEXT, tool_calls_json TEXT, attachments_json TEXT, created_at TEXT, FOREIGN KEY (thread_id) REFERENCES ai_chat_threads(id) ON DELETE CASCADE)',
        );
        await db.execute(
          'CREATE TABLE ai_chat_thread_summaries (thread_id TEXT PRIMARY KEY, summary TEXT NOT NULL, through_message_id TEXT NOT NULL, updated_at TEXT NOT NULL, FOREIGN KEY (thread_id) REFERENCES ai_chat_threads(id) ON DELETE CASCADE)',
        );
        await db.execute(
          'CREATE TABLE ai_routine_proposals (id TEXT PRIMARY KEY, thread_id TEXT NOT NULL, tool_call_id TEXT NOT NULL, action TEXT NOT NULL, routine_id TEXT, before_json TEXT, target_json TEXT NOT NULL, diff_json TEXT NOT NULL, status TEXT NOT NULL, applied_routine_id TEXT, error_code TEXT, error_message TEXT, created_at TEXT NOT NULL, resolved_at TEXT, FOREIGN KEY (thread_id) REFERENCES ai_chat_threads(id) ON DELETE CASCADE)',
        );
        await db.execute(
          'CREATE TABLE foods (id TEXT PRIMARY KEY, source TEXT NOT NULL, external_id TEXT NOT NULL, name TEXT NOT NULL, search_name TEXT NOT NULL, brand TEXT, barcode TEXT, source_url TEXT, fetched_at TEXT NOT NULL, last_used_at TEXT, is_favorite INTEGER NOT NULL DEFAULT 0, UNIQUE(source, external_id))',
        );
        await db.execute(
          'CREATE TABLE food_variants (id TEXT PRIMARY KEY, food_id TEXT NOT NULL, label TEXT, reference_amount REAL NOT NULL, reference_unit TEXT NOT NULL, calories REAL, protein_g REAL, carbs_g REAL, fat_g REAL, saturated_fat_g REAL, monounsaturated_fat_g REAL, polyunsaturated_fat_g REAL, trans_fat_g REAL, fiber_g REAL, sugars_g REAL, sodium_mg REAL, potassium_mg REAL, calcium_mg REAL, iron_mg REAL, magnesium_mg REAL, zinc_mg REAL, vitamin_a_ug REAL, vitamin_c_mg REAL, vitamin_d_ug REAL, vitamin_b12_ug REAL, extra_nutrients_json TEXT, is_estimated INTEGER NOT NULL DEFAULT 0, FOREIGN KEY (food_id) REFERENCES foods(id) ON DELETE CASCADE)',
        );
        await db.execute(
          'CREATE TABLE food_servings (id TEXT PRIMARY KEY, food_variant_id TEXT NOT NULL, label TEXT NOT NULL, quantity REAL NOT NULL DEFAULT 1, unit TEXT NOT NULL, grams_equivalent REAL, ml_equivalent REAL, FOREIGN KEY (food_variant_id) REFERENCES food_variants(id) ON DELETE CASCADE)',
        );
        await db.execute(
          'CREATE TABLE meal_logs (id TEXT PRIMARY KEY, date TEXT NOT NULL, meal_type TEXT NOT NULL, name TEXT, notes TEXT, created_at TEXT NOT NULL, UNIQUE(date, meal_type))',
        );
        await db.execute(
          'CREATE TABLE meal_log_items (id TEXT PRIMARY KEY, meal_log_id TEXT NOT NULL, food_id TEXT, food_variant_id TEXT, food_name_snapshot TEXT NOT NULL, brand_snapshot TEXT, quantity REAL NOT NULL, unit TEXT NOT NULL, calories REAL, protein_g REAL, carbs_g REAL, fat_g REAL, saturated_fat_g REAL, monounsaturated_fat_g REAL, polyunsaturated_fat_g REAL, trans_fat_g REAL, fiber_g REAL, sugars_g REAL, sodium_mg REAL, potassium_mg REAL, calcium_mg REAL, iron_mg REAL, magnesium_mg REAL, zinc_mg REAL, vitamin_a_ug REAL, vitamin_c_mg REAL, vitamin_d_ug REAL, vitamin_b12_ug REAL, nutrition_snapshot_json TEXT NOT NULL, created_at TEXT NOT NULL, FOREIGN KEY (meal_log_id) REFERENCES meal_logs(id) ON DELETE CASCADE, FOREIGN KEY (food_id) REFERENCES foods(id) ON DELETE SET NULL, FOREIGN KEY (food_variant_id) REFERENCES food_variants(id) ON DELETE SET NULL)',
        );
        await db.execute(
          'CREATE TABLE meal_types (id TEXT PRIMARY KEY, key TEXT UNIQUE NOT NULL, name TEXT, order_index INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE nutrition_goals (id TEXT PRIMARY KEY, calories REAL, protein_g REAL, carbs_g REAL, fat_g REAL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, is_active INTEGER NOT NULL DEFAULT 1)',
        );
        await db.execute(
          'CREATE TABLE saved_meals (id TEXT PRIMARY KEY, name TEXT NOT NULL, meal_type TEXT, portions REAL NOT NULL DEFAULT 1, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE saved_meal_items (id TEXT PRIMARY KEY, saved_meal_id TEXT NOT NULL, food_id TEXT, food_variant_id TEXT, food_name_snapshot TEXT NOT NULL, brand_snapshot TEXT, quantity REAL NOT NULL, unit TEXT NOT NULL, serving_label TEXT, serving_grams_equivalent REAL, serving_ml_equivalent REAL, order_index INTEGER NOT NULL DEFAULT 0, FOREIGN KEY (saved_meal_id) REFERENCES saved_meals(id) ON DELETE CASCADE, FOREIGN KEY (food_id) REFERENCES foods(id) ON DELETE SET NULL, FOREIGN KEY (food_variant_id) REFERENCES food_variants(id) ON DELETE SET NULL)',
        );
        await db.execute(
          "CREATE TABLE sleep_entries (id TEXT PRIMARY KEY, date TEXT NOT NULL UNIQUE, sleep_minutes INTEGER NOT NULL, actual_sleep_minutes INTEGER, bedtime_minutes INTEGER, wake_time_minutes INTEGER, comment TEXT, source TEXT NOT NULL DEFAULT 'manual', time_in_bed_minutes INTEGER, estimated_sleep_minutes INTEGER, created_at TEXT NOT NULL)",
        );
        await db.execute(
          "CREATE TABLE sleep_monitor_sessions (id TEXT PRIMARY KEY, sleep_entry_id TEXT, status TEXT NOT NULL, started_at TEXT NOT NULL, ended_at TEXT, alarm_at TEXT, monitor_mode TEXT, mission_type TEXT, alarm_dismiss_method TEXT, alarm_dismissed_at TEXT, utc_offset_start_minutes INTEGER NOT NULL, utc_offset_end_minutes INTEGER, sensor_mode TEXT NOT NULL DEFAULT 'audio', algorithm_version TEXT NOT NULL, time_in_bed_minutes INTEGER, quiet_minutes INTEGER, noisy_minutes INTEGER, estimated_sleep_minutes INTEGER, noise_event_count INTEGER NOT NULL DEFAULT 0, signal_quality_score REAL, analysis_status TEXT NOT NULL DEFAULT 'legacy_unavailable', sleep_onset_at TEXT, final_wake_at TEXT, sleep_latency_minutes INTEGER, awake_minutes INTEGER, sleeping_minutes INTEGER, deep_sleep_minutes INTEGER, unknown_minutes INTEGER, awakening_count INTEGER, sleep_efficiency REAL, stage_confidence REAL, stage_algorithm_version TEXT, end_reason TEXT, created_at TEXT NOT NULL, FOREIGN KEY (sleep_entry_id) REFERENCES sleep_entries(id) ON DELETE CASCADE)",
        );
        await db.execute(
          "CREATE TABLE sleep_stage_epochs (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, started_at TEXT NOT NULL, duration_seconds INTEGER NOT NULL, stage TEXT NOT NULL, confidence REAL NOT NULL, awake_probability REAL, sleeping_probability REAL, deep_probability REAL, algorithm_version TEXT NOT NULL, source TEXT NOT NULL DEFAULT 'acoustic_model', FOREIGN KEY (session_id) REFERENCES sleep_monitor_sessions(id) ON DELETE CASCADE)",
        );
        await db.execute(
          'CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT)',
        );
        await db.execute('''
          CREATE TABLE run_activities (
            id TEXT PRIMARY KEY, activity_type TEXT NOT NULL DEFAULT 'running',
            started_at TEXT NOT NULL, ended_at TEXT, duration_seconds INTEGER NOT NULL DEFAULT 0,
            moving_time_seconds INTEGER NOT NULL DEFAULT 0, distance_meters REAL NOT NULL DEFAULT 0,
            avg_pace_sec_per_km REAL, max_pace_sec_per_km REAL, calories INTEGER,
            title TEXT, notes TEXT, rpe REAL, feeling_rating INTEGER,
            status TEXT NOT NULL DEFAULT 'completed', polyline_summary TEXT,
            created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
            best_split_pace_sec_per_km REAL, best_effort_1k_sec INTEGER,
            best_effort_3k_sec INTEGER, best_effort_5k_sec INTEGER,
            best_effort_10k_sec INTEGER, best_effort_half_sec INTEGER,
            best_effort_marathon_sec INTEGER, efforts_computed INTEGER NOT NULL DEFAULT 0,
              plan_workout_id TEXT,
              elevation_gain_meters REAL,
              elevation_loss_meters REAL,
              minimum_altitude_meters REAL,
              maximum_altitude_meters REAL,
              gps_accuracy_mean_meters REAL,
              gps_accuracy_good_fraction REAL,
              raw_point_count INTEGER,
              stored_point_count INTEGER,
              route_quality TEXT,
              route_codec_version INTEGER
          )
        ''');
        await db.execute('''
            CREATE TABLE run_track_points (
            id TEXT PRIMARY KEY, activity_id TEXT NOT NULL, seq INTEGER NOT NULL,
            lat REAL NOT NULL, lng REAL NOT NULL, altitude REAL, accuracy REAL,
            speed REAL, recorded_at TEXT NOT NULL,
            FOREIGN KEY (activity_id) REFERENCES run_activities(id) ON DELETE CASCADE
            )
          ''');
        await db.execute('''
            CREATE TABLE run_route_data (
              activity_id TEXT PRIMARY KEY,
              codec_version INTEGER NOT NULL,
              quality TEXT NOT NULL,
              point_count INTEGER NOT NULL,
              original_point_count INTEGER NOT NULL,
              payload BLOB NOT NULL,
              checksum INTEGER NOT NULL,
              compacted_at TEXT NOT NULL
            )
          ''');
        await db.execute('''
            CREATE TABLE run_splits (
              activity_id TEXT NOT NULL,
              split_index INTEGER NOT NULL,
              distance_meters REAL NOT NULL,
              duration_seconds INTEGER NOT NULL,
              pace_sec_per_km REAL,
              is_partial INTEGER NOT NULL DEFAULT 0,
              PRIMARY KEY (activity_id, split_index)
            )
          ''');
        await DatabaseRunPlanSchema.create(db);
      },
    ),
  );
  _currentDb = db;
  DatabaseHelper.overrideDatabase = db;
  return db;
}

Future<void> uninstallAiTestDb() async {
  if (_currentDb != null && _currentDb!.isOpen) {
    await _currentDb!.close();
  }
  _currentDb = null;
  DatabaseHelper.overrideDatabase = null;
}
