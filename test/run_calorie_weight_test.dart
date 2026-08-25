import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/database/database_schema.dart';
import 'package:workout_notes/repositories/run_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database database;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    database = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 48,
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

  test('uses the latest body weight for run calories and preview', () async {
    await database.insert('body_measurements', {
      'id': 'older-weight',
      'type': 'weight',
      'value': 90.0,
      'unit': 'kg',
      'date': '2026-08-01',
      'created_at': '2026-08-01T08:00:00.000',
    });
    await database.insert('body_measurements', {
      'id': 'latest-weight',
      'type': 'weight',
      'value': 80.0,
      'unit': 'kg',
      'date': '2026-08-25',
      'created_at': '2026-08-25T08:00:00.000',
    });

    final repository = RunRepository();
    final spool = _spool('weighted-run');
    final preview = await repository.previewNativeSpoolUsingLatestWeight(spool);
    final imported = await repository.importNativeSpool(spool);

    expect(preview.calories, 400);
    expect(imported.calories, 400);
  });

  test('falls back to 70 kg when no body weight is registered', () async {
    final imported = await RunRepository().importNativeSpool(
      _spool('fallback-run'),
    );

    expect(imported.calories, 350);
  });
}

Map<String, dynamic> _spool(String id) => {
  'activity': <String, dynamic>{
    'id': id,
    'status': 'completed',
    'started_at': '2026-08-25T10:00:00.000Z',
    'ended_at': '2026-08-25T10:30:00.000Z',
    'duration_seconds': 1800,
    'moving_time_seconds': 1750,
    'distance_meters': 5000.0,
  },
  'points': <Map<String, dynamic>>[],
};
