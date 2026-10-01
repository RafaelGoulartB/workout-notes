import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/models/ai_proposal.dart';
import 'package:workout_notes/models/ai_tool_domain.dart';
import 'package:workout_notes/models/run_plan.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/repositories/run_plan_repository.dart';
import 'package:workout_notes/services/ai_proposals/ai_proposal_handler.dart';
import 'package:workout_notes/services/ai_proposals/ai_proposal_schema.dart';
import 'package:workout_notes/services/ai_tool_spec.dart';
import 'package:workout_notes/services/run_week_balance.dart';
import 'package:workout_notes/utils/ai_derived_id.dart';
import 'package:workout_notes/utils/ai_revision.dart';
import 'package:workout_notes/utils/date_utils.dart';

/// `propose_run_plan_adjustment`: small, safe changes to a running plan.
///
/// - `move_session`: put a planned session on another weekday of its week
///   (the calendar rows follow). The week-balance rules the app uses (no two
///   runs on one day, no two hard days back to back) are shown as warnings.
/// - `scale_week`: make a not-yet-lived week lighter (easy volume only; work
///   reps keep their shape), logged in `run_plan_adaptations` as a step back,
///   exactly like the weekly review does.
///
/// Weeks that already have a run ticked off or skipped, and weeks before the
/// current one, are history: they are never rewritten. Re-composing a whole
/// plan stays with the in-app weekly review.
class RunPlanProposalHandler extends AiProposalHandler {
  final DatabaseHelper _db;
  final DateTime Function() _now;

  RunPlanProposalHandler({DatabaseHelper? db, DateTime Function()? now})
    : _db = db ?? DatabaseHelper.instance,
      _now = now ?? DateTime.now;

  @override
  String get kind => 'run_plan';

  @override
  String get toolName => 'propose_run_plan_adjustment';

  @override
  AiToolDomain get domain => AiToolDomain.running;

  static const _actions = ['move_session', 'scale_week'];

  /// Lightest and heaviest scale: a week is never cut by more than half, and
  /// never raised (more volume is the coach's call, with the weekly review).
  static const minFactor = 0.5;
  static const maxFactor = 0.95;

  @override
  AiToolSpec get spec => AiToolSpec(
    name: toolName,
    proposal: true,
    domain: domain,
    description:
        'Adjust a running plan: move a planned session to another weekday of its week, or lighten an upcoming week (volume only goes down). Past and started weeks never change. Ids from get_run_plan.',
    properties: {
      'action': AiSchema.enumOf(_actions),
      'plan_id': AiSchema.str(),
      'week_number': AiSchema.integer('scale_week.', 1),
      'workout_id': AiSchema.str('move_session.'),
      'day_of_week': AiSchema.integer('move_session; 1 = Monday.', 1, 7),
      'factor': AiSchema.number(
        'scale_week: volume kept (0.8 = 20% less).',
        minFactor,
        maxFactor,
      ),
      'reason': AiSchema.str(),
    },
    required: ['action', 'plan_id'],
  );

  @override
  Future<AiProposalDraft> prepare(
    DatabaseExecutor db,
    AiProposalArgs args,
  ) async {
    args.allowOnly({
      'action',
      'plan_id',
      'week_number',
      'workout_id',
      'day_of_week',
      'factor',
      'reason',
    });
    final action = args.requiredEnum('action', _actions);
    final planId = args.requiredString('plan_id', maxLength: 80);
    final reason = args.optionalString('reason', maxLength: 200);
    final repo = _db.runPlanRepo;
    final plan = await repo.getPlanIn(db, planId);
    if (plan == null) {
      throw const AiProposalException(
        'not_found',
        'Running plan not found.',
        param: 'plan_id',
        hint: 'Use a plan id from get_run_plan.',
      );
    }
    if (plan.isArchived) {
      throw const AiProposalException(
        'plan_archived',
        'That plan is archived.',
        param: 'plan_id',
        hint: 'Only plans in the library or being followed can be adjusted.',
      );
    }
    final today = dayOf(_now());
    if (plan.isFinishedOn(today)) {
      throw const AiProposalException(
        'plan_finished',
        'That plan already ran its full length.',
        param: 'plan_id',
        hint: 'There is nothing left to adjust.',
      );
    }
    final rows = await repo.scheduledRowsIn(db, planId);

    if (action == 'move_session') {
      return _prepareMove(args, plan, rows, today);
    }
    return _prepareScale(args, plan, rows, today, reason);
  }

