import 'package:sqflite/sqflite.dart';

/// Schema for structured running plans (v45, `activated_at` in v46).
///
/// Mirrors the strength side (`routines` → `routine_days` → `routine_exercises`)
/// with a progressive twist: a run plan spans N weeks, each week holds the
/// sessions for specific weekdays, and each session holds an ordered list of
/// steps (warmup / work / recovery / cooldown).
///
/// Repeats are modelled flat: consecutive steps sharing the same
/// `repeat_group` are repeated `repeat_count` times by the engine. This keeps
/// the table shape as simple as `predefined_sets`.
abstract final class DatabaseRunPlanSchema {
  static Future<void> create(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS run_plans (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        notes TEXT,
        goal_kind TEXT NOT NULL DEFAULT 'base',
        race_date TEXT,
        weeks INTEGER NOT NULL DEFAULT 1,
        status TEXT NOT NULL DEFAULT 'active',
        activated_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        CHECK (weeks >= 1)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS run_plan_workouts (
        id TEXT PRIMARY KEY,
        run_plan_id TEXT NOT NULL,
        week_index INTEGER NOT NULL DEFAULT 0,
        day_of_week INTEGER,
        order_index INTEGER NOT NULL DEFAULT 0,
        kind TEXT NOT NULL DEFAULT 'easy',
        name TEXT NOT NULL,
        notes TEXT,
        target_distance_meters REAL,
        target_duration_seconds INTEGER,
        target_pace_sec_per_km REAL,
        effort_zone TEXT,
        created_at TEXT NOT NULL,
        CHECK (week_index >= 0),
        CHECK (day_of_week IS NULL OR (day_of_week >= 1 AND day_of_week <= 7)),
        FOREIGN KEY (run_plan_id) REFERENCES run_plans(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS run_workout_steps (
        id TEXT PRIMARY KEY,
        run_plan_workout_id TEXT NOT NULL,
        order_index INTEGER NOT NULL DEFAULT 0,
        role TEXT NOT NULL DEFAULT 'work',
        metric TEXT NOT NULL DEFAULT 'distance',
        value INTEGER NOT NULL DEFAULT 0,
        repeat_group INTEGER,
        repeat_count INTEGER NOT NULL DEFAULT 1,
        target_pace_min_sec_per_km REAL,
        target_pace_max_sec_per_km REAL,
        notes TEXT,
        CHECK (value >= 0),
        CHECK (repeat_count >= 1),
        FOREIGN KEY (run_plan_workout_id) REFERENCES run_plan_workouts(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS scheduled_runs (
        id TEXT PRIMARY KEY,
        date TEXT NOT NULL,
        run_plan_id TEXT,
        run_plan_workout_id TEXT,
        status TEXT NOT NULL DEFAULT 'planned',
        notes TEXT,
        run_activity_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (run_plan_id) REFERENCES run_plans(id) ON DELETE CASCADE,
        FOREIGN KEY (run_plan_workout_id) REFERENCES run_plan_workouts(id) ON DELETE CASCADE,
        FOREIGN KEY (run_activity_id) REFERENCES run_activities(id) ON DELETE SET NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS run_activity_steps (
        id TEXT PRIMARY KEY,
        run_activity_id TEXT NOT NULL,
        order_index INTEGER NOT NULL DEFAULT 0,
        role TEXT NOT NULL DEFAULT 'work',
        rep_index INTEGER NOT NULL DEFAULT 1,
        planned_metric TEXT,
        planned_value INTEGER,
        planned_pace_sec_per_km REAL,
        actual_distance_meters REAL,
        actual_duration_seconds INTEGER,
        actual_pace_sec_per_km REAL,
        FOREIGN KEY (run_activity_id) REFERENCES run_activities(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_run_plan_workouts_plan ON run_plan_workouts(run_plan_id, week_index, order_index)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_run_workout_steps_workout ON run_workout_steps(run_plan_workout_id, order_index)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_scheduled_runs_date ON scheduled_runs(date)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_scheduled_runs_activity ON scheduled_runs(run_activity_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_run_activity_steps_activity ON run_activity_steps(run_activity_id, order_index)',
    );
  }
}
