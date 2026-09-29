import 'dart:ui';

import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/models/exercise_with_sets.dart';
import 'package:workout_notes/models/workout_stats.dart';
import 'package:workout_notes/repositories/base_repository.dart';
import 'package:workout_notes/repositories/strength_records_repository.dart';
import 'package:workout_notes/repositories/workout_repository.dart';
import 'package:workout_notes/repositories/workout_sql.dart';
import 'package:workout_notes/utils/sql_helpers.dart';
import 'package:workout_notes/utils/strength_workout_records.dart';
import 'package:workout_notes/utils/date_utils.dart';

/// How the exercise-name part of a search matches an `exercises` row
/// (`id`, `name`, `locale_key`). Lets the UI search localized names.
typedef ExerciseSearchMatcher =
    bool Function(Map<String, dynamic> exercise, String query);

enum StrengthHistoryPeriod { all, last30Days, last90Days, thisYear }

/// Search, routine, period and muscle filters of the strength history.
class StrengthHistoryFilter {
  final String query;
  final String? routineId;
  final String? categoryId;
  final StrengthHistoryPeriod period;

  const StrengthHistoryFilter({
    this.query = '',
    this.routineId,
    this.categoryId,
    this.period = StrengthHistoryPeriod.all,
  });

  bool get isActive =>
      query.trim().isNotEmpty ||
      routineId != null ||
      categoryId != null ||
      period != StrengthHistoryPeriod.all;

  StrengthHistoryFilter copyWith({
    String? query,
    String? routineId,
    bool clearRoutine = false,
    String? categoryId,
    bool clearCategory = false,
    StrengthHistoryPeriod? period,
  }) => StrengthHistoryFilter(
    query: query ?? this.query,
    routineId: clearRoutine ? null : (routineId ?? this.routineId),
    categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
    period: period ?? this.period,
  );

  /// First day included by [period] as `yyyy-MM-dd`, or null for all time.
  String? fromDay(DateTime now) {
    final DateTime? from = switch (period) {
      StrengthHistoryPeriod.all => null,
      StrengthHistoryPeriod.last30Days => now.subtract(
        const Duration(days: 30),
      ),
      StrengthHistoryPeriod.last90Days => now.subtract(
        const Duration(days: 90),
      ),
      StrengthHistoryPeriod.thisYear => DateTime(now.year),
    };
    return from == null ? null : dateKey(from);
  }
}

/// Work done on one muscle group (exercise category) in a workout.
class StrengthMuscleShare {
  final String categoryId;
  final String name;
  final String? localeKey;
  final Color color;
  final int workingSets;
  final double volume;

  const StrengthMuscleShare({
    required this.categoryId,
    required this.name,
    required this.localeKey,
    required this.color,
    required this.workingSets,
    required this.volume,
  });

  /// Row shaped like a category query, for `ExerciseLocaleHelper`.
  Map<String, dynamic> get categoryRow => {
    'locale_key': localeKey,
    'category_id': categoryId,
    'category_name': name,
  };
}

/// One finished gym workout as listed in the history.
class StrengthHistoryWorkout {
  final String id;

  /// Workout day (`yyyy-MM-dd`).
  final DateTime day;

  /// Real start time, when it was recorded.
  final DateTime? startedAt;
  final int durationSeconds;
  final int feelingRating;
  final String? comment;
  final String? routineId;
  final String? routineDayId;
  final String? routineName;
  final String? dayName;
  final double volume;
  final int workingSets;
  final int exerciseCount;
  final List<StrengthMuscleShare> muscles;
  final int recordCount;

  const StrengthHistoryWorkout({
    required this.id,
    required this.day,
    required this.startedAt,
    required this.durationSeconds,
    required this.feelingRating,
    required this.comment,
    required this.routineId,
    required this.routineDayId,
    required this.routineName,
    required this.dayName,
    required this.volume,
    required this.workingSets,
    required this.exerciseCount,
    required this.muscles,
    this.recordCount = 0,
  });

