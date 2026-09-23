import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';

/// Returns a localized label for a workout set field.
String workoutFieldLabel(AppLocalizations loc, String key) => switch (key) {
  'weight' => loc.activeWorkoutWeight,
  'reps' => loc.activeWorkoutReps,
  'distance' => loc.activeWorkoutDistance,
  'time_seconds' => loc.activeWorkoutTime,
  _ => key,
};

/// Returns the ordered field keys for a given exercise type.
List<String> getFieldsForType(String type) {
  switch (type) {
    case 'weightReps':
      return ['weight', 'reps'];
    case 'distanceTime':
      return ['distance', 'time_seconds'];
    case 'weightDistance':
      return ['weight', 'distance'];
    case 'weightTime':
      return ['weight', 'time_seconds'];
    case 'repsDistance':
      return ['reps', 'distance'];
    case 'repsTime':
      return ['reps', 'time_seconds'];
    case 'weightOnly':
      return ['weight'];
    case 'repsOnly':
      return ['reps'];
    case 'distanceOnly':
      return ['distance'];
    case 'timeOnly':
      return ['time_seconds'];
    default:
      return ['weight', 'reps'];
  }
}

/// Formats a set field value for display.
String formatFieldValue(Map<String, dynamic> set, String key) {
  if (key == 'weight') {
    final v = (set['weight'] as num?)?.toDouble();
    return v != null ? v.toStringAsFixed(1) : '-';
  }
  if (key == 'distance') {
    final v = (set['distance'] as num?)?.toDouble();
    return v != null ? v.toStringAsFixed(1) : '-';
  }
  if (key == 'reps') {
    return (set['reps'] as int?)?.toString() ?? '-';
  }
  if (key == 'time_seconds') {
    final v = (set['time_seconds'] as int?);
    if (v == null) return '-';
    if (v >= 60) return '${v ~/ 60}:${(v % 60).toString().padLeft(2, '0')}';
    return '${v}s';
  }
  return '-';
}

/// Colors to use for exercise categories.
final List<Color> categoryColors = [
  Colors.red,
  Colors.blue,
  Colors.green,
  Colors.orange,
  Colors.purple,
  Colors.teal,
  Colors.cyan,
  Colors.pink,
  Colors.indigo,
  Colors.amber,
];
