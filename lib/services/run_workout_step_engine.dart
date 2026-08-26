import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/models/run_voice_settings.dart';
import 'package:workout_notes/models/run_workout_step.dart';

enum RunStepEnginePhase { idle, running, done }

enum RunStepEventKind {
  stepStarted,
  stepCompleted,
  timeRemainingCue,
  distanceRemainingCue,
  paceTooSlow,
  paceTooFast,
  workoutCompleted,
}

/// Emitted as the session advances. Consumed by the voice coach (Dart) and
/// mirrored by the native controller.
class RunStepEvent {
  final RunStepEventKind kind;

  /// Position in the expanded sequence (0-based). -1 for workout-level events.
  final int stepIndex;
  final int totalSteps;
  final RunStepRole role;
  final int repIndex;
  final int repTotal;
  final RunIntervalMetric metric;
  final int target;
  final int? remainingSeconds;
  final int? remainingMeters;
  final double? paceSecPerKm;

  const RunStepEvent({
    required this.kind,
    required this.stepIndex,
    required this.totalSteps,
    required this.role,
    required this.repIndex,
    required this.repTotal,
    required this.metric,
    required this.target,
    this.remainingSeconds,
    this.remainingMeters,
    this.paceSecPerKm,
  });
}

/// Live view of the structured session.
class RunStepSnapshot {
  final RunStepEnginePhase phase;
  final int stepIndex;
  final int totalSteps;
  final RunStepRole role;
  final int repIndex;
  final int repTotal;
  final RunIntervalMetric metric;
  final int target;

  /// 0..1 inside the current step.
  final double progress;

  /// Meters or seconds left in the current step.
  final double remaining;
  final double? targetPaceMinSecPerKm;
  final double? targetPaceMaxSecPerKm;

  /// Effort reps already finished (e.g. 3 of 6 tiros).
  final int workRepsDone;
  final int workRepsTotal;

  const RunStepSnapshot({
    required this.phase,
    required this.stepIndex,
    required this.totalSteps,
    required this.role,
    required this.repIndex,
    required this.repTotal,
    required this.metric,
    required this.target,
    required this.progress,
    required this.remaining,
    this.targetPaceMinSecPerKm,
    this.targetPaceMaxSecPerKm,
    required this.workRepsDone,
    required this.workRepsTotal,
  });

  const RunStepSnapshot.idle()
    : this(
        phase: RunStepEnginePhase.idle,
        stepIndex: 0,
        totalSteps: 0,
        role: RunStepRole.work,
        repIndex: 0,
        repTotal: 0,
        metric: RunIntervalMetric.distance,
        target: 0,
        progress: 0,
        remaining: 0,
        workRepsDone: 0,
        workRepsTotal: 0,
      );

  factory RunStepSnapshot.fromMap(Map<String, dynamic> map) {
    final phase = switch (map['phase']) {
      'running' => RunStepEnginePhase.running,
      'done' => RunStepEnginePhase.done,
      _ => RunStepEnginePhase.idle,
    };
    return RunStepSnapshot(
      phase: phase,
      stepIndex: (map['stepIndex'] as num?)?.toInt() ?? 0,
      totalSteps: (map['totalSteps'] as num?)?.toInt() ?? 0,
      role: RunStepRole.fromString(map['role'] as String?),
      repIndex: (map['repIndex'] as num?)?.toInt() ?? 0,
      repTotal: (map['repTotal'] as num?)?.toInt() ?? 0,
      metric: map['metric'] == 'time'
          ? RunIntervalMetric.time
          : RunIntervalMetric.distance,
      target: (map['target'] as num?)?.toInt() ?? 0,
      progress: (map['progress'] as num?)?.toDouble() ?? 0,
      remaining: (map['remaining'] as num?)?.toDouble() ?? 0,
      targetPaceMinSecPerKm: (map['targetPaceMinSecPerKm'] as num?)?.toDouble(),
      targetPaceMaxSecPerKm: (map['targetPaceMaxSecPerKm'] as num?)?.toDouble(),
      workRepsDone: (map['workRepsDone'] as num?)?.toInt() ?? 0,
      workRepsTotal: (map['workRepsTotal'] as num?)?.toInt() ?? 0,
    );
  }

  bool get isActive => phase == RunStepEnginePhase.running;
  bool get isDone => phase == RunStepEnginePhase.done;
}

/// Pure FSM that walks a structured running session (warmup → N×(work/recovery)
/// → cooldown) driven by distance/time ticks while recording.
///
/// This is the multi-step successor to [RunIntervalEngine], which only handles a
/// single work/rest pair. The preset engine stays for the quick "intervalos"
/// toggle; this one runs a planned session. Kotlin mirror:
/// `android/.../run/RunWorkoutStepEngineNative.kt` — keep both in sync.
class RunWorkoutStepEngine {
  List<RunExpandedStep> _steps = const [];
  RunStepEnginePhase _phase = RunStepEnginePhase.idle;
  int _index = 0;
  double _accum = 0;
  bool _remainingCueSpoken = false;
  bool _paceCueSpoken = false;
  double _lastDistance = 0;
  int _lastMovingSeconds = 0;

