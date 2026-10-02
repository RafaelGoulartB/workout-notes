import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/screens/settings/settings_preferences_controller.dart';

void main() {
  test('rest time labels stay compact and locale agnostic', () {
    expect(WorkoutPreferencesController.formatRestTime(30), '30s');
    expect(WorkoutPreferencesController.formatRestTime(60), '1min');
    expect(WorkoutPreferencesController.formatRestTime(90), '1min 30s');
    expect(WorkoutPreferencesController.formatRestTime(180), '3min');
  });
}
