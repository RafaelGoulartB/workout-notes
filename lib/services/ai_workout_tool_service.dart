import '../database/database_helper.dart';

/// Read-only, AI-facing workout queries.
///
/// Performance aggregates intentionally include only finished workouts and
/// completed, non-warm-up sets. Planned sets remain available in workout
/// details, but never count as work the user actually performed.
class AiWorkoutToolService {
  final DatabaseHelper db;

  AiWorkoutToolService({DatabaseHelper? db})
    : db = db ?? DatabaseHelper.instance;

  Future<Map<String, dynamic>> recent({int limit = 8}) async {
    final result = await history(status: 'completed', pageSize: limit, page: 1);
    return {'workouts': result['workouts']};
  }

  Future<Map<String, dynamic>> history({
    String? startDate,
    String? endDate,
    String status = 'all',
    int page = 1,
    int pageSize = 20,
  }) async {
    final rawDb = await db.database;
    final where = <String>[];
    final values = <Object?>[];
    if (startDate != null) {
      where.add('w.date >= ?');
      values.add(startDate);
    }
    if (endDate != null) {
      where.add('w.date <= ?');
      values.add(endDate);
    }
    switch (status) {
      case 'completed':
        where.add('w.end_time IS NOT NULL');
      case 'in_progress':
        where.add('w.end_time IS NULL AND w.start_time IS NOT NULL');
      case 'planned':
        where.add('w.start_time IS NULL');
    }
    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    final countRows = await rawDb.rawQuery(
      'SELECT COUNT(*) AS total FROM workouts w $whereSql',
      values,
    );
    final total = (countRows.first['total'] as num?)?.toInt() ?? 0;
    final offset = (page - 1) * pageSize;
    final rows = await rawDb.rawQuery(
      '''
      SELECT w.*,
        COUNT(DISTINCT ee.id) AS exercise_count,
        COUNT(DISTINCT CASE WHEN s.is_complete = 1 AND s.is_warmup = 0
          THEN s.id END) AS completed_set_count,
        COUNT(DISTINCT CASE WHEN COALESCE(s.is_complete, 0) = 0
          THEN s.id END) AS planned_set_count,
        COALESCE(SUM(CASE WHEN s.is_complete = 1 AND s.is_warmup = 0
          THEN COALESCE(s.weight, 0) * COALESCE(s.reps, 0)
          ELSE 0 END), 0) AS volume_kg,
        COALESCE(SUM(CASE WHEN s.is_complete = 1 AND s.is_warmup = 0
          THEN COALESCE(s.reps, 0) ELSE 0 END), 0) AS total_reps,
        COALESCE(SUM(CASE WHEN s.is_complete = 1 AND s.is_warmup = 0
          THEN COALESCE(s.distance, 0) ELSE 0 END), 0) AS total_distance,
        COALESCE(SUM(CASE WHEN s.is_complete = 1 AND s.is_warmup = 0
          THEN COALESCE(s.time_seconds, 0) ELSE 0 END), 0) AS exercise_time_seconds,
        AVG(CASE WHEN s.is_complete = 1 AND s.is_warmup = 0
          THEN s.rpe END) AS average_rpe
      FROM workouts w
      LEFT JOIN exercise_entries ee ON ee.workout_id = w.id
      LEFT JOIN sets s ON s.exercise_entry_id = ee.id
      $whereSql
      GROUP BY w.id
      ORDER BY w.date DESC,
        COALESCE(w.end_time, w.start_time, w.created_at) DESC
      LIMIT ? OFFSET ?
    ''',
      [...values, pageSize, offset],
    );
    final workouts = rows.map(_workoutSummary).toList();
    return {
      'filters': {'startDate': startDate, 'endDate': endDate, 'status': status},
      'pagination': {
        'page': page,
        'pageSize': pageSize,
        'totalItems': total,
        'totalPages': total == 0 ? 0 : ((total - 1) ~/ pageSize) + 1,
        'hasMore': offset + workouts.length < total,
      },
      'workouts': workouts,
    };
  }

