import 'package:collection/collection.dart';
import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/models/ai_proposal.dart';
import 'package:workout_notes/models/ai_tool_domain.dart';
import 'package:workout_notes/repositories/ai_routine_mutation_repository.dart';
import 'package:workout_notes/services/ai_proposals/ai_proposal_handler.dart';
import 'package:workout_notes/services/ai_proposals/ai_proposal_schema.dart';
import 'package:workout_notes/services/ai_proposals/routine_proposal_diff.dart';
import 'package:workout_notes/services/ai_tool_spec.dart';
import 'package:workout_notes/utils/ai_revision.dart';
import 'package:workout_notes/utils/workout_card_helpers.dart';

/// Caps and ranges of a routine proposal. A model mistake (a rest of a million
/// seconds, 400 sets) is rejected while preparing instead of being stored.
abstract final class RoutineProposalLimits {
  static const maxDays = 7;
  static const maxExercisesPerDay = 15;
  static const maxSetsPerExercise = 10;
  static const maxNameLength = 100;
  static const maxDayNameLength = 60;
  static const maxNotesLength = 2000;
  static const maxSupersetIdLength = 40;
  static const maxReps = 100;
  static const maxWeightKg = 1000.0;
  static const maxRestSeconds = 900;
  static const maxTimeSeconds = 7200;

  /// Routine sets store distance in kilometres (what the set editor shows).
  static const maxDistanceKm = 1000.0;
}

/// `propose_routine_change`: create a routine or rewrite an existing one.
///
/// Create is insert-only (no `source_*` ids). Update needs the `revision`
/// returned by `get_routine_detail`, is checked against it at prepare AND at
/// approve, and is applied in two phases so moving an exercise between days
/// never deletes it.
class RoutineProposalHandler extends AiProposalHandler {
  final DatabaseHelper _db;

  RoutineProposalHandler({DatabaseHelper? db})
    : _db = db ?? DatabaseHelper.instance;

  AiRoutineMutationRepository get _repo => _db.aiRoutineMutationRepo;

  @override
  String get kind => 'routine';

  @override
  String get toolName => 'propose_routine_change';

  @override
  AiToolDomain get domain => AiToolDomain.workouts;

  @override
  AiToolSpec get spec => AiToolSpec(
    name: toolName,
    proposal: true,
    domain: domain,
    description:
        'Create or rewrite a routine. Create: exercise ids from list_exercises, no source_* ids (to copy, resend the content without them). '
        'Update: get_routine_detail first; send routine_id, revision and the COMPLETE final tree, keeping source_* ids of what stays (omitted = deleted; keep the exercise id to move it between days). '
        'Set fields must fit the exercise type.',
    properties: {
      'action': AiSchema.enumOf(['create', 'update']),
      'routine_id': AiSchema.str('Update only.'),
      'revision': AiSchema.str('Update only.'),
      'routine': AiSchema.object(
        {
          'name': AiSchema.str(),
          'notes': AiSchema.str(),
          'days': AiSchema.list(
            AiSchema.object(
              {
                'source_day_id': AiSchema.str(),
                'name': AiSchema.str(),
                'notes': AiSchema.str(),
                'exercises': AiSchema.list(
                  AiSchema.object(
                    {
                      'source_routine_exercise_id': AiSchema.str(),
                      'exercise_id': AiSchema.str(),
                      'rest_time_seconds': AiSchema.integer(),
                      'superset_group_id': AiSchema.str(),
                      'sets': AiSchema.list(
                        AiSchema.object({
                          'source_set_id': AiSchema.str(),
                          'weight': AiSchema.number('kg'),
                          'reps': AiSchema.integer(null, 1),
                          'distance': AiSchema.number('km'),
                          'time_seconds': AiSchema.integer(),
                          'is_warmup': AiSchema.boolean(),
                        }),
                        min: 1,
                        max: RoutineProposalLimits.maxSetsPerExercise,
                      ),
                    },
                    required: ['exercise_id', 'sets'],
                  ),
                  min: 1,
                  max: RoutineProposalLimits.maxExercisesPerDay,
                ),
              },
              required: ['name', 'exercises'],
            ),
            min: 1,
            max: RoutineProposalLimits.maxDays,
          ),
        },
        required: ['name', 'days'],
      ),
    },
    required: ['action', 'routine'],
  );

  static const _routineKeys = {'name', 'notes', 'days'};
  static const _dayKeys = {'source_day_id', 'name', 'notes', 'exercises'};
  static const _exerciseKeys = {
    'source_routine_exercise_id',
    'exercise_id',
    'rest_time_seconds',
    'superset_group_id',
    'sets',
  };
  static const _setKeys = {
    'source_set_id',
    'weight',
    'reps',
    'distance',
    'time_seconds',
    'is_warmup',
  };

