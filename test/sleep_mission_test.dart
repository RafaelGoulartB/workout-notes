import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:workout_notes/models/sleep_monitor_mode.dart';
import 'package:workout_notes/utils/sleep_alarm_time.dart';

void main() {
  test('monitoring modes expose the expected alarm and mission rules', () {
    expect(SleepMonitoringMode.alarmWithoutMission.hasAlarm, isTrue);
    expect(SleepMonitoringMode.alarmWithoutMission.requiresMission, isFalse);
    expect(SleepMonitoringMode.alarmWithMission.hasAlarm, isTrue);
    expect(SleepMonitoringMode.alarmWithMission.requiresMission, isTrue);
    expect(SleepMonitoringMode.monitoringOnly.hasAlarm, isFalse);
    expect(SleepMonitoringMode.fromWire('monitoring_only'),
        SleepMonitoringMode.monitoringOnly);
  });

  test('mission configuration round-trips through app settings', () {
    final original = SleepMissionConfig(
      enabled: true,
      hash: 'hash',
      salt: 'salt',
      format: 'EAN-13',
      registeredAt: DateTime.utc(2026, 8, 1),
    );

    final restored = SleepMissionConfig.fromSettings(
      original.toSettings().map((key, value) => MapEntry(key, value.toString())),
    );

    expect(restored.isConfigured, isTrue);
    expect(restored.hash, 'hash');
    expect(restored.salt, 'salt');
    expect(restored.format, 'EAN-13');
    expect(restored.registeredAt, original.registeredAt);
  });

  test('incomplete mission cannot be used for a protected session', () {
    expect(const SleepMissionConfig.empty().isConfigured, isFalse);
    expect(
      const SleepMissionConfig(enabled: true, hash: 'hash').isConfigured,
      isFalse,
    );
  });

  test('default alarm is eight hours ahead rounded down to 15 minutes', () {
    final now = DateTime(2026, 8, 1, 22, 37, 42);
    expect(
      SleepAlarmTime.defaultAlarm(now: now),
      DateTime(2026, 8, 2, 6, 30),
    );
  });

  test('next occurrence rolls to tomorrow when the selected time is too near', () {
    final now = DateTime(2026, 8, 1, 23, 59);
    final occurrence = SleepAlarmTime.nextOccurrence(
      const TimeOfDay(hour: 0, minute: 0),
      now: now,
    );
    expect(occurrence, DateTime(2026, 8, 2, 0, 0));
    expect(
      SleepAlarmTime.isWithinMonitoringWindow(
        now.add(const Duration(minutes: 1)),
        now: now,
      ),
      isTrue,
    );
    expect(
      SleepAlarmTime.isWithinMonitoringWindow(
        now.add(const Duration(hours: 16, seconds: 1)),
        now: now,
      ),
      isFalse,
    );
  });
}
