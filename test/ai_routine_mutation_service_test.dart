import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/services/ai_routine_mutation_service.dart';

import 'support/ai_test_db.dart';

void main() {
  late Database db;
  late AiRoutineMutationService service;

  setUp(() async {
    db = await installAiTestDb();
    service = AiRoutineMutationService();
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
}
