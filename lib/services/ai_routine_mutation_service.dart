import 'package:collection/collection.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../database/database_helper.dart';
import '../models/ai_message_role.dart';
import '../models/ai_routine_proposal.dart';

const _uuid = Uuid();

/// Builds and applies routine proposals. Preparation never mutates routines.
class AiRoutineMutationService {
  final DatabaseHelper db;
  AiRoutineMutationService({DatabaseHelper? db})
    : db = db ?? DatabaseHelper.instance;

  Future<AiToolResult> prepareProposal({
    required String threadId,
    required String toolCallId,
    required Map<String, dynamic> args,
    required bool explicitRequest,
  }) async {
    if (!explicitRequest) {
      return const AiToolResult(
        ok: false,
        code: 'explicit_request_required',
        message:
            'Peça explicitamente para criar ou alterar uma rotina antes de preparar alterações.',
      );
    }
    try {
      final action = AiRoutineProposalAction.fromStorage(
        args['action'] as String?,
      );
      final routineId = args['routine_id'] as String?;
      final rawTarget = args['routine'];
      if (rawTarget is! Map) return _invalid('routine é obrigatória.');
      final target = _normaliseTarget(rawTarget.cast<String, dynamic>());
      if (action == AiRoutineProposalAction.update &&
          (routineId == null || routineId.isEmpty)) {
        return _invalid('routine_id é obrigatório para editar uma rotina.');
      }
      final before = action == AiRoutineProposalAction.update
          ? await loadRoutineTree(routineId!)
          : null;
      if (action == AiRoutineProposalAction.update && before == null) {
        return const AiToolResult(
          ok: false,
          code: 'not_found',
          message: 'Rotina não encontrada.',
        );
      }
      final validation = await _validateTarget(
        target,
        action: action,
        routineId: routineId,
      );
      if (validation != null) return _invalid(validation);
      final sourceValidation = _validateSourceIds(before, target);
      if (sourceValidation != null) return _invalid(sourceValidation);
      await _attachExerciseNames(target);
      final proposal = AiRoutineProposal(
        id: _uuid.v4(),
        threadId: threadId,
        toolCallId: toolCallId,
        action: action,
        routineId: routineId,
        before: before,
        target: target,
        diff: _buildDiff(before, target),
        status: AiRoutineProposalStatus.awaitingApproval,
        createdAt: DateTime.now(),
      );
      await db.insertAiRoutineProposal(proposal.toRow());
      return AiToolResult(
        ok: true,
        data: {
          'proposalId': proposal.id,
          'status': proposal.status.storageValue,
          'action': proposal.action.storageValue,
          'routineName': proposal.routineName,
          'diff': proposal.diff,
        },
      );
    } catch (e) {
      return AiToolResult(
        ok: false,
        code: 'invalid_args',
        message: e.toString(),
      );
    }
  }

  Future<AiRoutineProposal?> getProposal(String id) async {
    final row = await db.getAiRoutineProposal(id);
    return row == null ? null : AiRoutineProposal.fromRow(row);
  }

  Future<List<AiRoutineProposal>> getThreadProposals(String threadId) async =>
      (await db.getAiRoutineProposalsThread(
        threadId,
      )).map(AiRoutineProposal.fromRow).toList();

  Future<void> updateProposalStatus(String id, Map<String, dynamic> values) =>
      db.updateAiRoutineProposal(id, values);

  Future<AiRoutineProposal> reject(String id) async {
    final p = await getProposal(id);
    if (p == null) throw StateError('Proposta não encontrada.');
    if (p.status != AiRoutineProposalStatus.awaitingApproval) return p;
    await db.updateAiRoutineProposal(id, {
      'status': AiRoutineProposalStatus.rejected.storageValue,
      'resolved_at': DateTime.now().toIso8601String(),
    });
    return (await getProposal(id))!;
  }

