import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/models/cardio_activity_type.dart';
import 'package:workout_notes/models/run_review_draft.dart';
import 'package:workout_notes/models/run_session_context.dart';
import 'package:workout_notes/models/run_step_snapshot.dart';
import 'package:workout_notes/models/run_tracking_state.dart';
import 'package:workout_notes/repositories/run_repository.dart';
import 'package:workout_notes/services/run_native_voice_service.dart';

/// In-app timer for indoor sessions: stationary bike and treadmill.
///
/// Unlike outdoor running, this tracker deliberately has no location or native
/// GPS dependency. Elapsed values are derived from timestamps so they remain
/// correct when Flutter pauses periodic timers while the app is backgrounded.
/// The distance is typed on the review screen.
///
/// It serves every indoor activity (`CardioActivityType.isIndoor`). A
/// treadmill run also gets the native voice coach (`RunIndoorVoiceService`),
/// which keeps talking with the screen off and reports the step snapshot the
/// record screen shows.
class IndoorTrackingService extends ChangeNotifier {
  static final IndoorTrackingService instance = IndoorTrackingService._();

  static const _uuid = Uuid();

  IndoorTrackingService._();

  final RunRepository _repository = DatabaseHelper.instance.runRepo;
  final RunNativeVoiceService _voice = RunNativeVoiceService.instance;

  /// The native treadmill coach is running for this session.
  bool _voiceActive = false;
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
  /// [voice] starts the treadmill voice coach (ignored for the bike).
  Future<bool> start({
    CardioActivityType type = CardioActivityType.stationaryBike,
    RunSessionContext? context,
    RunIndoorVoiceSetup? voice,
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
    if (voice != null &&
        voice.settings.enabled &&
        _activityType == CardioActivityType.treadmill) {
      _voiceActive = await _voice.indoorStart(
        settings: voice.settings,
        goal: voice.goal,
        plan: voice.plan,
        workout: voice.workout,
      );
    }
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
    if (_voiceActive) await _voice.indoorPause();
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
    if (_voiceActive) await _voice.indoorResume();
  }

  Future<RunReviewDraft?> stopForReview() async {
    if (!_state.isActive) return null;
    _updateClock();
    final snapshot = _state;
    final endedAt = DateTime.now();
    final activityId = snapshot.activityId ?? _uuid.v4();
    _stopTicker();
    final stepResults = _voiceActive
        ? await _voice.indoorStop()
        : const <RunStepResult>[];
    _voiceActive = false;

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
        if (stepResults.isNotEmpty)
          'voice_step_results': [
            for (final result in stepResults) result.toMap(),
          ],
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
    if (_voiceActive) await _voice.indoorStop();
    _voiceActive = false;
    _reset();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_state.isActive) return;
      _updateClock();
      notifyListeners();
      if (_voiceActive) unawaited(_refreshVoiceState());
    });
  }

  /// Mirrors the native coach's step progress into the state for the UI.
  Future<void> _refreshVoiceState() async {
    final voiceState = await _voice.indoorState();
    if (voiceState == null || !_voiceActive || !_state.isActive) return;
    _state = _state.copyWith(
      stepSnapshot: voiceState.stepSnapshot,
      intervalSnapshot: voiceState.intervalSnapshot,
    );
    notifyListeners();
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
