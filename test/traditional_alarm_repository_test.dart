import 'package:flutter_test/flutter_test.dart';

import 'package:workout_notes/repositories/traditional_alarm_repository.dart';
import 'support/test_db.dart';

void main() {
  late TraditionalAlarmRepository repository;

  setUpAll(initSqfliteFfiForTests);

  setUp(() async {
    await installTestDb();
    repository = TraditionalAlarmRepository();
  });

  tearDown(uninstallTestDb);

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
