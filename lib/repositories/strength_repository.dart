import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/models/strength_workout_summary.dart';
import 'package:workout_notes/repositories/base_repository.dart';
import 'package:workout_notes/utils/date_utils.dart';
import 'package:workout_notes/utils/workout_estimator.dart';

/// The routine (and day) a workout was last trained from.
class StrengthLastRoutineUse {
  final String routineId;
  final String? routineDayId;
  final DateTime date;

  const StrengthLastRoutineUse({
    required this.routineId,
    required this.routineDayId,
    required this.date,
  });
}

/// Batched read queries for the gym hub. Only finished workouts
/// (`end_time` set) and completed, non-warm-up sets of anaerobic exercises
/// are counted, so planned or abandoned sessions never inflate the numbers.
class StrengthRepository extends BaseRepository {
  static const String _anaerobic =
      "IFNULL(c.energy_system, 'anaerobic') = 'anaerobic'";

  /// Finished workouts with at least one completed working set, newest
  /// first. [from]/[to] bound the workout date (inclusive).
  Future<List<StrengthWorkoutSummary>> loadFinishedWorkouts({
    DateTime? from,
    DateTime? to,
    int? limit,
  }) async {
    final database = await db;
    final dateFilter =
        '${from == null ? '' : 'AND w.date >= ?'} '
        '${to == null ? '' : 'AND w.date <= ?'}';
    final dateArgs = [if (from != null) dateKey(from), if (to != null) dateKey(to)];

    final rows = await database.rawQuery(
      '''
      SELECT w.id AS id, w.date AS date, w.start_time AS start_time,
        w.end_time AS end_time, w.duration_seconds AS duration_seconds,
        w.feeling_rating AS feeling_rating, w.routine_id AS routine_id,
        w.routine_day_id AS routine_day_id,
        rd.name AS routine_day_name, r.name AS routine_name,
        a.volume AS volume, a.sets AS sets, a.exercises AS exercises
      FROM workouts w
      JOIN (
        SELECT ee.workout_id AS workout_id,
          COUNT(s.id) AS sets,
          COUNT(DISTINCT ee.id) AS exercises,
          SUM(COALESCE(s.weight, 0) * COALESCE(s.reps, 0)) AS volume
        FROM sets s
        JOIN exercise_entries ee ON ee.id = s.exercise_entry_id
        JOIN workouts w ON w.id = ee.workout_id
        JOIN exercises e ON e.id = ee.exercise_id
        LEFT JOIN exercise_categories c ON c.id = e.category_id
        WHERE s.is_complete = 1 AND IFNULL(s.is_warmup, 0) = 0
          AND w.end_time IS NOT NULL AND $_anaerobic $dateFilter
        GROUP BY ee.workout_id
      ) a ON a.workout_id = w.id
      LEFT JOIN routine_days rd ON rd.id = w.routine_day_id
      LEFT JOIN routines r ON r.id = COALESCE(w.routine_id, rd.routine_id)
      WHERE w.end_time IS NOT NULL $dateFilter
      ORDER BY w.date DESC, w.start_time DESC
      ${limit == null ? '' : 'LIMIT ?'}
      ''',
      [...dateArgs, ...dateArgs, ?limit],
    );
    if (rows.isEmpty) return const [];

    final categoryRows = await database.rawQuery('''
      SELECT ee.workout_id AS workout_id, e.category_id AS category_id,
        COUNT(s.id) AS sets
      FROM sets s
      JOIN exercise_entries ee ON ee.id = s.exercise_entry_id
      JOIN workouts w ON w.id = ee.workout_id
      JOIN exercises e ON e.id = ee.exercise_id
      LEFT JOIN exercise_categories c ON c.id = e.category_id
      WHERE s.is_complete = 1 AND IFNULL(s.is_warmup, 0) = 0
        AND w.end_time IS NOT NULL AND $_anaerobic $dateFilter
      GROUP BY ee.workout_id, e.category_id
      ORDER BY ee.workout_id ASC, sets DESC, e.category_id ASC
      ''', dateArgs);
    final categoriesByWorkout = <String, List<String>>{};
    for (final row in categoryRows) {
      final id = row['category_id'] as String?;
      if (id == null || id.isEmpty) continue;
      (categoriesByWorkout[row['workout_id'] as String] ??= []).add(id);
    }

    return [
      for (final row in rows)
        _summaryFromRow(row, categoriesByWorkout[row['id'] as String] ?? []),
    ];
  }

