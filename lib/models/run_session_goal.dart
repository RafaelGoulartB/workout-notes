import 'package:workout_notes/models/run_voice_settings.dart';

/// Per-run goal (distance or time). Session-only — not persisted on the activity.
class RunSessionGoal {
  final bool enabled;
  final RunIntervalMetric metric;
  final int value;

  const RunSessionGoal({
    required this.enabled,
    required this.metric,
    required this.value,
  });

  const RunSessionGoal.disabled()
      : this(
          enabled: false,
          metric: RunIntervalMetric.distance,
          value: 5000,
        );

  const RunSessionGoal.defaults()
      : this(
          enabled: false,
          metric: RunIntervalMetric.distance,
          value: 5000,
        );

  RunSessionGoal copyWith({
    bool? enabled,
    RunIntervalMetric? metric,
    int? value,
  }) {
    return RunSessionGoal(
      enabled: enabled ?? this.enabled,
      metric: metric ?? this.metric,
      value: value ?? this.value,
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