  /// Distance and time consumed by the current step, for step results.
  double _stepDistance = 0;
  int _stepSeconds = 0;
  final List<RunStepResult> _results = [];

  List<RunExpandedStep> get steps => _steps;

  List<RunStepResult> get results => List.unmodifiable(_results);

  int get totalSteps => _steps.length;

  int get workRepsTotal =>
      _steps.where((step) => step.step.role == RunStepRole.work).length;

  int get workRepsDone => _steps
      .take(_index.clamp(0, _steps.length))
      .where((step) => step.step.role == RunStepRole.work)
      .length;

  /// Loads a session. Resets any progress.
  void configure(RunPlanWorkout workout) {
    configureSteps(workout.expandSteps());
  }

  void configureSteps(List<RunExpandedStep> steps) {
    _steps = List.unmodifiable(steps.where((step) => step.step.value > 0));
    reset();
  }

  void reset() {
    _phase = RunStepEnginePhase.idle;
    _index = 0;
    _accum = 0;
    _remainingCueSpoken = false;
    _paceCueSpoken = false;
    _lastDistance = 0;
    _lastMovingSeconds = 0;
    _stepDistance = 0;
    _stepSeconds = 0;
    _results.clear();
  }

  RunStepSnapshot get snapshot {
    if (_phase != RunStepEnginePhase.running ||
        _index < 0 ||
        _index >= _steps.length) {
      return RunStepSnapshot(
        phase: _phase,
        stepIndex: _index,
        totalSteps: _steps.length,
        role: RunStepRole.work,
        repIndex: 0,
        repTotal: 0,
        metric: RunIntervalMetric.distance,
        target: 0,
        progress: _phase == RunStepEnginePhase.done ? 1 : 0,
        remaining: 0,
        workRepsDone: _phase == RunStepEnginePhase.done
            ? workRepsTotal
            : workRepsDone,
        workRepsTotal: workRepsTotal,
      );
    }
    final current = _steps[_index];
    final target = current.step.value.toDouble();
    return RunStepSnapshot(
      phase: _phase,
      stepIndex: _index,
      totalSteps: _steps.length,
      role: current.step.role,
      repIndex: current.repIndex,
      repTotal: current.repTotal,
      metric: current.step.metric,
      target: current.step.value,
      progress: target <= 0 ? 1 : (_accum / target).clamp(0.0, 1.0),
      remaining: (target - _accum).clamp(0.0, target),
      targetPaceMinSecPerKm: current.step.targetPaceMinSecPerKm,
      targetPaceMaxSecPerKm: current.step.targetPaceMaxSecPerKm,
      workRepsDone: workRepsDone,
      workRepsTotal: workRepsTotal,
    );
  }

  /// Starts the first step. Returns the initial event, or an empty list when
  /// the session has no usable steps.
  List<RunStepEvent> start() {
    if (_steps.isEmpty) {
      _phase = RunStepEnginePhase.done;
      return const [];
    }
    _index = 0;
    _accum = 0;
    _stepDistance = 0;
    _stepSeconds = 0;
    _remainingCueSpoken = false;
    _paceCueSpoken = false;
    _lastDistance = 0;
    _lastMovingSeconds = 0;
    _results.clear();
    _phase = RunStepEnginePhase.running;
    return [_event(RunStepEventKind.stepStarted, _steps[0])];
  }

