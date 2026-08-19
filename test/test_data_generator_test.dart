import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/database/database_schema.dart';
import 'package:workout_notes/dev_tools/test_data/test_data_context.dart';
import 'package:workout_notes/dev_tools/test_data/test_data_generator.dart';

void main() {
  late Database database;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 37,
        singleInstance: false,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: DatabaseSchema.onCreate,
      ),
    );
    DatabaseHelper.overrideDatabase = database;
  });

  tearDown(() async {
    DatabaseHelper.overrideDatabase = null;
    await database.close();
  });

  test('creates every app domain on a timeline relative to the click', () async {
    final anchor = DateTime(2026, 8, 12, 14, 30);
    final report = await TestDataGenerator(
      clock: () => anchor,
      randomSeed: 1234,
    ).generate();

    expect(report.workouts, greaterThan(40));
    expect(report.routines, 2);
    expect(report.runs, greaterThan(20));
    expect(report.measurements, greaterThan(40));
    expect(report.sleepNights, greaterThan(100));
    expect(report.monitoredNights, greaterThan(5));
    expect(report.nutritionDays, greaterThan(65));
    expect(report.meals, greaterThan(200));
    expect(report.goals, 4);
    expect(report.periodizationPlans, 2);
    expect(report.periodizationPhases, 7);
    expect(report.periodizationCheckins, greaterThan(8));
    expect(
      Sqflite.firstIntValue(
        await database.rawQuery(
          'SELECT COUNT(*) FROM periodization_plans WHERE id LIKE ?',
          ['$devDataPrefix%'],
        ),
      ),
      2,
    );
    expect(
      Sqflite.firstIntValue(
        await database.rawQuery(
          "SELECT COUNT(*) FROM periodization_plans WHERE id LIKE ? AND status = 'active'",
          ['$devDataPrefix%'],
        ),
      ),
      1,
    );
    expect(
      Sqflite.firstIntValue(
        await database.rawQuery(
          'SELECT COUNT(*) FROM periodization_phases WHERE id LIKE ?',
          ['$devDataPrefix%'],
        ),
      ),
      7,
    );
    expect(
      Sqflite.firstIntValue(
        await database.rawQuery(
          'SELECT COUNT(*) FROM phase_targets WHERE id LIKE ?',
          ['$devDataPrefix%'],
        ),
      ),
      9,
    );
    expect(
      Sqflite.firstIntValue(
        await database.rawQuery(
          'SELECT COUNT(*) FROM phase_routine_links WHERE id LIKE ?',
          ['$devDataPrefix%'],
        ),
      ),
      8,
    );
    expect(
      Sqflite.firstIntValue(
        await database.rawQuery('SELECT COUNT(*) FROM saved_meals'),
      ),
      2,
    );
    expect(
      Sqflite.firstIntValue(
        await database.rawQuery(
          'SELECT COUNT(*) FROM run_activities WHERE id LIKE ?',
          ['$devDataPrefix%'],
        ),
      ),
      report.runs,
    );
    expect(
      Sqflite.firstIntValue(
        await database.rawQuery(
          'SELECT COUNT(*) FROM run_track_points WHERE activity_id IN '
          '(SELECT id FROM run_activities WHERE id LIKE ?)',
          ['$devDataPrefix%'],
        ),
      ),
      greaterThan(0),
    );

    final range = await database.rawQuery(
      'SELECT MIN(date) AS first_date, MAX(date) AS last_date FROM sleep_entries',
    );
    expect(range.single['first_date'], '2026-04-09');
    expect(range.single['last_date'], lessThanOrEqualTo('2026-08-12'));
    expect(
      Sqflite.firstIntValue(
        await database.rawQuery('SELECT COUNT(*) FROM sleep_stage_epochs'),
      ),
      greaterThan(50),
    );
  });

  test('replaces only previous generated rows and preserves user data', () async {
    await database.insert('sleep_entries', {
      'id': 'user-sleep',
      'date': '2026-08-12',
      'sleep_minutes': 480,
      'source': 'manual',
      'created_at': '2026-08-12T08:00:00.000',
    });
    await database.insert('periodization_plans', {
      'id': 'user-plan',
      'name': 'Plano real preservado',
      'start_date': '2026-08-01',
      'end_date': '2026-10-31',
      'status': 'active',
      'created_at': '2026-08-01T08:00:00.000',
      'updated_at': '2026-08-01T08:00:00.000',
    });
    final first = TestDataGenerator(
      clock: () => DateTime(2026, 8, 12, 14),
      randomSeed: 10,
    );
    await first.generate();
    final secondReport = await TestDataGenerator(
      clock: () => DateTime(2026, 8, 13, 9),
      randomSeed: 20,
    ).generate();

    expect(
      Sqflite.firstIntValue(
        await database.rawQuery(
          'SELECT COUNT(*) FROM workouts WHERE id LIKE ?',
          ['$devDataPrefix%'],
        ),
      ),
      secondReport.workouts,
    );
    expect(
      Sqflite.firstIntValue(
        await database.rawQuery(
          'SELECT COUNT(*) FROM sleep_entries WHERE id = ?',
          ['user-sleep'],
        ),
      ),
      1,
    );
    expect(
      Sqflite.firstIntValue(
        await database.rawQuery(
          "SELECT COUNT(*) FROM periodization_plans WHERE id = 'user-plan' AND status = 'active'",
        ),
      ),
      1,
    );
    expect(
      Sqflite.firstIntValue(
        await database.rawQuery(
          "SELECT COUNT(*) FROM periodization_plans WHERE id LIKE ? AND status = 'draft'",
          ['$devDataPrefix%'],
        ),
      ),
      1,
    );
  });
}
