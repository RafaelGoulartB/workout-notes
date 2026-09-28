import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/database/database_schema.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<void> expectRunPlanV52(Database database) async {
    final columns = await database.rawQuery('PRAGMA table_info(run_plans)');
    expect(
      columns.map((row) => row['name']),
      containsAll(['template_key', 'config_json']),
    );
    final tables = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'run_plan_adaptations'",
    );
    expect(tables, hasLength(1));
  }

  test('fresh v52 database creates plan config and adaptation log', () async {
    final database = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 52,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: DatabaseSchema.onCreate,
      ),
    );
    addTearDown(database.close);
    await expectRunPlanV52(database);
  });

  test('v52 upgrades existing plans without losing them', () async {
    final database = await databaseFactory.openDatabase(inMemoryDatabasePath);
    addTearDown(database.close);
    await database.execute('''
      CREATE TABLE run_plans (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await database.insert('run_plans', {
      'id': 'legacy-plan',
      'name': 'Legacy plan',
      'created_at': '2026-09-01',
      'updated_at': '2026-09-01',
    });

    await DatabaseSchema.onUpgrade(database, 51, 52);
    await DatabaseSchema.onUpgrade(database, 51, 52);

    await expectRunPlanV52(database);
    final plans = await database.query('run_plans');
    expect(plans, hasLength(1));
    expect(plans.single['id'], 'legacy-plan');
    expect(plans.single['config_json'], isNull);
  });
}