  /// Routine day name, else routine name; null for a free workout.
  String? get title {
    final day = dayName?.trim();
    if (day != null && day.isNotEmpty) return day;
    final routine = routineName?.trim();
    if (routine != null && routine.isNotEmpty) return routine;
    return null;
  }

  StrengthHistoryWorkout withRecordCount(int count) => StrengthHistoryWorkout(
    id: id,
    day: day,
    startedAt: startedAt,
    durationSeconds: durationSeconds,
    feelingRating: feelingRating,
    comment: comment,
    routineId: routineId,
    routineDayId: routineDayId,
    routineName: routineName,
    dayName: dayName,
    volume: volume,
    workingSets: workingSets,
    exerciseCount: exerciseCount,
    muscles: muscles,
    recordCount: count,
  );
}

/// Aggregate of the workouts matching a filter (or one month of them).
class StrengthHistoryTotals {
  final int count;
  final double volume;
  final int workingSets;
  final int durationSeconds;

  const StrengthHistoryTotals({
    required this.count,
    required this.volume,
    required this.workingSets,
    required this.durationSeconds,
  });

  static const empty = StrengthHistoryTotals(
    count: 0,
    volume: 0,
    workingSets: 0,
    durationSeconds: 0,
  );
}

class StrengthRoutineOption {
  final String id;
  final String name;

  const StrengthRoutineOption({required this.id, required this.name});
}

class StrengthCategoryOption {
  final String id;
  final String name;
  final String? localeKey;
  final Color color;

  const StrengthCategoryOption({
    required this.id,
    required this.name,
    required this.localeKey,
    required this.color,
  });

  Map<String, dynamic> get categoryRow => {
    'locale_key': localeKey,
    'category_id': id,
    'category_name': name,
  };
}

/// Everything the workout detail screen shows.
class StrengthWorkoutDetail {
  final Map<String, dynamic> workout;
  final String? routineName;
  final String? dayName;
  final List<ExerciseWithSets> exercises;
  final WorkoutStats? stats;
  final WorkoutStatsComparison? comparison;
  final WorkoutComparable? comparable;

  /// Name of the routine day (or routine) the comparison is based on.
  final String? comparableName;
  final List<StrengthRecordEvent> records;

  const StrengthWorkoutDetail({
    required this.workout,
    required this.routineName,
    required this.dayName,
    required this.exercises,
    required this.stats,
    required this.comparison,
    required this.comparable,
    required this.comparableName,
    required this.records,
  });

  bool get isFinished => workout['end_time'] != null;

  String? get title {
    final day = dayName?.trim();
    if (day != null && day.isNotEmpty) return day;
    final routine = routineName?.trim();
    if (routine != null && routine.isNotEmpty) return routine;
    return null;
  }
}

/// Queries behind the strength history and the workout detail. Only finished
/// workouts that contain strength (anaerobic) exercises are listed; cardio-only
/// sessions are left out. All aggregation is batched, never per row.
class StrengthHistoryRepository extends BaseRepository {
  final ExerciseSearchMatcher? exerciseMatcher;
  final WorkoutRepository _workouts;
  final StrengthRecordsRepository _records;

  StrengthHistoryRepository({
    this.exerciseMatcher,
    WorkoutRepository? workouts,
    StrengthRecordsRepository? records,
  }) : _workouts = workouts ?? DatabaseHelper.instance.workoutRepo,
       _records = records ?? DatabaseHelper.instance.strengthRecordsRepo;

  static const _anaerobic =
      "IFNULL(c.energy_system, 'anaerobic') = 'anaerobic'";
  static const _workingSet = WorkoutSql.workSet;