  @override
  Future<AiProposalDraft> prepare(
    DatabaseExecutor db,
    AiProposalArgs args,
  ) async {
    args.allowOnly({'action', 'routine_id', 'revision', 'routine'});
    final action = args.requiredEnum('action', const ['create', 'update']);
    final routineId = args.optionalString('routine_id', maxLength: 80);
    final revision = args.optionalString('revision', maxLength: 40);
    final isUpdate = action == 'update';

    if (!isUpdate && (routineId != null || revision != null)) {
      throw const AiProposalException(
        'invalid_args',
        'routine_id and revision are only for action "update".',
        param: 'routine_id',
        hint:
            'To create a new routine remove routine_id and revision. To edit an existing one use action "update".',
      );
    }
    Map<String, dynamic>? base;
    if (isUpdate) {
      if (routineId == null) {
        throw const AiProposalException(
          'invalid_args',
          '"routine_id" is required to update a routine.',
          param: 'routine_id',
          expected: 'routine id from list_routines',
          hint: 'Call list_routines, then get_routine_detail, and pass the id.',
        );
      }
      if (revision == null) {
        throw const AiProposalException(
          'invalid_args',
          '"revision" is required to update a routine.',
          param: 'revision',
          expected: 'the revision returned by get_routine_detail',
          hint:
              'Call get_routine_detail for this routine and pass its "revision".',
        );
      }
      base = await _repo.loadRoutineTree(db, routineId);
      if (base == null) {
        throw const AiProposalException(
          'not_found',
          'Routine not found.',
          param: 'routine_id',
          hint: 'Call list_routines to get valid routine ids.',
        );
      }
      final current = await routineRevision(db, routineId);
      if (current != revision) {
        throw AiProposalException(
          'stale_revision',
          'The routine changed since you read it.',
          param: 'revision',
          hint:
              'Call get_routine_detail again, rebuild the change on the new tree and send its new "revision".',
          received: revision,
        );
      }
    }

    final target = _normalise(
      args.requiredObject('routine'),
      insertOnly: !isUpdate,
    );
    final exerciseIds = {
      for (final day in _maps(target['days']))
        for (final exercise in _maps(day['exercises']))
          exercise['exercise_id'] as String,
    };
    final baseExerciseIds = {
      for (final day in _maps(base?['days']))
        for (final exercise in _maps(day['exercises']))
          exercise['exercise_id'] as String,
    };
    final info = await _repo.exerciseInfo(db, {
      ...exerciseIds,
      ...baseExerciseIds,
    });
    _checkExercises(target, info);
    if (isUpdate) _checkSourceIds(base!, target);

    final preview = RoutineProposalDiff.build(
      action: action,
      base: base,
      target: target,
      exercises: info,
    );
    if (RoutineProposalDiff.isNoOp(preview)) {
      throw const AiProposalException(
        'no_changes',
        'The routine already matches this proposal.',
        hint: 'Tell the user nothing needs to change, or send the real change.',
      );
    }
    final warnings = <Map<String, dynamic>>[];
    if (!isUpdate) {
      final dupes = await db.query(
        'routines',
        columns: ['id'],
        where: 'LOWER(name) = LOWER(?)',
        whereArgs: [target['name']],
        limit: 1,
      );
      if (dupes.isNotEmpty) warnings.add({'code': 'routine_name_exists'});
    }
    preview['warnings'] = warnings;

    final counts = preview['counts'] as Map;
    return AiProposalDraft(
      payload: {'action': action, 'routine_id': ?routineId, 'routine': target},
      preview: preview,
      base: base,
      baseHash: isUpdate ? revision : null,
      subjectId: routineId,
      summary: {
        'action': action,
        'routine_name': target['name'],
        if (isUpdate) 'current_name': base!['name'],
        'days': (target['days'] as List).length,
        'exercises': [
          for (final day in _maps(target['days']))
            ...?day['exercises'] as List?,
        ].length,
        if (isUpdate) ...{
          'days_removed': counts['days_removed'],
          'exercises_removed': counts['exercises_removed'],
          'exercises_swapped': counts['exercises_swapped'],
          'sets_removed': counts['sets_removed'],
          'sets_changed': counts['sets_changed'],
        },
      },
    );
  }

