import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:workout_notes/models/cardio_activity_type.dart';
import 'package:workout_notes/models/run_review_draft.dart';
import 'package:workout_notes/models/run_session_context.dart';
import 'package:workout_notes/models/run_tracking_state.dart';
import 'package:workout_notes/repositories/run_repository.dart';

/// In-app timer for indoor sessions: stationary bike and treadmill.
///
/// Unlike outdoor running, this tracker deliberately has no location or native
/// GPS dependency. Elapsed values are derived from timestamps so they remain
/// correct when Flutter pauses periodic timers while the app is backgrounded.
/// The distance is typed on the review screen. (The class keeps its original
/// name; see [IndoorTrackingService].)
class StationaryBikeTrackingService extends ChangeNotifier {
  static final StationaryBikeTrackingService instance =
      StationaryBikeTrackingService._();

  static const _uuid = Uuid();

  StationaryBikeTrackingService._();

  final RunRepository _repository = RunRepository();
  RunTrackingState _state = const RunTrackingState.initial(supported: true);
  CardioActivityType _activityType = CardioActivityType.stationaryBike;

  /// Planned session the runner attached (treadmill runs may complete one).
  RunSessionContext? _sessionContext;
  Timer? _ticker;
  DateTime? _resumedAt;
  int _accumulatedMovingSeconds = 0;

  RunTrackingState get state => _state;

  bool get isActive => _state.isActive;

  /// The indoor activity being timed (or last started).
  CardioActivityType get activityType => _activityType;

  /// Starts timing. [context] links a planned workout: a treadmill run then
  /// completes that plan session when the review is saved, like an outdoor run.
  Future<bool> start({
    CardioActivityType type = CardioActivityType.stationaryBike,
    RunSessionContext? context,
  }) async {
    assert(type.isIndoor, 'Only indoor activities use the timer service');
    if (_state.isActive) return true;
    _activityType = type.isIndoor ? type : CardioActivityType.stationaryBike;
    _sessionContext = _activityType == CardioActivityType.treadmill
        ? context
        : null;
    final now = DateTime.now();
    _accumulatedMovingSeconds = 0;
    _resumedAt = now;
    _state = RunTrackingState(
      supported: true,
      locationGranted: false,
      status: RunTrackingState.recording,
      activityId: _uuid.v4(),
      startedAt: now,
      updatedAt: now,
      distanceMeters: 0,
      durationSeconds: 0,
      movingTimeSeconds: 0,
      currentPaceSecPerKm: null,
      lat: null,
      lng: null,
      accuracyMeters: null,
      trail: const [],
      splits: const [],
      currentSplit: null,
      errorCode: null,
      errorMessage: null,
    );
    _startTicker();
    notifyListeners();
    return true;
  }

  Future<void> pause() async {
    if (!_state.isRecording) return;
    _updateClock();
    _accumulatedMovingSeconds = _state.movingTimeSeconds;
    _resumedAt = null;
    _state = _state.copyWith(
      status: RunTrackingState.paused,
      updatedAt: DateTime.now(),
    );
    notifyListeners();
  }

  Future<void> resume() async {
    if (!_state.isPaused) return;
    _resumedAt = DateTime.now();
    _state = _state.copyWith(
      status: RunTrackingState.recording,
      updatedAt: _resumedAt,
    );
    _startTicker();
    notifyListeners();
  }

  Future<RunReviewDraft?> stopForReview() async {
    if (!_state.isActive) return null;
    _updateClock();
    final snapshot = _state;
    final endedAt = DateTime.now();
    final activityId = snapshot.activityId ?? _uuid.v4();
    _stopTicker();

    final payload = <String, dynamic>{
      'schema_version': 1,
      'activity': <String, dynamic>{
        'id': activityId,
        'activity_type': _activityType.databaseValue,
        'started_at': (snapshot.startedAt ?? endedAt).toIso8601String(),
        'ended_at': endedAt.toIso8601String(),
        'duration_seconds': snapshot.durationSeconds,
        'moving_time_seconds': snapshot.movingTimeSeconds,
        'distance_meters': 0.0,
        'status': 'pending_review',
        if (_sessionContext?.planWorkoutId != null)
          'plan_workout_id': _sessionContext!.planWorkoutId,
        if (_sessionContext?.scheduledRunId != null)
          'scheduled_run_id': _sessionContext!.scheduledRunId,
      },
      'points': <Map<String, dynamic>>[],
    };
    final activity = await _repository.previewNativeSpoolUsingLatestWeight(
      payload,
    );
    _reset();
    return RunReviewDraft.fromSpool(activity: activity, spool: payload);
  }

  Future<void> discard() async {
    _stopTicker();
    _reset();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_state.isActive) return;
      _updateClock();
      notifyListeners();
    });
  }

  void _updateClock() {
    final startedAt = _state.startedAt;
    if (startedAt == null) return;
    final now = DateTime.now();
    final resumedAt = _resumedAt;
    final movingSeconds =
        _accumulatedMovingSeconds +
        (resumedAt == null ? 0 : now.difference(resumedAt).inSeconds);
    _state = _state.copyWith(
      durationSeconds: now.difference(startedAt).inSeconds.clamp(0, 864000),
      movingTimeSeconds: movingSeconds.clamp(0, 864000),
      updatedAt: now,
    );
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _reset() {
    _sessionContext = null;
    _accumulatedMovingSeconds = 0;
    _resumedAt = null;
    _state = const RunTrackingState.initial(supported: true);
    notifyListeners();
  }

  @override
  void dispose() {
    _stopTicker();
    super.dispose();
  }
}

/// The tracker handles every indoor (no-GPS) activity, not just the bike.
typedef IndoorTrackingService = StationaryBikeTrackingService;
