import 'package:workout_notes/utils/workout_estimator.dart';

/// Recommended weekly working sets per muscle group (hypertrophy consensus:
/// roughly 10-20 hard sets). Used as the marker on the "muscles per week" bars.
const int kRecommendedWeeklySetsMin = 10;
const int kRecommendedWeeklySetsMax = 20;

/// Working sets and volume a routine day (or routine) gives one muscle group.
class RoutineMuscleSets {
  final String categoryId;

  /// Stored category name; localize with `ExerciseLocaleHelper.categoryName`
  /// using `{'category_id': categoryId, 'category_name': categoryName}`.
  final String categoryName;
  final int color;
  final int sets;
  final double volumeKg;

  const RoutineMuscleSets({
    required this.categoryId,
    required this.categoryName,
    required this.color,
    required this.sets,
    required this.volumeKg,
  });

  Map<String, dynamic> get categoryRow => {
    'category_id': categoryId,
    'category_name': categoryName,
  };
}

/// One day of a routine, summarised from its planned exercises and sets.
class RoutineDaySummary {
  final String id;
  final String routineId;
  final String name;
  final String? notes;
  final int orderIndex;
  final int exerciseCount;

  /// Planned non-warm-up sets of strength (anaerobic) exercises.
  final int workingSets;

  /// Every planned set, warm-ups and cardio included.
  final int totalSets;
  final int estimatedSeconds;
  final double volumeKg;

  /// Muscle groups trained, most sets first.
  final List<RoutineMuscleSets> muscles;

  /// Most recent finished workout that trained this day.
  final DateTime? lastTrainedAt;

  const RoutineDaySummary({
    required this.id,
    required this.routineId,
    required this.name,
    required this.notes,
    required this.orderIndex,
    required this.exerciseCount,
    required this.workingSets,
    required this.totalSets,
    required this.estimatedSeconds,
    required this.volumeKg,
    required this.muscles,
    required this.lastTrainedAt,
  });
}

/// A routine with everything the list, the form and the "in use" card need,
/// loaded in one batch.
class RoutineSummary {
  final String id;
  final String name;
  final String? notes;
  final DateTime? createdAt;
  final List<RoutineDaySummary> days;

  /// Most recent finished workout of this routine (any day, or a legacy
  /// workout linked only by `routine_id`).
  final DateTime? lastTrainedAt;

  const RoutineSummary({
    required this.id,
    required this.name,
    required this.notes,
    required this.createdAt,
    required this.days,
    required this.lastTrainedAt,
  });

  int get dayCount => days.length;

  int get exerciseCount => days.fold(0, (sum, d) => sum + d.exerciseCount);

  /// Working sets over one pass through every day (one week when each day is
  /// trained once).
  int get weeklySets => days.fold(0, (sum, d) => sum + d.workingSets);

  double get weeklyVolumeKg => days.fold(0.0, (sum, d) => sum + d.volumeKg);

  /// Average estimated duration of a session, over days that have sets.
  int get averageSessionSeconds {
    final withSets = days.where((d) => d.estimatedSeconds > 0).toList();
    if (withSets.isEmpty) return 0;
    final total = withSets.fold(0, (sum, d) => sum + d.estimatedSeconds);
    return (total / withSets.length).round();
  }

  int get totalEstimatedSeconds =>
      days.fold(0, (sum, d) => sum + d.estimatedSeconds);

  /// Sets per muscle group over the whole routine, most sets first.
  List<RoutineMuscleSets> get muscles =>
      StrengthRoutineSummaryBuilder.mergeMuscles(days.expand((d) => d.muscles));

  /// Whether the routine has at least one planned exercise.
  bool get hasExercises => exerciseCount > 0;
}

