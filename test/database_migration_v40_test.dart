import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:workout_notes/database/database_schema.dart';

/// Verifies the incremental schema upgrades in
/// [DatabaseSchema.onUpgrade] cover every migration that has run in
/// the field. Version 37 is the last schema shipped before the
/// daily-expenditure / adjustment split, and version 39 is the sleep
/// migration that already shipped — the nutrition columns must land in
/// a step ABOVE 39 or devices already on v39 never receive them.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<Database> openLegacyGoalDb({
    required int version,
    bool withNewColumns = false,
  }) async {
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: version,
        onCreate: (db, v) async {
          // Minimal legacy schema for `nutrition_goals`, mirroring what
          // shipped before the TDEE/goal split landed.
          await db.execute('''
            CREATE TABLE nutrition_goals (
              id TEXT PRIMARY KEY,
              calories REAL,
              protein_g REAL,
              carbs_g REAL,
              fat_g REAL,
              ${withNewColumns ? 'tdee REAL, adjustment_kind TEXT, adjustment_percent REAL,' : ''}
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
    return database;
  }

  Future<void> expectBackfilled(Database database) async {
    // The new columns must exist and the row must be backfilled so
    // the goal is preserved (TDEE = calories, adjustment maintenance).
    final rows = await database.query('nutrition_goals');
    expect(rows, hasLength(1));
    final row = rows.first;
    expect(row['tdee'], 2000.0);
    expect(row['adjustment_kind'], 'maintenance');
    expect(row['adjustment_percent'], 0.0);
    expect(row['calories'], 2000.0);
  }

  test('upgrade from v37 adds the TDEE/adjustment columns and backfills', () async {
    final database = await openLegacyGoalDb(version: 37);
    await DatabaseSchema.onUpgrade(database, 37, 40);
    await expectBackfilled(database);
  });

  test('upgrade from v39 (shipped sleep migration) adds the columns too', () async {
    // Regression for devices that already upgraded past v39: a
    // lower-numbered migration step never runs for them, which used to
    // crash every TDEE/goal save with "no column named tdee".
    final database = await openLegacyGoalDb(version: 39);
    await DatabaseSchema.onUpgrade(database, 39, 40);
    await expectBackfilled(database);

    // Saving a TDEE-driven goal must now succeed on the upgraded table.
    final db = database;
    await db.insert('nutrition_goals', {
      'id': 'goal-2',
      'calories': 2000.0,
      'protein_g': 150.0,
      'carbs_g': 200.0,
      'fat_g': 60.0,
      'tdee': 2500.0,
      'adjustment_kind': 'cut',
      'adjustment_percent': -20.0,
      'created_at': '2024-01-02T00:00:00.000',
      'updated_at': '2024-01-02T00:00:00.000',
      'is_active': 1,
    });
    final rows = await database.query(
      'nutrition_goals',
      where: 'id = ?',
      whereArgs: ['goal-2'],
    );
    expect(rows.single['tdee'], 2500.0);
  });

  test('migration is idempotent when the columns already exist', () async {
    // Devices that ran an interim build with the columns present must
    // upgrade cleanly — the ALTER TABLE is best-effort and the backfill
    // only touches rows where tdee is still NULL.
    final database = await openLegacyGoalDb(version: 39, withNewColumns: true);
    await DatabaseSchema.onUpgrade(database, 39, 40);
    await expectBackfilled(database);
  });

  test('fresh database keeps the full column set', () async {
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 40,
        onCreate: (db, version) async {
          await DatabaseSchema.onCreate(db, version);
        },
      ),
    );
    addTearDown(database.close);

    // Re-running the migration must not raise (the ALTER TABLE is
    // best-effort and the missing-table UPDATE paths are guarded).
    await DatabaseSchema.onUpgrade(database, 40, 40);

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
