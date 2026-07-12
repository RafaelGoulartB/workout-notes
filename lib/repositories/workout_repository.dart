import 'dart:ui';

import 'package:workout_notes/models/exercise_with_sets.dart';
import 'package:workout_notes/models/exercise_personal_records.dart';
import 'package:workout_notes/models/workout_stats.dart';
import 'package:workout_notes/models/workout_set_draft.dart';
import 'package:workout_notes/utils/app_date_codec.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'base_repository.dart';
import '../database/database_provider.dart';

/// Repository for workouts, exercise entries, and sets CRUD operations.
class WorkoutRepository extends BaseRepository {
  WorkoutRepository([DatabaseProvider? databaseProvider])
    : super(databaseProvider);
  // ===================================================================
  // WORKOUTS
  // ===================================================================

  Future<String> createWorkout({
    DateTime? date,
    String? routineId,
    List<Map<String, dynamic>>? exercises,
  }) async {
    final db = await this.db;
    final id = const Uuid().v4();
    final now = DateTime.now();
    await db.transaction((txn) async {
      await txn.insert('workouts', {
        'id': id,
        'date': AppDateCodec.toStorageDate(date ?? now),
        'is_from_routine': routineId != null ? 1 : 0,
        'routine_id': routineId,
        'created_at': now.toIso8601String(),
      });

      if (exercises == null) {
        return;
      }
      for (
        var exerciseIndex = 0;
        exerciseIndex < exercises.length;
        exerciseIndex++
      ) {
        final exercise = exercises[exerciseIndex];
        final entryId = const Uuid().v4();
        await txn.insert('exercise_entries', {
          'id': entryId,
          'workout_id': id,
          'exercise_id': exercise['exercise_id'],
          'order_index': exerciseIndex,
          'notes': exercise['notes'],
          'rest_time_seconds': exercise['rest_time_seconds'],
        });

        final sets = exercise['sets'] as List<Map<String, dynamic>>? ?? [];
        for (var setIndex = 0; setIndex < sets.length; setIndex++) {
          final set = sets[setIndex];
          await txn.insert('sets', {
            'id': const Uuid().v4(),
            'exercise_entry_id': entryId,
            'weight': set['weight'],
            'reps': set['reps'],
            'distance': set['distance'],
            'time_seconds': set['time_seconds'],
            'is_complete': 0,
            'is_warmup': set['is_warmup'] ?? 0,
            'rpe': set['rpe'],
            'comment': set['comment'],
            'order_index': setIndex,
          });
        }
      }
    });

    return id;
  }

