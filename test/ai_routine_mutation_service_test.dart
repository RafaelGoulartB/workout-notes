import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/services/ai_routine_mutation_service.dart';

import 'support/ai_test_db.dart';

void main() {
  late Database db;
  late AiRoutineMutationService service;

  Future<void> seedPrerequisites() async {
    final now = DateTime.now().toIso8601String();
    await db.insert('ai_chat_threads', {
      'id': 'thread_1',
      'title': 'Teste',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('exercise_categories', {
      'id': 'chest',
      'name': 'Peito',
      'color': 1,
      'order_index': 0,
      'energy_system': 'anaerobic',
    });
    await db.insert('exercises', {
      'id': 'bench',
      'name': 'Supino',
      'category_id': 'chest',
      'type': 'weightReps',
      'is_favorite': 0,
      'created_at': now,
    });
  }

  setUp(() async {
    db = await installAiTestDb();
    service = AiRoutineMutationService();
    await seedPrerequisites();
  });

  tearDown(() async => uninstallAiTestDb());

  Map<String, dynamic> target() => {
    'name': 'Push A',
    'notes': 'Peito e tríceps',
    'days': [
      {
        'name': 'Segunda',
        'notes': null,
        'exercises': [
          {
            'exercise_id': 'bench',
            'rest_time_seconds': 90,
            'superset_group_id': null,
            'sets': [
              {
                'weight': 60,
                'reps': 10,
                'distance': null,
                'time_seconds': null,
                'is_warmup': false,
              },
            ],
          },
        ],
      },
    ],
  };

  Future<String> prepare({String toolCallId = 'call_1'}) async {
    final result = await service.prepareProposal(
      threadId: 'thread_1',
      toolCallId: toolCallId,
      args: {'action': 'create', 'routine': target()},
      explicitRequest: true,
    );
    expect(result.ok, isTrue);
    return ((result.data as Map)['proposalId'] as String);
  }

  test('preparing a proposal does not mutate routines', () async {
    await prepare();
    expect(await db.query('routines'), isEmpty);
    expect(await db.query('ai_routine_proposals'), hasLength(1));
  });

  test('rejecting a proposal does not mutate routines', () async {
    final id = await prepare();
    final proposal = await service.reject(id);
    expect(proposal.status.name, 'rejected');
    expect(await db.query('routines'), isEmpty);
  });

  test('approved creation writes complete routine tree once', () async {
    final id = await prepare();
    final proposal = await service.approve(id);
    expect(proposal.status.name, 'applied');
    final routines = await db.query('routines');
    expect(routines, hasLength(1));
    final days = await db.query('routine_days');
    final exercises = await db.query('routine_exercises');
    final sets = await db.query('predefined_sets');
    expect(days, hasLength(1));
    expect(exercises, hasLength(1));
    expect(sets, hasLength(1));
    expect(sets.first['reps'], 10);
    final again = await service.approve(id);
    expect(again.status.name, 'applied');
    expect(await db.query('routines'), hasLength(1));
  });

  test('approval repairs fresh databases missing routine day notes', () async {
    await uninstallAiTestDb();
    db = await installAiTestDb(includeRoutineDayNotes: false);
    service = AiRoutineMutationService();
    await seedPrerequisites();

    final id = await prepare();
    final proposal = await service.approve(id);

    expect(proposal.status.name, 'applied');
    final columns = await db.rawQuery('PRAGMA table_info(routine_days)');
    expect(columns.map((column) => column['name']), contains('notes'));
    expect((await db.query('routine_days')).single['notes'], isNull);
  });

  test('invalid action is rejected instead of becoming create', () async {
    final result = await service.prepareProposal(
      threadId: 'thread_1',
      toolCallId: 'call_invalid_action',
      args: {'action': 'delete', 'routine': target()},
      explicitRequest: true,
    );

    expect(result.ok, isFalse);
    expect(result.code, 'invalid_args');
    expect(await db.query('ai_routine_proposals'), isEmpty);
  });

  test('failed application rolls back the entire routine tree', () async {
    final id = await prepare();
    await db.update(
      'ai_routine_proposals',
      {'target_json': '{"name":"Broken","days":"invalid"}'},
      where: 'id = ?',
      whereArgs: [id],
    );

    await expectLater(
      service.approve(id),
      throwsA(isA<AiRoutineMutationException>()),
    );
    expect(await db.query('routines'), isEmpty);
    final row = (await db.query(
      'ai_routine_proposals',
      where: 'id = ?',
      whereArgs: [id],
    )).single;
    expect(row['status'], 'awaitingApproval');
  });

  test('approval fails safely when an exercise no longer exists', () async {
    final id = await prepare();
    await db.delete('exercises', where: 'id = ?', whereArgs: ['bench']);

    final proposal = await service.approve(id);

    expect(proposal.status.name, 'failed');
    expect(proposal.errorCode, 'exercise_missing');
    expect(await db.query('routines'), isEmpty);
  });

  test('an outdated update proposal is never applied', () async {
    final createdId = await prepare();
    final created = await service.approve(createdId);
    final routineId = created.appliedRoutineId!;
    final update = await service.prepareProposal(
      threadId: 'thread_1',
      toolCallId: 'call_2',
      explicitRequest: true,
      args: {
        'action': 'update',
        'routine_id': routineId,
        'routine': {
          ...target(),
          'name': 'Push B',
          'days': (await service.loadRoutineTree(routineId))!['days'],
        },
      },
    );
    final updateId = (update.data as Map)['proposalId'] as String;
    await db.update(
      'routines',
      {'name': 'Mudança manual'},
      where: 'id = ?',
      whereArgs: [routineId],
    );
    final stale = await service.approve(updateId);
    expect(stale.status.name, 'stale');
    expect(
      (await db.query(
        'routines',
        where: 'id = ?',
        whereArgs: [routineId],
      )).first['name'],
      'Mudança manual',
    );
  });

  test('duplicate source ids in an update proposal are rejected', () async {
    final created = await service.approve(await prepare());
    final routineId = created.appliedRoutineId!;
    final tree = (await service.loadRoutineTree(routineId))!;
    final day = Map<String, dynamic>.from((tree['days'] as List).single as Map);
    final duplicateDay = Map<String, dynamic>.from(day)
      ..['exercises'] = <Map<String, dynamic>>[];

    final result = await service.prepareProposal(
      threadId: 'thread_1',
      toolCallId: 'call_duplicate_source',
      explicitRequest: true,
      args: {
        'action': 'update',
        'routine_id': routineId,
        'routine': {
          'name': 'Duplicada',
          'days': [day, duplicateDay],
        },
      },
    );

    expect(result.ok, isFalse);
    expect(result.code, 'invalid_args');
    expect(result.message, contains('source_day_id está duplicado'));
  });
}
