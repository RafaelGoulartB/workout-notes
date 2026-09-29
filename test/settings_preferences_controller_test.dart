import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/screens/workout/settings_preferences_controller.dart';

void main() {
  test('rest time labels stay compact and locale agnostic', () {
    expect(WorkoutPreferencesController.formatRestTime(30), '30s');
    expect(WorkoutPreferencesController.formatRestTime(60), '1min');
    expect(WorkoutPreferencesController.formatRestTime(90), '1min 30s');
    expect(WorkoutPreferencesController.formatRestTime(180), '3min');
  });

  test('theme modes map to the stored preference values', () {
    expect(AppearanceController.themeModeValue(ThemeMode.light), 'light');
    expect(AppearanceController.themeModeValue(ThemeMode.dark), 'dark');
    expect(AppearanceController.themeModeValue(ThemeMode.system), 'system');
  });
}
