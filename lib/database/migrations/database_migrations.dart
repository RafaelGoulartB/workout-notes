import 'package:sqflite/sqflite.dart';

import 'package:workout_notes/database/database_ai_schema.dart';
import 'package:workout_notes/database/database_medication_schema.dart';
import 'package:workout_notes/database/database_run_extras_schema.dart';
import 'package:workout_notes/database/database_run_plan_schema.dart';
import 'package:workout_notes/database/database_run_route_schema.dart';
import 'package:workout_notes/repositories/run_repository.dart';

/// Incremental database upgrades. Version 37 is the migration floor: no
/// installs exist below it, so `DatabaseSchema.onUpgrade` recreates the
/// database from scratch for older versions and this class only carries the
/// steps from v37 onwards.
abstract final class DatabaseMigrations {
  /// Oldest schema version that can be upgraded in place.
  static const int floorVersion = 37;

  /// Applies every step in `(oldVersion, newVersion]`.
  static Future<void> upgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    bool step(int version) => oldVersion < version && newVersion >= version;

    if (step(40)) {
      // v40: daily expenditure (TDEE) and the deficit/maintenance/surplus
      // adjustment that derives the consumption goal. Existing rows are
      // backfilled as `tdee = calories` and `adjustment = maintenance`,
      // which preserves the previous goal exactly (TDEE × 1.0 = goal).
      for (final statement in const <String>[
        'ALTER TABLE nutrition_goals ADD COLUMN tdee REAL',
        'ALTER TABLE nutrition_goals ADD COLUMN adjustment_kind TEXT',
        'ALTER TABLE nutrition_goals ADD COLUMN adjustment_percent REAL',
      ]) {
        await tryExecute(db, statement);
      }
      await db.execute('''
        UPDATE nutrition_goals
        SET tdee = calories,
            adjustment_kind = 'maintenance',
            adjustment_percent = 0
        WHERE tdee IS NULL
      ''');
    }
    if (step(41)) {
      await tryExecute(db, '''
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
      await tryExecute(db, '''
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
      await tryExecute(
        db,
        'CREATE INDEX IF NOT EXISTS idx_run_activities_started ON run_activities(started_at DESC)',
      );
      await tryExecute(
        db,
        'CREATE INDEX IF NOT EXISTS idx_run_track_points_activity_seq ON run_track_points(activity_id, seq ASC)',
      );
    }
    if (step(42)) {
      // Blood pressure stores systolic in `value` and diastolic in
      // `secondary_value`, while preserving the generic measurement schema.
      await tryExecute(
        db,
        'ALTER TABLE body_measurements ADD COLUMN secondary_value REAL',
      );
    }
    if (step(43)) {
      // Cached GPS effort PRs for all-time run achievements (Strava-like).
      for (final sql in const [
        'ALTER TABLE run_activities ADD COLUMN best_split_pace_sec_per_km REAL',
        'ALTER TABLE run_activities ADD COLUMN best_effort_1k_sec INTEGER',
        'ALTER TABLE run_activities ADD COLUMN best_effort_3k_sec INTEGER',
        'ALTER TABLE run_activities ADD COLUMN best_effort_5k_sec INTEGER',
        'ALTER TABLE run_activities ADD COLUMN best_effort_10k_sec INTEGER',
        'ALTER TABLE run_activities ADD COLUMN best_effort_half_sec INTEGER',
        'ALTER TABLE run_activities ADD COLUMN best_effort_marathon_sec INTEGER',
        'ALTER TABLE run_activities ADD COLUMN efforts_computed INTEGER NOT NULL DEFAULT 0',
      ]) {
        await tryExecute(db, sql);
      }
    }
    if (step(44)) {
      for (final sql in const [
        'CREATE INDEX IF NOT EXISTS idx_workouts_date_end ON workouts(date, end_time)',
        'CREATE INDEX IF NOT EXISTS idx_sets_entry_state ON sets(exercise_entry_id, is_complete, is_warmup)',
        'CREATE INDEX IF NOT EXISTS idx_measurements_type_date ON body_measurements(type, date DESC, created_at DESC)',
      ]) {
        await tryExecute(db, sql);
      }
    }
    if (step(45)) {
      // Structured running plans: templates, weekly schedule and per-step
      // results. `create` is idempotent (CREATE TABLE IF NOT EXISTS).
      await DatabaseRunPlanSchema.create(db);
      // Links an ad-hoc run started straight from a plan (no scheduled row).
      await tryExecute(
        db,
        'ALTER TABLE run_activities ADD COLUMN plan_workout_id TEXT',
      );
    }
    if (step(46)) {
      // The day a running plan was activated. Anchors "week N of the plan"
      // onto the calendar for plans not driven by a periodization phase.
      // At most one plan carries a non-null value at a time.
      await tryExecute(
        db,
        'ALTER TABLE run_plans ADD COLUMN activated_at TEXT',
      );
    }
    if (step(47)) {
      // Lifetime number of times a running plan reached 100%. This survives a
      // progress reset so repeated completions can be celebrated in the UI.
      await tryExecute(
        db,
        'ALTER TABLE run_plans ADD COLUMN completion_count INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (step(48)) {
      // Subjective post-run review. Kept on the activity so it survives plan
      // changes and remains available in history/export.
      for (final sql in const [
        'ALTER TABLE run_activities ADD COLUMN rpe REAL',
        'ALTER TABLE run_activities ADD COLUMN feeling_rating INTEGER',
      ]) {
        await tryExecute(db, sql);
      }
    }
    if (step(49)) {
      // Cardio activities share the existing durable activity envelope while
      // retaining run-only GPS points, pace records and plan semantics.
      await tryExecute(
        db,
        "ALTER TABLE run_activities ADD COLUMN activity_type TEXT NOT NULL DEFAULT 'running'",
      );
      await tryExecute(
        db,
        'CREATE INDEX IF NOT EXISTS idx_run_activities_type_started ON run_activities(activity_type, started_at DESC)',
      );
    }
    if (step(50)) {
      // Rolling summary of the older part of an AI chat thread. Lets the
      // coach keep long-range context without resending the whole transcript.
      await tryExecute(db, '''
        CREATE TABLE IF NOT EXISTS ai_chat_thread_summaries (
          thread_id TEXT PRIMARY KEY,
          summary TEXT NOT NULL,
          through_message_id TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (thread_id) REFERENCES ai_chat_threads(id) ON DELETE CASCADE
        )
      ''');
    }
    if (step(51)) {
      await DatabaseRunRouteSchema.create(db);
      for (final sql in const [
        'ALTER TABLE run_activities ADD COLUMN elevation_gain_meters REAL',
        'ALTER TABLE run_activities ADD COLUMN elevation_loss_meters REAL',
        'ALTER TABLE run_activities ADD COLUMN minimum_altitude_meters REAL',
        'ALTER TABLE run_activities ADD COLUMN maximum_altitude_meters REAL',
        'ALTER TABLE run_activities ADD COLUMN gps_accuracy_mean_meters REAL',
        'ALTER TABLE run_activities ADD COLUMN gps_accuracy_good_fraction REAL',
        'ALTER TABLE run_activities ADD COLUMN raw_point_count INTEGER',
        'ALTER TABLE run_activities ADD COLUMN stored_point_count INTEGER',
        'ALTER TABLE run_activities ADD COLUMN route_quality TEXT',
        'ALTER TABLE run_activities ADD COLUMN route_codec_version INTEGER',
      ]) {
        await tryExecute(db, sql);
      }
    }
    if (step(52)) {
      // Running plans remember the template and wizard inputs they were built
      // from, so they can be re-planned after missed weeks or a fitness test,
      // plus a log of those weekly reviews.
      for (final sql in const [
        'ALTER TABLE run_plans ADD COLUMN template_key TEXT',
        'ALTER TABLE run_plans ADD COLUMN config_json TEXT',
      ]) {
        await tryExecute(db, sql);
      }
      await DatabaseRunPlanSchema.createAdaptations(db);
    }
    if (step(53)) {
      // Running gear (shoe mileage) and manual laps recorded during a run.
      await tryExecute(
        db,
        'ALTER TABLE run_activities ADD COLUMN gear_id TEXT',
      );
      await DatabaseRunExtrasSchema.create(db);
    }
    if (step(54)) {
      // Which routine day a workout trained, so history and the strength
      // hub can name the session and pick the next day.
      await tryExecute(
        db,
        'ALTER TABLE workouts ADD COLUMN routine_day_id TEXT',
      );
    }
    if (step(55)) {
      // Medication reminders and the confirmed / skipped dose log.
      await DatabaseMedicationSchema.create(db);
    }
    if (step(56)) {
      await _upgradeToV56(db);
    }
    if (step(57)) {
      await normalizeRunTimestamps(db);
    }
    if (step(58)) {
      // Bedside sleep engine v6: restless-sleep and snoring minutes.
      for (final column in const ['restless_sleep_minutes', 'snore_minutes']) {
        await tryExecute(
          db,
          'ALTER TABLE sleep_monitor_sessions ADD COLUMN $column INTEGER',
        );
      }
    }
    if (step(59)) {
      // Minute-by-minute night summary for the sleep chart (~2 KB a night).
      await tryExecute(
        db,
        'ALTER TABLE sleep_monitor_sessions ADD COLUMN stage_timeline TEXT',
      );
    }
    if (step(60)) {
      // Smart alarm: the window of the night, when and why it rang and the
      // one-tap morning answer; gentle volume rise per standalone alarm.
      for (final statement in const [
        'ALTER TABLE sleep_monitor_sessions ADD COLUMN smart_window_minutes INTEGER',
        'ALTER TABLE sleep_monitor_sessions ADD COLUMN alarm_fired_at TEXT',
        'ALTER TABLE sleep_monitor_sessions ADD COLUMN alarm_trigger TEXT',
        'ALTER TABLE sleep_monitor_sessions ADD COLUMN wake_feeling INTEGER',
        'ALTER TABLE traditional_alarms ADD COLUMN gradual_volume INTEGER NOT NULL DEFAULT 0',
      ]) {
        await tryExecute(db, statement);
      }
    }
    if (step(61)) {
      // AI Coach v2: generic proposals (routine proposals are copied over and
      // their table dropped), long-term memories, durable turns and folded
      // search text.
      for (final statement in DatabaseAiSchema.v61Columns) {
        await tryExecute(db, statement);
      }
      await DatabaseAiSchema.create(db);
      await DatabaseAiSchema.migrateRoutineProposals(db);
      await DatabaseAiSchema.backfillSearchText(db);
      await db.execute(DatabaseRunPlanSchema.scheduledRunsPlanIndex);
      for (final statement in const [
        'DROP INDEX IF EXISTS idx_ai_routine_proposals_thread_status',
        'DROP TABLE IF EXISTS ai_routine_proposals',
        'DROP INDEX IF EXISTS idx_ai_chat_messages_thread',
        'DROP INDEX IF EXISTS idx_ai_chat_threads_updated',
      ]) {
        await db.execute(statement);
      }
    }
  }

  /// Statements that create the v56 indexes. Also used by `onCreate`.
  static const List<String> v56Indexes = [
    'CREATE INDEX IF NOT EXISTS idx_exercise_entries_exercise ON exercise_entries(exercise_id)',
    'CREATE INDEX IF NOT EXISTS idx_workouts_routine ON workouts(routine_id)',
    'CREATE INDEX IF NOT EXISTS idx_workouts_routine_day ON workouts(routine_day_id)',
    'CREATE INDEX IF NOT EXISTS idx_meal_log_items_food ON meal_log_items(food_id)',
    'CREATE INDEX IF NOT EXISTS idx_meal_log_items_variant ON meal_log_items(food_variant_id)',
    'CREATE INDEX IF NOT EXISTS idx_routine_days_routine ON routine_days(routine_id)',
    'CREATE INDEX IF NOT EXISTS idx_routine_exercises_day ON routine_exercises(routine_day_id)',
    'CREATE INDEX IF NOT EXISTS idx_predefined_sets_exercise ON predefined_sets(routine_exercise_id)',
  ];

  static Future<void> _upgradeToV56(Database db) async {
    // Legacy per-point routes become compact route blobs one last time, then
    // the point table is gone for good.
    final legacyTable = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' "
      "AND name = 'run_track_points'",
    );
    if (legacyTable.isNotEmpty) await RunRepository.compactLegacyRoutes(db);
    for (final sql in const [
      'DROP INDEX IF EXISTS idx_run_track_points_activity_seq',
      'DROP TABLE IF EXISTS run_track_points',
      // Sleep segments/epochs are transient calculation material that has not
      // been written since v39; phase_routine_links has no readers left.
      'DROP INDEX IF EXISTS idx_sleep_monitor_segments_session_started',
      'DROP TABLE IF EXISTS sleep_monitor_segments',
      'DROP INDEX IF EXISTS idx_sleep_stage_epochs_session_started',
      'DROP TABLE IF EXISTS sleep_stage_epochs',
      'DROP INDEX IF EXISTS idx_phase_routine_links_dates',
      'DROP TABLE IF EXISTS phase_routine_links',
      // Redundant: a UNIQUE constraint or a wider index already covers them,
      // or the LIKE '%..%' search cannot use them.
      'DROP INDEX IF EXISTS idx_sleep_entries_date',
      'DROP INDEX IF EXISTS idx_workouts_date',
      'DROP INDEX IF EXISTS idx_sets_entry',
      'DROP INDEX IF EXISTS idx_measurements_type',
      'DROP INDEX IF EXISTS idx_foods_search_name',
      'DROP INDEX IF EXISTS idx_foods_brand',
      ...v56Indexes,
    ]) {
      await db.execute(sql);
    }
  }