  @override
  Future<String?> revalidate(DatabaseExecutor txn, AiProposal proposal) async {
    final target = _target(proposal);
    final isUpdate = proposal.payload['action'] == 'update';
    if (isUpdate) {
      final routineId = proposal.payload['routine_id'] as String?;
      if (routineId == null) throw _invalidPayload();
      final current = await routineRevision(txn, routineId);
      if (current == null) return 'stale_target_missing';
      final hash = proposal.baseHash;
      if (hash != null) {
        if (current != hash) return 'stale_revision';
      } else {
        // Proposals migrated from the old table carry the tree, not a hash.
        final live = await _repo.loadRoutineTree(txn, routineId);
        if (!const DeepCollectionEquality().equals(live, proposal.base)) {
          return 'stale_revision';
        }
      }
    }
    final ids = {
      for (final day in _maps(target['days']))
        for (final exercise in _maps(day['exercises']))
          exercise['exercise_id'] as String,
    };
    if ((await _repo.missingExerciseIds(txn, ids)).isNotEmpty) {
      return 'exercise_missing';
    }
    return null;
  }

  @override
  Future<Map<String, dynamic>> apply(
    DatabaseExecutor txn,
    AiProposal proposal,
  ) async {
    final target = _target(proposal);
    final isUpdate = proposal.payload['action'] == 'update';
    final String routineId;
    if (isUpdate) {
      routineId = proposal.payload['routine_id'] as String? ?? '';
      if (routineId.isEmpty) throw _invalidPayload();
      await _repo.updateRoutine(
        txn,
        proposalId: proposal.id,
        routineId: routineId,
        target: target,
      );
    } else {
      // Defence in depth: a stored create payload with source ids must never
      // be applied (it would re-parent another routine's rows).
      if (_hasSourceIds(target)) throw _invalidPayload();
      routineId = await _repo.createRoutine(
        txn,
        proposalId: proposal.id,
        target: target,
      );
    }
    final after = await _repo.loadRoutineTree(txn, routineId);
    if (after == null || !_matches(after, target)) {
      throw const AiProposalException(
        'apply_failed',
        'The routine does not match the proposal after applying it.',
      );
    }
    final days = _maps(after['days']);
    return {
      'routine_id': routineId,
      'routine_name': target['name'],
      'action': isUpdate ? 'update' : 'create',
      'revision': await routineRevision(txn, routineId),
      'days': days.length,
      'exercises': [for (final d in days) ...(d['exercises'] as List)].length,
    };
  }

  @override
  Future<Map<String, dynamic>?> rebuildPreview(
    DatabaseExecutor db,
    AiProposal proposal,
  ) async {
    final target = proposal.payload['routine'];
    if (target is! Map) return null;
    final tree = target.cast<String, dynamic>();
    final ids = {
      for (final day in _maps(tree['days']))
        for (final exercise in _maps(day['exercises']))
          if (exercise['exercise_id'] is String)
            exercise['exercise_id'] as String,
      for (final day in _maps(proposal.base?['days']))
        for (final exercise in _maps(day['exercises']))
          if (exercise['exercise_id'] is String)
            exercise['exercise_id'] as String,
    };
    final info = await _repo.exerciseInfo(db, ids);
    final preview = RoutineProposalDiff.build(
      action: proposal.payload['action'] == 'update' ? 'update' : 'create',
      base: proposal.base,
      target: tree,
      exercises: info,
    );
    preview['warnings'] = const <Map<String, dynamic>>[];
    return preview;
  }

  @override
  Map<String, dynamic> resultFacts(AiProposal proposal) => {
    for (final entry in (proposal.result ?? const {}).entries)
      if (entry.key != 'revision' || proposal.result?['action'] == 'update')
        entry.key: entry.value,
  };

  // ---------------------------------------------------------------- parsing

  Map<String, dynamic> _target(AiProposal proposal) {
    final raw = proposal.payload['routine'];
    if (raw is! Map) throw _invalidPayload();
    final target = raw.cast<String, dynamic>();
    if (target['days'] is! List) throw _invalidPayload();
    return target;
  }

  AiProposalException _invalidPayload() => const AiProposalException(
    'invalid_payload',
    'The stored proposal is not a valid routine change.',
  );

