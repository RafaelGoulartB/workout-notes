import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/sleep_monitor_mode.dart';
import 'package:workout_notes/screens/workout/sleep_monitor_controller.dart';
import 'package:workout_notes/widgets/sleep/monitor/sleep_monitor_texts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('starts on the plain alarm mode and locks the mission mode', () {
    final controller = SleepMonitorController();
    addTearDown(controller.dispose);

    expect(controller.selectedMode, SleepMonitoringMode.alarmWithoutMission);
    expect(controller.selectedTime, const TimeOfDay(hour: 7, minute: 0));
    expect(controller.loading, isTrue);
    expect(controller.isBusy, isFalse);
    // No mission has been registered yet.
    expect(controller.isModeLocked(SleepMonitoringMode.alarmWithMission), true);
    expect(controller.isModeLocked(SleepMonitoringMode.monitoringOnly), false);
    expect(SleepMonitorController.modeOrder, hasLength(3));
  });

  test('elapsed and remaining clocks are zero padded', () {
    expect(
      formatMonitorDuration(const Duration(hours: 7, minutes: 5, seconds: 9)),
      '07:05:09',
    );
    final past = DateTime.now().subtract(const Duration(minutes: 5));
    expect(formatMonitorRemaining(past), '0h 0min');
    expect(formatMonitorRemaining(past, withSeconds: true), '00:00:00');
  });
}