  AiProposalDraft _prepareMove(
    AiProposalArgs args,
    RunPlan plan,
    List<Map<String, Object?>> rows,
    DateTime today,
  ) {
    final workoutId = args.requiredString('workout_id', maxLength: 80);
    final dayOfWeek = args.requiredInt('day_of_week', min: 1, max: 7);
    final workout = plan.workouts.where((w) => w.id == workoutId).firstOrNull;
    if (workout == null) {
      throw const AiProposalException(
        'not_found',
        'Session not found in this plan.',
        param: 'workout_id',
        hint: 'Use a session id from get_run_plan.',
      );
    }
    final statuses = _statusesOf(rows);
    if (statuses[workoutId]?.any((s) => s != 'planned') ?? false) {
      throw const AiProposalException(
        'session_already_done',
        'That session was already run or skipped.',
        param: 'workout_id',
        hint: 'Finished sessions are history and cannot be moved.',
      );
    }
    final week = workout.weekIndex;
    _requireOpenWeek(plan, week, today, statuses, wholeWeek: false);
    if (workout.dayOfWeek == dayOfWeek) {
      throw const AiProposalException(
        'no_changes',
        'The session is already on that weekday.',
        hint: 'Tell the user nothing needs to change.',
      );
    }
    final weekStart = _weekStart(plan, week, today);
    final newDate = addDays(weekStart, dayOfWeek - 1);
    if (plan.isActivated && newDate.isBefore(today)) {
      throw AiProposalException(
        'invalid_args',
        'That weekday has already passed.',
        param: 'day_of_week',
        received: dayOfWeek,
        hint: 'Choose today or a later weekday of the same week.',
      );
    }

    // Week balance, as the app's reschedule flow checks it.
    final sessions = <RunBalanceSession>[
      for (final w in plan.workoutsForWeek(week))
        if (w.dayOfWeek != null)
          RunBalanceSession(
            id: w.id,
            date: addDays(weekStart, w.dayOfWeek! - 1),
            kind: w.kind,
            km: w.plannedDistanceMeters / 1000,
            fixed: statuses[w.id]?.any((s) => s != 'planned') ?? false,
          )
        else
          RunBalanceSession(
            id: w.id,
            date: weekStart,
            kind: w.kind,
            km: w.plannedDistanceMeters / 1000,
          ),
    ];
    final warnings = <Map<String, dynamic>>[];
    final others = {for (final w in plan.workoutsForWeek(week)) w.id: w};
    if (sessions.any((s) => s.id == workoutId)) {
      final advice = RunWeekBalance.adviseMove(
        week: sessions,
        movingId: workoutId,
        to: newDate,
        earliest: plan.isActivated ? today : null,
      );
      for (final issue in advice.issues) {
        warnings.add({
          'code': issue.problem == RunBalanceProblem.sameDay
              ? 'run_same_day'
              : 'run_hard_back_to_back',
          'other': others[issue.other.id]?.name,
        });
      }
      if (advice.betterDate != null) {
        warnings.add({
          'code': 'run_better_day',
          'day_of_week': advice.betterDate!.weekday,
        });
      }
    }

    return AiProposalDraft(
      payload: {
        'action': 'move_session',
        'plan_id': plan.id,
        'workout_id': workoutId,
        'day_of_week': dayOfWeek,
        'week_index': week,
      },
      preview: {
        'v': kAiProposalPreviewVersion,
        'action': 'move_session',
        'plan': plan.name,
        'week': week + 1,
        'session': _sessionView(workout),
        'from_day': workout.dayOfWeek,
        'to_day': dayOfWeek,
        'date': plan.isActivated ? dateKey(newDate) : null,
        'warnings': warnings,
      },
      base: {'workout_id': workoutId, 'day_of_week': workout.dayOfWeek},
      baseHash: _moveHash(workout, rows),
      subjectId: plan.id,
      summary: {
        'action': 'move_session',
        'plan': plan.name,
        'session': workout.name,
        'week': week + 1,
        'from_day': workout.dayOfWeek,
        'to_day': dayOfWeek,
      },
    );
  }

