import 'dart:math' as math;

import 'package:uuid/uuid.dart';
import 'package:workout_notes/models/run_split.dart';
import 'package:workout_notes/models/run_tracking_state.dart';

/// Pure debug GPS path generator. Not used in release builds.
class RunDebugSimulator {
  static const _uuid = Uuid();

  /// ~15 m/s so each km lands in about a minute — good for emulator QA.
  static const metersPerSecond = 15.0;

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

  /// Advances one second of simulated movement.
  void tick() {
    elapsedSeconds += 1;
    movingSeconds += 1;
    _tick += 1;

    // Gentle curve so the map polyline is visible (circle-ish).
    final headingRad = (_tick * 0.035) % (2 * math.pi);
    final step = metersPerSecond;
    final dLat = (step * math.cos(headingRad)) / 111320.0;
    final dLng =
        (step * math.sin(headingRad)) /
        (111320.0 * math.cos(lat * math.pi / 180.0));
    lat += dLat;
    lng += dLng;
    distanceMeters += step;
    trail.add(RunLatLng(lat, lng));
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
    if (distanceMeters < 1 || movingSeconds <= 0) return null;
    return movingSeconds / (distanceMeters / 1000.0);
  }

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
      points.add({
        'id': _uuid.v4(),
        'seq': i,
        'lat': p.lat,
        'lng': p.lng,
        'accuracy': 5.0,
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
        'avg_pace_sec_per_km': currentPaceSecPerKm,
        'max_pace_sec_per_km': currentPaceSecPerKm,
        'calories': (distanceMeters / 1000.0 * 70).round(),
        'title': 'Debug Run',
        'notes': 'Simulated debug run',
      },
      'points': points,
    };
  }
}