  Future<_Where> _where(
    DatabaseExecutor db,
    StrengthHistoryFilter filter,
    DateTime now,
  ) async {
    final joins = StringBuffer()
      ..write('LEFT JOIN routine_days rd ON rd.id = w.routine_day_id ')
      ..write(
        'LEFT JOIN routines r ON r.id = COALESCE(w.routine_id, rd.routine_id)',
      );

    final conditions = <String>['w.end_time IS NOT NULL'];
    final args = <Object?>[];

    final categoryId = filter.categoryId;
    conditions.add('''
      EXISTS (
        SELECT 1 FROM exercise_entries ee
        JOIN exercises e ON e.id = ee.exercise_id
        LEFT JOIN exercise_categories c ON c.id = e.category_id
        WHERE ee.workout_id = w.id AND $_anaerobic
        ${categoryId == null ? '' : 'AND e.category_id = ?'})
    ''');
    if (categoryId != null) args.add(categoryId);

    final from = filter.fromDay(now);
    if (from != null) {
      conditions.add('w.date >= ?');
      args.add(from);
    }
    if (filter.routineId != null) {
      conditions.add('COALESCE(w.routine_id, rd.routine_id) = ?');
      args.add(filter.routineId);
    }

    final query = filter.query.trim();
    if (query.isNotEmpty) {
      final like = '%${escapeLike(query)}%';
      final matchedIds = <String>[];
      final matcher = exerciseMatcher;
      if (matcher != null) {
        final exercises = await db.query(
          'exercises',
          columns: ['id', 'name', 'locale_key'],
        );
        for (final row in exercises) {
          if (matcher(row, query)) matchedIds.add(row['id'] as String);
        }
      }
      final idClause = matchedIds.isEmpty
          ? ''
          : 'OR e2.id IN (${List.filled(matchedIds.length, '?').join(',')})';
      conditions.add('''
        (r.name LIKE ? ESCAPE '\\' OR rd.name LIKE ? ESCAPE '\\'
         OR w.comment LIKE ? ESCAPE '\\'
         OR EXISTS (
           SELECT 1 FROM exercise_entries ee2
           JOIN exercises e2 ON e2.id = ee2.exercise_id
           WHERE ee2.workout_id = w.id
             AND (e2.name LIKE ? ESCAPE '\\' $idClause)))
      ''');
      args.addAll([like, like, like, like, ...matchedIds]);
    }

    return _Where(
      joins: joins.toString(),
      condition: conditions.join(' AND '),
      args: args,
    );
  }

  /// A page of workouts, newest first.
  Future<List<StrengthHistoryWorkout>> search(
    StrengthHistoryFilter filter, {
    int limit = 30,
    int offset = 0,
    DateTime? now,
  }) async {
    final database = await db;
    final where = await _where(database, filter, now ?? DateTime.now());
    final rows = await database.rawQuery(
      '''
      SELECT w.id AS id, w.date AS date, w.start_time AS start_time,
        w.duration_seconds AS duration_seconds,
        w.feeling_rating AS feeling_rating, w.comment AS comment,
        r.id AS routine_id, w.routine_day_id AS routine_day_id,
        r.name AS routine_name, rd.name AS day_name
      FROM workouts w
      ${where.joins}
      WHERE ${where.condition}
      ORDER BY w.date DESC, COALESCE(w.start_time, w.created_at) DESC, w.id DESC
      LIMIT ? OFFSET ?
      ''',
      [...where.args, limit, offset],
    );
    if (rows.isEmpty) return const [];

    final ids = [for (final r in rows) r['id'] as String];
    final muscles = await _musclesByWorkout(database, ids);
    return [
      for (final r in rows)
        _summaryFromRow(r, muscles[r['id'] as String] ?? const []),
    ];
  }

