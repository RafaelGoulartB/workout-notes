import 'package:workout_notes/models/run_voice_settings.dart';

/// Per-run goal. Session-only — not persisted on the activity.
///
/// Two independent parts: a distance/time target ([enabled], [metric],
/// [value]) and an optional pace target ([paceTargetSecPerKm] with
/// [paceTolerancePercent]) that feeds the pace warnings for this run only.
class RunSessionGoal {
  static const defaultPaceTolerancePercent = 5;

  final bool enabled;
  final RunIntervalMetric metric;
  final int value;

  /// Target pace for this run, in seconds per km. Null = no pace goal.
  final int? paceTargetSecPerKm;

  /// How far outside the target (percent) before the voice coach warns.
  final int paceTolerancePercent;

  const RunSessionGoal({
    required this.enabled,
    required this.metric,
    required this.value,
    this.paceTargetSecPerKm,
    this.paceTolerancePercent = defaultPaceTolerancePercent,
  });

  const RunSessionGoal.disabled()
    : this(enabled: false, metric: RunIntervalMetric.distance, value: 5000);

  const RunSessionGoal.defaults()
    : this(enabled: false, metric: RunIntervalMetric.distance, value: 5000);

  bool get hasPaceGoal => paceTargetSecPerKm != null && paceTargetSecPerKm! > 0;

  /// True when there is anything to show or enforce for this run.
  bool get hasAnyGoal => enabled || hasPaceGoal;

  RunSessionGoal copyWith({
    bool? enabled,
    RunIntervalMetric? metric,
    int? value,
    int? paceTargetSecPerKm,
    bool clearPaceTarget = false,
    int? paceTolerancePercent,
  }) {
    return RunSessionGoal(
      enabled: enabled ?? this.enabled,
      metric: metric ?? this.metric,
      value: value ?? this.value,
      paceTargetSecPerKm: clearPaceTarget
          ? null
          : (paceTargetSecPerKm ?? this.paceTargetSecPerKm),
      paceTolerancePercent: paceTolerancePercent ?? this.paceTolerancePercent,
    );
  }

  /// Wire/spool shape, shared with the Android side.
  Map<String, dynamic> toMap() => {
    'enabled': enabled,
    'metric': metric.name,
    'value': value,
    'pace_target_sec_per_km': hasPaceGoal ? paceTargetSecPerKm : null,
    'pace_tolerance_percent': paceTolerancePercent,
  };

  factory RunSessionGoal.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const RunSessionGoal.defaults();
    final pace = (map['pace_target_sec_per_km'] as num?)?.toInt();
    final tolerance = (map['pace_tolerance_percent'] as num?)?.toInt();
    return RunSessionGoal(
      enabled: map['enabled'] as bool? ?? false,
      metric: map['metric'] == 'time'
          ? RunIntervalMetric.time
          : RunIntervalMetric.distance,
      value: (map['value'] as num?)?.toInt() ?? 5000,
      paceTargetSecPerKm: pace != null && pace > 0 ? pace : null,
      paceTolerancePercent: (tolerance ?? defaultPaceTolerancePercent).clamp(
        2,
        50,
      ),
    );
  }

  double progressFor({
    required double distanceMeters,
    required int movingTimeSeconds,
  }) {
    if (!enabled || value <= 0) return 0;
    final current = metric == RunIntervalMetric.distance
        ? distanceMeters
        : movingTimeSeconds.toDouble();
    return (current / value).clamp(0.0, 1.0);
  }

  bool isComplete({
    required double distanceMeters,
    required int movingTimeSeconds,
  }) {
    if (!enabled || value <= 0) return false;
    if (metric == RunIntervalMetric.distance) {
      return distanceMeters + 1e-6 >= value;
    }
    return movingTimeSeconds >= value;
  }

  double remaining({
    required double distanceMeters,
    required int movingTimeSeconds,
  }) {
    if (!enabled || value <= 0) return 0;
    if (metric == RunIntervalMetric.distance) {
      return (value - distanceMeters).clamp(0.0, value.toDouble());
    }
    return (value - movingTimeSeconds).clamp(0, value).toDouble();
  }
}

class RunGoalSnapshot {
  final RunSessionGoal goal;
  final bool completed;
  final double progress;
  final double remaining;

  const RunGoalSnapshot({
    required this.goal,
    required this.completed,
    required this.progress,
    required this.remaining,
  });

  const RunGoalSnapshot.none()
    : this(
        goal: const RunSessionGoal.disabled(),
        completed: false,
        progress: 0,
        remaining: 0,
      );

  bool get isActive => goal.enabled;
}
