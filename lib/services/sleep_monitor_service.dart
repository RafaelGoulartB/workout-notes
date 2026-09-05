import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/sleep_monitor_state.dart';
import '../models/sleep_monitor_mode.dart';
import '../repositories/sleep_monitor_repository.dart';
import 'package:workout_notes/models/sleep_monitor_segment.dart';
import 'package:workout_notes/services/sleep_wake_engine.dart';
import 'package:workout_notes/services/sleep_diagnostic_store.dart';

/// Flutter facade for the Android foreground sleep monitor.
///
/// The EventChannel is deliberately only a live UI signal. Durable sessions
/// are imported from the native spool through the MethodChannel.
class SleepMonitorService extends ChangeNotifier {
  static final SleepMonitorService _instance = SleepMonitorService._();
  static SleepMonitorService get instance => _instance;

  SleepMonitorService._();

  static const methods = MethodChannel('workout_notes/sleep_monitor/methods');
  static const events = EventChannel('workout_notes/sleep_monitor/events');

  final SleepMonitorRepository _repository = SleepMonitorRepository();
  SleepMonitorState _state = SleepMonitorState.initial(
    supported: !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
  );
  StreamSubscription<dynamic>? _eventSubscription;
  bool _initialized = false;
  bool _recovering = false;
  int _recoveredCount = 0;
  SleepWakeCursor? _liveCursor;
  DateTime? _lastLiveSegment;
  SleepWakeDecision? _liveDecision;
  SleepWakeDecision? get liveDecision => _liveDecision;
  String? _restoredLiveSession;

  SleepMonitorState get state => _state;
  bool get isSupported => _state.supported;
  bool get isMonitoring => _state.isActive;
  int get recoveredCount => _recoveredCount;

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
        microphoneGranted:
            capabilities['microphone_granted'] as bool? ??
            _state.microphoneGranted,
        exactAlarmGranted:
            capabilities['exact_alarm_granted'] as bool? ??
            _state.exactAlarmGranted,
        fullScreenIntentGranted:
            capabilities['full_screen_intent_granted'] as bool? ??
            _state.fullScreenIntentGranted,
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

  Future<SleepMonitorState> getState() async {
    if (!_isAndroid) return _state;
    try {
      final result = await methods.invokeMapMethod<String, dynamic>('getState');
      if (result != null) {
        _state = SleepMonitorState.fromMap(result);
        await _restoreLiveState();
        _updateLiveState(_state.latestSegment);
        notifyListeners();
      }
    } on MissingPluginException {
      _state = _state.copyWith(supported: false);
      notifyListeners();
    } catch (error) {
      _setError('state_error', error.toString());
    }
    return _state;
  }

  Future<bool> requestMicrophonePermission() async {
    if (!_isAndroid) return false;
    try {
      final granted =
          await methods.invokeMethod<bool>('requestMicrophonePermission') ??
          false;
      _state = _state.copyWith(microphoneGranted: granted);
      notifyListeners();
      return granted;
    } on PlatformException catch (error) {
      _setError(error.code, error.message ?? error.toString());
      return false;
    } catch (error) {
      _setError('microphone_permission', error.toString());
      return false;
    }
  }

  Future<Map<String, bool>> getAlarmCapabilities() async {
    if (!_isAndroid) {
      return {'exactAlarmGranted': false, 'fullScreenIntentGranted': false};
    }
    try {
      final result = await methods.invokeMapMethod<String, dynamic>(
        'getAlarmCapabilities',
      );
      final exact = result?['exact_alarm_granted'] as bool? ?? false;
      final fullScreen =
          result?['full_screen_intent_granted'] as bool? ?? false;
      _state = _state.copyWith(
        exactAlarmGranted: exact,
        fullScreenIntentGranted: fullScreen,
      );
      notifyListeners();
      return {
        'exactAlarmGranted': exact,
        'fullScreenIntentGranted': fullScreen,
      };
    } catch (error) {
      _setError('alarm_capabilities', error.toString());
      return {'exactAlarmGranted': false, 'fullScreenIntentGranted': false};
    }
  }

  Future<bool> requestExactAlarmPermission() async {
    if (!_isAndroid) return false;
    try {
      await methods.invokeMethod<bool>('requestExactAlarmPermission');
      final capabilities = await getAlarmCapabilities();
      return capabilities['exactAlarmGranted'] ?? false;
    } catch (error) {
      _setError('exact_alarm_denied', error.toString());
      return false;
    }
  }

  Future<bool> requestFullScreenPermission() async {
    if (!_isAndroid) return false;
    try {
      await methods.invokeMethod<bool>('requestFullScreenPermission');
      final capabilities = await getAlarmCapabilities();
      return capabilities['fullScreenIntentGranted'] ?? false;
    } catch (error) {
      _setError('full_screen_denied', error.toString());
      return false;
    }
  }

