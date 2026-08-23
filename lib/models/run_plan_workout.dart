import 'package:workout_notes/models/run_voice_settings.dart';
import 'package:workout_notes/models/run_workout_step.dart';

/// Type of running session. Drives icon, colour and quality-volume counting.
enum RunWorkoutKind {
  easy('easy'),
  long('long'),
  tempo('tempo'),
  interval('interval'),
  fartlek('fartlek'),
  hills('hills'),
  progression('progression'),
  recovery('recovery'),
  race('race');

  final String value;
  const RunWorkoutKind(this.value);

  static RunWorkoutKind fromString(String? raw) => values.firstWhere(
    (kind) => kind.value == raw,
    orElse: () => RunWorkoutKind.easy,
  );

  /// Quality (hard) sessions, as opposed to easy volume. Used by the weekly
  /// `quality_sessions_per_week` target.
  bool get isQuality =>
      this == RunWorkoutKind.tempo ||
      this == RunWorkoutKind.interval ||
      this == RunWorkoutKind.fartlek ||
      this == RunWorkoutKind.hills ||
      this == RunWorkoutKind.race;
}

/// One planned session inside a [RunPlan] week.
class RunPlanWorkout {
  final String id;
  final String runPlanId;

  /// Zero-based week inside the plan.
  final int weekIndex;

  /// ISO weekday (1 = Monday … 7 = Sunday). Null means "any day of the week".
  final int? dayOfWeek;
  final int orderIndex;
  final RunWorkoutKind kind;
  final String name;
  final String? notes;
  final double? targetDistanceMeters;
  final int? targetDurationSeconds;
  final double? targetPaceSecPerKm;
  final String? effortZone;
  final DateTime createdAt;

  /// Ordered steps. Empty when the session is a plain continuous run described
  /// only by [targetDistanceMeters] / [targetDurationSeconds].
  final List<RunWorkoutStep> steps;

  RunPlanWorkout({
    required this.id,
    required this.runPlanId,
    required this.weekIndex,
    this.dayOfWeek,
    required this.orderIndex,
    required this.kind,
    required this.name,
    this.notes,
    this.targetDistanceMeters,
    this.targetDurationSeconds,
    this.targetPaceSecPerKm,
    this.effortZone,
    required this.createdAt,
    List<RunWorkoutStep> steps = const [],
  }) : steps = List.unmodifiable(steps);

  bool get hasSteps => steps.isNotEmpty;

  /// Total planned distance, summing step repeats when steps are present.
  /// Falls back to [targetDistanceMeters] for continuous sessions.
  double get plannedDistanceMeters {
    if (steps.isEmpty) return targetDistanceMeters ?? 0;
    var total = 0.0;
    for (final expanded in expandSteps()) {
      if (expanded.step.metric == RunIntervalMetric.distance) {
        total += expanded.step.value;
      } else if (expanded.step.targetPaceMinSecPerKm != null) {
        // Time-based step with a pace target — estimate the distance covered.
        total +=
            expanded.step.value / expanded.step.targetPaceMinSecPerKm! * 1000;
      }
    }
    return total;
  }

  /// Total planned duration, summing step repeats when steps are present.
  int get plannedDurationSeconds {
    if (steps.isEmpty) return targetDurationSeconds ?? 0;
    var total = 0;
    for (final expanded in expandSteps()) {
      if (expanded.step.metric == RunIntervalMetric.time) {
        total += expanded.step.value;
      } else if (expanded.step.targetPaceMinSecPerKm != null) {
        total +=
            (expanded.step.value / 1000 * expanded.step.targetPaceMinSecPerKm!)
                .round();
      }
    }
    return total;
  }

  /// How many effort reps the session holds (e.g. `6` for 6×800 m).
  int get workRepCount => expandSteps()
      .where((expanded) => expanded.step.role == RunStepRole.work)
      .length;

  /// Flattens [steps] into the actual execution sequence, expanding repeat
  /// blocks. Shared by the UI summary, the engine and the native bridge so all
  /// three agree on what "6×800 m" means.
  List<RunExpandedStep> expandSteps() => expand(executionSteps);

  /// Steps used by the live runner. Continuous workouts intentionally have no
  /// stored step rows, so synthesize one from their distance/duration target.
  /// Without this fallback an easy/long run appears as planned in the UI but
  /// never enters the voice step engine.
  List<RunWorkoutStep> get executionSteps {
    if (steps.isNotEmpty) return steps;
    final distance = targetDistanceMeters?.round() ?? 0;
    final duration = targetDurationSeconds ?? 0;
    if (distance <= 0 && duration <= 0) return const [];
    final targetPace = targetPaceSecPerKm;
    return [
      RunWorkoutStep(
        id: '$id:continuous',
        runPlanWorkoutId: id,
        orderIndex: 0,
        role: switch (kind) {
          RunWorkoutKind.recovery => RunStepRole.recovery,
          RunWorkoutKind.easy || RunWorkoutKind.long => RunStepRole.steady,
          _ => RunStepRole.work,
        },
        metric: distance > 0
            ? RunIntervalMetric.distance
            : RunIntervalMetric.time,
        value: distance > 0 ? distance : duration,
        targetPaceMinSecPerKm: targetPace == null ? null : targetPace * .95,
        targetPaceMaxSecPerKm: targetPace == null ? null : targetPace * 1.05,
      ),
    ];
  }

