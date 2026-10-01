import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/models/ai_proposal.dart';
import 'package:workout_notes/services/ai_proposal_service.dart';
import 'package:workout_notes/utils/ai_revision.dart';

import 'support/ai_proposal_fixtures.dart';
import 'support/test_db.dart';

const _tool = 'propose_routine_change';

void main() {
  late Database db;
  late AiProposalService service;

  setUp(() async {
    db = await installTestDb();
    service = AiProposalService();
    await AiProposalFixtures.seedThreadAndExercises(db);
  });

  tearDown(uninstallTestDb);

  /// Routine "Push" with two days: Mon [bench: 60x10, 60x8] and Wed [squat].
  Future<void> seedRoutine({String id = 'r1', String name = 'Push'}) async {
    await db.insert('routines', {
      'id': id,
      'name': name,
      'notes': 'n',
      'created_at': AiProposalFixtures.now,
    });
    await db.insert('routine_days', {
      'id': '$id-d1',
      'routine_id': id,
      'name': 'Mon',
      'order_index': 0,
    });
    await db.insert('routine_days', {
      'id': '$id-d2',
      'routine_id': id,
      'name': 'Wed',
      'order_index': 1,
    });
    await db.insert('routine_exercises', {
      'id': '$id-e1',
      'routine_day_id': '$id-d1',
      'exercise_id': 'bench',
      'order_index': 0,
      'rest_time_seconds': 90,
    });
    await db.insert('routine_exercises', {
      'id': '$id-e2',
      'routine_day_id': '$id-d2',
      'exercise_id': 'squat',
      'order_index': 0,
      'rest_time_seconds': 120,
    });
    for (final (sid, ex, w, r, o) in [
      ('$id-s1', '$id-e1', 60.0, 10, 0),
      ('$id-s2', '$id-e1', 60.0, 8, 1),
      ('$id-s3', '$id-e2', 100.0, 5, 0),
    ]) {
      await db.insert('predefined_sets', {
        'id': sid,
        'routine_exercise_id': ex,
        'weight': w,
        'reps': r,
        'is_warmup': 0,
        'order_index': o,
      });
    }
  }

  Map<String, dynamic> set(num? weight, int? reps, {String? id}) => {
    'source_set_id': ?id,
    'weight': weight,
    'reps': reps,
  };

  /// The full current tree of `r1` as update arguments (everything kept).
  Future<Map<String, dynamic>> updateArgs({
    required List<Map<String, dynamic>> days,
    String? revision,
    String routineId = 'r1',
    String name = 'Push',
  }) async => {
    'action': 'update',
    'routine_id': routineId,
    'revision': revision ?? await routineRevision(db, routineId),
    'routine': {'name': name, 'notes': 'n', 'days': days},
  };

  Map<String, dynamic> day1({List<Map<String, dynamic>>? sets}) => {
    'source_day_id': 'r1-d1',
    'name': 'Mon',
    'exercises': [
      {
        'source_routine_exercise_id': 'r1-e1',
        'exercise_id': 'bench',
        'rest_time_seconds': 90,
        'sets': sets ?? [set(60, 10, id: 'r1-s1'), set(60, 8, id: 'r1-s2')],
      },
    ],
  };

  Map<String, dynamic> day2() => {
    'source_day_id': 'r1-d2',
    'name': 'Wed',
    'exercises': [
      {
        'source_routine_exercise_id': 'r1-e2',
        'exercise_id': 'squat',
        'rest_time_seconds': 120,
        'sets': [set(100, 5, id: 'r1-s3')],
      },
    ],
  };

  Map<String, dynamic> createArgs() => {
    'action': 'create',
    'routine': {
      'name': 'Pull',
      'days': [
        {
          'name': 'Day A',
          'exercises': [
            {
              'exercise_id': 'bench',
              'rest_time_seconds': 90,
              'sets': [set(40, 10)],
            },
          ],
        },
      ],
    },
  };

  Future<Map<String, dynamic>> callError(Map<String, dynamic> args) async {
    final result = await service.prepare(
      threadId: AiProposalFixtures.threadId,
      toolCallId: 'call_x',
      toolName: _tool,
      args: args,
    );
    expect(result.ok, isFalse, reason: '${result.toMap()}');
    return result.toMap();
  }

  group('prepare', () {
    test('stores an awaiting proposal and mutates nothing', () async {
      final result = await service.prepare(
        threadId: AiProposalFixtures.threadId,
        toolCallId: 'c1',
        toolName: _tool,
        args: createArgs(),
      );
      expect(result.ok, isTrue);
      final data = result.data as Map;
      expect(data['status'], 'awaiting');
      expect(data['applied'], false);
      expect(data['kind'], 'routine');
      expect(data['note'], contains('NOTHING was applied'));
      expect((data['summary'] as Map)['routine_name'], 'Pull');
      expect(await db.query('routines'), isEmpty);
      expect(await db.query('ai_proposals'), hasLength(1));
    });

    test('an identical pending proposal is reused', () async {
      final first = await prepareProposal(
        service,
        _tool,
        createArgs(),
        toolCallId: 'a',
      );
      final second = await prepareProposal(
        service,
        _tool,
        createArgs(),
        toolCallId: 'b',
      );
      expect(second, first);
      expect(await db.query('ai_proposals'), hasLength(1));
    });

    test('a retried tool call returns the same proposal', () async {
      final first = await prepareProposal(service, _tool, createArgs());
      final second = await prepareProposal(service, _tool, {
        ...createArgs(),
        'routine': {
          ...(createArgs()['routine'] as Map<String, dynamic>),
          'name': 'Other',
        },
      });
      expect(second, first);
    });

    test(
      'rejects source ids on create and never touches another routine',
      () async {
        await seedRoutine();
        final before = await routineRevision(db, 'r1');
        final error = await callError({
          'action': 'create',
          'routine': {
            'name': 'Copy of Push',
            'days': [day1(), day2()],
          },
        });
        expect(error['code'], 'invalid_args');
        expect((error['data'] as Map)['hint'], contains('source'));
        expect(await db.query('ai_proposals'), isEmpty);
        expect(await routineRevision(db, 'r1'), before);
      },
    );

    test('update needs a routine id and a revision', () async {
      await seedRoutine();
      var error = await callError({
        'action': 'update',
        'revision': 'x',
        'routine': {
          'name': 'p',
          'days': [day1()],
        },
      });
      expect((error['data'] as Map)['param'], 'routine_id');
      error = await callError({
        'action': 'update',
        'routine_id': 'r1',
        'routine': {
          'name': 'p',
          'days': [day1()],
        },
      });
      expect((error['data'] as Map)['param'], 'revision');
    });

    test('update refuses a stale revision with a hint', () async {
      await seedRoutine();
      final error = await callError(
        await updateArgs(days: [day1(), day2()], revision: 'deadbeef'),
      );
      expect(error['code'], 'stale_revision');
      expect((error['data'] as Map)['hint'], contains('get_routine_detail'));
    });

    test('update of a missing routine is not_found', () async {
      final error = await callError({
        'action': 'update',
        'routine_id': 'nope',
        'revision': 'x',
        'routine': {
          'name': 'p',
          'days': [day1()],
        },
      });
      expect(error['code'], 'not_found');
    });

    test('an update that changes nothing is refused', () async {
      await seedRoutine();
      final error = await callError(await updateArgs(days: [day1(), day2()]));
      expect(error['code'], 'no_changes');
    });

    test('rejects unknown ids and foreign source ids', () async {
      await seedRoutine();
      await seedRoutine(id: 'r2', name: 'Other');
      var error = await callError(
        await updateArgs(
          days: [
            {
              ...day1(),
              'exercises': [
                {
                  'exercise_id': 'ghost',
                  'sets': [set(1, 1)],
                },
              ],
            },
          ],
        ),
      );
      expect(error['code'], 'not_found');
      error = await callError(
        await updateArgs(
          days: [
            {...day1(), 'source_day_id': 'r2-d1'},
          ],
        ),
      );
      expect(error['code'], 'invalid_args');
      expect((error['data'] as Map)['param'], 'routine.days[0].source_day_id');
    });

    test('a set must stay with its own exercise', () async {
      await seedRoutine();
      final error = await callError(
        await updateArgs(
          days: [
            day1(
              sets: [
                set(60, 10, id: 'r1-s1'),
                set(100, 5, id: 'r1-s3'),
              ],
            ),
            day2(),
          ],
        ),
      );
      expect(error['code'], 'invalid_args');
    });

    group('validation', () {
      Map<String, dynamic> withSet(
        Map<String, dynamic> s, {
        String ex = 'bench',
      }) => {
        'action': 'create',
        'routine': {
          'name': 'X',
          'days': [
            {
              'name': 'D',
              'exercises': [
                {
                  'exercise_id': ex,
                  'sets': [s],
                },
              ],
            },
          ],
        },
      };

      test('caps and ranges', () async {
        for (final bad in [
          {'weight': 1e12, 'reps': 5},
          {'weight': -1, 'reps': 5},
          {'weight': 50, 'reps': 500},
          {'weight': 50, 'reps': 1.5},
          {'weight': '50', 'reps': 5},
        ]) {
          final error = await callError(withSet(bad));
          expect(error['code'], 'invalid_args', reason: '$bad');
        }
        final rest = withSet({'weight': 1, 'reps': 1});
        final restExercise = dig(rest, 'routine.days.0.exercises.0') as Map;
        restExercise['rest_time_seconds'] = 999999999;
        expect((await callError(rest))['code'], 'invalid_args');
      });

      test('set fields must fit the exercise type', () async {
        final error = await callError(
          withSet({'weight': 5, 'reps': 5}, ex: 'run'),
        );
        expect(error['code'], 'invalid_args');
        expect(error['message'], contains('weight'));
        final ok = await service.prepare(
          threadId: AiProposalFixtures.threadId,
          toolCallId: 'c',
          toolName: _tool,
          args: withSet({'distance': 5, 'time_seconds': 1500}, ex: 'run'),
        );
        expect(ok.ok, isTrue);
      });

      test('too many days, exercises and sets', () async {
        final days = [
          for (var i = 0; i < 8; i++)
            {
              'name': 'D$i',
              'exercises': [
                {
                  'exercise_id': 'bench',
                  'sets': [set(1, 1)],
                },
              ],
            },
        ];
        expect(
          (await callError({
            'action': 'create',
            'routine': {'name': 'X', 'days': days},
          }))['code'],
          'invalid_args',
        );
        final sets = [for (var i = 0; i < 11; i++) set(1, 1)];
        expect(
          (await callError({
            'action': 'create',
            'routine': {
              'name': 'X',
              'days': [
                {
                  'name': 'D',
                  'exercises': [
                    {'exercise_id': 'bench', 'sets': sets},
                  ],
                },
              ],
            },
          }))['code'],
          'invalid_args',
        );
      });

      test('types of name, notes and superset group', () async {
        for (final mutate in <void Function(Map<String, dynamic>)>[
          (r) => r['name'] = {'a': 1},
          (r) => r['notes'] = {'a': 1},
          (r) => ((r['days'] as List).first as Map)['name'] = 5,
          (r) => (dig(r, 'days.0.exercises.0') as Map)['superset_group_id'] = {
            'x': 1,
          },
        ]) {
          final args = createArgs();
          mutate(args['routine'] as Map<String, dynamic>);
          final error = await callError(args);
          expect(error['code'], 'invalid_args');
          expect(error['message'], isNot(contains('is not a subtype')));
        }
      });

      test('empty days and unknown keys', () async {
        expect(
          (await callError({
            'action': 'create',
            'routine': {'name': 'X', 'days': []},
          }))['code'],
          'invalid_args',
        );
        final args = createArgs();
        (args['routine'] as Map)['colour'] = 'red';
        final error = await callError(args);
        expect(error['message'], contains('colour'));
        expect((error['data'] as Map)['expected'], contains('days'));
      });
    });
  });

  group('approve', () {
    test('create writes the whole tree once, with the proposal id', () async {
      final id = await prepareProposal(service, _tool, createArgs());
      final applied = await service.approve(id);
      expect(applied.status, AiProposalStatus.applied);
      expect(applied.result?['routine_id'], id);
      expect(await db.query('routines'), hasLength(1));
      expect(await db.query('routine_days'), hasLength(1));
      expect(await db.query('routine_exercises'), hasLength(1));
      expect(await db.query('predefined_sets'), hasLength(1));

      final again = await service.approve(id);
      expect(again.status, AiProposalStatus.applied);
      expect(await db.query('routines'), hasLength(1));
      expect(await db.query('predefined_sets'), hasLength(1));
    });

    test('concurrent approvals apply exactly once', () async {
      final id = await prepareProposal(service, _tool, createArgs());
      await Future.wait([service.approve(id), service.approve(id)]);
      expect(await db.query('routines'), hasLength(1));
    });

    test(
      'a double apply cannot duplicate even if the claim is bypassed',
      () async {
        final id = await prepareProposal(service, _tool, createArgs());
        await service.approve(id);
        await db.update(
          'ai_proposals',
          {'status': 'awaiting'},
          where: 'id = ?',
          whereArgs: [id],
        );
        final retried = await service.approve(id);
        // The derived primary keys collide: the second apply fails and rolls
        // back instead of inserting a second tree.
        expect(retried.status, AiProposalStatus.failed);
        expect(await db.query('routines'), hasLength(1));
        expect(await db.query('routine_days'), hasLength(1));
      },
    );

    test('reject leaves routines untouched', () async {
      final id = await prepareProposal(service, _tool, createArgs());
      final rejected = await service.reject(id);
      expect(rejected.status, AiProposalStatus.rejected);
      expect(await db.query('routines'), isEmpty);
      final approved = await service.approve(id);
      expect(approved.status, AiProposalStatus.rejected);
      expect(await db.query('routines'), isEmpty);
    });

    test('moving an exercise to a later day keeps it and its sets', () async {
      await seedRoutine();
      // bench leaves Monday for Wednesday; Monday gets a new plank.
      final id = await prepareProposal(
        service,
        _tool,
        await updateArgs(
          days: [
            {
              'source_day_id': 'r1-d1',
              'name': 'Mon',
              'exercises': [
                {
                  'exercise_id': 'plank',
                  'sets': [
                    {'time_seconds': 60},
                  ],
                },
              ],
            },
            {
              'source_day_id': 'r1-d2',
              'name': 'Wed',
              'exercises': [
                dig(day2(), 'exercises.0'),
                {
                  'source_routine_exercise_id': 'r1-e1',
                  'exercise_id': 'bench',
                  'rest_time_seconds': 90,
                  'sets': [set(60, 10, id: 'r1-s1'), set(60, 8, id: 'r1-s2')],
                },
              ],
            },
          ],
        ),
      );
      final preview = (await service.get(id))!.preview;
      expect(
        (preview['counts'] as Map)['exercises_moved'],
        1,
        reason: 'moved, not removed',
      );
      expect((preview['counts'] as Map)['exercises_removed'], 0);

      final applied = await service.approve(id);
      expect(
        applied.status,
        AiProposalStatus.applied,
        reason: '${applied.errorCode}',
      );
      final bench = await db.query(
        'routine_exercises',
        where: 'id = ?',
        whereArgs: ['r1-e1'],
      );
      expect(bench, hasLength(1));
      expect(bench.first['routine_day_id'], 'r1-d2');
      final sets = await db.query(
        'predefined_sets',
        where: 'routine_exercise_id = ?',
        whereArgs: ['r1-e1'],
        orderBy: 'order_index',
      );
      expect(sets.map((s) => s['id']), ['r1-s1', 'r1-s2']);
      expect(await db.query('routine_exercises'), hasLength(3));
    });

    test(
      'removing a day, an exercise and a set deletes exactly those',
      () async {
        await seedRoutine();
        final id = await prepareProposal(
          service,
          _tool,
          await updateArgs(
            days: [
              day1(sets: [set(60, 10, id: 'r1-s1')]),
            ],
          ),
        );
        final proposal = (await service.get(id))!;
        final counts = proposal.preview['counts'] as Map;
        expect(counts['days_removed'], 1);
        expect(counts['exercises_removed'], 1);
        expect(counts['sets_removed'], 1);
        expect([
          for (final removal in proposal.preview['removals'] as List)
            dig(removal, 'type'),
        ], containsAll(['day', 'exercise', 'set']));
        await service.approve(id);
        expect(await db.query('routine_days'), hasLength(1));
        expect(await db.query('routine_exercises'), hasLength(1));
        expect(await db.query('predefined_sets'), hasLength(1));
      },
    );

    test(
      'the preview shows swaps, reorders and 60 to 200 kg honestly',
      () async {
        await seedRoutine();
        final id = await prepareProposal(
          service,
          _tool,
          await updateArgs(
            name: 'Push v2',
            days: [
              {
                'source_day_id': 'r1-d1',
                'name': 'Mon',
                'exercises': [
                  {
                    'source_routine_exercise_id': 'r1-e1',
                    'exercise_id': 'squat',
                    'rest_time_seconds': 90,
                    'sets': [
                      set(200, 10, id: 'r1-s1'),
                      set(60, 8, id: 'r1-s2'),
                    ],
                  },
                ],
              },
              day2(),
            ],
          ),
        );
        final preview = (await service.get(id))!.preview;
        expect(preview['current_name'], 'Push');
        expect(preview['routine_name'], 'Push v2');
        expect(preview['name_changed'], true);
        final swaps = preview['replacements'] as List;
        expect(swaps, hasLength(1));
        expect(dig(swaps, '0.from.name'), 'Bench press');
        expect(dig(swaps, '0.to.name'), 'Squat');
        expect(dig(preview, 'days.0.exercises.0.sets.0.changes.weight'), {
          'from': 60.0,
          'to': 200.0,
        });
      },
    );

    test('a routine edited after the proposal makes it stale', () async {
      await seedRoutine();
      final id = await prepareProposal(
        service,
        _tool,
        await updateArgs(
          days: [
            day1(
              sets: [
                set(70, 10, id: 'r1-s1'),
                set(60, 8, id: 'r1-s2'),
              ],
            ),
            day2(),
          ],
        ),
      );
      await db.update(
        'predefined_sets',
        {'weight': 65},
        where: 'id = ?',
        whereArgs: ['r1-s2'],
      );
      final result = await service.approve(id);
      expect(result.status, AiProposalStatus.stale);
      expect(result.errorCode, 'stale_revision');
      final s1 = await db.query(
        'predefined_sets',
        where: 'id = ?',
        whereArgs: ['r1-s1'],
      );
      expect(s1.first['weight'], 60);
      expect(service.outcomeFacts(result)['note'], contains('NOT applied'));
    });

    test('a failing apply rolls back everything and ends failed', () async {
      await seedRoutine();
      final id = await prepareProposal(
        service,
        _tool,
        await updateArgs(
          days: [
            day1(
              sets: [
                set(70, 10, id: 'r1-s1'),
                set(60, 8, id: 'r1-s2'),
              ],
            ),
            day2(),
          ],
        ),
      );
      // Corrupt the stored payload so a row id does not exist: the UPDATE
      // affects no row and the whole transaction must abort.
      final row = (await db.query(
        'ai_proposals',
        where: 'id = ?',
        whereArgs: [id],
      )).first;
      final payload = (row['payload_json'] as String).replaceFirst(
        'r1-s2',
        'ghost',
      );
      await db.update(
        'ai_proposals',
        {'payload_json': payload},
        where: 'id = ?',
        whereArgs: [id],
      );
      final result = await service.approve(id);
      expect(result.status, AiProposalStatus.failed);
      expect(result.errorCode, 'apply_failed');
      final s1 = await db.query(
        'predefined_sets',
        where: 'id = ?',
        whereArgs: ['r1-s1'],
      );
      expect(s1.first['weight'], 60, reason: 'earlier writes rolled back');
    });

    test(
      'an exercise deleted before approval makes the proposal stale',
      () async {
        final id = await prepareProposal(service, _tool, createArgs());
        await db.delete('exercises', where: 'id = ?', whereArgs: ['bench']);
        final result = await service.approve(id);
        expect(result.status, AiProposalStatus.stale);
        expect(result.errorCode, 'exercise_missing');
        expect(await db.query('routines'), isEmpty);
      },
    );
  });

  group('placeholders models write into optional fields', () {
    test('zeros and blanks that do not apply are ignored', () async {
      // reps 0 on a run, weight 0 on a distance exercise, blank ids on create.
      final id = await prepareProposal(service, _tool, {
        'action': 'create',
        'routine_id': '',
        'revision': '',
        'routine': {
          'name': 'Mixed',
          'notes': '',
          'days': [
            {
              'source_day_id': '',
              'name': 'D',
              'exercises': [
                {
                  'source_routine_exercise_id': '',
                  'exercise_id': 'run',
                  'superset_group_id': '',
                  'sets': [
                    {
                      'source_set_id': '',
                      'weight': 0,
                      'reps': 0,
                      'distance': 5,
                      'time_seconds': 1500,
                    },
                  ],
                },
                {
                  'exercise_id': 'bench',
                  'sets': [
                    {'weight': 40, 'reps': 8, 'distance': 0, 'time_seconds': 0},
                  ],
                },
              ],
            },
          ],
        },
      });
      await service.approve(id);
      final sets = await db.query('predefined_sets', orderBy: 'order_index');
      expect(sets, hasLength(2));
      final run = sets.firstWhere((s) => s['distance'] == 5.0);
      expect(run['weight'], isNull);
      expect(run['reps'], isNull);
      final bench = sets.firstWhere((s) => s['weight'] == 40.0);
      expect(bench['distance'], isNull);
      expect(bench['time_seconds'], isNull);
    });

    test(
      'a real value in a field the type does not use is still refused',
      () async {
        final error = await callError({
          'action': 'create',
          'routine': {
            'name': 'X',
            'days': [
              {
                'name': 'D',
                'exercises': [
                  {
                    'exercise_id': 'run',
                    'sets': [
                      {'weight': 20, 'distance': 5},
                    ],
                  },
                ],
              },
            ],
          },
        });
        expect(error['code'], 'invalid_args');
      },
    );
  });
}