  StrengthWorkoutSummary _summaryFromRow(
    Map<String, Object?> row,
    List<String> categoryIds,
  ) {
    final date = DateTime.parse(row['date'] as String);
    final start = DateTime.tryParse(row['start_time'] as String? ?? '');
    final end = DateTime.tryParse(row['end_time'] as String? ?? '');
    var duration = (row['duration_seconds'] as num?)?.toInt() ?? 0;
    if (duration <= 0 && start != null && end != null) {
      duration = end.difference(start).inSeconds.clamp(0, 86400);
    }
    return StrengthWorkoutSummary(
      id: row['id'] as String,
      date: dayOf(date),
      startTime: start,
      endTime: end,
      durationSeconds: duration,
      feelingRating: (row['feeling_rating'] as num?)?.toInt() ?? 0,
      routineId: row['routine_id'] as String?,
      routineDayId: row['routine_day_id'] as String?,
      routineDayName: row['routine_day_name'] as String?,
      routineName: row['routine_name'] as String?,
      volumeKg: (row['volume'] as num?)?.toDouble() ?? 0,
      workingSets: (row['sets'] as num?)?.toInt() ?? 0,
      exerciseCount: (row['exercises'] as num?)?.toInt() ?? 0,
      categoryIds: categoryIds,
    );
  }

  /// Day and length of every finished workout with a completed working set
  /// since [from] (or ever), oldest first. No joins on the result: this is
  /// what weekly overviews and streaks read.
  Future<List<StrengthWorkoutStamp>> loadWorkoutStamps({DateTime? from}) async {
    final database = await db;
    final rows = await database.rawQuery(
      '''
      SELECT w.date AS date, w.start_time AS start_time,
        w.end_time AS end_time, w.duration_seconds AS duration_seconds
      FROM workouts w
      WHERE w.end_time IS NOT NULL
        ${from == null ? '' : 'AND w.date >= ?'}
        AND EXISTS (
          SELECT 1 FROM sets s
          JOIN exercise_entries ee ON ee.id = s.exercise_entry_id
          JOIN exercises e ON e.id = ee.exercise_id
          LEFT JOIN exercise_categories c ON c.id = e.category_id
          WHERE ee.workout_id = w.id AND s.is_complete = 1
            AND IFNULL(s.is_warmup, 0) = 0 AND $_anaerobic
        )
      ORDER BY w.date ASC
      ''',
      [if (from != null) dateKey(from)],
    );
    return [
      for (final row in rows)
        () {
          final date = DateTime.parse(row['date'] as String);
          final start = DateTime.tryParse(row['start_time'] as String? ?? '');
          final end = DateTime.tryParse(row['end_time'] as String? ?? '');
          var duration = (row['duration_seconds'] as num?)?.toInt() ?? 0;
          if (duration <= 0 && start != null && end != null) {
            duration = end.difference(start).inSeconds.clamp(0, 86400);
          }
          return StrengthWorkoutStamp(
            date: dayOf(date),
            durationSeconds: duration,
          );
        }(),
    ];
  }

  /// Muscle groups with their working sets and volume in the date range,
  /// most trained first.
  Future<List<StrengthMuscleLoad>> loadMuscleLoad({
    DateTime? from,
    DateTime? to,
  }) async {
    final database = await db;
    final rows = await database.rawQuery(
      '''
      SELECT e.category_id AS category_id, c.name AS name,
        c.locale_key AS locale_key, c.color AS color,
        COUNT(s.id) AS sets,
        SUM(COALESCE(s.weight, 0) * COALESCE(s.reps, 0)) AS volume
      FROM sets s
      JOIN exercise_entries ee ON ee.id = s.exercise_entry_id
      JOIN workouts w ON w.id = ee.workout_id
      JOIN exercises e ON e.id = ee.exercise_id
      LEFT JOIN exercise_categories c ON c.id = e.category_id
      WHERE s.is_complete = 1 AND IFNULL(s.is_warmup, 0) = 0
        AND w.end_time IS NOT NULL AND $_anaerobic
        ${from == null ? '' : 'AND w.date >= ?'}
        ${to == null ? '' : 'AND w.date <= ?'}
      GROUP BY e.category_id
      ORDER BY sets DESC, volume DESC
      ''',
      [if (from != null) dateKey(from), if (to != null) dateKey(to)],
    );
    return [
      for (final row in rows)
        if ((row['category_id'] as String?)?.isNotEmpty == true)
          StrengthMuscleLoad(
            category: StrengthCategoryInfo(
              id: row['category_id'] as String,
              name: row['name'] as String? ?? row['category_id'] as String,
              localeKey: row['locale_key'] as String?,
              color: (row['color'] as num?)?.toInt() ?? 0xFF757575,
            ),
            sets: (row['sets'] as num?)?.toInt() ?? 0,
            volumeKg: (row['volume'] as num?)?.toDouble() ?? 0,
          ),
    ];
  }