  Future<bool> startMonitoring({
    DateTime? alarmAt,
    SleepMonitoringMode mode = SleepMonitoringMode.alarmWithoutMission,
    SleepMissionConfig? mission,
    int maxSnoozes = 3,
  }) async {
    if (!_isAndroid) return false;
    if (_state.isActive) return true;
    if (mode.hasAlarm && alarmAt == null) {
      _setError('invalid_alarm_time', 'Alarm time is required');
      return false;
    }
    if (mode.requiresMission && !(mission?.isConfigured ?? false)) {
      _setError('mission_not_configured', 'A barcode mission is required');
      return false;
    }
    try {
      final arguments = <String, dynamic>{'monitor_mode': mode.wireValue};
      arguments['max_snoozes'] = maxSnoozes.clamp(0, 10);
      if (alarmAt != null) {
        arguments['alarm_at_epoch_ms'] = alarmAt.millisecondsSinceEpoch;
      }
      if (mission != null) {
        arguments.addAll({
          'mission_type': mission.type,
          'mission_hash': mission.hash,
          'mission_salt': mission.salt,
          'mission_format': mission.format,
        });
      }
      final result = await methods.invokeMapMethod<String, dynamic>(
        'startMonitoring',
        arguments,
      );
      if (result != null) {
        _onEvent(result);
      } else {
        await getState();
      }
      return _state.isActive;
    } on PlatformException catch (error) {
      _setError(error.code, error.message ?? error.toString());
      return false;
    } catch (error) {
      _setError('start_failed', error.toString());
      return false;
    }
  }

  Future<bool> updateAlarm(DateTime alarmAt) async {
    if (!_isAndroid || !_state.isActive) return false;
    try {
      final result = await methods.invokeMapMethod<String, dynamic>(
        'updateAlarm',
        {'alarm_at_epoch_ms': alarmAt.millisecondsSinceEpoch},
      );
      if (result != null) _onEvent(result);
      return _state.alarmAt != null &&
          _state.alarmAt!.millisecondsSinceEpoch ==
              alarmAt.millisecondsSinceEpoch;
    } on PlatformException catch (error) {
      _setError(error.code, error.message ?? error.toString());
      return false;
    } catch (error) {
      _setError('alarm_schedule_failed', error.toString());
      return false;
    }
  }

  Future<bool> openSnoozedAlarmMission() async {
    if (!_isAndroid ||
        !_state.isAlarmSnoozing ||
        !_state.mode.requiresMission) {
      return false;
    }
    try {
      final result = await methods.invokeMapMethod<String, dynamic>(
        'openSnoozedAlarmMission',
      );
      if (result != null) _onEvent(result);
      return _state.alarmRinging;
    } on PlatformException catch (error) {
      _setError(error.code, error.message ?? error.toString());
      return false;
    } catch (error) {
      _setError('alarm_resume_failed', error.toString());
      return false;
    }
  }

  Future<bool> dismissSnoozedAlarm() async {
    if (!_isAndroid || !_state.isAlarmSnoozing || _state.mode.requiresMission) {
      return false;
    }
    try {
      final result = await methods.invokeMapMethod<String, dynamic>(
        'dismissSnoozedAlarm',
      );
      if (result != null) _onEvent(result);
      return _state.alarmDismissed;
    } on PlatformException catch (error) {
      _setError(error.code, error.message ?? error.toString());
      return false;
    } catch (error) {
      _setError('alarm_dismiss_failed', error.toString());
      return false;
    }
  }

  Future<Map<String, dynamic>?> scanBarcodeForMission() async {
    if (!_isAndroid) return null;
    try {
      return await methods.invokeMapMethod<String, dynamic>(
        'scanBarcodeForMission',
      );
    } on PlatformException catch (error) {
      _setError(error.code, error.message ?? error.toString());
      return null;
    } catch (error) {
      _setError('barcode_scan_failed', error.toString());
      return null;
    }
  }

  Future<Map<String, bool>> getMissionCapabilities() async {
    if (!_isAndroid) return {'cameraGranted': false};
    try {
      final result = await methods.invokeMapMethod<String, dynamic>(
        'getMissionCapabilities',
      );
      return {'cameraGranted': result?['camera_granted'] as bool? ?? false};
    } catch (error) {
      _setError('mission_capabilities', error.toString());
      return {'cameraGranted': false};
    }
  }

  Future<bool> requestCameraPermission() async {
    if (!_isAndroid) return false;
    try {
      return await methods.invokeMethod<bool>('requestCameraPermission') ??
          false;
    } on PlatformException catch (error) {
      _setError(error.code, error.message ?? error.toString());
      return false;
    } catch (error) {
      _setError('camera_permission', error.toString());
      return false;
    }
  }

  Future<bool> openCameraSettings() async {
    if (!_isAndroid) return false;
    try {
      return await methods.invokeMethod<bool>('openCameraSettings') ?? false;
    } catch (error) {
      _setError('camera_settings', error.toString());
      return false;
    }
  }

