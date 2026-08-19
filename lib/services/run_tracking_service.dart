import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/models/run_tracking_state.dart';
import 'package:workout_notes/repositories/run_repository.dart';

/// Flutter facade for the Android foreground GPS run tracker.
///
/// The EventChannel is a live UI signal. Durable activities are imported from
/// the native spool through the MethodChannel after stop / app relaunch.
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

  RunTrackingState get state => _state;
  bool get isSupported => _state.supported;
  bool get isActive => _state.isActive;
  int get recoveredCount => _recoveredCount;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> initialize() async {
    if (!_isAndroid) {
      _initialized = true;
      return;
    }
    if (!_initialized) {
      _initialized = true;
      _eventSubscription = events.receiveBroadcastStream().listen(
        _onEvent,
        onError: (Object error, StackTrace stack) {
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
    if (!_isAndroid) return {'supported': false};
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
      _state = _state.copyWith(supported: false);
      notifyListeners();
      return {'supported': false};
    } catch (error) {
      _setError('capabilities_error', error.toString());
      return {'supported': true, 'error': error.toString()};
    }
  }

  Future<RunTrackingState> getState() async {
    if (!_isAndroid) return _state;
    try {
      final result = await methods.invokeMapMethod<String, dynamic>('getState');
      if (result != null) {
        _applyNativeState(result);
      }
    } on MissingPluginException {
      _state = _state.copyWith(supported: false);
      notifyListeners();
    } catch (error) {
      _setError('state_error', error.toString());
    }
    return _state;
  }

  Future<bool> requestPermissions() async {
    if (!_isAndroid) return false;
    try {
      final granted =
          await methods.invokeMethod<bool>('requestPermissions') ?? false;
      _state = _state.copyWith(locationGranted: granted, clearError: true);
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

  Future<bool> start() async {
    if (!_isAndroid) return false;
    if (_state.isActive) return true;
    if (!_state.locationGranted) {
      final granted = await requestPermissions();
      if (!granted) return false;
    }
    try {
      _trail.clear();
      final result = await methods.invokeMapMethod<String, dynamic>('start');
      if (result != null) {
        _applyNativeState(result);
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
    if (!_isAndroid || !_state.isRecording) return;
    try {
      final result = await methods.invokeMapMethod<String, dynamic>('pause');
      if (result != null) _applyNativeState(result);
    } catch (error) {
      _setError('pause_error', error.toString());
    }
  }

  Future<void> resume() async {
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
    if (!_isAndroid) return null;
    final activityId = _state.activityId;
    try {
      await methods.invokeMapMethod<String, dynamic>('stop');
    } catch (error) {
      _setError('stop_error', error.toString());
    }

    RunActivity? imported;
    if (activityId != null) {
      imported = await _importSpool(activityId);
    } else {
      await recoverPendingSessions();
      // Fall back: latest recovered completed activity is not tracked here.
    }

    _trail.clear();
    _state = RunTrackingState.initial(supported: true).copyWith(
      locationGranted: _state.locationGranted,
    );
    notifyListeners();
    return imported;
  }

  Future<void> discard() async {
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
    if (!_isAndroid || _recovering) return _recoveredCount;
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
        // Skip the spool still owned by a live native service.
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
        activityMap['status'] = 'completed';
        activityMap['ended_at'] ??= DateTime.now().toIso8601String();
        raw['activity'] = activityMap;
      }
      final imported = await _repository.importNativeSpool(
        Map<String, dynamic>.from(raw),
      );
      await methods.invokeMethod<dynamic>('deleteSpool', id);
      return imported;
    } catch (error) {
      // Leave the spool for retry on next launch.
      _setError('import_error', error.toString());
      return null;
    }
  }

  void _onEvent(dynamic event) {
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
        // Cap live trail for UI memory.
        if (_trail.length > 5000) {
          _trail.removeRange(0, _trail.length - 4000);
        }
      }
    }
    _state = RunTrackingState.fromMap(map, trail: List.unmodifiable(_trail));
    notifyListeners();
  }

  void _setError(String code, String message) {
    _state = _state.copyWith(errorCode: code, errorMessage: message);
    notifyListeners();
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    super.dispose();
  }
}
