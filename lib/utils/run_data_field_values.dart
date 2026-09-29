import 'package:intl/intl.dart';
import 'package:workout_notes/models/cardio_activity_type.dart';
import 'package:workout_notes/models/run_data_field.dart';
import 'package:workout_notes/models/run_tracking_state.dart';
import 'package:workout_notes/repositories/run_repository.dart';
import 'package:workout_notes/utils/run_formatters.dart';

/// A formatted live value, split so the unit can be drawn smaller.
class RunDataValue {
  final String value;
  final String? unit;

  const RunDataValue(this.value, [this.unit]);

  @override
  bool operator ==(Object other) =>
      other is RunDataValue && other.value == value && other.unit == unit;

  @override
  int get hashCode => Object.hash(value, unit);

  @override
  String toString() => unit == null ? value : '$value $unit';
}

/// Turns a [RunTrackingState] into the text of each [RunDataField]. Pure, so
/// the formatting rules are unit-tested without a widget tree.
class RunDataFieldValues {
  static const placeholder = '--';

  static RunDataValue of(
    RunDataField field, {
    required RunTrackingState state,
    required DateTime now,
    CardioActivityType activityType = CardioActivityType.running,
    double bodyWeightKg = 70,
  }) {
    switch (field) {
      case RunDataField.time:
        return RunDataValue(RunFormatters.duration(state.durationSeconds));
      case RunDataField.distance:
        return RunDataValue(
          RunFormatters.distanceKm(state.distanceMeters),
          'km',
        );
      case RunDataField.pace:
        return RunDataValue(RunFormatters.pace(_currentPace(state)), '/km');
      case RunDataField.avgPace:
        return RunDataValue(RunFormatters.pace(_averagePace(state)), '/km');
      case RunDataField.kmPace:
        return RunDataValue(RunFormatters.pace(_kmPace(state)), '/km');
      case RunDataField.lapTime:
        final lap = state.currentLap;
        return RunDataValue(
          lap == null ? '--:--' : RunFormatters.duration(lap.durationSeconds),
        );
      case RunDataField.lapDistance:
        final lap = state.currentLap;
        return RunDataValue(
          RunFormatters.distanceKm(lap?.distanceMeters ?? 0),
          'km',
        );
      case RunDataField.calories:
        final kcal = RunRepository.estimateCalories(
          activityType: activityType,
          distanceMeters: state.distanceMeters,
          movingSeconds: state.movingTimeSeconds,
          bodyWeightKg: bodyWeightKg,
        );
        return RunDataValue(kcal <= 0 ? placeholder : '$kcal', 'kcal');
      case RunDataField.clock:
        return RunDataValue(DateFormat.Hm(Intl.defaultLocale).format(now));
    }
  }

  /// Instantaneous pace; blank while standing still so a stale value never
  /// looks like the current effort.
  static double? _currentPace(RunTrackingState state) {
    if (state.isAutoPaused) return null;
    return state.currentPaceSecPerKm ?? _averagePace(state);
  }

  static double? _averagePace(RunTrackingState state) {
    if (state.distanceMeters < 1 || state.movingTimeSeconds <= 0) return null;
    return state.movingTimeSeconds / (state.distanceMeters / 1000.0);
  }

  /// Pace of the kilometer in progress, falling back to the last completed km
  /// until the partial one has enough distance to mean something.
  static double? _kmPace(RunTrackingState state) {
    final partial = state.currentSplit;
    if (partial != null && partial.distanceMeters >= 50) {
      return partial.paceSecPerKm;
    }
    if (state.splits.isNotEmpty) return state.splits.last.paceSecPerKm;
    return partial?.paceSecPerKm;
  }
}