  /// Feeds a tracking snapshot. Only advances while [recording] is true, but
  /// always tracks the deltas so a pause never double-counts.
  List<RunStepEvent> tick({
    required bool recording,
    required double distanceMeters,
    required int movingTimeSeconds,
  }) {
    final distanceDelta = (distanceMeters - _lastDistance).clamp(
      0.0,
      double.infinity,
    );
    final timeDelta = (movingTimeSeconds - _lastMovingSeconds).clamp(0, 3600);
    _lastDistance = distanceMeters;
    _lastMovingSeconds = movingTimeSeconds;

    if (_phase != RunStepEnginePhase.running || !recording) return const [];

    final events = <RunStepEvent>[];
    _stepDistance += distanceDelta;
    _stepSeconds += timeDelta;

    var current = _steps[_index];
    _accum += current.step.metric == RunIntervalMetric.distance
        ? distanceDelta
        : timeDelta.toDouble();

    // One brief heads-up before a transition. Short time steps use 10 seconds;
    // longer ones use 30. Distance steps use 100 m when there is enough room.
    final target = current.step.value.toDouble();
    if (current.step.metric == RunIntervalMetric.time &&
        !_remainingCueSpoken &&
        target > 15) {
      final cueAt = target <= 120 ? 10 : 30;
      final remaining = target - _accum;
      if (remaining <= cueAt && remaining > 0) {
        _remainingCueSpoken = true;
        events.add(
          _event(
            RunStepEventKind.timeRemainingCue,
            current,
            remainingSeconds: cueAt,
          ),
        );
      }
    } else if (current.step.metric == RunIntervalMetric.distance &&
        !_remainingCueSpoken &&
        target >= 300) {
      final remaining = target - _accum;
      if (remaining <= 100 && remaining > 0) {
        _remainingCueSpoken = true;
        events.add(
          _event(
            RunStepEventKind.distanceRemainingCue,
            current,
            remainingMeters: 100,
          ),
        );
      }
    }

    // Pace feedback, once per step, only on effort steps with a target.
    if (!_paceCueSpoken && current.step.role.isEffort) {
      final pace = _currentStepPace();
      if (pace != null && _stepSeconds >= 20) {
        final min = current.step.targetPaceMinSecPerKm;
        final max = current.step.targetPaceMaxSecPerKm;
        if (max != null && pace > max) {
          _paceCueSpoken = true;
          events.add(
            _event(RunStepEventKind.paceTooSlow, current, paceSecPerKm: pace),
          );
        } else if (min != null && pace < min) {
          _paceCueSpoken = true;
          events.add(
            _event(RunStepEventKind.paceTooFast, current, paceSecPerKm: pace),
          );
        }
      }
    }

    // A step may complete on the same tick as the next one (tiny targets), so
    // drain in a loop instead of advancing once.
    while (_phase == RunStepEnginePhase.running &&
        (current.step.value <= 0 || _accum + 1e-6 >= current.step.value)) {
      final overflow = _accum - current.step.value;
      events.add(_event(RunStepEventKind.stepCompleted, current));
      _recordResult(current);
      if (_index >= _steps.length - 1) {
        _phase = RunStepEnginePhase.done;
        _index = _steps.length;
        events.add(
          RunStepEvent(
            kind: RunStepEventKind.workoutCompleted,
            stepIndex: -1,
            totalSteps: _steps.length,
            role: current.step.role,
            repIndex: current.repIndex,
            repTotal: current.repTotal,
            metric: current.step.metric,
            target: current.step.value,
          ),
        );
        break;
      }
      _index++;
      current = _steps[_index];
      // Carry the overflow so long steps don't drift on coarse GPS ticks.
      _accum = current.step.metric == _steps[_index - 1].step.metric
          ? overflow.clamp(0.0, double.infinity)
          : 0;
      _stepDistance = 0;
      _stepSeconds = 0;
      _remainingCueSpoken = false;
      _paceCueSpoken = false;
      events.add(_event(RunStepEventKind.stepStarted, current));
    }
    return events;
  }

  /// Closes the current step when the run is stopped mid-session so the partial
  /// effort still shows up in the results.
  void finish() {
    if (_phase == RunStepEnginePhase.running &&
        _index >= 0 &&
        _index < _steps.length &&
        (_stepDistance > 0 || _stepSeconds > 0)) {
      _recordResult(_steps[_index]);
    }
    _phase = RunStepEnginePhase.done;
  }

  double? _currentStepPace() {
    if (_stepDistance < 50 || _stepSeconds <= 0) return null;
    return _stepSeconds / (_stepDistance / 1000.0);
  }

  void _recordResult(RunExpandedStep expanded) {
    _results.add(
      RunStepResult(
        sequence: _results.length,
        role: expanded.step.role,
        repIndex: expanded.repIndex,
        plannedMetric: expanded.step.metric,
        plannedValue: expanded.step.value,
        plannedPaceSecPerKm: expanded.step.targetPaceMinSecPerKm,
        distanceMeters: _stepDistance,
        durationSeconds: _stepSeconds,
      ),
    );
  }

  RunStepEvent _event(
    RunStepEventKind kind,
    RunExpandedStep expanded, {
    int? remainingSeconds,
    int? remainingMeters,
    double? paceSecPerKm,
  }) => RunStepEvent(
    kind: kind,
    stepIndex: expanded.sequence,
    totalSteps: _steps.length,
    role: expanded.step.role,
    repIndex: expanded.repIndex,
    repTotal: expanded.repTotal,
    metric: expanded.step.metric,
    target: expanded.step.value,
    remainingSeconds: remainingSeconds,
    remainingMeters: remainingMeters,
    paceSecPerKm: paceSecPerKm,
  );
}

/// Planned-vs-actual outcome of one executed step, produced by the engine and
/// persisted as `run_activity_steps`.
class RunStepResult {
  final int sequence;
  final RunStepRole role;
  final int repIndex;
  final RunIntervalMetric plannedMetric;
  final int plannedValue;
  final double? plannedPaceSecPerKm;
  final double distanceMeters;
  final int durationSeconds;

  const RunStepResult({
    required this.sequence,
    required this.role,
    required this.repIndex,
    required this.plannedMetric,
    required this.plannedValue,
    this.plannedPaceSecPerKm,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  double? get actualPaceSecPerKm => distanceMeters < 1 || durationSeconds <= 0
      ? null
      : durationSeconds / (distanceMeters / 1000.0);
}
