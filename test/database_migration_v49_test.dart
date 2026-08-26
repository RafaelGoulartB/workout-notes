import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/database/database_schema.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('v49 classifies existing activities as running', () async {
    final database = await databaseFactory.openDatabase(inMemoryDatabasePath);
    addTearDown(database.close);
    await database.execute('''
      CREATE TABLE run_activities (
        id TEXT PRIMARY KEY,
        started_at TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'completed'
      )
    ''');
    await database.insert('run_activities', {
      'id': 'legacy-run',
      'started_at': '2026-08-25T10:00:00.000Z',
    });

    await DatabaseSchema.onUpgrade(database, 48, 49);

    final columns = await database.rawQuery(
      'PRAGMA table_info(run_activities)',
    );
    expect(columns.map((row) => row['name']), contains('activity_type'));
    final rows = await database.query('run_activities');
    expect(rows.single['activity_type'], 'running');
  });
}
