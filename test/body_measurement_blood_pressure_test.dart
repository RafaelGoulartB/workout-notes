import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/database/database_schema.dart';
import 'package:workout_notes/models/body_measurement_types.dart';
import 'package:workout_notes/utils/body_tracker_utils.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('v42 adds the diastolic column to existing body measurements', () async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 41,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE body_measurements (
              id TEXT PRIMARY KEY,
              type TEXT NOT NULL,
              value REAL NOT NULL,
              unit TEXT NOT NULL,
              date TEXT NOT NULL,
              created_at TEXT NOT NULL
            )
          ''');
        },
      ),
    );
    addTearDown(db.close);

    await DatabaseSchema.onUpgrade(db, 41, 42);

    final columns = await db.rawQuery('PRAGMA table_info(body_measurements)');
    expect(columns.map((row) => row['name']), contains('secondary_value'));
  });

  test('formats blood pressure with systolic and diastolic values', () {
    const type = MeasureType(
      'bloodPressure',
      Icons.favorite,
      'mmHg',
      Colors.red,
      false,
    );

    expect(
      formatMeasurementValue({'value': 120.0, 'secondary_value': 80.0}, type),
      '120/80 mmHg',
    );
  });
}