  /// Creates a completed one-exercise workout as a single transaction.
  ///
  /// Quick-add entries are complete by definition: the user is recording a
  /// past workout rather than starting an active session.
  Future<String> createCompletedQuickWorkout({
    required String exerciseId,
    required List<WorkoutSetDraft> sets,
    int feelingRating = 3,
  }) async {
    if (sets.isEmpty) {
      throw ArgumentError.value(sets, 'sets', 'must not be empty');
    }

    final db = await this.db;
    final now = DateTime.now();
    final nowIso = now.toIso8601String();
    final workoutId = const Uuid().v4();
    final entryId = const Uuid().v4();

    await db.transaction((txn) async {
      await txn.insert('workouts', {
        'id': workoutId,
        'date': AppDateCodec.toStorageDate(now),
        'start_time': nowIso,
        'end_time': nowIso,
        'duration_seconds': 0,
        'feeling_rating': feelingRating,
        'is_from_routine': 0,
        'created_at': nowIso,
      });
      await txn.insert('exercise_entries', {
        'id': entryId,
        'workout_id': workoutId,
        'exercise_id': exerciseId,
        'order_index': 0,
      });
      for (var index = 0; index < sets.length; index++) {
        final set = sets[index];
        await txn.insert('sets', {
          'id': const Uuid().v4(),
          'exercise_entry_id': entryId,
          'weight': set.weight,
          'reps': set.reps,
          'distance': set.distance,
          'time_seconds': set.timeSeconds,
          'is_complete': 1,
          'is_warmup': set.isWarmup ? 1 : 0,
          'rpe': set.rpe,
          'comment': set.comment,
          'order_index': index,
        });
      }
    });

    return workoutId;
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
    await db.transaction((txn) async {
      final count =
          Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT COUNT(*) FROM exercise_entries WHERE workout_id = ?',
              [workoutId],
            ),
          ) ??
          0;
      await txn.insert('exercise_entries', {
        'id': entryId,
        'workout_id': workoutId,
        'exercise_id': exerciseId,
        'order_index': count,
        'rest_time_seconds': restTimeSeconds ?? 90,
      });
      final lastSets = await _getLastWorkoutSets(
        txn,
        exerciseId,
        excludeWorkoutId: workoutId,
      );
      for (final set in lastSets) {
        await txn.insert('sets', {
          'id': const Uuid().v4(),
          'exercise_entry_id': entryId,
          'weight': set['weight'],
          'reps': set['reps'],
          'distance': set['distance'],
          'time_seconds': set['time_seconds'],
          'is_complete': 0,
          'is_warmup': set['is_warmup'] ?? 0,
          'order_index': set['order_index'],
        });
      }
    });
    return entryId;
  }

  Future<void> importRoutineDayToWorkout(
    String workoutId,
    String routineDayId,
  ) async {
    final db = await this.db;
    await db.transaction((txn) async {
      final routineExercises = await _getRoutineExercises(txn, routineDayId);
      var orderIndex =
          Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT COUNT(*) FROM exercise_entries WHERE workout_id = ?',
              [workoutId],
            ),
          ) ??
          0;

      for (final routineExercise in routineExercises) {
        final entryId = const Uuid().v4();
        final exerciseId = routineExercise['exercise_id'] as String;
        await txn.insert('exercise_entries', {
          'id': entryId,
          'workout_id': workoutId,
          'exercise_id': exerciseId,
          'order_index': orderIndex++,
          'rest_time_seconds': routineExercise['rest_time_seconds'],
        });

        final previousSets = await _getLastWorkoutSets(
          txn,
          exerciseId,
          excludeWorkoutId: workoutId,
        );
        final sourceSets = previousSets.isNotEmpty
            ? previousSets
            : await _getPredefinedSets(txn, routineExercise['id'] as String);

        for (var index = 0; index < sourceSets.length; index++) {
          final set = sourceSets[index];
          await txn.insert('sets', {
            'id': const Uuid().v4(),
            'exercise_entry_id': entryId,
            'weight': set['weight'],
            'reps': set['reps'],
            'distance': set['distance'],
            'time_seconds': set['time_seconds'],
            'is_complete': 0,
            'is_warmup': set['is_warmup'] ?? 0,
            'order_index': index,
          });
        }
      }
    });
  }

  Future<String> copyWorkoutToDate(
    String sourceWorkoutId,
    DateTime newDate,
  ) async {
    final db = await this.db;
    final newId = const Uuid().v4();
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      final sourceWorkout = await _getWorkout(txn, sourceWorkoutId);
      if (sourceWorkout == null) {
        throw StateError('Source workout not found');
      }
      await txn.insert('workouts', {
        'id': newId,
        'date': AppDateCodec.toStorageDate(newDate),
        'start_time': null,
        'end_time': null,
        'duration_seconds': null,
        'comment': null,
        'feeling_rating': null,
        'is_from_routine': sourceWorkout['is_from_routine'] ?? 0,
        'routine_id': sourceWorkout['routine_id'],
        'created_at': now,
      });

      final entries = await txn.query(
        'exercise_entries',
        where: 'workout_id = ?',
        whereArgs: [sourceWorkoutId],
        orderBy: 'order_index ASC',
      );

      for (final entry in entries) {
        final newEntryId = const Uuid().v4();
        await txn.insert('exercise_entries', {
          'id': newEntryId,
          'workout_id': newId,
          'exercise_id': entry['exercise_id'],
          'order_index': entry['order_index'],
          'superset_group_id': entry['superset_group_id'],
          'notes': entry['notes'],
          'rest_time_seconds': entry['rest_time_seconds'],
        });

        final sets = await txn.query(
          'sets',
          where: 'exercise_entry_id = ?',
          whereArgs: [entry['id']],
          orderBy: 'order_index ASC',
        );

        for (final set in sets) {
          await txn.insert('sets', {
            'id': const Uuid().v4(),
            'exercise_entry_id': newEntryId,
            'weight': set['weight'],
            'reps': set['reps'],
            'distance': set['distance'],
            'time_seconds': set['time_seconds'],
            'is_complete': 0,
            'is_warmup': set['is_warmup'] ?? 0,
            'rpe': set['rpe'],
            'comment': set['comment'],
            'order_index': set['order_index'],
          });
        }
      }
    });

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
    final today = AppDateCodec.toStorageDate(DateTime.now());
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
      args.add(AppDateCodec.toStorageDate(startDate));
    }
    if (endDate != null) {
      query += ' AND date <= ?';
      args.add(AppDateCodec.toStorageDate(endDate));
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
      'ec.name as category_name, ec.color as category_color, ec.energy_system as category_energy, e.type as exercise_type '
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
    DatabaseExecutor db,
    String workoutId,
  ) async {
    final workout = await _getWorkout(db, workoutId);
    if (workout == null) return null;

    final routineId = workout['routine_id'] as String?;
    final currentDate = workout['date'] as String? ?? '';
    final currentMoment =
        (workout['end_time'] as String?) ??
        (workout['start_time'] as String?) ??
        (workout['created_at'] as String?) ??
        '';
    if (routineId != null && routineId.isNotEmpty) {
      final rows = await db.rawQuery(
        '''
        SELECT id
        FROM workouts
        WHERE id != ?
          AND routine_id = ?
          AND end_time IS NOT NULL
          AND (
            date < ?
            OR (date = ? AND COALESCE(end_time, start_time, created_at, '') < ?)
          )
        ORDER BY date DESC, end_time DESC, created_at DESC
        LIMIT 1
      ''',
        [workoutId, routineId, currentDate, currentDate, currentMoment],
      );
      if (rows.isNotEmpty) return rows.first['id'] as String;
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
      SELECT w.id, COUNT(DISTINCT ee.exercise_id) as shared_count
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
    return rows.first['id'] as String;
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
    DatabaseExecutor db,
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
    DatabaseExecutor db,
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

    await db.update(
      'workouts',
      {
        'end_time': now.toIso8601String(),
        'duration_seconds': duration,
        'start_time': startTimeStr ?? now.toIso8601String(),
        'comment': ?comment,
        'feeling_rating': ?feelingRating,
      },
      where: 'id = ?',
      whereArgs: [id],
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
    if (weight != null) updates['weight'] = weight;
    if (reps != null) updates['reps'] = reps;
    if (distance != null) updates['distance'] = distance;
    if (timeSeconds != null) updates['time_seconds'] = timeSeconds;
    if (isComplete != null) updates['is_complete'] = isComplete ? 1 : 0;
    if (isWarmup != null) updates['is_warmup'] = isWarmup ? 1 : 0;
    if (rpe != null) updates['rpe'] = rpe;
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
    return _getLastWorkoutSets(
      db,
      exerciseId,
      excludeWorkoutId: excludeWorkoutId,
    );
  }

  /// Returns personal-record baselines while excluding the workout currently
  /// being completed, so a set cannot be compared against itself.
  Future<ExercisePersonalRecords> getPersonalRecordsBeforeWorkout({
    required String exerciseId,
    required String workoutId,
  }) async {
    final db = await this.db;
    final rows = await db.rawQuery(
      '''
      SELECT
        COALESCE(MAX(s.weight), 0) AS max_weight,
        COALESCE(SUM(s.weight * s.reps), 0) AS max_volume,
        COALESCE(MAX(s.distance), 0) AS max_distance
      FROM sets s
      JOIN exercise_entries ee ON s.exercise_entry_id = ee.id
      WHERE ee.exercise_id = ? AND ee.workout_id != ?
        AND s.is_warmup = 0 AND s.is_complete = 1
      ''',
      [exerciseId, workoutId],
    );
    final row = rows.single;
    return ExercisePersonalRecords(
      maxWeight: (row['max_weight'] as num?)?.toDouble() ?? 0,
      maxVolume: (row['max_volume'] as num?)?.toDouble() ?? 0,
      maxDistance: (row['max_distance'] as num?)?.toDouble() ?? 0,
    );
  }

  Future<List<Map<String, dynamic>>> _getLastWorkoutSets(
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

  // ===================================================================
  // INTERNAL HELPERS (used by importRoutineDayToWorkout)
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