  Future<Map<String, dynamic>?> workoutDetail(String id) async {
    final workout = await db.getWorkout(id);
    if (workout == null) return null;
    final rawDb = await db.database;
    final rows = await rawDb.rawQuery(
      '''
      SELECT ee.id AS entry_id, ee.exercise_id, ee.order_index,
        ee.superset_group_id, ee.notes AS entry_notes, ee.rest_time_seconds,
        e.name AS exercise_name, e.type AS exercise_type,
        e.equipment, e.notes AS exercise_notes,
        ec.id AS category_id, ec.name AS category_name,
        ec.energy_system AS category_energy_system,
        s.id AS set_id, s.order_index AS set_order, s.weight, s.reps,
        s.distance, s.time_seconds, s.is_warmup, s.is_complete, s.rpe,
        s.comment AS set_comment
      FROM exercise_entries ee
      JOIN exercises e ON e.id = ee.exercise_id
      LEFT JOIN exercise_categories ec ON ec.id = e.category_id
      LEFT JOIN sets s ON s.exercise_entry_id = ee.id
      WHERE ee.workout_id = ?
      ORDER BY ee.order_index ASC, s.order_index ASC
    ''',
      [id],
    );
    final byEntry = <String, Map<String, dynamic>>{};
    var completedSets = 0;
    var volumeKg = 0.0;
    var totalReps = 0;
    var totalDistance = 0.0;
    var exerciseTimeSeconds = 0;
    final rpes = <double>[];
    for (final row in rows) {
      final entryId = row['entry_id'] as String;
      final entry = byEntry.putIfAbsent(
        entryId,
        () => {
          'entryId': entryId,
          'exerciseId': row['exercise_id'],
          'exerciseName': row['exercise_name'],
          'exerciseType': row['exercise_type'],
          'equipment': row['equipment'],
          'exerciseNotes': row['exercise_notes'],
          'category': {
            'id': row['category_id'],
            'name': row['category_name'],
            'energySystem': row['category_energy_system'],
          },
          'order': row['order_index'],
          'supersetGroupId': row['superset_group_id'],
          'notes': row['entry_notes'],
          'restTimeSeconds': row['rest_time_seconds'],
          'sets': <Map<String, dynamic>>[],
        },
      );
      if (row['set_id'] == null) continue;
      final complete = (row['is_complete'] as num?)?.toInt() == 1;
      final warmup = (row['is_warmup'] as num?)?.toInt() == 1;
      final weight = (row['weight'] as num?)?.toDouble();
      final reps = (row['reps'] as num?)?.toInt();
      final distance = (row['distance'] as num?)?.toDouble();
      final time = (row['time_seconds'] as num?)?.toInt();
      final rpe = (row['rpe'] as num?)?.toDouble();
      (entry['sets'] as List<Map<String, dynamic>>).add({
        'id': row['set_id'],
        'order': row['set_order'],
        'weight': weight,
        'reps': reps,
        'distance': distance,
        'timeSeconds': time,
        'isWarmup': warmup,
        'isComplete': complete,
        'rpe': rpe,
        'comment': row['set_comment'],
      });
      if (complete && !warmup) {
        completedSets++;
        volumeKg += (weight ?? 0) * (reps ?? 0);
        totalReps += reps ?? 0;
        totalDistance += distance ?? 0;
        exerciseTimeSeconds += time ?? 0;
        if (rpe != null) rpes.add(rpe);
      }
    }
    return {
      'id': id,
      'date': workout['date'],
      'status': _workoutStatus(workout),
      'startTime': workout['start_time'],
      'endTime': workout['end_time'],
      'pauseStartTime': workout['pause_start_time'],
      'durationSeconds': workout['duration_seconds'],
      'estimatedCalories': (workout['estimated_calories'] as num?)?.toDouble(),
      'feeling': workout['feeling_rating'],
      'comment': workout['comment'],
      'isFromRoutine': (workout['is_from_routine'] as num?)?.toInt() == 1,
      'routineId': workout['routine_id'],
      'createdAt': workout['created_at'],
      'performedTotals': {
        'completedSets': completedSets,
        'volumeKg': volumeKg,
        'totalReps': totalReps,
        'totalDistance': totalDistance,
        'exerciseTimeSeconds': exerciseTimeSeconds,
        'averageRpe': _average(rpes),
      },
      'exercises': byEntry.values.toList(),
    };
  }

