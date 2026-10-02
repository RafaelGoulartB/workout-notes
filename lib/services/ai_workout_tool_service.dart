// Read-only queries built for the AI Coach may run SQL directly (a documented
// exception to the repository-only rule); writes never happen in this file.
import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/l10n/l10n_exercises.dart';
import 'package:workout_notes/models/nutrition/food.dart';
import 'package:workout_notes/repositories/strength_records_repository.dart';
import 'package:workout_notes/repositories/workout_repository.dart';
import 'package:workout_notes/services/ai_tool_math.dart';
import 'package:workout_notes/services/ai_tool_result_shaper.dart';
import 'package:workout_notes/services/ai_tool_spec.dart';
import 'package:workout_notes/utils/ai_json.dart';
import 'package:workout_notes/utils/ai_revision.dart';
import 'package:workout_notes/utils/date_utils.dart';

/// Read-only, AI-facing strength-training queries: workouts, exercises,
/// records, period summaries and routines.
///
/// Performance numbers count only finished workouts and completed,
/// non-warm-up sets. Planned sets stay visible in a workout's detail but never
/// count as work the user actually performed.
class AiWorkoutToolService {
  final DatabaseHelper db;
  final DateTime Function() _now;

  AiWorkoutToolService({DatabaseHelper? db, DateTime Function()? now})
    : db = db ?? DatabaseHelper.instance,
      _now = now ?? DateTime.now;

  /// The injected clock, so spec handlers resolve windows against the same
  /// "today" as the queries.
  DateTime now() => _now();

  static const String _countedSet = 's.is_complete = 1 AND s.is_warmup = 0';

  // -------------------------------------------------------------------------
  // Workouts
  // -------------------------------------------------------------------------

