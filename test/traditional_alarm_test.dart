import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/traditional_alarm.dart';
import 'package:workout_notes/models/traditional_alarm_runtime_state.dart';

TraditionalAlarm _alarm({
  required List<int> weekdays,
  int hour = 7,
  int minute = 0,
}) => TraditionalAlarm(
  id: 'alarm',
  hour: hour,
  minute: minute,
  weekdays: weekdays,
  enabled: true,
  snoozeEnabled: true,
  snoozeMinutes: 5,
  maxSnoozes: 3,
  requiresMission: false,
  nextTriggerAt: null,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

void main() {
  test('one-shot alarm selects today when its time is still ahead', () {
    expect(
      _alarm(weekdays: []).nextOccurrence(now: DateTime(2026, 8, 1, 6, 59)),
      DateTime(2026, 8, 1, 7),
    );
  });

  test('one-shot alarm selects tomorrow when its time has passed', () {
    expect(
      _alarm(weekdays: []).nextOccurrence(now: DateTime(2026, 8, 1, 7)),
      DateTime(2026, 8, 2, 7),
    );
  });

  test('repeating alarm selects the nearest configured weekday', () {
    // Saturday, 1 Aug 2026. Monday is DateTime.weekday 1.
    expect(
      _alarm(weekdays: [1, 3]).nextOccurrence(now: DateTime(2026, 8, 1, 8)),
      DateTime(2026, 8, 3, 7),
    );
  });

  test('repeating alarm rolls to the following week when needed', () {
    // Monday at the configured time must not fire a second time today.
    expect(
      _alarm(weekdays: [1]).nextOccurrence(now: DateTime(2026, 8, 3, 7)),
      DateTime(2026, 8, 10, 7),
    );
  });

  test('runtime state recognizes a scheduled occurrence as snoozing', () {
    final state = TraditionalAlarmRuntimeState.fromMap({
      'id': 'alarm',
      'enabled': true,
      'state': 'scheduled',
      'alarm_at_epoch_ms': 1788482700000,
      'snooze_count': 2,
      'max_snoozes': 3,
      'requires_mission': true,
    });

    expect(state.isSnoozing, isTrue);
    expect(state.snoozeCount, 2);
    expect(state.maxSnoozes, 3);
    expect(state.requiresMission, isTrue);
  });

  test('initial schedule and ringing state are not reported as snoozing', () {
    TraditionalAlarmRuntimeState state(String status, int count) =>
        TraditionalAlarmRuntimeState(
          id: 'alarm',
          enabled: true,
          state: status,
          alarmAt: DateTime(2026, 9, 4, 7),
          snoozeCount: count,
          maxSnoozes: 3,
          requiresMission: true,
        );

    expect(state('scheduled', 0).isSnoozing, isFalse);
    expect(state('ringing', 1).isSnoozing, isFalse);
  });
}