  Future<Map<String, dynamic>> listExercises({
    String? categoryId,
    String? search,
    bool? favorites,
    int limit = 20,
  }) async {
    final rows = await db.getExercises(
      categoryId: categoryId,
      search: search,
      favorites: favorites,
    );
    return {'exercises': rows.take(limit).map(_exerciseSummary).toList()};
  }

  Future<Map<String, dynamic>?> exerciseDetail(String id) async {
    final exercise = await db.getExercise(id);
    if (exercise == null) return null;
    final rawDb = await db.database;
    final usage = await rawDb.rawQuery(
      '''
      SELECT COUNT(DISTINCT w.id) AS completed_workouts,
        COUNT(s.id) AS completed_sets, MAX(w.date) AS last_performed_date
      FROM exercise_entries ee
      JOIN workouts w ON w.id = ee.workout_id AND w.end_time IS NOT NULL
      LEFT JOIN sets s ON s.exercise_entry_id = ee.id
        AND s.is_complete = 1 AND s.is_warmup = 0
      WHERE ee.exercise_id = ?
    ''',
      [id],
    );
    final stats = usage.first;
    return {
      ..._exerciseSummary(exercise),
      'notes': exercise['notes'],
      'equipment': exercise['equipment'],
      'defaultRestTimeSeconds': exercise['default_rest_time'],
      'weightIncrement': (exercise['weight_increment'] as num?)?.toDouble(),
      'createdAt': exercise['created_at'],
      'usage': {
        'completedWorkouts':
            (stats['completed_workouts'] as num?)?.toInt() ?? 0,
        'completedSets': (stats['completed_sets'] as num?)?.toInt() ?? 0,
        'lastPerformedDate': stats['last_performed_date'],
      },
    };
  }

  Future<Map<String, dynamic>> exerciseHistory(
    String exerciseId, {
    int limit = 12,
    String? startDate,
    String? endDate,
  }) async {
    final sessions = await _exerciseSessions(
      exerciseId,
      limit: limit,
      startDate: startDate,
      endDate: endDate,
    );
    final allSets = sessions
        .expand((session) => session['sets'] as List<Map<String, dynamic>>)
        .toList();
    final weights = allSets
        .map((set) => set['weight'] as double?)
        .whereType<double>()
        .toList();
    final reps = allSets
        .map((set) => set['reps'] as int?)
        .whereType<int>()
        .toList();
    final topSets = [...allSets]
      ..sort((a, b) {
        final aScore =
            (a['estimated1Rm'] as double?) ?? ((a['weight'] as double?) ?? 0);
        final bScore =
            (b['estimated1Rm'] as double?) ?? ((b['weight'] as double?) ?? 0);
        return bScore.compareTo(aScore);
      });
    return {
      'exerciseId': exerciseId,
      'filters': {'startDate': startDate, 'endDate': endDate},
      'sessionCount': sessions.length,
      'totalSets': allSets.length,
      'avgWeight': _average(weights),
      'avgReps': reps.isEmpty
          ? null
          : reps.reduce((a, b) => a + b) / reps.length,
      'topSets': topSets.take(5).toList(),
      'history': sessions,
    };
  }

