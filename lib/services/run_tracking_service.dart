import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/dev_tools/run_debug_backend.dart';
import 'package:workout_notes/models/cardio_activity_type.dart';
import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/models/run_lap.dart';
import 'package:workout_notes/models/run_permission_state.dart';
import 'package:workout_notes/models/run_review_draft.dart';
import 'package:workout_notes/models/run_session_context.dart';
import 'package:workout_notes/models/run_step_snapshot.dart';
import 'package:workout_notes/models/run_tracking_state.dart';
import 'package:workout_notes/models/scheduled_run.dart';
import 'package:workout_notes/repositories/run_plan_repository.dart';
import 'package:workout_notes/repositories/run_repository.dart';
import 'package:workout_notes/services/run_native_tracking_backend.dart';
import 'package:workout_notes/services/run_tracking_backend.dart';
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

/// Flutter facade for the run tracker.
///
/// The tracker itself is a [RunTrackingBackend]: the Android foreground GPS
/// service in production ([NativeRunTrackingBackend]), or in [kDebugMode] a
/// simulated GPS path ([RunDebugBackend], see [startDebugSimulation]) so the
/// emulator can exercise distance, pace, splits, and save without real motion.
///
/// The EventChannel is a live UI signal. Durable activities are imported from
/// the native spool through the MethodChannel after stop / app relaunch.
class RunTrackingService extends ChangeNotifier {
  static final RunTrackingService _instance = RunTrackingService._();
  static RunTrackingService get instance => _instance;

  RunTrackingService._() {
    _native = _own(NativeRunTrackingBackend.new);
    _backend = _native;
  }

  static const methods = NativeRunTrackingBackend.methods;

  final RunRepository _repository = DatabaseHelper.instance.runRepo;
  final RunPlanRepository _planRepository = DatabaseHelper.instance.runPlanRepo;
  RunTrackingState _state = RunTrackingState.initial(
    supported: defaultTargetPlatform == TargetPlatform.android,
  );
  late final NativeRunTrackingBackend _native;
  late RunTrackingBackend _backend;
  Future<void>? _initFuture;
  bool _routeMaintenanceStarted = false;
  bool _recovering = false;
  int _recoveredCount = 0;
  final Map<String, Map<String, dynamic>> _memoryReviewSpools = {};

  bool _notificationsGranted = false;
  bool _notificationsPermissionRequired = false;
  RunSessionContext? _sessionContext;

  RunTrackingState get state => _state;
  bool get isSupported => _state.supported;
  bool get isActive => _state.isActive;
  int get recoveredCount => _recoveredCount;
  bool get isDebugSimulating => _backend.isSimulated;
  bool get canDebugSimulate => kDebugMode;
  bool get notificationsGranted => _notificationsGranted;
  bool get notificationsPermissionRequired => _notificationsPermissionRequired;
  RunPermissionState get permissionState => RunPermissionState(
    locationGranted: _state.locationGranted,
    notificationsGranted: _notificationsGranted,
    notificationsPermissionRequired: _notificationsPermissionRequired,
  );

  bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

  /// Subscribes to the native events, reads capabilities/state and recovers
  /// what a killed process left behind. Concurrent and later callers share the
  /// same run (home, run screens and startup all call this); a failed run can
  /// be retried by calling it again. Use [refresh] for a light re-read.
  Future<void> initialize() {
    final running = _initFuture;
    if (running != null) return running;
    final future = _initialize();
    _initFuture = future;
    future.catchError((Object _) {
      if (identical(_initFuture, future)) _initFuture = null;
    });
    return future;
  }

  Future<void> _initialize() async {
    if (!_isAndroid) {
      if (kDebugMode) {
        _state = _state.copyWith(supported: true, locationGranted: true);
      }
      _notificationsGranted = true;
      notifyListeners();
      _scheduleRouteMaintenance();
      return;
    }
    _native.listen();
    await refresh();
    await _native.recoverActive();
    _sessionContext = _state.sessionContext;
    await recoverPendingSessions();
    _scheduleRouteMaintenance();
  }

  /// Forgets the shared initialisation so the next [initialize] runs again
  /// (tests share the singleton across cases).
  @visibleForTesting
  void resetInitializationForTest() {
    _initFuture = null;
    _routeMaintenanceStarted = false;
  }

