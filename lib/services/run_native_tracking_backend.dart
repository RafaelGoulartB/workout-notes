import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:workout_notes/models/run_lap.dart';
import 'package:workout_notes/models/run_tracking_state.dart';
import 'package:workout_notes/services/run_tracking_backend.dart';

/// The Android foreground GPS tracker, reached over a MethodChannel (commands)
/// and an EventChannel (live UI signal). Durable data flows through the native
/// spool, never through the events.
class NativeRunTrackingBackend implements RunTrackingBackend {
  NativeRunTrackingBackend(this._sink);

  static const methods = MethodChannel('workout_notes/run_tracking/methods');
  static const events = EventChannel('workout_notes/run_tracking/events');

  final RunTrackingSink _sink;
  final List<RunLatLng> _trail = [];
  StreamSubscription<dynamic>? _eventSubscription;

  bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

  @override
  bool get isSimulated => false;

  /// Starts listening to the native live-state events. Idempotent.
  void listen() {
    _eventSubscription ??= events.receiveBroadcastStream().listen(
      (event) {
        if (event is! Map) return;
        apply(Map<String, dynamic>.from(event));
      },
      onError: (Object error, StackTrace stack) {
        _sink.reportError('event_channel', error.toString());
      },
    );
  }

  /// Pulls the current native state (used to resync and to poll transitions).
  Future<RunTrackingState> refresh() async {
    if (!_isAndroid) return _sink.state;
    try {
      final result = await methods.invokeMapMethod<String, dynamic>('getState');
      if (result != null) apply(result);
    } on MissingPluginException {
      _sink.publish(_sink.state.copyWith(supported: kDebugMode));
    } catch (error) {
      _sink.reportError('state_error', error.toString());
    }
    return _sink.state;
  }

  /// Folds a native state map into the UI state, growing the map trail.
  void apply(Map<String, dynamic> map) {
    final lat = (map['lat'] as num?)?.toDouble();
    final lng = (map['lng'] as num?)?.toDouble();
    if (lat != null && lng != null) {
      final last = _trail.isEmpty ? null : _trail.last;
      if (last == null || last.lat != lat || last.lng != lng) {
        _trail.add(RunLatLng(lat, lng));
        if (_trail.length > 5000) {
          _trail.removeRange(0, _trail.length - 4000);
        }
      }
    }
    _sink.publish(
      RunTrackingState.fromMap(map, trail: List.unmodifiable(_trail)),
    );
  }

  /// Asks the native side to reattach to a run it kept alive while Flutter was
  /// closed, and waits until that run reports its state.
  Future<void> recoverActive() async {
    if (!_isAndroid || _sink.state.isActive) return;
    try {
      final requested =
          await methods.invokeMethod<bool>('recoverActive') ?? false;
      if (!requested) return;
      await awaitStatus({
        RunTrackingState.recording,
        RunTrackingState.paused,
        RunTrackingState.completed,
        RunTrackingState.discarded,
      }, timeout: const Duration(seconds: 8));
    } on MissingPluginException {
      // Older debug builds and tests.
    } catch (error) {
      _sink.reportError('active_recovery_error', error.toString());
    }
  }

  /// Polls native state until [statuses] match or [timeout] elapses.
  Future<bool> awaitStatus(
    Set<String> statuses, {
    Duration timeout = const Duration(seconds: 5),
    Duration interval = const Duration(milliseconds: 150),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (statuses.contains(_sink.state.status)) return true;
      if (_sink.state.errorCode == 'location_denied') return false;
      await Future<void>.delayed(interval);
      await refresh();
    }
    return statuses.contains(_sink.state.status);
  }

  @override
  Future<bool> start() async {
    if (_sink.state.isActive) return true;
    if (!_sink.state.locationGranted) {
      _sink.reportError(
        'location_denied',
        'Precise location permission is required',
      );
      return false;
    }
    try {
      _trail.clear();
      final result = await methods.invokeMapMethod<String, dynamic>('start');
      if (result != null) apply(result);
      final ready = await awaitStatus({
        RunTrackingState.recording,
        RunTrackingState.paused,
      }, timeout: const Duration(seconds: 8));
      if (!ready) {
        if (_sink.state.errorCode == null) {
          _sink.reportError('start_timeout', 'Run service did not start in time');
        }
        return _sink.state.isActive;
      }
      return true;
    } on PlatformException catch (error) {
      _sink.reportError(error.code, error.message ?? error.toString());
      return false;
    } catch (error) {
      _sink.reportError('start_error', error.toString());
      return false;
    }
  }

  @override
  Future<void> pause() async {
    if (!_isAndroid || !_sink.state.isRecording) return;
    await _command('pause', 'pause_error');
  }

  @override
  Future<void> resume() async {
    // "Resume" also ends an auto-pause early ("I'm moving, carry on").
    final state = _sink.state;
    if (!_isAndroid || !(state.isPaused || state.isAutoPaused)) return;
    await _command('resume', 'resume_error');
  }

  @override
  Future<RunLap?> lap() async {
    final before = _sink.state.laps.length;
    if (!_isAndroid || !_sink.state.isRecording) return null;
    if (!await _command('lap', 'lap_error')) return null;
    final laps = _sink.state.laps;
    return laps.length > before ? laps.last : null;
  }

  Future<bool> _command(String method, String errorCode) async {
    try {
      final result = await methods.invokeMapMethod<String, dynamic>(method);
      if (result != null) apply(result);
      return true;
    } catch (error) {
      _sink.reportError(errorCode, error.toString());
      return false;
    }
  }

  @override
  Future<Map<String, dynamic>?> stopForReview() async {
    if (!_isAndroid) return null;
    final activityId = _sink.state.activityId;
    await _command('stop', 'stop_error');
    await awaitStatus({
      RunTrackingState.completed,
      RunTrackingState.idle,
      RunTrackingState.discarded,
    }, timeout: const Duration(seconds: 5));

    final resolvedId = activityId ?? _sink.state.activityId;
    _trail.clear();
    if (resolvedId == null) return null;
    try {
      final raw = await methods.invokeMapMethod<String, dynamic>(
        'markPendingReview',
        resolvedId,
      );
      return raw == null ? null : Map<String, dynamic>.from(raw);
    } catch (error) {
      _sink.reportError('review_error', error.toString());
      return null;
    }
  }

  @override
  Future<void> discard() async {
    _trail.clear();
    if (!_isAndroid) return;
    final activityId = _sink.state.activityId;
    try {
      await methods.invokeMethod<dynamic>('discard', activityId);
    } catch (error) {
      _sink.reportError('discard_error', error.toString());
    }
    if (activityId != null) {
      try {
        await methods.invokeMethod<dynamic>('deleteSpool', activityId);
      } catch (_) {
        // The spool may already be gone; cleanup is best-effort.
      }
    }
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _eventSubscription = null;
  }
}
