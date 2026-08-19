import 'dart:math' as math;

import 'package:uuid/uuid.dart';
import 'package:workout_notes/models/run_split.dart';
import 'package:workout_notes/models/run_tracking_state.dart';

/// Pure debug GPS path generator. Not used in release builds.
class RunDebugSimulator {
  static const _uuid = Uuid();

  /// Nominal cruise speed — still fast so ~1 km finishes in ~1 minute of QA time.
  static const baseMetersPerSecond = 14.0;

  /// Hard floor / ceiling so the path stays testable but visibly uneven.
  static const minMetersPerSecond = 8.0;
  static const maxMetersPerSecond = 22.0;

  final String activityId;
  final DateTime startedAt;
  final double startLat;
  final double startLng;

  double distanceMeters = 0;
  int elapsedSeconds = 0;
  int movingSeconds = 0;
  double lat;
  double lng;
  final List<RunLatLng> trail = [];
  final List<RunSplit> completedSplits = [];
  int _lastSplitMovingSeconds = 0;
  double _nextSplitAtMeters = 1000;
  int _tick = 0;
  double _lastStepMeters = baseMetersPerSecond;
  double? _instantPaceSecPerKm;
  double? _bestPaceSecPerKm;

  RunDebugSimulator({
    required this.activityId,
    required this.startedAt,
    required this.startLat,
    required this.startLng,
  })  : lat = startLat,
        lng = startLng {
    trail.add(RunLatLng(startLat, startLng));
  }

  factory RunDebugSimulator.create({
    double startLat = -23.5505,
    double startLng = -46.6333,
  }) {
    return RunDebugSimulator(
      activityId: _uuid.v4(),
      startedAt: DateTime.now(),
      startLat: startLat,
      startLng: startLng,
    );
  }

  /// Speed for this simulated second — multi-frequency undulation + short surges.
  /// Kept deterministic so tests and chart shapes are stable.
  double speedForTick(int tick) {
    // ~45 s / ~600 m wave: "hill" vs "flat"
    final slowWave = 3.5 * math.sin(tick * 0.14);
    // Faster wobble so the pace chart is not a single sine.
    final fastWave = 1.8 * math.sin(tick * 0.37 + 0.6);
    // Brief surge every ~28 s (4 s hard).
    final surge = (tick % 28) < 4 ? 2.8 : 0.0;
    // Soft dip mid-cycle so one km is clearly slower than another.
    final dip = (tick % 55) > 40 ? -2.2 : 0.0;
    return (baseMetersPerSecond + slowWave + fastWave + surge + dip)
        .clamp(minMetersPerSecond, maxMetersPerSecond);
  }

  /// Advances one second of simulated movement.
  void tick() {
    elapsedSeconds += 1;
    movingSeconds += 1;
    _tick += 1;

    // Gentle curve so the map polyline is visible (circle-ish).
    final headingRad = (_tick * 0.035) % (2 * math.pi);
    final step = speedForTick(_tick);
    _lastStepMeters = step;
    final dLat = (step * math.cos(headingRad)) / 111320.0;
    final dLng =
        (step * math.sin(headingRad)) /
        (111320.0 * math.cos(lat * math.pi / 180.0));
    lat += dLat;
    lng += dLng;
    distanceMeters += step;
    trail.add(RunLatLng(lat, lng));

    final instant = 1000.0 / step; // sec/km for this second
    _instantPaceSecPerKm = instant;
    _bestPaceSecPerKm = switch (_bestPaceSecPerKm) {
      null => instant,
      final existing => math.min(existing, instant),
    };

    if (trail.length > 5000) {
      trail.removeRange(0, trail.length - 4000);
    }
    _recordCompletedSplits();
  }

