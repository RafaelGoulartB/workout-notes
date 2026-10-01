import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/models/ai_proposal.dart';
import 'package:workout_notes/models/ai_tool_domain.dart';
import 'package:workout_notes/services/ai_proposals/ai_proposal_handler.dart';
import 'package:workout_notes/services/ai_proposals/ai_proposal_schema.dart';
import 'package:workout_notes/services/ai_tool_spec.dart';
import 'package:workout_notes/utils/ai_revision.dart';
import 'package:workout_notes/utils/date_utils.dart';

/// `propose_workout_schedule`: put a workout on the calendar. Schedules a
/// routine day on a date (a planned workout pre-filled like the calendar does),
/// moves a still-planned workout to another date, or copies a workout to a new
/// date. Planned means not started and not finished: a workout the user
/// already did is history and is never moved.
class WorkoutScheduleProposalHandler extends AiProposalHandler {
  final DatabaseHelper _db;
  final DateTime Function() _now;

  WorkoutScheduleProposalHandler({DatabaseHelper? db, DateTime Function()? now})
    : _db = db ?? DatabaseHelper.instance,
      _now = now ?? DateTime.now;

  @override
  String get kind => 'workout_schedule';

  @override
  String get toolName => 'propose_workout_schedule';

  @override
  AiToolDomain get domain => AiToolDomain.workouts;

  static const _actions = ['schedule_routine_day', 'move', 'copy'];
  static const _maxDaysAhead = 365;
  static const _previewExercises = 10;

  @override
  AiToolSpec get spec => AiToolSpec(
    name: toolName,
    proposal: true,
    domain: domain,
    description:
        'Schedule a strength workout: a routine day on a date, move a PLANNED workout, or copy a workout (planned and unchecked). Dates: today up to one year ahead; started or finished workouts cannot be moved.',
    properties: {
      'action': AiSchema.enumOf(_actions),
      'date': AiSchema.date('Target day'),
      'routine_day_id': AiSchema.str('source_day_id from get_routine_detail.'),
      'workout_id': AiSchema.str('From get_workout_history.'),
    },
    required: ['action', 'date'],
  );

  @override
  Future<AiProposalDraft> prepare(
    DatabaseExecutor db,
    AiProposalArgs args,
  ) async {
    args.allowOnly({'action', 'date', 'routine_day_id', 'workout_id'});
    final action = args.requiredEnum('action', _actions);
    final date = args.requiredDate('date');
    final today = dayOf(_now());
    final todayKey = dateKey(today);
    final last = dateKey(addDays(today, _maxDaysAhead));
    if (date.compareTo(todayKey) < 0 || date.compareTo(last) > 0) {
      throw AiProposalException(
        'invalid_args',
        '"date" must be between today and one year ahead.',
        param: 'date',
        expected: 'between $todayKey and $last',
        received: date,
        hint:
            'Planning is for today or the future. To log a workout that already happened, ask the user to add it in the app.',
      );
    }
    final routineDayId = args.optionalString('routine_day_id', maxLength: 80);
    final workoutId = args.optionalString('workout_id', maxLength: 80);
    final repo = _db.workoutRepo;

    final onDate = await db.query(
      'workouts',
      columns: ['id', 'end_time', 'start_time'],
      where: 'date = ?',
      whereArgs: [date],
    );
    final warnings = <Map<String, dynamic>>[
      if (onDate.isNotEmpty)
        {
          'code': 'date_has_workouts',
          'count': onDate.length,
          'finished': onDate.where((w) => w['end_time'] != null).length,
        },
    ];

    if (action == 'schedule_routine_day') {
      // A workout_id here is a placeholder and is ignored.
      if (routineDayId == null) {
        throw const AiProposalException(
          'invalid_args',
          '"routine_day_id" is required to schedule a routine day.',
          param: 'routine_day_id',
          expected: 'routine day id from get_routine_detail',
          hint: 'Call get_routine_detail and use a day\'s source_day_id.',
        );
      }
      final day = await _routineDay(db, routineDayId);
      if (day == null) {
        throw const AiProposalException(
          'not_found',
          'Routine day not found.',
          param: 'routine_day_id',
          hint: 'Call get_routine_detail for valid day ids.',
        );
      }
      final exercises = await _dayExercises(db, routineDayId);
      if (exercises.isEmpty) {
        throw const AiProposalException(
          'invalid_args',
          'That routine day has no exercises.',
          param: 'routine_day_id',
          hint: 'Pick a day with exercises, or edit the routine first.',
        );
      }
      return AiProposalDraft(
        payload: {
          'action': action,
          'date': date,
          'routine_day_id': routineDayId,
        },
        preview: {
          'v': kAiProposalPreviewVersion,
          'action': action,
          'date': date,
          'routine': day['routine_name'],
          'day': day['day_name'],
          'exercise_count': exercises.length,
          'exercises': exercises.take(_previewExercises).toList(),
          'warnings': warnings,
        },
        base: {'routine_day_id': routineDayId},
        baseHash: aiRevision({'day': routineDayId, 'exercises': exercises}),
        subjectId: routineDayId,
        summary: {
          'action': action,
          'date': date,
          'routine': day['routine_name'],
          'day': day['day_name'],
          'exercises': exercises.length,
        },
      );
    }

    if (workoutId == null) {
      throw AiProposalException(
        'invalid_args',
        '"workout_id" is required to $action a workout.',
        param: 'workout_id',
        hint: 'Find the workout id with get_workout_history.',
      );
    }
    final workout = await repo.getWorkoutIn(db, workoutId);
    if (workout == null) {
      throw const AiProposalException(
        'not_found',
        'Workout not found.',
        param: 'workout_id',
        hint: 'Use a workout id from get_workout_history.',
      );
    }
    final planned =
        workout['start_time'] == null && workout['end_time'] == null;
    if (action == 'move' && !planned) {
      throw const AiProposalException(
        'workout_not_planned',
        'Only planned workouts can be moved; this one was started or finished.',
        param: 'workout_id',
        hint:
            'Use action "copy" to repeat it on another date, or tell the user it is already in their history.',
      );
    }
    if (action == 'move' && workout['date'] == date) {
      throw const AiProposalException(
        'no_changes',
        'The workout is already on that date.',
        hint: 'Tell the user nothing needs to change.',
      );
    }
    final exercises = await _workoutExercises(db, workoutId);
    return AiProposalDraft(
      payload: {'action': action, 'date': date, 'workout_id': workoutId},
      preview: {
        'v': kAiProposalPreviewVersion,
        'action': action,
        'date': date,
        'from_date': workout['date'],
        'planned': planned,
        'exercise_count': exercises.length,
        'exercises': exercises.take(_previewExercises).toList(),
        'warnings': warnings,
      },
      base: {
        'workout_id': workoutId,
        'date': workout['date'],
        'planned': planned,
      },
      baseHash: aiRevision({
        'id': workoutId,
        'date': workout['date'],
        'start': workout['start_time'],
        'end': workout['end_time'],
      }),
      subjectId: workoutId,
      summary: {
        'action': action,
        'date': date,
        'from_date': workout['date'],
        'exercises': exercises.length,
      },
    );
  }

