import 'package:workout_notes/models/run_plan_workout.dart';

/// Target of a running plan. Drives the suggested templates and the plan card.
enum RunPlanGoalKind {
  base('base'),
  fiveK('5k'),
  tenK('10k'),
  half('half'),
  marathon('marathon'),
  maintenance('maintenance');

  final String value;
  const RunPlanGoalKind(this.value);

  static RunPlanGoalKind fromString(String? raw) => values.firstWhere(
    (kind) => kind.value == raw,
    orElse: () => RunPlanGoalKind.base,
  );
}

enum RunPlanStatus {
  active('active'),
  archived('archived');

  final String value;
  const RunPlanStatus(this.value);

  static RunPlanStatus fromString(String? raw) => values.firstWhere(
    (status) => status.value == raw,
    orElse: () => RunPlanStatus.active,
  );
}

/// A structured running plan — the running counterpart of a strength routine,
/// but progressive: [weeks] weeks, each holding its own sessions.
class RunPlan {
  final String id;
  final String name;
  final String? notes;
  final RunPlanGoalKind goalKind;
  final DateTime? raceDate;
  final int weeks;
  final RunPlanStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Sessions across every week. Empty when loaded without detail.
  final List<RunPlanWorkout> workouts;

  RunPlan({
    required this.id,
    required this.name,
    this.notes,
    required this.goalKind,
    this.raceDate,
    required this.weeks,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    List<RunPlanWorkout> workouts = const [],
  }) : workouts = List.unmodifiable(workouts);

  bool get isArchived => status == RunPlanStatus.archived;

  /// Sessions of [weekIndex] (zero-based), ordered by weekday then order.
  List<RunPlanWorkout> workoutsForWeek(int weekIndex) {
    final list = workouts
        .where((workout) => workout.weekIndex == weekIndex)
        .toList();
    list.sort((a, b) {
      final dayA = a.dayOfWeek ?? 8;
      final dayB = b.dayOfWeek ?? 8;
      if (dayA != dayB) return dayA.compareTo(dayB);
      return a.orderIndex.compareTo(b.orderIndex);
    });
    return list;
  }

  double weeklyDistanceMeters(int weekIndex) => workoutsForWeek(
    weekIndex,
  ).fold<double>(0, (sum, workout) => sum + workout.plannedDistanceMeters);

  /// Longest planned session of the week — the "longão".
  RunPlanWorkout? longRunForWeek(int weekIndex) {
    final list = workoutsForWeek(weekIndex);
    if (list.isEmpty) return null;
    return list.reduce(
      (a, b) => b.plannedDistanceMeters > a.plannedDistanceMeters ? b : a,
    );
  }

  int qualitySessionsForWeek(int weekIndex) =>
      workoutsForWeek(weekIndex).where((w) => w.kind.isQuality).length;

  RunPlan copyWith({
    String? name,
    Object? notes = _sentinel,
    RunPlanGoalKind? goalKind,
    Object? raceDate = _sentinel,
    int? weeks,
    RunPlanStatus? status,
    DateTime? updatedAt,
    List<RunPlanWorkout>? workouts,
  }) => RunPlan(
    id: id,
    name: name ?? this.name,
    notes: identical(notes, _sentinel) ? this.notes : notes as String?,
    goalKind: goalKind ?? this.goalKind,
    raceDate: identical(raceDate, _sentinel)
        ? this.raceDate
        : raceDate as DateTime?,
    weeks: weeks ?? this.weeks,
    status: status ?? this.status,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    workouts: workouts ?? this.workouts,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'notes': notes,
    'goal_kind': goalKind.value,
    'race_date': raceDate == null ? null : _date(raceDate!),
    'weeks': weeks,
    'status': status.value,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  factory RunPlan.fromMap(
    Map<String, dynamic> map, {
    List<RunPlanWorkout> workouts = const [],
  }) => RunPlan(
    id: map['id'] as String,
    name: map['name'] as String? ?? '',
    notes: map['notes'] as String?,
    goalKind: RunPlanGoalKind.fromString(map['goal_kind'] as String?),
    raceDate: map['race_date'] == null
        ? null
        : DateTime.tryParse(map['race_date'] as String),
    weeks: (map['weeks'] as num?)?.toInt() ?? 1,
    status: RunPlanStatus.fromString(map['status'] as String?),
    createdAt:
        DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime(2000),
    updatedAt:
        DateTime.tryParse(map['updated_at'] as String? ?? '') ?? DateTime(2000),
    workouts: workouts,
  );

  static String _date(DateTime value) => DateTime(
    value.year,
    value.month,
    value.day,
  ).toIso8601String().substring(0, 10);
}

const Object _sentinel = Object();
