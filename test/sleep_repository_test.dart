import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/models/sleep_entry.dart';
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

  test('saves, reads, updates and deletes a record', () async {
    final date = DateTime(2026, 7, 25);
    await repository.add(
      date: date,
      sleepMinutes: 480,
      actualSleepMinutes: 420,
      bedtimeMinutes: 22 * 60,
      wakeTimeMinutes: 6 * 60,
      comment: 'Good night',
    );

    var entry = await repository.getByDate(date);
    expect(entry, isNotNull);
    expect(entry!.actualSleepMinutes, 420);
    expect(entry.efficiency, closeTo(87.5, 0.001));

    await repository.save(
      entry.copyWith(sleepMinutes: 450, actualSleepMinutes: null),
    );
    entry = await repository.getByDate(date);
    expect(entry!.sleepMinutes, 450);
    expect(entry.actualSleepMinutes, isNull);

    await repository.delete(entry.id);
    expect(await repository.getLatest(), isNull);
  });

  test('replaces the existing record for the same date', () async {
    await repository.add(date: DateTime(2026, 7, 25), sleepMinutes: 420);
    await repository.add(
      date: DateTime(2026, 7, 25),
      sleepMinutes: 500,
      actualSleepMinutes: 480,
    );

    final entries = await repository.getEntries();
    expect(entries, hasLength(1));
    expect(entries.single.sleepMinutes, 500);
  });

  test(
    'calculates dashboard values and ignores missing actual sleep',
    () async {
      final ref = DateTime(2026, 7, 26);
      await repository.add(
        date: DateTime(2026, 7, 26),
        sleepMinutes: 480,
        actualSleepMinutes: 420,
      );
      await repository.add(date: DateTime(2026, 7, 25), sleepMinutes: 450);
      await repository.add(
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
    },
  );

  test(
    'rejects invalid durations and actual sleep greater than duration',
    () async {
      final base = SleepEntry(
        id: 'invalid',
        date: DateTime(2026, 7, 26),
        sleepMinutes: 0,
        createdAt: DateTime.now(),
      );
      expect(() => repository.save(base), throwsArgumentError);

      expect(
        () => repository.save(
          base.copyWith(sleepMinutes: 300, actualSleepMinutes: 301),
        ),
        throwsArgumentError,
      );
    },
  );
}