  void _recordCompletedSplits() {
    while (distanceMeters >= _nextSplitAtMeters) {
      final splitDuration = math.max(0, movingSeconds - _lastSplitMovingSeconds);
      completedSplits.add(
        RunSplit(
          km: (_nextSplitAtMeters / 1000).round(),
          distanceMeters: 1000,
          durationSeconds: splitDuration,
          paceSecPerKm: splitDuration.toDouble(),
          isPartial: false,
        ),
      );
      _lastSplitMovingSeconds = movingSeconds;
      _nextSplitAtMeters += 1000;
    }
  }

  RunSplit? get currentPartialSplit {
    if (distanceMeters < 1 && completedSplits.isEmpty) return null;
    final partialMeters = distanceMeters % 1000.0;
    if (partialMeters < 0.5 && distanceMeters >= 1000) return null;
    final duration = math.max(0, movingSeconds - _lastSplitMovingSeconds);
    final pace = partialMeters >= 1
        ? duration / (partialMeters / 1000.0)
        : null;
    return RunSplit(
      km: completedSplits.length + 1,
      distanceMeters: partialMeters,
      durationSeconds: duration,
      paceSecPerKm: pace,
      isPartial: true,
    );
  }

  double? get currentPaceSecPerKm {
    // Prefer the latest second so the live sheet reflects variance.
    if (_instantPaceSecPerKm != null) return _instantPaceSecPerKm;
    if (distanceMeters < 1 || movingSeconds <= 0) return null;
    return movingSeconds / (distanceMeters / 1000.0);
  }

  double? get avgPaceSecPerKm {
    if (distanceMeters < 1 || movingSeconds <= 0) return null;
    return movingSeconds / (distanceMeters / 1000.0);
  }

  /// Last step length (meters) — exposed for tests.
  double get lastStepMeters => _lastStepMeters;

  RunTrackingState toState({required bool locationGranted}) {
    return RunTrackingState(
      supported: true,
      locationGranted: locationGranted,
      status: RunTrackingState.recording,
      activityId: activityId,
      startedAt: startedAt,
      updatedAt: DateTime.now(),
      distanceMeters: distanceMeters,
      durationSeconds: elapsedSeconds,
      movingTimeSeconds: movingSeconds,
      currentPaceSecPerKm: currentPaceSecPerKm,
      lat: lat,
      lng: lng,
      accuracyMeters: 5,
      trail: List.unmodifiable(trail),
      splits: List.unmodifiable(completedSplits),
      currentSplit: currentPartialSplit,
      errorCode: null,
      errorMessage: null,
    );
  }

  RunTrackingState toPausedState({required bool locationGranted}) {
    return toState(locationGranted: locationGranted).copyWith(
      status: RunTrackingState.paused,
    );
  }

  /// Spool-shaped payload for [RunRepository.importNativeSpool].
  Map<String, dynamic> toSpoolPayload() {
    final endedAt = DateTime.now();
    final points = <Map<String, dynamic>>[];
    for (var i = 0; i < trail.length; i++) {
      final p = trail[i];
      // Point 0 is the start; subsequent points align with tick 1..n.
      final speed = i == 0 ? null : speedForTick(i);
      points.add({
        'id': _uuid.v4(),
        'seq': i,
        'lat': p.lat,
        'lng': p.lng,
        'accuracy': 5.0,
        'speed': speed,
        'recorded_at': startedAt.add(Duration(seconds: i)).toIso8601String(),
      });
    }
    return {
      'activity': {
        'id': activityId,
        'status': 'completed',
        'started_at': startedAt.toIso8601String(),
        'ended_at': endedAt.toIso8601String(),
        'duration_seconds': elapsedSeconds,
        'moving_time_seconds': movingSeconds,
        'distance_meters': distanceMeters,
        'avg_pace_sec_per_km': avgPaceSecPerKm,
        'max_pace_sec_per_km': _bestPaceSecPerKm ?? avgPaceSecPerKm,
        'calories': (distanceMeters / 1000.0 * 70).round(),
        'title': 'Debug Run',
        'notes': 'Simulated debug run',
      },
      'points': points,
    };
  }
}