/// Pure aggregation of the flat rows returned by
/// `RoutineRepository.getRoutineSummaries` (kept free of SQL so it can be unit
/// tested).
abstract final class StrengthRoutineSummaryBuilder {
  static List<RoutineSummary> build({
    required List<Map<String, dynamic>> routines,
    required List<Map<String, dynamic>> days,
    required List<Map<String, dynamic>> setRows,
    required List<Map<String, dynamic>> lastTrainedRows,
  }) {
    // (routine, day) -> last finished workout; day null = legacy workout.
    final lastByDay = <String, DateTime>{};
    final lastByRoutine = <String, DateTime>{};
    for (final row in lastTrainedRows) {
      final routineId = row['routine_id'] as String?;
      final dayId = row['routine_day_id'] as String?;
      final date = DateTime.tryParse((row['last_date'] as String?) ?? '');
      if (routineId == null || date == null) continue;
      final currentRoutine = lastByRoutine[routineId];
      if (currentRoutine == null || date.isAfter(currentRoutine)) {
        lastByRoutine[routineId] = date;
      }
      if (dayId != null) {
        final current = lastByDay[dayId];
        if (current == null || date.isAfter(current)) lastByDay[dayId] = date;
      }
    }

    // Group set rows by day, then routine exercise, keeping SQL order.
    final rowsByDay = <String, List<Map<String, dynamic>>>{};
    for (final row in setRows) {
      final dayId = row['day_id'] as String?;
      if (dayId == null) continue;
      (rowsByDay[dayId] ??= []).add(row);
    }

    final daysByRoutine = <String, List<RoutineDaySummary>>{};
    for (final day in days) {
      final routineId = day['routine_id'] as String?;
      final dayId = day['id'] as String?;
      if (routineId == null || dayId == null) continue;
      final summary = buildDay(
        day: day,
        rows: rowsByDay[dayId] ?? const [],
        lastTrainedAt: lastByDay[dayId],
      );
      (daysByRoutine[routineId] ??= []).add(summary);
    }
    for (final list in daysByRoutine.values) {
      list.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    }

    return [
      for (final routine in routines)
        RoutineSummary(
          id: routine['id'] as String,
          name: routine['name'] as String? ?? '',
          notes: routine['notes'] as String?,
          createdAt: DateTime.tryParse(
            (routine['created_at'] as String?) ?? '',
          ),
          days: daysByRoutine[routine['id']] ?? const [],
          lastTrainedAt: lastByRoutine[routine['id']],
        ),
    ];
  }

  static RoutineDaySummary buildDay({
    required Map<String, dynamic> day,
    required List<Map<String, dynamic>> rows,
    required DateTime? lastTrainedAt,
  }) {
    final exercises = <String, _ExerciseAcc>{};
    for (final row in rows) {
      final exerciseId = row['routine_exercise_id'] as String;
      final acc = exercises.putIfAbsent(
        exerciseId,
        () => _ExerciseAcc(
          restSeconds: (row['rest_time_seconds'] as num?)?.toInt(),
          categoryId: row['category_id'] as String? ?? '',
          categoryName: row['category_name'] as String? ?? '',
          color: (row['category_color'] as num?)?.toInt() ?? 0xFF757575,
          type: row['exercise_type'] as String? ?? 'weightReps',
          isStrength:
              (row['category_energy'] as String? ?? 'anaerobic') != 'aerobic',
        ),
      );
      if (row['set_id'] == null) continue;
      acc.sets.add(row);
    }

    final muscles = <String, RoutineMuscleSets>{};
    var workingSets = 0;
    var totalSets = 0;
    var volume = 0.0;
    final estimateExercises = <WorkoutEstimateExercise>[];
    for (final acc in exercises.values) {
      estimateExercises.add(
        WorkoutEstimateExercise(
          restTimeSeconds: acc.restSeconds,
          sets: [
            for (final s in acc.sets)
              WorkoutEstimateSet(
                reps: (s['reps'] as num?)?.toInt(),
                timeSeconds: (s['time_seconds'] as num?)?.toInt(),
              ),
          ],
        ),
      );
      var exerciseSets = 0;
      var exerciseVolume = 0.0;
      for (final s in acc.sets) {
        totalSets++;
        if ((s['is_warmup'] as num?)?.toInt() == 1) continue;
        exerciseSets++;
        if (acc.type == 'weightReps') {
          exerciseVolume +=
              ((s['weight'] as num?)?.toDouble() ?? 0) *
              ((s['reps'] as num?)?.toInt() ?? 0);
        }
      }
      if (!acc.isStrength) continue;
      workingSets += exerciseSets;
      volume += exerciseVolume;
      final current = muscles[acc.categoryId];
      muscles[acc.categoryId] = RoutineMuscleSets(
        categoryId: acc.categoryId,
        categoryName: acc.categoryName,
        color: acc.color,
        sets: (current?.sets ?? 0) + exerciseSets,
        volumeKg: (current?.volumeKg ?? 0) + exerciseVolume,
      );
    }

    return RoutineDaySummary(
      id: day['id'] as String,
      routineId: day['routine_id'] as String,
      name: day['name'] as String? ?? '',
      notes: day['notes'] as String?,
      orderIndex: (day['order_index'] as num?)?.toInt() ?? 0,
      exerciseCount: exercises.length,
      workingSets: workingSets,
      totalSets: totalSets,
      estimatedSeconds: WorkoutEstimateCalculator.estimateDurationSeconds(
        estimateExercises,
      ),
      volumeKg: volume,
      muscles: _sorted(muscles.values),
      lastTrainedAt: lastTrainedAt,
    );
  }