  @override
  Future<String?> revalidate(DatabaseExecutor txn, AiProposal proposal) async {
    final payload = proposal.payload;
    final today = dateKey(dayOf(_now()));
    // The date was valid when prepared; a proposal approved days later must not
    // schedule into the past.
    if ((payload['date'] as String? ?? '').compareTo(today) < 0) {
      return 'stale_date_passed';
    }
    if (payload['action'] == 'schedule_routine_day') {
      final id = payload['routine_day_id'] as String? ?? '';
      final day = await _routineDay(txn, id);
      if (day == null) return 'stale_target_missing';
      final exercises = await _dayExercises(txn, id);
      if (exercises.isEmpty) return 'stale_target_missing';
      return aiRevision({'day': id, 'exercises': exercises}) ==
              proposal.baseHash
          ? null
          : 'stale_revision';
    }
    final id = payload['workout_id'] as String? ?? '';
    final workout = await _db.workoutRepo.getWorkoutIn(txn, id);
    if (workout == null) return 'stale_target_missing';
    final hash = aiRevision({
      'id': id,
      'date': workout['date'],
      'start': workout['start_time'],
      'end': workout['end_time'],
    });
    return hash == proposal.baseHash ? null : 'stale_revision';
  }

  @override
  Future<Map<String, dynamic>> apply(
    DatabaseExecutor txn,
    AiProposal proposal,
  ) async {
    final payload = proposal.payload;
    final date = DateTime.parse(payload['date'] as String);
    final repo = _db.workoutRepo;
    switch (payload['action']) {
      case 'schedule_routine_day':
        final dayId = payload['routine_day_id'] as String;
        final id = await repo.createWorkoutIn(
          txn,
          id: proposal.id,
          date: date,
          routineDayId: dayId,
        );
        await repo.importRoutineDayToWorkoutIn(txn, id, dayId);
        return {
          'workout_id': id,
          'date': payload['date'],
          'action': 'schedule_routine_day',
        };
      case 'move':
        final id = payload['workout_id'] as String;
        final changed = await repo.reschedulePlannedWorkoutIn(txn, id, date);
        if (changed != 1) {
          throw const AiProposalException.stale(
            'stale_revision',
            'The workout was started, finished or deleted.',
          );
        }
        return {'workout_id': id, 'date': payload['date'], 'action': 'move'};
      case 'copy':
        final id = await repo.copyWorkoutToDateIn(
          txn,
          payload['workout_id'] as String,
          date,
          newId: proposal.id,
        );
        return {'workout_id': id, 'date': payload['date'], 'action': 'copy'};
    }
    throw const AiProposalException(
      'invalid_payload',
      'The stored proposal is not a valid schedule change.',
    );
  }

  Future<Map<String, Object?>?> _routineDay(
    DatabaseExecutor db,
    String id,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT d.id, d.name AS day_name, r.name AS routine_name
      FROM routine_days d JOIN routines r ON r.id = d.routine_id
      WHERE d.id = ?
      ''',
      [id],
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, Object?>>> _dayExercises(
    DatabaseExecutor db,
    String dayId,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT e.id AS exercise_id, e.name, e.locale_key,
        (SELECT COUNT(*) FROM predefined_sets ps
          WHERE ps.routine_exercise_id = re.id) AS sets
      FROM routine_exercises re JOIN exercises e ON e.id = re.exercise_id
      WHERE re.routine_day_id = ?
      ORDER BY re.order_index, re.id
      ''',
      [dayId],
    );
    return [for (final row in rows) Map<String, Object?>.from(row)];
  }

  Future<List<Map<String, Object?>>> _workoutExercises(
    DatabaseExecutor db,
    String workoutId,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT e.id AS exercise_id, e.name, e.locale_key,
        (SELECT COUNT(*) FROM sets s WHERE s.exercise_entry_id = ee.id) AS sets
      FROM exercise_entries ee JOIN exercises e ON e.id = ee.exercise_id
      WHERE ee.workout_id = ?
      ORDER BY ee.order_index, ee.id
      ''',
      [workoutId],
    );
    return [for (final row in rows) Map<String, Object?>.from(row)];
  }
}
