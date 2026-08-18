import 'package:sqflite/sqflite.dart';

abstract final class DatabasePeriodizationSchema {
  static Future<void> create(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS periodization_plans (
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
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS periodization_phases (
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
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS phase_targets (
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
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS phase_routine_links (
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
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS periodization_checkins (
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
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_periodization_plans_status ON periodization_plans(status, updated_at DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_periodization_phases_plan_dates ON periodization_phases(plan_id, start_date, end_date)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_periodization_phases_dates ON periodization_phases(start_date, end_date)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_phase_targets_effective ON phase_targets(phase_id, valid_from DESC, version DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_phase_routine_links_dates ON phase_routine_links(phase_id, starts_on, ends_on)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_periodization_checkins_phase_week ON periodization_checkins(phase_id, week_start DESC)',
    );
    await db.execute(
      "CREATE UNIQUE INDEX IF NOT EXISTS idx_periodization_one_active_plan ON periodization_plans(status) WHERE status = 'active'",
    );
  }
}
