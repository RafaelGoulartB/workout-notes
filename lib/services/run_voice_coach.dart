import 'package:flutter/foundation.dart';
import 'package:workout_notes/models/run_session_goal.dart';
import 'package:workout_notes/models/run_tracking_state.dart';
import 'package:workout_notes/models/run_voice_settings.dart';
import 'package:workout_notes/services/run_audio_gate_service.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/models/run_workout_step.dart';
import 'package:workout_notes/services/run_interval_engine.dart';
import 'package:workout_notes/services/run_workout_step_engine.dart';
import 'package:workout_notes/services/run_native_voice_service.dart';
import 'package:workout_notes/services/run_tracking_service.dart';
import 'package:workout_notes/services/run_tts_service.dart';
import 'package:workout_notes/services/run_voice_phrases.dart';
import 'package:workout_notes/services/run_voice_cue_arbiter.dart';
import 'package:workout_notes/services/run_voice_settings_store.dart';

typedef RunVoiceSpeakFn = Future<void> Function(String text);
typedef RunVoiceCapsFn = Future<RunAudioCapabilities> Function();

/// Listens to run tracking snapshots and speaks configured English cues.
class RunVoiceCoach extends ChangeNotifier {
  RunVoiceCoach({
    RunVoiceSettingsStore? settingsStore,
    RunIntervalEngine? intervalEngine,
    RunWorkoutStepEngine? stepEngine,
    RunVoiceSpeakFn? speak,
    RunVoiceCapsFn? audioCaps,
    Future<void> Function()? ensureTtsReady,
    Future<void> Function()? stopTts,
    bool? useNativeVoice,
  }) : _settingsStore = settingsStore ?? RunVoiceSettingsStore.instance,
       _intervalEngine = intervalEngine ?? RunIntervalEngine(),
       _stepEngine = stepEngine ?? RunWorkoutStepEngine(),
       _speak = speak ?? ((text) => RunTtsService.instance.speak(text)),
       _audioCaps =
           audioCaps ?? (() => RunAudioGateService.instance.getCapabilities()),
       _ensureTtsReady =
           ensureTtsReady ?? (() => RunTtsService.instance.ensureReady()),
       _stopTts = stopTts ?? (() => RunTtsService.instance.stop()),
       _useNativeVoiceOverride = useNativeVoice,
       _isCustomSpeak =
           speak != null || ensureTtsReady != null || stopTts != null;

  final RunVoiceSettingsStore _settingsStore;
  final RunIntervalEngine _intervalEngine;

  /// Structured plan session. When loaded it takes over from [_intervalEngine].
  final RunWorkoutStepEngine _stepEngine;
  final RunVoiceSpeakFn _speak;
  final RunVoiceCapsFn _audioCaps;
  final Future<void> Function() _ensureTtsReady;
  final Future<void> Function() _stopTts;
  final bool? _useNativeVoiceOverride;
  final bool _isCustomSpeak;
  final RunVoiceCueArbiter _arbiter = RunVoiceCueArbiter();

  RunVoiceSettings _settings = const RunVoiceSettings.defaults();
  RunSessionGoal _goal = const RunSessionGoal.defaults();
  RunPlanWorkout? _planWorkout;
  bool _goalCompleted = false;
  bool _active = false;
  bool _intervalsOn = false;
  bool _bypassHeadphonesGate = false;
  int _lastAnnouncedKm = 0;
  int _lastSplitCount = 0;
  bool? _lastWeakGps;
  DateTime? _lastGpsAnnounceAt;
  DateTime? _lastPaceAnnounceAt;
  bool _busy = false;
  final Set<int> _goalProgressCues = {};
  final List<({DateTime at, double distance, int movingSeconds})> _paceSamples =
      [];
  DateTime? _paceDeviationSince;
  int _paceDeviationDirection = 0;
  bool _paceCorrectionSpoken = false;
  bool? _wasPaused;

  /// When set (tests), [prepare]/[reloadSettings] skip the DB store.
  RunVoiceSettings? settingsOverride;

  RunVoiceSettings get settings => _settings;
  bool get intervalsOn => _intervalsOn;
  RunSessionGoal get goal => _goal;
  RunIntervalSnapshot get intervalSnapshot => _intervalEngine.snapshot;

  /// The planned session being executed, if any.
  RunPlanWorkout? get planWorkout => _planWorkout;

  RunStepSnapshot get stepSnapshot => _stepEngine.snapshot;

