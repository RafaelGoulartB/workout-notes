import 'dart:developer' as developer;

import 'package:collection/collection.dart';
import 'package:uuid/uuid.dart';

import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/models/ai_message_role.dart';
import 'package:workout_notes/models/ai_routine_proposal.dart';

const _uuid = Uuid();

class AiRoutineMutationException implements Exception {
  final String code;
  final String message;
  final Object cause;

  const AiRoutineMutationException({
    required this.code,
    required this.message,
    required this.cause,
  });

  @override
  String toString() => 'AiRoutineMutationException($code): $message';
}

/// Builds and applies routine proposals. Preparation never mutates routines.
class AiRoutineMutationService {
  final DatabaseHelper db;
  AiRoutineMutationService({DatabaseHelper? db})
    : db = db ?? DatabaseHelper.instance;

  Future<AiToolResult> prepareProposal({
    required String threadId,
    required String toolCallId,
    required Map<String, dynamic> args,
  }) async {
    try {
      final rawAction = args['action'];
      if (rawAction != 'create' && rawAction != 'update') {
        return _invalid('action deve ser create ou update.');
      }
      final action = AiRoutineProposalAction.fromStorage(rawAction as String);
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
      final existing = (await getThreadProposals(threadId)).firstWhereOrNull(
        (proposal) =>
            proposal.status == AiRoutineProposalStatus.awaitingApproval &&
            proposal.action == action &&
            proposal.routineId == routineId &&
            const DeepCollectionEquality().equals(proposal.target, target),
      );
      if (existing != null) return _proposalResult(existing, reused: true);
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
      await db.aiChatRepo.insertAiRoutineProposal(proposal.toRow());
      return _proposalResult(proposal);
    } catch (e) {
      return AiToolResult(
        ok: false,
        code: 'invalid_args',
        message: e.toString(),
      );
    }
  }

  Future<AiRoutineProposal?> getProposal(String id) async {
    final row = await db.aiChatRepo.getAiRoutineProposal(id);
    return row == null ? null : AiRoutineProposal.fromRow(row);
  }

  Future<void> restorePendingProposal(AiRoutineProposal proposal) async {
    if (proposal.status != AiRoutineProposalStatus.awaitingApproval) return;
    if (await getProposal(proposal.id) != null) return;
    await db.aiChatRepo.insertAiRoutineProposal(proposal.toRow());
  }

  Future<List<AiRoutineProposal>> getThreadProposals(String threadId) async =>
      (await db.aiChatRepo.getAiRoutineProposalsThread(
        threadId,
      )).map(AiRoutineProposal.fromRow).toList();

  AiToolResult _proposalResult(
    AiRoutineProposal proposal, {
    bool reused = false,
  }) => AiToolResult(
    ok: true,
    data: {
      'proposalId': proposal.id,
      'status': proposal.status.storageValue,
      'action': proposal.action.storageValue,
      'routineName': proposal.routineName,
      'diff': proposal.diff,
      if (reused) 'reused': true,
    },
  );

  Future<AiRoutineProposal> reject(String id) async {
    await db.aiRoutineMutationRepo.rejectProposal(id);
    return (await getProposal(id))!;
  }

  Future<AiRoutineProposal> approve(String id) async {
    try {
      await db.aiRoutineMutationRepo.approveProposal(id);
      return (await getProposal(id))!;
    } catch (error, stackTrace) {
      developer.log(
        'Failed to apply routine proposal $id',
        name: 'AiRoutineMutationService',
        error: error,
        stackTrace: stackTrace,
      );
      throw AiRoutineMutationException(
        code: 'routine_apply_failed',
        message: 'Não foi possível aplicar a proposta de rotina.',
        cause: error,
      );
    }
  }

  Future<Map<String, dynamic>?> loadRoutineTree(String id) =>
      db.aiRoutineMutationRepo.loadRoutineTree(id);

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
    for (final day in (target['days'] as List).cast<Map<String, dynamic>>()) {
      if ((day['name'] as String?)?.trim().isEmpty ?? true) {
        return 'Todo dia precisa de nome.';
      }
      for (final exercise in (day['exercises'] as List).cast<Map<String, dynamic>>()) {
        final exerciseId = exercise['exercise_id'] as String?;
        if (exerciseId == null || exerciseId.isEmpty) {
          return 'Todo exercício precisa de exercise_id.';
        }
        if (!seen.add(
          '${day['source_day_id'] ?? day.hashCode}:$exerciseId:${exercise['source_routine_exercise_id'] ?? exercise.hashCode}',
        )) {
          return 'Há exercícios duplicados na proposta.';
        }
        if (!await db.aiRoutineMutationRepo.exerciseExists(exerciseId)) {
          return 'Exercício "$exerciseId" não existe na biblioteca.';
        }
        final rest = exercise['rest_time_seconds'];
        if (rest is int && rest < 0) return 'O descanso não pode ser negativo.';
        for (final set in (exercise['sets'] as List).cast<Map<String, dynamic>>()) {
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
    for (final rawDay in target['days'] as List) {
      final day = (rawDay as Map).cast<String, dynamic>();
      for (final rawExercise in day['exercises'] as List) {
        final exercise = (rawExercise as Map).cast<String, dynamic>();
        final name = await db.aiRoutineMutationRepo.exerciseName(
          exercise['exercise_id'] as String,
        );
        if (name != null) exercise['exercise_name'] = name;
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
    final targetDayIds = <String>{};
    final targetExerciseIds = <String>{};
    final targetSetIds = <String>{};
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
      if (dayId != null && !targetDayIds.add(dayId)) {
        return 'source_day_id está duplicado na proposta.';
      }
      for (final rawExercise in day['exercises'] as List) {
        final exercise = (rawExercise as Map).cast<String, dynamic>();
        final sourceExerciseId =
            exercise['source_routine_exercise_id'] as String?;
        if (sourceExerciseId != null &&
            !oldExercises.containsKey(sourceExerciseId)) {
          return 'source_routine_exercise_id não pertence à rotina.';
        }
        if (sourceExerciseId != null &&
            !targetExerciseIds.add(sourceExerciseId)) {
          return 'source_routine_exercise_id está duplicado na proposta.';
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
          if (sourceSetId != null && !targetSetIds.add(sourceSetId)) {
            return 'source_set_id está duplicado na proposta.';
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
      for (final d in (tree['days'] as List? ?? const []).cast<Map<String, dynamic>>()) {
        if (key == 'exercises') {
          total += (d['exercises'] as List? ?? const []).length;
        }
        for (final e in (d['exercises'] as List? ?? const []).cast<Map<String, dynamic>>()) {
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
        .cast<Map<String, dynamic>>()
        .map((d) => d['source_day_id'])
        .whereType<String>()
        .toSet();
    final keptDayIds = (target['days'] as List)
        .cast<Map<String, dynamic>>()
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

  AiToolResult _invalid(String message) =>
      AiToolResult(ok: false, code: 'invalid_args', message: message);
}
