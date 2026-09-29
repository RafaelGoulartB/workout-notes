import 'dart:ui';

import 'package:workout_notes/models/exercise_with_sets.dart';
import 'package:workout_notes/models/workout_stats.dart';
import 'package:workout_notes/utils/workout_estimator.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'base_repository.dart';

double _normalizeWorkoutDecimal(double value, int decimals) =>
    double.tryParse(value.toStringAsFixed(decimals)) ?? 0;

/// What made a previous session comparable to another workout.
enum WorkoutComparisonBasis { routineDay, routine, exercises }

/// A previous finished session picked for comparison.
class WorkoutComparable {
  final String id;

  /// `yyyy-MM-dd`.
  final String date;
  final WorkoutComparisonBasis basis;

  const WorkoutComparable({
    required this.id,
    required this.date,
    required this.basis,
  });
}

/// Repository for workouts, exercise entries, and sets CRUD operations.
class WorkoutRepository extends BaseRepository {
  // ===================================================================
  // WORKOUTS
  // ===================================================================

  Future<String> createWorkout({
    DateTime? date,
    String? routineId,
    String? routineDayId,
    List<Map<String, dynamic>>? exercises,
  }) async {
    final db = await this.db;
    final id = const Uuid().v4();
    final now = DateTime.now();
    // A routine day always belongs to a routine: fill it in when the caller
    // only knows the day.
    if (routineDayId != null && routineId == null) {
      final day = await db.query(
        'routine_days',
        columns: ['routine_id'],
        where: 'id = ?',
        whereArgs: [routineDayId],
        limit: 1,
      );
      if (day.isNotEmpty) routineId = day.first['routine_id'] as String?;
    }
    await db.insert('workouts', {
      'id': id,
      'date': (date ?? now).toIso8601String().substring(0, 10),
      'is_from_routine': routineId != null ? 1 : 0,
      'routine_id': routineId,
      if (routineDayId != null && await _hasRoutineDayColumn(db))
        'routine_day_id': routineDayId,
      'created_at': now.toIso8601String(),
    });

    if (exercises != null) {
      for (int i = 0; i < exercises.length; i++) {
        final entryId = const Uuid().v4();
        await db.insert('exercise_entries', {
          'id': entryId,
          'workout_id': id,
          'exercise_id': exercises[i]['exercise_id'],
          'order_index': i,
          'notes': exercises[i]['notes'],
          'rest_time_seconds': exercises[i]['rest_time_seconds'],
        });

        final sets = exercises[i]['sets'] as List<Map<String, dynamic>>? ?? [];
        for (int j = 0; j < sets.length; j++) {
          final s = sets[j];
          await db.insert('sets', {
            'id': const Uuid().v4(),
            'exercise_entry_id': entryId,
            'weight': s['weight'],
            'reps': s['reps'],
            'distance': s['distance'],
            'time_seconds': s['time_seconds'],
            'is_complete': 0,
            'is_warmup': s['is_warmup'] ?? 0,
            'rpe': s['rpe'],
            'comment': s['comment'],
            'order_index': j,
          });
        }
      }
    }

    return id;
  }