  Future<AiRoutineProposal> approve(String id) async {
    final database = await db.database;
    await database.transaction((txn) async {
      final rows = await txn.query(
        'ai_routine_proposals',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (rows.isEmpty) throw StateError('Proposta não encontrada.');
      final p = AiRoutineProposal.fromRow(rows.first);
      if (p.status != AiRoutineProposalStatus.awaitingApproval) return;
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
    return (await getProposal(id))!;
  }

  Future<Map<String, dynamic>?> loadRoutineTree(String id) async =>
      _loadRoutineTree(await db.database, id);

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

  Map<String, dynamic> _normaliseTarget(Map<String, dynamic> raw) {
    final days = (raw['days'] as List? ?? const []).whereType<Map>().map((d) {
      final exercises = (d['exercises'] as List? ?? const [])
          .whereType<Map>()
          .map((e) {
            final sets = (e['sets'] as List? ?? const [])
                .whereType<Map>()
                .map(
                  (s) => {
                    if (s['source_set_id'] != null)
                      'source_set_id': s['source_set_id'],
                    'weight': _number(s['weight']),
                    'reps': _integer(s['reps']),
                    'distance': _number(s['distance']),
                    'time_seconds': _integer(s['time_seconds']),
                    'is_warmup': s['is_warmup'] == true,
                  },
                )
                .toList();
            return {
              if (e['source_routine_exercise_id'] != null)
                'source_routine_exercise_id': e['source_routine_exercise_id'],
              'exercise_id': e['exercise_id'],
              'rest_time_seconds': _integer(e['rest_time_seconds']),
              'superset_group_id': e['superset_group_id'],
              'sets': sets,
            };
          })
          .toList();
      return {
        if (d['source_day_id'] != null) 'source_day_id': d['source_day_id'],
        'name': d['name'],
        'notes': d['notes'],
        'exercises': exercises,
      };
    }).toList();
    return {'name': raw['name'], 'notes': raw['notes'], 'days': days};
  }

  double? _number(dynamic value) => value is num ? value.toDouble() : null;
  int? _integer(dynamic value) => value is num ? value.toInt() : null;

  Future<String?> _validateTarget(
    Map<String, dynamic> target, {
    required AiRoutineProposalAction action,
    String? routineId,
  }) async {
    if ((target['name'] as String?)?.trim().isEmpty ?? true) {
      return 'O nome da rotina é obrigatório.';
    }
    final seen = <String>{};
    for (final day in target['days'] as List) {
      if ((day['name'] as String?)?.trim().isEmpty ?? true) {
        return 'Todo dia precisa de nome.';
      }
      for (final exercise in day['exercises'] as List) {
        final exerciseId = exercise['exercise_id'] as String?;
        if (exerciseId == null || exerciseId.isEmpty) {
          return 'Todo exercício precisa de exercise_id.';
        }
        if (!seen.add(
          '${day['source_day_id'] ?? day.hashCode}:$exerciseId:${exercise['source_routine_exercise_id'] ?? exercise.hashCode}',
        )) {
          return 'Há exercícios duplicados na proposta.';
        }
        final found = await db.database.then(
          (database) => database.query(
            'exercises',
            columns: ['id'],
            where: 'id = ?',
            whereArgs: [exerciseId],
          ),
        );
        if (found.isEmpty) {
          return 'Exercício "$exerciseId" não existe na biblioteca.';
        }
        final rest = exercise['rest_time_seconds'];
        if (rest is int && rest < 0) return 'O descanso não pode ser negativo.';
        for (final set in exercise['sets'] as List) {
          for (final key in const [
            'weight',
            'reps',
            'distance',
            'time_seconds',
          ]) {
            final value = set[key];
            if (value is num && value < 0) return '$key não pode ser negativo.';
          }
        }
      }
    }
    return null;
  }

  Future<void> _attachExerciseNames(Map<String, dynamic> target) async {
    final database = await db.database;
    for (final rawDay in target['days'] as List) {
      final day = (rawDay as Map).cast<String, dynamic>();
      for (final rawExercise in day['exercises'] as List) {
        final exercise = (rawExercise as Map).cast<String, dynamic>();
        final rows = await database.query(
          'exercises',
          columns: ['name'],
          where: 'id = ?',
          whereArgs: [exercise['exercise_id']],
        );
        if (rows.isNotEmpty) {
          exercise['exercise_name'] = rows.first['name'];
        }
      }
    }
  }

  String? _validateSourceIds(
    Map<String, dynamic>? before,
    Map<String, dynamic> target,
  ) {
    if (before == null) return null;
    final oldDays = <String, Map>{};
    final oldExercises = <String, Map>{};
    final oldSetsByExercise = <String, Set<String>>{};
    for (final rawDay in before['days'] as List) {
      final day = (rawDay as Map).cast<String, dynamic>();
      final dayId = day['source_day_id'] as String;
      oldDays[dayId] = day;
      for (final rawExercise in day['exercises'] as List) {
        final exercise = (rawExercise as Map).cast<String, dynamic>();
        final exerciseId = exercise['source_routine_exercise_id'] as String;
        oldExercises[exerciseId] = exercise;
        oldSetsByExercise[exerciseId] = (exercise['sets'] as List)
            .map((set) => (set as Map)['source_set_id'] as String)
            .toSet();
      }
    }
    for (final rawDay in target['days'] as List) {
      final day = (rawDay as Map).cast<String, dynamic>();
      final dayId = day['source_day_id'] as String?;
      if (dayId != null && !oldDays.containsKey(dayId)) {
        return 'source_day_id não pertence à rotina.';
      }
      for (final rawExercise in day['exercises'] as List) {
        final exercise = (rawExercise as Map).cast<String, dynamic>();
        final sourceExerciseId =
            exercise['source_routine_exercise_id'] as String?;
        if (sourceExerciseId != null &&
            !oldExercises.containsKey(sourceExerciseId)) {
          return 'source_routine_exercise_id não pertence à rotina.';
        }
        for (final rawSet in exercise['sets'] as List) {
          final set = (rawSet as Map).cast<String, dynamic>();
          final sourceSetId = set['source_set_id'] as String?;
          if (sourceSetId != null &&
              (sourceExerciseId == null ||
                  !(oldSetsByExercise[sourceExerciseId]?.contains(
                        sourceSetId,
                      ) ??
                      false))) {
            return 'source_set_id não pertence ao exercício informado.';
          }
        }
      }
    }
    return null;
  }

  Map<String, dynamic> _buildDiff(
    Map<String, dynamic>? before,
    Map<String, dynamic> target,
  ) {
    int count(Map<String, dynamic>? tree, String key) {
      if (tree == null) return 0;
      if (key == 'days') return (tree['days'] as List? ?? const []).length;
      var total = 0;
      for (final d in tree['days'] as List? ?? const []) {
        if (key == 'exercises') {
          total += (d['exercises'] as List? ?? const []).length;
        }
        for (final e in d['exercises'] as List? ?? const []) {
          if (key == 'sets') total += (e['sets'] as List? ?? const []).length;
        }
      }
      return total;
    }

    final beforeDays = count(before, 'days');
    final beforeExercises = count(before, 'exercises');
    final beforeSets = count(before, 'sets');
    final afterDays = count(target, 'days');
    final afterExercises = count(target, 'exercises');
    final afterSets = count(target, 'sets');
    final existingDayIds = (before?['days'] as List? ?? const [])
        .map((d) => d['source_day_id'])
        .whereType<String>()
        .toSet();
    final keptDayIds = (target['days'] as List)
        .map((d) => d['source_day_id'])
        .whereType<String>()
        .toSet();
    final removed =
        existingDayIds.difference(keptDayIds).length +
        (beforeExercises - afterExercises).clamp(0, 1 << 20) +
        (beforeSets - afterSets).clamp(0, 1 << 20);
    return {
      'before': {
        'days': beforeDays,
        'exercises': beforeExercises,
        'sets': beforeSets,
      },
      'after': {
        'days': afterDays,
        'exercises': afterExercises,
        'sets': afterSets,
      },
      'added': {
        'days': (afterDays - beforeDays).clamp(0, 1 << 20),
        'exercises': (afterExercises - beforeExercises).clamp(0, 1 << 20),
        'sets': (afterSets - beforeSets).clamp(0, 1 << 20),
      },
      'removed': {'total': removed},
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

  AiToolResult _invalid(String message) =>
      AiToolResult(ok: false, code: 'invalid_args', message: message);
}
