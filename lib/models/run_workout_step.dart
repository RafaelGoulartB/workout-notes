import 'package:workout_notes/models/run_voice_settings.dart';

/// Role of a step inside a structured running session.
enum RunStepRole {
  warmup('warmup'),
  work('work'),
  recovery('recovery'),
  steady('steady'),
  cooldown('cooldown');

  final String value;
  const RunStepRole(this.value);

  static RunStepRole fromString(String? raw) => values.firstWhere(
    (role) => role.value == raw,
    orElse: () => RunStepRole.work,
  );

  /// Recovery and warmup/cooldown steps are "easy" — used for cue wording and
  /// for counting quality volume.
  bool get isEffort => this == RunStepRole.work || this == RunStepRole.steady;
}

/// One segment of a structured session (e.g. `800 m @ 4:00` or `2 min trote`).
///
/// Repeats are flat: consecutive steps sharing the same [repeatGroup] form a
/// block repeated [repeatCount] times. Steps with a null [repeatGroup] run once.
class RunWorkoutStep {
  final String id;
  final String runPlanWorkoutId;
  final int orderIndex;
  final RunStepRole role;
  final RunIntervalMetric metric;

  /// Meters when [metric] is distance, seconds when it is time.
  final int value;
  final int? repeatGroup;
  final int repeatCount;
  final double? targetPaceMinSecPerKm;
  final double? targetPaceMaxSecPerKm;
  final String? notes;

  const RunWorkoutStep({
    required this.id,
    required this.runPlanWorkoutId,
    required this.orderIndex,
    required this.role,
    required this.metric,
    required this.value,
    this.repeatGroup,
    this.repeatCount = 1,
    this.targetPaceMinSecPerKm,
    this.targetPaceMaxSecPerKm,
    this.notes,
  });

  bool get isDistance => metric == RunIntervalMetric.distance;

  bool get hasPaceTarget =>
      targetPaceMinSecPerKm != null || targetPaceMaxSecPerKm != null;

  RunWorkoutStep copyWith({
    int? orderIndex,
    RunStepRole? role,
    RunIntervalMetric? metric,
    int? value,
    Object? repeatGroup = _sentinel,
    int? repeatCount,
    Object? targetPaceMinSecPerKm = _sentinel,
    Object? targetPaceMaxSecPerKm = _sentinel,
    Object? notes = _sentinel,
  }) => RunWorkoutStep(
    id: id,
    runPlanWorkoutId: runPlanWorkoutId,
    orderIndex: orderIndex ?? this.orderIndex,
    role: role ?? this.role,
    metric: metric ?? this.metric,
    value: value ?? this.value,
    repeatGroup: identical(repeatGroup, _sentinel)
        ? this.repeatGroup
        : repeatGroup as int?,
    repeatCount: repeatCount ?? this.repeatCount,
    targetPaceMinSecPerKm: identical(targetPaceMinSecPerKm, _sentinel)
        ? this.targetPaceMinSecPerKm
        : targetPaceMinSecPerKm as double?,
    targetPaceMaxSecPerKm: identical(targetPaceMaxSecPerKm, _sentinel)
        ? this.targetPaceMaxSecPerKm
        : targetPaceMaxSecPerKm as double?,
    notes: identical(notes, _sentinel) ? this.notes : notes as String?,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'run_plan_workout_id': runPlanWorkoutId,
    'order_index': orderIndex,
    'role': role.value,
    'metric': metric.name,
    'value': value,
    'repeat_group': repeatGroup,
    'repeat_count': repeatCount,
    'target_pace_min_sec_per_km': targetPaceMinSecPerKm,
    'target_pace_max_sec_per_km': targetPaceMaxSecPerKm,
    'notes': notes,
  };

  factory RunWorkoutStep.fromMap(Map<String, dynamic> map) => RunWorkoutStep(
    id: map['id'] as String,
    runPlanWorkoutId: map['run_plan_workout_id'] as String,
    orderIndex: (map['order_index'] as num?)?.toInt() ?? 0,
    role: RunStepRole.fromString(map['role'] as String?),
    metric: map['metric'] == 'time'
        ? RunIntervalMetric.time
        : RunIntervalMetric.distance,
    value: (map['value'] as num?)?.toInt() ?? 0,
    repeatGroup: (map['repeat_group'] as num?)?.toInt(),
    repeatCount: (map['repeat_count'] as num?)?.toInt() ?? 1,
    targetPaceMinSecPerKm: (map['target_pace_min_sec_per_km'] as num?)
        ?.toDouble(),
    targetPaceMaxSecPerKm: (map['target_pace_max_sec_per_km'] as num?)
        ?.toDouble(),
    notes: map['notes'] as String?,
  );

  /// Wire format shared with the native engine (Kotlin).
  Map<String, dynamic> toJson() => {
    'role': role.value,
    'metric': metric.name,
    'value': value,
    'repeatGroup': repeatGroup,
    'repeatCount': repeatCount,
    'targetPaceMinSecPerKm': targetPaceMinSecPerKm,
    'targetPaceMaxSecPerKm': targetPaceMaxSecPerKm,
  };
}

const Object _sentinel = Object();