  /// One page of workouts, newest first. [status] is `all`, `completed`,
  /// `in_progress` or `planned`.
  Future<Map<String, dynamic>> history({
    String? startDate,
    String? endDate,
    String status = 'completed',
    int limit = 10,
    int page = 1,
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
    final total =
        (await rawDb.rawQuery(
              'SELECT COUNT(*) AS total FROM workouts w $whereSql',
              values,
            )).first['total']
            as int? ??
        0;
    final offset = (page - 1) * limit;
    const order =
        'w.date DESC, COALESCE(w.end_time, w.start_time, w.created_at) DESC';
    final rows = await rawDb.rawQuery(
      '''
      SELECT w.id, w.date, w.start_time, w.end_time, w.duration_seconds,
        w.estimated_calories, w.feeling_rating, w.comment,
        r.name AS routine_name,
        COUNT(DISTINCT ee.id) AS exercise_count,
        COUNT(CASE WHEN s.is_complete = 1 AND s.is_warmup = 0
          THEN 1 END) AS done_sets,
        COUNT(CASE WHEN s.id IS NOT NULL AND s.is_complete = 0
          THEN 1 END) AS open_sets,
        SUM(CASE WHEN s.is_complete = 1 AND s.is_warmup = 0
          THEN COALESCE(s.weight, 0) * COALESCE(s.reps, 0) END) AS volume_kg,
        SUM(CASE WHEN s.is_complete = 1 AND s.is_warmup = 0
          THEN s.distance END) AS distance,
        SUM(CASE WHEN s.is_complete = 1 AND s.is_warmup = 0
          THEN s.time_seconds END) AS time_s,
        AVG(CASE WHEN s.is_complete = 1 AND s.is_warmup = 0
          THEN s.rpe END) AS avg_rpe
      FROM (
        SELECT w.* FROM workouts w $whereSql
        ORDER BY $order LIMIT ? OFFSET ?
      ) w
      LEFT JOIN routines r ON r.id = w.routine_id
      LEFT JOIN exercise_entries ee ON ee.workout_id = w.id
      LEFT JOIN sets s ON s.exercise_entry_id = ee.id
      GROUP BY w.id
      ORDER BY $order
      ''',
      [...values, limit, offset],
    );
    final hasMore = offset + rows.length < total;
    return {
      'applied': {
        'start_date': startDate,
        'end_date': endDate,
        'status': status,
        'limit': limit,
        'page': page,
      },
      'total': total,
      'has_more': hasMore,
      'next_page': hasMore ? page + 1 : null,
      'workouts': [
        for (final row in rows)
          {
            'id': row['id'],
            'date': row['date'],
            'status': status == 'all' ? _status(row) : null,
            'duration_s': row['duration_seconds'],
            'calories': row['estimated_calories'],
            'feeling': row['feeling_rating'],
            'routine': row['routine_name'],
            'exercises': row['exercise_count'],
            'sets': _positive(row['done_sets']),
            'planned_sets': _positive(row['open_sets']),
            'volume_kg': _positive(row['volume_kg']),
            'distance': _positive(row['distance']),
            'time_s': _positive(row['time_s']),
            'avg_rpe': row['avg_rpe'],
            'comment': _clip(row['comment'] as String?, 120),
          },
      ],
    };
  }

  /// Every exercise and set of one workout, its records and how it compares
  /// with the previous comparable session.
  Future<Map<String, dynamic>> workoutDetail(String id) async {
    final workout = await db.workoutRepo.getWorkout(id);
    if (workout == null) {
      throw const AiToolNotFoundException(
        'workout not found',
        hint: 'call get_workout_history to get valid ids',
      );
    }
    final rawDb = await db.database;
    final rows = await rawDb.rawQuery(
      '''
      SELECT ee.id AS entry_id, ee.exercise_id, ee.superset_group_id,
        ee.notes AS entry_notes, e.name AS exercise_name,
        e.type AS exercise_type, e.locale_key, ec.name AS category_name,
        s.order_index AS set_order, s.weight, s.reps, s.distance,
        s.time_seconds, s.is_warmup, s.is_complete, s.rpe, s.comment,
        s.id AS set_id
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
    var doneSets = 0;
    var volume = 0.0;
    var reps = 0;
    var distance = 0.0;
    var timeSeconds = 0;
    final rpes = <double>[];
    for (final row in rows) {
      final entryId = row['entry_id'] as String;
      final entry = byEntry.putIfAbsent(
        entryId,
        () => {
          'exercise_id': row['exercise_id'],
          'name': row['exercise_name'],
          'type': row['exercise_type'],
          'category': row['category_name'],
          'superset': row['superset_group_id'] != null ? true : null,
          'notes': _clip(row['entry_notes'] as String?, 160),
          'sets': <String>[],
          'warmup': <String>[],
          'open': <String>[],
        },
      );
      if (row['set_id'] == null) continue;
      final complete = (row['is_complete'] as num?)?.toInt() == 1;
      final warmup = (row['is_warmup'] as num?)?.toInt() == 1;
      final weight = (row['weight'] as num?)?.toDouble();
      final setReps = (row['reps'] as num?)?.toInt();
      final setDistance = (row['distance'] as num?)?.toDouble();
      final setTime = (row['time_seconds'] as num?)?.toInt();
      final rpe = (row['rpe'] as num?)?.toDouble();
      // `sets` are performed working sets, `warmup` performed warm-ups and
      // `open` the sets still to do (planned or unchecked).
      final text = _setText(
        weight,
        setReps,
        setDistance,
        setTime,
        rpe,
        row['exercise_type'] as String? ?? 'weightReps',
      );
      (entry[!complete ? 'open' : (warmup ? 'warmup' : 'sets')]
              as List<String>)
          .add(text);
      if (complete && !warmup) {
        doneSets++;
        volume += (weight ?? 0) * (setReps ?? 0);
        reps += setReps ?? 0;
        distance += setDistance ?? 0;
        timeSeconds += setTime ?? 0;
        if (rpe != null) rpes.add(rpe);
      }
    }
    final finished = workout['end_time'] != null;
    final routineId = workout['routine_id'] as String?;
    final routineName = routineId == null
        ? null
        : (await rawDb.query(
            'routines',
            columns: ['name'],
            where: 'id = ?',
            whereArgs: [routineId],
            limit: 1,
          )).firstOrNull?['name'];
    return {
      'id': id,
      'date': workout['date'],
      'status': _status(workout),
      'started_at': workout['start_time'],
      'ended_at': workout['end_time'],
      'duration_s': workout['duration_seconds'],
      'calories': workout['estimated_calories'],
      'feeling': workout['feeling_rating'],
      'comment': workout['comment'],
      'routine_id': routineId,
      'routine': routineName,
      'totals': _status(workout) == 'planned'
          ? null
          : {
              'sets': doneSets,
              'volume_kg': volume,
              'reps': reps,
              'distance': distance > 0 ? distance : null,
              'time_s': timeSeconds > 0 ? timeSeconds : null,
              'avg_rpe': AiToolMath.average(rpes),
            },
      'exercises': [
        for (final entry in byEntry.values)
          {
            ...entry,
            'sets': (entry['sets'] as List<String>).join(', '),
            'warmup': (entry['warmup'] as List<String>).join(', '),
            'open': (entry['open'] as List<String>).join(', '),
          },
      ],
      if (finished) 'records': await _recordsIn(id),
      if (finished) 'comparison': await _comparison(id, volume, doneSets),
    };
  }

  Future<List<Map<String, dynamic>>> _recordsIn(String workoutId) async {
    final events = await db.strengthRecordsRepo.recordsInWorkout(workoutId);
    return [
      for (final event in events)
        {
          'exercise_id': event.exerciseId,
          'exercise': event.exerciseName,
          'kind': event.kind == StrengthRecordKind.e1rm ? 'e1rm' : 'weight',
          'weight': event.weight,
          'reps': event.reps,
          'value_kg': event.value,
          'previous_kg': event.previous,
        },
    ];
  }

  Future<Map<String, dynamic>?> _comparison(
    String workoutId,
    double volume,
    int doneSets,
  ) async {
    final comparable = await db.workoutRepo.findComparableWorkout(workoutId);
    if (comparable == null) return null;
    final rawDb = await db.database;
    final rows = await rawDb.rawQuery(
      '''
      SELECT w.duration_seconds,
        COUNT(CASE WHEN $_countedSet THEN 1 END) AS done_sets,
        SUM(CASE WHEN $_countedSet
          THEN COALESCE(s.weight, 0) * COALESCE(s.reps, 0) END) AS volume_kg
      FROM workouts w
      LEFT JOIN exercise_entries ee ON ee.workout_id = w.id
      LEFT JOIN sets s ON s.exercise_entry_id = ee.id
      WHERE w.id = ?
      ''',
      [comparable.id],
    );
    final previous = rows.first;
    final previousVolume = (previous['volume_kg'] as num?)?.toDouble();
    return {
      'workout_id': comparable.id,
      'date': comparable.date,
      'basis': switch (comparable.basis) {
        WorkoutComparisonBasis.routineDay => 'same_routine_day',
        WorkoutComparisonBasis.routine => 'same_routine',
        WorkoutComparisonBasis.exercises => 'shared_exercises',
      },
      'sets': previous['done_sets'],
      'volume_kg': previousVolume,
      'duration_s': previous['duration_seconds'],
      'volume_change_pct': AiToolMath.percentChange(previousVolume, volume),
      'sets_change': doneSets - ((previous['done_sets'] as int?) ?? 0),
    };
  }

  // -------------------------------------------------------------------------
  // Exercises
  // -------------------------------------------------------------------------

  /// Exercises with usage, optionally filtered. [search] matches the stored
  /// name and the English and Portuguese names of the built-in catalog,
  /// ignoring case and accents. [sort] is `name`, `most_recent` (last trained
  /// first) or `least_recent` (trained longest ago first, never-trained last).
  Future<Map<String, dynamic>> listExercises({
    String? search,
    String? categoryId,
    bool? favorites,
    String sort = 'name',
    int limit = 20,
  }) async {
    final rows = await db.exerciseRepo.getExercises(
      categoryId: categoryId,
      favorites: favorites,
    );
    final usage = await db.exerciseRepo.getExerciseUsage();
    final today = dayOf(_now());
    final needle = search == null ? '' : Food.normalizeForSearch(search);
    final matches = <Map<String, dynamic>>[];
    for (final row in rows) {
      if (needle.isNotEmpty && !_matches(row, needle)) continue;
      final used = usage[row['id']];
      final last = used?.lastDate;
      matches.add({
        ..._exerciseNames(row),
        'id': row['id'],
        'category_id': row['category_id'],
        'type': row['type'],
        'equipment': row['equipment'],
        'favorite': (row['is_favorite'] as num?)?.toInt() == 1 ? true : null,
        'sessions': used?.sessions,
        'last_trained': last == null ? null : dateKey(last),
        'days_since': last == null ? null : _daysBetween(last, today),
        '_category_name': row['category_name'],
      });
    }
    int byLast(Map<String, dynamic> a, Map<String, dynamic> b, int direction) {
      final left = a['last_trained'] as String?;
      final right = b['last_trained'] as String?;
      if (left == null && right == null) return 0;
      if (left == null) return 1;
      if (right == null) return -1;
      return direction * left.compareTo(right);
    }

    switch (sort) {
      case 'least_recent':
        matches.sort((a, b) => byLast(a, b, 1));
      case 'most_recent':
        matches.sort((a, b) => byLast(a, b, -1));
    }
    final page = matches.take(limit).toList();
    final categories = <String, String>{};
    for (final item in page) {
      final name = item.remove('_category_name') as String?;
      if (name != null) categories[item['category_id'] as String] = name;
    }
    for (final item in matches.skip(limit)) {
      item.remove('_category_name');
    }
    return {
      'applied': {'sort': sort, 'limit': limit},
      'total': matches.length,
      'has_more': matches.length > limit,
      'categories': categories,
      'exercises': page,
    };
  }

  bool _matches(Map<String, dynamic> row, String needle) {
    final names = <String>[
      row['name'] as String? ?? '',
      if (row['locale_key'] != null) ...[
        ?ExerciseLocalization.exerciseName(row['locale_key'] as String, 'en'),
        ?ExerciseLocalization.exerciseName(row['locale_key'] as String, 'pt'),
      ],
    ];
    return names.any((name) => Food.normalizeForSearch(name).contains(needle));
  }

  /// `name` (as stored) plus `name_en` when the built-in English name differs.
  Map<String, dynamic> _exerciseNames(Map<String, dynamic> row) {
    final stored = row['name'] as String? ?? '';
    final key = row['locale_key'] as String?;
    final english = key == null
        ? null
        : ExerciseLocalization.exerciseName(key, 'en');
    return {
      'name': stored,
      'name_en': english != null && english.toLowerCase() != stored.toLowerCase()
          ? english
          : null,
    };
  }

  /// Profile of an exercise plus its all-time usage, shared by
  /// [exerciseHistory].
  Future<Map<String, dynamic>> _exerciseProfile(
    String id,
    Map<String, dynamic> exercise,
  ) async {
    final rawDb = await db.database;
    final usage = await rawDb.rawQuery(
      '''
      SELECT COUNT(DISTINCT w.id) AS sessions, COUNT(s.id) AS work_sets,
        MIN(w.date) AS first_trained, MAX(w.date) AS last_trained
      FROM exercise_entries ee
      JOIN workouts w ON w.id = ee.workout_id AND w.end_time IS NOT NULL
      JOIN sets s ON s.exercise_entry_id = ee.id AND $_countedSet
      WHERE ee.exercise_id = ?
      ''',
      [id],
    );
    final stats = usage.first;
    final last = DateTime.tryParse((stats['last_trained'] as String?) ?? '');
    return {
      'id': id,
      ..._exerciseNames(exercise),
      'category_id': exercise['category_id'],
      'category': exercise['category_name'],
      'type': exercise['type'],
      'equipment': exercise['equipment'],
      'notes': _clip(exercise['notes'] as String?, 240),
      'favorite': (exercise['is_favorite'] as num?)?.toInt() == 1 ? true : null,
      'default_rest_s': exercise['default_rest_time'],
      'weight_increment_kg': exercise['weight_increment'],
      'total_sessions': stats['sessions'],
      'total_sets': stats['work_sets'],
      'first_trained': stats['first_trained'],
      'last_trained': stats['last_trained'],
      'days_since': last == null ? null : _daysBetween(last, dayOf(_now())),
    };
  }

  /// An exercise's profile and usage, its newest [limit] sessions and a trend
  /// over the whole window: estimated 1RM slope, best, and last versus first
  /// session.
  Future<Map<String, dynamic>> exerciseHistory(
    String exerciseId, {
    String? startDate,
    String? endDate,
    int limit = 8,
  }) async {
    final exercise = await db.exerciseRepo.getExercise(exerciseId);
    if (exercise == null) throw _exerciseNotFound();
    final rawDb = await db.database;
    final where = <String>[
      'ee.exercise_id = ?',
      'w.end_time IS NOT NULL',
      _countedSet,
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
      SELECT w.id AS workout_id, w.date, s.weight, s.reps, s.distance,
        s.time_seconds, s.rpe
      FROM sets s
      JOIN exercise_entries ee ON ee.id = s.exercise_entry_id
      JOIN workouts w ON w.id = ee.workout_id
      WHERE ${where.join(' AND ')}
      ORDER BY w.date DESC, COALESCE(w.end_time, w.start_time) DESC,
        s.order_index ASC
      LIMIT 2000
    ''', values);
    final type = exercise['type'] as String? ?? 'weightReps';
    final sessions = <_Session>[];
    final byWorkout = <String, _Session>{};
    for (final row in rows) {
      final workoutId = row['workout_id'] as String;
      final session = byWorkout.putIfAbsent(workoutId, () {
        final created = _Session(workoutId, row['date'] as String);
        sessions.add(created);
        return created;
      });
      session.add(row, type);
    }
    final trend = _trend(sessions, type);
    return {
      ...await _exerciseProfile(exerciseId, exercise),
      'applied': {
        'start_date': startDate,
        'end_date': endDate,
        'limit': limit,
      },
      'session_count': sessions.length,
      'trend': trend,
      'sessions': [for (final session in sessions.take(limit)) session.toMap()],
    };
  }

  Map<String, dynamic>? _trend(List<_Session> sessions, String type) {
    if (sessions.isEmpty) return null;
    final ordered = sessions.reversed.toList(); // oldest first
    final first = ordered.first;
    final last = ordered.last;
    final e1rmPoints = <(double, double)>[];
    final firstDate = DateTime.parse(first.date);
    for (final session in ordered) {
      final e1rm = session.bestE1rm;
      if (e1rm == null) continue;
      final days = daysBetween(firstDate, DateTime.parse(session.date));
      e1rmPoints.add((days / 7, e1rm));
    }
    _Session? bestSession;
    for (final session in ordered) {
      final e1rm = session.bestE1rm;
      if (e1rm == null) continue;
      if (bestSession == null || e1rm > bestSession.bestE1rm!) {
        bestSession = session;
      }
    }
    final volumes = ordered.map((s) => s.volume).toList();
    final half = volumes.length ~/ 2;
    final earlier = half == 0 ? null : AiToolMath.average(volumes.take(half));
    final recent = half == 0 ? null : AiToolMath.average(volumes.skip(half));
    return {
      'first_date': first.date,
      'last_date': last.date,
      'first_e1rm_kg': first.bestE1rm,
      'last_e1rm_kg': last.bestE1rm,
      'best_e1rm_kg': bestSession?.bestE1rm,
      'best_e1rm_date': bestSession?.date,
      'e1rm_change_pct': AiToolMath.percentChange(
        first.bestE1rm,
        last.bestE1rm,
      ),
      'e1rm_slope_kg_per_week': AiToolMath.slopeXY(e1rmPoints),
      'top_weight_first_kg': first.topWeight,
      'top_weight_last_kg': last.topWeight,
      'top_weight_best_kg': ordered
          .map((s) => s.topWeight)
          .whereType<double>()
          .fold<double?>(null, (a, b) => a == null || b > a ? b : a),
      'volume_change_pct': AiToolMath.percentChange(earlier, recent),
    };
  }

  /// Recent personal records of every exercise (no [exerciseId]) or the best
  /// marks of one exercise plus its recent records.
  Future<Map<String, dynamic>> personalRecords({
    String? exerciseId,
    required AiDateWindow window,
    int limit = 15,
  }) async {
    final since = window.start;
    final recentEvents = await db.strengthRecordsRepo.recentRecords(
      limit: 500,
      since: since,
    );
    final filtered = recentEvents
        .where(
          (event) =>
              (exerciseId == null || event.exerciseId == exerciseId) &&
              event.date.isBefore(addDays(window.end, 1)),
        )
        .toList();
    Map<String, dynamic> eventRow(StrengthRecordEvent event) => {
      'date': dateKey(event.date),
      if (exerciseId == null) 'exercise_id': event.exerciseId,
      if (exerciseId == null) 'exercise': event.exerciseName,
      'kind': event.kind == StrengthRecordKind.e1rm ? 'e1rm' : 'weight',
      'weight': event.weight,
      'reps': event.reps,
      'value_kg': event.value,
      'previous_kg': event.previous,
      'workout_id': event.workoutId,
    };
    final rows = [for (final event in filtered.take(limit)) eventRow(event)];
    if (exerciseId == null) {
      return {
        'applied': window.toApplied(),
        'total': filtered.length,
        'has_more': filtered.length > limit,
        'records': rows,
      };
    }
    final exercise = await db.exerciseRepo.getExercise(exerciseId);
    if (exercise == null) throw _exerciseNotFound();
    return {
      'applied': window.toApplied(),
      'id': exerciseId,
      'name': exercise['name'],
      'type': exercise['type'],
      'best': await _bestMarks(exerciseId),
      'recent_records': rows,
    };
  }

  Future<List<Map<String, dynamic>>> _bestMarks(String exerciseId) async {
    final rawDb = await db.database;
    final rows = await rawDb.rawQuery(
      '''
      SELECT w.id AS workout_id, w.date, s.weight, s.reps, s.distance,
        s.time_seconds
      FROM sets s
      JOIN exercise_entries ee ON ee.id = s.exercise_entry_id
      JOIN workouts w ON w.id = ee.workout_id
      WHERE ee.exercise_id = ? AND w.end_time IS NOT NULL AND $_countedSet
      ORDER BY w.date ASC
      LIMIT 5000
      ''',
      [exerciseId],
    );
    final best = <String, _Mark>{};
    void consider(String metric, double? value, Map<String, Object?> row, {bool lower = false}) {
      if (value == null || value <= 0) return;
      final current = best[metric];
      if (current == null || (lower ? value < current.value : value > current.value)) {
        best[metric] = _Mark(value, row);
      }
    }

    final sessionVolume = <String, double>{};
    final sessionRow = <String, Map<String, Object?>>{};
    for (final row in rows) {
      final weight = (row['weight'] as num?)?.toDouble();
      final reps = (row['reps'] as num?)?.toInt();
      final distance = (row['distance'] as num?)?.toDouble();
      final time = (row['time_seconds'] as num?)?.toDouble();
      consider('max_weight_kg', weight, row);
      consider('max_reps', reps?.toDouble(), row);
      consider(
        'best_e1rm_kg',
        weight == null || reps == null ? null : strengthE1rm(weight, reps),
        row,
      );
      consider(
        'best_set_volume_kg',
        weight != null && reps != null ? weight * reps : null,
        row,
      );
      consider('max_distance', distance, row);
      consider('longest_time_s', time, row);
      if (time != null && distance != null && distance > 0) {
        consider('best_pace_s_per_distance', time / distance, row, lower: true);
      }
      final workoutId = row['workout_id'] as String;
      sessionVolume[workoutId] =
          (sessionVolume[workoutId] ?? 0) +
          (weight ?? 0) * (reps ?? 0);
      sessionRow[workoutId] = row;
    }
    String? bestSession;
    sessionVolume.forEach((id, volume) {
      if (volume > 0 &&
          (bestSession == null || volume > sessionVolume[bestSession]!)) {
        bestSession = id;
      }
    });
    if (bestSession != null) {
      best['best_session_volume_kg'] = _Mark(
        sessionVolume[bestSession]!,
        sessionRow[bestSession]!,
      );
    }
    return [
      for (final entry in best.entries)
        {
          'metric': entry.key,
          'value': entry.value.value,
          'reps': entry.key == 'max_weight_kg' || entry.key == 'best_e1rm_kg'
              ? entry.value.row['reps']
              : null,
          'date': entry.value.row['date'],
          'workout_id': entry.value.row['workout_id'],
        },
    ];
  }

  AiToolNotFoundException _exerciseNotFound() => const AiToolNotFoundException(
    'exercise not found',
    hint: 'call list_exercises to get valid ids',
  );

  // -------------------------------------------------------------------------
  // Period summary
  // -------------------------------------------------------------------------

  /// Training volume, frequency and effort for [window], compared with the
  /// previous window of the same length, optionally broken down by `week` or
  /// `category`.
  Future<Map<String, dynamic>> trainingSummary({
    required AiDateWindow window,
    String? groupBy,
  }) async {
    final rawDb = await db.database;
    final today = dayOf(_now());
    final startKey = window.startKey;
    final endKey = window.endKey;
    final current = await _periodTotals(rawDb, startKey, endKey);
    final days = window.days;
    final previousStart = addDays(window.start, -days);
    final previousEnd = addDays(window.start, -1);
    final previous = await _periodTotals(
      rawDb,
      dateKey(previousStart),
      dateKey(previousEnd),
    );
    final lastDay = window.end.isAfter(today) ? today : window.end;
    final elapsedDays = lastDay.isBefore(window.start)
        ? 0
        : AiDateWindow(window.start, lastDay).days;
    final completed = current['completed'] as int;
    final topExercises = await rawDb.rawQuery(
      '''
      SELECT e.id AS exercise_id, e.name,
        COUNT(DISTINCT w.id) AS sessions, COUNT(s.id) AS sets,
        SUM(COALESCE(s.weight, 0) * COALESCE(s.reps, 0)) AS volume_kg
      FROM sets s
      JOIN exercise_entries ee ON ee.id = s.exercise_entry_id
      JOIN exercises e ON e.id = ee.exercise_id
      JOIN workouts w ON w.id = ee.workout_id
      WHERE w.end_time IS NOT NULL AND w.date >= ? AND w.date <= ?
        AND $_countedSet
      GROUP BY e.id ORDER BY sessions DESC, sets DESC LIMIT 8
      ''',
      [startKey, endKey],
    );
    final volume = current['volume_kg'] as double;
    final previousVolume = previous['volume_kg'] as double;
    final duration = current['duration_s'] as int;
    return {
      'applied': {...window.toApplied(), 'group_by': groupBy},
      'workouts': {
        'completed': completed,
        'in_progress': current['in_progress'],
        'planned_upcoming': current['planned_upcoming'],
        'missed': current['missed'],
        'active_days': current['active_days'],
        'per_week': elapsedDays == 0 ? null : completed / elapsedDays * 7,
      },
      'totals': {
        'duration_s': duration,
        'calories': current['calories'],
        'avg_feeling': current['avg_feeling'],
        'sets': current['sets'],
        'volume_kg': volume,
        'reps': current['reps'],
        'distance': (current['distance'] as double) > 0
            ? current['distance']
            : null,
        'time_s': (current['time_s'] as int) > 0 ? current['time_s'] : null,
        'avg_rpe': current['avg_rpe'],
        'volume_kg_per_min': duration > 0 ? volume / (duration / 60) : null,
      },
      'previous_period': {
        'start_date': dateKey(previousStart),
        'end_date': dateKey(previousEnd),
        'workouts': previous['completed'],
        'sets': previous['sets'],
        'volume_kg': previousVolume,
        'workouts_change': completed - (previous['completed'] as int),
        'sets_change_pct': AiToolMath.percentChange(
          (previous['sets'] as int).toDouble(),
          (current['sets'] as int).toDouble(),
        ),
        'volume_change_pct': AiToolMath.percentChange(previousVolume, volume),
      },
      'top_exercises': topExercises,
      if (groupBy == 'week')
        'by_week': await _byWeek(rawDb, window, lastDay),
      if (groupBy == 'category') 'by_category': await _byCategory(rawDb, window),
    };
  }

  Future<Map<String, dynamic>> _periodTotals(
    DatabaseExecutor rawDb,
    String startKey,
    String endKey,
  ) async {
    final today = dateKey(dayOf(_now()));
    final statusRows = await rawDb.rawQuery(
      '''
      SELECT
        SUM(CASE WHEN end_time IS NOT NULL THEN 1 ELSE 0 END) AS completed,
        SUM(CASE WHEN end_time IS NULL AND start_time IS NOT NULL
          THEN 1 ELSE 0 END) AS in_progress,
        SUM(CASE WHEN start_time IS NULL AND date >= ? THEN 1 ELSE 0 END)
          AS planned_upcoming,
        SUM(CASE WHEN start_time IS NULL AND date < ? THEN 1 ELSE 0 END)
          AS missed,
        COUNT(DISTINCT CASE WHEN end_time IS NOT NULL THEN date END)
          AS active_days,
        SUM(CASE WHEN end_time IS NOT NULL THEN COALESCE(duration_seconds, 0)
          ELSE 0 END) AS duration_s,
        SUM(CASE WHEN end_time IS NOT NULL THEN estimated_calories END)
          AS calories,
        AVG(CASE WHEN end_time IS NOT NULL THEN feeling_rating END)
          AS avg_feeling
      FROM workouts WHERE date >= ? AND date <= ?
      ''',
      [today, today, startKey, endKey],
    );
    final setRows = await rawDb.rawQuery(
      '''
      SELECT COUNT(s.id) AS sets,
        COALESCE(SUM(COALESCE(s.weight, 0) * COALESCE(s.reps, 0)), 0)
          AS volume_kg,
        COALESCE(SUM(COALESCE(s.reps, 0)), 0) AS reps,
        COALESCE(SUM(COALESCE(s.distance, 0)), 0) AS distance,
        COALESCE(SUM(COALESCE(s.time_seconds, 0)), 0) AS time_s,
        AVG(s.rpe) AS avg_rpe
      FROM sets s
      JOIN exercise_entries ee ON ee.id = s.exercise_entry_id
      JOIN workouts w ON w.id = ee.workout_id
      WHERE w.end_time IS NOT NULL AND w.date >= ? AND w.date <= ?
        AND $_countedSet
      ''',
      [startKey, endKey],
    );
    final status = statusRows.first;
    final sets = setRows.first;
    return {
      'completed': (status['completed'] as num?)?.toInt() ?? 0,
      'in_progress': (status['in_progress'] as num?)?.toInt() ?? 0,
      'planned_upcoming': (status['planned_upcoming'] as num?)?.toInt() ?? 0,
      'missed': (status['missed'] as num?)?.toInt() ?? 0,
      'active_days': (status['active_days'] as num?)?.toInt() ?? 0,
      'duration_s': (status['duration_s'] as num?)?.toInt() ?? 0,
      'calories': (status['calories'] as num?)?.toDouble(),
      'avg_feeling': (status['avg_feeling'] as num?)?.toDouble(),
      'sets': (sets['sets'] as num?)?.toInt() ?? 0,
      'volume_kg': (sets['volume_kg'] as num?)?.toDouble() ?? 0.0,
      'reps': (sets['reps'] as num?)?.toInt() ?? 0,
      'distance': (sets['distance'] as num?)?.toDouble() ?? 0.0,
      'time_s': (sets['time_s'] as num?)?.toInt() ?? 0,
      'avg_rpe': (sets['avg_rpe'] as num?)?.toDouble(),
    };
  }

  /// Monday-based weeks of the window, newest first. Weeks that are not
  /// fully inside the window (or not over yet) are marked `partial`.
  Future<List<Map<String, dynamic>>> _byWeek(
    DatabaseExecutor rawDb,
    AiDateWindow window,
    DateTime lastDay,
  ) async {
    const monday =
        "date(w.date, '-' || ((CAST(strftime('%w', w.date) AS INTEGER) + 6) % 7) || ' days')";
    final workoutRows = await rawDb.rawQuery(
      '''
      SELECT $monday AS week_start, COUNT(*) AS workouts,
        SUM(COALESCE(w.duration_seconds, 0)) AS duration_s,
        AVG(w.feeling_rating) AS avg_feeling
      FROM workouts w
      WHERE w.end_time IS NOT NULL AND w.date >= ? AND w.date <= ?
      GROUP BY week_start
      ''',
      [window.startKey, window.endKey],
    );
    final setRows = await rawDb.rawQuery(
      '''
      SELECT $monday AS week_start, COUNT(s.id) AS sets,
        SUM(COALESCE(s.weight, 0) * COALESCE(s.reps, 0)) AS volume_kg
      FROM sets s
      JOIN exercise_entries ee ON ee.id = s.exercise_entry_id
      JOIN workouts w ON w.id = ee.workout_id
      WHERE w.end_time IS NOT NULL AND w.date >= ? AND w.date <= ?
        AND $_countedSet
      GROUP BY week_start
      ''',
      [window.startKey, window.endKey],
    );
    final workoutsByWeek = {
      for (final row in workoutRows) row['week_start'] as String: row,
    };
    final setsByWeek = {
      for (final row in setRows) row['week_start'] as String: row,
    };
    final out = <Map<String, dynamic>>[];
    var week = mondayOf(lastDay);
    final firstWeek = mondayOf(window.start);
    while (!week.isBefore(firstWeek)) {
      final key = dateKey(week);
      final weekEnd = addDays(week, 6);
      final partial =
          week.isBefore(window.start) || weekEnd.isAfter(lastDay);
      out.add({
        'week_start': key,
        'workouts': workoutsByWeek[key]?['workouts'] ?? 0,
        'sets': setsByWeek[key]?['sets'] ?? 0,
        'volume_kg': setsByWeek[key]?['volume_kg'] ?? 0,
        'duration_s': workoutsByWeek[key]?['duration_s'],
        'avg_feeling': workoutsByWeek[key]?['avg_feeling'],
        'partial': partial ? true : null,
      });
      week = addDays(week, -7);
    }
    return out;
  }

  /// Every category (also the untouched ones) with its activity in the window
  /// and the last time it was ever trained.
  Future<List<Map<String, dynamic>>> _byCategory(
    DatabaseExecutor rawDb,
    AiDateWindow window,
  ) async {
    final today = dayOf(_now());
    final categories = await rawDb.query(
      'exercise_categories',
      orderBy: 'order_index ASC',
    );
    final inWindow = await rawDb.rawQuery(
      '''
      SELECT e.category_id, COUNT(s.id) AS sets, COUNT(DISTINCT w.id) AS sessions,
        SUM(COALESCE(s.weight, 0) * COALESCE(s.reps, 0)) AS volume_kg
      FROM sets s
      JOIN exercise_entries ee ON ee.id = s.exercise_entry_id
      JOIN exercises e ON e.id = ee.exercise_id
      JOIN workouts w ON w.id = ee.workout_id
      WHERE w.end_time IS NOT NULL AND w.date >= ? AND w.date <= ?
        AND $_countedSet
      GROUP BY e.category_id
      ''',
      [window.startKey, window.endKey],
    );
    final lastTrained = await rawDb.rawQuery(
      '''
      SELECT e.category_id, MAX(w.date) AS last_trained
      FROM sets s
      JOIN exercise_entries ee ON ee.id = s.exercise_entry_id
      JOIN exercises e ON e.id = ee.exercise_id
      JOIN workouts w ON w.id = ee.workout_id
      WHERE w.end_time IS NOT NULL AND $_countedSet
      GROUP BY e.category_id
      ''',
    );
    final windowByCategory = {
      for (final row in inWindow) row['category_id'] as String: row,
    };
    final lastByCategory = {
      for (final row in lastTrained)
        row['category_id'] as String: row['last_trained'] as String?,
    };
    final rows = <Map<String, dynamic>>[
      for (final category in categories)
        {
          'category_id': category['id'],
          'name': category['name'],
          'energy_system': category['energy_system'],
          'sets': windowByCategory[category['id']]?['sets'] ?? 0,
          'sessions': windowByCategory[category['id']]?['sessions'] ?? 0,
          'volume_kg': windowByCategory[category['id']]?['volume_kg'] ?? 0,
          'last_trained': lastByCategory[category['id']],
          'days_since': lastByCategory[category['id']] == null
              ? null
              : _daysBetween(
                  DateTime.parse(lastByCategory[category['id']]!),
                  today,
                ),
        },
    ];
    rows.sort((a, b) => (b['sets'] as num).compareTo(a['sets'] as num));
    return rows;
  }

  // -------------------------------------------------------------------------
  // Routines
  // -------------------------------------------------------------------------

  Future<Map<String, dynamic>> listRoutines({String? nameContains}) async {
    final rawDb = await db.database;
    final needle = nameContains == null
        ? null
        : '%${nameContains.toLowerCase()}%';
    final rows = await rawDb.rawQuery(
      '''
      SELECT r.id, r.name, r.notes,
        (SELECT COUNT(*) FROM routine_days rd WHERE rd.routine_id = r.id)
          AS day_count,
        (SELECT COUNT(*) FROM routine_exercises re
          JOIN routine_days rd ON rd.id = re.routine_day_id
          WHERE rd.routine_id = r.id) AS exercise_count,
        (SELECT MAX(w.date) FROM workouts w
          WHERE w.routine_id = r.id AND w.end_time IS NOT NULL) AS last_used
      FROM routines r
      WHERE (? IS NULL OR LOWER(r.name) LIKE ?)
      ORDER BY r.created_at DESC
      LIMIT 40
      ''',
      [needle, needle],
    );
    return {
      'routines': [
        for (final row in rows)
          {
            'id': row['id'],
            'name': row['name'],
            'days': row['day_count'],
            'exercises': row['exercise_count'],
            'last_used': row['last_used'],
            'notes': _clip(row['notes'] as String?, 100),
          },
      ],
    };
  }

  /// A routine's full tree. Only the `source_*` ids a later edit needs are
  /// returned (each exactly once). Without [dayId] it returns as many days as
  /// fit the result budget and lists the rest under `more_days`.
  Future<Map<String, dynamic>> routineDetail(
    String routineId, {
    String? dayId,
  }) async {
    final routine = await db.routineRepo.getRoutine(routineId);
    if (routine == null) {
      throw const AiToolNotFoundException(
        'routine not found',
        hint: 'call list_routines to get valid ids',
      );
    }
    final rawDb = await db.database;
    final rows = await rawDb.rawQuery(
      '''
      SELECT rd.id AS day_id, rd.name AS day_name, rd.notes AS day_notes,
        re.id AS routine_exercise_id, re.exercise_id,
        e.name AS exercise_name, e.type AS exercise_type,
        re.rest_time_seconds, re.superset_group_id,
        ps.id AS set_id, ps.weight, ps.reps, ps.distance, ps.time_seconds,
        ps.is_warmup
      FROM routine_days rd
      LEFT JOIN routine_exercises re ON re.routine_day_id = rd.id
      LEFT JOIN exercises e ON e.id = re.exercise_id
      LEFT JOIN predefined_sets ps ON ps.routine_exercise_id = re.id
      WHERE rd.routine_id = ?
      ORDER BY rd.order_index ASC, rd.id ASC, re.order_index ASC, re.id ASC,
        ps.order_index ASC, ps.id ASC
      ''',
      [routineId],
    );
    final days = <Map<String, dynamic>>[];
    final byDay = <String, Map<String, dynamic>>{};
    final byExercise = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final id = row['day_id'] as String;
      final day = byDay.putIfAbsent(id, () {
        final created = <String, dynamic>{
          'source_day_id': id,
          'name': row['day_name'],
          'notes': _clip(row['day_notes'] as String?, 120),
          'exercises': <Map<String, dynamic>>[],
        };
        days.add(created);
        return created;
      });
      final exerciseId = row['routine_exercise_id'] as String?;
      if (exerciseId == null) continue;
      final exercise = byExercise.putIfAbsent(exerciseId, () {
        final created = <String, dynamic>{
          'source_routine_exercise_id': exerciseId,
          'exercise_id': row['exercise_id'],
          'name': row['exercise_name'],
          'type': row['exercise_type'],
          'rest_s': row['rest_time_seconds'],
          'superset_group_id': row['superset_group_id'],
          'sets': <Map<String, dynamic>>[],
        };
        (day['exercises'] as List<Map<String, dynamic>>).add(created);
        return created;
      });
      if (row['set_id'] != null) {
        (exercise['sets'] as List<Map<String, dynamic>>).add({
          'source_set_id': row['set_id'],
          'weight': row['weight'],
          'reps': row['reps'],
          'distance': row['distance'],
          'time_s': row['time_seconds'],
          'warmup': (row['is_warmup'] as num?)?.toInt() == 1 ? true : null,
        });
      }
    }
    final revision = await routineRevision(rawDb, routineId);
    var selected = days;
    if (dayId != null) {
      selected = days.where((day) => day['source_day_id'] == dayId).toList();
      if (selected.isEmpty) {
        throw const AiToolNotFoundException(
          'routine day not found',
          hint: 'use a source_day_id from get_routine_detail',
        );
      }
    }
    final more = <Map<String, dynamic>>[];
    if (dayId == null) {
      // Keep the whole routine under the result budget: the remaining days
      // are one call away through `day_id`.
      var used = 0;
      final kept = <Map<String, dynamic>>[];
      for (final day in days) {
        final size = _shapedSize(day);
        if (kept.isNotEmpty && used + size > _routineBudget) {
          more.add({
            'source_day_id': day['source_day_id'],
            'name': day['name'],
            'exercises': (day['exercises'] as List).length,
          });
          continue;
        }
        used += size;
        kept.add(day);
      }
      selected = kept;
    }
    return {
      'id': routineId,
      'name': routine['name'],
      'notes': _clip(routine['notes'] as String?, 160),
      'revision': revision,
      'days': selected,
      if (more.isNotEmpty) 'more_days': more,
      if (more.isNotEmpty) 'has_more': true,
    };
  }

