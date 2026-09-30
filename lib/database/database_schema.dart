import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/database/database_medication_schema.dart';
import 'package:workout_notes/database/database_nutrition_schema.dart';
import 'package:workout_notes/database/database_periodization_schema.dart';
import 'package:workout_notes/database/database_run_extras_schema.dart';
import 'package:workout_notes/database/database_run_plan_schema.dart';
import 'package:workout_notes/database/database_run_route_schema.dart';
import 'package:workout_notes/database/database_seed.dart';
import 'package:workout_notes/database/migrations/database_migrations.dart';

/// Owns database creation and coordinates incremental schema upgrades.
abstract final class DatabaseSchema {
  static Future<void> onCreate(Database db, int version) async {
    await createSchema(db);
    await DatabaseSeed.seedMealTypes(db);
    await DatabaseSeed.seedInitialData(db);
  }

  /// Creates every table and index of the current schema without seeding
  /// catalog rows. Tests use it to get the real schema on an empty database.
  static Future<void> createSchema(Database db) async {
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
        created_at TEXT NOT NULL,
        routine_day_id TEXT
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
        secondary_value REAL,
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
        restless_sleep_minutes INTEGER,
        snore_minutes INTEGER,
        awakening_count INTEGER,
        sleep_efficiency REAL,
        stage_confidence REAL,
        stage_algorithm_version TEXT,
        end_reason TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (sleep_entry_id) REFERENCES sleep_entries(id) ON DELETE CASCADE
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

    // Rolling summary of the part of a thread no longer sent on the wire (v50).
    await db.execute('''
      CREATE TABLE ai_chat_thread_summaries (
        thread_id TEXT PRIMARY KEY,
        summary TEXT NOT NULL,
        through_message_id TEXT NOT NULL,
        updated_at TEXT NOT NULL,
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

    // Running activities (v41) — separate from gym workouts.
    await db.execute('''
      CREATE TABLE run_activities (
        id TEXT PRIMARY KEY,
        activity_type TEXT NOT NULL DEFAULT 'running',
        started_at TEXT NOT NULL,
        ended_at TEXT,
        duration_seconds INTEGER NOT NULL DEFAULT 0,
        moving_time_seconds INTEGER NOT NULL DEFAULT 0,
        distance_meters REAL NOT NULL DEFAULT 0,
        avg_pace_sec_per_km REAL,
        max_pace_sec_per_km REAL,
        calories INTEGER,
        title TEXT,
        notes TEXT,
        rpe REAL,
        feeling_rating INTEGER,
        status TEXT NOT NULL DEFAULT 'completed',
        polyline_summary TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        best_split_pace_sec_per_km REAL,
        best_effort_1k_sec INTEGER,
        best_effort_3k_sec INTEGER,
        best_effort_5k_sec INTEGER,
        best_effort_10k_sec INTEGER,
        best_effort_half_sec INTEGER,
        best_effort_marathon_sec INTEGER,
        efforts_computed INTEGER NOT NULL DEFAULT 0,
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
        route_codec_version INTEGER,
        gear_id TEXT
      )
    ''');
    await DatabaseRunRouteSchema.create(db);
    await DatabaseRunExtrasSchema.create(db);
    await DatabaseMedicationSchema.create(db);

    // Nutrition module (v22). Foods, variants, servings, meal logs and
    // goals share a single helper so `_onCreate` and `_onUpgrade` use
    // the same definition.
    await DatabaseNutritionSchema.create(db);
    await DatabasePeriodizationSchema.create(db);
    await DatabaseRunPlanSchema.create(db);

    // Indexes
    await db.execute(
      'CREATE INDEX idx_workouts_date_end ON workouts(date, end_time)',
    );
    await db.execute(
      'CREATE INDEX idx_exercise_entries_workout ON exercise_entries(workout_id)',
    );
    await db.execute(
      'CREATE INDEX idx_sets_entry_state ON sets(exercise_entry_id, is_complete, is_warmup)',
    );
    await db.execute(
      'CREATE INDEX idx_measurements_date ON body_measurements(date)',
    );
    await db.execute(
      'CREATE INDEX idx_measurements_type_date ON body_measurements(type, date DESC, created_at DESC)',
    );
    await db.execute(
      'CREATE INDEX idx_sleep_monitor_sessions_status_started ON sleep_monitor_sessions(status, started_at DESC)',
    );
    await db.execute(
      'CREATE INDEX idx_sleep_monitor_sessions_entry ON sleep_monitor_sessions(sleep_entry_id)',
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
    await db.execute(
      'CREATE INDEX idx_run_activities_started ON run_activities(started_at DESC)',
    );
    await db.execute(
      'CREATE INDEX idx_run_activities_type_started ON run_activities(activity_type, started_at DESC)',
    );
    // Foreign-key lookups added in v56 (shared with the upgrade).
    for (final statement in DatabaseMigrations.v56Indexes) {
      await db.execute(statement);
    }
  }

  static Future<void> onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < DatabaseMigrations.floorVersion) {
      // No installs exist below the migration floor, so rebuilding is safe and
      // keeps the migration history short.
      debugPrint(
        'Database v$oldVersion is below the migration floor '
        '(v${DatabaseMigrations.floorVersion}); recreating the schema.',
      );
      await _dropEverything(db);
      await onCreate(db, newVersion);
      return;
    }
    await DatabaseMigrations.upgrade(db, oldVersion, newVersion);
  }

  /// Drops every table, children before the tables they reference, so the
  /// implicit `DELETE` of `DROP TABLE` never trips a foreign key check.
  static Future<void> _dropEverything(Database db) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master "
      "WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
    );
    final remaining = {for (final row in rows) row['name'] as String};
    final references = <String, Set<String>>{};
    for (final table in remaining) {
      final keys = await db.rawQuery('PRAGMA foreign_key_list("$table")');
      references[table] = {for (final key in keys) key['table'] as String}
        ..remove(table);
    }
    while (remaining.isNotEmpty) {
      final droppable = remaining
          .where(
            (table) =>
                !remaining.any((other) => references[other]!.contains(table)),
          )
          .toList();
      // A reference cycle cannot occur in this schema; drop the rest anyway
      // rather than loop forever.
      final batch = droppable.isEmpty ? remaining.toList() : droppable;
      for (final table in batch) {
        await db.execute('DROP TABLE IF EXISTS "$table"');
        remaining.remove(table);
      }
    }
  }
}