  AiProposalDraft _prepareScale(
    AiProposalArgs args,
    RunPlan plan,
    List<Map<String, Object?>> rows,
    DateTime today,
    String? reason,
  ) {
    final weekNumber = args.requiredInt('week_number', min: 1, max: plan.weeks);
    final factor = args.requiredNumber(
      'factor',
      min: minFactor,
      max: maxFactor,
    );
    final week = weekNumber - 1;
    final sessions = plan.workoutsForWeek(week);
    if (sessions.isEmpty) {
      throw AiProposalException(
        'invalid_args',
        'Week $weekNumber has no sessions.',
        param: 'week_number',
        hint: 'Pick a week of the plan that has sessions.',
      );
    }
    final statuses = _statusesOf(rows);
    _requireOpenWeek(plan, week, today, statuses);
    final before = sessions.fold<double>(
      0,
      (sum, w) => sum + w.plannedDistanceMeters,
    );
    final scaled = [
      for (final w in sessions) RunPlanRepository.scaledWorkout(w, factor),
    ];
    final after = scaled.fold<double>(
      0,
      (sum, w) => sum + w.plannedDistanceMeters,
    );
    final changed = [
      for (var i = 0; i < sessions.length; i++)
        {
          'name': sessions[i].name,
          'kind': sessions[i].kind.value,
          'before_m': sessions[i].plannedDistanceMeters.round(),
          'after_m': scaled[i].plannedDistanceMeters.round(),
          'before_s': sessions[i].plannedDurationSeconds,
          'after_s': scaled[i].plannedDurationSeconds,
        },
    ];
    final anyChange = [
      for (var i = 0; i < sessions.length; i++)
        _volumeKey(sessions[i]) != _volumeKey(scaled[i]),
    ].any((c) => c);
    if (!anyChange) {
      throw const AiProposalException(
        'no_changes',
        'This factor would not change any session.',
        param: 'factor',
        hint: 'Use a smaller factor, or tell the user nothing changes.',
      );
    }
    return AiProposalDraft(
      payload: {
        'action': 'scale_week',
        'plan_id': plan.id,
        'week_index': week,
        'factor': factor,
        'reason': reason,
        'before_m': before.round(),
        'after_m': after.round(),
      },
      preview: {
        'v': kAiProposalPreviewVersion,
        'action': 'scale_week',
        'plan': plan.name,
        'week': weekNumber,
        'factor': factor,
        'before_m': before.round(),
        'after_m': after.round(),
        'reason': reason,
        'sessions': changed,
        'warnings': const <Map<String, dynamic>>[],
      },
      base: {'week_index': week},
      baseHash: _scaleHash(sessions, rows),
      subjectId: plan.id,
      summary: {
        'action': 'scale_week',
        'plan': plan.name,
        'week': weekNumber,
        'factor': factor,
        'km_before': (before / 1000 * 10).round() / 10,
        'km_after': (after / 1000 * 10).round() / 10,
      },
    );
  }

  /// A week is open when it is the current or a later week and, when the
  /// whole week is about to change ([wholeWeek]), nothing in it was run or
  /// skipped yet.
  void _requireOpenWeek(
    RunPlan plan,
    int week,
    DateTime today,
    Map<String, List<String>> statuses, {
    bool wholeWeek = true,
  }) {
    if (plan.isActivated) {
      final current = plan.activeWeekIndexOn(today);
      if (current != null && week < current) {
        throw AiProposalException(
          'week_in_the_past',
          'Week ${week + 1} is already behind the current week.',
          param: 'week_number',
          hint:
              'Past weeks are history and are never rewritten. Pick the current week or a later one.',
        );
      }
    }
    if (!wholeWeek) return;
    final ids = [for (final w in plan.workoutsForWeek(week)) w.id];
    final lived = ids.any(
      (id) => statuses[id]?.any((s) => s != 'planned') ?? false,
    );
    if (lived) {
      throw const AiProposalException(
        'week_has_progress',
        'That week already has a run done or skipped.',
        param: 'week_number',
        hint:
            'A week in progress is never rewritten. Adjust a later week instead.',
      );
    }
  }

  DateTime _weekStart(RunPlan plan, int week, DateTime today) {
    final anchor = plan.activatedAt;
    final base = anchor == null ? mondayOf(today) : mondayOf(anchor);
    return addDays(base, 7 * (anchor == null ? 0 : week));
  }

  Map<String, List<String>> _statusesOf(List<Map<String, Object?>> rows) {
    final out = <String, List<String>>{};
    for (final row in rows) {
      final id = row['run_plan_workout_id'] as String?;
      if (id == null) continue;
      out.putIfAbsent(id, () => []).add(row['status'] as String? ?? 'planned');
    }
    return out;
  }