  /// Adds an exercise entry to an existing workout.
  /// Returns the newly created entry ID.
  Future<String> addExerciseToWorkout(
    String workoutId,
    String exerciseId, {
    int? restTimeSeconds,
  }) async {
    final db = await this.db;
    final entryId = const Uuid().v4();
    final count = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM exercise_entries WHERE workout_id = ?',
            [workoutId],
          ),
        ) ??
        0;
    final rt = restTimeSeconds ?? 90;
    await db.insert('exercise_entries', {
      'id': entryId,
      'workout_id': workoutId,
      'exercise_id': exerciseId,
      'order_index': count,
      'rest_time_seconds': rt,
    });
    // Auto-populate sets from last workout for this exercise
    final lastSets = await getLastWorkoutSets(
      exerciseId,
      excludeWorkoutId: workoutId,
    );
    for (final s in lastSets) {
      final setId = const Uuid().v4();
      await db.insert('sets', {
        'id': setId,
        'exercise_entry_id': entryId,
        'weight': s['weight'],
        'reps': s['reps'],
        'distance': s['distance'],
        'time_seconds': s['time_seconds'],
        'is_complete': 0,
        'is_warmup': s['is_warmup'] ?? 0,
        'order_index': s['order_index'],
      });
    }
    return entryId;
  }

  Future<void> importRoutineDayToWorkout(
    String workoutId,
    String routineDayId,
  ) async {
    final db = await this.db;
    await _linkRoutineDay(db, workoutId, routineDayId);
    final routineExercises = await _getRoutineExercises(db, routineDayId);

    for (final re in routineExercises) {
      final entryId = const Uuid().v4();
      final count = Sqflite.firstIntValue(
            await db.rawQuery(
              'SELECT COUNT(*) FROM exercise_entries WHERE workout_id = ?',
              [workoutId],
            ),
          ) ??
          0;

      final exerciseId = re['exercise_id'] as String;
      await db.insert('exercise_entries', {
        'id': entryId,
        'workout_id': workoutId,
        'exercise_id': exerciseId,
        'order_index': count,
        'rest_time_seconds': re['rest_time_seconds'],
      });

      final lastSets = await getLastWorkoutSets(
        exerciseId,
        excludeWorkoutId: workoutId,
      );
      final sourceSets = lastSets.isNotEmpty
          ? lastSets
          : await _getPredefinedSets(db, re['id'] as String);

      for (int j = 0; j < sourceSets.length; j++) {
        final s = sourceSets[j];
        await db.insert('sets', {
          'id': const Uuid().v4(),
          'exercise_entry_id': entryId,
          'weight': s['weight'],
          'reps': s['reps'],
          'distance': s['distance'],
          'time_seconds': s['time_seconds'],
          'is_complete': 0,
          'is_warmup': s['is_warmup'] ?? 0,
          'order_index': j,
        });
      }
    }
  }

  Future<String> copyWorkoutToDate(
    String sourceWorkoutId,
    DateTime newDate,
  ) async {
    final db = await this.db;
    final sourceWorkout = await _getWorkout(db, sourceWorkoutId);
    if (sourceWorkout == null) throw Exception('Source workout not found');

    final newId = const Uuid().v4();
    final now = DateTime.now().toIso8601String();
    await db.insert('workouts', {
      'id': newId,
      'date': newDate.toIso8601String().substring(0, 10),
      'start_time': null,
      'end_time': null,
      'duration_seconds': null,
      'comment': null,
      'feeling_rating': null,
      'is_from_routine': sourceWorkout['is_from_routine'] ?? 0,
      'routine_id': sourceWorkout['routine_id'],
      if (sourceWorkout['routine_day_id'] != null)
        'routine_day_id': sourceWorkout['routine_day_id'],
      'created_at': now,
    });

    final entries = await db.query(
      'exercise_entries',
      where: 'workout_id = ?',
      whereArgs: [sourceWorkoutId],
      orderBy: 'order_index ASC',
    );

    for (final entry in entries) {
      final newEntryId = const Uuid().v4();
      await db.insert('exercise_entries', {
        'id': newEntryId,
        'workout_id': newId,
        'exercise_id': entry['exercise_id'],
        'order_index': entry['order_index'],
        'superset_group_id': entry['superset_group_id'],
        'notes': entry['notes'],
        'rest_time_seconds': entry['rest_time_seconds'],
      });

      final sets = await db.query(
        'sets',
        where: 'exercise_entry_id = ?',
        whereArgs: [entry['id']],
        orderBy: 'order_index ASC',
      );

      for (final s in sets) {
        await db.insert('sets', {
          'id': const Uuid().v4(),
          'exercise_entry_id': newEntryId,
          'weight': s['weight'],
          'reps': s['reps'],
          'distance': s['distance'],
          'time_seconds': s['time_seconds'],
          'is_complete': 0,
          'is_warmup': s['is_warmup'] ?? 0,
          'rpe': s['rpe'],
          'comment': s['comment'],
          'order_index': s['order_index'],
        });
      }
    }

    return newId;
  }

  Future<Map<String, dynamic>?> getWorkout(String id) async {
    final db = await this.db;
    final results = await db.query(
      'workouts',
      where: 'id = ?',
      whereArgs: [id],
    );
    return results.isEmpty ? null : results.first;
  }

  /// Returns workouts that are currently active (no end_time, from today,
  /// and with at least one exercise entry).
  Future<List<Map<String, dynamic>>> getActiveWorkouts() async {
    final db = await this.db;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return db.rawQuery(
      '''
      SELECT DISTINCT w.* FROM workouts w
      JOIN exercise_entries ee ON ee.workout_id = w.id
      WHERE w.end_time IS NULL AND w.date = ?
      ORDER BY w.created_at DESC
    ''',
      [today],
    );
  }

  Future<List<Map<String, dynamic>>> getWorkouts({
    DateTime? startDate,
    DateTime? endDate,
    int? limit,
    int? offset,
  }) async {
    final db = await this.db;
    var query = 'SELECT * FROM workouts WHERE 1=1';
    final args = <dynamic>[];

    if (startDate != null) {
      query += ' AND date >= ?';
      args.add(startDate.toIso8601String().substring(0, 10));
    }
    if (endDate != null) {
      query += ' AND date <= ?';
      args.add(endDate.toIso8601String().substring(0, 10));
    }

    query += ' ORDER BY date DESC, start_time DESC';

    if (limit != null) {
      query += ' LIMIT ?';
      args.add(limit);
    }
    if (offset != null) {
      query += ' OFFSET ?';
      args.add(offset);
    }

    return db.rawQuery(query, args);
  }

  Future<List<Map<String, dynamic>>> getWorkoutsByMonth(
    int year,
    int month,
  ) async {
    final db = await this.db;
    final monthStr = month.toString().padLeft(2, '0');
    return db.rawQuery(
      "SELECT * FROM workouts WHERE date LIKE ? ORDER BY date DESC",
      ['$year-$monthStr%'],
    );
  }

  /// Headline values of a month in one indexed range query. Only finished
  /// workouts count (planned or abandoned sessions are ignored) and only
  /// their completed, non-warm-up sets; volume is limited to strength
  /// (anaerobic) exercises. Workouts without any completed set are still
  /// counted as sessions.
  Future<Map<String, dynamic>> getMonthlySummary(DateTime month) async {
    final database = await db;
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    final rows = await database.rawQuery(
      '''
      SELECT
        COUNT(DISTINCT w.id) AS workout_count,
        COALESCE(SUM(CASE
          WHEN s.is_complete = 1 AND IFNULL(s.is_warmup, 0) = 0
            AND IFNULL(c.energy_system, 'anaerobic') = 'anaerobic'
          THEN COALESCE(s.weight, 0) * COALESCE(s.reps, 0) ELSE 0 END), 0)
          AS total_volume,
        COALESCE(SUM(CASE
          WHEN s.is_complete = 1 AND IFNULL(s.is_warmup, 0) = 0
          THEN COALESCE(s.distance, 0) ELSE 0 END), 0) AS cardio_distance,
        COALESCE(SUM(CASE
          WHEN s.is_complete = 1 AND IFNULL(s.is_warmup, 0) = 0
          THEN COALESCE(s.time_seconds, 0) ELSE 0 END), 0) AS cardio_time
      FROM workouts w
      LEFT JOIN exercise_entries ee ON ee.workout_id = w.id
      LEFT JOIN exercises e ON e.id = ee.exercise_id
      LEFT JOIN exercise_categories c ON c.id = e.category_id
      LEFT JOIN sets s ON s.exercise_entry_id = ee.id
      WHERE w.end_time IS NOT NULL AND w.date >= ? AND w.date < ?
      ''',
      [
        start.toIso8601String().substring(0, 10),
        end.toIso8601String().substring(0, 10),
      ],
    );
    return rows.first;
  }

  Future<Map<String, List<Map<String, dynamic>>>> getWorkoutCategoriesByDate(
    int year,
    int month,
  ) async {
    final db = await this.db;
    final monthStr = month.toString().padLeft(2, '0');
    final rows = await db.rawQuery(
      '''
      SELECT DISTINCT w.date, ec.id as category_id, ec.name as category_name, ec.color as category_color
      FROM workouts w
      JOIN exercise_entries ee ON w.id = ee.workout_id
      JOIN exercises e ON ee.exercise_id = e.id
      JOIN exercise_categories ec ON e.category_id = ec.id
      WHERE w.date LIKE ?
      ORDER BY w.date, ec.name
    ''',
      ['$year-$monthStr%'],
    );

    final Map<String, List<Map<String, dynamic>>> result = {};
    for (final row in rows) {
      final date = row['date'] as String;
      result.putIfAbsent(date, () => []).add({
        'id': row['category_id'],
        'name': row['category_name'],
        'color': row['category_color'],
      });
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> getWorkoutExercises(
    String workoutId,
  ) async {
    final db = await this.db;
    return db.rawQuery(
      'SELECT ee.*, e.name as exercise_name, e.locale_key as exercise_locale_key, e.category_id, '
      'ec.name as category_name, ec.color as category_color, ec.energy_system as category_energy, '
      'e.type as exercise_type, e.weight_increment '
      'FROM exercise_entries ee '
      'JOIN exercises e ON ee.exercise_id = e.id '
      'LEFT JOIN exercise_categories ec ON e.category_id = ec.id '
      'WHERE ee.workout_id = ? '
      'ORDER BY ee.order_index ASC',
      [workoutId],
    );
  }

  Future<List<Map<String, dynamic>>> getExerciseSets(
    String exerciseEntryId,
  ) async {
    final db = await this.db;
    return db.query(
      'sets',
      where: 'exercise_entry_id = ?',
      whereArgs: [exerciseEntryId],
      orderBy: 'order_index ASC',
    );
  }

  Future<WorkoutStats?> getWorkoutStats(String workoutId) async {
    final db = await this.db;
    final workout = await _getWorkout(db, workoutId);
    if (workout == null) return null;

    final entries = await getWorkoutExercises(workoutId);
    final inputs = <WorkoutStatsExerciseInput>[];
    for (final entry in entries) {
      if ((entry['exercise_type'] as String?) != 'weightReps') continue;
      final sets = await getExerciseSets(entry['id'] as String);
      inputs.add(
        WorkoutStatsExerciseInput(
          exerciseId: entry['exercise_id'] as String? ?? '',
          name: entry['exercise_name'] as String? ?? '',
          localeKey: entry['exercise_locale_key'] as String?,
          categoryId: entry['category_id'] as String?,
          categoryName: entry['category_name'] as String? ?? '',
          categoryColor: Color(entry['category_color'] as int? ?? 0xFF757575),
          sets: sets
              .map(
                (set) => WorkoutStatsSetInput(
                  weight: (set['weight'] as num?)?.toDouble() ?? 0,
                  reps: (set['reps'] as int?) ?? 0,
                  isComplete: (set['is_complete'] as int?) == 1,
                  isWarmup: (set['is_warmup'] as int?) == 1,
                  rpe: (set['rpe'] as num?)?.toDouble(),
                ),
              )
              .toList(),
        ),
      );
    }

    return WorkoutStats.calculate(
      workoutId: workoutId,
      durationSeconds: (workout['duration_seconds'] as int?) ?? 0,
      estimatedCalories: (workout['estimated_calories'] as num?)?.toDouble(),
      exercises: inputs,
    );
  }

  Future<WorkoutStatsComparison?> getWorkoutStatsComparison(
    String workoutId,
  ) async {
    final db = await this.db;
    final current = await getWorkoutStats(workoutId);
    if (current == null) return null;

    final comparableWorkoutId = await _findComparableWorkoutId(db, workoutId);
    if (comparableWorkoutId == null) return null;

    final previous = await getWorkoutStats(comparableWorkoutId);
    if (previous == null) return null;

    return WorkoutStatsComparison(current: current, previous: previous);
  }

  Future<String?> _findComparableWorkoutId(
    Database db,
    String workoutId,
  ) async => (await _findComparableWorkout(db, workoutId))?.id;

  /// The previous finished session to compare [workoutId] against: the same
  /// routine day when known, else the same routine, else the finished workout
  /// sharing the most exercises.
  Future<WorkoutComparable?> findComparableWorkout(String workoutId) async =>
      _findComparableWorkout(await db, workoutId);

  Future<WorkoutComparable?> _findComparableWorkout(
    Database db,
    String workoutId,
  ) async {
    final workout = await _getWorkout(db, workoutId);
    if (workout == null) return null;

    final routineId = workout['routine_id'] as String?;
    final routineDayId = workout['routine_day_id'] as String?;
    final currentDate = workout['date'] as String? ?? '';
    final currentMoment = (workout['end_time'] as String?) ??
        (workout['start_time'] as String?) ??
        (workout['created_at'] as String?) ??
        '';

    Future<WorkoutComparable?> previousBy(
      String column,
      String value,
      WorkoutComparisonBasis basis,
    ) async {
      final rows = await db.rawQuery(
        '''
        SELECT id, date
        FROM workouts
        WHERE id != ?
          AND $column = ?
          AND end_time IS NOT NULL
          AND (
            date < ?
            OR (date = ? AND COALESCE(end_time, start_time, created_at, '') < ?)
          )
        ORDER BY date DESC, end_time DESC, created_at DESC
        LIMIT 1
      ''',
        [workoutId, value, currentDate, currentDate, currentMoment],
      );
      if (rows.isEmpty) return null;
      return WorkoutComparable(
        id: rows.first['id'] as String,
        date: rows.first['date'] as String? ?? '',
        basis: basis,
      );
    }

    if (routineDayId != null && routineDayId.isNotEmpty) {
      final byDay = await previousBy(
        'routine_day_id',
        routineDayId,
        WorkoutComparisonBasis.routineDay,
      );
      if (byDay != null) return byDay;
    }
    if (routineId != null && routineId.isNotEmpty) {
      final byRoutine = await previousBy(
        'routine_id',
        routineId,
        WorkoutComparisonBasis.routine,
      );
      if (byRoutine != null) return byRoutine;
    }

    final currentExerciseRows = await db.rawQuery(
      '''
      SELECT DISTINCT exercise_id
      FROM exercise_entries
      WHERE workout_id = ?
    ''',
      [workoutId],
    );
    final exerciseIds = currentExerciseRows
        .map((row) => row['exercise_id'] as String)
        .toList(growable: false);
    if (exerciseIds.isEmpty) return null;

    final placeholders = List.filled(exerciseIds.length, '?').join(',');
    final args = <Object?>[
      workoutId,
      currentDate,
      currentDate,
      currentMoment,
      ...exerciseIds,
    ];
    final rows = await db.rawQuery('''
      SELECT w.id, w.date, COUNT(DISTINCT ee.exercise_id) as shared_count
      FROM workouts w
      JOIN exercise_entries ee ON ee.workout_id = w.id
      WHERE w.id != ?
        AND w.end_time IS NOT NULL
        AND (
          w.date < ?
          OR (w.date = ? AND COALESCE(w.end_time, w.start_time, w.created_at, '') < ?)
        )
        AND ee.exercise_id IN ($placeholders)
      GROUP BY w.id
      HAVING shared_count > 0
      ORDER BY shared_count DESC, w.date DESC, w.end_time DESC, w.created_at DESC
      LIMIT 1
    ''', args);
    if (rows.isEmpty) return null;
    return WorkoutComparable(
      id: rows.first['id'] as String,
      date: rows.first['date'] as String? ?? '',
      basis: WorkoutComparisonBasis.exercises,
    );
  }

  Future<List<ExerciseVolumeComparison>> getExerciseVolumeComparisons(
    String workoutId,
  ) async {
    final db = await this.db;
    final exerciseRows = await db.rawQuery(
      '''
      SELECT DISTINCT e.id as exercise_id
      FROM exercise_entries ee
      JOIN exercises e ON ee.exercise_id = e.id
      WHERE ee.workout_id = ? AND e.type = 'weightReps'
      ORDER BY ee.order_index ASC
    ''',
      [workoutId],
    );

    final comparisons = <ExerciseVolumeComparison>[];
    for (final row in exerciseRows) {
      final exerciseId = row['exercise_id'] as String;
      final currentVolume = await _getWorkoutExerciseVolume(
        db,
        workoutId,
        exerciseId,
        completedOnly: false,
      );
      final lastVolume = await _getLastCompletedExerciseVolume(
        db,
        exerciseId,
        workoutId,
      );
      comparisons.add(
        ExerciseVolumeComparison(
          exerciseId: exerciseId,
          currentVolume: currentVolume,
          lastVolume: lastVolume,
        ),
      );
    }
    return comparisons;
  }

  Future<List<CategoryVolumeComparison>> getCategoryVolumeComparisons(
    String workoutId,
  ) async {
    final db = await this.db;
    final exerciseRows = await db.rawQuery(
      '''
      SELECT DISTINCT e.id as exercise_id, ec.id as category_id,
        ec.name as category_name, ec.color as category_color
      FROM exercise_entries ee
      JOIN exercises e ON ee.exercise_id = e.id
      LEFT JOIN exercise_categories ec ON e.category_id = ec.id
      WHERE ee.workout_id = ? AND e.type = 'weightReps'
      ORDER BY ec.name ASC
    ''',
      [workoutId],
    );

    final grouped = <String, _CategoryVolumeAccumulator>{};
    for (final row in exerciseRows) {
      final exerciseId = row['exercise_id'] as String;
      final categoryId = row['category_id'] as String? ?? '';
      final acc = grouped.putIfAbsent(
        categoryId,
        () => _CategoryVolumeAccumulator(
          categoryId: categoryId,
          categoryName: row['category_name'] as String? ?? '',
          categoryColor: Color(row['category_color'] as int? ?? 0xFF757575),
        ),
      );
      acc.currentVolume += await _getWorkoutExerciseVolume(
        db,
        workoutId,
        exerciseId,
        completedOnly: false,
      );
      acc.lastVolume += await _getLastCompletedExerciseVolume(
        db,
        exerciseId,
        workoutId,
      );
    }

    final comparisons = grouped.values
        .where((acc) => acc.currentVolume > 0 || acc.lastVolume > 0)
        .map(
          (acc) => CategoryVolumeComparison(
            categoryId: acc.categoryId,
            categoryName: acc.categoryName,
            categoryColor: acc.categoryColor,
            currentVolume: acc.currentVolume,
            lastVolume: acc.lastVolume,
          ),
        )
        .toList();
    comparisons.sort((a, b) {
      final byCurrent = b.currentVolume.compareTo(a.currentVolume);
      if (byCurrent != 0) return byCurrent;
      return b.lastVolume.compareTo(a.lastVolume);
    });
    return comparisons;
  }

  Future<double> _getWorkoutExerciseVolume(
    Database db,
    String workoutId,
    String exerciseId, {
    required bool completedOnly,
  }) async {
    final completeFilter = completedOnly ? 'AND s.is_complete = 1' : '';
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(s.weight * s.reps), 0) as volume
      FROM sets s
      JOIN exercise_entries ee ON s.exercise_entry_id = ee.id
      JOIN exercises e ON ee.exercise_id = e.id
      WHERE ee.workout_id = ? AND ee.exercise_id = ?
        AND e.type = 'weightReps'
        $completeFilter
        AND s.is_warmup = 0
        AND s.weight IS NOT NULL
        AND s.reps IS NOT NULL
    ''',
      [workoutId, exerciseId],
    );
    return (rows.first['volume'] as num?)?.toDouble() ?? 0;
  }

  Future<double> _getLastCompletedExerciseVolume(
    Database db,
    String exerciseId,
    String excludeWorkoutId,
  ) async {
    final lastWorkout = await db.rawQuery(
      '''
      SELECT w.id
      FROM workouts w
      JOIN exercise_entries ee ON ee.workout_id = w.id
      JOIN exercises e ON ee.exercise_id = e.id
      WHERE ee.exercise_id = ?
        AND w.id != ?
        AND w.end_time IS NOT NULL
        AND e.type = 'weightReps'
      ORDER BY w.date DESC, w.end_time DESC, w.start_time DESC
      LIMIT 1
    ''',
      [exerciseId, excludeWorkoutId],
    );
    if (lastWorkout.isEmpty) return 0;

    return _getWorkoutExerciseVolume(
      db,
      lastWorkout.first['id'] as String,
      exerciseId,
      completedOnly: true,
    );
  }

  Future<void> finishWorkout(
    String id, {
    String? comment,
    int? feelingRating,
    double? estimatedCalories,
  }) async {
    final db = await this.db;
    final now = DateTime.now();
    final workout = await getWorkout(id);
    if (workout == null) return;

    int duration = 0;
    final startTimeStr = workout['start_time'] as String?;
    if (startTimeStr != null) {
      final startTime = DateTime.parse(startTimeStr);
      duration = now.difference(startTime).inSeconds;
    }

    final calories = estimatedCalories ??
        await _estimateCaloriesForWorkout(db, id, durationSeconds: duration);

    await db.update(
      'workouts',
      {
        'end_time': now.toIso8601String(),
        'duration_seconds': duration,
        'estimated_calories': calories,
        'start_time': startTimeStr ?? now.toIso8601String(),
        'comment': comment,
        'feeling_rating': feelingRating,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Provides a persistence-level fallback so every workout completion flow
  /// uses the same calorie estimate, including future callers.
  Future<double?> _estimateCaloriesForWorkout(
    Database db,
    String workoutId, {
    required int durationSeconds,
  }) async {
    final weightRows = await db.query(
      'body_measurements',
      columns: ['value', 'unit'],
      where: 'type = ?',
      whereArgs: ['weight'],
      orderBy: 'date DESC, created_at DESC',
      limit: 1,
    );
    if (weightRows.isEmpty) return null;

    final weightValue = (weightRows.first['value'] as num?)?.toDouble();
    if (weightValue == null || weightValue <= 0) return null;
    final unit = (weightRows.first['unit'] as String? ?? 'kg').toLowerCase();
    final double bodyWeightKg;
    if (unit == 'kg' || unit.isEmpty) {
      bodyWeightKg = weightValue;
    } else if (unit == 'lb' ||
        unit == 'lbs' ||
        unit == 'pound' ||
        unit == 'pounds') {
      bodyWeightKg = weightValue * 0.45359237;
    } else {
      return null;
    }

    var calorieDurationSeconds = durationSeconds;
    if (calorieDurationSeconds <= 0) {
      final entries = await db.query(
        'exercise_entries',
        columns: ['id', 'rest_time_seconds'],
        where: 'workout_id = ?',
        whereArgs: [workoutId],
        orderBy: 'order_index ASC',
      );
      final exercises = <WorkoutEstimateExercise>[];
      for (final entry in entries) {
        final sets = await db.query(
          'sets',
          columns: ['reps', 'time_seconds'],
          where: 'exercise_entry_id = ?',
          whereArgs: [entry['id']],
          orderBy: 'order_index ASC',
        );
        exercises.add(
          WorkoutEstimateExercise(
            restTimeSeconds: (entry['rest_time_seconds'] as num?)?.toInt(),
            sets: sets
                .map(
                  (set) => WorkoutEstimateSet(
                    reps: (set['reps'] as num?)?.toInt(),
                    timeSeconds: (set['time_seconds'] as num?)?.toInt(),
                  ),
                )
                .toList(growable: false),
          ),
        );
      }
      calorieDurationSeconds =
          WorkoutEstimateCalculator.estimateDurationSeconds(exercises);
    }

    return WorkoutEstimateCalculator.estimateCalories(
      durationSeconds: calorieDurationSeconds,
      bodyWeightKg: bodyWeightKg,
    );
  }

  Future<void> startWorkoutTimer(String id) async {
    final db = await this.db;
    final now = DateTime.now().toIso8601String();
    await db.update(
      'workouts',
      {'start_time': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> stopWorkoutTimer(String id) async {
    final db = await this.db;
    final now = DateTime.now();
    final workout = await getWorkout(id);
    if (workout == null) return;
    final startTimeStr = workout['start_time'] as String?;
    int duration = 0;
    if (startTimeStr != null) {
      final startTime = DateTime.parse(startTimeStr);
      duration = now.difference(startTime).inSeconds;
    }
    await db.update(
      'workouts',
      {
        'end_time': now.toIso8601String(),
        'duration_seconds': duration,
        'start_time': startTimeStr ?? now.toIso8601String(),
        'pause_start_time': null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> resetWorkoutTimer(String id) async {
    final db = await this.db;
    await db.update(
      'workouts',
      {
        'start_time': null,
        'end_time': null,
        'duration_seconds': null,
        'pause_start_time': null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Persists the workout pause start time.
  Future<void> setWorkoutPause(String id, DateTime pauseStart) async {
    final db = await this.db;
    await db.update(
      'workouts',
      {'pause_start_time': pauseStart.toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Clears the pause state and shifts the start time forward by the
  /// accumulated pause duration, so the elapsed time excludes the pause.
  Future<void> clearWorkoutPause(String id, DateTime newStartTime) async {
    final db = await this.db;
    await db.update(
      'workouts',
      {'pause_start_time': null, 'start_time': newStartTime.toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateWorkoutDate(String id, DateTime newDate) async {
    final db = await this.db;
    await db.update(
      'workouts',
      {'date': newDate.toIso8601String().substring(0, 10)},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateWorkoutFeedback(
    String id, {
    required String? comment,
    required int? feelingRating,
  }) async {
    final db = await this.db;
    await db.update(
      'workouts',
      {'comment': comment, 'feeling_rating': feelingRating},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Persists user-edited start/end timestamps for a completed workout and
  /// recomputes the cached `duration_seconds`. Any in-progress pause state
  /// is cleared so the new times are not double-counted.
  Future<void> updateWorkoutTimes(
    String id, {
    required DateTime? startTime,
    required DateTime? endTime,
  }) async {
    final db = await this.db;
    int? duration;
    if (startTime != null && endTime != null) {
      final diff = endTime.difference(startTime).inSeconds;
      duration = diff > 0 ? diff : 0;
    }
    await db.update(
      'workouts',
      {
        'start_time': startTime?.toIso8601String(),
        'end_time': endTime?.toIso8601String(),
        'duration_seconds': duration,
        'pause_start_time': null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> resetWorkoutToInProgress(String id) async {
    final db = await this.db;
    await db.update(
      'workouts',
      {'end_time': null, 'duration_seconds': null},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteWorkout(String id) async {
    final db = await this.db;
    await db.delete('workouts', where: 'id = ?', whereArgs: [id]);
  }

  /// Removes a workout only if it is still an untouched blank session: not
  /// finished, no exercises and no notes. Returns whether it was deleted.
  /// Deletes a workout that was prefilled (from a routine) but never used:
  /// not started, not finished, no set completed and no feedback. Leaving the
  /// screen of such a draft must not keep it around as "in progress".
  Future<bool> deleteUntouchedDraft(String id) async {
    final db = await this.db;
    return db.transaction((txn) async {
      final rows = await txn.rawQuery(
        '''
        SELECT 1 FROM workouts w
        WHERE w.id = ? AND w.end_time IS NULL AND w.start_time IS NULL
          AND IFNULL(w.comment, '') = '' AND w.feeling_rating IS NULL
          AND NOT EXISTS (
            SELECT 1 FROM sets s
            JOIN exercise_entries ee ON ee.id = s.exercise_entry_id
            WHERE ee.workout_id = w.id AND IFNULL(s.is_complete, 0) = 1)
        ''',
        [id],
      );
      if (rows.isEmpty) return false;
      await txn.rawDelete(
        'DELETE FROM sets WHERE exercise_entry_id IN '
        '(SELECT id FROM exercise_entries WHERE workout_id = ?)',
        [id],
      );
      await txn.delete(
        'exercise_entries',
        where: 'workout_id = ?',
        whereArgs: [id],
      );
      await txn.delete('workouts', where: 'id = ?', whereArgs: [id]);
      return true;
    });
  }

  Future<bool> deleteIfBlank(String id) async {
    final db = await this.db;
    final removed = await db.delete(
      'workouts',
      where: '''
        id = ? AND end_time IS NULL
        AND IFNULL(comment, '') = ''
        AND NOT EXISTS (
          SELECT 1 FROM exercise_entries WHERE workout_id = workouts.id)
      ''',
      whereArgs: [id],
    );
    return removed > 0;
  }

  /// Cleans up blank sessions abandoned by older versions (a new workout used
  /// to be inserted immediately). Only touches unfinished, non-routine,
  /// empty workouts dated today or earlier, never planned future ones.
  Future<int> deleteAbandonedBlankWorkouts({String? exceptId}) async {
    final db = await this.db;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return db.delete(
      'workouts',
      where: '''
        end_time IS NULL AND date <= ?
        AND IFNULL(is_from_routine, 0) = 0
        AND IFNULL(comment, '') = ''
        AND feeling_rating IS NULL
        AND NOT EXISTS (
          SELECT 1 FROM exercise_entries WHERE workout_id = workouts.id)
        ${exceptId == null ? '' : 'AND id != ?'}
      ''',
      whereArgs: [today, ?exceptId],
    );
  }

  // ===================================================================
  // SETS
  // ===================================================================

  Future<String> addSet({
    required String exerciseEntryId,
    double? weight,
    int? reps,
    double? distance,
    int? timeSeconds,
    bool isWarmup = false,
    double? rpe,
    String? comment,
  }) async {
    final db = await this.db;
    final id = const Uuid().v4();
    final count = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM sets WHERE exercise_entry_id = ?',
            [exerciseEntryId],
          ),
        ) ??
        0;

    await db.insert('sets', {
      'id': id,
      'exercise_entry_id': exerciseEntryId,
      'weight': weight,
      'reps': reps,
      'distance': distance,
      'time_seconds': timeSeconds,
      'is_complete': 0,
      'is_warmup': isWarmup ? 1 : 0,
      'rpe': rpe,
      'comment': comment,
      'order_index': count,
    });
    return id;
  }

  Future<void> updateSet(
    String setId, {
    double? weight,
    int? reps,
    double? distance,
    int? timeSeconds,
    bool? isComplete,
    bool? isWarmup,
    double? rpe,
    String? comment,
  }) async {
    final db = await this.db;
    final updates = <String, dynamic>{};
    if (weight != null) {
      updates['weight'] = _normalizeWorkoutDecimal(weight, 2);
    }
    if (reps != null) updates['reps'] = reps;
    if (distance != null) {
      updates['distance'] = _normalizeWorkoutDecimal(distance, 2);
    }
    if (timeSeconds != null) updates['time_seconds'] = timeSeconds;
    if (isComplete != null) updates['is_complete'] = isComplete ? 1 : 0;
    if (isWarmup != null) updates['is_warmup'] = isWarmup ? 1 : 0;
    if (rpe != null) updates['rpe'] = _normalizeWorkoutDecimal(rpe, 1);
    if (comment != null) updates['comment'] = comment;

    if (updates.isNotEmpty) {
      await db.update('sets', updates, where: 'id = ?', whereArgs: [setId]);
    }
  }

  Future<void> toggleSetComplete(String setId) async {
    final db = await this.db;
    final result = await db.query('sets', where: 'id = ?', whereArgs: [setId]);
    if (result.isEmpty) return;
    final current = (result.first['is_complete'] as int?) ?? 0;
    await db.update(
      'sets',
      {'is_complete': current == 0 ? 1 : 0},
      where: 'id = ?',
      whereArgs: [setId],
    );
  }

  Future<void> deleteSet(String setId) async {
    final db = await this.db;
    await db.delete('sets', where: 'id = ?', whereArgs: [setId]);
  }

  Future<void> removeExerciseEntryFromWorkout(
    String workoutId,
    String exerciseId,
  ) async {
    final db = await this.db;
    final entries = await db.query(
      'exercise_entries',
      where: 'workout_id = ? AND exercise_id = ?',
      whereArgs: [workoutId, exerciseId],
    );
    for (final entry in entries) {
      final entryId = entry['id'] as String;
      await db.delete(
        'sets',
        where: 'exercise_entry_id = ?',
        whereArgs: [entryId],
      );
      await db.delete(
        'exercise_entries',
        where: 'id = ?',
        whereArgs: [entryId],
      );
    }
  }

  /// Persists a new ordering of exercise entries for a workout.
  /// The list [orderedEntryIds] must contain the IDs of every exercise_entry
  /// currently belonging to [workoutId] in the desired order.
  /// Performed in a single batch transaction.
  Future<void> reorderWorkoutExercises(
    String workoutId,
    List<String> orderedEntryIds,
  ) async {
    final db = await this.db;
    final batch = db.batch();
    for (int i = 0; i < orderedEntryIds.length; i++) {
      batch.update(
        'exercise_entries',
        {'order_index': i},
        where: 'id = ? AND workout_id = ?',
        whereArgs: [orderedEntryIds[i], workoutId],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> deleteExerciseEntry(String entryId) async {
    final db = await this.db;
    await db.delete(
      'sets',
      where: 'exercise_entry_id = ?',
      whereArgs: [entryId],
    );
    await db.delete('exercise_entries', where: 'id = ?', whereArgs: [entryId]);
  }

  Future<void> updateExerciseEntryRestTime(
    String exerciseEntryId,
    int restTimeSeconds,
  ) async {
    final db = await this.db;
    await db.update(
      'exercise_entries',
      {'rest_time_seconds': restTimeSeconds},
      where: 'id = ?',
      whereArgs: [exerciseEntryId],
    );
  }

  Future<List<Map<String, dynamic>>> getLastWorkoutSets(
    String exerciseId, {
    String? excludeWorkoutId,
  }) async {
    final db = await this.db;

    String where = 'ee.exercise_id = ?';
    final args = <dynamic>[exerciseId];
    if (excludeWorkoutId != null) {
      where += ' AND w.id != ?';
      args.add(excludeWorkoutId);
    }
    final lastWid = await db.rawQuery('''
      SELECT ee.workout_id FROM exercise_entries ee
      JOIN workouts w ON ee.workout_id = w.id
      WHERE $where
      ORDER BY w.date DESC, w.start_time DESC
      LIMIT 1
    ''', args);

    if (lastWid.isEmpty) return [];
    final workoutId = lastWid.first['workout_id'] as String;

    return db.rawQuery(
      '''
      SELECT s.* FROM sets s
      JOIN exercise_entries ee ON s.exercise_entry_id = ee.id
      WHERE ee.exercise_id = ? AND ee.workout_id = ?
      ORDER BY s.order_index ASC
    ''',
      [exerciseId, workoutId],
    );
  }

  // ===================================================================
  // INTERNAL HELPERS (used by importRoutineDayToWorkout)

  /// Older test schemas and partially migrated databases lack the v54
  /// `workouts.routine_day_id` column.
  Future<bool> _hasRoutineDayColumn(DatabaseExecutor db) async {
    final columns = await db.rawQuery('PRAGMA table_info(workouts)');
    return columns.any((c) => c['name'] == 'routine_day_id');
  }

  /// Records which routine day (and routine) a workout trains. Keeps an
  /// existing link: importing a second day into the same session does not
  /// relabel it.
  Future<void> _linkRoutineDay(
    DatabaseExecutor db,
    String workoutId,
    String routineDayId,
  ) async {
    if (!await _hasRoutineDayColumn(db)) return;
    final day = await db.query(
      'routine_days',
      columns: ['routine_id'],
      where: 'id = ?',
      whereArgs: [routineDayId],
      limit: 1,
    );
    await db.rawUpdate(
      '''
      UPDATE workouts SET
        routine_day_id = COALESCE(routine_day_id, ?),
        routine_id = COALESCE(routine_id, ?),
        is_from_routine = 1
      WHERE id = ?
      ''',
      [routineDayId, day.isEmpty ? null : day.first['routine_id'], workoutId],
    );
  }
  // ===================================================================

  Future<List<Map<String, dynamic>>> _getRoutineExercises(
    Database db,
    String routineDayId,
  ) async {
    return db.rawQuery(
      '''
      SELECT re.*, e.name as exercise_name, e.locale_key as exercise_locale_key, e.category_id,
      ec.name as category_name, ec.color as category_color, e.type as exercise_type
      FROM routine_exercises re
      JOIN exercises e ON re.exercise_id = e.id
      LEFT JOIN exercise_categories ec ON e.category_id = ec.id
      WHERE re.routine_day_id = ?
      ORDER BY re.order_index ASC
    ''',
      [routineDayId],
    );
  }

  Future<List<Map<String, dynamic>>> _getPredefinedSets(
    Database db,
    String routineExerciseId,
  ) async {
    return db.query(
      'predefined_sets',
      where: 'routine_exercise_id = ?',
      whereArgs: [routineExerciseId],
      orderBy: 'order_index ASC',
    );
  }

  Future<Map<String, dynamic>?> _getWorkout(Database db, String id) async {
    final results = await db.query(
      'workouts',
      where: 'id = ?',
      whereArgs: [id],
    );
    return results.isEmpty ? null : results.first;
  }
}

class _CategoryVolumeAccumulator {
  final String categoryId;
  final String categoryName;
  final Color categoryColor;
  double currentVolume = 0;
  double lastVolume = 0;

  _CategoryVolumeAccumulator({
    required this.categoryId,
    required this.categoryName,
    required this.categoryColor,
  });
}
