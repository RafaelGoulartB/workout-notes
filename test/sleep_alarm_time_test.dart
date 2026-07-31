import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/utils/sleep_alarm_time.dart';

void main() {
  test('defaults to eight hours rounded down to a 15-minute division', () {
    final now = DateTime(2026, 7, 31, 22, 44, 38);

    final alarm = SleepAlarmTime.defaultAlarm(now: now);

    expect(alarm, DateTime(2026, 8, 1, 6, 30));
  });

  test('keeps an exact 15-minute division after adding eight hours', () {
    final now = DateTime(2026, 7, 31, 21, 15);

    final alarm = SleepAlarmTime.defaultAlarm(now: now);

    expect(alarm, DateTime(2026, 8, 1, 5, 15));
  });

  test('uses today when the selected time is at least one minute away', () {
    final now = DateTime(2026, 7, 31, 22);

    final alarm = SleepAlarmTime.nextOccurrence(
      const TimeOfDay(hour: 22, minute: 1),
      now: now,
    );

    expect(alarm, DateTime(2026, 7, 31, 22, 1));
  });

  test('uses tomorrow when the selected time already passed', () {
    final now = DateTime(2026, 7, 31, 23, 30);

    final alarm = SleepAlarmTime.nextOccurrence(
      const TimeOfDay(hour: 7, minute: 0),
      now: now,
    );

    expect(alarm, DateTime(2026, 8, 1, 7));
  });

  test('moves the current minute to the next day', () {
    final now = DateTime(2026, 7, 31, 7, 0, 10);

    final alarm = SleepAlarmTime.nextOccurrence(
      const TimeOfDay(hour: 7, minute: 0),
      now: now,
    );

    expect(alarm, DateTime(2026, 8, 1, 7));
  });

  test('accepts the one-minute and sixteen-hour boundaries', () {
    final now = DateTime(2026, 7, 31, 20);

    expect(
      SleepAlarmTime.isWithinMonitoringWindow(
        now.add(const Duration(minutes: 1)),
        now: now,
      ),
      isTrue,
    );
    expect(
      SleepAlarmTime.isWithinMonitoringWindow(
        now.add(const Duration(hours: 16)),
        now: now,
      ),
      isTrue,
    );
  });

  test('rejects times outside the monitoring window', () {
    final now = DateTime(2026, 7, 31, 20);

    expect(
      SleepAlarmTime.isWithinMonitoringWindow(
        now.add(const Duration(seconds: 59)),
        now: now,
      ),
      isFalse,
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