  StrengthHistoryWorkout _summaryFromRow(
    Map<String, Object?> r,
    List<_MuscleRow> muscleRows,
  ) {
    final start = DateTime.tryParse(r['start_time'] as String? ?? '');
    final day =
        DateTime.tryParse(r['date'] as String? ?? '') ??
        start ??
        DateTime.now();
    final shares =
        [
          for (final m in muscleRows)
            StrengthMuscleShare(
              categoryId: m.categoryId,
              name: m.name,
              localeKey: m.localeKey,
              color: Color(m.color),
              workingSets: m.workingSets,
              volume: m.volume,
            ),
        ]..sort((a, b) {
          final bySets = b.workingSets.compareTo(a.workingSets);
          return bySets != 0 ? bySets : b.volume.compareTo(a.volume);
        });
    final comment = (r['comment'] as String?)?.trim();
    return StrengthHistoryWorkout(
      id: r['id'] as String,
      day: dayOf(day),
      startedAt: start,
      durationSeconds: (r['duration_seconds'] as num?)?.toInt() ?? 0,
      feelingRating: (r['feeling_rating'] as num?)?.toInt() ?? 0,
      comment: comment == null || comment.isEmpty ? null : comment,
      routineId: r['routine_id'] as String?,
      routineDayId: r['routine_day_id'] as String?,
      routineName: r['routine_name'] as String?,
      dayName: r['day_name'] as String?,
      volume: muscleRows.fold<double>(0, (sum, m) => sum + m.volume),
      workingSets: muscleRows.fold<int>(0, (sum, m) => sum + m.workingSets),
      exerciseCount: muscleRows.fold<int>(0, (sum, m) => sum + m.entries),
      muscles: shares,
    );
  }

  /// Per workout and muscle group: entries, working sets and volume, for all
  /// [workoutIds] in one query.
  Future<Map<String, List<_MuscleRow>>> _musclesByWorkout(
    DatabaseExecutor database,
    List<String> workoutIds,
  ) async {
    final result = <String, List<_MuscleRow>>{};
    final placeholders = List.filled(workoutIds.length, '?').join(',');
    final rows = await database.rawQuery('''
      SELECT ee.workout_id AS workout_id, IFNULL(e.category_id, '') AS category_id,
        c.name AS name, c.locale_key AS locale_key, c.color AS color,
        COUNT(DISTINCT ee.id) AS entries,
        SUM(CASE WHEN $_workingSet THEN 1 ELSE 0 END) AS work_sets,
        SUM(CASE WHEN $_workingSet
            THEN IFNULL(s.weight, 0) * IFNULL(s.reps, 0) ELSE 0 END) AS volume
      FROM exercise_entries ee
      JOIN exercises e ON e.id = ee.exercise_id
      LEFT JOIN exercise_categories c ON c.id = e.category_id
      LEFT JOIN sets s ON s.exercise_entry_id = ee.id
      WHERE ee.workout_id IN ($placeholders) AND $_anaerobic
      GROUP BY ee.workout_id, e.category_id
      ''', workoutIds);
    for (final r in rows) {
      result
          .putIfAbsent(r['workout_id'] as String, () => [])
          .add(
            _MuscleRow(
              categoryId: r['category_id'] as String? ?? '',
              name: r['name'] as String? ?? '',
              localeKey: r['locale_key'] as String?,
              color: (r['color'] as num?)?.toInt() ?? 0xFF757575,
              entries: (r['entries'] as num?)?.toInt() ?? 0,
              workingSets: (r['work_sets'] as num?)?.toInt() ?? 0,
              volume: (r['volume'] as num?)?.toDouble() ?? 0,
            ),
          );
    }
    return result;
  }

  /// Totals of everything matching [filter].
  Future<StrengthHistoryTotals> summarize(
    StrengthHistoryFilter filter, {
    DateTime? now,
  }) async {
    final totals = await monthlyTotals(filter, now: now);
    if (totals.isEmpty) return StrengthHistoryTotals.empty;
    return StrengthHistoryTotals(
      count: totals.values.fold(0, (sum, t) => sum + t.count),
      volume: totals.values.fold(0.0, (sum, t) => sum + t.volume),
      workingSets: totals.values.fold(0, (sum, t) => sum + t.workingSets),
      durationSeconds: totals.values.fold(
        0,
        (sum, t) => sum + t.durationSeconds,
      ),
    );
  }

