import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/models/run_permission_state.dart';
import 'package:workout_notes/models/run_review_draft.dart';
import 'package:workout_notes/models/run_session_context.dart';
import 'package:workout_notes/models/run_tracking_state.dart';
import 'package:workout_notes/models/scheduled_run.dart';
import 'package:workout_notes/repositories/run_plan_repository.dart';
import 'package:workout_notes/repositories/run_repository.dart';
import 'package:workout_notes/services/run_debug_simulator.dart';
import 'package:workout_notes/services/run_workout_step_engine.dart';
import 'package:workout_notes/utils/run_spool_recovery.dart';

class RunGpsFix {
  final double lat;
  final double lng;
  final double? accuracyMeters;
  final DateTime? recordedAt;

  const RunGpsFix({
    required this.lat,
    required this.lng,
    this.accuracyMeters,
    this.recordedAt,
  });

  bool get isReady => accuracyMeters != null && accuracyMeters! <= 20;
  bool get isRegular => accuracyMeters != null && accuracyMeters! <= 35;
}

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
  final RunPlanRepository _planRepository = RunPlanRepository();
  RunTrackingState _state = RunTrackingState.initial(
    supported: !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
  );
  StreamSubscription<dynamic>? _eventSubscription;
  bool _initialized = false;
  bool _recovering = false;
  int _recoveredCount = 0;
  final List<RunLatLng> _trail = [];
  final Map<String, Map<String, dynamic>> _memoryReviewSpools = {};

  RunDebugSimulator? _debugSim;
  Timer? _debugTimer;
  bool _debugPaused = false;
  bool _nativeDebugSim = false;
  bool _notificationsGranted = false;
  bool _notificationsPermissionRequired = false;
  RunSessionContext? _sessionContext;

  RunTrackingState get state => _state;
  bool get isSupported => _state.supported;
  bool get isActive => _state.isActive;
  int get recoveredCount => _recoveredCount;
  bool get isDebugSimulating => _debugSim != null;
  bool get canDebugSimulate => kDebugMode;
  bool get notificationsGranted => _notificationsGranted;
  bool get notificationsPermissionRequired => _notificationsPermissionRequired;
  RunPermissionState get permissionState => RunPermissionState(
    locationGranted: _state.locationGranted,
    notificationsGranted: _notificationsGranted,
    notificationsPermissionRequired: _notificationsPermissionRequired,
  );

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> initialize() async {
    if (!_isAndroid) {
      if (kDebugMode) {
        _state = _state.copyWith(supported: true, locationGranted: true);
      }
      _notificationsGranted = true;
      _initialized = true;
      notifyListeners();
      await _maintainRouteStorage();
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
    await _recoverActiveNativeSession();
    _sessionContext = _state.sessionContext;
    await recoverPendingSessions();
    await _maintainRouteStorage();
  }

  Future<void> _maintainRouteStorage() async {
    try {
      await _repository.migrateLegacyRoutes(limit: 5);
      await _repository.optimizeOldRoutes(limit: 5);
      await _repository.reclaimIncrementalVacuumPages();
    } catch (_) {
      // Storage maintenance is opportunistic and must never block tracking.
    }
  }

  Future<void> _recoverActiveNativeSession() async {
    if (!_isAndroid || _state.isActive) return;
    try {
      final requested =
          await methods.invokeMethod<bool>('recoverActive') ?? false;
      if (!requested) return;
      await _awaitStatus({
        RunTrackingState.recording,
        RunTrackingState.paused,
        RunTrackingState.completed,
        RunTrackingState.discarded,
      }, timeout: const Duration(seconds: 8));
    } on MissingPluginException {
      // Older debug builds and tests.
    } catch (error) {
      _setError('active_recovery_error', error.toString());
    }
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
      _notificationsGranted =
          capabilities['notifications_granted'] as bool? ?? true;
      _notificationsPermissionRequired =
          capabilities['notifications_permission_required'] as bool? ?? false;
      notifyListeners();
      return capabilities;
    } on MissingPluginException {
      _state = _state.copyWith(
        supported: kDebugMode,
        locationGranted: kDebugMode,
      );
      _notificationsGranted = kDebugMode;
      _notificationsPermissionRequired = false;
      notifyListeners();
      return {'supported': kDebugMode};
    } catch (error) {
      _setError('capabilities_error', error.toString());
      return {'supported': true, 'error': error.toString()};
    }
  }

  Future<RunTrackingState> getState() async {
    if (_debugSim != null && !_nativeDebugSim) return _state;
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

  Future<bool> requestLocationPermission() async {
    if (kDebugMode && !_isAndroid) {
      _state = _state.copyWith(locationGranted: true, clearError: true);
      notifyListeners();
      return true;
    }
    if (!_isAndroid) return false;
    try {
      final granted =
          await methods.invokeMethod<bool>('requestLocationPermission') ??
          false;
      _state = _state.copyWith(locationGranted: granted, clearError: true);
      if (!granted) {
        _setError('location_denied', 'Precise location permission is required');
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

  /// Android 13+: optional permission that keeps foreground-run controls in the
  /// notification drawer. A denial never blocks GPS recording.
  Future<bool> requestNotificationPermission() async {
    if (!_isAndroid) return true;
    if (!_notificationsPermissionRequired) {
      _notificationsGranted = true;
      notifyListeners();
      return true;
    }
    try {
      final granted =
          await methods.invokeMethod<bool>('requestNotificationPermission') ??
          false;
      _notificationsGranted = granted;
      notifyListeners();
      return granted;
    } on MissingPluginException {
      _notificationsGranted = kDebugMode;
      notifyListeners();
      return _notificationsGranted;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<RunPermissionState> refreshPermissions() async {
    await getCapabilities();
    return permissionState;
  }

  Future<bool> openAppSettings() async {
    if (!_isAndroid) return false;
    try {
      return await methods.invokeMethod<bool>('openAppSettings') ?? false;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Persists the logical session identity before the foreground tracker starts.
  Future<void> setSessionContext(RunSessionContext context) async {
    _sessionContext = context;
    _state = _state.copyWith(sessionContext: context);
    notifyListeners();
    if (!_isAndroid) return;
    try {
      await methods.invokeMethod<void>('setSessionContext', context.toMap());
    } on MissingPluginException {
      // Desktop/tests.
    } catch (error) {
      _setError('session_context_error', error.toString());
    }
  }

  /// Fetches one visible-activity GPS fix without starting the run timer.
  Future<RunGpsFix?> prepareLocation() async {
    if (kDebugMode && !_isAndroid) {
      const fix = RunGpsFix(lat: -23.5505, lng: -46.6333, accuracyMeters: 5);
      _state = _state.copyWith(
        locationGranted: true,
        lat: fix.lat,
        lng: fix.lng,
        accuracyMeters: fix.accuracyMeters,
        clearError: true,
      );
      notifyListeners();
      return fix;
    }
    if (!_isAndroid || !_state.locationGranted) return null;
    try {
      final result = await methods.invokeMapMethod<String, dynamic>(
        'getCurrentLocation',
      );
      if (result == null) return null;
      final lat = (result['lat'] as num?)?.toDouble();
      final lng = (result['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;
      final millis = (result['recorded_at_millis'] as num?)?.toInt();
      final fix = RunGpsFix(
        lat: lat,
        lng: lng,
        accuracyMeters: (result['accuracy_meters'] as num?)?.toDouble(),
        recordedAt: millis == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(millis),
      );
      _state = _state.copyWith(
        lat: lat,
        lng: lng,
        accuracyMeters: fix.accuracyMeters,
        clearError: true,
      );
      notifyListeners();
      return fix;
    } on PlatformException catch (error) {
      _setError(error.code, error.message ?? error.toString());
      return null;
    } catch (error) {
      _setError('gps_prepare_error', error.toString());
      return null;
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
    _nativeDebugSim = false;
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
      _setError('location_denied', 'Precise location permission is required');
      return false;
    }
    try {
      _trail.clear();
      final result = await methods.invokeMapMethod<String, dynamic>('start');
      if (result != null) {
        _applyNativeState(result);
      }
      final ready = await _awaitStatus({
        RunTrackingState.recording,
        RunTrackingState.paused,
      }, timeout: const Duration(seconds: 8));
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
      if (_nativeDebugSim && _isAndroid) {
        try {
          final result = await methods.invokeMapMethod<String, dynamic>(
            'pause',
          );
          if (result != null) _applyNativeState(result);
        } catch (_) {}
        return;
      }
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
      if (_nativeDebugSim && _isAndroid) {
        try {
          final result = await methods.invokeMapMethod<String, dynamic>(
            'resume',
          );
          if (result != null) _applyNativeState(result);
        } catch (_) {}
        return;
      }
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

  /// Stops tracking but keeps the completed spool outside SQLite until the
  /// athlete accepts the post-run review.
  Future<RunReviewDraft?> stopForReview({
    List<RunStepResult> stepResults = const [],
  }) async {
    if (_debugSim != null && !_nativeDebugSim) {
      final sim = _debugSim!;
      _stopDebugTimer();
      _debugSim = null;
      _debugPaused = false;
      final payload = sim.toSpoolPayload();
      final activity = Map<String, dynamic>.from(
        payload['activity'] as Map? ?? const {},
      );
      _writeContextToActivity(activity, _sessionContext);
      activity['status'] = 'pending_review';
      activity['splits'] = [
        for (final split in _state.splits)
          {
            'km': split.km,
            'distance_meters': split.distanceMeters,
            'duration_seconds': split.durationSeconds,
            'pace_sec_per_km': split.paceSecPerKm,
            'is_partial': split.isPartial,
          },
      ];
      activity['voice_step_results'] = _stepResultsJson(stepResults);
      payload['activity'] = activity;
      final typedPayload = Map<String, dynamic>.from(payload);
      final preview = await _repository.previewNativeSpoolUsingLatestWeight(
        typedPayload,
      );
      _memoryReviewSpools[preview.id] = typedPayload;
      _trail.clear();
      _sessionContext = null;
      _state = RunTrackingState.initial(
        supported: true,
      ).copyWith(locationGranted: true);
      notifyListeners();
      return RunReviewDraft.fromSpool(activity: preview, spool: typedPayload);
    }
    if (_nativeDebugSim) {
      _stopDebugTimer();
      _debugSim = null;
      _debugPaused = false;
      _nativeDebugSim = false;
      // Fall through to native stop path below.
    }

    if (!_isAndroid) return null;
    final activityId = _state.activityId;
    try {
      final result = await methods.invokeMapMethod<String, dynamic>('stop');
      if (result != null) _applyNativeState(result);
    } catch (error) {
      _setError('stop_error', error.toString());
    }

    await _awaitStatus({
      RunTrackingState.completed,
      RunTrackingState.idle,
      RunTrackingState.discarded,
    }, timeout: const Duration(seconds: 5));

    final resolvedId = activityId ?? _state.activityId;
    RunReviewDraft? draft;
    if (resolvedId != null) {
      try {
        final raw = await methods.invokeMapMethod<String, dynamic>(
          'markPendingReview',
          resolvedId,
        );
        if (raw != null) {
          final payload = Map<String, dynamic>.from(raw);
          final activity = Map<String, dynamic>.from(
            payload['activity'] as Map? ?? const {},
          );
          _writeContextToActivity(activity, _sessionContext);
          if (stepResults.isNotEmpty) {
            activity['voice_step_results'] = _stepResultsJson(stepResults);
          }
          payload['activity'] = activity;
          final preview = await _repository.previewNativeSpoolUsingLatestWeight(
            payload,
          );
          draft = RunReviewDraft.fromSpool(activity: preview, spool: payload);
        }
      } catch (error) {
        _setError('review_error', error.toString());
      }
    }

    _trail.clear();
    _sessionContext = null;
    _state = RunTrackingState.initial(
      supported: true,
    ).copyWith(locationGranted: _state.locationGranted);
    notifyListeners();
    return draft;
  }

  /// Backward-compatible immediate save for non-UI callers.
  Future<RunActivity?> stop() async {
    final draft = await stopForReview();
    if (draft == null) return null;
    return saveReviewedRun(draft: draft, completePlannedWorkout: true);
  }

  Future<List<RunReviewDraft>> listPendingReviews() async {
    final drafts = <RunReviewDraft>[];
    final seen = <String>{};
    for (final payload in _memoryReviewSpools.values) {
      final preview = await _repository.previewNativeSpoolUsingLatestWeight(
        payload,
      );
      drafts.add(RunReviewDraft.fromSpool(activity: preview, spool: payload));
      seen.add(preview.id);
    }
    if (!_isAndroid) return drafts;
    try {
      final pending =
          await methods.invokeListMethod<dynamic>('listPendingSpools') ??
          const [];
      for (final row in pending.whereType<Map>()) {
        final summary = Map<String, dynamic>.from(row);
        if (summary['status'] != 'pending_review') continue;
        final id = summary['id'] as String?;
        if (id == null || seen.contains(id)) continue;
        final raw = await methods.invokeMapMethod<String, dynamic>(
          'readSpool',
          id,
        );
        if (raw == null) continue;
        final payload = Map<String, dynamic>.from(raw);
        final preview = await _repository.previewNativeSpoolUsingLatestWeight(
          payload,
        );
        drafts.add(RunReviewDraft.fromSpool(activity: preview, spool: payload));
        seen.add(id);
      }
    } on MissingPluginException {
      // Tests and older desktop runners.
    } catch (error) {
      _setError('review_recovery_error', error.toString());
    }
    drafts.sort((a, b) => b.activity.startedAt.compareTo(a.activity.startedAt));
    return drafts;
  }

  Future<RunActivity?> saveReviewedRun({
    required RunReviewDraft draft,
    required bool completePlannedWorkout,
    String? title,
    String? notes,
    double? rpe,
    int? feelingRating,
    double? distanceMeters,
  }) async {
    try {
      final payload = Map<String, dynamic>.from(draft.spool);
      final activity = Map<String, dynamic>.from(
        payload['activity'] as Map? ?? const {},
      );
      activity['status'] = 'completed';
      activity['title'] = title?.trim().isEmpty == true ? null : title?.trim();
      activity['notes'] = notes?.trim().isEmpty == true ? null : notes?.trim();
      activity['rpe'] = rpe;
      activity['feeling_rating'] = feelingRating;
      if (distanceMeters != null) {
        activity['distance_meters'] = distanceMeters.clamp(0, 1000000);
        // Recalculate the estimate from the reviewed metrics.
        activity.remove('calories');
      }
      payload['activity'] = activity;

      final imported = await _repository.importNativeSpool(payload);
      await _repository.updateActivityMeta(
        id: imported.id,
        title: title?.trim(),
        notes: notes?.trim(),
        rpe: rpe,
        feelingRating: feelingRating,
      );
      final reconciled = await _reconcilePlanContext(
        imported.id,
        activity,
        completePlannedWorkout: completePlannedWorkout,
      );
      if (!reconciled) return null;
      _memoryReviewSpools.remove(imported.id);
      if (_isAndroid) {
        await methods.invokeMethod<dynamic>('deleteSpool', imported.id);
      }
      return await _repository.getActivity(imported.id) ?? imported;
    } catch (error) {
      _setError('review_save_error', error.toString());
      return null;
    }
  }

  Future<void> discardReview(RunReviewDraft draft) async {
    try {
      await _repository.deleteActivity(draft.id);
    } catch (_) {
      // The usual case is that the review was never imported.
    }
    _memoryReviewSpools.remove(draft.id);
    if (_isAndroid) {
      try {
        await methods.invokeMethod<dynamic>('deleteSpool', draft.id);
      } catch (error) {
        _setError('review_discard_error', error.toString());
      }
    }
  }

  static List<Map<String, dynamic>> _stepResultsJson(
    List<RunStepResult> results,
  ) => [
    for (final result in results)
      {
        'sequence': result.sequence,
        'role': result.role.value,
        'repIndex': result.repIndex,
        'plannedMetric': result.plannedMetric.name,
        'plannedValue': result.plannedValue,
        'plannedPaceSecPerKm': result.plannedPaceSecPerKm,
        'distanceMeters': result.distanceMeters,
        'durationSeconds': result.durationSeconds,
        'actualPaceSecPerKm': result.actualPaceSecPerKm,
      },
  ];

  Future<void> discard() async {
    if (_debugSim != null && !_nativeDebugSim) {
      _stopDebugTimer();
      _debugSim = null;
      _debugPaused = false;
      _trail.clear();
      _sessionContext = null;
      _state = RunTrackingState.initial(
        supported: true,
      ).copyWith(locationGranted: true);
      notifyListeners();
      return;
    }
    if (_nativeDebugSim) {
      _stopDebugTimer();
      _debugSim = null;
      _debugPaused = false;
      _nativeDebugSim = false;
      // Fall through to native discard path.
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
    _sessionContext = null;
    _state = RunTrackingState.initial(
      supported: true,
    ).copyWith(locationGranted: _state.locationGranted);
    notifyListeners();
  }

  Future<int> recoverPendingSessions() async {
    if (_isAndroid == false ||
        _recovering ||
        (_debugSim != null && !_nativeDebugSim)) {
      return _recoveredCount;
    }
    _recovering = true;
    var count = 0;
    try {
      final liveStatus = _state.status;
      final serviceAlive =
          liveStatus == RunTrackingState.recording ||
          liveStatus == RunTrackingState.paused ||
          liveStatus == RunTrackingState.starting ||
          liveStatus == RunTrackingState.stopping;
      final pending =
          await methods.invokeListMethod<dynamic>('listPendingSpools') ??
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
        if (status == 'pending_review') {
          // The athlete has not accepted this activity yet. The run hub owns
          // reopening it; recovery must never silently import it.
          continue;
        }
        if (!serviceAlive &&
            (status == 'recording' ||
                status == 'paused' ||
                status == 'starting' ||
                status == 'stopping')) {
          // Never convert a live-looking spool to completed merely because
          // Flutter won a race with the native service restart. The explicit
          // recoverActive call above owns that transition.
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
      final reconciled = await _reconcilePlanContext(imported.id, activityMap);
      // Keep the native envelope as a retry ledger when the activity itself
      // imported but the plan/schedule reconciliation failed.
      if (reconciled) {
        await methods.invokeMethod<dynamic>('deleteSpool', id);
      }
      return imported;
    } catch (error) {
      _setError('import_error', error.toString());
      return null;
    }
  }

  static void _writeContextToActivity(
    Map<String, dynamic> activity,
    RunSessionContext? context,
  ) {
    if (context == null) return;
    activity['plan_workout_id'] = context.planWorkoutId;
    activity['scheduled_run_id'] = context.scheduledRunId;
    activity['session_goal'] = context.toMap()['goal'];
    activity['session_intervals_on'] = context.intervalsOn;
  }

  /// Idempotently repairs the plan ledger after either a normal stop or spool
  /// recovery. Re-running it only replaces the same step rows and links.
  Future<bool> _reconcilePlanContext(
    String activityId,
    Map<String, dynamic> activity, {
    bool completePlannedWorkout = true,
  }) async {
    final planWorkoutId = activity['plan_workout_id'] as String?;
    if (planWorkoutId == null || planWorkoutId.isEmpty) return true;
    try {
      await _planRepository.setActivityPlanWorkout(
        activityId: activityId,
        planWorkoutId: planWorkoutId,
      );
      final rawResults = activity['voice_step_results'];
      if (rawResults is List && rawResults.isNotEmpty) {
        final steps = <RunActivityStep>[];
        for (final raw in rawResults.whereType<Map>()) {
          final row = Map<String, dynamic>.from(raw);
          steps.add(
            RunActivityStep(
              id: '',
              runActivityId: activityId,
              orderIndex: (row['sequence'] as num?)?.toInt() ?? steps.length,
              role: row['role'] as String? ?? 'work',
              repIndex: (row['repIndex'] as num?)?.toInt() ?? 1,
              plannedMetric: row['plannedMetric'] as String?,
              plannedValue: (row['plannedValue'] as num?)?.toInt(),
              plannedPaceSecPerKm: (row['plannedPaceSecPerKm'] as num?)
                  ?.toDouble(),
              actualDistanceMeters: (row['distanceMeters'] as num?)?.toDouble(),
              actualDurationSeconds: (row['durationSeconds'] as num?)?.toInt(),
              actualPaceSecPerKm: (row['actualPaceSecPerKm'] as num?)
                  ?.toDouble(),
            ),
          );
        }
        await _planRepository.saveActivitySteps(activityId, steps);
      }

      if (!completePlannedWorkout) return true;

      final scheduledRunId = activity['scheduled_run_id'] as String?;
      final scheduled = scheduledRunId == null
          ? null
          : await _planRepository.getScheduledRun(scheduledRunId);
      if (scheduled != null) {
        await _planRepository.attachActivity(
          scheduledRunId: scheduled.id,
          runActivityId: activityId,
        );
      } else {
        final startedAt = DateTime.tryParse(
          activity['started_at'] as String? ?? '',
        );
        await _planRepository.markPlanWorkoutCompleted(
          planWorkoutId: planWorkoutId,
          date: startedAt?.toLocal() ?? DateTime.now(),
          runActivityId: activityId,
        );
      }
      return true;
    } catch (error) {
      _setError('plan_reconcile_error', error.toString());
      return false;
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
    if (_debugSim != null && !_nativeDebugSim) return;
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
    if (_sessionContext != null) {
      _state = _state.copyWith(sessionContext: _sessionContext);
    }
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