  Future<Map<String, dynamic>> exerciseRecords(String exerciseId) async {
    final rawDb = await db.database;
    final exercise = await db.getExercise(exerciseId);
    final rows = await rawDb.rawQuery(
      '''
      SELECT w.id AS workout_id, w.date, s.weight, s.reps, s.distance,
        s.time_seconds, s.rpe
      FROM sets s
      JOIN exercise_entries ee ON ee.id = s.exercise_entry_id
      JOIN workouts w ON w.id = ee.workout_id
      WHERE ee.exercise_id = ? AND w.end_time IS NOT NULL
        AND s.is_complete = 1 AND s.is_warmup = 0
      ORDER BY w.date ASC
    ''',
      [exerciseId],
    );
    final definitions = <String, _RecordCandidate>{};
    void maximum(String key, String unit, double? value, Map row) {
      if (value == null) return;
      final current = definitions[key];
      if (current == null || value > current.value) {
        definitions[key] = _RecordCandidate(value, unit, row);
      }
    }

    void minimum(String key, String unit, double? value, Map row) {
      if (value == null || value <= 0) return;
      final current = definitions[key];
      if (current == null || value < current.value) {
        definitions[key] = _RecordCandidate(value, unit, row);
      }
    }

    for (final row in rows) {
      final weight = (row['weight'] as num?)?.toDouble();
      final reps = (row['reps'] as num?)?.toInt();
      final distance = (row['distance'] as num?)?.toDouble();
      final time = (row['time_seconds'] as num?)?.toDouble();
      maximum('max_weight', 'kg', weight, row);
      maximum('max_reps', 'reps', reps?.toDouble(), row);
      maximum(
        'best_estimated_1rm',
        'kg',
        weight != null && weight > 0 && reps != null && reps > 0
            ? weight * (1 + reps / 30)
            : null,
        row,
      );
      maximum(
        'max_set_volume',
        'kg',
        weight != null && reps != null ? weight * reps : null,
        row,
      );
      maximum('max_distance', 'distance_unit', distance, row);
      maximum('longest_duration', 'seconds', time, row);
      minimum(
        'best_pace',
        'seconds_per_distance_unit',
        time != null && distance != null && distance > 0
            ? time / distance
            : null,
        row,
      );
    }
    return {
      'exerciseId': exerciseId,
      'exerciseName': exercise?['name'],
      'exerciseType': exercise?['type'],
      'records': definitions.entries
          .map(
            (entry) => {
              'metric': entry.key,
              'value': entry.value.value,
              'unit': entry.value.unit,
              'date': entry.value.row['date'],
              'workoutId': entry.value.row['workout_id'],
            },
          )
          .toList(),
    };
  }

  Future<Map<String, dynamic>> progressTrend(
    String exerciseId, {
    int weeks = 8,
  }) async {
    final end = DateTime.now();
    final start = end.subtract(Duration(days: weeks * 7 - 1));
    final history = await exerciseHistory(
      exerciseId,
      limit: 1000,
      startDate: _date(start),
      endDate: _date(end),
    );
    return {
      'exerciseId': exerciseId,
      'weeksBack': weeks,
      'startDate': _date(start),
      'endDate': _date(end),
      'dataPoints': history['history'],
      'sessionCount': history['sessionCount'],
    };
  }

  Future<Map<String, dynamic>> weeklyVolume({int weeks = 8}) async {
    final rawDb = await db.database;
    final today = DateTime.now();
    final currentMonday = today.subtract(Duration(days: today.weekday - 1));
    final firstMonday = currentMonday.subtract(Duration(days: (weeks - 1) * 7));
    final rows = await rawDb.rawQuery(
      '''
      SELECT w.date, ec.id AS category_id, ec.name AS category_name,
        ec.energy_system, s.weight, s.reps, s.distance, s.time_seconds
      FROM sets s
      JOIN exercise_entries ee ON ee.id = s.exercise_entry_id
      JOIN exercises e ON e.id = ee.exercise_id
      JOIN exercise_categories ec ON ec.id = e.category_id
      JOIN workouts w ON w.id = ee.workout_id
      WHERE w.end_time IS NOT NULL AND w.date >= ? AND w.date <= ?
        AND s.is_complete = 1 AND s.is_warmup = 0
      ORDER BY w.date ASC
    ''',
      [_date(firstMonday), _date(today)],
    );
    final buckets = <String, Map<String, Map<String, dynamic>>>{};
    for (final row in rows) {
      final date = DateTime.parse(row['date'] as String);
      final monday = date.subtract(Duration(days: date.weekday - 1));
      final weekKey = _date(monday);
      final categoryId = row['category_id'] as String;
      final category = buckets
          .putIfAbsent(weekKey, () => {})
          .putIfAbsent(
            categoryId,
            () => {
              'categoryId': categoryId,
              'categoryName': row['category_name'],
              'energySystem': row['energy_system'],
              'completedSets': 0,
              'volumeKg': 0.0,
              'totalReps': 0,
              'totalDistance': 0.0,
              'exerciseTimeSeconds': 0,
            },
          );
      category['completedSets'] = (category['completedSets'] as int) + 1;
      final weight = (row['weight'] as num?)?.toDouble() ?? 0;
      final reps = (row['reps'] as num?)?.toInt() ?? 0;
      category['volumeKg'] = (category['volumeKg'] as double) + weight * reps;
      category['totalReps'] = (category['totalReps'] as int) + reps;
      category['totalDistance'] =
          (category['totalDistance'] as double) +
          ((row['distance'] as num?)?.toDouble() ?? 0);
      category['exerciseTimeSeconds'] =
          (category['exerciseTimeSeconds'] as int) +
          ((row['time_seconds'] as num?)?.toInt() ?? 0);
    }
    final output = <Map<String, dynamic>>[];
    for (var offset = weeks - 1; offset >= 0; offset--) {
      final start = currentMonday.subtract(Duration(days: offset * 7));
      output.add({
        'startDate': _date(start),
        'endDate': _date(start.add(const Duration(days: 6))),
        'categories': buckets[_date(start)]?.values.toList() ?? const [],
      });
    }
    return {'weeksBack': weeks, 'weeks': output};
  }

