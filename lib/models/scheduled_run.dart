import 'package:workout_notes/models/run_plan_workout.dart';

enum ScheduledRunStatus {
  planned('planned'),
  completed('completed'),
  skipped('skipped');

  final String value;
  const ScheduledRunStatus(this.value);

  static ScheduledRunStatus fromString(String? raw) => values.firstWhere(
    (status) => status.value == raw,
    orElse: () => ScheduledRunStatus.planned,
  );
}

/// A run planned for a specific date — the running counterpart of a `workouts`
/// row with a future date. Materialised so the calendar, adherence and
/// "reschedule / skip" flows have something to point at.
class ScheduledRun {
  final String id;
  final DateTime date;
  final String? runPlanId;
  final String? runPlanWorkoutId;
  final ScheduledRunStatus status;
  final String? notes;

  /// Set once the run is recorded.
  final String? runActivityId;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Hydrated session template when loaded with detail.
  final RunPlanWorkout? workout;

  const ScheduledRun({
    required this.id,
    required this.date,
    this.runPlanId,
    this.runPlanWorkoutId,
    required this.status,
    this.notes,
    this.runActivityId,
    required this.createdAt,
    required this.updatedAt,
    this.workout,
  });

  bool get isCompleted => status == ScheduledRunStatus.completed;
  bool get isSkipped => status == ScheduledRunStatus.skipped;
  bool get isPlanned => status == ScheduledRunStatus.planned;

  ScheduledRun copyWith({
    DateTime? date,
    ScheduledRunStatus? status,
    Object? notes = _sentinel,
    Object? runActivityId = _sentinel,
    DateTime? updatedAt,
    RunPlanWorkout? workout,
  }) => ScheduledRun(
    id: id,
    date: date ?? this.date,
    runPlanId: runPlanId,
    runPlanWorkoutId: runPlanWorkoutId,
    status: status ?? this.status,
    notes: identical(notes, _sentinel) ? this.notes : notes as String?,
    runActivityId: identical(runActivityId, _sentinel)
        ? this.runActivityId
        : runActivityId as String?,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    workout: workout ?? this.workout,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'date': _date(date),
    'run_plan_id': runPlanId,
    'run_plan_workout_id': runPlanWorkoutId,
    'status': status.value,
    'notes': notes,
    'run_activity_id': runActivityId,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  factory ScheduledRun.fromMap(
    Map<String, dynamic> map, {
    RunPlanWorkout? workout,
  }) => ScheduledRun(
    id: map['id'] as String,
    date: DateTime.parse(map['date'] as String),
    runPlanId: map['run_plan_id'] as String?,
    runPlanWorkoutId: map['run_plan_workout_id'] as String?,
    status: ScheduledRunStatus.fromString(map['status'] as String?),
    notes: map['notes'] as String?,
    runActivityId: map['run_activity_id'] as String?,
    createdAt:
        DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime(2000),
    updatedAt:
        DateTime.tryParse(map['updated_at'] as String? ?? '') ?? DateTime(2000),
    workout: workout,
  );

  static String _date(DateTime value) => DateTime(
    value.year,
    value.month,
    value.day,
  ).toIso8601String().substring(0, 10);
}

/// Planned-vs-actual result of one executed step.
class RunActivityStep {
  final String id;
  final String runActivityId;
  final int orderIndex;
  final String role;
  final int repIndex;
  final String? plannedMetric;
  final int? plannedValue;
  final double? plannedPaceSecPerKm;
  final double? actualDistanceMeters;
  final int? actualDurationSeconds;
  final double? actualPaceSecPerKm;

  const RunActivityStep({
    required this.id,
    required this.runActivityId,
    required this.orderIndex,
    required this.role,
    required this.repIndex,
    this.plannedMetric,
    this.plannedValue,
    this.plannedPaceSecPerKm,
    this.actualDistanceMeters,
    this.actualDurationSeconds,
    this.actualPaceSecPerKm,
  });

  /// Signed deviation from the planned pace, in seconds per km.
  /// Negative means faster than planned.
  double? get paceDeltaSecPerKm =>
      plannedPaceSecPerKm == null || actualPaceSecPerKm == null
      ? null
      : actualPaceSecPerKm! - plannedPaceSecPerKm!;

  Map<String, dynamic> toMap() => {
    'id': id,
    'run_activity_id': runActivityId,
    'order_index': orderIndex,
    'role': role,
    'rep_index': repIndex,
    'planned_metric': plannedMetric,
    'planned_value': plannedValue,
    'planned_pace_sec_per_km': plannedPaceSecPerKm,
    'actual_distance_meters': actualDistanceMeters,
    'actual_duration_seconds': actualDurationSeconds,
    'actual_pace_sec_per_km': actualPaceSecPerKm,
  };

  factory RunActivityStep.fromMap(Map<String, dynamic> map) => RunActivityStep(
    id: map['id'] as String,
    runActivityId: map['run_activity_id'] as String,
    orderIndex: (map['order_index'] as num?)?.toInt() ?? 0,
    role: map['role'] as String? ?? 'work',
    repIndex: (map['rep_index'] as num?)?.toInt() ?? 1,
    plannedMetric: map['planned_metric'] as String?,
    plannedValue: (map['planned_value'] as num?)?.toInt(),
    plannedPaceSecPerKm: (map['planned_pace_sec_per_km'] as num?)?.toDouble(),
    actualDistanceMeters: (map['actual_distance_meters'] as num?)?.toDouble(),
    actualDurationSeconds: (map['actual_duration_seconds'] as num?)?.toInt(),
    actualPaceSecPerKm: (map['actual_pace_sec_per_km'] as num?)?.toDouble(),
  );
}

const Object _sentinel = Object();
