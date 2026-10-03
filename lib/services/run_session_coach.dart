import 'package:flutter/foundation.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/models/run_session_goal.dart';
import 'package:workout_notes/models/run_step_snapshot.dart';
import 'package:workout_notes/models/run_tracking_state.dart';
import 'package:workout_notes/models/run_voice_settings.dart';
import 'package:workout_notes/services/run_native_voice_service.dart';
import 'package:workout_notes/services/run_voice_settings_store.dart';

/// What the record screen needs to know about the voice session: the voice
/// settings, the session goal, the planned workout and the quick-interval
/// toggle.
///
/// Speaking is entirely native (`RunVoiceController` inside the tracking
/// foreground service). This class only hands it the session set-up over
/// [RunNativeVoiceService] and latches goal completion for the UI.
class RunSessionCoach extends ChangeNotifier {
  RunSessionCoach({
    RunVoiceSettingsStore? settingsStore,
    RunNativeVoiceService? voice,
  }) : _settingsStore = settingsStore ?? RunVoiceSettingsStore.instance,
       _voice = voice ?? RunNativeVoiceService.instance;

  final RunVoiceSettingsStore _settingsStore;
  final RunNativeVoiceService _voice;

  RunVoiceSettings _settings = const RunVoiceSettings.defaults();
  RunSessionGoal _goal = const RunSessionGoal.defaults();
  RunPlanWorkout? _planWorkout;
  bool _goalCompleted = false;
  bool _active = false;
  bool _intervalsOn = false;

  RunVoiceSettings get settings => _settings;
  bool get intervalsOn => _intervalsOn;
  RunSessionGoal get goal => _goal;
  bool get isActive => _active;

  /// The planned session being executed, if any.
  RunPlanWorkout? get planWorkout => _planWorkout;

  /// True while a structured plan session drives the cues.
  bool get hasPlan =>
      _planWorkout?.expandSteps().any((step) => step.step.value > 0) ?? false;

  RunGoalSnapshot goalSnapshotFor(RunTrackingState state) {
    return RunGoalSnapshot(
      goal: _goal,
      completed: _goalCompleted,
      progress: _goal.progressFor(
        distanceMeters: state.distanceMeters,
        movingTimeSeconds: state.movingTimeSeconds,
      ),
      remaining: _goal.remaining(
        distanceMeters: state.distanceMeters,
        movingTimeSeconds: state.movingTimeSeconds,
      ),
    );
  }

  Future<void> prepare() async {
    _settings = await _settingsStore.load();
    _intervalsOn = _settings.intervalsEnabledByDefault;
    notifyListeners();
  }

  Future<void> reloadSettings() async {
    _settingsStore.invalidateCache();
    _settings = await _settingsStore.load();
    if (_active) {
      await _voice.syncSettings(
        settings: _settings,
        goal: _goal.toMap(),
        intervalsOn: _intervalsOn,
        plan: _planWorkout?.stepsJson(),
        workout: _planWorkout?.voiceProfile(),
      );
    }
    notifyListeners();
  }

  void setIntervalsOn(bool value) {
    if (_intervalsOn == value) return;
    _intervalsOn = value;
    notifyListeners();
  }

  /// Loads (or clears) the structured session to execute. A plan overrides the
  /// quick interval preset — the two never run at the same time.
  void setPlanWorkout(RunPlanWorkout? workout) {
    _planWorkout = workout;
    notifyListeners();
  }

  void setGoal(RunSessionGoal goal) {
    _goal = goal;
    if (!goal.enabled) {
      _goalCompleted = false;
    }
    notifyListeners();
  }

  /// Hands the session set-up to the native voice controller. Pass
  /// `nativeVoice: false` for a session that has no native tracker (the debug
  /// simulator) or whose coach is started elsewhere (the treadmill, see
  /// [indoorVoiceSetup]).
  Future<void> beginSession({
    required bool intervalsOn,
    RunSessionGoal? goal,
    RunPlanWorkout? planWorkout,
    bool nativeVoice = true,
  }) async {
    await prepare();
    _active = true;
    if (planWorkout != null) setPlanWorkout(planWorkout);
    _intervalsOn = hasPlan ? false : intervalsOn;
    _goal = goal ?? _goal;
    _goalCompleted = false;
    if (nativeVoice) {
      await _voice.beginSession(
        settings: _settings,
        goal: _goal.toMap(),
        intervalsOn: _intervalsOn,
        plan: _planWorkout?.stepsJson(),
        workout: _planWorkout?.voiceProfile(),
      );
    }
    notifyListeners();
  }

  /// What the treadmill coach needs: the same set-up, with the plan's
  /// distance steps turned into time (there is no distance indoors).
  RunIndoorVoiceSetup indoorVoiceSetup() => RunIndoorVoiceSetup(
    settings: _settings,
    goal: _goal.toMap(),
    plan: _planWorkout?.treadmillStepsJson() ?? const [],
    workout: _planWorkout?.voiceProfile(),
  );

  /// Reattaches Flutter UI to a session already owned by the native service.
  /// Unlike [beginSession], this never sends `begin` over the platform channel,
  /// because doing so would reset the native structured-workout engine.
  Future<void> attachToActiveSession({
    required bool intervalsOn,
    required RunSessionGoal goal,
    RunPlanWorkout? planWorkout,
  }) async {
    await prepare();
    _active = true;
    if (planWorkout != null) setPlanWorkout(planWorkout);
    _intervalsOn = hasPlan ? false : intervalsOn;
    _goal = goal;
    _goalCompleted = false;
    notifyListeners();
  }

  Future<void> endSession() async {
    _active = false;
    _goalCompleted = false;
    await _voice.endSession();
    notifyListeners();
  }

  /// A deliberately minimal acknowledgement after the tracker has stopped.
  /// Planned sessions already announce their final step and do not repeat it.
  Future<void> announceManualCompletion() async {
    if (!_settings.enabled || hasPlan) return;
    await _voice.speakWorkoutComplete(_settings);
  }

  /// Latches goal completion so the goal card can show it.
  void onTrackingUpdate(RunTrackingState state) {
    if (!_active || _goalCompleted || !_goal.enabled) return;
    if (!state.isClockRunning && !state.isPaused) return;
    final done = _goal.isComplete(
      distanceMeters: state.distanceMeters,
      movingTimeSeconds: state.movingTimeSeconds,
    );
    if (!done) return;
    _goalCompleted = true;
    notifyListeners();
  }

  /// "Skip step": jumps the structured session (or the quick interval set) to
  /// its next step; the native controller announces it.
  Future<void> skipStep() async {
    if (!_active) return;
    await _voice.skipStep();
    notifyListeners();
  }

  /// Per-step outcome of the session that just ended, measured natively (the
  /// foreground service keeps measuring while the Flutter engine is dead).
  Future<List<RunStepResult>> collectStepResults() => _voice.stepResults();
}