  /// Every category by id (for colouring workouts by their dominant group).
  Future<Map<String, StrengthCategoryInfo>> loadCategories() async {
    final database = await db;
    final rows = await database.query('exercise_categories');
    return {
      for (final row in rows)
        row['id'] as String: StrengthCategoryInfo(
          id: row['id'] as String,
          name: row['name'] as String? ?? row['id'] as String,
          localeKey: row['locale_key'] as String?,
          color: (row['color'] as num?)?.toInt() ?? 0xFF757575,
        ),
    };
  }

  /// Planned workouts dated after [after] (exclusive) that were not started.
  Future<List<StrengthUpcomingWorkout>> loadUpcoming({
    required DateTime after,
    int limit = 5,
  }) async {
    final database = await db;
    final rows = await database.rawQuery(
      '''
      SELECT w.id AS id, w.date AS date,
        rd.name AS routine_day_name, r.name AS routine_name,
        (SELECT COUNT(*) FROM exercise_entries ee
          WHERE ee.workout_id = w.id) AS exercises
      FROM workouts w
      LEFT JOIN routine_days rd ON rd.id = w.routine_day_id
      LEFT JOIN routines r ON r.id = COALESCE(w.routine_id, rd.routine_id)
      WHERE w.date > ? AND w.end_time IS NULL
      ORDER BY w.date ASC, w.created_at ASC
      LIMIT ?
      ''',
      [dateKey(after), limit],
    );
    return [
      for (final row in rows)
        StrengthUpcomingWorkout(
          id: row['id'] as String,
          date: DateTime.parse(row['date'] as String),
          routineDayName: row['routine_day_name'] as String?,
          routineName: row['routine_name'] as String?,
          exerciseCount: (row['exercises'] as num?)?.toInt() ?? 0,
        ),
    ];
  }

  Future<int> routineCount() async {
    final database = await db;
    return Sqflite.firstIntValue(
          await database.rawQuery('SELECT COUNT(*) FROM routines'),
        ) ??
        0;
  }