  Future<Map<String, dynamic>> trainingSummary({
    required String startDate,
    required String endDate,
  }) async {
    final rawDb = await db.database;
    final statusRows = await rawDb.rawQuery(
      '''
      SELECT
        SUM(CASE WHEN end_time IS NOT NULL THEN 1 ELSE 0 END) AS completed,
        SUM(CASE WHEN end_time IS NULL AND start_time IS NOT NULL THEN 1 ELSE 0 END) AS in_progress,
        SUM(CASE WHEN start_time IS NULL THEN 1 ELSE 0 END) AS planned,
        COUNT(DISTINCT CASE WHEN end_time IS NOT NULL THEN date END) AS active_days,
        SUM(CASE WHEN end_time IS NOT NULL THEN COALESCE(duration_seconds, 0) ELSE 0 END) AS duration_seconds,
        SUM(CASE WHEN end_time IS NOT NULL THEN COALESCE(estimated_calories, 0) ELSE 0 END) AS calories,
        AVG(CASE WHEN end_time IS NOT NULL THEN feeling_rating END) AS average_feeling
      FROM workouts WHERE date >= ? AND date <= ?
    ''',
      [startDate, endDate],
    );
    final setRows = await rawDb.rawQuery(
      '''
      SELECT COUNT(s.id) AS completed_sets,
        COALESCE(SUM(COALESCE(s.weight, 0) * COALESCE(s.reps, 0)), 0) AS volume_kg,
        COALESCE(SUM(COALESCE(s.reps, 0)), 0) AS total_reps,
        COALESCE(SUM(COALESCE(s.distance, 0)), 0) AS total_distance,
        COALESCE(SUM(COALESCE(s.time_seconds, 0)), 0) AS exercise_time_seconds,
        AVG(s.rpe) AS average_rpe
      FROM sets s
      JOIN exercise_entries ee ON ee.id = s.exercise_entry_id
      JOIN workouts w ON w.id = ee.workout_id
      WHERE w.end_time IS NOT NULL AND w.date >= ? AND w.date <= ?
        AND s.is_complete = 1 AND s.is_warmup = 0
    ''',
      [startDate, endDate],
    );
    final categories = await rawDb.rawQuery(
      '''
      SELECT ec.id AS category_id, ec.name AS category_name,
        ec.energy_system, COUNT(s.id) AS completed_sets,
        COALESCE(SUM(COALESCE(s.weight, 0) * COALESCE(s.reps, 0)), 0) AS volume_kg,
        COALESCE(SUM(COALESCE(s.distance, 0)), 0) AS total_distance,
        COALESCE(SUM(COALESCE(s.time_seconds, 0)), 0) AS exercise_time_seconds
      FROM sets s
      JOIN exercise_entries ee ON ee.id = s.exercise_entry_id
      JOIN exercises e ON e.id = ee.exercise_id
      JOIN exercise_categories ec ON ec.id = e.category_id
      JOIN workouts w ON w.id = ee.workout_id
      WHERE w.end_time IS NOT NULL AND w.date >= ? AND w.date <= ?
        AND s.is_complete = 1 AND s.is_warmup = 0
      GROUP BY ec.id ORDER BY completed_sets DESC
    ''',
      [startDate, endDate],
    );
    final topExercises = await rawDb.rawQuery(
      '''
      SELECT e.id AS exercise_id, e.name AS exercise_name,
        COUNT(DISTINCT w.id) AS sessions, COUNT(s.id) AS completed_sets,
        COALESCE(SUM(COALESCE(s.weight, 0) * COALESCE(s.reps, 0)), 0) AS volume_kg
      FROM sets s
      JOIN exercise_entries ee ON ee.id = s.exercise_entry_id
      JOIN exercises e ON e.id = ee.exercise_id
      JOIN workouts w ON w.id = ee.workout_id
      WHERE w.end_time IS NOT NULL AND w.date >= ? AND w.date <= ?
        AND s.is_complete = 1 AND s.is_warmup = 0
      GROUP BY e.id ORDER BY sessions DESC, completed_sets DESC LIMIT 10
    ''',
      [startDate, endDate],
    );
    final status = statusRows.first;
    final sets = setRows.first;
    final completed = (status['completed'] as num?)?.toInt() ?? 0;
    final days =
        DateTime.parse(endDate).difference(DateTime.parse(startDate)).inDays +
        1;
    return {
      'period': {'startDate': startDate, 'endDate': endDate, 'days': days},
      'workouts': {
        'completed': completed,
        'inProgress': (status['in_progress'] as num?)?.toInt() ?? 0,
        'planned': (status['planned'] as num?)?.toInt() ?? 0,
        'activeDays': (status['active_days'] as num?)?.toInt() ?? 0,
        'averagePerWeek': days == 0 ? 0 : completed / days * 7,
      },
      'performedTotals': {
        'durationSeconds': (status['duration_seconds'] as num?)?.toInt() ?? 0,
        'estimatedCalories': (status['calories'] as num?)?.toDouble() ?? 0,
        'averageFeeling': (status['average_feeling'] as num?)?.toDouble(),
        'completedSets': (sets['completed_sets'] as num?)?.toInt() ?? 0,
        'volumeKg': (sets['volume_kg'] as num?)?.toDouble() ?? 0,
        'totalReps': (sets['total_reps'] as num?)?.toInt() ?? 0,
        'totalDistance': (sets['total_distance'] as num?)?.toDouble() ?? 0,
        'exerciseTimeSeconds':
            (sets['exercise_time_seconds'] as num?)?.toInt() ?? 0,
        'averageRpe': (sets['average_rpe'] as num?)?.toDouble(),
        'volumePerMinute':
            ((status['duration_seconds'] as num?)?.toInt() ?? 0) <= 0
            ? null
            : ((sets['volume_kg'] as num?)?.toDouble() ?? 0) /
                  (((status['duration_seconds'] as num).toDouble()) / 60),
      },
      'byCategory': categories,
      'topExercises': topExercises,
    };
  }