  Map<String, dynamic> _normalise(
    AiProposalArgs routine, {
    required bool insertOnly,
  }) {
    routine.allowOnly(_routineKeys);
    final name = routine.requiredString(
      'name',
      maxLength: RoutineProposalLimits.maxNameLength,
    );
    final notes = routine.optionalString(
      'notes',
      maxLength: RoutineProposalLimits.maxNotesLength,
    );
    final days = routine.requiredObjects(
      'days',
      max: RoutineProposalLimits.maxDays,
    );
    final outDays = <Map<String, dynamic>>[];
    for (final day in days) {
      day.allowOnly(_dayKeys);
      if (insertOnly) _rejectSource(day, 'source_day_id');
      final sourceDay = day.optionalString('source_day_id', maxLength: 80);
      final exercises = day.requiredObjects(
        'exercises',
        max: RoutineProposalLimits.maxExercisesPerDay,
      );
      final outExercises = <Map<String, dynamic>>[];
      for (final exercise in exercises) {
        exercise.allowOnly(_exerciseKeys);
        if (insertOnly) {
          _rejectSource(exercise, 'source_routine_exercise_id');
        }
        final sets = exercise.requiredObjects(
          'sets',
          max: RoutineProposalLimits.maxSetsPerExercise,
        );
        final outSets = <Map<String, dynamic>>[];
        for (final set in sets) {
          set.allowOnly(_setKeys);
          if (insertOnly) _rejectSource(set, 'source_set_id');
          final sourceSet = set.optionalString('source_set_id', maxLength: 80);
          outSets.add({
            'source_set_id': ?sourceSet,
            'weight': set.optionalNumber(
              'weight',
              min: 0,
              max: RoutineProposalLimits.maxWeightKg,
            ),
            // 0 reps is the placeholder models write for "not applicable".
            'reps': set.optionalInt(
              'reps',
              min: 1,
              max: RoutineProposalLimits.maxReps,
              zeroIsAbsent: true,
            ),
            'distance': set.optionalNumber(
              'distance',
              min: 0,
              max: RoutineProposalLimits.maxDistanceKm,
            ),
            'time_seconds': set.optionalInt(
              'time_seconds',
              min: 0,
              max: RoutineProposalLimits.maxTimeSeconds,
            ),
            'is_warmup': set.optionalBool('is_warmup') ?? false,
          });
        }
        final sourceExercise = exercise.optionalString(
          'source_routine_exercise_id',
          maxLength: 80,
        );
        outExercises.add({
          'source_routine_exercise_id': ?sourceExercise,
          'exercise_id': exercise.requiredString('exercise_id', maxLength: 80),
          'rest_time_seconds': exercise.optionalInt(
            'rest_time_seconds',
            min: 0,
            max: RoutineProposalLimits.maxRestSeconds,
          ),
          'superset_group_id': exercise.optionalString(
            'superset_group_id',
            maxLength: RoutineProposalLimits.maxSupersetIdLength,
          ),
          'sets': outSets,
        });
      }
      outDays.add({
        'source_day_id': ?sourceDay,
        'name': day.requiredString(
          'name',
          maxLength: RoutineProposalLimits.maxDayNameLength,
        ),
        'notes': day.optionalString(
          'notes',
          maxLength: RoutineProposalLimits.maxNotesLength,
        ),
        'exercises': outExercises,
      });
    }
    return {'name': name, 'notes': notes, 'days': outDays};
  }

  void _rejectSource(AiProposalArgs node, String key) {
    if (!node.has(key)) return;
    throw AiProposalException(
      'invalid_args',
      'Creating a routine is insert-only: "${node.path}.$key" is not allowed.',
      param: '${node.path}.$key',
      hint:
          'Remove every source_* id when creating. To copy a routine send its days, exercises and sets without ids.',
    );
  }

  bool _hasSourceIds(Map<String, dynamic> target) => _maps(target['days']).any(
    (day) =>
        day['source_day_id'] != null ||
        _maps(day['exercises']).any(
          (exercise) =>
              exercise['source_routine_exercise_id'] != null ||
              _maps(
                exercise['sets'],
              ).any((set) => set['source_set_id'] != null),
        ),
  );

  /// Library existence and set fields compatible with each exercise's type.
  void _checkExercises(
    Map<String, dynamic> target,
    Map<String, Map<String, dynamic>> info,
  ) {
    final days = _maps(target['days']);
    for (var d = 0; d < days.length; d++) {
      final exercises = _maps(days[d]['exercises']);
      for (var e = 0; e < exercises.length; e++) {
        final exercise = exercises[e];
        final path = 'routine.days[$d].exercises[$e]';
        final id = exercise['exercise_id'] as String;
        final row = info[id];
        if (row == null) {
          throw AiProposalException(
            'not_found',
            'Exercise "$id" does not exist in the library.',
            param: '$path.exercise_id',
            received: id,
            hint: 'Use an exercise id returned by list_exercises.',
          );
        }
        final type = (row['type'] as String?) ?? 'weightReps';
        final allowed = getFieldsForType(type).toSet();
        final sets = _maps(exercise['sets']);
        for (var s = 0; s < sets.length; s++) {
          for (final field in const [
            'weight',
            'reps',
            'distance',
            'time_seconds',
          ]) {
            if (allowed.contains(field) || sets[s][field] == null) continue;
            // A 0 in a field the exercise type does not use is a placeholder.
            if (sets[s][field] == 0) {
              sets[s][field] = null;
              continue;
            }
            {
              throw AiProposalException(
                'invalid_args',
                '"${row['name']}" is a $type exercise: sets cannot have "$field".',
                param: '$path.sets[$s].$field',
                expected: 'only ${allowed.join(' and ')}',
                received: sets[s][field],
                hint: 'Use only ${allowed.join(' and ')} for this exercise.',
              );
            }
          }
        }
      }
    }
  }

