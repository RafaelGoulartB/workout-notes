import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/models/ai_proposal.dart';
import 'package:workout_notes/models/run_plan.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/models/run_voice_settings.dart';
import 'package:workout_notes/models/run_workout_step.dart';
import 'package:workout_notes/repositories/run_plan_repository.dart';
import 'package:workout_notes/services/ai_proposal_service.dart';

import 'support/ai_proposal_fixtures.dart';
import 'support/test_db.dart';

const _tool = 'propose_run_plan_adjustment';

void main() {
  late Database db;
  late DateTime clock;
  late AiProposalService service;
  late RunPlanRepository plans;
  late RunPlan plan;
  late Map<String, RunPlanWorkout> sessions;

  setUp(() async {
    db = await installTestDb();
    // Wednesday of plan week 3 (index 2): the plan started on 2026-09-14.
    clock = DateTime(2026, 9, 30, 9);
    service = AiProposalService(now: () => clock);
    plans = RunPlanRepository();
    await AiProposalFixtures.seedThread(db);

    plan = await plans.createPlan(
      name: '10k',
      goalKind: RunPlanGoalKind.tenK,
      weeks: 4,
    );
    sessions = {};
    for (var week = 0; week < 4; week++) {
      sessions['easy$week'] = await plans.addWorkout(
        planId: plan.id,
        weekIndex: week,
        name: 'Easy $week',
        dayOfWeek: 2,
        targetDistanceMeters: 6000,
      );
      final quality = await plans.addWorkout(
        planId: plan.id,
        weekIndex: week,
        name: 'Intervals $week',
        kind: RunWorkoutKind.interval,
        dayOfWeek: 4,
      );
      sessions['quality$week'] = quality;
      await plans.addStep(
        workoutId: quality.id,
        role: RunStepRole.warmup,
        metric: RunIntervalMetric.distance,
        value: 2000,
      );
      await plans.addStep(
        workoutId: quality.id,
        role: RunStepRole.work,
        metric: RunIntervalMetric.distance,
        value: 800,
        repeatGroup: 1,
        repeatCount: 6,
      );
      await plans.addStep(
        workoutId: quality.id,
        role: RunStepRole.cooldown,
        metric: RunIntervalMetric.distance,
        value: 1000,
      );
      sessions['long$week'] = await plans.addWorkout(
        planId: plan.id,
        weekIndex: week,
        name: 'Long $week',
        kind: RunWorkoutKind.long,
        dayOfWeek: 7,
        targetDistanceMeters: 12000,
      );
    }
    await plans.activatePlan(plan.id, from: DateTime(2026, 9, 14));
  });

  tearDown(uninstallTestDb);

  Future<Map<String, dynamic>> refused(Map<String, dynamic> args) async {
    final result = await service.prepare(
      threadId: AiProposalFixtures.threadId,
      toolCallId: 'c',
      toolName: _tool,
      args: args,
    );
    expect(result.ok, isFalse, reason: '${result.toMap()}');
    return result.toMap();
  }

  Map<String, dynamic> scale(int week, num factor) => {
    'action': 'scale_week',
    'plan_id': plan.id,
    'week_number': week,
    'factor': factor,
  };

  Map<String, dynamic> move(String key, int day) => {
    'action': 'move_session',
    'plan_id': plan.id,
    'workout_id': sessions[key]!.id,
    'day_of_week': day,
  };

  Future<RunPlan> reload() async => (await plans.getPlan(plan.id))!;

  group('scale_week', () {
    test(
      'lightens easy volume, keeps work reps and logs the adjustment',
      () async {
        final id = await prepareProposal(service, _tool, {
          ...scale(4, 0.8),
          'reason': 'tired',
        });
        final preview = (await service.get(id))!.preview;
        expect(preview['week'], 4);
        expect(preview['before_m'], 6000 + 12000 + 800 * 6 + 3000);
        expect(preview['after_m'], 4800 + 9600 + 800 * 6 + 2400);
        final long =
            (preview['sessions'] as List).firstWhere(
                  (s) => (s as Map)['name'] == 'Long 3',
                )
                as Map;
        expect(long['before_m'], 12000);
        expect(long['after_m'], 9600);

        final applied = await service.approve(id);
        expect(
          applied.status,
          AiProposalStatus.applied,
          reason: '${applied.errorCode}',
        );
        await service.approve(id);

        final week = (await reload()).workoutsForWeek(3);
        expect(
          week.firstWhere((w) => w.name == 'Easy 3').targetDistanceMeters,
          4800,
        );
        expect(
          week.firstWhere((w) => w.name == 'Long 3').targetDistanceMeters,
          9600,
        );
        final steps = week.firstWhere((w) => w.name == 'Intervals 3').steps;
        expect(steps.map((s) => s.value), [1600, 800, 800]);
        // Other weeks are untouched.
        expect(
          (await reload())
              .workoutsForWeek(2)
              .firstWhere((w) => w.name == 'Easy 2')
              .targetDistanceMeters,
          6000,
        );
        final adaptations = await db.query('run_plan_adaptations');
        expect(adaptations, hasLength(1));
        expect(adaptations.single['kind'], 'stepBack');
        expect(adaptations.single['status'], 'applied');
        expect(adaptations.single['week_index'], 3);
        final payload = jsonDecode(
          adaptations.single['payload_json'] as String,
        );
        expect(dig(payload, 'source'), 'ai');
        expect(dig(payload, 'reason'), 'tired');
      },
    );

    test('never rewrites lived weeks and only ever reduces', () async {
      expect((await refused(scale(2, 0.8)))['code'], 'week_in_the_past');
      expect((await refused(scale(1, 0.8)))['code'], 'week_in_the_past');
      for (final factor in [0.3, 1.0, 1.2, 0]) {
        expect(
          (await refused(scale(4, factor)))['code'],
          'invalid_args',
          reason: '$factor',
        );
      }
      expect((await refused(scale(9, 0.8)))['code'], 'invalid_args');
    });

    test('the current week with a run done is history', () async {
      await db.update(
        'scheduled_runs',
        {'status': 'completed'},
        where: 'run_plan_workout_id = ?',
        whereArgs: [sessions['easy2']!.id],
      );
      final error = await refused(scale(3, 0.8));
      expect(error['code'], 'week_has_progress');
      // A later week is still open.
      expect(
        (await service.prepare(
          threadId: AiProposalFixtures.threadId,
          toolCallId: 'x',
          toolName: _tool,
          args: scale(4, 0.8),
        )).ok,
        isTrue,
      );
    });

    test('unknown, archived and finished plans are refused', () async {
      expect(
        (await refused({...scale(4, 0.8), 'plan_id': 'zz'}))['code'],
        'not_found',
      );
      await db.update('run_plans', {'status': 'archived'});
      expect((await refused(scale(4, 0.8)))['code'], 'plan_archived');
      await db.update('run_plans', {'status': 'active'});
      clock = DateTime(2026, 11, 30);
      expect((await refused(scale(4, 0.8)))['code'], 'plan_finished');
    });

    test('a session logged after the proposal makes it stale', () async {
      final id = await prepareProposal(service, _tool, scale(4, 0.8));
      await db.update(
        'scheduled_runs',
        {'status': 'completed'},
        where: 'run_plan_workout_id = ?',
        whereArgs: [sessions['easy3']!.id],
      );
      final result = await service.approve(id);
      expect(result.status, AiProposalStatus.stale);
      expect(result.errorCode, 'stale_revision');
      expect(
        (await reload())
            .workoutsForWeek(3)
            .firstWhere((w) => w.name == 'Easy 3')
            .targetDistanceMeters,
        6000,
      );
      expect(await db.query('run_plan_adaptations'), isEmpty);
    });

    test('the week starting before approval makes it stale', () async {
      final id = await prepareProposal(service, _tool, scale(3, 0.8));
      clock = DateTime(2026, 10, 6);
      final result = await service.approve(id);
      expect(result.status, AiProposalStatus.stale);
      expect(result.errorCode, 'stale_week_started');
    });
  });

  group('move_session', () {
    test('previews the weekdays and the new date', () async {
      // A session whose day already passed can still be moved to a day ahead.
      final id = await prepareProposal(service, _tool, move('easy2', 5));
      final preview = (await service.get(id))!.preview;
      expect(preview['from_day'], 2);
      expect(preview['to_day'], 5);
      expect(preview['date'], '2026-10-02');
      expect(preview['week'], 3);
    });

    test('moves a session still ahead and the calendar follows', () async {
      final id = await prepareProposal(service, _tool, move('quality2', 5));
      final applied = await service.approve(id);
      expect(
        applied.status,
        AiProposalStatus.applied,
        reason: '${applied.errorCode}',
      );
      await service.approve(id);
      final moved = (await reload())
          .workoutsForWeek(2)
          .firstWhere((w) => w.id == sessions['quality2']!.id);
      expect(moved.dayOfWeek, 5);
      final rows = await db.query(
        'scheduled_runs',
        where: 'run_plan_workout_id = ?',
        whereArgs: [sessions['quality2']!.id],
      );
      expect(rows.single['date'], '2026-10-02');
      expect(rows.single['status'], 'planned');
      expect(await db.query('run_plan_adaptations'), isEmpty);
    });

    test(
      'warns about back-to-back hard days and suggests a better day',
      () async {
        // Intervals on Saturday, the day before the long run.
        final id = await prepareProposal(service, _tool, move('quality2', 6));
        final warnings = (await service.get(id))!.preview['warnings'] as List;
        expect(codes(warnings), containsAll(['run_hard_back_to_back']));
      },
    );

    test('refuses done sessions, past days, past weeks and no-ops', () async {
      await db.update(
        'scheduled_runs',
        {'status': 'completed'},
        where: 'run_plan_workout_id = ?',
        whereArgs: [sessions['easy2']!.id],
      );
      expect((await refused(move('easy2', 5)))['code'], 'session_already_done');
      expect((await refused(move('easy1', 5)))['code'], 'week_in_the_past');
      // Tuesday of the current week is behind us.
      expect((await refused(move('quality2', 2)))['code'], 'invalid_args');
      expect((await refused(move('quality2', 4)))['code'], 'no_changes');
      expect(
        (await refused({...move('quality2', 5), 'workout_id': 'zz'}))['code'],
        'not_found',
      );
      expect((await refused(move('quality2', 9)))['code'], 'invalid_args');
    });

    test(
      'moving a session is allowed when another one of the week was run',
      () async {
        await db.update(
          'scheduled_runs',
          {'status': 'completed'},
          where: 'run_plan_workout_id = ?',
          whereArgs: [sessions['easy2']!.id],
        );
        final id = await prepareProposal(service, _tool, move('quality2', 5));
        expect((await service.approve(id)).status, AiProposalStatus.applied);
      },
    );

    test(
      'approved after the target day passed: stale, nothing moves',
      () async {
        // Prepared on Wednesday for Friday, approved on Saturday.
        final id = await prepareProposal(service, _tool, move('quality2', 5));
        clock = DateTime(2026, 10, 3, 9);
        final result = await service.approve(id);
        expect(result.status, AiProposalStatus.stale);
        expect(result.errorCode, 'stale_date_passed');
        final kept = (await reload())
            .workoutsForWeek(2)
            .firstWhere((w) => w.id == sessions['quality2']!.id);
        expect(kept.dayOfWeek, 4);
      },
    );

    test('a session moved elsewhere in the meantime makes it stale', () async {
      final id = await prepareProposal(service, _tool, move('quality2', 5));
      await plans.moveWorkoutToDay(sessions['quality2']!.id, 6);
      final result = await service.approve(id);
      expect(result.status, AiProposalStatus.stale);
      expect(
        (await reload())
            .workoutsForWeek(2)
            .firstWhere((w) => w.id == sessions['quality2']!.id)
            .dayOfWeek,
        6,
      );
    });
  });

  test('placeholders for the other action are ignored', () async {
    final moved = await service.prepare(
      threadId: AiProposalFixtures.threadId,
      toolCallId: 'a',
      toolName: _tool,
      args: {
        ...move('quality2', 5),
        'factor': 0,
        'week_number': 0,
        'reason': '',
      },
    );
    expect(moved.ok, isTrue, reason: '${moved.toMap()}');
    final scaled = await service.prepare(
      threadId: AiProposalFixtures.threadId,
      toolCallId: 'b',
      toolName: _tool,
      args: {...scale(4, 0.8), 'workout_id': '', 'day_of_week': 0},
    );
    expect(scaled.ok, isTrue, reason: '${scaled.toMap()}');
  });
}
