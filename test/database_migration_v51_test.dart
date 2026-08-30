import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/database/database_schema.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('fresh v51 database creates compact route tables and columns', () async {
    final database = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 51,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: DatabaseSchema.onCreate,
      ),
    );
    addTearDown(database.close);

    final columns = await database.rawQuery(
      'PRAGMA table_info(run_activities)',
    );
    expect(columns.map((row) => row['name']), contains('route_codec_version'));
    expect(
      await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('run_route_data', 'run_splits')",
      ),
      hasLength(2),
    );
  });

  test('v51 adds compact route storage without touching legacy points', () async {
    final database = await databaseFactory.openDatabase(inMemoryDatabasePath);
    addTearDown(database.close);
    await database.execute('''
      CREATE TABLE run_activities (
        id TEXT PRIMARY KEY,
        started_at TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'completed'
      )
    ''');
    await database.execute('''
      CREATE TABLE run_track_points (
        id TEXT PRIMARY KEY,
        activity_id TEXT NOT NULL,
        seq INTEGER NOT NULL,
        lat REAL NOT NULL,
        lng REAL NOT NULL,
        recorded_at TEXT NOT NULL
      )
    ''');
    await database.insert('run_activities', {
      'id': 'legacy-run',
      'started_at': '2026-08-25T10:00:00.000Z',
    });
    await database.insert('run_track_points', {
      'id': 'point-1',
      'activity_id': 'legacy-run',
      'seq': 0,
      'lat': -23.5,
      'lng': -46.6,
      'recorded_at': '2026-08-25T10:00:00.000Z',
    });

    await DatabaseSchema.onUpgrade(database, 50, 51);

    final columns = await database.rawQuery(
      'PRAGMA table_info(run_activities)',
    );
    expect(columns.map((row) => row['name']), contains('route_codec_version'));
    expect(
      await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('run_route_data', 'run_splits')",
      ),
      hasLength(2),
    );
    expect(await database.query('run_track_points'), hasLength(1));
  });
}
