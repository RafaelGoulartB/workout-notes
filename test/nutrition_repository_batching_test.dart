import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/models/nutrition/food.dart';
import 'package:workout_notes/models/nutrition/nutrition_values.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/utils/nutrition_conversion.dart';

import 'support/sql_capture.dart';
import 'support/test_db.dart';

void main() {
  late Database db;
  late SqlLog sqlLog;
  late NutritionRepository repo;

  setUpAll(initSqfliteFfiForTests);

  setUp(() async {
    (db, sqlLog) = await installCountingTestDb(seedMealTypes: true);
    repo = NutritionRepository();
  });

  tearDown(uninstallTestDb);

  Future<Food> makeFood(
    String name, {
    double calories = 100,
    List<ManualServingInput> servings = const [],
  }) => repo.createManualFood(
    name: name,
    referenceAmount: 100,
    referenceUnit: 'g',
    referenceValues: NutritionValues(
      calories: calories,
      proteinG: 10,
      carbsG: 20,
      fatG: 5,
    ),
    servings: servings,
  );

  Future<SavedMealItemDraft> draftOf(Food food, {double grams = 100}) async {
    final details = await repo.getFoodWithDetails(food.id);
    return SavedMealItemDraft(
      foodId: food.id,
      foodVariantId: details!.variants.first.id,
      foodNameSnapshot: food.name,
      quantity: grams,
      unit: 'g',
    );
  }

  Future<int> count(String table) async =>
      Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $table')) ??
      0;

  group('addSavedMealToDate is atomic', () {
    late Food oats;
    late Food boom;
    late Food milk;
    late String mealId;

    setUp(() async {
      oats = await makeFood('Oats', calories: 380);
      boom = await makeFood('Boom', calories: 50);
      milk = await makeFood('Milk', calories: 60);
      final meal = await repo.saveSavedMeal(
        name: 'Breakfast bowl',
        items: [
          await draftOf(oats, grams: 50),
          await draftOf(boom, grams: 10),
          await draftOf(milk, grams: 200),
        ],
      );
      mealId = meal.id;
    });

    test('adds every ingredient to one section', () async {
      final result = await repo.addSavedMealToDate(
        date: '2026-08-01',
        mealType: 'breakfast',
        savedMealId: mealId,
      );

      expect(result, (added: 3, skipped: 0));
      final logs = await db.query('meal_logs');
      expect(logs, hasLength(1));
      final items = await db.query('meal_log_items', orderBy: 'created_at');
      expect(items, hasLength(3));
      expect(items.map((i) => i['meal_log_id']).toSet(), {logs.single['id']});
      expect(items.map((i) => i['food_name_snapshot']).toSet(), {
        'Oats',
        'Boom',
        'Milk',
      });
      // Recently-used recency moves for every logged food.
      final foods = await db.query('foods');
      expect(foods.every((f) => f['last_used_at'] != null), isTrue);
    });

    test('a failure on the second ingredient writes nothing', () async {
      await db.execute('''
        CREATE TRIGGER fail_boom BEFORE INSERT ON meal_log_items
        WHEN NEW.food_name_snapshot = 'Boom'
        BEGIN SELECT RAISE(ABORT, 'boom'); END
      ''');

      await expectLater(
        repo.addSavedMealToDate(
          date: '2026-08-01',
          mealType: 'breakfast',
          savedMealId: mealId,
        ),
        throwsA(isA<DatabaseException>()),
      );

      expect(await count('meal_log_items'), 0);
      expect(await count('meal_logs'), 0);
      expect(
        (await db.query('foods')).every((f) => f['last_used_at'] == null),
        isTrue,
      );

      // A retry after the cause is gone logs each ingredient exactly once.
      await db.execute('DROP TRIGGER fail_boom');
      final retry = await repo.addSavedMealToDate(
        date: '2026-08-01',
        mealType: 'breakfast',
        savedMealId: mealId,
      );
      expect(retry, (added: 3, skipped: 0));
      expect(await count('meal_log_items'), 3);
    });

    test('a deleted food is skipped, not a failure', () async {
      await db.delete('foods', where: 'id = ?', whereArgs: [boom.id]);

      final result = await repo.addSavedMealToDate(
        date: '2026-08-01',
        mealType: 'breakfast',
        savedMealId: mealId,
      );

      expect(result, (added: 2, skipped: 1));
      expect(
        (await db.query('meal_log_items')).map((i) => i['food_name_snapshot']),
        containsAll(['Oats', 'Milk']),
      );
    });

    test(
      'resolves foods and writes with a bounded number of queries',
      () async {
        sqlLog.clear();
        await repo.addSavedMealToDate(
          date: '2026-08-01',
          mealType: 'breakfast',
          savedMealId: mealId,
        );

        // saved meal + items + variants + servings, foods + variants +
        // servings, meal log lookup, one batch, one recency update.
        expect(sqlLog.reads, lessThanOrEqualTo(9));
        expect(sqlLog.writes, lessThanOrEqualTo(4));
      },
    );
  });

  group('diary and saved-meal reads are batched', () {
    test('getDayMeals uses two queries however many meals', () async {
      final food = await makeFood('Rice');
      final details = (await repo.getFoodWithDetails(food.id))!;
      for (final type in ['breakfast', 'lunch', 'dinner', 'snacks']) {
        for (var i = 0; i < 3; i++) {
          await repo.addMealLogItem(
            date: '2026-08-01',
            mealType: type,
            food: food,
            variant: details.variants.first,
            conversion: _grams(100.0 + i),
          );
        }
      }
      await repo.addMealLogItem(
        date: '2026-08-02',
        mealType: 'lunch',
        food: food,
        variant: details.variants.first,
        conversion: _grams(50),
      );

      sqlLog.clear();
      final meals = await repo.getDayMeals('2026-08-01');

      expect(sqlLog.reads, 2);
      expect(meals.map((m) => m.log.mealType).toSet(), {
        'breakfast',
        'lunch',
        'dinner',
        'snacks',
      });
      for (final meal in meals) {
        expect(meal.items.map((i) => i.quantity), [100.0, 101.0, 102.0]);
      }
      expect(await repo.getDayMeals('2026-01-01'), isEmpty);
    });

    test('getSavedMeals loads items and variants in batch', () async {
      final foods = [
        await makeFood('A', calories: 100),
        await makeFood(
          'B',
          calories: 200,
          servings: const [
            ManualServingInput(
              label: 'Slice',
              quantity: 1,
              unit: 'unit',
              gramsEquivalent: 30,
            ),
          ],
        ),
        await makeFood('C', calories: 300),
      ];
      final ids = <String>[];
      for (var m = 0; m < 4; m++) {
        final saved = await repo.saveSavedMeal(
          name: 'Meal $m',
          portions: 1.0 + m,
          items: [for (final f in foods) await draftOf(f, grams: 100.0 + m)],
        );
        ids.add(saved.id);
      }

      sqlLog.clear();
      final all = await repo.getSavedMeals();
      final reads = sqlLog.reads;

      // saved_meals, items, variants, servings.
      expect(reads, 4);
      expect(all.map((m) => m.meal.name), [
        'Meal 0',
        'Meal 1',
        'Meal 2',
        'Meal 3',
      ]);
      for (final meal in all) {
        final single = (await repo.getSavedMeal(meal.meal.id))!;
        expect(meal.items.map((i) => i.id), single.items.map((i) => i.id));
        expect(meal.totals?.calories, single.totals?.calories);
        expect(
          meal.consumedByItem.keys.toSet(),
          single.consumedByItem.keys.toSet(),
        );
      }
      // Meal 0: 1 portion of 100 g each => 100 + 200 + 300 kcal.
      expect(all.first.totals?.calories, 600.0);
      // Meal 3: 4 portions of 103 g each.
      expect(all.last.totals?.calories, closeTo(600 * 1.03 * 4, 0.0001));
      expect(await repo.getSavedMeals().then((v) => v.length), 4);
      expect(ids, hasLength(4));
    });

    test('getFoodWithDetails reads variants and servings once each', () async {
      final food = await makeFood(
        'Bread',
        servings: const [
          ManualServingInput(
            label: 'Slice',
            quantity: 1,
            unit: 'unit',
            gramsEquivalent: 30,
          ),
          ManualServingInput(
            label: 'Loaf',
            quantity: 1,
            unit: 'unit',
            gramsEquivalent: 600,
          ),
        ],
      );

      sqlLog.clear();
      final details = await repo.getFoodWithDetails(food.id);

      expect(sqlLog.reads, 3); // food, variants, servings
      expect(details!.servings.values.single, hasLength(2));
    });

    test('an empty saved-meal list costs one query', () async {
      sqlLog.clear();
      expect(await repo.getSavedMeals(), isEmpty);
      expect(sqlLog.reads, 1);
    });
  });
}

NutritionConversion _grams(double quantity) => NutritionConversion(
  quantity: quantity,
  unit: 'g',
  referenceAmount: 100,
  referenceUnit: 'g',
);