  /// True while a structured plan session drives the cues.
  bool get hasPlan => _planWorkout != null && _stepEngine.totalSteps > 0;

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

  bool get isActive => _active;
  bool get bypassHeadphonesGate => _bypassHeadphonesGate;

  bool get _useNativeVoice {
    if (_useNativeVoiceOverride != null) return _useNativeVoiceOverride;
    if (_isCustomSpeak) {
      return false; // Tests inject fake TTS -> stay on Dart path
    }
    if (RunTrackingService.instance.isDebugSimulating) return false;
    if (_bypassHeadphonesGate) {
      return false; // Debug sim uses Dart TTS (emulator, no headset)
    }
    return !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  }

  void setBypassHeadphonesGate(bool value) {
    _bypassHeadphonesGate = value;
  }

  Future<void> prepare() async {
    _settings = settingsOverride ?? await _settingsStore.load();
    _intervalEngine.configure(_settings.interval);
    _intervalsOn = _settings.intervalsEnabledByDefault;
    notifyListeners();
  }

  Future<void> reloadSettings() async {
    if (settingsOverride != null) {
      _settings = settingsOverride!;
    } else {
      _settingsStore.invalidateCache();
      _settings = await _settingsStore.load();
    }
    _intervalEngine.configure(_settings.interval);
    if (_active && _useNativeVoice) {
      await RunNativeVoiceService.instance.syncSettings(
        settings: _settings.toJson(),
        goal: {
          'enabled': _goal.enabled,
          'metric': _goal.metric.name,
          'value': _goal.value,
        },
        intervalsOn: _intervalsOn,
        bypassHeadphonesGate: _bypassHeadphonesGate,
        plan: _planWorkout?.stepsJson(),
      );
    }
    notifyListeners();
  }

  void setIntervalsOn(bool value) {
    if (_intervalsOn == value) return;
    _intervalsOn = value;
    if (!value) {
      _intervalEngine.reset();
    }
    notifyListeners();
  }

  /// Loads (or clears) the structured session to execute. A plan overrides the
  /// quick interval preset — the two never run at the same time.
  void setPlanWorkout(RunPlanWorkout? workout) {
    _planWorkout = workout;
    if (workout == null) {
      _stepEngine.configureSteps(const []);
    } else {
      _stepEngine.configure(workout);
      _intervalEngine.reset();
    }
    notifyListeners();
  }

  void setGoal(RunSessionGoal goal) {
    _goal = goal;
    if (!goal.enabled) {
      _goalCompleted = false;
    }
    notifyListeners();
  }

