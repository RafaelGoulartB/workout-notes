import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/database/database_schema.dart';
import 'package:workout_notes/models/ai_proposal.dart';
import 'package:workout_notes/services/ai_memory_service.dart';
import 'package:workout_notes/services/ai_proposal_service.dart';
import 'package:workout_notes/services/ai_tool_registry.dart';
import 'package:workout_notes/services/ai_tool_specs_proposals.dart';

import 'support/ai_proposal_fixtures.dart';
import 'support/schema_snapshot.dart';
import 'support/test_db.dart';

void main() {
  late Database db;
  late DateTime clock;
  late AiProposalService service;

  Map<String, dynamic> body(String name) => {
    'action': 'create',
    'routine': {
      'name': name,
      'days': [
        {
          'name': 'Day',
          'exercises': [
            {
              'exercise_id': 'bench',
              'sets': [
                {'weight': 50, 'reps': 8},
              ],
            },
          ],
        },
      ],
    },
  };

  setUp(() async {
    db = await installTestDb();
    clock = DateTime(2026, 9, 30, 10);
    service = AiProposalService(now: () => clock);
    await AiProposalFixtures.seedThreadAndExercises(db);
  });

  tearDown(uninstallTestDb);

  group('catalog', () {
    test('exposes one proposal tool per kind in a stable order', () {
      final names = [for (final s in service.toolSpecs()) s.name];
      expect(names, [
        'propose_routine_change',
        'propose_manual_food_creation',
        'propose_meal_log',
        'propose_body_measurement',
        'propose_goal',
        'propose_nutrition_goal',
        'propose_workout_schedule',
        'propose_run_plan_adjustment',
      ]);
      expect(names.toSet(), hasLength(names.length));
      for (final name in names) {
        expect(service.handles(name), isTrue);
      }
      expect(service.handles('list_goals'), isFalse);
      expect(
        [for (final s in proposalToolSpecs()) s.name],
        names,
        reason: 'the registry list matches the service list',
      );
    });

    test('every schema is well formed: no defaults, no empty required', () {
      void check(String path, Object? node, {required bool isProperty}) {
        if (node is! Map) return;
        expect(
          node.containsKey('default'),
          isFalse,
          reason: '$path has default',
        );
        final props = node['properties'];
        if (props is Map) {
          for (final entry in props.entries) {
            check('$path.${entry.key}', entry.value, isProperty: true);
          }
        }
        final items = node['items'];
        if (items is Map) check('$path[]', items, isProperty: false);
        final required = node['required'];
        if (required != null) {
          expect(required, isNotEmpty, reason: '$path has empty required');
          for (final key in required as List) {
            expect(
              (props as Map).containsKey(key),
              isTrue,
              reason: '$path requires unknown $key',
            );
          }
        }
        final enumValues = node['enum'];
        if (enumValues != null) expect(enumValues, isNotEmpty);
      }

      for (final spec in service.toolSpecs()) {
        final fn = spec.schema['function'] as Map;
        expect(spec.proposal, isTrue, reason: spec.name);
        expect((fn['description'] as String).length, greaterThan(40));
        check(spec.name, fn['parameters'], isProperty: false);
      }
    });

    test('all schemas together stay small (sent on every request)', () {
      final sizes = {
        for (final spec in service.toolSpecs())
          spec.name: jsonEncode(spec.schema).length,
      };
      final total = sizes.values.fold<int>(0, (a, b) => a + b);
      expect(total, lessThanOrEqualTo(8000), reason: '$sizes');
    });

    test('descriptions only mention tools that exist', () {
      final known = {
        ...AiToolRegistry().readToolNames,
        ...AiMemoryService.toolNames,
        for (final spec in service.toolSpecs()) spec.name,
      };
      final pattern = RegExp(
        r'\b(?:get|list|search|analyze|propose|save|delete)_[a-z_]+',
      );
      final texts = <String>[];
      void collect(Object? node) {
        if (node is Map) {
          final description = node['description'];
          if (description is String) texts.add(description);
          node.values.forEach(collect);
        } else if (node is List) {
          node.forEach(collect);
        }
      }

      for (final spec in service.toolSpecs()) {
        collect(spec.schema);
      }
      for (final text in texts) {
        for (final match in pattern.allMatches(text)) {
          expect(known, contains(match.group(0)), reason: text);
        }
      }
    });

    test('domains: every optional domain a proposal can belong to', () {
      final domains = {
        for (final s in service.toolSpecs()) s.name: s.domain.name,
      };
      expect(domains['propose_routine_change'], 'workouts');
      expect(domains['propose_workout_schedule'], 'workouts');
      expect(domains['propose_manual_food_creation'], 'nutrition');
      expect(domains['propose_meal_log'], 'nutrition');
      expect(domains['propose_nutrition_goal'], 'nutrition');
      expect(domains['propose_body_measurement'], 'body');
      expect(domains['propose_goal'], 'goals');
      expect(domains['propose_run_plan_adjustment'], 'running');
    });
  });

  group('prepare', () {
    test('an unknown tool is refused', () async {
      final result = await service.prepare(
        threadId: AiProposalFixtures.threadId,
        toolCallId: 'c',
        toolName: 'delete_everything',
        args: const {},
      );
      expect(result.ok, isFalse);
      expect(result.code, 'unknown_tool');
    });

    test(
      'a failure carries param, expected and a hint for the model',
      () async {
        final result = await service.prepare(
          threadId: AiProposalFixtures.threadId,
          toolCallId: 'c',
          toolName: 'propose_body_measurement',
          args: {
            'date': '01/09/2026',
            'measurements': [
              {'type': 'weight', 'value': 80},
            ],
          },
        );
        expect(result.ok, isFalse);
        expect(result.code, 'invalid_args');
        final data = result.data as Map;
        expect(data['param'], 'date');
        expect(data['expected'], 'YYYY-MM-DD');
        expect(data['received'], '01/09/2026');
        expect(data['hint'], isNotEmpty);
        expect(await db.query('ai_proposals'), isEmpty);
      },
    );

    test(
      'a database failure is an internal error that does not leak',
      () async {
        final result = await service.prepare(
          threadId: 'no-such-thread',
          toolCallId: 'c',
          toolName: 'propose_routine_change',
          args: body('X'),
        );
        expect(result.ok, isFalse);
        expect(result.code, 'internal_error');
        expect(result.message, isNot(contains('FOREIGN')));
      },
    );

    test('the tool result says nothing was applied', () async {
      final result = await service.prepare(
        threadId: AiProposalFixtures.threadId,
        toolCallId: 'c',
        toolName: 'propose_routine_change',
        args: body('X'),
      );
      final data = result.data as Map;
      expect(
        data.keys,
        containsAll(['proposal_id', 'kind', 'status', 'summary']),
      );
      expect(data['applied'], false);
      expect(data['note'], contains('NOTHING'));
      expect(jsonEncode(result.toMap()), isNotEmpty);
    });
  });

  group('lifecycle', () {
    test('an awaiting proposal expires after seven days, lazily', () async {
      final id = await prepareProposal(
        service,
        'propose_routine_change',
        body('A'),
      );
      clock = clock.add(const Duration(days: 6, hours: 23));
      expect((await service.get(id))!.status, AiProposalStatus.awaiting);
      clock = clock.add(const Duration(hours: 2));
      final expired = (await service.get(id))!;
      expect(expired.status, AiProposalStatus.expired);
      expect(expired.errorCode, 'expired');
      expect(expired.resolvedAt, isNotNull);
      // Approving an expired proposal applies nothing.
      final result = await service.approve(id);
      expect(result.status, AiProposalStatus.expired);
      expect(await db.query('routines'), isEmpty);
      expect(service.outcomeFacts(result)['note'], contains('expired'));
    });

    test('resolved proposals never expire or change', () async {
      final id = await prepareProposal(
        service,
        'propose_routine_change',
        body('A'),
      );
      await service.approve(id);
      clock = clock.add(const Duration(days: 30));
      expect((await service.get(id))!.status, AiProposalStatus.applied);
    });

    test(
      'forThread lists a conversation oldest first and nothing else',
      () async {
        await AiProposalFixtures.seedThread(db, id: 'other');
        final a = await prepareProposal(
          service,
          'propose_routine_change',
          body('A'),
          toolCallId: 'a',
        );
        clock = clock.add(const Duration(minutes: 1));
        final b = await prepareProposal(
          service,
          'propose_routine_change',
          body('B'),
          toolCallId: 'b',
        );
        await prepareProposal(
          service,
          'propose_routine_change',
          body('C'),
          toolCallId: 'c',
          threadId: 'other',
        );
        final list = await service.forThread(AiProposalFixtures.threadId);
        expect(list.map((p) => p.id), [a, b]);
      },
    );

    test('deleting the conversation deletes its proposals', () async {
      await prepareProposal(service, 'propose_routine_change', body('A'));
      await db.delete('ai_chat_threads');
      expect(await db.query('ai_proposals'), isEmpty);
    });

    test(
      'approve of an unknown proposal is not_found; reject is idempotent',
      () async {
        await expectLater(service.approve('missing'), throwsA(isA<Object>()));
        final id = await prepareProposal(
          service,
          'propose_routine_change',
          body('A'),
        );
        await service.reject(id);
        final again = await service.reject(id);
        expect(again.status, AiProposalStatus.rejected);
      },
    );

    test('outcome facts are compact and language neutral', () async {
      final id = await prepareProposal(
        service,
        'propose_routine_change',
        body('A'),
      );
      var facts = service.outcomeFacts((await service.get(id))!);
      expect(facts['status'], 'awaiting');
      expect(facts['applied'], false);
      final applied = await service.approve(id);
      facts = service.outcomeFacts(applied);
      expect(facts['status'], 'applied');
      expect(facts['applied'], true);
      expect((facts['result'] as Map)['routine_id'], id);
      expect(jsonEncode(facts).length, lessThan(600));
    });
  });

  group('user-confirmed proposals', () {
    Map<String, dynamic> food() => {
      'name': 'Banana',
      'reference_amount': 100,
      'reference_unit': 'g',
      'per': {'calories': 89, 'protein_g': 1.1, 'carbs_g': 23, 'fat_g': 0.3},
    };

    test(
      'approve leaves it awaiting; the saved form marks it applied',
      () async {
        final id = await prepareProposal(
          service,
          'propose_manual_food_creation',
          food(),
        );
        final proposal = (await service.get(id))!;
        expect(
          service.applyModeOf(proposal),
          AiProposalApplyMode.userConfirmed,
        );

        final approved = await service.approve(id);
        expect(approved.status, AiProposalStatus.awaiting);
        expect(await db.query('foods'), isEmpty);

        final done = await service.markApplied(id, result: {'food_id': 'f1'});
        expect(done.status, AiProposalStatus.applied);
        expect(done.result, {'food_id': 'f1'});
        final again = await service.markApplied(id, result: {'food_id': 'f2'});
        expect(again.result, {'food_id': 'f1'}, reason: 'idempotent');
        expect(service.outcomeFacts(done)['result'], {
          'saved': true,
          'food_id': 'f1',
        });
      },
    );

    test('a rejected form cannot be marked applied afterwards', () async {
      final id = await prepareProposal(
        service,
        'propose_manual_food_creation',
        food(),
      );
      await service.reject(id);
      final result = await service.markApplied(id, result: {'food_id': 'f'});
      expect(result.status, AiProposalStatus.rejected);
    });

    test('markApplied is refused for transactional kinds', () async {
      final id = await prepareProposal(
        service,
        'propose_routine_change',
        body('A'),
      );
      await expectLater(service.markApplied(id), throwsA(isA<Object>()));
      expect((await service.get(id))!.status, AiProposalStatus.awaiting);
    });
  });

  group('legacy routine proposals', () {
    /// A v60 database (still holding `ai_routine_proposals`) upgraded to the
    /// current schema, installed as the app database.
    Future<Database> upgradedLegacyDb() async {
      final database = await openV37Database();
      addTearDown(database.close);
      for (var v = 38; v <= 60; v++) {
        await DatabaseSchema.onUpgrade(database, v - 1, v);
      }
      return database;
    }

    test('migrated rows get a rebuilt preview and can be approved', () async {
      final database = await upgradedLegacyDb();
      final now = DateTime.now().toIso8601String();
      await database.insert('ai_chat_threads', {
        'id': 't',
        'title': 'x',
        'created_at': now,
        'updated_at': now,
      });
      await database.insert('exercise_categories', {
        'id': 'chest',
        'name': 'Chest',
        'color': 1,
        'order_index': 0,
        'energy_system': 'anaerobic',
      });
      await database.insert('exercises', {
        'id': 'bench',
        'name': 'Bench',
        'category_id': 'chest',
        'type': 'weightReps',
        'is_favorite': 0,
        'created_at': now,
      });
      final target = {
        'name': 'Legacy',
        'notes': null,
        'days': [
          {
            'name': 'Mon',
            'notes': null,
            'exercises': [
              {
                'exercise_id': 'bench',
                'exercise_name': 'Bench',
                'rest_time_seconds': 90,
                'superset_group_id': null,
                'sets': [
                  {
                    'weight': 60.0,
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
      await database.insert('ai_routine_proposals', {
        'id': 'legacy',
        'thread_id': 't',
        'tool_call_id': 'call',
        'action': 'create',
        'target_json': jsonEncode(target),
        'diff_json': jsonEncode({
          'added': {'days': 1},
        }),
        'status': 'awaitingApproval',
        'created_at': now,
      });
      await DatabaseSchema.onUpgrade(database, 60, 61);
      DatabaseHelper.overrideDatabase = database;
      addTearDown(() => DatabaseHelper.overrideDatabase = null);

      final legacy = AiProposalService();
      final proposal = (await legacy.get('legacy'))!;
      expect(proposal.kind, 'routine');
      expect(proposal.status, AiProposalStatus.awaiting);
      expect(proposal.preview['v'], 2, reason: 'preview rebuilt from payload');
      expect((proposal.preview['counts'] as Map)['days_added'], 1);
      final stored = (await database.query('ai_proposals')).single;
      expect(dig(jsonDecode(stored['preview_json'] as String), 'v'), 2);

      final applied = await legacy.approve('legacy');
      expect(
        applied.status,
        AiProposalStatus.applied,
        reason: '${applied.errorCode}',
      );
      expect(await database.query('routines'), hasLength(1));
      expect((await database.query('routines')).single['id'], 'legacy');
    });
  });
}
