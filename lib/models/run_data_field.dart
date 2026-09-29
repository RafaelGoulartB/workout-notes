import 'package:workout_notes/models/cardio_activity_type.dart';

/// A metric the runner can pin to the live grid of the record screen.
enum RunDataField {
  time('time'),
  distance('distance'),
  pace('pace'),
  avgPace('avg_pace'),
  kmPace('km_pace'),
  lapTime('lap_time'),
  lapDistance('lap_distance'),
  calories('calories'),
  clock('clock');

  final String storageValue;

  const RunDataField(this.storageValue);

  static RunDataField? fromStorage(String? raw) {
    for (final field in values) {
      if (field.storageValue == raw) return field;
    }
    return null;
  }

  /// Fields that only make sense when GPS provides distance.
  bool get needsGps =>
      this == distance ||
      this == pace ||
      this == avgPace ||
      this == kmPace ||
      this == lapDistance;
}

/// The ordered set of fields shown while recording (3 to 6).
class RunDataFieldLayout {
  static const minFields = 3;
  static const maxFields = 6;

  static const defaults = [
    RunDataField.time,
    RunDataField.distance,
    RunDataField.pace,
  ];

  /// Indoor sessions have no GPS: time, effort and the wall clock.
  static const indoor = [
    RunDataField.time,
    RunDataField.calories,
    RunDataField.clock,
  ];

  /// The fixed layout of [type] when it is not customizable, else null.
  static List<RunDataField>? fixedFor(CardioActivityType type) =>
      type.isIndoor ? indoor : null;

  /// Drops unknown / duplicate entries and enforces the 3..6 range.
  static List<RunDataField> sanitize(Iterable<RunDataField> fields) {
    final unique = <RunDataField>[];
    for (final field in fields) {
      if (!unique.contains(field)) unique.add(field);
    }
    final capped = unique.take(maxFields).toList();
    if (capped.length >= minFields) return capped;
    for (final fallback in [...defaults, ...RunDataField.values]) {
      if (capped.length >= minFields) break;
      if (!capped.contains(fallback)) capped.add(fallback);
    }
    return capped;
  }

  static List<String> toStorage(List<RunDataField> fields) => [
    for (final field in fields) field.storageValue,
  ];

  static List<RunDataField> fromStorage(List<String>? raw) {
    if (raw == null) return defaults;
    return sanitize([
      for (final value in raw) ?RunDataField.fromStorage(value),
    ]);
  }

  /// Row sizes for [count] fields: 3 -> [3], 4 -> [2, 2], 5 -> [3, 2],
  /// 6 -> [3, 3]. Keeps numbers big without ever overflowing 360 dp.
  static List<int> rowsFor(int count) => switch (count) {
    <= 3 => [count],
    4 => [2, 2],
    5 => [3, 2],
    _ => [3, 3],
  };
}
