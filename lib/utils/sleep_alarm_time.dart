import 'package:flutter/material.dart';

class SleepAlarmTime {
  static const minimumLead = Duration(minutes: 1);
  static const maximumLead = Duration(hours: 16);
  static const defaultSleepDuration = Duration(hours: 8);

  const SleepAlarmTime._();

  static DateTime defaultAlarm({DateTime? now}) {
    final target = (now ?? DateTime.now()).add(defaultSleepDuration);
    return DateTime(
      target.year,
      target.month,
      target.day,
      target.hour,
      (target.minute ~/ 15) * 15,
    );
  }

  static DateTime nextOccurrence(TimeOfDay time, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    var candidate = DateTime(
      reference.year,
      reference.month,
      reference.day,
      time.hour,
      time.minute,
    );
    if (candidate.difference(reference) < minimumLead) {
      candidate = DateTime(
        reference.year,
        reference.month,
        reference.day + 1,
        time.hour,
        time.minute,
      );
    }
    return candidate;
  }

  static bool isWithinMonitoringWindow(DateTime alarmAt, {DateTime? now}) {
    final lead = alarmAt.difference(now ?? DateTime.now());
    return lead >= minimumLead && lead <= maximumLead;
  }
}