  /// Light re-read of the native capabilities and state (no recovery).
  Future<void> refresh() async {
    await getCapabilities();
    await getState();
  }

  /// Route storage maintenance runs at most once per process, in the
  /// background, and never while a run is being recorded.
  void _scheduleRouteMaintenance() {
    if (_routeMaintenanceStarted || _state.isActive) return;
    _routeMaintenanceStarted = true;
    unawaited(_maintainRouteStorage());
  }

  Future<void> _maintainRouteStorage() async {
    try {
      await _repository.runRouteMaintenance();
    } catch (_) {
      // Storage maintenance is opportunistic and must never block tracking.
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

  Future<RunTrackingState> getState() => _native.refresh();

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
    _backend.dispose();
    _backend = _own(
      (sink) => RunDebugBackend(sink, startLat: startLat, startLng: startLng),
    );
    return _backend.start();
  }

  Future<bool> start() async {
    if (_backend.isSimulated) return true;
    if (!_isAndroid) {
      if (kDebugMode) return startDebugSimulation();
      return false;
    }
    return _backend.start();
  }

  Future<void> pause() => _backend.pause();

  /// Marks a manual lap. Returns the lap just closed, or null when it was
  /// ignored (accidental double tap, nothing recording).
  Future<RunLap?> lap() => _backend.lap();

  Future<void> resume() => _backend.resume();

  /// Stops tracking but keeps the completed spool outside SQLite until the
  /// athlete accepts the post-run review.
  Future<RunReviewDraft?> stopForReview({
    List<RunStepResult> stepResults = const [],
  }) async {
    final backend = _backend;
    final payload = await backend.stopForReview();
    RunReviewDraft? draft;
    if (payload != null) {
      try {
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
        // A simulated run has no native spool to reopen the review from.
        if (backend.isSimulated) _memoryReviewSpools[preview.id] = payload;
        draft = RunReviewDraft.fromSpool(activity: preview, spool: payload);
      } catch (error) {
        _setError('review_error', error.toString());
      }
    }
    _resetAfterRun();
    return draft;
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
        // Treadmill: the pace only exists once the console distance is typed.
        if (CardioActivityType.fromDatabase(activity['activity_type']) ==
            CardioActivityType.treadmill) {
          activity.remove('avg_pace_sec_per_km');
        }
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
  ) => [for (final result in results) result.toMap()];

  Future<void> discard() async {
    await _backend.discard();
    _resetAfterRun();
  }

  /// Back to an idle state (and the native backend) once a run ended.
  void _resetAfterRun() {
    if (_backend.isSimulated) {
      _backend.dispose();
      _backend = _native;
    }
    _sessionContext = null;
    _state = const RunTrackingState.initial(
      supported: true,
    ).copyWith(locationGranted: _state.locationGranted);
    notifyListeners();
  }

  Future<int> recoverPendingSessions() async {
    if (_isAndroid == false || _recovering || _backend.isSimulated) {
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
      final status = activityMap['status'] as String? ?? 'completed';
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
            .map(Map<String, dynamic>.from)
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

  /// Builds a backend wired to this service through its own [_BackendSink].
  T _own<T extends RunTrackingBackend>(T Function(RunTrackingSink) create) {
    final sink = _BackendSink(this);
    final backend = create(sink);
    sink._owner = backend;
    return backend;
  }

  void _publish(RunTrackingState state) {
    _state = state;
    notifyListeners();
  }

  void _setError(String code, String message) {
    _state = _state.copyWith(errorCode: code, errorMessage: message);
    notifyListeners();
  }

  @override
  void dispose() {
    _backend.dispose();
    _native.dispose();
    super.dispose();
  }
}

/// Lets a backend publish into the service, but only while it is the active
/// one — a late native event must not overwrite a simulated run's state.
class _BackendSink implements RunTrackingSink {
  _BackendSink(this._service);

  final RunTrackingService _service;
  late final RunTrackingBackend _owner;

  @override
  RunTrackingState get state => _service._state;

  @override
  RunSessionContext? get sessionContext => _service._sessionContext;

  @override
  void publish(RunTrackingState state) {
    if (!identical(_service._backend, _owner)) return;
    _service._publish(state);
  }

  @override
  void reportError(String code, String message) {
    if (!identical(_service._backend, _owner)) return;
    _service._setError(code, message);
  }
}
