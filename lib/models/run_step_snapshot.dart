import 'package:workout_notes/models/run_voice_settings.dart';
import 'package:workout_notes/models/run_workout_step.dart';
import 'package:workout_notes/utils/run_formatters.dart';

enum RunStepEnginePhase { idle, running, done }

/// Live view of the structured session, as published by the native voice
/// controller (`step_snapshot` in the tracking state).
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

  /// The step that follows the running one, for the "up next" preview. Null on
  /// the last step and outside a running session.
  final RunStepRole? nextRole;
  final RunIntervalMetric? nextMetric;
  final int? nextTarget;
  final int nextRepIndex;
  final int nextRepTotal;

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
    this.nextRole,
    this.nextMetric,
    this.nextTarget,
    this.nextRepIndex = 0,
    this.nextRepTotal = 0,
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
      nextRole: map['nextRole'] == null
          ? null
          : RunStepRole.fromString(map['nextRole'] as String?),
      nextMetric: map['nextMetric'] == null
          ? null
          : (map['nextMetric'] == 'time'
                ? RunIntervalMetric.time
                : RunIntervalMetric.distance),
      nextTarget: (map['nextTarget'] as num?)?.toInt(),
      nextRepIndex: (map['nextRepIndex'] as num?)?.toInt() ?? 0,
      nextRepTotal: (map['nextRepTotal'] as num?)?.toInt() ?? 0,
    );
  }

  bool get hasNext => nextRole != null && (nextTarget ?? 0) > 0;

  bool get isActive => phase == RunStepEnginePhase.running;
  bool get isDone => phase == RunStepEnginePhase.done;
}

/// Planned-vs-actual outcome of one executed step, measured by the native
/// step engine and persisted as `run_activity_steps`.
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

  /// Row produced by the native voice controller (`stepResults`).
  factory RunStepResult.fromMap(Map<String, dynamic> row) => RunStepResult(
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

  double? get actualPaceSecPerKm =>
      RunFormatters.paceOrNull(distanceMeters, durationSeconds);
}
