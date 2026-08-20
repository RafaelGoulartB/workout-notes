import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/models/run_tracking_state.dart';
import 'package:workout_notes/repositories/run_repository.dart';
import 'package:workout_notes/services/run_debug_simulator.dart';
import 'package:workout_notes/utils/run_spool_recovery.dart';

/// Flutter facade for the Android foreground GPS run tracker.
///
/// The EventChannel is a live UI signal. Durable activities are imported from
/// the native spool through the MethodChannel after stop / app relaunch.
///
/// In [kDebugMode] only, [startDebugSimulation] drives a fake GPS path so the
/// emulator can exercise distance, pace, splits, and save without real motion.
class RunTrackingService extends ChangeNotifier {
  static final RunTrackingService _instance = RunTrackingService._();
  static RunTrackingService get instance => _instance;

  RunTrackingService._();

  static const methods = MethodChannel('workout_notes/run_tracking/methods');
  static const events = EventChannel('workout_notes/run_tracking/events');

  final RunRepository _repository = RunRepository();
  RunTrackingState _state = RunTrackingState.initial(
    supported: !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
  );
  StreamSubscription<dynamic>? _eventSubscription;
  bool _initialized = false;
  bool _recovering = false;
  int _recoveredCount = 0;
  final List<RunLatLng> _trail = [];

  RunDebugSimulator? _debugSim;
  Timer? _debugTimer;
  bool _debugPaused = false;
  bool _askedBackgroundPermission = false;

  RunTrackingState get state => _state;
  bool get isSupported => _state.supported;
  bool get isActive => _state.isActive;
  int get recoveredCount => _recoveredCount;
  bool get isDebugSimulating => _debugSim != null;
  bool get canDebugSimulate => kDebugMode;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> initialize() async {
    if (!_isAndroid) {
      if (kDebugMode) {
        _state = _state.copyWith(supported: true, locationGranted: true);
      }
      _initialized = true;
      notifyListeners();
      return;
    }
    if (!_initialized) {
      _initialized = true;
      _eventSubscription = events.receiveBroadcastStream().listen(
        _onEvent,
        onError: (Object error, StackTrace stack) {
          if (_debugSim != null) return;
          _state = _state.copyWith(
            errorCode: 'event_channel',
            errorMessage: error.toString(),
          );
          notifyListeners();
        },
      );
    }
    await getCapabilities();
    await getState();
    await recoverPendingSessions();
  }

  Future<Map<String, dynamic>> getCapabilities() async {
    if (!_isAndroid) {
      if (kDebugMode) {
        return {'supported': true, 'location_granted': true, 'debug': true};
      }
      return {'supported': false};
    }
    try {
      final result = await methods.invokeMapMethod<String, dynamic>(
        'getCapabilities',
      );
      final capabilities = result ?? const <String, dynamic>{};
      _state = _state.copyWith(
        supported: capabilities['supported'] as bool? ?? true,
        locationGranted:
            capabilities['location_granted'] as bool? ?? _state.locationGranted,
      );
      notifyListeners();
      return capabilities;
    } on MissingPluginException {
      _state = _state.copyWith(
        supported: kDebugMode,
        locationGranted: kDebugMode,
      );
      notifyListeners();
      return {'supported': kDebugMode};
    } catch (error) {
      _setError('capabilities_error', error.toString());
      return {'supported': true, 'error': error.toString()};
    }
  }

  Future<RunTrackingState> getState() async {
    if (_debugSim != null) return _state;
    if (!_isAndroid) return _state;
    try {
      final result = await methods.invokeMapMethod<String, dynamic>('getState');
      if (result != null) {
        _applyNativeState(result);
      }
    } on MissingPluginException {
      _state = _state.copyWith(supported: kDebugMode);
      notifyListeners();
    } catch (error) {
      _setError('state_error', error.toString());
    }
    return _state;
  }

  Future<bool> requestPermissions() async {
    if (kDebugMode && !_isAndroid) {
      _state = _state.copyWith(locationGranted: true, clearError: true);
      notifyListeners();
      return true;
    }
    if (!_isAndroid) return false;
    try {
      final granted =
          await methods.invokeMethod<bool>('requestPermissions') ?? false;
      _state = _state.copyWith(locationGranted: granted, clearError: true);
      if (!granted) {
        _setError(
          'location_denied',
          'Precise location permission is required',
        );
      }
      notifyListeners();
      return granted;
    } on PlatformException catch (error) {
      _setError(error.code, error.message ?? error.toString());
      return false;
    } catch (error) {
      _setError('location_permission', error.toString());
      return false;
    }
  }