  /// Flat rows in the shape [build] expects, from the results of
  /// `getRoutineExercises` and `getPredefinedSetsForDay`. Lets the day editor
  /// summarise what it already loaded instead of querying again.
  static List<Map<String, dynamic>> setRowsFromDay(
    List<Map<String, dynamic>> exercises,
    Map<String, List<Map<String, dynamic>>> setsByExercise,
  ) {
    final rows = <Map<String, dynamic>>[];
    for (final ex in exercises) {
      final id = ex['id'] as String;
      final base = <String, dynamic>{
        'routine_exercise_id': id,
        'rest_time_seconds': ex['rest_time_seconds'],
        'category_id': ex['category_id'],
        'category_name': ex['category_name'],
        'category_color': ex['category_color'],
        'category_energy': ex['category_energy'],
        'exercise_type': ex['exercise_type'],
      };
      final sets = setsByExercise[id] ?? const [];
      if (sets.isEmpty) {
        rows.add({...base, 'set_id': null});
        continue;
      }
      for (final s in sets) {
        rows.add({
          ...base,
          'set_id': s['id'],
          'weight': s['weight'],
          'reps': s['reps'],
          'time_seconds': s['time_seconds'],
          'is_warmup': s['is_warmup'],
        });
      }
    }
    return rows;
  }

  /// Sums muscle entries that share a category, most sets first.
  static List<RoutineMuscleSets> mergeMuscles(
    Iterable<RoutineMuscleSets> entries,
  ) {
    final merged = <String, RoutineMuscleSets>{};
    for (final m in entries) {
      final current = merged[m.categoryId];
      merged[m.categoryId] = RoutineMuscleSets(
        categoryId: m.categoryId,
        categoryName: m.categoryName,
        color: m.color,
        sets: (current?.sets ?? 0) + m.sets,
        volumeKg: (current?.volumeKg ?? 0) + m.volumeKg,
      );
    }
    return _sorted(merged.values);
  }

  static List<RoutineMuscleSets> _sorted(Iterable<RoutineMuscleSets> values) =>
      values.where((m) => m.sets > 0).toList()
        ..sort((a, b) => b.sets.compareTo(a.sets));

  /// Where [sets] falls against the recommended weekly range.
  static WeeklySetsLevel levelFor(int sets) {
    if (sets < kRecommendedWeeklySetsMin) return WeeklySetsLevel.low;
    if (sets > kRecommendedWeeklySetsMax) return WeeklySetsLevel.high;
    return WeeklySetsLevel.inRange;
  }
}

enum WeeklySetsLevel { low, inRange, high }

class _ExerciseAcc {
  final int? restSeconds;
  final String categoryId;
  final String categoryName;
  final int color;
  final String type;
  final bool isStrength;
  final List<Map<String, dynamic>> sets = [];

  _ExerciseAcc({
    required this.restSeconds,
    required this.categoryId,
    required this.categoryName,
    required this.color,
    required this.type,
    required this.isStrength,
  });
}

/// Picks the routine to highlight as "in use": the one the current
/// periodization target links to, otherwise the most recently trained one.
String? pickActiveRoutineId({
  required List<RoutineSummary> routines,
  String? plannedRoutineId,
}) {
  if (plannedRoutineId != null &&
      routines.any((r) => r.id == plannedRoutineId)) {
    return plannedRoutineId;
  }
  RoutineSummary? best;
  for (final routine in routines) {
    final last = routine.lastTrainedAt;
    if (last == null) continue;
    if (best == null || last.isAfter(best.lastTrainedAt!)) best = routine;
  }
  return best?.id;
}

/// The day to train next when no plan says so: the one after the most recently
/// trained day, wrapping around. Null when no day of [routine] has been
/// trained yet (or the routine has a single day).
String? pickNextDayId(RoutineSummary routine) {
  if (routine.days.length < 2) return null;
  var lastIndex = -1;
  DateTime? lastDate;
  for (var i = 0; i < routine.days.length; i++) {
    final date = routine.days[i].lastTrainedAt;
    if (date == null) continue;
    if (lastDate == null || date.isAfter(lastDate)) {
      lastDate = date;
      lastIndex = i;
    }
  }
  if (lastIndex < 0) return null;
  return routine.days[(lastIndex + 1) % routine.days.length].id;
}