  Future<Map<String, dynamic>> cardioSummary({int weeks = 4}) async {
    final rawDb = await db.database;
    final end = DateTime.now();
    final start = end.subtract(Duration(days: weeks * 7 - 1));
    final rows = await rawDb.rawQuery(
      '''
      SELECT w.id AS workout_id, w.date, e.id AS exercise_id,
        e.name AS exercise_name, ec.id AS modality_id,
        ec.name AS modality, s.distance, s.time_seconds, s.rpe
      FROM sets s
      JOIN exercise_entries ee ON ee.id = s.exercise_entry_id
      JOIN exercises e ON e.id = ee.exercise_id
      JOIN exercise_categories ec ON ec.id = e.category_id
      JOIN workouts w ON w.id = ee.workout_id
      WHERE ec.energy_system = 'aerobic' AND w.end_time IS NOT NULL
        AND w.date >= ? AND w.date <= ?
        AND s.is_complete = 1 AND s.is_warmup = 0
        AND (COALESCE(s.distance, 0) > 0 OR COALESCE(s.time_seconds, 0) > 0)
      ORDER BY w.date ASC
    ''',
      [_date(start), _date(end)],
    );
    final modalities = <String, Map<String, dynamic>>{};
    final sessions = <Map<String, dynamic>>[];
    for (final row in rows) {
      final distance = (row['distance'] as num?)?.toDouble() ?? 0;
      final time = (row['time_seconds'] as num?)?.toInt() ?? 0;
      sessions.add({
        'workoutId': row['workout_id'],
        'date': row['date'],
        'exerciseId': row['exercise_id'],
        'exerciseName': row['exercise_name'],
        'modality': row['modality'],
        'distance': distance,
        'timeSeconds': time,
        'paceSecondsPerDistanceUnit': distance > 0 && time > 0
            ? time / distance
            : null,
        'rpe': (row['rpe'] as num?)?.toDouble(),
      });
      final modality = modalities.putIfAbsent(
        row['modality_id'] as String,
        () => {
          'id': row['modality_id'],
          'name': row['modality'],
          'setCount': 0,
          'workoutIds': <String>{},
          'totalDistance': 0.0,
          'totalTimeSeconds': 0,
        },
      );
      modality['setCount'] = (modality['setCount'] as int) + 1;
      (modality['workoutIds'] as Set<String>).add(row['workout_id'] as String);
      modality['totalDistance'] =
          (modality['totalDistance'] as double) + distance;
      modality['totalTimeSeconds'] =
          (modality['totalTimeSeconds'] as int) + time;
    }
    final byModality = modalities.values.map((value) {
      final distance = value['totalDistance'] as double;
      final time = value['totalTimeSeconds'] as int;
      return {
        'id': value['id'],
        'name': value['name'],
        'workouts': (value['workoutIds'] as Set<String>).length,
        'completedSets': value['setCount'],
        'totalDistance': distance,
        'totalTimeSeconds': time,
        'averagePaceSecondsPerDistanceUnit': distance > 0 && time > 0
            ? time / distance
            : null,
      };
    }).toList();
    return {
      'weeksBack': weeks,
      'startDate': _date(start),
      'endDate': _date(end),
      'byModality': byModality,
      'sessions': sessions,
    };
  }

