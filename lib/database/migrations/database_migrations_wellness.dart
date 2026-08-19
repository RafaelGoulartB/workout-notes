import 'package:sqflite/sqflite.dart';

import '../database_nutrition_schema.dart';
import '../database_seed.dart';

/// Incremental database upgrades extracted from the legacy schema versions.
abstract final class DatabaseWellnessMigrations {
  static Future<void> upgrade(Database db, int oldVersion) async {
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
        await DatabaseNutritionSchema.create(db);
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
        await DatabaseNutritionSchema.create(db);
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
        await DatabaseNutritionSchema.create(db);
      } catch (_) {}
      await DatabaseSeed.seedMealTypes(db);
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
    if (oldVersion < 34) {
      const columns = <String>[
        'potassium_mg',
        'calcium_mg',
        'iron_mg',
        'magnesium_mg',
        'zinc_mg',
        'vitamin_a_ug',
        'vitamin_c_mg',
        'vitamin_d_ug',
        'vitamin_b12_ug',
      ];
      for (final table in <String>['food_variants', 'meal_log_items']) {
        for (final column in columns) {
          try {
            await db.execute('ALTER TABLE $table ADD COLUMN $column REAL');
          } catch (_) {}
        }
      }
    }
    if (oldVersion < 35) {
      const columns = <String>[
        'saturated_fat_g',
        'monounsaturated_fat_g',
        'polyunsaturated_fat_g',
        'trans_fat_g',
      ];
      for (final table in <String>['food_variants', 'meal_log_items']) {
        for (final column in columns) {
          try {
            await db.execute('ALTER TABLE $table ADD COLUMN $column REAL');
          } catch (_) {}
        }
      }
    }
    if (oldVersion < 36) {
      // Saved meal ingredients previously persisted only the generic
      // `serving` unit. With multiple servings that loses which gram/ml
      // equivalence the user selected, so totals could be understated.
      for (final statement in <String>[
        'ALTER TABLE saved_meal_items ADD COLUMN serving_label TEXT',
        'ALTER TABLE saved_meal_items ADD COLUMN serving_grams_equivalent REAL',
        'ALTER TABLE saved_meal_items ADD COLUMN serving_ml_equivalent REAL',
      ]) {
        try {
          await db.execute(statement);
        } catch (_) {}
      }
    }
    if (oldVersion < 40) {
      // v40: daily expenditure (TDEE) and the deficit/maintenance/surplus
      // adjustment that derives the consumption goal. Existing rows are
      // backfilled as `tdee = calories` and `adjustment = maintenance`,
      // which preserves the previous goal exactly (TDEE × 1.0 = goal).
      // This must live in a step ABOVE v39: devices that already upgraded
      // to the v39 sleep migration would skip any lower-numbered block.
      for (final statement in <String>[
        'ALTER TABLE nutrition_goals ADD COLUMN tdee REAL',
        'ALTER TABLE nutrition_goals ADD COLUMN adjustment_kind TEXT',
        'ALTER TABLE nutrition_goals ADD COLUMN adjustment_percent REAL',
      ]) {
        try {
          await db.execute(statement);
        } catch (_) {}
      }
      try {
        await db.execute('''
          UPDATE nutrition_goals
          SET tdee = calories,
              adjustment_kind = 'maintenance',
              adjustment_percent = 0
          WHERE tdee IS NULL
        ''');
      } catch (_) {}
    }
    if (oldVersion < 39) {
      // v39: sleep_monitor_segments and sleep_stage_epochs are transient
      // calculation material. They were only consumed during import to
      // produce the session aggregates (now the only persisted sleep data)
      // and are no longer written or exported. Existing rows are dropped
      // once; a best-effort VACUUM reclaims the file space.
      try {
        await db.execute('DELETE FROM sleep_monitor_segments');
      } catch (_) {}
      try {
        await db.execute('DELETE FROM sleep_stage_epochs');
      } catch (_) {}
      try {
        await db.execute('VACUUM');
      } catch (_) {}
    }
    if (oldVersion < 41) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS run_activities (
            id TEXT PRIMARY KEY,
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
            status TEXT NOT NULL DEFAULT 'completed',
            polyline_summary TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
      } catch (_) {}
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS run_track_points (
            id TEXT PRIMARY KEY,
            activity_id TEXT NOT NULL,
            seq INTEGER NOT NULL,
            lat REAL NOT NULL,
            lng REAL NOT NULL,
            altitude REAL,
            accuracy REAL,
            speed REAL,
            recorded_at TEXT NOT NULL,
            FOREIGN KEY (activity_id) REFERENCES run_activities(id) ON DELETE CASCADE
          )
        ''');
      } catch (_) {}
      try {
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_run_activities_started ON run_activities(started_at DESC)',
        );
      } catch (_) {}
      try {
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_run_track_points_activity_seq ON run_track_points(activity_id, seq ASC)',
        );
      } catch (_) {}
    }
    if (oldVersion < 42) {
      // Blood pressure stores systolic in `value` and diastolic in
      // `secondary_value`, while preserving the generic measurement schema.
      try {
        await db.execute(
          'ALTER TABLE body_measurements ADD COLUMN secondary_value REAL',
        );
      } catch (_) {}
    }
  }
}