  static int _shapedSize(Map<String, dynamic> day) =>
      AiToolResultShaper.encodedLength(
        const AiToolResultShaper(maxChars: 1 << 30).shape({'day': day}),
      );

  /// Budget (in approximate shaped characters) for the days of one
  /// `get_routine_detail` call.
  static const int _routineBudget = 4600;

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  static String _status(Map<dynamic, dynamic> workout) {
    if (workout['end_time'] != null) return 'completed';
    if (workout['start_time'] != null) return 'in_progress';
    return 'planned';
  }

  static Object? _positive(Object? value) {
    final number = value as num?;
    return number == null || number <= 0 ? null : number;
  }

  static String? _clip(String? text, int max) {
    if (text == null) return null;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    return trimmed.length <= max ? trimmed : '${trimmed.substring(0, max)}...';
  }

  static int _daysBetween(DateTime from, DateTime to) {
    var days = 0;
    var cursor = dayOf(from);
    final end = dayOf(to);
    if (cursor.isAfter(end)) return 0;
    while (cursor.isBefore(end)) {
      cursor = addDays(cursor, 1);
      days++;
    }
    return days;
  }
}

class _Mark {
  final double value;
  final Map<String, Object?> row;

  const _Mark(this.value, this.row);
}

/// One finished session of an exercise, accumulated set by set.
class _Session {
  final String workoutId;
  final String date;
  final List<String> setTexts = [];
  int sets = 0;
  double volume = 0;
  double? topWeight;
  int? topWeightReps;
  double? bestE1rm;
  double distance = 0;
  int timeSeconds = 0;
  final List<double> rpes = [];

