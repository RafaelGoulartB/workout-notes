/// Schema of a database created by app version 37 (the migration floor).
///
/// Captured from the real `onCreate` of that release so upgrade tests start
/// from the same tables and indexes an installed v37 database has. Do not edit
/// to follow current schema changes: this is a historical snapshot.
const schemaV37Statements = <String>[
  '''
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
''',
  '''
CREATE TABLE ai_chat_threads (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        last_message_preview TEXT,
        archived INTEGER NOT NULL DEFAULT 0,
        is_pinned INTEGER NOT NULL DEFAULT 0
      )
''',
  '''
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
''',
  '''
CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
''',
  '''
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
''',
  '''
CREATE TABLE exercise_categories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        locale_key TEXT,
        color INTEGER NOT NULL,
        order_index INTEGER NOT NULL DEFAULT 0,
        energy_system TEXT NOT NULL DEFAULT 'anaerobic'
      )
''',
  '''
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
''',
  '''
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
''',
  '''
CREATE TABLE food_servings (
        id TEXT PRIMARY KEY,
        food_variant_id TEXT NOT NULL,
        label TEXT NOT NULL,
        quantity REAL NOT NULL DEFAULT 1,
        unit TEXT NOT NULL,
        grams_equivalent REAL,
        ml_equivalent REAL,
        FOREIGN KEY (food_variant_id) REFERENCES food_variants(id) ON DELETE CASCADE
      )
''',
  '''
CREATE TABLE food_variants (
        id TEXT PRIMARY KEY,
        food_id TEXT NOT NULL,
        label TEXT,
        reference_amount REAL NOT NULL,
        reference_unit TEXT NOT NULL,
        calories REAL,
        protein_g REAL,
        carbs_g REAL,
        fat_g REAL,
        saturated_fat_g REAL,
        monounsaturated_fat_g REAL,
        polyunsaturated_fat_g REAL,
        trans_fat_g REAL,
        fiber_g REAL,
        sugars_g REAL,
        sodium_mg REAL,
        potassium_mg REAL,
        calcium_mg REAL,
        iron_mg REAL,
        magnesium_mg REAL,
        zinc_mg REAL,
        vitamin_a_ug REAL,
        vitamin_c_mg REAL,
        vitamin_d_ug REAL,
        vitamin_b12_ug REAL,
        extra_nutrients_json TEXT,
        is_estimated INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (food_id) REFERENCES foods(id) ON DELETE CASCADE
      )
''',
  '''
CREATE TABLE foods (
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
''',
  '''
CREATE TABLE meal_log_items (
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
        saturated_fat_g REAL,
        monounsaturated_fat_g REAL,
        polyunsaturated_fat_g REAL,
        trans_fat_g REAL,
        fiber_g REAL,
        sugars_g REAL,
        sodium_mg REAL,
        potassium_mg REAL,
        calcium_mg REAL,
        iron_mg REAL,
        magnesium_mg REAL,
        zinc_mg REAL,
        vitamin_a_ug REAL,
        vitamin_c_mg REAL,
        vitamin_d_ug REAL,
        vitamin_b12_ug REAL,
        nutrition_snapshot_json TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (meal_log_id) REFERENCES meal_logs(id) ON DELETE CASCADE,
        FOREIGN KEY (food_id) REFERENCES foods(id) ON DELETE SET NULL,
        FOREIGN KEY (food_variant_id) REFERENCES food_variants(id) ON DELETE SET NULL
      )
''',
  '''
CREATE TABLE meal_logs (
        id TEXT PRIMARY KEY,
        date TEXT NOT NULL,
        meal_type TEXT NOT NULL,
        name TEXT,
        notes TEXT,
        created_at TEXT NOT NULL,
        UNIQUE(date, meal_type)
      )
''',
  '''
CREATE TABLE meal_types (
        id TEXT PRIMARY KEY,
        key TEXT UNIQUE NOT NULL,
        name TEXT,
        order_index INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
''',
  '''
CREATE TABLE nutrition_goals (
        id TEXT PRIMARY KEY,
        calories REAL,
        protein_g REAL,
        carbs_g REAL,
        fat_g REAL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1
      )
''',
  '''
CREATE TABLE periodization_checkins (
        id TEXT PRIMARY KEY,
        phase_id TEXT NOT NULL,
        week_start TEXT NOT NULL,
        energy INTEGER NOT NULL,
        hunger INTEGER NOT NULL,
        recovery INTEGER NOT NULL,
        performance TEXT NOT NULL,
        decision TEXT NOT NULL,
        notes TEXT,
        metrics_json TEXT NOT NULL DEFAULT '{}',
        targets_snapshot_json TEXT NOT NULL DEFAULT '{}',
        created_at TEXT NOT NULL,
        UNIQUE (phase_id, week_start),
        FOREIGN KEY (phase_id) REFERENCES periodization_phases(id) ON DELETE CASCADE
      )
''',
  '''
CREATE TABLE periodization_phases (
        id TEXT PRIMARY KEY,
        plan_id TEXT NOT NULL,
        name TEXT NOT NULL,
        template_key TEXT,
        color INTEGER NOT NULL,
        start_date TEXT NOT NULL,
        end_date TEXT NOT NULL,
        intent TEXT,
        order_index INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        CHECK (end_date >= start_date),
        FOREIGN KEY (plan_id) REFERENCES periodization_plans(id) ON DELETE CASCADE
      )
''',
  '''
CREATE TABLE periodization_plans (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        start_date TEXT NOT NULL,
        end_date TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'draft',
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        CHECK (end_date >= start_date)
      )
''',
  '''
CREATE TABLE phase_routine_links (
        id TEXT PRIMARY KEY,
        phase_id TEXT NOT NULL,
        routine_id TEXT NOT NULL,
        starts_on TEXT NOT NULL,
        ends_on TEXT NOT NULL,
        created_at TEXT NOT NULL,
        CHECK (ends_on >= starts_on),
        FOREIGN KEY (phase_id) REFERENCES periodization_phases(id) ON DELETE CASCADE,
        FOREIGN KEY (routine_id) REFERENCES routines(id) ON DELETE CASCADE
      )
''',
  '''
CREATE TABLE phase_targets (
        id TEXT PRIMARY KEY,
        phase_id TEXT NOT NULL,
        nutrition_json TEXT NOT NULL DEFAULT '{}',
        training_json TEXT NOT NULL DEFAULT '{}',
        body_json TEXT NOT NULL DEFAULT '{}',
        sleep_json TEXT NOT NULL DEFAULT '{}',
        version INTEGER NOT NULL,
        valid_from TEXT NOT NULL,
        created_at TEXT NOT NULL,
        UNIQUE (phase_id, version),
        FOREIGN KEY (phase_id) REFERENCES periodization_phases(id) ON DELETE CASCADE
      )
''',
  '''
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
''',
  '''
CREATE TABLE routine_days (
        id TEXT PRIMARY KEY,
        routine_id TEXT NOT NULL,
        name TEXT,
        notes TEXT,
        order_index INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (routine_id) REFERENCES routines(id) ON DELETE CASCADE
      )
''',
  '''
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
''',
  '''
CREATE TABLE routines (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        notes TEXT,
        created_at TEXT NOT NULL
      )
''',
  '''
CREATE TABLE saved_meal_items (
        id TEXT PRIMARY KEY,
        saved_meal_id TEXT NOT NULL,
        food_id TEXT,
        food_variant_id TEXT,
        food_name_snapshot TEXT NOT NULL,
        brand_snapshot TEXT,
        quantity REAL NOT NULL,
        unit TEXT NOT NULL,
        serving_label TEXT,
        serving_grams_equivalent REAL,
        serving_ml_equivalent REAL,
        order_index INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (saved_meal_id) REFERENCES saved_meals(id) ON DELETE CASCADE,
        FOREIGN KEY (food_id) REFERENCES foods(id) ON DELETE SET NULL,
        FOREIGN KEY (food_variant_id) REFERENCES food_variants(id) ON DELETE SET NULL
      )
''',
  '''
CREATE TABLE saved_meals (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        meal_type TEXT,
        portions REAL NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
''',
  '''
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
''',
  '''
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
''',
  '''
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
''',
  '''
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
''',
  '''
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
''',
  '''
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
''',
  '''
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
''',
  '''
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
''',
  '''
CREATE INDEX idx_ai_chat_messages_thread ON ai_chat_messages(thread_id, created_at ASC)
''',
  '''
CREATE INDEX idx_ai_chat_threads_pinned_updated ON ai_chat_threads(is_pinned DESC, updated_at DESC)
''',
  '''
CREATE INDEX idx_ai_chat_threads_updated ON ai_chat_threads(updated_at DESC)
''',
  '''
CREATE INDEX idx_ai_routine_proposals_thread_status ON ai_routine_proposals(thread_id, status, created_at ASC)
''',
  '''
CREATE INDEX idx_exercise_entries_workout ON exercise_entries(workout_id)
''',
  '''
CREATE INDEX idx_food_servings_variant ON food_servings(food_variant_id)
''',
  '''
CREATE INDEX idx_food_variants_food ON food_variants(food_id)
''',
  '''
CREATE INDEX idx_foods_barcode ON foods(barcode)
''',
  '''
CREATE INDEX idx_foods_brand ON foods(brand)
''',
  '''
CREATE INDEX idx_foods_search_name ON foods(search_name)
''',
  '''
CREATE INDEX idx_meal_log_items_meal ON meal_log_items(meal_log_id, created_at ASC)
''',
  '''
CREATE INDEX idx_meal_logs_date ON meal_logs(date)
''',
  '''
CREATE INDEX idx_meal_types_order ON meal_types(order_index)
''',
  '''
CREATE INDEX idx_measurements_date ON body_measurements(date)
''',
  '''
CREATE INDEX idx_measurements_type ON body_measurements(type)
''',
  '''
CREATE INDEX idx_nutrition_goals_active ON nutrition_goals(is_active)
''',
  '''
CREATE INDEX idx_periodization_checkins_phase_week ON periodization_checkins(phase_id, week_start DESC)
''',
  '''
CREATE UNIQUE INDEX idx_periodization_one_active_plan ON periodization_plans(status) WHERE status = 'active'
''',
  '''
CREATE INDEX idx_periodization_phases_dates ON periodization_phases(start_date, end_date)
''',
  '''
CREATE INDEX idx_periodization_phases_plan_dates ON periodization_phases(plan_id, start_date, end_date)
''',
  '''
CREATE INDEX idx_periodization_plans_status ON periodization_plans(status, updated_at DESC)
''',
  '''
CREATE INDEX idx_phase_routine_links_dates ON phase_routine_links(phase_id, starts_on, ends_on)
''',
  '''
CREATE INDEX idx_phase_targets_effective ON phase_targets(phase_id, valid_from DESC, version DESC)
''',
  '''
CREATE INDEX idx_saved_meal_items_meal ON saved_meal_items(saved_meal_id, order_index ASC)
''',
  '''
CREATE INDEX idx_sets_entry ON sets(exercise_entry_id)
''',
  '''
CREATE INDEX idx_sleep_entries_date ON sleep_entries(date DESC)
''',
  '''
CREATE INDEX idx_sleep_monitor_segments_session_started ON sleep_monitor_segments(session_id, started_at ASC)
''',
  '''
CREATE INDEX idx_sleep_monitor_sessions_entry ON sleep_monitor_sessions(sleep_entry_id)
''',
  '''
CREATE INDEX idx_sleep_monitor_sessions_status_started ON sleep_monitor_sessions(status, started_at DESC)
''',
  '''
CREATE UNIQUE INDEX idx_sleep_stage_epochs_session_started ON sleep_stage_epochs(session_id, started_at ASC)
''',
  '''
CREATE INDEX idx_traditional_alarms_next_trigger ON traditional_alarms(enabled, next_trigger_at ASC)
''',
  '''
CREATE INDEX idx_workouts_date ON workouts(date)
''',
];
