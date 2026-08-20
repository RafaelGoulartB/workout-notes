import 'package:workout_notes/models/run_voice_settings.dart';

enum RunIntervalPhase { idle, work, rest, done }

class RunIntervalSnapshot {
  final RunIntervalPhase phase;
  final int workIndex;
  final int totalWorks;
  final double progress; // 0..1 within current phase
  final double remaining; // meters or seconds depending on phase metric
  final RunIntervalMetric currentMetric;
  final int currentTarget;

  const RunIntervalSnapshot({
    required this.phase,
    required this.workIndex,
    required this.totalWorks,
    required this.progress,
    required this.remaining,
    required this.currentMetric,
    required this.currentTarget,
  });

  const RunIntervalSnapshot.idle()
      : this(
          phase: RunIntervalPhase.idle,
          workIndex: 0,
          totalWorks: 0,
          progress: 0,
          remaining: 0,
          currentMetric: RunIntervalMetric.distance,
          currentTarget: 0,
        );

  bool get isActive =>
      phase == RunIntervalPhase.work || phase == RunIntervalPhase.rest;
}

enum RunIntervalEventKind {
  workStarted,
  restStarted,
  completed,
  timeRemainingCue,
}

class RunIntervalEvent {
  final RunIntervalEventKind kind;
  final int workIndex;
  final int totalWorks;
  final int? remainingSeconds;

  const RunIntervalEvent({
    required this.kind,
    required this.workIndex,
    required this.totalWorks,
    this.remainingSeconds,
  });
}

/// Pure work/rest FSM driven by distance/time ticks while recording.
class RunIntervalEngine {
  RunIntervalPreset _preset;
  RunIntervalPhase _phase = RunIntervalPhase.idle;
  int _workIndex = 0;
  double _phaseAccum = 0;
  bool _remainingCueSpoken = false;
  double _lastDistance = 0;
  int _lastMovingSeconds = 0;

  RunIntervalEngine({RunIntervalPreset? preset})
      : _preset = preset ?? const RunIntervalPreset.defaults();

  RunIntervalPreset get preset => _preset;

  void configure(RunIntervalPreset preset) {
    _preset = preset;
  }

  RunIntervalSnapshot get snapshot {
    if (_phase == RunIntervalPhase.idle || _phase == RunIntervalPhase.done) {
      return RunIntervalSnapshot(
        phase: _phase,
        workIndex: _workIndex,
        totalWorks: _preset.repeats,
        progress: _phase == RunIntervalPhase.done ? 1 : 0,
        remaining: 0,
        currentMetric: RunIntervalMetric.distance,
        currentTarget: 0,
      );
    }
    final metric = _phase == RunIntervalPhase.work
        ? _preset.workMetric
        : _preset.restMetric;
    final target = (_phase == RunIntervalPhase.work
            ? _preset.workValue
            : _preset.restValue)
        .toDouble();
    final progress = target <= 0 ? 1.0 : (_phaseAccum / target).clamp(0.0, 1.0);
    return RunIntervalSnapshot(
      phase: _phase,
      workIndex: _workIndex,
      totalWorks: _preset.repeats,
      progress: progress,
      remaining: (target - _phaseAccum).clamp(0.0, target),
      currentMetric: metric,
      currentTarget: target.round(),
    );
  }

  /// Starts the first work segment. Returns start event or empty.
  List<RunIntervalEvent> start() {
    _resetAccumulators();
    _workIndex = 1;
    _phase = RunIntervalPhase.work;
    _phaseAccum = 0;
    _remainingCueSpoken = false;
    return [
      RunIntervalEvent(
        kind: RunIntervalEventKind.workStarted,
        workIndex: _workIndex,
        totalWorks: _preset.repeats,
      ),
    ];
  }

  void reset() {
    _phase = RunIntervalPhase.idle;
    _workIndex = 0;
    _phaseAccum = 0;
    _remainingCueSpoken = false;
    _lastDistance = 0;
    _lastMovingSeconds = 0;
  }