  _Session(this.workoutId, this.date);

  void add(Map<String, Object?> row, String type) {
    final weight = (row['weight'] as num?)?.toDouble();
    final reps = (row['reps'] as num?)?.toInt();
    final dist = (row['distance'] as num?)?.toDouble();
    final time = (row['time_seconds'] as num?)?.toInt();
    final rpe = (row['rpe'] as num?)?.toDouble();
    sets++;
    volume += (weight ?? 0) * (reps ?? 0);
    distance += dist ?? 0;
    timeSeconds += time ?? 0;
    if (rpe != null) rpes.add(rpe);
    if (weight != null && weight > 0) {
      if (topWeight == null || weight > topWeight!) {
        topWeight = weight;
        topWeightReps = reps;
      }
    }
    if (weight != null && reps != null) {
      final e1rm = strengthE1rm(weight, reps);
      if (e1rm != null && (bestE1rm == null || e1rm > bestE1rm!)) {
        bestE1rm = e1rm;
      }
    }
    setTexts.add(_setText(weight, reps, dist, time, rpe, type));
  }

  Map<String, dynamic> toMap() => {
    'workout_id': workoutId,
    'date': date,
    'sets': setTexts.join(', '),
    'work_sets': sets,
    'volume_kg': volume > 0 ? volume : null,
    'top_weight_kg': topWeight,
    'top_weight_reps': topWeightReps,
    'best_e1rm_kg': bestE1rm,
    'distance': distance > 0 ? distance : null,
    'time_s': timeSeconds > 0 ? timeSeconds : null,
    'avg_rpe': AiToolMath.average(rpes),
  };
}

String _clock(int seconds) =>
    '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

/// A set as one short token: `80x10` (weight x reps, `BWx10` bodyweight),
/// `x15` reps only, `45s` timed, `5/25:00` distance/time; `@8` appends RPE.
String _setText(
  double? weight,
  int? reps,
  double? distance,
  int? time,
  double? rpe,
  String type,
) {
  final buffer = StringBuffer();
  switch (type) {
    case 'distanceTime':
      buffer.write('${AiJson.formatNumber(distance ?? 0)}/${_clock(time ?? 0)}');
    case 'timeOnly':
      buffer.write('${time ?? 0}s');
    case 'repsOnly':
      buffer.write('x${reps ?? 0}');
    default:
      buffer.write(
        weight != null && weight > 0
            ? '${AiJson.formatNumber(weight)}x${reps ?? 0}'
            : 'BWx${reps ?? 0}',
      );
  }
  if (rpe != null) buffer.write('@${AiJson.formatNumber(rpe)}');
  return buffer.toString();
}