  Map<String, dynamic> _sessionView(RunPlanWorkout w) => {
    'name': w.name,
    'kind': w.kind.value,
    'distance_m': w.plannedDistanceMeters.round(),
    'duration_s': w.plannedDurationSeconds,
  };

  String _volumeKey(RunPlanWorkout w) => [
    w.targetDistanceMeters,
    w.targetDurationSeconds,
    for (final s in w.steps) s.value,
  ].join('|');

  String _moveHash(RunPlanWorkout w, List<Map<String, Object?>> rows) =>
      aiRevision({
        'id': w.id,
        'week': w.weekIndex,
        'day': w.dayOfWeek,
        'rows': [
          for (final r in rows)
            if (r['run_plan_workout_id'] == w.id) [r['status'], r['date']],
        ],
      });

  String _scaleHash(
    List<RunPlanWorkout> week,
    List<Map<String, Object?>> rows,
  ) {
    final ids = {for (final w in week) w.id};
    return aiRevision({
      'workouts': [
        for (final w in week) [w.id, _volumeKey(w), w.dayOfWeek],
      ],
      'rows': [
        for (final r in rows)
          if (ids.contains(r['run_plan_workout_id'])) [r['status'], r['date']],
      ],
    });
  }

  @override
  Future<String?> revalidate(DatabaseExecutor txn, AiProposal proposal) async {
    final payload = proposal.payload;
    final repo = _db.runPlanRepo;
    final plan = await repo.getPlanIn(txn, payload['plan_id'] as String? ?? '');
    if (plan == null || plan.isArchived) return 'stale_target_missing';
    final today = dayOf(_now());
    final week = (payload['week_index'] as num?)?.toInt() ?? 0;
    if (plan.isActivated) {
      final current = plan.activeWeekIndexOn(today);
      if (current != null && week < current) return 'stale_week_started';
    }
    final rows = await repo.scheduledRowsIn(txn, plan.id);
    if (payload['action'] == 'move_session') {
      final workout = plan.workouts
          .where((w) => w.id == payload['workout_id'])
          .firstOrNull;
      if (workout == null) return 'stale_target_missing';
      // Approved late: the target weekday may have passed since the preview
      // (a Friday move approved on Saturday). Never move a run into the past.
      if (plan.isActivated) {
        final target = addDays(
          _weekStart(plan, week, today),
          (payload['day_of_week'] as num).toInt() - 1,
        );
        if (target.isBefore(today)) return 'stale_date_passed';
      }
      return _moveHash(workout, rows) == proposal.baseHash
          ? null
          : 'stale_revision';
    }
    final sessions = plan.workoutsForWeek(week);
    if (sessions.isEmpty) return 'stale_target_missing';
    return _scaleHash(sessions, rows) == proposal.baseHash
        ? null
        : 'stale_revision';
  }

  @override
  Future<Map<String, dynamic>> apply(
    DatabaseExecutor txn,
    AiProposal proposal,
  ) async {
    final payload = proposal.payload;
    final repo = _db.runPlanRepo;
    final planId = payload['plan_id'] as String? ?? '';
    switch (payload['action']) {
      case 'move_session':
        await repo.moveWorkoutToDayIn(
          txn,
          payload['workout_id'] as String,
          (payload['day_of_week'] as num).toInt(),
        );
        return {
          'action': 'move_session',
          'plan_id': planId,
          'workout_id': payload['workout_id'],
          'day_of_week': payload['day_of_week'],
        };
      case 'scale_week':
        final week = (payload['week_index'] as num).toInt();
        await repo.scaleWeekIn(
          txn,
          planId,
          week,
          (payload['factor'] as num).toDouble(),
        );
        // Logged like the weekly review does, so the plan's history shows it.
        await repo.recordAdaptationIn(
          txn,
          id: aiDerivedId(proposal.id, 'adaptation'),
          planId: planId,
          weekIndex: week,
          kind: 'stepBack',
          status: 'applied',
          payload: {
            'source': 'ai',
            'factor': payload['factor'],
            'reason': payload['reason'],
            'plannedMeters': payload['before_m'],
            'newMeters': payload['after_m'],
          },
        );
        return {
          'action': 'scale_week',
          'plan_id': planId,
          'week': week + 1,
          'factor': payload['factor'],
          'meters_before': payload['before_m'],
          'meters_after': payload['after_m'],
        };
    }
    throw const AiProposalException(
      'invalid_payload',
      'The stored proposal is not a valid run plan change.',
    );
  }
}
