import 'package:flutter/material.dart';

/// Returns the field labels for a given exercise type.
Map<String, String> getFieldsForType(String type) {
  switch (type) {
    case 'weightReps':
      return {'weight': 'Peso', 'reps': 'Reps'};
    case 'distanceTime':
      return {'distance': 'Dist.', 'time_seconds': 'Tempo'};
    case 'weightDistance':
      return {'weight': 'Peso', 'distance': 'Dist.'};
    case 'weightTime':
      return {'weight': 'Peso', 'time_seconds': 'Tempo'};
    case 'repsDistance':
      return {'reps': 'Reps', 'distance': 'Dist.'};
    case 'repsTime':
      return {'reps': 'Reps', 'time_seconds': 'Tempo'};
    case 'weightOnly':
      return {'weight': 'Peso'};
    case 'repsOnly':
      return {'reps': 'Reps'};
    case 'distanceOnly':
      return {'distance': 'Dist.'};
    case 'timeOnly':
      return {'time_seconds': 'Tempo'};
    default:
      return {'weight': 'Peso', 'reps': 'Reps'};
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
