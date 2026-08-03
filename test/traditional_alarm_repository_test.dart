import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/repositories/traditional_alarm_repository.dart';

void main() {
  late Database database;
  late TraditionalAlarmRepository repository;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    database = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) => db.execute('''
          CREATE TABLE traditional_alarms (
            id TEXT PRIMARY KEY, hour INTEGER NOT NULL, minute INTEGER NOT NULL,
            weekdays_json TEXT NOT NULL, enabled INTEGER NOT NULL,
            snooze_enabled INTEGER NOT NULL, snooze_minutes INTEGER NOT NULL,
            max_snoozes INTEGER NOT NULL,
            requires_mission INTEGER NOT NULL, next_trigger_at TEXT,
            created_at TEXT NOT NULL, updated_at TEXT NOT NULL
          )
        '''),
      ),
    );
    DatabaseHelper.overrideDatabase = database;
    repository = TraditionalAlarmRepository();
  });

  tearDown(() async {
    DatabaseHelper.overrideDatabase = null;
    await database.close();
  });

  test(
    'creates, updates native schedule state, and deletes an alarm',
    () async {
      final alarm = await repository.insert(
        hour: 7,
        minute: 30,
        weekdays: [1, 3, 5],
        snoozeEnabled: true,
        snoozeMinutes: 10,
        maxSnoozes: 3,
        requiresMission: true,
      );

      expect((await repository.getAll()).single.weekdays, [1, 3, 5]);
      expect(alarm.nextTriggerAt, isNotNull);
      expect(alarm.maxSnoozes, 3);

      final next = DateTime(2026, 8, 3, 7, 30);
      await repository.updateNativeSchedule(
        alarm.id,
        enabled: false,
        nextTriggerAt: next,
      );
      final updated = (await repository.getAll()).single;
      expect(updated.enabled, isFalse);
      expect(updated.nextTriggerAt, next);

      await repository.delete(alarm.id);
      expect(await repository.getAll(), isEmpty);
    },
  );
}
