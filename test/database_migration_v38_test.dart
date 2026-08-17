import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:workout_notes/database/database_schema.dart';

/// Verifies the incremental schema upgrades in
/// [DatabaseSchema.onUpgrade] cover every migration that has run in
/// the field. The previous version (37) is the last schema shipped
/// before the daily-expenditure / adjustment split landed, so this
/// test guards against forgetting to bump the version guard or
/// backfill the new columns.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('v38 migration adds TDEE/adjustment columns to existing goals', () async {
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 37,
        onCreate: (db, version) async {
          // Minimal v37 schema for `nutrition_goals`. Mirrors what
          // shipped before the TDEE/goal split landed.
          await db.execute('''
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
          ''');
        },
      ),
    );
    addTearDown(database.close);

    // Seed a pre-migration goal row (only the old columns).
    await database.insert('nutrition_goals', {
      'id': 'goal-1',
      'calories': 2000.0,
      'protein_g': 150.0,
      'carbs_g': 200.0,
      'fat_g': 60.0,
      'created_at': '2024-01-01T00:00:00.000',
      'updated_at': '2024-01-01T00:00:00.000',
      'is_active': 1,
    });

    // Run the app's own migration. The new helper accepts the
    // current version we want to upgrade to.
    await DatabaseSchema.onUpgrade(database, 37, 39);

    // The new columns must exist and the row must be backfilled so
    // the goal is preserved (TDEE = calories, adjustment maintenance).
    final rows = await database.query('nutrition_goals');
    expect(rows, hasLength(1));
    final row = rows.first;
    expect(row['tdee'], 2000.0);
    expect(row['adjustment_kind'], 'maintenance');
    expect(row['adjustment_percent'], 0.0);
    expect(row['calories'], 2000.0);
  });

  test('v38 migration is idempotent on a fresh database', () async {
    // Skipping ahead without a prior install should still be safe —
    // the schema helper creates the table with the new columns on
    // onCreate, and the migration's ALTER TABLE is wrapped in
    // try/catch so it becomes a no-op.
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 39,
        onCreate: (db, version) async {
          await DatabaseSchema.onCreate(db, version);
        },
      ),
    );
    addTearDown(database.close);

    // Re-running the migration must not raise (the ALTER TABLE is
    // best-effort and the missing-table UPDATE paths are guarded).
    await DatabaseSchema.onUpgrade(database, 39, 39);

    final rows = await database.rawQuery(
      'PRAGMA table_info(nutrition_goals)',
    );
    final columns = rows.map((r) => r['name'] as String).toSet();
    expect(columns, containsAll(<String>[
      'tdee',
      'adjustment_kind',
      'adjustment_percent',
      'calories',
    ]));
  });
}