  /// Android 10+: best-effort background location for screen-off tracking.
  /// Denial does not block starting a run (foreground service still works).
  Future<bool> requestBackgroundPermission() async {
    if (!_isAndroid) return true;
    try {
      final granted =
          await methods.invokeMethod<bool>('requestBackgroundPermission') ??
              false;
      return granted;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Starts a fake GPS run. Available only when [kDebugMode] is true.
  Future<bool> startDebugSimulation({
    double startLat = -23.5505,
    double startLng = -46.6333,
  }) async {
    if (!kDebugMode) return false;
    if (_state.isActive) return true;
    _stopDebugTimer();
    _trail.clear();
    _debugPaused = false;
    _debugSim = RunDebugSimulator.create(
      startLat: startLat,
      startLng: startLng,
    );
    _publishDebugState();
    _debugTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_debugPaused || _debugSim == null) return;
      _debugSim!.tick();
      _publishDebugState();
    });
    return true;
  }

  Future<bool> start() async {
    if (_debugSim != null) return true;
    if (!_isAndroid) {
      if (kDebugMode) return startDebugSimulation();
      return false;
    }
    if (_state.isActive) return true;
    if (!_state.locationGranted) {
      final granted = await requestPermissions();
      if (!granted) return false;
    }
    // Background is optional; FGS location works with while-in-use on most OEMs.
    // Prompt at most once per process so a denial does not spam the system dialog.
    if (!_askedBackgroundPermission) {
      _askedBackgroundPermission = true;
      await requestBackgroundPermission();
    }
    try {
      _trail.clear();
      final result = await methods.invokeMapMethod<String, dynamic>('start');
      if (result != null) {
        _applyNativeState(result);
      }
      final ready = await _awaitStatus(
        {
          RunTrackingState.recording,
          RunTrackingState.paused,
        },
        timeout: const Duration(seconds: 8),
      );
      if (!ready) {
        if (_state.errorCode == null) {
          _setError('start_timeout', 'Run service did not start in time');
        }
        return _state.isActive;
      }
      return true;
    } on PlatformException catch (error) {
      _setError(error.code, error.message ?? error.toString());
      return false;
    } catch (error) {
      _setError('start_error', error.toString());
      return false;
    }
  }

  Future<void> pause() async {
    if (_debugSim != null) {
      if (!_state.isRecording) return;
      _debugPaused = true;
      _state = _debugSim!.toPausedState(
        locationGranted: _state.locationGranted,
      );
      notifyListeners();
      return;
    }
    if (!_isAndroid || !_state.isRecording) return;
    try {
      final result = await methods.invokeMapMethod<String, dynamic>('pause');
      if (result != null) _applyNativeState(result);
    } catch (error) {
      _setError('pause_error', error.toString());
    }
  }

  Future<void> resume() async {
    if (_debugSim != null) {
      if (!_state.isPaused) return;
      _debugPaused = false;
      _publishDebugState();
      return;
    }
    if (!_isAndroid || !_state.isPaused) return;
    try {
      final result = await methods.invokeMapMethod<String, dynamic>('resume');
      if (result != null) _applyNativeState(result);
    } catch (error) {
      _setError('resume_error', error.toString());
    }
  }

  /// Stops tracking, imports the spool into SQLite, and deletes the spool.
  Future<RunActivity?> stop() async {
    if (_debugSim != null) {
      final sim = _debugSim!;
      _stopDebugTimer();
      _debugSim = null;
      _debugPaused = false;
      final imported = await _repository.importNativeSpool(sim.toSpoolPayload());
      _trail.clear();
      _state = RunTrackingState.initial(supported: true).copyWith(
        locationGranted: true,
      );
      notifyListeners();
      return imported;
    }

    if (!_isAndroid) return null;
    final activityId = _state.activityId;
    try {
      final result = await methods.invokeMapMethod<String, dynamic>('stop');
      if (result != null) _applyNativeState(result);
    } catch (error) {
      _setError('stop_error', error.toString());
    }

    await _awaitStatus(
      {
        RunTrackingState.completed,
        RunTrackingState.idle,
        RunTrackingState.discarded,
      },
      timeout: const Duration(seconds: 5),
    );

    final resolvedId = activityId ?? _state.activityId;
    RunActivity? imported;
    if (resolvedId != null) {
      imported = await _importSpool(resolvedId);
    } else {
      await recoverPendingSessions();
    }

    _trail.clear();
    _state = RunTrackingState.initial(supported: true).copyWith(
      locationGranted: _state.locationGranted,
    );
    notifyListeners();
    return imported;
  }

  Future<void> discard() async {
    if (_debugSim != null) {
      _stopDebugTimer();
      _debugSim = null;
      _debugPaused = false;
      _trail.clear();
      _state = RunTrackingState.initial(supported: true).copyWith(
        locationGranted: true,
      );
      notifyListeners();
      return;
    }

    if (!_isAndroid) return;
    final activityId = _state.activityId;
    try {
      await methods.invokeMethod<dynamic>('discard', activityId);
    } catch (error) {
      _setError('discard_error', error.toString());
    }
    if (activityId != null) {
      try {
        await methods.invokeMethod<dynamic>('deleteSpool', activityId);
      } catch (_) {}
    }
    _trail.clear();
    _state = RunTrackingState.initial(supported: true).copyWith(
      locationGranted: _state.locationGranted,
    );
    notifyListeners();
  }

  Future<int> recoverPendingSessions() async {
    if (!_isAndroid || _recovering || _debugSim != null) return _recoveredCount;
    _recovering = true;
    var count = 0;
    try {
      final liveStatus = _state.status;
      final serviceAlive = liveStatus == RunTrackingState.recording ||
          liveStatus == RunTrackingState.paused ||
          liveStatus == RunTrackingState.starting ||
          liveStatus == RunTrackingState.stopping;
      final pending = await methods.invokeListMethod<dynamic>(
            'listPendingSpools',
          ) ??
          const [];
      for (final row in pending) {
        if (row is! Map) continue;
        final map = Map<String, dynamic>.from(row);
        if (map['corrupt'] == true) continue;
        final id = map['id'] as String?;
        final status = map['status'] as String?;
        if (id == null) continue;
        if (status == 'discarded') {
          await methods.invokeMethod<dynamic>('deleteSpool', id);
          continue;
        }
        if (serviceAlive &&
            id == _state.activityId &&
            (status == 'recording' ||
                status == 'paused' ||
                status == 'starting' ||
                status == 'stopping')) {
          continue;
        }
        final imported = await _importSpool(id, forceComplete: !serviceAlive);
        if (imported != null) count += 1;
      }
      _recoveredCount = count;
    } on MissingPluginException {
      // Desktop/tests without the plugin.
    } catch (error) {
      _setError('recover_error', error.toString());
    } finally {
      _recovering = false;
    }
    return count;
  }

  Future<RunActivity?> _importSpool(
    String id, {
    bool forceComplete = false,
  }) async {
    try {
      final raw = await methods.invokeMapMethod<String, dynamic>(
        'readSpool',
        id,
      );
      if (raw == null) return null;
      final activityMap = Map<String, dynamic>.from(
        raw['activity'] as Map? ?? const {},
      );
      var status = activityMap['status'] as String? ?? 'completed';
      if (status == 'discarded') {
        await methods.invokeMethod<dynamic>('deleteSpool', id);
        return null;
      }
      if (!forceComplete &&
          (status == 'recording' ||
              status == 'paused' ||
              status == 'starting')) {
        return null;
      }
      if (forceComplete &&
          (status == 'recording' ||
              status == 'paused' ||
              status == 'starting' ||
              status == 'stopping')) {
        final points = (raw['points'] as List? ?? const [])
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
        RunSpoolRecovery.finalizeInterruptedActivity(
          activityMap,
          points: points,
        );
        raw['activity'] = activityMap;
      }
      final imported = await _repository.importNativeSpool(
        Map<String, dynamic>.from(raw),
      );
      await methods.invokeMethod<dynamic>('deleteSpool', id);
      return imported;
    } catch (error) {
      _setError('import_error', error.toString());
      return null;
    }
  }

  /// Polls native state until [statuses] match or [timeout] elapses.
  Future<bool> _awaitStatus(
    Set<String> statuses, {
    Duration timeout = const Duration(seconds: 5),
    Duration interval = const Duration(milliseconds: 150),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (statuses.contains(_state.status)) return true;
      if (_state.errorCode == 'location_denied') return false;
      await Future<void>.delayed(interval);
      await getState();
    }
    return statuses.contains(_state.status);
  }

  void _onEvent(dynamic event) {
    if (_debugSim != null) return;
    if (event is! Map) return;
    _applyNativeState(Map<String, dynamic>.from(event));
  }

  void _applyNativeState(Map<String, dynamic> map) {
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
    _state = RunTrackingState.fromMap(map, trail: List.unmodifiable(_trail));
    notifyListeners();
  }

  void _publishDebugState() {
    final sim = _debugSim;
    if (sim == null) return;
    _trail
      ..clear()
      ..addAll(sim.trail);
    _state = _debugPaused
        ? sim.toPausedState(locationGranted: true)
        : sim.toState(locationGranted: true);
    notifyListeners();
  }

  void _stopDebugTimer() {
    _debugTimer?.cancel();
    _debugTimer = null;
  }

  void _setError(String code, String message) {
    _state = _state.copyWith(errorCode: code, errorMessage: message);
    notifyListeners();
  }

  @override
  void dispose() {
    _stopDebugTimer();
    _eventSubscription?.cancel();
    super.dispose();
  }
}
