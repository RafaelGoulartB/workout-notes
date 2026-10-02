import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/services/app_data_coordinator.dart';

AppDataCoordinator _coordinator(
  List<String> steps, {
  bool failAlarms = false,
  bool failAi = false,
}) => AppDataCoordinator(
  syncAlarms: () async {
    if (failAlarms) throw StateError('channel down');
    steps.add('alarms');
  },
  syncMedications: () async => steps.add('medications'),
  resetAi: () async {
    if (failAi) throw ArgumentError('no settings yet');
    steps.add('ai');
  },
  refreshAppearance: () async => steps.add('appearance'),
);

void main() {
  test('runs every step in order after the data was replaced', () async {
    final steps = <String>[];

    await _coordinator(steps).afterDataReplaced(settingsReplaced: true);

    expect(steps, ['alarms', 'medications', 'ai', 'appearance']);
  });

  test('leaves the settings notifiers alone when not replaced', () async {
    final steps = <String>[];

    await _coordinator(steps).afterDataReplaced(settingsReplaced: false);

    expect(steps, ['alarms', 'medications', 'ai']);
  });

  test('a failing step is logged and does not stop the others', () async {
    final steps = <String>[];

    await _coordinator(
      steps,
      failAlarms: true,
      failAi: true,
    ).afterDataReplaced(settingsReplaced: true);

    expect(steps, ['medications', 'appearance']);
  });
}
