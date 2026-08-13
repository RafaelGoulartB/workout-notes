import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/models/nutrition/ai_manual_food_proposal.dart';
import 'package:workout_notes/services/ai_tool_registry.dart';

import 'support/ai_test_db.dart';

void main() {
  late Database db;
  late AiToolRegistry registry;

  setUp(() async {
    db = await installAiTestDb();
    registry = AiToolRegistry();
  });

  tearDown(() async {
    await uninstallAiTestDb();
  });

  test('openAiReadToolsSchema returns 18 tools with valid shape', () {
    final tools = registry.openAiReadToolsSchema();
    expect(tools.length, 18);
    for (final t in tools) {
      expect(t['type'], 'function');
      expect(t['function'], isA<Map>());
      final fn = t['function'] as Map;
      expect(fn['name'], isA<String>());
      expect(fn['parameters'], isA<Map>());
    }
  });

  test('openAiChatToolsSchema includes the guarded routine proposal tool', () {
    final tools = registry.openAiChatToolsSchema();
    expect(tools, hasLength(21));
    final proposal = tools.firstWhere(
      (tool) => (tool['function'] as Map)['name'] == 'propose_routine_change',
    );
    final parameters = (proposal['function'] as Map)['parameters'] as Map;
    expect(parameters['required'], containsAll(<String>['action', 'routine']));
  });

  test('manual food proposal schema covers the complete editable draft', () {
    final tools = registry.openAiChatToolsSchema(
      names: const {'propose_manual_food_creation'},
      includeRoutineProposal: false,
    );
    expect(tools, hasLength(2));
    final proposal = tools.firstWhere(
      (tool) =>
          (tool['function'] as Map)['name'] == 'propose_manual_food_creation',
    );
    final parameters = (proposal['function'] as Map)['parameters'] as Map;
    expect(
      parameters['required'],
      containsAll(<String>[
        'name',
        'reference_amount',
        'reference_unit',
        'per',
        'servings',
      ]),
    );
    final properties = parameters['properties'] as Map;
    final nutrients = (properties['per'] as Map)['properties'] as Map;
    expect(
      nutrients.keys,
      containsAll(<String>[
        'calories',
        'protein_g',
        'carbs_g',
        'fat_g',
        'sodium_mg',
        'potassium_mg',
        'vitamin_b12_ug',
      ]),
    );
  });

  test(
    'manual food request can omit capability discovery for compatibility',
    () {
      final tools = registry.openAiChatToolsSchema(
        names: const {'propose_manual_food_creation'},
        includeRoutineProposal: false,
        includeCapabilityDiscovery: false,
      );

      expect(tools, hasLength(1));
      expect(
        (tools.single['function'] as Map)['name'],
        'propose_manual_food_creation',
      );
    },
  );

  test('chat schema always includes lightweight capability discovery', () {
    final tools = registry.openAiChatToolsSchema(
      names: const <String>{},
      includeRoutineProposal: false,
    );
    expect(tools, hasLength(1));
    expect(
      (tools.single['function'] as Map)['name'],
      'discover_app_capabilities',
    );
  });

  test(
    'capability discovery unlocks reads and guarded routine proposals',
    () async {
      final result = await registry.executeRead(
        toolName: 'discover_app_capabilities',
        args: {
          'capabilities': ['sleep', 'routine_changes'],
        },
      );
      final tools = ((result.data as Map)['tools'] as List).cast<String>();
      expect(tools, contains('get_sleep_summary'));
      expect(tools, contains('list_exercises'));
      expect(tools, contains('propose_routine_change'));
    },
  );

  test('routine proposal schema uses portable scalar property types', () {
    final proposal = registry.openAiChatToolsSchema().firstWhere(
      (tool) => (tool['function'] as Map)['name'] == 'propose_routine_change',
    );

    void visit(dynamic value) {
      if (value is Map) {
        if (value.containsKey('type')) {
          expect(value['type'], isNot(isA<List>()));
        }
        for (final child in value.values) {
          visit(child);
        }
      } else if (value is List) {
        for (final child in value) {
          visit(child);
        }
      }
    }

    visit(proposal);
  });

  test('humanLabel returns a label for every registered tool', () {
    for (final t in registry.openAiReadToolsSchema()) {
      final name = (t['function'] as Map)['name'] as String;
      expect(registry.humanLabel(name), isNotEmpty);
    }
  });

  test('tool routing exposes a compact domain-specific catalog', () {
    final names = registry.toolNamesForQuery(
      'Meu sono está afetando meu desempenho no treino?',
    );
    expect(names, contains('get_sleep_summary'));
    expect(names, contains('analyze_sleep_performance'));
    expect(names, isNot(contains('get_routine_detail')));
    expect(
      registry.openAiReadToolsSchema(names: names).length,
      lessThan(registry.openAiReadToolsSchema().length),
    );
  });

  test('manual food creation routes directly to the guarded preview tool', () {
    expect(
      registry.toolNamesForQuery(
        'Crie um alimento manual de arroz integral cozido',
      ),
      {'propose_manual_food_creation'},
    );
    expect(
      registry.toolNamesForQuery('Adicione o alimento banana prata média'),
      {'propose_manual_food_creation'},
    );
  });

  test(
    'manual food proposal normalizes a rich draft without writing food',
    () async {
      final result = await registry.executeRead(
        toolName: 'propose_manual_food_creation',
        args: const {
          'name': 'Arroz integral cozido',
          'reference_amount': 100,
          'reference_unit': 'g',
          'per': {
            'calories': 124,
            'protein_g': 2.6,
            'carbs_g': 25.8,
            'fat_g': 1,
            'fiber_g': 2.7,
            'magnesium_mg': 44,
          },
          'servings': [
            {
              'label': '1 xícara',
              'quantity': 1,
              'unit': 'xícara',
              'grams_equivalent': 195,
            },
          ],
          'notes': 'Valores típicos para o alimento cozido sem sal.',
        },
      );

      expect(result.ok, isTrue);
      final proposal = AiManualFoodProposal.fromJson(
        (result.data as Map).cast<String, dynamic>(),
      );
      expect(proposal.status, AiManualFoodProposalStatus.awaitingApproval);
      expect(proposal.draft.name, 'Arroz integral cozido');
      expect(proposal.draft.values.carbsG, 25.8);
      expect(proposal.draft.values.magnesiumMg, 44);
      expect(proposal.draft.servings.single.gramsEquivalent, 195);
      expect(await db.query('foods'), isEmpty);
    },
  );

  test('manual food proposal rejects a draft without a food name', () async {
    final result = await registry.executeRead(
      toolName: 'propose_manual_food_creation',
      args: const {
        'reference_amount': 100,
        'reference_unit': 'g',
        'per': {},
        'servings': [],
      },
    );

    expect(result.ok, isFalse);
    expect(result.code, 'invalid_args');
  });

  test('short sleep follow-up exposes only the direct sleep summary', () {
    final names = registry.toolNamesForQuery('E o sono?');

    expect(names, {'get_sleep_summary'});
  });

  test('tool routing sends no schemas for casual conversation', () {
    final names = registry.toolNamesForQuery('Olá, tudo bem?');
    expect(names, isEmpty);
    expect(registry.openAiReadToolsSchema(names: names), isEmpty);
  });

  test('generic workout routing does not expose unrelated tools', () {
    final names = registry.toolNamesForQuery('Como foi meu último treino?');
    expect(names, {'list_recent_workouts', 'get_workout_detail'});
  });

  test('follow-up catalog contains only valid dependent reads', () {
    final names = registry.followUpToolNames(const [
      'list_recent_workouts',
    ], routineIntent: false);
    expect(names, {'get_workout_detail'});
    expect(names, isNot(contains('get_sleep_summary')));
  });

  test('tool results preserve all rows requested by the query', () async {
    await db.insert('exercise_categories', {
      'id': 'large',
      'name': 'Categoria',
      'color': 0,
      'order_index': 0,
      'energy_system': 'anaerobic',
    });
    for (var i = 0; i < 50; i++) {
      await db.insert('exercises', {
        'id': 'large-$i',
        'name': 'Exercício $i ${List.filled(500, 'x').join()}',
        'category_id': 'large',
        'type': 'weightReps',
        'is_favorite': 0,
        'created_at': DateTime.now().toIso8601String(),
      });
    }
    final result = await registry.executeRead(
      toolName: 'list_exercises',
      args: const {'limit': 50},
    );
    expect(result.ok, isTrue);
    final exercises = (result.data as Map)['exercises'] as List;
    expect(exercises, hasLength(50));
    expect((result.data as Map).containsKey('_truncated'), isFalse);
  });

  test('executeRead on unknown tool returns unknown_tool', () async {
    final r = await registry.executeRead(
      toolName: 'no_such_tool',
      args: const {},
    );
    expect(r.ok, isFalse);
    expect(r.code, 'unknown_tool');
  });

  test('list_recent_workouts returns empty list on empty DB', () async {
    final r = await registry.executeRead(
      toolName: 'list_recent_workouts',
      args: const {'limit': 5},
    );
    expect(r.ok, isTrue);
    expect((r.data as Map)['workouts'], isA<List>());
  });

  test('list_recent_workouts computes volume from sets', () async {
    final now = DateTime.now().toIso8601String();
    await db.insert('exercise_categories', {
      'id': 'chest',
      'name': 'Peito',
      'color': 0xFFE53935,
      'order_index': 0,
      'energy_system': 'anaerobic',
    });
    await db.insert('exercises', {
      'id': 'bench_press',
      'name': 'Supino Reto',
      'category_id': 'chest',
      'type': 'weightReps',
      'is_favorite': 0,
      'created_at': now,
    });
    await db.insert('workouts', {
      'id': 'w_recent',
      'date': '2024-06-01',
      'start_time': now,
      'duration_seconds': 3600,
      'estimated_calories': 367.5,
      'feeling_rating': 4,
      'is_from_routine': 0,
      'created_at': now,
    });
    await db.insert('exercise_entries', {
      'id': 'ee_recent',
      'workout_id': 'w_recent',
      'exercise_id': 'bench_press',
      'order_index': 0,
    });
    await db.insert('sets', {
      'id': 's_recent_1',
      'exercise_entry_id': 'ee_recent',
      'weight': 60.0,
      'reps': 10,
      'is_complete': 1,
      'is_warmup': 0,
      'order_index': 0,
    });
    await db.insert('sets', {
      'id': 's_recent_2',
      'exercise_entry_id': 'ee_recent',
      'weight': 60.0,
      'reps': 8,
      'is_complete': 1,
      'is_warmup': 1, // warmup, ignored
      'order_index': 1,
    });
    final r = await registry.executeRead(
      toolName: 'list_recent_workouts',
      args: const {'limit': 5},
    );
    expect(r.ok, isTrue);
    final workouts = (r.data as Map)['workouts'] as List;
    expect(workouts, hasLength(1));
    final w = workouts.first as Map;
    expect(w['id'], 'w_recent');
    expect(w['volumeKg'], 60.0 * 10);
    expect(w['exerciseCount'], 1);
    expect(w['estimatedCalories'], 367.5);
  });

  test('list_exercises returns exercise list', () async {
    await db.insert('exercise_categories', {
      'id': 'chest',
      'name': 'Peito',
      'color': 0xFFE53935,
      'order_index': 0,
      'energy_system': 'anaerobic',
    });
    await db.insert('exercises', {
      'id': 'bench_press',
      'name': 'Supino Reto',
      'category_id': 'chest',
      'type': 'weightReps',
      'is_favorite': 1,
      'created_at': DateTime.now().toIso8601String(),
    });
    final r = await registry.executeRead(
      toolName: 'list_exercises',
      args: const {'is_favorite': true},
    );
    expect(r.ok, isTrue);
    final list = (r.data as Map)['exercises'] as List;
    expect(list, hasLength(1));
    final first = list.first as Map;
    expect(first['name'], 'Supino Reto');
    expect(first['isFavorite'], true);
  });

  test('get_workout_detail returns exercise with sets', () async {
    final now = DateTime.now().toIso8601String();
    await db.insert('exercises', {
      'id': 'sq',
      'name': 'Agachamento',
      'category_id': 'legs',
      'type': 'weightReps',
      'is_favorite': 0,
      'created_at': now,
    });
    await db.insert('workouts', {
      'id': 'w_detail',
      'date': '2024-06-01',
      'duration_seconds': 1800,
      'estimated_calories': 210.25,
      'is_from_routine': 0,
      'created_at': now,
    });
    await db.insert('exercise_entries', {
      'id': 'ee_detail',
      'workout_id': 'w_detail',
      'exercise_id': 'sq',
      'order_index': 0,
    });
    await db.insert('sets', {
      'id': 's_detail_1',
      'exercise_entry_id': 'ee_detail',
      'weight': 100.0,
      'reps': 5,
      'is_complete': 1,
      'is_warmup': 0,
      'order_index': 0,
    });
    final r = await registry.executeRead(
      toolName: 'get_workout_detail',
      args: const {'workout_id': 'w_detail'},
    );
    expect(r.ok, isTrue);
    final data = r.data as Map;
    expect(data['id'], 'w_detail');
    expect(data['estimatedCalories'], 210.25);
    expect(data['exercises'], isA<List>());
    final exs = data['exercises'] as List;
    expect(exs, hasLength(1));
    final ex = exs.first as Map;
    expect(ex['exerciseId'], 'sq');
    final sets = ex['sets'] as List;
    expect(sets, hasLength(1));
  });

  test(
    'routine list and detail preserve aggregate counts and set tree',
    () async {
      final now = DateTime.now().toIso8601String();
      await db.insert('exercise_categories', {
        'id': 'legs',
        'name': 'Pernas',
        'color': 0,
        'order_index': 0,
        'energy_system': 'anaerobic',
      });
      await db.insert('exercises', {
        'id': 'squat',
        'name': 'Agachamento',
        'category_id': 'legs',
        'type': 'weightReps',
        'is_favorite': 0,
        'created_at': now,
      });
      await db.insert('routines', {
        'id': 'routine-1',
        'name': 'Pernas',
        'created_at': now,
      });
      await db.insert('routine_days', {
        'id': 'day-1',
        'routine_id': 'routine-1',
        'name': 'Dia A',
        'order_index': 0,
      });
      await db.insert('routine_exercises', {
        'id': 'routine-exercise-1',
        'routine_day_id': 'day-1',
        'exercise_id': 'squat',
        'order_index': 0,
        'rest_time_seconds': 90,
      });
      await db.insert('predefined_sets', {
        'id': 'predefined-1',
        'routine_exercise_id': 'routine-exercise-1',
        'weight': 80.0,
        'reps': 8,
        'is_warmup': 0,
        'order_index': 0,
      });

      final listed = await registry.executeRead(
        toolName: 'list_routines',
        args: const {},
      );
      final listItem = ((listed.data as Map)['routines'] as List).single as Map;
      expect(listItem['dayCount'], 1);
      expect(listItem['exerciseCount'], 1);

      final detailed = await registry.executeRead(
        toolName: 'get_routine_detail',
        args: const {'routine_id': 'routine-1'},
      );
      final day = ((detailed.data as Map)['days'] as List).single as Map;
      final exercise = (day['exercises'] as List).single as Map;
      final set = (exercise['predefinedSets'] as List).single as Map;
      expect(exercise['source_routine_exercise_id'], 'routine-exercise-1');
      expect(set['source_set_id'], 'predefined-1');
      expect(set['reps'], 8);
    },
  );

  test('list_goals returns empty list on empty DB', () async {
    final r = await registry.executeRead(
      toolName: 'list_goals',
      args: const {},
    );
    expect(r.ok, isTrue);
    final list = (r.data as Map)['goals'] as List;
    expect(list, isEmpty);
  });
}
