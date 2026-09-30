import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/sleep_monitor_mode.dart';
import 'package:workout_notes/screens/sleep/sleep_monitor_controller.dart';
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

  test('elapsed clock is zero padded and remaining time is compact', () {
    expect(
      formatMonitorDuration(const Duration(hours: 7, minutes: 5, seconds: 9)),
      '07:05:09',
    );
    final past = DateTime.now().subtract(const Duration(minutes: 5));
    expect(formatMonitorRemaining(past), '0min');
    final soon = DateTime.now().add(const Duration(minutes: 12, seconds: 30));
    expect(formatMonitorRemaining(soon), '12min');
    final later = DateTime.now().add(
      const Duration(hours: 7, minutes: 49, seconds: 30),
    );
    expect(formatMonitorRemaining(later), '7h 49min');
  });
}
