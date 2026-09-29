import 'package:collection/collection.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:workout_notes/models/ai_routine_proposal.dart';
import 'package:workout_notes/repositories/base_repository.dart';

const _uuid = Uuid();

/// SQL behind AI routine proposals: the routine tree snapshot used for diffs
/// and staleness checks, exercise lookups, and the atomic reject / approve
/// transactions that write routines. The proposal rows themselves live in
/// `AiChatRepository`; `AiRoutineMutationService` keeps the rules
/// (normalisation, validation, diff).
class AiRoutineMutationRepository extends BaseRepository {
  /// Snapshot of a routine (days, exercises, predefined sets) using the
  /// `source_*_id` keys proposals refer to, or null when it does not exist.
  Future<Map<String, dynamic>?> loadRoutineTree(String id) async =>
      _loadRoutineTree(await db, id);

  Future<bool> exerciseExists(String id) async {
    final database = await db;
    final rows = await database.query(
      'exercises',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<String?> exerciseName(String id) async {
    final database = await db;
    final rows = await database.query(
      'exercises',
      columns: ['name'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['name'] as String?;
  }

  /// Marks an awaiting proposal as rejected. Throws [StateError] when the
  /// proposal does not exist; resolved proposals are left untouched.
  Future<void> rejectProposal(String id) async {
    final database = await db;
    await database.transaction((txn) async {
      final rows = await txn.query(
        'ai_routine_proposals',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (rows.isEmpty) throw StateError('Proposta não encontrada.');
      final p = AiRoutineProposal.fromRow(rows.first);
      if (p.status != AiRoutineProposalStatus.awaitingApproval) return;
      await txn.update(
        'ai_routine_proposals',
        {
          'status': AiRoutineProposalStatus.rejected.storageValue,
          'resolved_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ? AND status = ?',
        whereArgs: [id, AiRoutineProposalStatus.awaitingApproval.storageValue],
      );
    });
  }

  /// Applies an awaiting proposal in a single transaction. The proposal ends
  /// as applied, failed (an exercise disappeared) or stale (the routine
  /// changed since it was prepared); a resolved proposal is a no-op.
  Future<void> approveProposal(String id) async {
    final database = await db;
    await database.transaction((txn) async {
      final rows = await txn.query(
        'ai_routine_proposals',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (rows.isEmpty) throw StateError('Proposta não encontrada.');
      final p = AiRoutineProposal.fromRow(rows.first);
      if (p.status != AiRoutineProposalStatus.awaitingApproval) return;
      final missingExerciseId = await _missingExerciseId(txn, p.target);
      if (missingExerciseId != null) {
        await txn.update(
          'ai_routine_proposals',
          {
            'status': AiRoutineProposalStatus.failed.storageValue,
            'error_code': 'exercise_missing',
            'error_message':
                'Um exercício da prévia não existe mais na biblioteca. Gere uma nova proposta.',
            'resolved_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [id],
        );
        return;
      }
      final claimed = await txn.update(
        'ai_routine_proposals',
        {'status': AiRoutineProposalStatus.applying.storageValue},
        where: 'id = ? AND status = ?',
        whereArgs: [id, AiRoutineProposalStatus.awaitingApproval.storageValue],
      );
      if (claimed != 1) return;
      if (p.action == AiRoutineProposalAction.update) {
        final live = await _loadRoutineTree(txn, p.routineId!);
        if (!const DeepCollectionEquality().equals(live, p.before)) {
          await txn.update(
            'ai_routine_proposals',
            {
              'status': AiRoutineProposalStatus.stale.storageValue,
              'error_code': 'stale',
              'error_message':
                  'A rotina foi alterada depois que esta proposta foi criada.',
              'resolved_at': DateTime.now().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [id],
          );
          return;
        }
      }
      final appliedId = await _applyTarget(txn, p);
      await txn.update(
        'ai_routine_proposals',
        {
          'status': AiRoutineProposalStatus.applied.storageValue,
          'applied_routine_id': appliedId,
          'resolved_at': DateTime.now().toIso8601String(),
          'error_code': null,
          'error_message': null,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<String?> _missingExerciseId(
    DatabaseExecutor executor,
    Map<String, dynamic> target,
  ) async {
    final ids = <String>{};
    for (final rawDay in target['days'] as List) {
      for (final rawExercise in (rawDay as Map)['exercises'] as List) {
        final id = (rawExercise as Map)['exercise_id'] as String;
        ids.add(id);
      }
    }
    for (final id in ids) {
      final rows = await executor.query(
        'exercises',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return id;
    }
    return null;
  }

  Future<Map<String, dynamic>?> _loadRoutineTree(
    DatabaseExecutor executor,
    String id,
  ) async {
    final routineRows = await executor.query(
      'routines',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (routineRows.isEmpty) return null;
    final routine = routineRows.first;
    final days = await executor.query(
      'routine_days',
      where: 'routine_id = ?',
      whereArgs: [id],
      orderBy: 'order_index ASC',
    );
    final dayOut = <Map<String, dynamic>>[];
    for (final day in days) {
      final exercises = await executor.query(
        'routine_exercises',
        where: 'routine_day_id = ?',
        whereArgs: [day['id']],
        orderBy: 'order_index ASC',
      );
      final exOut = <Map<String, dynamic>>[];
      for (final exercise in exercises) {
        final sets = await executor.query(
          'predefined_sets',
          where: 'routine_exercise_id = ?',
          whereArgs: [exercise['id']],
          orderBy: 'order_index ASC',
        );
        exOut.add({
          'source_routine_exercise_id': exercise['id'],
          'exercise_id': exercise['exercise_id'],
          'rest_time_seconds': exercise['rest_time_seconds'],
          'superset_group_id': exercise['superset_group_id'],
          'sets': sets
              .map(
                (set) => {
                  'source_set_id': set['id'],
                  'weight': set['weight'],
                  'reps': set['reps'],
                  'distance': set['distance'],
                  'time_seconds': set['time_seconds'],
                  'is_warmup': (set['is_warmup'] as num? ?? 0) == 1,
                },
              )
              .toList(),
        });
      }
      dayOut.add({
        'source_day_id': day['id'],
        'name': day['name'],
        'notes': day['notes'],
        'exercises': exOut,
      });
    }
    return {
      'id': routine['id'],
      'name': routine['name'],
      'notes': routine['notes'],
      'days': dayOut,
    };
  }

  Future<String> _applyTarget(
    Transaction txn,
    AiRoutineProposal proposal,
  ) async {
    final target = proposal.target;
    final routineId = proposal.action == AiRoutineProposalAction.create
        ? _uuid.v4()
        : proposal.routineId!;
    if (proposal.action == AiRoutineProposalAction.create) {
      await txn.insert('routines', {
        'id': routineId,
        'name': target['name'],
        'notes': target['notes'],
        'created_at': DateTime.now().toIso8601String(),
      });
    } else {
      await txn.update(
        'routines',
        {'name': target['name'], 'notes': target['notes']},
        where: 'id = ?',
        whereArgs: [routineId],
      );
    }
    final keepDays = <String>{};
    final days = target['days'] as List;
    for (var i = 0; i < days.length; i++) {
      final day = (days[i] as Map).cast<String, dynamic>();
      final dayId = day['source_day_id'] as String? ?? _uuid.v4();
      keepDays.add(dayId);
      final values = {
        'routine_id': routineId,
        'name': day['name'],
        'notes': day['notes'],
        'order_index': i,
      };
      if (day['source_day_id'] == null) {
        await txn.insert('routine_days', {'id': dayId, ...values});
      } else {
        await txn.update(
          'routine_days',
          values,
          where: 'id = ?',
          whereArgs: [dayId],
        );
      }
      await _applyExercises(
        txn,
        dayId,
        (day['exercises'] as List).cast<Map>(),
        proposal.action == AiRoutineProposalAction.update,
      );
    }
    if (proposal.action == AiRoutineProposalAction.update) {
      final placeholders = List.filled(keepDays.length, '?').join(',');
      if (keepDays.isEmpty) {
        await txn.delete(
          'routine_days',
          where: 'routine_id = ?',
          whereArgs: [routineId],
        );
      } else {
        await txn.delete(
          'routine_days',
          where: 'routine_id = ? AND id NOT IN ($placeholders)',
          whereArgs: [routineId, ...keepDays],
        );
      }
    }
    return routineId;
  }

  Future<void> _applyExercises(
    Transaction txn,
    String dayId,
    List<Map> exercises,
    bool updating,
  ) async {
    final keep = <String>{};
    for (var i = 0; i < exercises.length; i++) {
      final ex = exercises[i].cast<String, dynamic>();
      final id = ex['source_routine_exercise_id'] as String? ?? _uuid.v4();
      keep.add(id);
      final values = {
        'routine_day_id': dayId,
        'exercise_id': ex['exercise_id'],
        'order_index': i,
        'rest_time_seconds': ex['rest_time_seconds'],
        'superset_group_id': ex['superset_group_id'],
      };
      if (ex['source_routine_exercise_id'] == null) {
        await txn.insert('routine_exercises', {'id': id, ...values});
      } else {
        await txn.update(
          'routine_exercises',
          values,
          where: 'id = ?',
          whereArgs: [id],
        );
      }
      await _applySets(txn, id, (ex['sets'] as List).cast<Map>(), updating);
    }
    if (updating) {
      if (keep.isEmpty) {
        await txn.delete(
          'routine_exercises',
          where: 'routine_day_id = ?',
          whereArgs: [dayId],
        );
      } else {
        await txn.delete(
          'routine_exercises',
          where:
              'routine_day_id = ? AND id NOT IN (${List.filled(keep.length, '?').join(',')})',
          whereArgs: [dayId, ...keep],
        );
      }
    }
  }

  Future<void> _applySets(
    Transaction txn,
    String routineExerciseId,
    List<Map> sets,
    bool updating,
  ) async {
    final keep = <String>{};
    for (var i = 0; i < sets.length; i++) {
      final set = sets[i].cast<String, dynamic>();
      final id = set['source_set_id'] as String? ?? _uuid.v4();
      keep.add(id);
      final values = {
        'routine_exercise_id': routineExerciseId,
        'weight': set['weight'],
        'reps': set['reps'],
        'distance': set['distance'],
        'time_seconds': set['time_seconds'],
        'is_warmup': set['is_warmup'] == true ? 1 : 0,
        'order_index': i,
      };
      if (set['source_set_id'] == null) {
        await txn.insert('predefined_sets', {'id': id, ...values});
      } else {
        await txn.update(
          'predefined_sets',
          values,
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    }
    if (updating) {
      if (keep.isEmpty) {
        await txn.delete(
          'predefined_sets',
          where: 'routine_exercise_id = ?',
          whereArgs: [routineExerciseId],
        );
      } else {
        await txn.delete(
          'predefined_sets',
          where:
              'routine_exercise_id = ? AND id NOT IN (${List.filled(keep.length, '?').join(',')})',
          whereArgs: [routineExerciseId, ...keep],
        );
      }
    }
  }
}
