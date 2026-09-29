import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/database/database_schema.dart';
import 'package:workout_notes/models/run_review_draft.dart';
import 'package:workout_notes/repositories/run_repository.dart';

Map<String, dynamic> _spool({
  String id = 'run-with-laps',
  List<Map<String, dynamic>>? laps,
}) => {
  'activity': {
    'id': id,
    'status': 'completed',
    'started_at': '2026-09-01T07:00:00.000Z',
    'ended_at': '2026-09-01T07:30:00.000Z',
    'duration_seconds': 1800,
    'moving_time_seconds': 1700,
    'distance_meters': 5000.0,
    'laps': ?laps,
  },
  'points': <Map<String, dynamic>>[],
};

Map<String, dynamic> _lap(int index, double start, double distance, int secs) =>
    {
      'lap_index': index,
      'start_distance_meters': start,
      'distance_meters': distance,
      'duration_seconds': secs,
      'pace_sec_per_km': secs / (distance / 1000),
    };

void main() {
  late Database database;
  final repository = RunRepository();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    database = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 53,
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

  test('imports manual laps together with the activity', () async {
    final spool = _spool(
      laps: [
        _lap(1, 0, 1000, 320),
        _lap(2, 1000, 2500, 800),
        _lap(3, 3500, 1500, 500),
      ],
    );
    await repository.importNativeSpool(spool);

    final laps = await DatabaseHelper.instance.runGearRepo.getLaps(
      'run-with-laps',
    );
    expect(laps.map((l) => l.index), [1, 2, 3]);
    expect(laps[1].startDistanceMeters, 1000);
    expect(laps[1].distanceMeters, 2500);
    expect(laps[1].durationSeconds, 800);
    expect(laps[1].paceSecPerKm, closeTo(320, 0.01));
  });

  test('importing the same spool twice never duplicates laps', () async {
    final spool = _spool(laps: [_lap(1, 0, 5000, 1700)]);
    await repository.importNativeSpool(spool);
    await repository.importNativeSpool(spool);

    final rows = await database.query('run_laps');
    expect(rows, hasLength(1));
    expect(await database.query('run_activities'), hasLength(1));
  });

  test('a run without laps imports as before', () async {
    await repository.importNativeSpool(_spool());
    expect(await database.query('run_laps'), isEmpty);
    expect(await database.query('run_activities'), hasLength(1));
  });

  test('ignores malformed lap rows instead of failing the import', () async {
    final spool = _spool(
      laps: [
        {'distance_meters': 100.0}, // no index
        _lap(2, 0, 800, 240),
      ],
    );
    await repository.importNativeSpool(spool);
    final laps = await DatabaseHelper.instance.runGearRepo.getLaps(
      'run-with-laps',
    );
    expect(laps.map((l) => l.index), [2]);
  });

  test('the review draft exposes the laps of the spool', () {
    final spool = _spool(
      laps: [_lap(1, 0, 2500, 800), _lap(2, 2500, 2500, 900)],
    );
    final draft = RunReviewDraft.fromSpool(
      activity: repository.previewNativeSpool(spool),
      spool: spool,
    );
    expect(draft.laps, hasLength(2));
    expect(draft.laps.last.durationSeconds, 900);
    expect(
      RunReviewDraft.fromSpool(
        activity: repository.previewNativeSpool(_spool()),
        spool: _spool(),
      ).laps,
      isEmpty,
    );
  });
}