  /// Source ids must belong to the routine, be unique, and a set must stay
  /// with the exercise it belongs to.
  void _checkSourceIds(Map<String, dynamic> base, Map<String, dynamic> target) {
    final baseDays = <String>{};
    final baseExercises = <String>{};
    final setsOf = <String, Set<String>>{};
    for (final day in _maps(base['days'])) {
      baseDays.add(day['source_day_id'] as String);
      for (final exercise in _maps(day['exercises'])) {
        final id = exercise['source_routine_exercise_id'] as String;
        baseExercises.add(id);
        setsOf[id] = {
          for (final set in _maps(exercise['sets']))
            set['source_set_id'] as String,
        };
      }
    }
    final seenDays = <String>{};
    final seenExercises = <String>{};
    final seenSets = <String>{};
    final days = _maps(target['days']);
    for (var d = 0; d < days.length; d++) {
      final sourceDay = days[d]['source_day_id'] as String?;
      if (sourceDay != null) {
        _sourceId(
          'routine.days[$d].source_day_id',
          sourceDay,
          baseDays,
          seenDays,
          'day of this routine',
        );
      }
      final exercises = _maps(days[d]['exercises']);
      for (var e = 0; e < exercises.length; e++) {
        final sourceExercise =
            exercises[e]['source_routine_exercise_id'] as String?;
        final path = 'routine.days[$d].exercises[$e]';
        if (sourceExercise != null) {
          _sourceId(
            '$path.source_routine_exercise_id',
            sourceExercise,
            baseExercises,
            seenExercises,
            'exercise row of this routine',
          );
        }
        final sets = _maps(exercises[e]['sets']);
        for (var s = 0; s < sets.length; s++) {
          final sourceSet = sets[s]['source_set_id'] as String?;
          if (sourceSet == null) continue;
          final owned = sourceExercise == null
              ? const <String>{}
              : (setsOf[sourceExercise] ?? const <String>{});
          _sourceId(
            '$path.sets[$s].source_set_id',
            sourceSet,
            owned,
            seenSets,
            'set of this exercise row',
          );
        }
      }
    }
  }

  void _sourceId(
    String param,
    String id,
    Set<String> allowed,
    Set<String> seen,
    String what,
  ) {
    if (!allowed.contains(id)) {
      throw AiProposalException(
        'invalid_args',
        '"$param" is not a $what.',
        param: param,
        received: id,
        hint:
            'Use only source ids returned by get_routine_detail, and keep each set with its own exercise. Omit the id to add something new.',
      );
    }
    if (!seen.add(id)) {
      throw AiProposalException(
        'invalid_args',
        '"$param" is used more than once.',
        param: param,
        received: id,
        hint: 'Each source id may appear once; omit the id for new entries.',
      );
    }
  }

  /// Whether [tree] (as stored after applying) holds exactly what [target]
  /// asked for: same days/exercises/sets in the same order.
  bool _matches(Map<String, dynamic> tree, Map<String, dynamic> target) {
    if (tree['name'] != target['name']) return false;
    final days = _maps(tree['days']);
    final want = _maps(target['days']);
    if (days.length != want.length) return false;
    for (var d = 0; d < days.length; d++) {
      if (days[d]['name'] != want[d]['name']) return false;
      final exercises = _maps(days[d]['exercises']);
      final wantExercises = _maps(want[d]['exercises']);
      if (exercises.length != wantExercises.length) return false;
      for (var e = 0; e < exercises.length; e++) {
        if (exercises[e]['exercise_id'] != wantExercises[e]['exercise_id']) {
          return false;
        }
        if (_maps(exercises[e]['sets']).length !=
            _maps(wantExercises[e]['sets']).length) {
          return false;
        }
      }
    }
    return true;
  }

  static List<Map<String, dynamic>> _maps(Object? value) => value is List
      ? [
          for (final item in value)
            if (item is Map) item.cast<String, dynamic>(),
        ]
      : const [];
}