  Future<void> beginSession({
    required bool intervalsOn,
    RunSessionGoal? goal,
    RunPlanWorkout? planWorkout,
    bool bypassHeadphonesGate = false,
  }) async {
    await prepare();
    _active = true;
    if (planWorkout != null) setPlanWorkout(planWorkout);
    _intervalsOn = hasPlan ? false : intervalsOn;
    _goal = goal ?? _goal;
    _goalCompleted = false;
    _bypassHeadphonesGate = bypassHeadphonesGate;
    _lastAnnouncedKm = 0;
    _lastSplitCount = 0;
    _lastWeakGps = null;
    _lastGpsAnnounceAt = null;
    _lastPaceAnnounceAt = null;
    _goalProgressCues.clear();
    _paceSamples.clear();
    _paceDeviationSince = null;
    _paceDeviationDirection = 0;
    _paceCorrectionSpoken = false;
    _wasPaused = null;
    _arbiter.reset();
    _intervalEngine.reset();
    _intervalEngine.configure(_settings.interval);
    _stepEngine.reset();
    if (_useNativeVoice) {
      await RunNativeVoiceService.instance.beginSession(
        settings: _settings.toJson(),
        goal: {
          'enabled': _goal.enabled,
          'metric': _goal.metric.name,
          'value': _goal.value,
        },
        intervalsOn: _intervalsOn,
        bypassHeadphonesGate: _bypassHeadphonesGate,
        plan: _planWorkout?.stepsJson(),
      );
      // Still ensure TTS for test fallback or when service not yet ready,
      // but live announcements will be driven by native controller.
    } else {
      await _ensureTtsReady();
    }
    notifyListeners();
  }

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
    _intervalEngine.reset();
    // Keep the results — collectStepResults() reads them after stop().
    _stepEngine.finish();
    if (_useNativeVoice) {
      await RunNativeVoiceService.instance.endSession();
    }
    await _stopTts();
    notifyListeners();
  }

  /// A deliberately minimal acknowledgement after the tracker has stopped.
  /// Planned sessions already announce their final step and do not repeat it.
  Future<void> announceManualCompletion() async {
    if (!_settings.enabled || hasPlan) return;
    await _ensureTtsReady();
    await _speakIfAllowed(RunVoicePhrases.workoutComplete());
  }

  Future<void> onTrackingUpdate(RunTrackingState state) async {
    if (!_active) return;
    if (_busy) return;
    _busy = true;
    try {
      final cues = <RunVoiceCue>[];

      final statusCue = _statusCue(state);
      if (statusCue != null) cues.add(statusCue);

      // Goal completion always wins over other cues in the same tick.
      final goalJustCompleted = _checkGoalCompletion(state);
      if (goalJustCompleted) {
        cues.add(
          RunVoiceCue(
            text: RunVoicePhrases.goalComplete(
              metric: _goal.metric,
              value: _goal.value,
            ),
            priority: RunVoiceCuePriority.achievement,
            key: 'goal-complete',
          ),
        );
        // Keep the structured/preset counters in sync without speaking them.
        if (hasPlan) {
          _advanceStepEngine(state, speak: false);
        } else if (_intervalsOn) {
          if (_intervalEngine.snapshot.phase == RunIntervalPhase.idle &&
              state.isRecording) {
            _intervalEngine.start();
          }
          _intervalEngine.tick(
            recording: state.isRecording,
            distanceMeters: state.distanceMeters,
            movingTimeSeconds: state.movingTimeSeconds,
          );
        }
        _collectFreeRunCues(state);
      } else if (hasPlan) {
        // A planned session replaces the quick interval preset.
        cues.addAll(_advanceStepEngine(state, speak: true));
        if (state.isRecording || state.isPaused) {
          cues.addAll(_collectFreeRunCues(state));
        }
      } else {
        if (_intervalsOn &&
            _settings.announceIntervals &&
            state.isRecording &&
            _intervalEngine.snapshot.phase == RunIntervalPhase.idle) {
          final startEvents = _intervalEngine.start();
          for (final event in startEvents) {
            final cue = _cueForInterval(event);
            if (cue != null) cues.add(cue);
          }
        }

        if (_intervalsOn && _settings.announceIntervals) {
          final intervalEvents = _intervalEngine.tick(
            recording: state.isRecording,
            distanceMeters: state.distanceMeters,
            movingTimeSeconds: state.movingTimeSeconds,
          );
          for (final event in intervalEvents) {
            final cue = _cueForInterval(event);
            if (cue != null) cues.add(cue);
          }
        }

        if (state.isRecording || state.isPaused) {
          cues.addAll(_collectFreeRunCues(state));
        }
      }

      notifyListeners();

      // On Android, the foreground service speaks natively so cues survive
      // screen-off / Flutter engine death. Skip Dart TTS there to avoid
      // double announcements; native controller is fed from RunTrackingService ticks.
      if (_useNativeVoice) return;

      final cue = _arbiter.choose(cues);
      if (cue != null) await _speakIfAllowed(cue.text);
    } finally {
      _busy = false;
    }
  }

  bool _checkGoalCompletion(RunTrackingState state) {
    if (_goalCompleted || !_goal.enabled) return false;
    if (!state.isRecording && !state.isPaused) return false;
    final done = _goal.isComplete(
      distanceMeters: state.distanceMeters,
      movingTimeSeconds: state.movingTimeSeconds,
    );
    if (!done) return false;
    _goalCompleted = true;
    return true;
  }

  List<RunVoiceCue> _collectFreeRunCues(RunTrackingState state) {
    final out = <RunVoiceCue>[];
    final avgPace = state.distanceMeters > 0
        ? state.movingTimeSeconds / (state.distanceMeters / 1000.0)
        : null;
    final every = _settings.distanceEveryKm.clamp(1, 5);
    final milestone = ((state.distanceMeters / 1000).floor() ~/ every) * every;
    final hasNewMilestone =
        _settings.announceDistance &&
        milestone > 0 &&
        milestone > _lastAnnouncedKm;
    final hasNewSplit =
        _settings.announceSplit && state.splits.length > _lastSplitCount;

    // A kilometer boundary creates one compact report, never separate distance
    // and split announcements.
    if (hasNewSplit) {
      final split = state.splits.last;
      _lastSplitCount = state.splits.length;
      if (hasNewMilestone) _lastAnnouncedKm = milestone;
      out.add(
        RunVoiceCue(
          text: hasNewMilestone
              ? RunVoicePhrases.splitSummary(
                  km: split.km,
                  splitPaceSecPerKm: split.paceSecPerKm,
                  avgPaceSecPerKm: avgPace,
                )
              : RunVoicePhrases.splitComplete(
                  km: split.km,
                  paceSecPerKm: split.paceSecPerKm,
                ),
          priority: RunVoiceCuePriority.progress,
          key: 'split-${split.km}',
        ),
      );
    } else if (hasNewMilestone) {
      _lastAnnouncedKm = milestone;
      out.add(
        RunVoiceCue(
          text: RunVoicePhrases.distanceMilestone(
            km: milestone,
            durationSeconds: state.durationSeconds,
            avgPaceSecPerKm: avgPace,
          ),
          priority: RunVoiceCuePriority.progress,
          key: 'distance-$milestone',
        ),
      );
    }

    final goalProgress = _goalProgressCue(state);
    if (goalProgress != null) out.add(goalProgress);

    if (_settings.announceGpsStatus && state.isRecording) {
      final weak = state.hasWeakGps || state.lat == null;
      if (_lastWeakGps == null) {
        _lastWeakGps = weak;
      } else if (weak != _lastWeakGps) {
        final now = DateTime.now();
        final cooled =
            _lastGpsAnnounceAt == null ||
            now.difference(_lastGpsAnnounceAt!) >= const Duration(seconds: 30);
        if (cooled) {
          _lastWeakGps = weak;
          _lastGpsAnnounceAt = now;
          out.add(
            RunVoiceCue(
              text: weak
                  ? RunVoicePhrases.weakGps()
                  : RunVoicePhrases.gpsRestored(),
              priority: RunVoiceCuePriority.safety,
              key: weak ? 'gps-weak' : 'gps-restored',
            ),
          );
        }
      }
    }

    // A plan owns its pace target. Never let the global free-run target argue
    // with the current planned step.
    if (!hasPlan &&
        _settings.announcePaceWarning &&
        _settings.targetPaceSecPerKm != null &&
        state.isRecording) {
      final paceCue = _stablePaceCue(state);
      if (paceCue != null) out.add(paceCue);
    }
    return out;
  }

  RunVoiceCue? _goalProgressCue(RunTrackingState state) {
    if (!_goal.enabled || _goalCompleted || !state.isRecording) return null;
    final progress = _goal.progressFor(
      distanceMeters: state.distanceMeters,
      movingTimeSeconds: state.movingTimeSeconds,
    );
    final threshold = progress >= .8 ? 80 : (progress >= .5 ? 50 : 0);
    if (threshold == 0 || _goalProgressCues.contains(threshold)) return null;
    // Short goals only need the final approach cue.
    if (threshold == 50 &&
        ((_goal.metric == RunIntervalMetric.distance && _goal.value < 5000) ||
            (_goal.metric == RunIntervalMetric.time && _goal.value < 1800))) {
      return null;
    }
    _goalProgressCues.add(threshold);
    return RunVoiceCue(
      text: RunVoicePhrases.goalRemaining(
        metric: _goal.metric,
        value: _goal
            .remaining(
              distanceMeters: state.distanceMeters,
              movingTimeSeconds: state.movingTimeSeconds,
            )
            .round(),
      ),
      priority: RunVoiceCuePriority.coaching,
      key: 'goal-$threshold',
    );
  }

  RunVoiceCue? _stablePaceCue(RunTrackingState state) {
    final now = DateTime.now();
    _paceSamples.add((
      at: now,
      distance: state.distanceMeters,
      movingSeconds: state.movingTimeSeconds,
    ));
    _paceSamples.removeWhere(
      (sample) => now.difference(sample.at) > const Duration(seconds: 25),
    );
    if (_paceSamples.length < 2 || state.distanceMeters < 200) return null;
    final first = _paceSamples.first;
    final elapsed = state.movingTimeSeconds - first.movingSeconds;
    final distance = state.distanceMeters - first.distance;
    if (elapsed < 12 || distance < 40) return null;
    final pace = elapsed / (distance / 1000);
    final target = _settings.targetPaceSecPerKm!;
    final tolerance = _settings.paceTolerancePercent / 100;
    final direction = pace < target * (1 - tolerance)
        ? -1
        : (pace > target * (1 + tolerance) ? 1 : 0);
    if (direction == 0) {
      _paceDeviationSince = null;
      _paceDeviationDirection = 0;
      if (_paceCorrectionSpoken) {
        _paceCorrectionSpoken = false;
        return RunVoiceCue(
          text: RunVoicePhrases.paceOnTarget(),
          priority: RunVoiceCuePriority.coaching,
          key: 'pace-on-target',
        );
      }
      return null;
    }
    if (_paceDeviationDirection != direction) {
      _paceDeviationDirection = direction;
      _paceDeviationSince = now;
      return null;
    }
    if (_paceDeviationSince == null ||
        now.difference(_paceDeviationSince!) < const Duration(seconds: 10)) {
      return null;
    }
    final cooled =
        _lastPaceAnnounceAt == null ||
        now.difference(_lastPaceAnnounceAt!) >= const Duration(seconds: 60);
    if (!cooled || _paceCorrectionSpoken) return null;
    _lastPaceAnnounceAt = now;
    _paceCorrectionSpoken = true;
    return RunVoiceCue(
      text: direction < 0
          ? RunVoicePhrases.paceTooFast()
          : RunVoicePhrases.paceTooSlow(),
      priority: RunVoiceCuePriority.coaching,
      key: direction < 0 ? 'pace-fast' : 'pace-slow',
    );
  }

  RunVoiceCue? _statusCue(RunTrackingState state) {
    if (!state.isRecording && !state.isPaused) return null;
    final paused = state.isPaused;
    final previous = _wasPaused;
    _wasPaused = paused;
    if (previous == null || previous == paused) return null;
    return RunVoiceCue(
      text: paused ? RunVoicePhrases.paused() : RunVoicePhrases.resumed(),
      priority: RunVoiceCuePriority.transition,
      key: paused ? 'paused' : 'resumed',
    );
  }

  /// Starts the plan on the first recording tick and drains its events.
  /// Returns the phrases to speak (empty when [speak] is false).
  List<RunVoiceCue> _advanceStepEngine(
    RunTrackingState state, {
    required bool speak,
  }) {
    final events = <RunStepEvent>[];
    if (state.isRecording &&
        _stepEngine.snapshot.phase == RunStepEnginePhase.idle) {
      events.addAll(_stepEngine.start());
    }
    events.addAll(
      _stepEngine.tick(
        recording: state.isRecording,
        distanceMeters: state.distanceMeters,
        movingTimeSeconds: state.movingTimeSeconds,
      ),
    );
    if (!speak) return const [];
    final cues = <RunVoiceCue>[];
    for (final event in events) {
      final phrase = _phraseForStep(event);
      if (phrase != null) {
        cues.add(
          RunVoiceCue(
            text: phrase,
            priority:
                event.kind == RunStepEventKind.paceTooFast ||
                    event.kind == RunStepEventKind.paceTooSlow
                ? RunVoiceCuePriority.coaching
                : event.kind == RunStepEventKind.workoutCompleted
                ? RunVoiceCuePriority.achievement
                : RunVoiceCuePriority.transition,
            key: 'step-${event.kind.name}-${event.stepIndex}',
          ),
        );
      }
    }
    return cues;
  }

  String? _phraseForStep(RunStepEvent event) {
    switch (event.kind) {
      case RunStepEventKind.stepStarted:
        final expanded = _stepEngine.steps;
        final step = event.stepIndex >= 0 && event.stepIndex < expanded.length
            ? expanded[event.stepIndex].step
            : null;
        final min = step?.targetPaceMinSecPerKm;
        final max = step?.targetPaceMaxSecPerKm;
        final target = min != null && max != null
            ? (min + max) / 2
            : min ?? max;
        return RunVoicePhrases.stepStart(
          role: event.role,
          repIndex: event.repIndex,
          repTotal: event.repTotal,
          metric: event.metric,
          value: event.target,
          targetPaceSecPerKm: target,
        );
      case RunStepEventKind.timeRemainingCue:
        return RunVoicePhrases.timeRemaining(event.remainingSeconds ?? 30);
      case RunStepEventKind.distanceRemainingCue:
        return RunVoicePhrases.distanceRemaining(event.remainingMeters ?? 100);
      case RunStepEventKind.paceTooSlow:
        return RunVoicePhrases.stepPaceTooSlow(event.paceSecPerKm);
      case RunStepEventKind.paceTooFast:
        return RunVoicePhrases.stepPaceTooFast(event.paceSecPerKm);
      case RunStepEventKind.workoutCompleted:
        return RunVoicePhrases.workoutComplete();
      // Completion is implied by the next step's start cue.
      case RunStepEventKind.stepCompleted:
        return null;
    }
  }

  /// Per-step outcome of the session that just ended.
  ///
  /// Prefers the native results: on Android the foreground service keeps
  /// measuring while the Flutter engine is dead, so the Dart engine can have
  /// missed reps. Falls back to the Dart engine elsewhere (and in tests).
  Future<List<RunStepResult>> collectStepResults() async {
    if (_useNativeVoice) {
      final native = await RunNativeVoiceService.instance.stepResults();
      if (native.isNotEmpty) {
        return native.map(_stepResultFromNative).toList();
      }
    }
    return _stepEngine.results;
  }

  static RunStepResult _stepResultFromNative(Map<String, dynamic> row) =>
      RunStepResult(
        sequence: (row['sequence'] as num?)?.toInt() ?? 0,
        role: RunStepRole.fromString(row['role'] as String?),
        repIndex: (row['repIndex'] as num?)?.toInt() ?? 1,
        plannedMetric: row['plannedMetric'] == 'time'
            ? RunIntervalMetric.time
            : RunIntervalMetric.distance,
        plannedValue: (row['plannedValue'] as num?)?.toInt() ?? 0,
        plannedPaceSecPerKm: (row['plannedPaceSecPerKm'] as num?)?.toDouble(),
        distanceMeters: (row['distanceMeters'] as num?)?.toDouble() ?? 0,
        durationSeconds: (row['durationSeconds'] as num?)?.toInt() ?? 0,
      );

  RunVoiceCue? _cueForInterval(RunIntervalEvent event) {
    final text = _phraseForInterval(event);
    if (text == null) return null;
    return RunVoiceCue(
      text: text,
      priority: event.kind == RunIntervalEventKind.completed
          ? RunVoiceCuePriority.achievement
          : RunVoiceCuePriority.transition,
      key: 'interval-${event.kind.name}-${event.workIndex}',
    );
  }

  String? _phraseForInterval(RunIntervalEvent event) {
    switch (event.kind) {
      case RunIntervalEventKind.workStarted:
        return RunVoicePhrases.workIntervalStart(
          index: event.workIndex,
          total: event.totalWorks,
        );
      case RunIntervalEventKind.restStarted:
        return RunVoicePhrases.restIntervalStart(
          metric: _settings.interval.restMetric,
          value: _settings.interval.restValue,
        );
      case RunIntervalEventKind.completed:
        return RunVoicePhrases.intervalsComplete();
      case RunIntervalEventKind.timeRemainingCue:
        return RunVoicePhrases.timeRemaining(event.remainingSeconds ?? 30);
    }
  }

  Future<bool> _speakIfAllowed(String phrase) async {
    if (!_settings.enabled) {
      if (kDebugMode) {
        debugPrint('RunVoiceCoach: skipped (voice disabled)');
      }
      return false;
    }
    final caps = await _audioCaps();
    if (_settings.muteDuringCall && caps.inCall) {
      if (kDebugMode) {
        debugPrint('RunVoiceCoach: skipped (in call)');
      }
      return false;
    }
    if (_settings.headphonesOnly &&
        !caps.headsetConnected &&
        !_bypassHeadphonesGate) {
      if (kDebugMode) {
        debugPrint(
          'RunVoiceCoach: skipped (no headset; disable Headphones only or use debug sim)',
        );
      }
      return false;
    }
    if (kDebugMode) {
      debugPrint('RunVoiceCoach: speak "$phrase"');
    }
    await _speak(phrase);
    return true;
  }

  Future<bool> speakTestAnnouncement() async {
    await prepare();
    if (!_settings.enabled) return false;
    if (_useNativeVoice) {
      final ok = await RunNativeVoiceService.instance.speakTest();
      if (ok) return true;
      // Fallback to Dart TTS if native not available (service not bound)
    }
    await _ensureTtsReady();
    const phrase = 'Voice cues ready. Pace 5 30 per kilometer.';
    if (kDebugMode) {
      debugPrint('RunVoiceCoach: test speak');
    }
    await _speak(phrase);
    return true;
  }
}
