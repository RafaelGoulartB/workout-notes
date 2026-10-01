import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/repositories/base_repository.dart';
import 'package:workout_notes/utils/ai_derived_id.dart';

/// SQL behind AI routine proposals: the routine tree snapshot used for diffs,
/// exercise lookups and the two write paths (insert-only create, two-phase
/// update). Every method runs on the executor it is given so the routine
/// handler can fold them into the approval transaction; the rules
/// (validation, diff) live in the routine proposal handler.
class AiRoutineMutationRepository extends BaseRepository {
  /// Snapshot of a routine (days, exercises, predefined sets) using the
  /// `source_*_id` keys proposals refer to, or null when it does not exist.
  Future<Map<String, dynamic>?> loadRoutineTree(
    DatabaseExecutor executor,
    String id,
  ) async {
    final routineRows = await executor.query(
      'routines',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (routineRows.isEmpty) return null;
    final routine = routineRows.first;
    final rows = await executor.rawQuery(
      '''
      SELECT d.id AS day_id, d.name AS day_name, d.notes AS day_notes,
        re.id AS re_id, re.exercise_id, re.rest_time_seconds,
        re.superset_group_id,
        ps.id AS set_id, ps.weight, ps.reps, ps.distance, ps.time_seconds,
        ps.is_warmup
      FROM routine_days d
      LEFT JOIN routine_exercises re ON re.routine_day_id = d.id
      LEFT JOIN predefined_sets ps ON ps.routine_exercise_id = re.id
      WHERE d.routine_id = ?
      ORDER BY d.order_index, d.id, re.order_index, re.id, ps.order_index, ps.id
      ''',
      [id],
    );
    final days = <Map<String, dynamic>>[];
    Map<String, dynamic>? day;
    Map<String, dynamic>? exercise;
    for (final row in rows) {
      if (day == null || day['source_day_id'] != row['day_id']) {
        day = {
          'source_day_id': row['day_id'],
          'name': row['day_name'],
          'notes': row['day_notes'],
          'exercises': <Map<String, dynamic>>[],
        };
        days.add(day);
        exercise = null;
      }
      final reId = row['re_id'];
      if (reId == null) continue;
      if (exercise == null || exercise['source_routine_exercise_id'] != reId) {
        exercise = {
          'source_routine_exercise_id': reId,
          'exercise_id': row['exercise_id'],
          'rest_time_seconds': row['rest_time_seconds'],
          'superset_group_id': row['superset_group_id'],
          'sets': <Map<String, dynamic>>[],
        };
        (day['exercises'] as List).add(exercise);
      }
      if (row['set_id'] == null) continue;
      (exercise['sets'] as List).add({
        'source_set_id': row['set_id'],
        'weight': row['weight'],
        'reps': row['reps'],
        'distance': row['distance'],
        'time_seconds': row['time_seconds'],
        'is_warmup': (row['is_warmup'] as num? ?? 0) == 1,
      });
    }
    return {
      'id': routine['id'],
      'name': routine['name'],
      'notes': routine['notes'],
      'days': days,
    };
  }

  /// `id → {name, locale_key, type}` of the library exercises in [ids];
  /// ids missing from the library are absent from the result.
  Future<Map<String, Map<String, dynamic>>> exerciseInfo(
    DatabaseExecutor executor,
    Iterable<String> ids,
  ) async {
    final unique = ids.toSet().toList();
    final out = <String, Map<String, dynamic>>{};
    for (var i = 0; i < unique.length; i += 400) {
      final chunk = unique.sublist(i, (i + 400).clamp(0, unique.length));
      final rows = await executor.query(
        'exercises',
        columns: ['id', 'name', 'locale_key', 'type'],
        where: 'id IN (${List.filled(chunk.length, '?').join(', ')})',
        whereArgs: chunk,
      );
      for (final row in rows) {
        out[row['id'] as String] = {
          'name': row['name'],
          'locale_key': row['locale_key'],
          'type': row['type'],
        };
      }
    }
    return out;
  }

  /// Ids of the library exercises in [ids] that no longer exist.
  Future<Set<String>> missingExerciseIds(
    DatabaseExecutor executor,
    Iterable<String> ids,
  ) async {
    final wanted = ids.toSet();
    final found = await exerciseInfo(executor, wanted);
    return wanted.difference(found.keys.toSet());
  }

  /// Inserts a new routine with its whole tree. Insert-only: the target must
  /// not carry any `source_*` id. The routine takes [proposalId] as its
  /// primary key and every child a deterministic id derived from it, so the
  /// same proposal can never create the tree twice.
  Future<String> createRoutine(
    DatabaseExecutor txn, {
    required String proposalId,
    required Map<String, dynamic> target,
  }) async {
    await txn.insert('routines', {
      'id': proposalId,
      'name': target['name'],
      'notes': target['notes'],
      'created_at': DateTime.now().toIso8601String(),
    });
    final days = (target['days'] as List).cast<Map<String, dynamic>>();
    for (var d = 0; d < days.length; d++) {
      final day = days[d];
      final dayId = aiDerivedId(proposalId, 'day$d');
      await txn.insert('routine_days', {
        'id': dayId,
        'routine_id': proposalId,
        'name': day['name'],
        'notes': day['notes'],
        'order_index': d,
      });
      final exercises = (day['exercises'] as List).cast<Map<String, dynamic>>();
      for (var e = 0; e < exercises.length; e++) {
        final exercise = exercises[e];
        final reId = aiDerivedId(proposalId, 'day$d/ex$e');
        await txn.insert('routine_exercises', {
          'id': reId,
          'routine_day_id': dayId,
          'exercise_id': exercise['exercise_id'],
          'order_index': e,
          'rest_time_seconds': exercise['rest_time_seconds'],
          'superset_group_id': exercise['superset_group_id'],
        });
        final sets = (exercise['sets'] as List).cast<Map<String, dynamic>>();
        for (var s = 0; s < sets.length; s++) {
          await txn.insert('predefined_sets', {
            'id': aiDerivedId(proposalId, 'day$d/ex$e/set$s'),
            ..._setValues(sets[s], reId, s),
          });
        }
      }
    }
    return proposalId;
  }

  /// Rewrites [routineId] to [target] in two phases: first every kept (and
  /// new) row is upserted, then whatever the target no longer contains is
  /// deleted across the whole routine. Doing the deletes last means an
  /// exercise moved to another day (its row is re-parented in phase one) is
  /// never lost. Every UPDATE must hit exactly one row, otherwise the whole
  /// transaction aborts.
  Future<void> updateRoutine(
    DatabaseExecutor txn, {
    required String proposalId,
    required String routineId,
    required Map<String, dynamic> target,
  }) async {
    await _expectOne(
      await txn.update(
        'routines',
        {'name': target['name'], 'notes': target['notes']},
        where: 'id = ?',
        whereArgs: [routineId],
      ),
      'routine $routineId',
    );
    final keptDays = <String>{};
    final keptExercises = <String>{};
    final keptSets = <String>{};
    final days = (target['days'] as List).cast<Map<String, dynamic>>();
    for (var d = 0; d < days.length; d++) {
      final day = days[d];
      final sourceDay = day['source_day_id'] as String?;
      final dayId = sourceDay ?? aiDerivedId(proposalId, 'day$d');
      keptDays.add(dayId);
      final dayValues = {
        'routine_id': routineId,
        'name': day['name'],
        'notes': day['notes'],
        'order_index': d,
      };
      if (sourceDay == null) {
        await txn.insert('routine_days', {'id': dayId, ...dayValues});
      } else {
        await _expectOne(
          await txn.update(
            'routine_days',
            dayValues,
            where: 'id = ? AND routine_id = ?',
            whereArgs: [dayId, routineId],
          ),
          'routine day $dayId',
        );
      }
      final exercises = (day['exercises'] as List).cast<Map<String, dynamic>>();
      for (var e = 0; e < exercises.length; e++) {
        final exercise = exercises[e];
        final sourceExercise =
            exercise['source_routine_exercise_id'] as String?;
        final reId = sourceExercise ?? aiDerivedId(proposalId, 'day$d/ex$e');
        keptExercises.add(reId);
        final exerciseValues = {
          'routine_day_id': dayId,
          'exercise_id': exercise['exercise_id'],
          'order_index': e,
          'rest_time_seconds': exercise['rest_time_seconds'],
          'superset_group_id': exercise['superset_group_id'],
        };
        if (sourceExercise == null) {
          await txn.insert('routine_exercises', {
            'id': reId,
            ...exerciseValues,
          });
        } else {
          await _expectOne(
            await txn.update(
              'routine_exercises',
              exerciseValues,
              where:
                  'id = ? AND routine_day_id IN '
                  '(SELECT id FROM routine_days WHERE routine_id = ?)',
              whereArgs: [reId, routineId],
            ),
            'routine exercise $reId',
          );
        }
        final sets = (exercise['sets'] as List).cast<Map<String, dynamic>>();
        for (var s = 0; s < sets.length; s++) {
          final sourceSet = sets[s]['source_set_id'] as String?;
          final setId =
              sourceSet ?? aiDerivedId(proposalId, 'day$d/ex$e/set$s');
          keptSets.add(setId);
          final values = _setValues(sets[s], reId, s);
          if (sourceSet == null) {
            await txn.insert('predefined_sets', {'id': setId, ...values});
          } else {
            await _expectOne(
              await txn.update(
                'predefined_sets',
                values,
                where: 'id = ?',
                whereArgs: [setId],
              ),
              'predefined set $setId',
            );
          }
        }
      }
    }
    // Phase two: delete what the target dropped, across the whole routine.
    final existingSets = await txn.rawQuery(
      '''
      SELECT ps.id FROM predefined_sets ps
      JOIN routine_exercises re ON re.id = ps.routine_exercise_id
      JOIN routine_days d ON d.id = re.routine_day_id
      WHERE d.routine_id = ?
      ''',
      [routineId],
    );
    await _deleteIds(
      txn,
      'predefined_sets',
      [
        for (final row in existingSets) row['id'] as String,
      ].where((id) => !keptSets.contains(id)),
    );
    final existingExercises = await txn.rawQuery(
      '''
      SELECT re.id FROM routine_exercises re
      JOIN routine_days d ON d.id = re.routine_day_id
      WHERE d.routine_id = ?
      ''',
      [routineId],
    );
    await _deleteIds(
      txn,
      'routine_exercises',
      [
        for (final row in existingExercises) row['id'] as String,
      ].where((id) => !keptExercises.contains(id)),
    );
    final existingDays = await txn.query(
      'routine_days',
      columns: ['id'],
      where: 'routine_id = ?',
      whereArgs: [routineId],
    );
    await _deleteIds(
      txn,
      'routine_days',
      [
        for (final row in existingDays) row['id'] as String,
      ].where((id) => !keptDays.contains(id)),
    );
  }

  Map<String, Object?> _setValues(
    Map<String, dynamic> set,
    String routineExerciseId,
    int index,
  ) => {
    'routine_exercise_id': routineExerciseId,
    'weight': set['weight'],
    'reps': set['reps'],
    'distance': set['distance'],
    'time_seconds': set['time_seconds'],
    'is_warmup': set['is_warmup'] == true ? 1 : 0,
    'order_index': index,
  };

  Future<void> _deleteIds(
    DatabaseExecutor txn,
    String table,
    Iterable<String> ids,
  ) async {
    final list = ids.toList();
    for (var i = 0; i < list.length; i += 400) {
      final chunk = list.sublist(i, (i + 400).clamp(0, list.length));
      await txn.delete(
        table,
        where: 'id IN (${List.filled(chunk.length, '?').join(', ')})',
        whereArgs: chunk,
      );
    }
  }

  Future<void> _expectOne(int affected, String what) async {
    if (affected != 1) {
      throw StateError(
        'Expected to update exactly one row of $what, got $affected',
      );
    }
  }
}