  /// Totals per month (`yyyy-MM`) of everything matching [filter].
  Future<Map<String, StrengthHistoryTotals>> monthlyTotals(
    StrengthHistoryFilter filter, {
    DateTime? now,
  }) async {
    final database = await db;
    final where = await _where(database, filter, now ?? DateTime.now());
    final subquery =
        'SELECT w.id FROM workouts w ${where.joins} WHERE ${where.condition}';

    final counts = await database.rawQuery('''
      SELECT substr(w.date, 1, 7) AS month, COUNT(*) AS n,
        SUM(IFNULL(w.duration_seconds, 0)) AS duration
      FROM workouts w
      WHERE w.id IN ($subquery)
      GROUP BY substr(w.date, 1, 7)
      ''', where.args);
    final volumes = await database.rawQuery('''
      SELECT substr(w.date, 1, 7) AS month, COUNT(s.id) AS work_sets,
        SUM(IFNULL(s.weight, 0) * IFNULL(s.reps, 0)) AS volume
      FROM sets s
      JOIN exercise_entries ee ON ee.id = s.exercise_entry_id
      JOIN workouts w ON w.id = ee.workout_id
      JOIN exercises e ON e.id = ee.exercise_id
      LEFT JOIN exercise_categories c ON c.id = e.category_id
      WHERE $_workingSet AND $_anaerobic AND w.id IN ($subquery)
      GROUP BY substr(w.date, 1, 7)
      ''', where.args);
    final volumeByMonth = {for (final r in volumes) r['month'] as String: r};
    return {
      for (final r in counts)
        r['month'] as String: StrengthHistoryTotals(
          count: (r['n'] as num?)?.toInt() ?? 0,
          durationSeconds: (r['duration'] as num?)?.toInt() ?? 0,
          volume:
              (volumeByMonth[r['month']]?['volume'] as num?)?.toDouble() ?? 0,
          workingSets:
              (volumeByMonth[r['month']]?['work_sets'] as num?)?.toInt() ?? 0,
        ),
    };
  }

  /// Distinct exercises with a record, per workout id, in one pass over the
  /// whole history.
  Future<Map<String, int>> recordCounts() async {
    final events = StrengthRecordsCalculator.events(await _records.loadSets());
    return StrengthWorkoutRecords.exerciseCountByWorkout(events);
  }

  /// Routines that have at least one listed workout.
  Future<List<StrengthRoutineOption>> routineOptions() async {
    final database = await db;
    final rows = await database.rawQuery('''
      SELECT DISTINCT r.id AS id, r.name AS name
      FROM workouts w
      LEFT JOIN routine_days rd ON rd.id = w.routine_day_id
      JOIN routines r ON r.id = COALESCE(w.routine_id, rd.routine_id)
      WHERE w.end_time IS NOT NULL
      ORDER BY r.name COLLATE NOCASE
      ''');
    return [
      for (final r in rows)
        StrengthRoutineOption(
          id: r['id'] as String,
          name: r['name'] as String? ?? '',
        ),
    ];
  }

  /// Strength muscle groups, in the app's category order.
  Future<List<StrengthCategoryOption>> categoryOptions() async {
    final database = await db;
    final rows = await database.rawQuery('''
      SELECT id, name, locale_key, color
      FROM exercise_categories
      WHERE IFNULL(energy_system, 'anaerobic') = 'anaerobic'
      ORDER BY order_index ASC, name COLLATE NOCASE
      ''');
    return [
      for (final r in rows)
        StrengthCategoryOption(
          id: r['id'] as String,
          name: r['name'] as String? ?? '',
          localeKey: r['locale_key'] as String?,
          color: Color((r['color'] as num?)?.toInt() ?? 0xFF757575),
        ),
    ];
  }

