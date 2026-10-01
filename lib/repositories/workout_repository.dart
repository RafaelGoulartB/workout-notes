import 'dart:ui';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:workout_notes/models/workout_stats.dart';
import 'package:workout_notes/repositories/base_repository.dart';
import 'package:workout_notes/utils/date_utils.dart';
import 'package:workout_notes/utils/workout_estimator.dart';

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

  /// Creates a workout with its exercise entries and sets in one transaction,
  /// so a failure never leaves a half-built session behind.
  Future<String> createWorkout({
    DateTime? date,
    String? routineId,
    String? routineDayId,
    List<Map<String, dynamic>>? exercises,
  }) async {
    final db = await this.db;
    return db.transaction(
      (txn) => createWorkoutIn(
        txn,
        date: date,
        routineId: routineId,
        routineDayId: routineDayId,
        exercises: exercises,
      ),
    );
  }

  /// [createWorkout] on an explicit executor (callers fold it into their own
  /// transaction). A caller-supplied [id] becomes the workout's primary key.
  Future<String> createWorkoutIn(
    DatabaseExecutor txn, {
    String? id,
    DateTime? date,
    String? routineId,
    String? routineDayId,
    List<Map<String, dynamic>>? exercises,
  }) async {
    id ??= const Uuid().v4();
    final now = DateTime.now();
    // A routine day always belongs to a routine: fill it in when the caller
    // only knows the day.
    if (routineDayId != null && routineId == null) {
      final day = await txn.query(
        'routine_days',
        columns: ['routine_id'],
        where: 'id = ?',
        whereArgs: [routineDayId],
        limit: 1,
      );
      if (day.isNotEmpty) routineId = day.first['routine_id'] as String?;
    }
    final batch = txn.batch();
    batch.insert('workouts', {
      'id': id,
      'date': dateKey(date ?? now),
      'is_from_routine': routineId != null ? 1 : 0,
      'routine_id': routineId,
      'routine_day_id': ?routineDayId,
      'created_at': now.toIso8601String(),
    });
    for (int i = 0; i < (exercises?.length ?? 0); i++) {
      final exercise = exercises![i];
      final entryId = const Uuid().v4();
      batch.insert('exercise_entries', {
        'id': entryId,
        'workout_id': id,
        'exercise_id': exercise['exercise_id'],
        'order_index': i,
        'notes': exercise['notes'],
        'rest_time_seconds': exercise['rest_time_seconds'],
      });
      final sets = exercise['sets'] as List<Map<String, dynamic>>? ?? [];
      for (int j = 0; j < sets.length; j++) {
        final s = sets[j];
        batch.insert('sets', {
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
    await batch.commit(noResult: true);
    return id;
  }

  /// Adds an exercise entry to an existing workout, pre-filled with the sets
  /// of its last session, in one transaction.
  /// Returns the newly created entry ID.
  Future<String> addExerciseToWorkout(
    String workoutId,
    String exerciseId, {
    int? restTimeSeconds,
  }) async {
    final db = await this.db;
    final entryId = const Uuid().v4();
    await db.transaction((txn) async {
      final count = await _entryCount(txn, workoutId);
      final batch = txn.batch();
      batch.insert('exercise_entries', {
        'id': entryId,
        'workout_id': workoutId,
        'exercise_id': exerciseId,
        'order_index': count,
        'rest_time_seconds': restTimeSeconds ?? 90,
      });
      // Auto-populate sets from last workout for this exercise
      final lastSets = await _lastWorkoutSets(
        txn,
        exerciseId,
        excludeWorkoutId: workoutId,
      );
      for (final s in lastSets) {
        batch.insert('sets', {
          'id': const Uuid().v4(),
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
      await batch.commit(noResult: true);
    });
    return entryId;
  }

  /// Copies the exercises of a routine day into a workout (with the sets of
  /// each exercise's last session, else the routine's preset sets) in one
  /// transaction.
  Future<void> importRoutineDayToWorkout(
    String workoutId,
    String routineDayId,
  ) async {
    final db = await this.db;
    await db.transaction(
      (txn) => importRoutineDayToWorkoutIn(txn, workoutId, routineDayId),
    );
  }

  /// [importRoutineDayToWorkout] on an explicit executor.
  Future<void> importRoutineDayToWorkoutIn(
    DatabaseExecutor txn,
    String workoutId,
    String routineDayId,
  ) async {
    await _linkRoutineDay(txn, workoutId, routineDayId);
    final routineExercises = await _getRoutineExercises(txn, routineDayId);
    final firstOrder = await _entryCount(txn, workoutId);
    final batch = txn.batch();

    for (var i = 0; i < routineExercises.length; i++) {
      final re = routineExercises[i];
      final entryId = const Uuid().v4();
      final exerciseId = re['exercise_id'] as String;
      batch.insert('exercise_entries', {
        'id': entryId,
        'workout_id': workoutId,
        'exercise_id': exerciseId,
        'order_index': firstOrder + i,
        'rest_time_seconds': re['rest_time_seconds'],
      });

      final lastSets = await _lastWorkoutSets(
        txn,
        exerciseId,
        excludeWorkoutId: workoutId,
      );
      final sourceSets = lastSets.isNotEmpty
          ? lastSets
          : await _getPredefinedSets(txn, re['id'] as String);

      for (int j = 0; j < sourceSets.length; j++) {
        final s = sourceSets[j];
        batch.insert('sets', {
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
    await batch.commit(noResult: true);
  }

  /// Copies a workout (entries and sets, all unchecked) to [newDate] in one
  /// transaction and returns the new workout id.
  Future<String> copyWorkoutToDate(
    String sourceWorkoutId,
    DateTime newDate,
  ) async {
    final db = await this.db;
    return db.transaction(
      (txn) => copyWorkoutToDateIn(txn, sourceWorkoutId, newDate),
    );
  }

  /// [copyWorkoutToDate] on an explicit executor. A caller-supplied [newId]
  /// becomes the copy's primary key.
  Future<String> copyWorkoutToDateIn(
    DatabaseExecutor txn,
    String sourceWorkoutId,
    DateTime newDate, {
    String? newId,
  }) async {
    newId ??= const Uuid().v4();
    final sourceWorkout = await _getWorkout(txn, sourceWorkoutId);
    if (sourceWorkout == null) throw Exception('Source workout not found');

    final entries = await txn.query(
      'exercise_entries',
      where: 'workout_id = ?',
      whereArgs: [sourceWorkoutId],
      orderBy: 'order_index ASC',
    );
    final setsByEntry = <Object?, List<Map<String, Object?>>>{};
    if (entries.isNotEmpty) {
      final sets = await txn.query(
        'sets',
        where:
            'exercise_entry_id IN '
            '(${List.filled(entries.length, '?').join(', ')})',
        whereArgs: [for (final entry in entries) entry['id']],
        orderBy: 'order_index ASC',
      );
      for (final set in sets) {
        setsByEntry.putIfAbsent(set['exercise_entry_id'], () => []).add(set);
      }
    }

    final batch = txn.batch();
    batch.insert('workouts', {
      'id': newId,
      'date': dateKey(newDate),
      'start_time': null,
      'end_time': null,
      'duration_seconds': null,
      'comment': null,
      'feeling_rating': null,
      'is_from_routine': sourceWorkout['is_from_routine'] ?? 0,
      'routine_id': sourceWorkout['routine_id'],
      'routine_day_id': ?sourceWorkout['routine_day_id'],
      'created_at': DateTime.now().toIso8601String(),
    });
    for (final entry in entries) {
      final newEntryId = const Uuid().v4();
      batch.insert('exercise_entries', {
        'id': newEntryId,
        'workout_id': newId,
        'exercise_id': entry['exercise_id'],
        'order_index': entry['order_index'],
        'superset_group_id': entry['superset_group_id'],
        'notes': entry['notes'],
        'rest_time_seconds': entry['rest_time_seconds'],
      });
      for (final s in setsByEntry[entry['id']] ??
          const <Map<String, Object?>>[]) {
        batch.insert('sets', {
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
    await batch.commit(noResult: true);
    return newId;
  }

  /// [getWorkout] on an explicit executor.
  Future<Map<String, dynamic>?> getWorkoutIn(
    DatabaseExecutor executor,
    String id,
  ) => _getWorkout(executor, id);

  /// Moves a still-planned workout (not started, not finished) to [newDate] on
  /// [executor]. Returns the number of rows changed: 0 means the workout is
  /// missing or was started/finished in the meantime.
  Future<int> reschedulePlannedWorkoutIn(
    DatabaseExecutor executor,
    String id,
    DateTime newDate,
  ) => executor.update(
    'workouts',
    {'date': dateKey(newDate)},
    where: 'id = ? AND start_time IS NULL AND end_time IS NULL',
    whereArgs: [id],
  );

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
    final today = dateKey(DateTime.now());
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
    final currentMoment =
        (workout['end_time'] as String?) ??
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

    final calories =
        estimatedCalories ??
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
      // One joined read instead of a sets query per entry.
      final rows = await db.rawQuery(
        '''
        SELECT ee.id AS entry_id, ee.rest_time_seconds AS rest_time_seconds,
               s.id AS set_id, s.reps AS reps, s.time_seconds AS time_seconds
        FROM exercise_entries ee
        LEFT JOIN sets s ON s.exercise_entry_id = ee.id
        WHERE ee.workout_id = ?
        ORDER BY ee.order_index ASC, s.order_index ASC
        ''',
        [workoutId],
      );
      final restByEntry = <String, int?>{};
      final setsByEntry = <String, List<WorkoutEstimateSet>>{};
      for (final row in rows) {
        final entryId = row['entry_id'] as String;
        restByEntry[entryId] = (row['rest_time_seconds'] as num?)?.toInt();
        final sets = setsByEntry.putIfAbsent(entryId, () => []);
        if (row['set_id'] != null) {
          sets.add(
            WorkoutEstimateSet(
              reps: (row['reps'] as num?)?.toInt(),
              timeSeconds: (row['time_seconds'] as num?)?.toInt(),
            ),
          );
        }
      }
      final exercises = [
        for (final entryId in restByEntry.keys)
          WorkoutEstimateExercise(
            restTimeSeconds: restByEntry[entryId],
            sets: setsByEntry[entryId]!,
          ),
      ];
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
      {'date': dateKey(newDate)},
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
    final today = dateKey(DateTime.now());
    return db.delete(
      'workouts',
      where:
          '''
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
    final count =
        Sqflite.firstIntValue(
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

  /// Removes every entry of [exerciseId] from [workoutId] with one statement;
  /// their sets go with them through the `ON DELETE CASCADE` foreign key.
  Future<void> removeExerciseEntryFromWorkout(
    String workoutId,
    String exerciseId,
  ) async {
    final db = await this.db;
    await db.delete(
      'exercise_entries',
      where: 'workout_id = ? AND exercise_id = ?',
      whereArgs: [workoutId, exerciseId],
    );
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

  /// Deletes one entry; its sets cascade.
  Future<void> deleteExerciseEntry(String entryId) async {
    final db = await this.db;
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

  Future<List<Map<String, dynamic>>> _lastWorkoutSets(
    DatabaseExecutor db,
    String exerciseId, {
    String? excludeWorkoutId,
  }) async {
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

  Future<int> _entryCount(DatabaseExecutor db, String workoutId) async =>
      Sqflite.firstIntValue(
        await db.rawQuery(
          'SELECT COUNT(*) FROM exercise_entries WHERE workout_id = ?',
          [workoutId],
        ),
      ) ??
      0;

  // ===================================================================
  // ACTIVE WORKOUT READS
  // ===================================================================

  /// Every set of the workout, grouped by the exercise entry it belongs to
  /// (in set order): one query instead of one per exercise.
  Future<Map<String, List<Map<String, dynamic>>>> getWorkoutSetsByEntry(
    String workoutId,
  ) async {
    final db = await this.db;
    final rows = await db.rawQuery(
      '''
      SELECT s.* FROM sets s
      JOIN exercise_entries ee ON s.exercise_entry_id = ee.id
      WHERE ee.workout_id = ?
      ORDER BY s.order_index ASC
    ''',
      [workoutId],
    );
    final byEntry = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      byEntry
          .putIfAbsent(row['exercise_entry_id'] as String, () => [])
          .add(row);
    }
    return byEntry;
  }

  /// For each weight-and-reps exercise of the workout, the completed working
  /// volume (kg) of its previous finished session — the baseline the active
  /// workout compares against. One grouped query for all exercises; an
  /// exercise never done before maps to 0.
  Future<Map<String, double>> getLastCompletedVolumes(String workoutId) async {
    final db = await this.db;
    final rows = await db.rawQuery(
      '''
      SELECT cur.exercise_id AS exercise_id,
        COALESCE(SUM(s.weight * s.reps), 0) AS volume
      FROM (
        SELECT DISTINCT ee.exercise_id AS exercise_id
        FROM exercise_entries ee
        JOIN exercises e ON e.id = ee.exercise_id
        WHERE ee.workout_id = ? AND e.type = 'weightReps'
      ) cur
      LEFT JOIN exercise_entries lee
        ON lee.exercise_id = cur.exercise_id
        AND lee.workout_id = (
          SELECT w.id
          FROM workouts w
          JOIN exercise_entries ee2 ON ee2.workout_id = w.id
          WHERE ee2.exercise_id = cur.exercise_id
            AND w.id != ?
            AND w.end_time IS NOT NULL
          ORDER BY w.date DESC, w.end_time DESC, w.start_time DESC
          LIMIT 1
        )
      LEFT JOIN sets s
        ON s.exercise_entry_id = lee.id
        AND s.is_complete = 1
        AND s.is_warmup = 0
        AND s.weight IS NOT NULL
        AND s.reps IS NOT NULL
      GROUP BY cur.exercise_id
    ''',
      [workoutId, workoutId],
    );
    return {
      for (final row in rows)
        row['exercise_id'] as String: (row['volume'] as num?)?.toDouble() ?? 0,
    };
  }

  Future<Map<String, dynamic>?> getSet(String setId) async {
    final db = await this.db;
    final rows = await db.query(
      'sets',
      where: 'id = ?',
      whereArgs: [setId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// The longest distance completed for [exerciseId] in any workout other
  /// than [excludeWorkoutId]; 0 when there is none.
  Future<double> getBestPreviousDistance(
    String exerciseId, {
    required String excludeWorkoutId,
  }) async {
    final db = await this.db;
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(MAX(s.distance), 0) AS best_distance
      FROM sets s
      JOIN exercise_entries ee ON s.exercise_entry_id = ee.id
      WHERE ee.exercise_id = ? AND ee.workout_id != ?
        AND s.is_warmup = 0 AND s.is_complete = 1
        AND s.distance IS NOT NULL AND s.distance > 0
    ''',
      [exerciseId, excludeWorkoutId],
    );
    if (rows.isEmpty) return 0;
    return (rows.first['best_distance'] as num?)?.toDouble() ?? 0;
  }

  // ===================================================================
  // INTERNAL HELPERS (used by importRoutineDayToWorkout)

  /// Records which routine day (and routine) a workout trains. Keeps an
  /// existing link: importing a second day into the same session does not
  /// relabel it.
  Future<void> _linkRoutineDay(
    DatabaseExecutor db,
    String workoutId,
    String routineDayId,
  ) async {
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
    DatabaseExecutor db,
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
    DatabaseExecutor db,
    String routineExerciseId,
  ) async {
    return db.query(
      'predefined_sets',
      where: 'routine_exercise_id = ?',
      whereArgs: [routineExerciseId],
      orderBy: 'order_index ASC',
    );
  }

  Future<Map<String, dynamic>?> _getWorkout(
    DatabaseExecutor db,
    String id,
  ) async {
    final results = await db.query(
      'workouts',
      where: 'id = ?',
      whereArgs: [id],
    );
    return results.isEmpty ? null : results.first;
  }
}
