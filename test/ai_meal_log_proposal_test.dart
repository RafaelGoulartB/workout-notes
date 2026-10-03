import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/models/ai_proposal.dart';
import 'package:workout_notes/models/nutrition/food.dart';
import 'package:workout_notes/models/nutrition/nutrition_values.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/services/ai_proposal_service.dart';
import 'package:workout_notes/utils/nutrition_conversion.dart';

import 'support/ai_proposal_fixtures.dart';
import 'support/test_db.dart';

const _tool = 'propose_meal_log';

void main() {
  late Database db;
  late AiProposalService service;
  late NutritionRepository nutrition;
  late Food oats;
  late Food milk;
  late Food bread;

  setUp(() async {
    db = await installTestDb(seedMealTypes: true);
    service = AiProposalService(now: () => DateTime(2026, 9, 30, 9));
    nutrition = NutritionRepository();
    await AiProposalFixtures.seedThread(db);
    oats = await nutrition.createManualFood(
      name: 'Oats',
      referenceAmount: 100,
      referenceUnit: 'g',
      referenceValues: const NutritionValues(
        calories: 380,
        proteinG: 13,
        carbsG: 67,
        fatG: 7,
      ),
    );
    milk = await nutrition.createManualFood(
      name: 'Milk',
      referenceAmount: 100,
      referenceUnit: 'ml',
      referenceValues: const NutritionValues(
        calories: 60,
        proteinG: 3,
        carbsG: 5,
        fatG: 3,
      ),
      servings: const [
        ManualServingInput(
          label: '1 glass',
          quantity: 1,
          unit: 'glass',
          mlEquivalent: 200,
        ),
      ],
    );
    bread = await nutrition.createManualFood(
      name: 'Bread',
      referenceAmount: 100,
      referenceUnit: 'g',
      referenceValues: const NutritionValues(calories: 250),
      servings: const [
        ManualServingInput(
          label: '1 slice',
          quantity: 1,
          unit: 'slice',
          gramsEquivalent: 30,
        ),
        ManualServingInput(
          label: '1 roll',
          quantity: 1,
          unit: 'roll',
          gramsEquivalent: 50,
        ),
      ],
    );
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

  Map<String, dynamic> food(
    Food f,
    num quantity,
    String unit, {
    String? serving,
  }) => {
    'food_id': f.id,
    'quantity': quantity,
    'unit': unit,
    'serving_id': ?serving,
  };

  Future<int> count(String table) async =>
      Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $table')) ??
      0;

  group('prepare', () {
    test(
      'computes the numbers the diary will hold, per item and in total',
      () async {
        final id = await prepareProposal(service, _tool, {
          'date': '2026-09-29',
          'meal_type': 'breakfast',
          'foods': [food(oats, 50, 'g'), food(milk, 250, 'ml')],
        });
        final preview = (await service.get(id))!.preview;
        final items = preview['items'] as List;
        expect(dig(items, '0.calories'), 190);
        expect(dig(items, '0.protein_g'), 6.5);
        expect(dig(items, '1.calories'), 150);
        expect(dig(preview, 'totals.calories'), 340);
        expect(dig(preview, 'totals.incomplete'), false);
        expect(preview['meal_type'], 'breakfast');
        expect(preview['date'], '2026-09-29');
        expect(await count('meal_log_items'), 0);
        expect(await count('meal_logs'), 0);
      },
    );

    test(
      'servings convert through their equivalence and need an id when ambiguous',
      () async {
        final glass = (await nutrition.getFoodWithDetails(
          milk.id,
        ))!.servings.values.first.first;
        var id = await prepareProposal(service, _tool, {
          'meal_type': 'lunch',
          'foods': [food(milk, 2, 'serving')],
        });
        expect(
          dig((await service.get(id))!.preview, 'items.0.calories'),
          240,
          reason: 'one serving only: picked automatically',
        );
        id = await prepareProposal(service, _tool, {
          'meal_type': 'lunch',
          'foods': [food(milk, 1, 'serving', serving: glass.id)],
        }, toolCallId: 'b');
        expect(
          dig((await service.get(id))!.preview, 'items.0.serving.label'),
          '1 glass',
        );

        final ambiguous = await refused({
          'meal_type': 'lunch',
          'foods': [food(bread, 2, 'serving')],
        });
        expect(ambiguous['code'], 'invalid_args');
        expect((ambiguous['data'] as Map)['hint'], contains('1 slice'));
        final servingOfOtherFood = await refused({
          'meal_type': 'lunch',
          'foods': [food(bread, 1, 'serving', serving: glass.id)],
        });
        expect(
          (servingOfOtherFood['data'] as Map)['param'],
          'foods[0].serving_id',
        );
      },
    );

    test('rejects unknown ids with a hint to search the library', () async {
      final error = await refused({
        'meal_type': 'lunch',
        'foods': [food(oats, 50, 'g')..['food_id'] = 'made-up'],
      });
      expect(error['code'], 'not_found');
      expect((error['data'] as Map)['hint'], contains('search_food_library'));
      final saved = await refused({
        'meal_type': 'lunch',
        'saved_meals': [
          {'saved_meal_id': 'nope'},
        ],
      });
      expect(saved['code'], 'not_found');
    });

    test('validates the meal type, the date, quantities and units', () async {
      var error = await refused({
        'meal_type': 'brunch',
        'foods': [food(oats, 50, 'g')],
      });
      expect((error['data'] as Map)['hint'], contains('breakfast'));
      error = await refused({
        'meal_type': 'lunch',
        'date': '2026-10-01',
        'foods': [food(oats, 50, 'g')],
      });
      expect((error['data'] as Map)['param'], 'date');
      for (final bad in [0, -5, 99999]) {
        error = await refused({
          'meal_type': 'lunch',
          'foods': [food(oats, bad, 'g')],
        });
        expect(error['code'], 'invalid_args', reason: '$bad');
      }
      // Oats are per 100 g: millilitres cannot be converted.
      error = await refused({
        'meal_type': 'lunch',
        'foods': [food(oats, 200, 'ml')],
      });
      expect(error['code'], 'invalid_args');
      expect((error['data'] as Map)['hint'], contains('per 100.0 g'));
      error = await refused({'meal_type': 'lunch'});
      expect(error['message'], contains('Nothing to log'));
      error = await refused({
        'meal_type': 'lunch',
        'foods': [food(oats, 50, 'g')..['calories'] = 500],
      });
      expect(error['message'], contains('calories'));
    });

    test('flags incomplete nutrition and warns about repeated foods', () async {
      await nutrition.addMealLogItem(
        date: '2026-09-30',
        mealType: 'lunch',
        food: oats,
        variant: (await nutrition.getFoodWithDetails(oats.id))!.variants.first,
        conversion: const NutritionConversion(
          quantity: 100,
          unit: 'g',
          referenceAmount: 100,
          referenceUnit: 'g',
        ),
      );
      final id = await prepareProposal(service, _tool, {
        'meal_type': 'lunch',
        'foods': [food(bread, 60, 'g'), food(oats, 40, 'g')],
      });
      final preview = (await service.get(id))!.preview;
      expect(dig(preview, 'totals.incomplete'), true);
      expect(codes(preview['warnings']), contains('already_in_meal'));
      expect(dig(preview, 'day.before_kcal'), 380);
    });
  });

  group('approve', () {
    test('logs every item into one section exactly once', () async {
      final id = await prepareProposal(service, _tool, {
        'date': '2026-09-29',
        'meal_type': 'breakfast',
        'foods': [food(oats, 50, 'g'), food(milk, 250, 'ml')],
      });
      final applied = await service.approve(id);
      expect(
        applied.status,
        AiProposalStatus.applied,
        reason: '${applied.errorCode}',
      );
      await service.approve(id);
      final logs = await db.query('meal_logs');
      expect(logs, hasLength(1));
      expect(logs.single['date'], '2026-09-29');
      expect(logs.single['meal_type'], 'breakfast');
      final items = await db.query(
        'meal_log_items',
        orderBy: 'food_name_snapshot',
      );
      expect(items, hasLength(2));
      expect(items.map((i) => i['food_name_snapshot']), ['Milk', 'Oats']);
      expect(items.map((i) => i['calories']), [150.0, 190.0]);
      expect(items.first['quantity'], 250);
      expect(items.first['unit'], 'ml');
      expect(applied.result, {
        'date': '2026-09-29',
        'meal_type': 'breakfast',
        'items_added': 2,
      });
    });

    test(
      'adds to an existing section instead of creating a second one',
      () async {
        final first = await prepareProposal(service, _tool, {
          'meal_type': 'lunch',
          'foods': [food(oats, 50, 'g')],
        });
        final second = await prepareProposal(service, _tool, {
          'meal_type': 'lunch',
          'foods': [food(milk, 100, 'ml')],
        }, toolCallId: 'b');
        await service.approve(first);
        await service.approve(second);
        expect(await count('meal_logs'), 1);
        expect(await count('meal_log_items'), 2);
      },
    );

    test('saved meals are logged with their own quantities', () async {
      final details = await nutrition.getFoodWithDetails(oats.id);
      final meal = await nutrition.saveSavedMeal(
        name: 'Bowl',
        items: [
          SavedMealItemDraft(
            foodId: oats.id,
            foodVariantId: details!.variants.first.id,
            foodNameSnapshot: 'Oats',
            quantity: 40,
            unit: 'g',
          ),
        ],
      );
      final id = await prepareProposal(service, _tool, {
        'meal_type': 'snacks',
        'saved_meals': [
          {'saved_meal_id': meal.id},
        ],
        'foods': [food(milk, 100, 'ml')],
      });
      final preview = (await service.get(id))!.preview;
      expect(
        [dig(preview, 'items.0.kind'), dig(preview, 'items.1.kind')],
        ['food', 'saved_meal'],
      );
      expect(dig(preview, 'totals.calories'), 60 + 152);
      await service.approve(id);
      await service.approve(id);
      expect(await count('meal_log_items'), 2);
    });

    test(
      'a food edited after the preview makes it stale instead of logging other numbers',
      () async {
        final id = await prepareProposal(service, _tool, {
          'meal_type': 'lunch',
          'foods': [food(oats, 50, 'g')],
        });
        await db.update('food_variants', {'calories': 500});
        final result = await service.approve(id);
        expect(result.status, AiProposalStatus.stale);
        expect(result.errorCode, 'stale_revision');
        expect(await count('meal_log_items'), 0);
      },
    );

    test('a deleted food or meal type makes it stale', () async {
      final id = await prepareProposal(service, _tool, {
        'meal_type': 'lunch',
        'foods': [food(oats, 50, 'g')],
      });
      await db.delete('foods', where: 'id = ?', whereArgs: [oats.id]);
      final result = await service.approve(id);
      expect(result.status, AiProposalStatus.stale);
      expect(result.errorCode, 'food_missing');
      expect(await count('meal_log_items'), 0);
    });

    test('rejecting logs nothing', () async {
      final id = await prepareProposal(service, _tool, {
        'meal_type': 'lunch',
        'foods': [food(oats, 50, 'g')],
      });
      await service.reject(id);
      await service.approve(id);
      expect(await count('meal_logs'), 0);
    });
  });

  test(
    'blank optional fields and a serving id next to grams are ignored',
    () async {
      final glass = (await nutrition.getFoodWithDetails(
        milk.id,
      ))!.servings.values.first.first;
      final id = await prepareProposal(service, _tool, {
        'date': '',
        'meal_type': 'lunch',
        'foods': [
          {
            'food_id': oats.id,
            'quantity': 50,
            'unit': 'g',
            'serving_id': glass.id,
            'variant_id': '',
          },
        ],
        'saved_meals': [],
      });
      expect(dig((await service.get(id))!.preview, 'items.0.calories'), 190);
    },
  );
}
