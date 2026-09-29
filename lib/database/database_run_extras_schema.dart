import 'package:sqflite/sqflite.dart';

/// Running gear (shoes) and manual laps (v53). Shared by `onCreate` and the
/// v53 upgrade so both paths build identical tables.
abstract final class DatabaseRunExtrasSchema {
  static Future<void> create(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS run_gear (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        brand TEXT,
        notes TEXT,
        initial_distance_meters REAL NOT NULL DEFAULT 0,
        retire_distance_meters REAL NOT NULL DEFAULT 700000,
        is_default INTEGER NOT NULL DEFAULT 0,
        retired_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS run_laps (
        activity_id TEXT NOT NULL,
        lap_index INTEGER NOT NULL,
        start_distance_meters REAL NOT NULL,
        distance_meters REAL NOT NULL,
        duration_seconds INTEGER NOT NULL,
        pace_sec_per_km REAL,
        PRIMARY KEY (activity_id, lap_index),
        FOREIGN KEY (activity_id) REFERENCES run_activities(id) ON DELETE CASCADE
      ) WITHOUT ROWID
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_run_activities_gear ON run_activities(gear_id)',
    );
  }
}
