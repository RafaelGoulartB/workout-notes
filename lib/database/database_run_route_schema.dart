import 'package:sqflite/sqflite.dart';

abstract final class DatabaseRunRouteSchema {
  static Future<void> create(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS run_route_data (
        activity_id TEXT PRIMARY KEY,
        codec_version INTEGER NOT NULL,
        quality TEXT NOT NULL,
        point_count INTEGER NOT NULL,
        original_point_count INTEGER NOT NULL,
        payload BLOB NOT NULL,
        checksum INTEGER NOT NULL,
        compacted_at TEXT NOT NULL,
        FOREIGN KEY (activity_id) REFERENCES run_activities(id) ON DELETE CASCADE
      ) WITHOUT ROWID
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS run_splits (
        activity_id TEXT NOT NULL,
        split_index INTEGER NOT NULL,
        distance_meters REAL NOT NULL,
        duration_seconds INTEGER NOT NULL,
        pace_sec_per_km REAL,
        is_partial INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (activity_id, split_index),
        FOREIGN KEY (activity_id) REFERENCES run_activities(id) ON DELETE CASCADE
      ) WITHOUT ROWID
    ''');
  }
}