  // ===================================================================
  // DETAIL
  // ===================================================================

  Future<StrengthWorkoutDetail?> loadDetail(String workoutId) async {
    final workout = await _workouts.getWorkout(workoutId);
    if (workout == null) return null;
    final database = await db;

    final entries = await _workouts.getWorkoutExercises(workoutId);
    final exercises = <ExerciseWithSets>[];
    for (final entry in entries) {
      final sets = await _workouts.getExerciseSets(entry['id'] as String);
      exercises.add(
        ExerciseWithSets(
          entryId: entry['id'] as String,
          exerciseId: entry['exercise_id'] as String? ?? '',
          name: entry['exercise_name'] as String? ?? '',
          localeKey: entry['exercise_locale_key'] as String?,
          categoryId: entry['category_id'] as String?,
          categoryName: entry['category_name'] as String? ?? '',
          categoryColor: Color(entry['category_color'] as int? ?? 0xFF757575),
          exerciseType: entry['exercise_type'] as String? ?? 'weightReps',
          sets: sets,
          restTimeSeconds: (entry['rest_time_seconds'] as int?) ?? 90,
        ),
      );
    }

    final names = await _routineNames(database, workout);
    final stats = await _workouts.getWorkoutStats(workoutId);
    WorkoutStatsComparison? comparison;
    WorkoutComparable? comparable;
    String? comparableName;
    if (stats != null && workout['end_time'] != null) {
      comparable = await _workouts.findComparableWorkout(workoutId);
      if (comparable != null) {
        final previous = await _workouts.getWorkoutStats(comparable.id);
        if (previous != null) {
          final delta = WorkoutStatsComparison(
            current: stats,
            previous: previous,
          );
          if (delta.hasAnyDelta) {
            comparison = delta;
            final previousWorkout = await _workouts.getWorkout(comparable.id);
            if (previousWorkout != null) {
              final previousNames = await _routineNames(
                database,
                previousWorkout,
              );
              comparableName = previousNames.day ?? previousNames.routine;
            }
          }
        }
      }
    }

    final records = workout['end_time'] == null
        ? const <StrengthRecordEvent>[]
        : await _records.recordsInWorkout(workoutId);

    return StrengthWorkoutDetail(
      workout: workout,
      routineName: names.routine,
      dayName: names.day,
      exercises: exercises,
      stats: stats,
      comparison: comparison,
      comparable: comparison == null ? null : comparable,
      comparableName: comparableName,
      records: records,
    );
  }

  Future<({String? routine, String? day})> _routineNames(
    DatabaseExecutor database,
    Map<String, dynamic> workout,
  ) async {
    String? dayName;
    String? routineName;
    String? routineId = workout['routine_id'] as String?;
    final dayId = workout['routine_day_id'] as String?;
    if (dayId != null) {
      final rows = await database.query(
        'routine_days',
        columns: ['name', 'routine_id'],
        where: 'id = ?',
        whereArgs: [dayId],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        dayName = rows.first['name'] as String?;
        routineId ??= rows.first['routine_id'] as String?;
      }
    }
    if (routineId != null) {
      final rows = await database.query(
        'routines',
        columns: ['name'],
        where: 'id = ?',
        whereArgs: [routineId],
        limit: 1,
      );
      if (rows.isNotEmpty) routineName = rows.first['name'] as String?;
    }
    return (routine: routineName, day: dayName);
  }
}

class _Where {
  final String joins;
  final String condition;
  final List<Object?> args;

  const _Where({
    required this.joins,
    required this.condition,
    required this.args,
  });
}

class _MuscleRow {
  final String categoryId;
  final String name;
  final String? localeKey;
  final int color;
  final int entries;
  final int workingSets;
  final double volume;

  const _MuscleRow({
    required this.categoryId,
    required this.name,
    required this.localeKey,
    required this.color,
    required this.entries,
    required this.workingSets,
    required this.volume,
  });
}
