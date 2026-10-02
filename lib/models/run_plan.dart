import 'dart:convert';

import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/utils/date_utils.dart';

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

/// How far along a plan is, counted from the scheduled ledger.
class RunPlanProgress {
  /// Sessions the plan defines across every week.
  final int totalSessions;

  /// Sessions with a recorded run attached.
  final int completedSessions;
  final int skippedSessions;

  /// Sessions materialised in the calendar and still waiting.
  final int plannedSessions;

  const RunPlanProgress({
    this.totalSessions = 0,
    this.completedSessions = 0,
    this.skippedSessions = 0,
    this.plannedSessions = 0,
  });

  /// 0..1 completion against the whole plan. 0 when the plan has no sessions.
  double get fraction => totalSessions < 1
      ? 0
      : (completedSessions / totalSessions).clamp(0.0, 1.0);

  bool get hasProgress => completedSessions > 0 || skippedSessions > 0;

  /// A plan is complete only when every defined session was actually run.
  /// Skipped sessions resolve calendar items but do not earn completion.
  bool get isComplete =>
      totalSessions > 0 && completedSessions >= totalSessions;
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
  final int completionCount;

  /// Day the plan was activated, or null when it is just a template sitting in
  /// the library. Activating anchors "week 1 of the plan" to this date's week,
  /// which is what lets a completed run tick off the right planned session.
  /// At most one plan is activated at a time.
  final DateTime? activatedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Catalog template the plan was generated from; null for blank plans and
  /// plans created before v52.
  final String? templateKey;

  /// The wizard inputs the plan was built with (a `RunPlanBuildConfig` as
  /// JSON), kept so the plan can be re-planned mid-way. Null for blank and
  /// pre-v52 plans.
  final Map<String, dynamic>? config;

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
    this.completionCount = 0,
    this.activatedAt,
    required this.createdAt,
    required this.updatedAt,
    this.templateKey,
    this.config,
    List<RunPlanWorkout> workouts = const [],
  }) : workouts = List.unmodifiable(workouts);

  bool get isArchived => status == RunPlanStatus.archived;

  /// Being followed right now. Archived plans never count, even if an old
  /// activation date is still stored.
  bool get isActivated => activatedAt != null && !isArchived;

  /// A one-week or maintenance plan is meant to be repeated for as long as it
  /// is followed. Everything else — a race build, a base block — has an end.
  bool get repeats => weeks == 1 || goalKind == RunPlanGoalKind.maintenance;

  /// Zero-based plan week that [date] falls in, counting from the activation
  /// week. Null when the plan is not activated, has not started yet, or —
  /// for plans that do not [repeats] — is already over. Repeating plans
  /// wrap.
  int? activeWeekIndexOn(DateTime date) {
    final elapsed = _elapsedWeeks(date);
    if (elapsed == null || elapsed < 0) return null;
    if (elapsed < weeks) return elapsed;
    return repeats ? elapsed % weeks : null;
  }

  /// The plan ran its full length by [date] (and does not repeat). Used to
  /// close it out instead of silently starting week 1 again.
  bool isFinishedOn(DateTime date) {
    if (!isActivated || repeats) return false;
    final elapsed = _elapsedWeeks(date);
    return elapsed != null && elapsed >= weeks;
  }

  int? _elapsedWeeks(DateTime date) {
    final anchor = activatedAt;
    if (anchor == null || weeks < 1) return null;
    return daysBetween(mondayOf(anchor), mondayOf(date)) ~/ 7;
  }

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
    int? completionCount,
    Object? activatedAt = _sentinel,
    DateTime? updatedAt,
    Object? config = _sentinel,
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
    completionCount: completionCount ?? this.completionCount,
    activatedAt: identical(activatedAt, _sentinel)
        ? this.activatedAt
        : activatedAt as DateTime?,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    templateKey: templateKey,
    config: identical(config, _sentinel)
        ? this.config
        : config as Map<String, dynamic>?,
    workouts: workouts ?? this.workouts,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'notes': notes,
    'goal_kind': goalKind.value,
    'race_date': raceDate == null ? null : dateKey(raceDate!),
    'weeks': weeks,
    'status': status.value,
    'completion_count': completionCount,
    'activated_at': activatedAt == null ? null : dateKey(activatedAt!),
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'template_key': templateKey,
    'config_json': config == null ? null : jsonEncode(config),
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
    completionCount: (map['completion_count'] as num?)?.toInt() ?? 0,
    // Absent on databases older than v46.
    activatedAt: map['activated_at'] == null
        ? null
        : DateTime.tryParse(map['activated_at'] as String),
    createdAt:
        DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime(2000),
    updatedAt:
        DateTime.tryParse(map['updated_at'] as String? ?? '') ?? DateTime(2000),
    // Absent on databases older than v52.
    templateKey: map['template_key'] as String?,
    config: _decodeConfig(map['config_json']),
    workouts: workouts,
  );

  static Map<String, dynamic>? _decodeConfig(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }
}

const Object _sentinel = Object();
