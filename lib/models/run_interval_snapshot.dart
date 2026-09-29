import 'package:workout_notes/models/run_voice_settings.dart';

enum RunIntervalPhase { idle, work, rest, done }

/// Live view of the quick interval set, as published by the native voice
/// controller (`interval_snapshot` in the tracking state).
class RunIntervalSnapshot {
  final RunIntervalPhase phase;
  final int workIndex;
  final int totalWorks;
  final double progress; // 0..1 within current phase
  final double remaining; // meters or seconds depending on phase metric
  final RunIntervalMetric currentMetric;
  final int currentTarget;

  /// What follows the running phase ("up next" preview); null when the set
  /// ends here.
  final RunIntervalPhase? nextPhase;
  final RunIntervalMetric? nextMetric;
  final int? nextTarget;

  const RunIntervalSnapshot({
    required this.phase,
    required this.workIndex,
    required this.totalWorks,
    required this.progress,
    required this.remaining,
    required this.currentMetric,
    required this.currentTarget,
    this.nextPhase,
    this.nextMetric,
    this.nextTarget,
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

  factory RunIntervalSnapshot.fromMap(Map<String, dynamic> map) {
    RunIntervalPhase? phaseOf(Object? raw) => switch (raw) {
      'work' => RunIntervalPhase.work,
      'rest' => RunIntervalPhase.rest,
      'done' => RunIntervalPhase.done,
      'idle' => RunIntervalPhase.idle,
      _ => null,
    };
    RunIntervalMetric metricOf(Object? raw) =>
        raw == 'time' ? RunIntervalMetric.time : RunIntervalMetric.distance;
    return RunIntervalSnapshot(
      phase: phaseOf(map['phase']) ?? RunIntervalPhase.idle,
      workIndex: (map['workIndex'] as num?)?.toInt() ?? 0,
      totalWorks: (map['totalWorks'] as num?)?.toInt() ?? 0,
      progress: (map['progress'] as num?)?.toDouble() ?? 0,
      remaining: (map['remaining'] as num?)?.toDouble() ?? 0,
      currentMetric: metricOf(map['metric']),
      currentTarget: (map['target'] as num?)?.toInt() ?? 0,
      nextPhase: phaseOf(map['nextPhase']),
      nextMetric: map['nextMetric'] == null
          ? null
          : metricOf(map['nextMetric']),
      nextTarget: (map['nextTarget'] as num?)?.toInt(),
    );
  }

  bool get isActive =>
      phase == RunIntervalPhase.work || phase == RunIntervalPhase.rest;
}