  /// The routine of the latest workout that came from one (finished or not,
  /// today or before), for the "what's next" fallback.
  Future<StrengthLastRoutineUse?> lastRoutineUse({DateTime? upTo}) async {
    final database = await db;
    final rows = await database.rawQuery(
      '''
      SELECT w.routine_id AS routine_id,
        w.routine_day_id AS routine_day_id,
        w.date AS date
      FROM workouts w
      JOIN routines r ON r.id = w.routine_id
      WHERE w.routine_id IS NOT NULL AND w.end_time IS NOT NULL
        ${upTo == null ? '' : 'AND w.date <= ?'}
      ORDER BY w.date DESC, w.start_time DESC
      LIMIT 1
      ''',
      [if (upTo != null) dateKey(upTo)],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return StrengthLastRoutineUse(
      routineId: row['routine_id'] as String,
      routineDayId: row['routine_day_id'] as String?,
      date: DateTime.parse(row['date'] as String),
    );
  }

  /// Finished workouts trained from [routineId].
  Future<int> routineSessionCount(String routineId) async {
    final database = await db;
    return Sqflite.firstIntValue(
          await database.rawQuery(
            'SELECT COUNT(*) FROM workouts '
            'WHERE routine_id = ? AND end_time IS NOT NULL',
            [routineId],
          ),
        ) ??
        0;
  }

  /// The most recently created routine with at least one day, used when the
  /// user never trained from a routine yet.
  Future<String?> firstRoutineWithDays() async {
    final database = await db;
    final rows = await database.rawQuery('''
      SELECT r.id AS id FROM routines r
      WHERE EXISTS (SELECT 1 FROM routine_days d WHERE d.routine_id = r.id)
      ORDER BY r.created_at DESC
      LIMIT 1
    ''');
    return rows.isEmpty ? null : rows.first['id'] as String;
  }

  /// Days of a routine in their configured order.
  Future<List<StrengthRoutineDayRef>> routineDays(String routineId) async {
    final database = await db;
    final rows = await database.rawQuery(
      '''
      SELECT d.id AS id, d.name AS name, d.order_index AS order_index,
        r.name AS routine_name
      FROM routine_days d
      JOIN routines r ON r.id = d.routine_id
      WHERE d.routine_id = ?
      ORDER BY d.order_index ASC, d.id ASC
      ''',
      [routineId],
    );
    return [
      for (final row in rows)
        StrengthRoutineDayRef(
          routineId: routineId,
          routineName: row['routine_name'] as String? ?? '',
          dayId: row['id'] as String,
          dayName: row['name'] as String? ?? '',
          orderIndex: (row['order_index'] as num?)?.toInt() ?? 0,
        ),
    ];
  }

  /// A routine day with its exercise count, muscle groups and estimated
  /// duration, in two queries.
  Future<StrengthRoutineDayInfo?> loadRoutineDayInfo(
    String routineDayId,
  ) async {
    final database = await db;
    final dayRows = await database.rawQuery(
      '''
      SELECT d.id AS id, d.name AS name, d.routine_id AS routine_id,
        r.name AS routine_name
      FROM routine_days d
      JOIN routines r ON r.id = d.routine_id
      WHERE d.id = ?
      ''',
      [routineDayId],
    );
    if (dayRows.isEmpty) return null;
    final day = dayRows.first;

    final exerciseRows = await database.rawQuery(
      '''
      SELECT re.id AS id, re.rest_time_seconds AS rest,
        e.category_id AS category_id, c.name AS category_name,
        c.locale_key AS category_locale_key, c.color AS category_color
      FROM routine_exercises re
      JOIN exercises e ON e.id = re.exercise_id
      LEFT JOIN exercise_categories c ON c.id = e.category_id
      WHERE re.routine_day_id = ?
      ORDER BY re.order_index ASC
      ''',
      [routineDayId],
    );

    final setsByExercise = <String, List<WorkoutEstimateSet>>{};
    if (exerciseRows.isNotEmpty) {
      final ids = [for (final row in exerciseRows) row['id'] as String];
      final setRows = await database.rawQuery('''
        SELECT routine_exercise_id, reps, time_seconds
        FROM predefined_sets
        WHERE routine_exercise_id IN (${List.filled(ids.length, '?').join(', ')})
        ORDER BY order_index ASC
        ''', ids);
      for (final row in setRows) {
        (setsByExercise[row['routine_exercise_id'] as String] ??= []).add(
          WorkoutEstimateSet(
            reps: (row['reps'] as num?)?.toInt(),
            timeSeconds: (row['time_seconds'] as num?)?.toInt(),
          ),
        );
      }
    }

    final categoryCounts = <String, int>{};
    final categories = <String, StrengthCategoryInfo>{};
    for (final row in exerciseRows) {
      final id = row['category_id'] as String?;
      if (id == null || id.isEmpty) continue;
      categoryCounts[id] = (categoryCounts[id] ?? 0) + 1;
      categories[id] ??= StrengthCategoryInfo(
        id: id,
        name: row['category_name'] as String? ?? id,
        localeKey: row['category_locale_key'] as String?,
        color: (row['category_color'] as num?)?.toInt() ?? 0xFF757575,
      );
    }
    final orderedIds = categoryCounts.keys.toList()
      ..sort((a, b) => categoryCounts[b]!.compareTo(categoryCounts[a]!));

    return StrengthRoutineDayInfo(
      routineId: day['routine_id'] as String,
      routineName: day['routine_name'] as String? ?? '',
      routineDayId: routineDayId,
      dayName: day['name'] as String? ?? '',
      exerciseCount: exerciseRows.length,
      categories: [for (final id in orderedIds) categories[id]!],
      estimatedSeconds: WorkoutEstimateCalculator.estimateDurationSeconds([
        for (final row in exerciseRows)
          WorkoutEstimateExercise(
            restTimeSeconds: (row['rest'] as num?)?.toInt(),
            sets: setsByExercise[row['id'] as String] ?? const [],
          ),
      ]),
    );
  }
}
