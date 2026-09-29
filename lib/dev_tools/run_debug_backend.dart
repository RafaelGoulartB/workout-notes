import 'dart:async';

import 'package:workout_notes/dev_tools/run_debug_simulator.dart';
import 'package:workout_notes/models/run_lap.dart';
import 'package:workout_notes/services/run_tracking_backend.dart';

/// Debug-only tracker that fakes a GPS run (see [RunDebugSimulator]) so the
/// emulator can exercise distance, pace, splits and save without real motion.
///
/// It has no native service behind it: cues are not spoken and the review
/// draft stays in memory.
class RunDebugBackend implements RunTrackingBackend {
  RunDebugBackend(
    this._sink, {
    required double startLat,
    required double startLng,
  }) : _sim = RunDebugSimulator.create(startLat: startLat, startLng: startLng);

  final RunTrackingSink _sink;
  final RunDebugSimulator _sim;
  Timer? _timer;
  bool _paused = false;

  @override
  bool get isSimulated => true;

  @override
  Future<bool> start() async {
    _publish();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_paused) return;
      _sim.tick();
      _publish();
    });
    return true;
  }

  @override
  Future<void> pause() async {
    if (!_sink.state.isRecording) return;
    _paused = true;
    _publish();
  }

  @override
  Future<void> resume() async {
    if (!_sink.state.isPaused) return;
    _paused = false;
    _publish();
  }

  @override
  Future<RunLap?> lap() async {
    if (!_sink.state.isRecording) return null;
    final lap = _sim.markLap();
    if (lap != null) _publish();
    return lap;
  }

  @override
  Future<Map<String, dynamic>?> stopForReview() async {
    _stopTimer();
    final payload = _sim.toSpoolPayload();
    final activity = Map<String, dynamic>.from(
      payload['activity'] as Map? ?? const {},
    );
    activity['status'] = 'pending_review';
    activity['splits'] = [
      for (final split in _sink.state.splits)
        {
          'km': split.km,
          'distance_meters': split.distanceMeters,
          'duration_seconds': split.durationSeconds,
          'pace_sec_per_km': split.paceSecPerKm,
          'is_partial': split.isPartial,
        },
    ];
    payload['activity'] = activity;
    return Map<String, dynamic>.from(payload);
  }

  @override
  Future<void> discard() async => _stopTimer();

  @override
  void dispose() => _stopTimer();

  void _publish() {
    var state = _paused
        ? _sim.toPausedState(locationGranted: true)
        : _sim.toState(locationGranted: true);
    final context = _sink.sessionContext;
    if (context != null) state = state.copyWith(sessionContext: context);
    _sink.publish(state);
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }
}