  /// Wire format for the native engine.
  List<Map<String, dynamic>> stepsJson() =>
      executionSteps.map((step) => step.toJson()).toList();

  static List<RunExpandedStep> expand(List<RunWorkoutStep> steps) {
    final ordered = [...steps]
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    final result = <RunExpandedStep>[];
    var index = 0;
    while (index < ordered.length) {
      final group = ordered[index].repeatGroup;
      if (group == null) {
        result.add(
          RunExpandedStep(
            step: ordered[index],
            repIndex: 1,
            repTotal: 1,
            sequence: result.length,
          ),
        );
        index++;
        continue;
      }
      // Collect the contiguous block sharing this repeat group.
      final block = <RunWorkoutStep>[];
      var cursor = index;
      while (cursor < ordered.length && ordered[cursor].repeatGroup == group) {
        block.add(ordered[cursor]);
        cursor++;
      }
      final repeats = block
          .map((step) => step.repeatCount)
          .reduce((a, b) => a > b ? a : b)
          .clamp(1, 99);
      for (var rep = 1; rep <= repeats; rep++) {
        for (final step in block) {
          result.add(
            RunExpandedStep(
              step: step,
              repIndex: rep,
              repTotal: repeats,
              sequence: result.length,
            ),
          );
        }
      }
      index = cursor;
    }
    return result;
  }

  RunPlanWorkout copyWith({
    int? weekIndex,
    Object? dayOfWeek = _sentinel,
    int? orderIndex,
    RunWorkoutKind? kind,
    String? name,
    Object? notes = _sentinel,
    Object? targetDistanceMeters = _sentinel,
    Object? targetDurationSeconds = _sentinel,
    Object? targetPaceSecPerKm = _sentinel,
    Object? effortZone = _sentinel,
    List<RunWorkoutStep>? steps,
  }) => RunPlanWorkout(
    id: id,
    runPlanId: runPlanId,
    weekIndex: weekIndex ?? this.weekIndex,
    dayOfWeek: identical(dayOfWeek, _sentinel)
        ? this.dayOfWeek
        : dayOfWeek as int?,
    orderIndex: orderIndex ?? this.orderIndex,
    kind: kind ?? this.kind,
    name: name ?? this.name,
    notes: identical(notes, _sentinel) ? this.notes : notes as String?,
    targetDistanceMeters: identical(targetDistanceMeters, _sentinel)
        ? this.targetDistanceMeters
        : targetDistanceMeters as double?,
    targetDurationSeconds: identical(targetDurationSeconds, _sentinel)
        ? this.targetDurationSeconds
        : targetDurationSeconds as int?,
    targetPaceSecPerKm: identical(targetPaceSecPerKm, _sentinel)
        ? this.targetPaceSecPerKm
        : targetPaceSecPerKm as double?,
    effortZone: identical(effortZone, _sentinel)
        ? this.effortZone
        : effortZone as String?,
    createdAt: createdAt,
    steps: steps ?? this.steps,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'run_plan_id': runPlanId,
    'week_index': weekIndex,
    'day_of_week': dayOfWeek,
    'order_index': orderIndex,
    'kind': kind.value,
    'name': name,
    'notes': notes,
    'target_distance_meters': targetDistanceMeters,
    'target_duration_seconds': targetDurationSeconds,
    'target_pace_sec_per_km': targetPaceSecPerKm,
    'effort_zone': effortZone,
    'created_at': createdAt.toIso8601String(),
  };

  factory RunPlanWorkout.fromMap(
    Map<String, dynamic> map, {
    List<RunWorkoutStep> steps = const [],
  }) => RunPlanWorkout(
    id: map['id'] as String,
    runPlanId: map['run_plan_id'] as String,
    weekIndex: (map['week_index'] as num?)?.toInt() ?? 0,
    dayOfWeek: (map['day_of_week'] as num?)?.toInt(),
    orderIndex: (map['order_index'] as num?)?.toInt() ?? 0,
    kind: RunWorkoutKind.fromString(map['kind'] as String?),
    name: map['name'] as String? ?? '',
    notes: map['notes'] as String?,
    targetDistanceMeters: (map['target_distance_meters'] as num?)?.toDouble(),
    targetDurationSeconds: (map['target_duration_seconds'] as num?)?.toInt(),
    targetPaceSecPerKm: (map['target_pace_sec_per_km'] as num?)?.toDouble(),
    effortZone: map['effort_zone'] as String?,
    createdAt:
        DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime(2000),
    steps: steps,
  );
}

/// A step after repeat expansion — what the engine actually executes.
class RunExpandedStep {
  final RunWorkoutStep step;

  /// 1-based repetition of the enclosing block.
  final int repIndex;
  final int repTotal;

  /// Position in the expanded sequence.
  final int sequence;

  const RunExpandedStep({
    required this.step,
    required this.repIndex,
    required this.repTotal,
    required this.sequence,
  });

  bool get isRepeated => repTotal > 1;
}

const Object _sentinel = Object();
