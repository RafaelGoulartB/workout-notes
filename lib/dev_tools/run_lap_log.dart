import 'package:workout_notes/models/run_lap.dart';

/// Manual laps for the Dart-side (debug) tracker. Mirrors the Android
/// `RunLapTracker`: a lap is measured on moving time, and a double tap
/// under [minLapSeconds] is ignored.
class RunLapLog {
  static const minLapSeconds = 2;

  final List<RunLap> _laps = [];
  double _startDistance = 0;
  int _startMoving = 0;

  List<RunLap> get laps => List.unmodifiable(_laps);

  void reset() {
    _laps.clear();
    _startDistance = 0;
    _startMoving = 0;
  }

  /// The lap in progress; before the first mark it spans the whole run.
  RunLap current({required double distanceMeters, required int movingSeconds}) {
    final distance = (distanceMeters - _startDistance).clamp(
      0.0,
      double.infinity,
    );
    final duration = (movingSeconds - _startMoving).clamp(0, 1 << 30);
    return RunLap(
      index: _laps.length + 1,
      startDistanceMeters: _startDistance,
      distanceMeters: distance,
      durationSeconds: duration,
      paceSecPerKm: distance < 1 || duration <= 0
          ? null
          : duration / (distance / 1000.0),
    );
  }

  /// Closes the current lap and returns it, or null for an accidental tap.
  RunLap? mark({required double distanceMeters, required int movingSeconds}) {
    if (movingSeconds - _startMoving < minLapSeconds) return null;
    final lap = current(
      distanceMeters: distanceMeters,
      movingSeconds: movingSeconds,
    );
    _laps.add(lap);
    _startDistance = distanceMeters;
    _startMoving = movingSeconds;
    return lap;
  }

  /// When the run ends after at least one manual lap, the remainder becomes
  /// the last lap so the laps add up to the whole activity.
  List<RunLap> closedLaps({
    required double distanceMeters,
    required int movingSeconds,
  }) {
    if (_laps.isEmpty) return const [];
    final rest = current(
      distanceMeters: distanceMeters,
      movingSeconds: movingSeconds,
    );
    if (rest.durationSeconds < 1 && rest.distanceMeters < 1) return laps;
    return [..._laps, rest];
  }
}
