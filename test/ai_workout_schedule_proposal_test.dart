import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/models/ai_proposal.dart';
import 'package:workout_notes/services/ai_proposal_service.dart';

import 'support/ai_proposal_fixtures.dart';
import 'support/test_db.dart';

const _tool = 'propose_workout_schedule';

void main() {
  late Database db;
  late DateTime clock;
  late AiProposalService service;

  setUp(() async {
    db = await installTestDb();
    clock = DateTime(2026, 9, 30, 9);
    service = AiProposalService(now: () => clock);
    await AiProposalFixtures.seedThreadAndExercises(db);
    await db.insert('routines', {
      'id': 'r1',
      'name': 'Push',
      'created_at': AiProposalFixtures.now,
    });
    await db.insert('routine_days', {
      'id': 'day1',
      'routine_id': 'r1',
      'name': 'Monday',
      'order_index': 0,
    });
    await db.insert('routine_days', {
      'id': 'empty',
      'routine_id': 'r1',
      'name': 'Empty',
      'order_index': 1,
    });
    await db.insert('routine_exercises', {
      'id': 're1',
      'routine_day_id': 'day1',
      'exercise_id': 'bench',
      'order_index': 0,
      'rest_time_seconds': 90,
    });
    for (var i = 0; i < 3; i++) {
      await db.insert('predefined_sets', {
        'id': 'ps$i',
        'routine_exercise_id': 're1',
        'weight': 60.0,
        'reps': 10,
        'is_warmup': 0,
        'order_index': i,
      });
    }
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

  Future<void> workout(
    String id,
    String date, {
    String? start,
    String? end,
  }) async {
    await db.insert('workouts', {
      'id': id,
      'date': date,
      'start_time': start,
      'end_time': end,
      'is_from_routine': 0,
      'created_at': AiProposalFixtures.now,
    });
    await db.insert('exercise_entries', {
      'id': 'ee-$id',
      'workout_id': id,
      'exercise_id': 'squat',
      'order_index': 0,
    });
    await db.insert('sets', {
      'id': 'set-$id',
      'exercise_entry_id': 'ee-$id',
      'weight': 100.0,
      'reps': 5,
      'is_complete': end == null ? 0 : 1,
      'is_warmup': 0,
      'order_index': 0,
    });
  }

  group('schedule_routine_day', () {
    Map<String, dynamic> args({String date = '2026-10-02'}) => {
      'action': 'schedule_routine_day',
      'date': date,
      'routine_day_id': 'day1',
    };

    test(
      'previews the day and creates a planned, linked workout once',
      () async {
        final id = await prepareProposal(service, _tool, args());
        final preview = (await service.get(id))!.preview;
        expect(preview['routine'], 'Push');
        expect(preview['day'], 'Monday');
        expect(preview['exercise_count'], 1);
        expect(await db.query('workouts'), isEmpty);

        final applied = await service.approve(id);
        expect(
          applied.status,
          AiProposalStatus.applied,
          reason: '${applied.errorCode}',
        );
        await service.approve(id);
        final workouts = await db.query('workouts');
        expect(workouts, hasLength(1));
        expect(workouts.single['id'], id);
        expect(workouts.single['date'], '2026-10-02');
        expect(workouts.single['routine_id'], 'r1');
        expect(workouts.single['routine_day_id'], 'day1');
        expect(workouts.single['start_time'], isNull);
        expect(workouts.single['end_time'], isNull);
        expect(await db.query('exercise_entries'), hasLength(1));
        expect(await db.query('sets'), hasLength(3));
      },
    );

    test('rejects past, far-future and malformed dates', () async {
      for (final date in [
        '2026-09-29',
        '2028-01-01',
        '2026-13-01',
        'tomorrow',
      ]) {
        expect(
          (await refused(args(date: date)))['code'],
          'invalid_args',
          reason: date,
        );
      }
      // Today is allowed.
      expect(
        (await service.prepare(
          threadId: AiProposalFixtures.threadId,
          toolCallId: 'c',
          toolName: _tool,
          args: args(date: '2026-09-30'),
        )).ok,
        isTrue,
      );
    });

    test('needs an existing day with exercises', () async {
      expect(
        (await refused({...args(), 'routine_day_id': 'nope'}))['code'],
        'not_found',
      );
      expect(
        (await refused({...args(), 'routine_day_id': 'empty'}))['code'],
        'invalid_args',
      );
      expect(
        ((await refused({
              'action': 'schedule_routine_day',
              'date': '2026-10-02',
            }))['data']
            as Map)['param'],
        'routine_day_id',
      );
    });

    test('warns when the date already has workouts', () async {
      await workout(
        'done',
        '2026-10-02',
        start: '2026-10-02T08:00:00',
        end: '2026-10-02T09:00:00',
      );
      final id = await prepareProposal(service, _tool, args());
      final warning =
          ((await service.get(id))!.preview['warnings'] as List).single;
      expect(dig(warning, 'code'), 'date_has_workouts');
      expect(dig(warning, 'finished'), 1);
    });

    test('a day emptied before approval makes the proposal stale', () async {
      final id = await prepareProposal(service, _tool, args());
      await db.delete('routine_exercises');
      final result = await service.approve(id);
      expect(result.status, AiProposalStatus.stale);
      expect(await db.query('workouts'), isEmpty);
    });

    test(
      'editing a set of the routine day after the preview is stale',
      () async {
        final id = await prepareProposal(service, _tool, args());
        await db.update(
          'predefined_sets',
          {'weight': 80.0},
          where: 'id = ?',
          whereArgs: ['ps1'],
        );
        final result = await service.approve(id);
        expect(result.status, AiProposalStatus.stale);
        expect(result.errorCode, 'stale_revision');
        expect(await db.query('workouts'), isEmpty);
      },
    );

    test('an approval after the date passed is stale', () async {
      final id = await prepareProposal(
        service,
        _tool,
        args(date: '2026-10-01'),
      );
      clock = DateTime(2026, 10, 3);
      final result = await service.approve(id);
      expect(result.status, AiProposalStatus.stale);
      expect(result.errorCode, 'stale_date_passed');
    });
  });

  group('move and copy', () {
    test('moves a planned workout and nothing else', () async {
      await workout('planned', '2026-10-01');
      await workout('other', '2026-10-01');
      final id = await prepareProposal(service, _tool, {
        'action': 'move',
        'date': '2026-10-05',
        'workout_id': 'planned',
      });
      final preview = (await service.get(id))!.preview;
      expect(preview['from_date'], '2026-10-01');
      expect(preview['date'], '2026-10-05');
      await service.approve(id);
      final rows = {
        for (final r in await db.query('workouts')) r['id']: r['date'],
      };
      expect(rows, {'planned': '2026-10-05', 'other': '2026-10-01'});
    });

    test('a finished or started workout cannot be moved', () async {
      await workout(
        'done',
        '2026-09-20',
        start: '2026-09-20T08:00:00',
        end: '2026-09-20T09:00:00',
      );
      await workout('live', '2026-09-30', start: '2026-09-30T08:00:00');
      for (final id in ['done', 'live']) {
        final error = await refused({
          'action': 'move',
          'date': '2026-10-05',
          'workout_id': id,
        });
        expect(error['code'], 'workout_not_planned', reason: id);
      }
      expect(
        (await refused({
          'action': 'move',
          'date': '2026-10-05',
          'workout_id': 'zz',
        }))['code'],
        'not_found',
      );
    });

    test('moving to the same date is a no-op', () async {
      await workout('planned', '2026-10-05');
      expect(
        (await refused({
          'action': 'move',
          'date': '2026-10-05',
          'workout_id': 'planned',
        }))['code'],
        'no_changes',
      );
    });

    test('a workout started after the proposal is not moved', () async {
      await workout('planned', '2026-10-01');
      final id = await prepareProposal(service, _tool, {
        'action': 'move',
        'date': '2026-10-05',
        'workout_id': 'planned',
      });
      await db.update('workouts', {'start_time': '2026-10-01T08:00:00'});
      final result = await service.approve(id);
      expect(result.status, AiProposalStatus.stale);
      expect((await db.query('workouts')).single['date'], '2026-10-01');
    });

    test('copies any workout to a new, unchecked, planned workout', () async {
      await workout(
        'done',
        '2026-09-20',
        start: '2026-09-20T08:00:00',
        end: '2026-09-20T09:00:00',
      );
      final id = await prepareProposal(service, _tool, {
        'action': 'copy',
        'date': '2026-10-06',
        'workout_id': 'done',
      });
      await service.approve(id);
      await service.approve(id);
      final workouts = await db.query('workouts', orderBy: 'date');
      expect(workouts, hasLength(2));
      final copy = workouts.last;
      expect(copy['id'], id);
      expect(copy['date'], '2026-10-06');
      expect(copy['end_time'], isNull);
      final sets = await db.query('sets');
      expect(sets, hasLength(2));
      expect(sets.where((s) => s['is_complete'] == 0), hasLength(1));
    });

    test('a copy whose source was edited after the preview is stale', () async {
      await workout(
        'done',
        '2026-09-20',
        start: '2026-09-20T08:00:00',
        end: '2026-09-20T09:00:00',
      );
      final id = await prepareProposal(service, _tool, {
        'action': 'copy',
        'date': '2026-10-06',
        'workout_id': 'done',
      });
      // The user swaps the exercise and changes the set after the preview.
      await db.update(
        'exercise_entries',
        {'exercise_id': 'bench'},
        where: 'id = ?',
        whereArgs: ['ee-done'],
      );
      final swapped = await service.approve(id);
      expect(swapped.status, AiProposalStatus.stale);
      expect(swapped.errorCode, 'stale_revision');
      expect(await db.query('workouts'), hasLength(1));

      // A set edit alone is enough too.
      await db.update(
        'exercise_entries',
        {'exercise_id': 'squat'},
        where: 'id = ?',
        whereArgs: ['ee-done'],
      );
      final second = await prepareProposal(service, _tool, {
        'action': 'copy',
        'date': '2026-10-07',
        'workout_id': 'done',
      });
      await db.update(
        'sets',
        {'weight': 140.0},
        where: 'id = ?',
        whereArgs: ['set-done'],
      );
      expect((await service.approve(second)).status, AiProposalStatus.stale);
    });

    test('action specific arguments are enforced', () async {
      expect(
        ((await refused({'action': 'copy', 'date': '2026-10-06'}))['data']
            as Map)['param'],
        'workout_id',
      );
      // An id of the other action is a placeholder: ignored, not an error.
      expect(
        (await refused({
          'action': 'copy',
          'date': '2026-10-06',
          'workout_id': 'w',
          'routine_day_id': 'day1',
        }))['code'],
        'not_found',
        reason: 'the unknown workout is the only problem',
      );
    });
  });

  test('placeholders for the other action and blanks are ignored', () async {
    await workout('planned', '2026-10-01');
    expect(
      (await service.prepare(
        threadId: AiProposalFixtures.threadId,
        toolCallId: 'a',
        toolName: _tool,
        args: {
          'action': 'schedule_routine_day',
          'date': '2026-10-02',
          'routine_day_id': 'day1',
          'workout_id': '',
        },
      )).ok,
      isTrue,
    );
    expect(
      (await service.prepare(
        threadId: AiProposalFixtures.threadId,
        toolCallId: 'b',
        toolName: _tool,
        args: {
          'action': 'move',
          'date': '2026-10-05',
          'workout_id': 'planned',
          'routine_day_id': 'day1',
        },
      )).ok,
      isTrue,
    );
  });
}
