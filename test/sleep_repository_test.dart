import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/repositories/sleep_repository.dart';

void main() {
  late Database database;
  late SleepRepository repository;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    database = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE sleep_entries (
              id TEXT PRIMARY KEY,
              date TEXT NOT NULL UNIQUE,
              sleep_minutes INTEGER NOT NULL,
              actual_sleep_minutes INTEGER,
              bedtime_minutes INTEGER,
              wake_time_minutes INTEGER,
              comment TEXT,
              source TEXT NOT NULL DEFAULT 'monitored',
              time_in_bed_minutes INTEGER,
              estimated_sleep_minutes INTEGER,
              created_at TEXT NOT NULL
            )
          ''');
        },
      ),
    );
    DatabaseHelper.overrideDatabase = database;
    repository = SleepRepository();
  });

  tearDown(() async {
    DatabaseHelper.overrideDatabase = null;
    await database.close();
  });

  test('reads records in date order and deletes by id', () async {
    await _insertEntry(
      database,
      date: DateTime(2026, 7, 24),
      sleepMinutes: 420,
    );
    await _insertEntry(
      database,
      date: DateTime(2026, 7, 25),
      sleepMinutes: 480,
      actualSleepMinutes: 420,
    );

    final entries = await repository.getEntries();
    expect(entries, hasLength(2));
    expect(entries.first.date, DateTime(2026, 7, 25));
    expect(entries.first.efficiency, closeTo(87.5, 0.001));

    final byDate = await repository.getByDate(DateTime(2026, 7, 24));
    expect(byDate, isNotNull);
    expect(await repository.getById(byDate!.id), isNotNull);
    expect((await repository.getLatest())!.id, entries.first.id);

    await repository.delete(byDate.id);
    expect(await repository.getByDate(DateTime(2026, 7, 24)), isNull);
  });

  test(
    'calculates dashboard values and ignores missing actual sleep',
    () async {
      final ref = DateTime(2026, 7, 26);
      await _insertEntry(
        database,
        date: DateTime(2026, 7, 26),
        sleepMinutes: 480,
        actualSleepMinutes: 420,
      );
      await _insertEntry(
        database,
        date: DateTime(2026, 7, 25),
        sleepMinutes: 450,
      );
      await _insertEntry(
        database,
        date: DateTime(2026, 7, 1),
        sleepMinutes: 360,
        actualSleepMinutes: 300,
      );

      final stats = await repository.getDashboardStats(referenceDate: ref);
      expect(stats.recordedDays7Days, 2);
      expect(stats.recordedDays30Days, 3);
      expect(stats.average7Days, closeTo(465, 0.001));
      expect(stats.actualAverage7Days, closeTo(420, 0.001));
      expect(stats.minimum30Days, 360);
      expect(stats.maximum30Days, 480);
      expect(stats.efficiency7Days, closeTo(87.5, 0.001));
      expect(stats.efficiency30Days, closeTo((87.5 + 83.333333) / 2, 0.001));
      expect(stats.regularity7Days, isNull);
      expect(stats.regularitySampleCount, 0);
    },
  );
  test('regularity treats bedtime values around midnight as close', () async {
    final reference = DateTime(2026, 7, 26);
    await _insertEntry(
      database,
      date: DateTime(2026, 7, 26),
      sleepMinutes: 450,
      bedtimeMinutes: 10,
      wakeTimeMinutes: 450,
    );
    await _insertEntry(
      database,
      date: DateTime(2026, 7, 25),
      sleepMinutes: 450,
      bedtimeMinutes: 1430,
      wakeTimeMinutes: 430,
    );

    final stats = await repository.getDashboardStats(referenceDate: reference);

    expect(stats.regularitySampleCount, 2);
    expect(stats.regularity7Days, closeTo(94.44, 0.2));
  });

  test('regularity ignores incomplete times and requires two nights', () async {
    final reference = DateTime(2026, 7, 26);
    await _insertEntry(
      database,
      date: DateTime(2026, 7, 26),
      sleepMinutes: 450,
      bedtimeMinutes: 1380,
      wakeTimeMinutes: 420,
    );
    await _insertEntry(
      database,
      date: DateTime(2026, 7, 25),
      sleepMinutes: 430,
      bedtimeMinutes: 1370,
    );

    final stats = await repository.getDashboardStats(referenceDate: reference);

    expect(stats.regularitySampleCount, 1);
    expect(stats.regularity7Days, isNull);
  });

  test(
    'regularity bottoms out after three hours of average variation',
    () async {
      final reference = DateTime(2026, 7, 26);
      await _insertEntry(
        database,
        date: DateTime(2026, 7, 26),
        sleepMinutes: 480,
        bedtimeMinutes: 0,
        wakeTimeMinutes: 660,
      );
      await _insertEntry(
        database,
        date: DateTime(2026, 7, 25),
        sleepMinutes: 480,
        bedtimeMinutes: 1080,
        wakeTimeMinutes: 300,
      );

      final stats = await repository.getDashboardStats(
        referenceDate: reference,
      );

      expect(stats.regularitySampleCount, 2);
      expect(stats.regularity7Days, 0);
    },
  );
}

Future<void> _insertEntry(
  Database database, {
  required DateTime date,
  required int sleepMinutes,
  int? actualSleepMinutes,
  int? bedtimeMinutes,
  int? wakeTimeMinutes,
}) async {
  final dateString = date.toIso8601String().substring(0, 10);
  await database.insert('sleep_entries', {
    'id': 'entry-$dateString',
    'date': dateString,
    'sleep_minutes': sleepMinutes,
    'actual_sleep_minutes': actualSleepMinutes,
    'bedtime_minutes': bedtimeMinutes,
    'wake_time_minutes': wakeTimeMinutes,
    'source': 'monitored',
    'created_at': date.add(const Duration(hours: 7)).toIso8601String(),
  });
}
