import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/database/database_schema.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'v48 adds subjective review fields to existing run activities',
    () async {
      final database = await databaseFactory.openDatabase(inMemoryDatabasePath);
      addTearDown(database.close);
      await database.execute('''
      CREATE TABLE run_activities (
        id TEXT PRIMARY KEY,
        started_at TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'completed',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

      await DatabaseSchema.onUpgrade(database, 47, 48);

      final columns = await database.rawQuery(
        'PRAGMA table_info(run_activities)',
      );
      final names = columns.map((row) => row['name']).toSet();
      expect(names, containsAll(<String>{'rpe', 'feeling_rating'}));
    },
  );
}