  /// Columns of `run_activities` that native spools used to import as UTC
  /// instants (`...Z`).
  static const List<String> _runTimestampColumns = [
    'started_at',
    'ended_at',
    'created_at',
    'updated_at',
  ];

  /// Rewrites UTC run timestamps as local wall-clock ISO strings without an
  /// offset, the format used by every other date in the app. Day attribution
  /// relies on `yyyy-MM-dd` prefixes and string ranges, so a 21:30 run in
  /// UTC-3 (stored `...T00:30Z`) used to land on the next day. The conversion
  /// runs in Dart because SQLite cannot know the device time zone.
  ///
  /// Also applied to restored backups, which may predate the fix.
  static Future<void> normalizeRunTimestamps(DatabaseExecutor db) async {
    final rows = await db.query(
      'run_activities',
      columns: ['id', ..._runTimestampColumns],
      where: _runTimestampColumns.map((c) => "$c LIKE '%Z'").join(' OR '),
    );
    if (rows.isEmpty) return;
    final batch = db.batch();
    for (final row in rows) {
      final values = <String, Object?>{};
      for (final column in _runTimestampColumns) {
        final text = row[column] as String?;
        if (text == null || !text.endsWith('Z')) continue;
        final parsed = DateTime.tryParse(text);
        if (parsed == null) continue;
        values[column] = parsed.toLocal().toIso8601String();
      }
      if (values.isEmpty) continue;
      batch.update(
        'run_activities',
        values,
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
    await batch.commit(noResult: true);
  }

  /// Runs one idempotent migration statement.
  ///
  /// Only errors that mean "this change is already applied" (a duplicate
  /// column or an object that already exists) are swallowed, so re-running a
  /// partially applied upgrade is safe. Any other failure (missing table,
  /// syntax error, disk full) propagates and aborts the upgrade transaction
  /// instead of leaving a silently half-migrated schema.
  static Future<void> tryExecute(
    DatabaseExecutor db,
    String sql, [
    List<Object?>? arguments,
  ]) async {
    try {
      await db.execute(sql, arguments);
    } on DatabaseException catch (error) {
      final message = error.toString().toLowerCase();
      if (message.contains('duplicate column name') ||
          message.contains('already exists')) {
        return;
      }
      rethrow;
    }
  }
}
