/// Represents the energy system scope of a goal.
enum GoalScope {
  anaerobic('anaerobic'),
  aerobic('aerobic');

  final String value;
  const GoalScope(this.value);

  static GoalScope fromString(String value) =>
      values.firstWhere((e) => e.value == value, orElse: () => GoalScope.anaerobic);

  bool get isCardio => this == GoalScope.aerobic;
}

/// What kind of metric the goal tracks.
enum GoalMetric {
  volume('volume'),
  days('days'),
  distance('distance'),
  time('time');

  final String value;
  const GoalMetric(this.value);

  static GoalMetric fromString(String value) =>
      values.firstWhere((e) => e.value == value, orElse: () => GoalMetric.volume);

  /// Which metrics are valid for a given scope.
  static List<GoalMetric> forScope(GoalScope scope) {
    if (scope == GoalScope.anaerobic) {
      return [GoalMetric.volume, GoalMetric.days];
    }
    return [GoalMetric.distance, GoalMetric.time, GoalMetric.days];
  }
}

/// How often the goal resets.
enum GoalPeriod {
  weekly('weekly'),
  monthly('monthly');

  final String value;
  const GoalPeriod(this.value);

  static GoalPeriod fromString(String value) =>
      values.firstWhere((e) => e.value == value, orElse: () => GoalPeriod.weekly);
}

/// A user-defined goal with target value and reset cadence.
class Goal {
  final String id;
  final String title;
  final GoalScope scope;
  final GoalMetric metric;
  final GoalPeriod period;
  final double targetValue;
  final DateTime createdAt;
  final bool isActive;
  final int? color;

  const Goal({
    required this.id,
    required this.title,
    required this.scope,
    required this.metric,
    required this.period,
    required this.targetValue,
    required this.createdAt,
    this.isActive = true,
    this.color,
  });

  Goal copyWith({
    String? id,
    String? title,
    GoalScope? scope,
    GoalMetric? metric,
    GoalPeriod? period,
    double? targetValue,
    DateTime? createdAt,
    bool? isActive,
    int? color,
  }) {
    return Goal(
      id: id ?? this.id,
      title: title ?? this.title,
      scope: scope ?? this.scope,
      metric: metric ?? this.metric,
      period: period ?? this.period,
      targetValue: targetValue ?? this.targetValue,
      createdAt: createdAt ?? this.createdAt,
      isActive: isActive ?? this.isActive,
      color: color ?? this.color,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'scope': scope.value,
      'metric': metric.value,
      'period': period.value,
      'target_value': targetValue,
      'created_at': createdAt.toIso8601String(),
      'is_active': isActive ? 1 : 0,
      'color': color,
    };
  }

  factory Goal.fromMap(Map<String, dynamic> map) {
    return Goal(
      id: map['id'] as String,
      title: map['title'] as String? ?? '',
      scope: GoalScope.fromString(map['scope'] as String? ?? 'anaerobic'),
      metric: GoalMetric.fromString(map['metric'] as String? ?? 'volume'),
      period: GoalPeriod.fromString(map['period'] as String? ?? 'weekly'),
      targetValue: (map['target_value'] as num?)?.toDouble() ?? 0,
      createdAt: DateTime.parse(map['created_at'] as String),
      isActive: (map['is_active'] as int? ?? 1) == 1,
      color: map['color'] as int?,
    );
  }

  /// Whether this metric requires a distance unit (km or mi).
  bool get isDistance => metric == GoalMetric.distance;

  /// Whether this metric requires a time unit (seconds).
  bool get isTime => metric == GoalMetric.time;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Goal &&
        other.id == id &&
        other.title == title &&
        other.scope == scope &&
        other.metric == metric &&
        other.period == period &&
        other.targetValue == targetValue &&
        other.createdAt == createdAt &&
        other.isActive == isActive &&
        other.color == color;
  }

  @override
  int get hashCode => Object.hash(
        id,
        title,
        scope,
        metric,
        period,
        targetValue,
        createdAt,
        isActive,
        color,
      );

  @override
  String toString() =>
      'Goal(id: $id, title: $title, scope: ${scope.value}, metric: ${metric.value}, period: ${period.value}, target: $targetValue)';
}

/// Progress of a goal for the current period.
class GoalProgress {
  final double currentValue;
  final double targetValue;
  final double percent; // 0.0 to 1.0+ (capped at 1.5 for display)
  final bool isComplete;
  final DateTime periodStart;
  final DateTime periodEnd;
  final int daysRemaining;
  final int daysElapsed;

  const GoalProgress({
    required this.currentValue,
    required this.targetValue,
    required this.percent,
    required this.isComplete,
    required this.periodStart,
    required this.periodEnd,
    required this.daysRemaining,
    required this.daysElapsed,
  });

  static GoalProgress empty(DateTime now) => GoalProgress(
        currentValue: 0,
        targetValue: 0,
        percent: 0,
        isComplete: false,
        periodStart: now,
        periodEnd: now,
        daysRemaining: 0,
        daysElapsed: 0,
      );
}

/// A historical period result for a goal.
class GoalPeriodResult {
  final DateTime start;
  final DateTime end;
  final double value;
  final double targetValue;
  final bool wasCompleted;

  const GoalPeriodResult({
    required this.start,
    required this.end,
    required this.value,
    required this.targetValue,
    required this.wasCompleted,
  });

  double get percent {
    if (targetValue <= 0) return 0;
    return (value / targetValue).clamp(0.0, 1.5);
  }
}

/// A workout that contributed to the current period's progress.
class ContributingWorkout {
  final String workoutId;
  final String date; // YYYY-MM-DD
  final double contributedValue; // volume/distance/time in the goal's unit
  final int setCount; // number of sets contributing (for days = 0)

  const ContributingWorkout({
    required this.workoutId,
    required this.date,
    required this.contributedValue,
    required this.setCount,
  });
}