  /// Feed tracking snapshot. Only advances while [recording] is true.
  List<RunIntervalEvent> tick({
    required bool recording,
    required double distanceMeters,
    required int movingTimeSeconds,
  }) {
    if (_phase == RunIntervalPhase.idle || _phase == RunIntervalPhase.done) {
      _lastDistance = distanceMeters;
      _lastMovingSeconds = movingTimeSeconds;
      return const [];
    }

    final distanceDelta =
        (distanceMeters - _lastDistance).clamp(0.0, double.infinity);
    final timeDelta =
        (movingTimeSeconds - _lastMovingSeconds).clamp(0, 3600);
    _lastDistance = distanceMeters;
    _lastMovingSeconds = movingTimeSeconds;

    if (!recording) {
      return const [];
    }

    final events = <RunIntervalEvent>[];
    final metric = _phase == RunIntervalPhase.work
        ? _preset.workMetric
        : _preset.restMetric;
    final target = (_phase == RunIntervalPhase.work
            ? _preset.workValue
            : _preset.restValue)
        .toDouble();

    if (metric == RunIntervalMetric.distance) {
      _phaseAccum += distanceDelta;
    } else {
      _phaseAccum += timeDelta.toDouble();
    }

    // Optional 30s remaining cue for time-based phases (not on the
    // same tick that completes the phase).
    if (metric == RunIntervalMetric.time &&
        !_remainingCueSpoken &&
        target > 30) {
      final remaining = target - _phaseAccum;
      if (remaining <= 30 && remaining > 0) {
        _remainingCueSpoken = true;
        events.add(
          RunIntervalEvent(
            kind: RunIntervalEventKind.timeRemainingCue,
            workIndex: _workIndex,
            totalWorks: _preset.repeats,
            remainingSeconds: 30,
          ),
        );
      }
    }

    if (target <= 0 || _phaseAccum + 1e-6 >= target) {
      events.addAll(_advancePhase());
    }
    return events;
  }

  List<RunIntervalEvent> _advancePhase() {
    final events = <RunIntervalEvent>[];
    if (_phase == RunIntervalPhase.work) {
      if (_workIndex >= _preset.repeats) {
        _phase = RunIntervalPhase.done;
        _phaseAccum = 0;
        events.add(
          RunIntervalEvent(
            kind: RunIntervalEventKind.completed,
            workIndex: _workIndex,
            totalWorks: _preset.repeats,
          ),
        );
        return events;
      }
      // Rest after work (skip if rest value is 0).
      if (_preset.restValue <= 0) {
        _workIndex += 1;
        _phase = RunIntervalPhase.work;
        _phaseAccum = 0;
        _remainingCueSpoken = false;
        events.add(
          RunIntervalEvent(
            kind: RunIntervalEventKind.workStarted,
            workIndex: _workIndex,
            totalWorks: _preset.repeats,
          ),
        );
        return events;
      }
      _phase = RunIntervalPhase.rest;
      _phaseAccum = 0;
      _remainingCueSpoken = false;
      events.add(
        RunIntervalEvent(
          kind: RunIntervalEventKind.restStarted,
          workIndex: _workIndex,
          totalWorks: _preset.repeats,
        ),
      );
      return events;
    }

    // Rest finished → next work or done.
    if (_workIndex >= _preset.repeats) {
      _phase = RunIntervalPhase.done;
      _phaseAccum = 0;
      events.add(
        RunIntervalEvent(
          kind: RunIntervalEventKind.completed,
          workIndex: _workIndex,
          totalWorks: _preset.repeats,
        ),
      );
      return events;
    }
    _workIndex += 1;
    _phase = RunIntervalPhase.work;
    _phaseAccum = 0;
    _remainingCueSpoken = false;
    events.add(
      RunIntervalEvent(
        kind: RunIntervalEventKind.workStarted,
        workIndex: _workIndex,
        totalWorks: _preset.repeats,
      ),
    );
    return events;
  }

  void _resetAccumulators() {
    _phaseAccum = 0;
    _remainingCueSpoken = false;
    _lastDistance = 0;
    _lastMovingSeconds = 0;
  }
}