  Future<List<Map<String, dynamic>>> _exerciseSessions(
    String exerciseId, {
    required int limit,
    String? startDate,
    String? endDate,
  }) async {
    final rawDb = await db.database;
    final where = <String>[
      'ee.exercise_id = ?',
      'w.end_time IS NOT NULL',
      's.is_complete = 1',
      's.is_warmup = 0',
    ];
    final values = <Object?>[exerciseId];
    if (startDate != null) {
      where.add('w.date >= ?');
      values.add(startDate);
    }
    if (endDate != null) {
      where.add('w.date <= ?');
      values.add(endDate);
    }
    final rows = await rawDb.rawQuery('''
      SELECT w.id AS workout_id, w.date, w.start_time, w.end_time,
        s.id AS set_id, s.order_index, s.weight, s.reps, s.distance,
        s.time_seconds, s.rpe, s.comment
      FROM sets s
      JOIN exercise_entries ee ON ee.id = s.exercise_entry_id
      JOIN workouts w ON w.id = ee.workout_id
      WHERE ${where.join(' AND ')}
      ORDER BY w.date DESC, COALESCE(w.end_time, w.start_time) DESC,
        s.order_index ASC
    ''', values);
    final sessions = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final workoutId = row['workout_id'] as String;
      if (!sessions.containsKey(workoutId) && sessions.length >= limit) {
        continue;
      }
      final session = sessions.putIfAbsent(
        workoutId,
        () => {
          'workoutId': workoutId,
          'date': row['date'],
          'startTime': row['start_time'],
          'endTime': row['end_time'],
          'sets': <Map<String, dynamic>>[],
          'completedSets': 0,
          'volumeKg': 0.0,
          'totalReps': 0,
          'totalDistance': 0.0,
          'totalTimeSeconds': 0,
          'rpeValues': <double>[],
        },
      );
      final weight = (row['weight'] as num?)?.toDouble();
      final reps = (row['reps'] as num?)?.toInt();
      final distance = (row['distance'] as num?)?.toDouble();
      final time = (row['time_seconds'] as num?)?.toInt();
      final rpe = (row['rpe'] as num?)?.toDouble();
      final estimated1Rm =
          weight != null && weight > 0 && reps != null && reps > 0
          ? weight * (1 + reps / 30)
          : null;
      (session['sets'] as List<Map<String, dynamic>>).add({
        'id': row['set_id'],
        'order': row['order_index'],
        'weight': weight,
        'reps': reps,
        'distance': distance,
        'timeSeconds': time,
        'rpe': rpe,
        'comment': row['comment'],
        'estimated1Rm': estimated1Rm,
      });
      session['completedSets'] = (session['completedSets'] as int) + 1;
      session['volumeKg'] =
          (session['volumeKg'] as double) + (weight ?? 0) * (reps ?? 0);
      session['totalReps'] = (session['totalReps'] as int) + (reps ?? 0);
      session['totalDistance'] =
          (session['totalDistance'] as double) + (distance ?? 0);
      session['totalTimeSeconds'] =
          (session['totalTimeSeconds'] as int) + (time ?? 0);
      if (rpe != null) (session['rpeValues'] as List<double>).add(rpe);
    }
    return sessions.values.map((session) {
      final rpes = session.remove('rpeValues') as List<double>;
      session['averageRpe'] = _average(rpes);
      return session;
    }).toList();
  }

  Map<String, dynamic> _workoutSummary(Map<String, dynamic> row) => {
    'id': row['id'],
    'date': row['date'],
    'status': _workoutStatus(row),
    'startTime': row['start_time'],
    'endTime': row['end_time'],
    'durationSeconds': row['duration_seconds'],
    'estimatedCalories': (row['estimated_calories'] as num?)?.toDouble(),
    'feeling': row['feeling_rating'],
    'comment': row['comment'],
    'isFromRoutine': (row['is_from_routine'] as num?)?.toInt() == 1,
    'routineId': row['routine_id'],
    'exerciseCount': (row['exercise_count'] as num?)?.toInt() ?? 0,
    'completedSetCount': (row['completed_set_count'] as num?)?.toInt() ?? 0,
    'plannedSetCount': (row['planned_set_count'] as num?)?.toInt() ?? 0,
    'volumeKg': (row['volume_kg'] as num?)?.toDouble() ?? 0,
    'totalReps': (row['total_reps'] as num?)?.toInt() ?? 0,
    'totalDistance': (row['total_distance'] as num?)?.toDouble() ?? 0,
    'exerciseTimeSeconds': (row['exercise_time_seconds'] as num?)?.toInt() ?? 0,
    'averageRpe': (row['average_rpe'] as num?)?.toDouble(),
  };

  Map<String, dynamic> _exerciseSummary(Map<String, dynamic> exercise) => {
    'id': exercise['id'],
    'name': exercise['name'],
    'categoryId': exercise['category_id'],
    'categoryName': exercise['category_name'],
    'categoryEnergySystem': exercise['category_energy'],
    'type': exercise['type'],
    'equipment': exercise['equipment'],
    'defaultRestTimeSeconds': exercise['default_rest_time'],
    'weightIncrement': (exercise['weight_increment'] as num?)?.toDouble(),
    'isFavorite': (exercise['is_favorite'] as num?)?.toInt() == 1,
  };

  String _workoutStatus(Map<dynamic, dynamic> workout) {
    if (workout['end_time'] != null) return 'completed';
    if (workout['start_time'] != null) return 'in_progress';
    return 'planned';
  }

  double? _average(Iterable<double> values) {
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }

  String _date(DateTime date) => date.toIso8601String().substring(0, 10);
}

class _RecordCandidate {
  final double value;
  final String unit;
  final Map<dynamic, dynamic> row;

  const _RecordCandidate(this.value, this.unit, this.row);
}
