import 'dart:convert';

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

  test('openAiReadToolsSchema returns 39 tools with valid shape', () {
    final tools = registry.openAiReadToolsSchema();
    expect(tools.length, 39);
    for (final t in tools) {
      expect(t['type'], 'function');
      expect(t['function'], isA<Map>());
      final fn = t['function'] as Map;
      expect(fn['name'], isA<String>());
      expect(fn['parameters'], isA<Map>());
    }
  });

  test('openAiChatToolsSchema exposes the full catalog plus proposals', () {
    final tools = registry.openAiChatToolsSchema();
    expect(tools, hasLength(41));
    final names = tools
        .map((tool) => (tool['function'] as Map)['name'] as String)
        .toSet();
    expect(names, containsAll(registry.readToolNames));
    expect(names, contains('propose_manual_food_creation'));
    expect(names, isNot(contains('discover_app_capabilities')));
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
    expect(tools, hasLength(1));
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

  test('tool hints point at the domain-specific tools', () {
    final names = registry.toolNamesForQuery(
      'Meu sono está afetando meu desempenho no treino?',
    );
    expect(names, contains('get_sleep_summary'));
    expect(names, contains('analyze_sleep_performance'));
    expect(names, isNot(contains('get_routine_detail')));
  });

  test('running vocabulary routes to recorded activity tools', () {
    final latest = registry.toolNamesForQuery(
      'Como foi minha última corrida e qual foi meu pace?',
    );
    expect(latest, contains('list_run_activities'));
    expect(latest, contains('get_run_activity_detail'));
    expect(latest, isNot(contains('get_exercise_personal_records')));

    final records = registry.toolNamesForQuery(
      'Qual é meu recorde de 5k e minha evolução semanal?',
    );
    expect(records, contains('get_run_achievements'));
    expect(records, contains('get_run_progress'));

    final bike = registry.toolNamesForQuery('Como foi meu pedal de bicicleta?');
    expect(bike, contains('list_run_activities'));
    expect(bike, isNot(contains('get_run_achievements')));
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

  test('dated sleep question routes directly to the night detail', () {
    expect(registry.toolNamesForQuery('Como eu dormi ontem?'), {
      'get_sleep_night_detail',
    });
    expect(registry.toolNamesForQuery('Quantos despertares tive nesse dia?'), {
      'get_sleep_night_detail',
    });
  });

  test('sleep history and profile requests use their dedicated tools', () {
    expect(
      registry.toolNamesForQuery(
        'Mostre meu histórico de sono noite por noite',
      ),
      {'get_sleep_history'},
    );
    expect(registry.toolNamesForQuery('Qual é a minha meta de sono?'), {
      'get_sleep_profile',
    });
  });

  test('sleep monitor vocabulary exposes night detail', () {
    for (final query in [
      'Eu ronquei?',
      'Teve muito barulho?',
      'Como está a latência?',
      'Qual foi a qualidade da gravação?',
      'Quantas vezes acordei?',
    ]) {
      expect(registry.toolNamesForQuery(query), {'get_sleep_night_detail'});
    }
  });

  test('casual conversation yields no tool hints', () {
    expect(registry.toolNamesForQuery('Olá, tudo bem?'), isEmpty);
  });

  test('generic workout routing does not expose unrelated tools', () {
    final names = registry.toolNamesForQuery('Como foi meu último treino?');
    expect(names, {'list_recent_workouts', 'get_workout_detail'});
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
      'end_time': now,
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

  test('nutrition routing exposes focused diary and micronutrient tools', () {
    final diary = registry.toolNamesForQuery(
      'O que comi hoje no meu diário alimentar?',
    );
    expect(diary, {'get_nutrition_diary_day'});

    final micros = registry.toolNamesForQuery(
      'Como estão meu magnésio, ferro e vitamina B12?',
    );
    expect(micros, contains('get_micronutrient_summary'));

    expect(
      registry.toolNamesForQuery('Como foi a minha alimentação de ontem?'),
      {'get_nutrition_diary_day'},
    );
    expect(
      registry.toolNamesForQuery('E me fale sobre o que eu comi nesse dia'),
      {'get_nutrition_diary_day'},
    );

    final library = registry.toolNamesForQuery(
      'Mostre meus alimentos favoritos da biblioteca de alimentos',
    );
    expect(library, contains('search_food_library'));
  });

  test(
    'nutrition diary exposes meals, foods and every tracked nutrient',
    () async {
      final date = await _seedNutritionData(db);

      final result = await registry.executeRead(
        toolName: 'get_nutrition_diary_day',
        args: {'date': date},
      );

      expect(result.ok, isTrue);
      final data = result.data as Map;
      expect(data['mealCount'], 1);
      expect(data['itemCount'], 1);
      final totals = data['totals'] as Map;
      expect(totals['proteinG'], 31.0);
      expect(totals['magnesiumMg'], 29.0);
      expect(totals['vitaminB12Ug'], 0.3);
      expect(totals['vitaminDUg'], isNull);
      final item =
          (((data['meals'] as List).single as Map)['items'] as List).single
              as Map;
      expect(item['foodName'], 'Peito de frango grelhado');
      expect((item['nutrients'] as Map)['sodiumMg'], 74.0);
      expect(item['isEstimated'], isFalse);
      final coverage = (data['dataCoverage'] as Map)['byNutrient'] as Map;
      expect((coverage['vitaminDUg'] as Map)['pct'], 0.0);
      expect((coverage['ironMg'] as Map)['pct'], 100.0);
    },
  );

  test(
    'nutrition history and micronutrient summary preserve coverage',
    () async {
      final date = await _seedNutritionData(db);

      final history = await registry.executeRead(
        toolName: 'get_nutrition_history',
        args: const {'days': 7},
      );
      final day = ((history.data as Map)['days'] as List).single as Map;
      expect(day['date'], date);
      expect((day['totals'] as Map)['potassiumMg'], 256.0);
      expect((day['totals'] as Map)['vitaminDUg'], isNull);

      final micros = await registry.executeRead(
        toolName: 'get_micronutrient_summary',
        args: const {'days': 7},
      );
      final nutrients = (micros.data as Map)['nutrients'] as Map;
      final magnesium = nutrients['magnesiumMg'] as Map;
      expect(magnesium['averageOnReportedDays'], 29.0);
      expect(magnesium['dayCoveragePct'], 100.0);
      expect(
        (magnesium['topFoodSources'] as List).single['name'],
        'Peito de frango grelhado',
      );
      expect((nutrients['vitaminDUg'] as Map)['dayCoveragePct'], 0.0);
    },
  );

  test('food tools expose variants, extra nutrients and servings', () async {
    await _seedNutritionData(db);

    final searched = await registry.executeRead(
      toolName: 'search_food_library',
      args: const {'query': 'frango'},
    );
    final food = ((searched.data as Map)['foods'] as List).single as Map;
    expect(food['id'], 'food-chicken');
    expect((food['primaryVariant'] as Map)['nutrients'], isA<Map>());

    final detailed = await registry.executeRead(
      toolName: 'get_food_detail',
      args: const {'food_id': 'food-chicken'},
    );
    final variant = ((detailed.data as Map)['variants'] as List).single as Map;
    expect((variant['extraNutrients'] as Map)['selenium_ug'], 27.6);
    expect((variant['servings'] as List).single['gramsEquivalent'], 120.0);
  });

  test(
    'saved meals and nutrition profile cover remaining nutrition data',
    () async {
      await _seedNutritionData(db);

      final listed = await registry.executeRead(
        toolName: 'list_saved_meals',
        args: const {},
      );
      final saved = ((listed.data as Map)['savedMeals'] as List).single as Map;
      expect(saved['name'], 'Frango base');
      expect((saved['totals'] as Map)['proteinG'], 31.0);

      final detail = await registry.executeRead(
        toolName: 'get_saved_meal_detail',
        args: const {'saved_meal_id': 'saved-chicken'},
      );
      expect(((detail.data as Map)['items'] as List), hasLength(1));
      final savedItem = ((detail.data as Map)['items'] as List).single as Map;
      expect((savedItem['nutrients'] as Map)['magnesiumMg'], 29.0);

      final profile = await registry.executeRead(
        toolName: 'get_nutrition_profile',
        args: const {},
      );
      final profileData = profile.data as Map;
      expect((profileData['activeDailyGoal'] as Map)['calories'], 2200.0);
      expect(
        (profileData['goalSuggestionProfile'] as Map)['activityLevel'],
        'moderate',
      );
      expect((profileData['mealTypes'] as List).single['key'], 'lunch');
      expect((profileData['libraryCounts'] as Map)['savedMeals'], 1);
    },
  );
}

Future<String> _seedNutritionData(Database db) async {
  final now = DateTime.now();
  final date = now.toIso8601String().substring(0, 10);
  final timestamp = now.toIso8601String();
  await db.insert('foods', {
    'id': 'food-chicken',
    'source': 'manual',
    'external_id': 'food-chicken',
    'name': 'Peito de frango grelhado',
    'search_name': 'peito de frango grelhado',
    'brand': null,
    'fetched_at': timestamp,
    'last_used_at': timestamp,
    'is_favorite': 1,
  });
  final nutrients = <String, Object?>{
    'calories': 165.0,
    'protein_g': 31.0,
    'carbs_g': 0.0,
    'fat_g': 3.6,
    'saturated_fat_g': 1.0,
    'monounsaturated_fat_g': 1.2,
    'polyunsaturated_fat_g': 0.8,
    'trans_fat_g': 0.0,
    'fiber_g': 0.0,
    'sugars_g': 0.0,
    'sodium_mg': 74.0,
    'potassium_mg': 256.0,
    'calcium_mg': 15.0,
    'iron_mg': 1.0,
    'magnesium_mg': 29.0,
    'zinc_mg': 1.0,
    'vitamin_a_ug': 6.0,
    'vitamin_c_mg': 0.0,
    'vitamin_d_ug': null,
    'vitamin_b12_ug': 0.3,
  };
  await db.insert('food_variants', {
    'id': 'variant-chicken',
    'food_id': 'food-chicken',
    'label': 'Grelhado',
    'reference_amount': 100.0,
    'reference_unit': 'g',
    ...nutrients,
    'extra_nutrients_json': jsonEncode({'selenium_ug': 27.6}),
    'is_estimated': 0,
  });
  await db.insert('food_servings', {
    'id': 'serving-chicken',
    'food_variant_id': 'variant-chicken',
    'label': '1 filé médio',
    'quantity': 1.0,
    'unit': 'filé',
    'grams_equivalent': 120.0,
  });
  await db.insert('meal_logs', {
    'id': 'meal-lunch',
    'date': date,
    'meal_type': 'lunch',
    'name': 'Almoço',
    'notes': 'Após o treino',
    'created_at': timestamp,
  });
  await db.insert('meal_log_items', {
    'id': 'item-chicken',
    'meal_log_id': 'meal-lunch',
    'food_id': 'food-chicken',
    'food_variant_id': 'variant-chicken',
    'food_name_snapshot': 'Peito de frango grelhado',
    'quantity': 100.0,
    'unit': 'g',
    ...nutrients,
    'nutrition_snapshot_json': jsonEncode({
      'version': 3,
      'source': 'manual',
      'external_id': 'food-chicken',
      'food_name': 'Peito de frango grelhado',
      'food_brand': null,
      'variant_label': 'Grelhado',
      'reference_amount': 100.0,
      'reference_unit': 'g',
      'quantity': 100.0,
      'unit': 'g',
      'grams_equivalent': 100.0,
      'ml_equivalent': null,
      'consumed': nutrients,
      'is_estimated': false,
      'has_missing_values': false,
    }),
    'created_at': timestamp,
  });
  await db.insert('nutrition_goals', {
    'id': 'goal-nutrition',
    'calories': 2200.0,
    'protein_g': 160.0,
    'carbs_g': 230.0,
    'fat_g': 70.0,
    'created_at': timestamp,
    'updated_at': timestamp,
    'is_active': 1,
  });
  await db.insert('app_settings', {
    'key': 'nutrition_profile_activity',
    'value': 'moderate',
  });
  await db.insert('app_settings', {
    'key': 'nutrition_profile_age',
    'value': '32',
  });
  await db.insert('meal_types', {
    'id': 'meal-type-lunch',
    'key': 'lunch',
    'name': null,
    'order_index': 0,
    'created_at': timestamp,
  });
  await db.insert('saved_meals', {
    'id': 'saved-chicken',
    'name': 'Frango base',
    'meal_type': 'lunch',
    'portions': 1.0,
    'created_at': timestamp,
    'updated_at': timestamp,
  });
  await db.insert('saved_meal_items', {
    'id': 'saved-item-chicken',
    'saved_meal_id': 'saved-chicken',
    'food_id': 'food-chicken',
    'food_variant_id': 'variant-chicken',
    'food_name_snapshot': 'Peito de frango grelhado',
    'quantity': 100.0,
    'unit': 'g',
    'order_index': 0,
  });
  return date;
}