  Future<void> stopMonitoring() async {
    if (!_isAndroid || !_state.isActive) return;
    try {
      final result = await methods.invokeMapMethod<String, dynamic>(
        'stopMonitoring',
      );
      if (result != null) _onEvent(result);
      await recoverPendingSessions();
    } on PlatformException catch (error) {
      _setError(error.code, error.message ?? error.toString());
    } catch (error) {
      _setError('stop_failed', error.toString());
    }
  }

  Future<void> discardSession() async {
    final sessionId = _state.sessionId;
    if (_isAndroid && sessionId != null) {
      try {
        await methods.invokeMethod<void>('discardSession', sessionId);
      } catch (_) {}
    }
    if (sessionId != null) {
      await _repository.deleteSession(sessionId);
    }
    _state = SleepMonitorState.initial(supported: _isAndroid);
    notifyListeners();
  }

  /// Imports every finished native spool and recovers unfinished sessions as
  /// interrupted. A failed SQLite commit leaves the spool intact.
  Future<int> recoverPendingSessions() async {
    if (!_isAndroid || _recovering) return 0;
    _recovering = true;
    var imported = 0;
    try {
      final current = await getState();
      final raw =
          await methods.invokeListMethod<dynamic>('listPendingSessions') ??
          const <dynamic>[];
      for (final item in raw) {
        if (item is! Map) continue;
        final listed = Map<String, dynamic>.from(item);
        final id =
            listed['id'] as String? ??
            (listed['session'] is Map
                ? (listed['session'] as Map)['id'] as String?
                : null);
        if (id == null || (current.isActive && id == current.sessionId)) {
          continue;
        }
        try {
          final spool = listed.containsKey('segments')
              ? listed
              : await methods.invokeMapMethod<String, dynamic>(
                      'readSession',
                      id,
                    ) ??
                    listed;
          final importedSession = await _repository.importNativeSpool(spool);
          try {
            await SleepDiagnosticStore().save(
              spool,
              resultSummary: importedSession.toMap(),
            );
          } catch (_) {
            _setError('diagnostic_save_failed', 'diagnostic_save_failed');
          }
          await methods.invokeMethod<void>('deleteSpool', id);
          imported++;
        } catch (error) {
          _setError('import_failed', error.toString());
          // The native spool remains available for the next attempt.
        }
      }
      if (imported > 0) {
        _recoveredCount += imported;
        notifyListeners();
      }
    } catch (error) {
      _setError('recovery_failed', error.toString());
    } finally {
      _recovering = false;
    }
    return imported;
  }

  void _onEvent(dynamic event) {
    if (event is! Map) return;
    try {
      final map = Map<String, dynamic>.from(event);
      _state = SleepMonitorState.fromMap(map);
      _updateLiveState(_state.latestSegment);
      if (map['alarm_dismissed'] == true &&
          map['session_id'] is String &&
          map['alarm_dismiss_method'] is String) {
        _repository
            .markAlarmDismissed(
              map['session_id'] as String,
              map['alarm_dismiss_method'] as String,
              DateTime.now(),
            )
            .catchError((_) {});
      }
      notifyListeners();
    } catch (error) {
      _setError('event_invalid', error.toString());
    }
  }

  void _updateLiveState(SleepMonitorSegment? segment) {
    if (!_state.isActive ||
        segment == null ||
        segment.sessionId != _state.sessionId ||
        segment.audioSampleRate == null) {
      _liveCursor = null;
      _lastLiveSegment = null;
      _liveDecision = null;
      return;
    }
    if (_liveCursor?.sessionId != segment.sessionId) {
      _liveCursor = SleepWakeCursor(sessionId: segment.sessionId);
      _lastLiveSegment = null;
    }
    if (_lastLiveSegment != null &&
        !segment.startedAt.isAfter(_lastLiveSegment!)) {
      return;
    }
    _liveDecision = _liveCursor!.add(segment);
    _lastLiveSegment = segment.startedAt;
  }

  Future<void> _restoreLiveState() async {
    final id = _state.sessionId;
    if (!_isAndroid ||
        !_state.isActive ||
        id == null ||
        _restoredLiveSession == id) {
      return;
    }
    _restoredLiveSession = id;
    try {
      // Once on opening the session; no polling, background isolate or raw audio.
      final spool = await methods.invokeMapMethod<String, dynamic>(
        'readSession',
        id,
      );
      if (_state.sessionId != id || !_state.isActive) return;
      final segments =
          (spool?['segments'] as List? ?? const [])
              .whereType<Map>()
              .map(
                (s) =>
                    SleepMonitorSegment.fromMap(Map<String, dynamic>.from(s)),
              )
              .toList()
            ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
      _liveCursor = null;
      _lastLiveSegment = null;
      for (final segment in segments) {
        _updateLiveState(segment);
      }
    } catch (_) {
      _restoredLiveSession = null;
    }
  }

  void _setError(String code, String message) {
    _state = _state.copyWith(errorCode: code, errorMessage: message);
    notifyListeners();
  }

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void dispose() {
    _eventSubscription?.cancel();
    super.dispose();
  }
}
