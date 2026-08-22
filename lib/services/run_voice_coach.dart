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
  })  : _settingsStore = settingsStore ?? RunVoiceSettingsStore.instance,
        _intervalEngine = intervalEngine ?? RunIntervalEngine(),
        _stepEngine = stepEngine ?? RunWorkoutStepEngine(),
        _speak = speak ?? ((text) => RunTtsService.instance.speak(text)),
        _audioCaps =
            audioCaps ?? (() => RunAudioGateService.instance.getCapabilities()),
        _ensureTtsReady =
            ensureTtsReady ?? (() => RunTtsService.instance.ensureReady()),
        _stopTts = stopTts ?? (() => RunTtsService.instance.stop()),
        _useNativeVoiceOverride = useNativeVoice,
        _isCustomSpeak = speak != null || ensureTtsReady != null || stopTts != null;

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
    if (_isCustomSpeak) return false; // Tests inject fake TTS -> stay on Dart path
    if (RunTrackingService.instance.isDebugSimulating) return false;
    if (_bypassHeadphonesGate) return false; // Debug sim uses Dart TTS (emulator, no headset)
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

  Future<void> onTrackingUpdate(RunTrackingState state) async {
    if (!_active) return;
    if (_busy) return;
    _busy = true;
    try {
      final phrases = <String>[];

      // Goal completion always wins over other cues in the same tick.
      final goalJustCompleted = _checkGoalCompletion(state);
      if (goalJustCompleted) {
        phrases.add(
          RunVoicePhrases.goalComplete(
            metric: _goal.metric,
            value: _goal.value,
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
        _collectFreeRunPhrases(state);
      } else if (hasPlan) {
        // A planned session replaces the quick interval preset.
        phrases.addAll(
          _advanceStepEngine(state, speak: _settings.announceIntervals),
        );
        if (state.isRecording || state.isPaused) {
          phrases.addAll(_collectFreeRunPhrases(state));
        }
      } else {
        if (_intervalsOn &&
            _settings.announceIntervals &&
            state.isRecording &&
            _intervalEngine.snapshot.phase == RunIntervalPhase.idle) {
          final startEvents = _intervalEngine.start();
          for (final event in startEvents) {
            final phrase = _phraseForInterval(event);
            if (phrase != null) phrases.add(phrase);
          }
        }

        if (_intervalsOn && _settings.announceIntervals) {
          final intervalEvents = _intervalEngine.tick(
            recording: state.isRecording,
            distanceMeters: state.distanceMeters,
            movingTimeSeconds: state.movingTimeSeconds,
          );
          for (final event in intervalEvents) {
            final phrase = _phraseForInterval(event);
            if (phrase != null) phrases.add(phrase);
          }
        }

        if (state.isRecording || state.isPaused) {
          phrases.addAll(_collectFreeRunPhrases(state));
        }
      }

      notifyListeners();

      // On Android, the foreground service speaks natively so cues survive
      // screen-off / Flutter engine death. Skip Dart TTS there to avoid
      // double announcements; native controller is fed from RunTrackingService ticks.
      if (_useNativeVoice) return;

      for (final phrase in phrases) {
        final spoken = await _speakIfAllowed(phrase);
        if (!spoken) break;
      }
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

  List<String> _collectFreeRunPhrases(RunTrackingState state) {
    final out = <String>[];

    if (_settings.announceDistance) {
      final every = _settings.distanceEveryKm.clamp(1, 5);
      final kmFloor = (state.distanceMeters / 1000.0).floor();
      final milestone = (kmFloor ~/ every) * every;
      if (milestone > 0 && milestone > _lastAnnouncedKm) {
        _lastAnnouncedKm = milestone;
        final avgPace = state.distanceMeters > 0
            ? state.movingTimeSeconds / (state.distanceMeters / 1000.0)
            : null;
        out.add(
          RunVoicePhrases.distanceMilestone(
            km: milestone,
            durationSeconds: state.durationSeconds,
            avgPaceSecPerKm: avgPace,
          ),
        );
      }
    }

    if (_settings.announceSplit) {
      final completed = state.splits.length;
      if (completed > _lastSplitCount) {
        final split = state.splits.last;
        _lastSplitCount = completed;
        out.add(
          RunVoicePhrases.splitComplete(
            km: split.km,
            paceSecPerKm: split.paceSecPerKm,
          ),
        );
      }
    }

    if (_settings.announceGpsStatus && state.isRecording) {
      final weak = state.hasWeakGps || state.lat == null;
      if (_lastWeakGps == null) {
        _lastWeakGps = weak;
      } else if (weak != _lastWeakGps) {
        final now = DateTime.now();
        final cooled = _lastGpsAnnounceAt == null ||
            now.difference(_lastGpsAnnounceAt!) >= const Duration(seconds: 20);
        if (cooled) {
          _lastWeakGps = weak;
          _lastGpsAnnounceAt = now;
          out.add(weak ? RunVoicePhrases.weakGps() : RunVoicePhrases.gpsRestored());
        }
      }
    }

    if (_settings.announcePaceWarning &&
        _settings.targetPaceSecPerKm != null &&
        state.isRecording) {
      final pace = state.currentPaceSecPerKm;
      final target = _settings.targetPaceSecPerKm!;
      if (pace != null &&
          pace > 0 &&
          pace.isFinite &&
          state.distanceMeters >= 200) {
        final tol = _settings.paceTolerancePercent / 100.0;
        final fastLimit = target * (1 - tol);
        final slowLimit = target * (1 + tol);
        String? warning;
        if (pace < fastLimit) {
          warning = RunVoicePhrases.paceTooFast();
        } else if (pace > slowLimit) {
          warning = RunVoicePhrases.paceTooSlow();
        }
        if (warning != null) {
          final now = DateTime.now();
          final cooled = _lastPaceAnnounceAt == null ||
              now.difference(_lastPaceAnnounceAt!) >=
                  const Duration(seconds: 45);
          if (cooled) {
            _lastPaceAnnounceAt = now;
            out.add(warning);
          }
        }
      }
    }

    return out;
  }

  /// Starts the plan on the first recording tick and drains its events.
  /// Returns the phrases to speak (empty when [speak] is false).
  List<String> _advanceStepEngine(
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
    final phrases = <String>[];
    for (final event in events) {
      final phrase = _phraseForStep(event);
      if (phrase != null) phrases.add(phrase);
    }
    return phrases;
  }

  String? _phraseForStep(RunStepEvent event) {
    switch (event.kind) {
      case RunStepEventKind.stepStarted:
        final expanded = _stepEngine.steps;
        final target = event.stepIndex >= 0 && event.stepIndex < expanded.length
            ? expanded[event.stepIndex].step.targetPaceMinSecPerKm
            : null;
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
    const phrase =
        'Voice alerts are working. One kilometer. Pace 5 minutes 30 seconds.';
    if (kDebugMode) {
      debugPrint('RunVoiceCoach: test speak');
    }
    await _speak(phrase);
    return true;
  }
}
