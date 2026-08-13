import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/models/nutrition/food.dart';
import 'package:workout_notes/models/nutrition/food_variant.dart';
import 'package:workout_notes/models/nutrition/nutrition_values.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/utils/nutrition_conversion.dart';

void main() {
  late Database database;
  late NutritionRepository repository;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    database = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE foods (
              id TEXT PRIMARY KEY,
              source TEXT NOT NULL,
              external_id TEXT NOT NULL,
              name TEXT NOT NULL,
              search_name TEXT NOT NULL,
              brand TEXT,
              barcode TEXT,
              source_url TEXT,
              fetched_at TEXT NOT NULL,
              last_used_at TEXT,
              is_favorite INTEGER NOT NULL DEFAULT 0,
              UNIQUE(source, external_id)
            )
          ''');
          await db.execute('''
            CREATE TABLE food_variants (
              id TEXT PRIMARY KEY,
              food_id TEXT NOT NULL,
              label TEXT,
              reference_amount REAL NOT NULL,
              reference_unit TEXT NOT NULL,
              calories REAL,
              protein_g REAL,
              carbs_g REAL,
              fat_g REAL,
              saturated_fat_g REAL, monounsaturated_fat_g REAL,
              polyunsaturated_fat_g REAL, trans_fat_g REAL,
              fiber_g REAL,
              sugars_g REAL,
              sodium_mg REAL,
              potassium_mg REAL, calcium_mg REAL, iron_mg REAL, magnesium_mg REAL,
              zinc_mg REAL, vitamin_a_ug REAL, vitamin_c_mg REAL,
              vitamin_d_ug REAL, vitamin_b12_ug REAL,
              extra_nutrients_json TEXT,
              is_estimated INTEGER NOT NULL DEFAULT 0,
              FOREIGN KEY (food_id) REFERENCES foods(id) ON DELETE CASCADE
            )
          ''');
          await db.execute('''
            CREATE TABLE food_servings (
              id TEXT PRIMARY KEY,
              food_variant_id TEXT NOT NULL,
              label TEXT NOT NULL,
              quantity REAL NOT NULL DEFAULT 1,
              unit TEXT NOT NULL,
              grams_equivalent REAL,
              ml_equivalent REAL,
              FOREIGN KEY (food_variant_id) REFERENCES food_variants(id) ON DELETE CASCADE
            )
          ''');
          await db.execute('''
            CREATE TABLE meal_logs (
              id TEXT PRIMARY KEY,
              date TEXT NOT NULL,
              meal_type TEXT NOT NULL,
              name TEXT,
              notes TEXT,
              created_at TEXT NOT NULL,
              UNIQUE(date, meal_type)
            )
          ''');
          await db.execute('''
            CREATE TABLE meal_log_items (
              id TEXT PRIMARY KEY,
              meal_log_id TEXT NOT NULL,
              food_id TEXT,
              food_variant_id TEXT,
              food_name_snapshot TEXT NOT NULL,
              brand_snapshot TEXT,
              quantity REAL NOT NULL,
              unit TEXT NOT NULL,
              calories REAL,
              protein_g REAL,
              carbs_g REAL,
              fat_g REAL,
              saturated_fat_g REAL, monounsaturated_fat_g REAL,
              polyunsaturated_fat_g REAL, trans_fat_g REAL,
              fiber_g REAL,
              sugars_g REAL,
              sodium_mg REAL,
              potassium_mg REAL, calcium_mg REAL, iron_mg REAL, magnesium_mg REAL,
              zinc_mg REAL, vitamin_a_ug REAL, vitamin_c_mg REAL,
              vitamin_d_ug REAL, vitamin_b12_ug REAL,
              nutrition_snapshot_json TEXT NOT NULL,
              created_at TEXT NOT NULL,
              FOREIGN KEY (meal_log_id) REFERENCES meal_logs(id) ON DELETE CASCADE,
              FOREIGN KEY (food_id) REFERENCES foods(id) ON DELETE SET NULL,
              FOREIGN KEY (food_variant_id) REFERENCES food_variants(id) ON DELETE SET NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE nutrition_goals (
              id TEXT PRIMARY KEY,
              calories REAL,
              protein_g REAL,
              carbs_g REAL,
              fat_g REAL,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              is_active INTEGER NOT NULL DEFAULT 1
            )
          ''');
          await db.execute('''
            CREATE TABLE saved_meals (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              meal_type TEXT,
              portions REAL NOT NULL DEFAULT 1,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE saved_meal_items (
              id TEXT PRIMARY KEY,
              saved_meal_id TEXT NOT NULL,
              food_id TEXT,
              food_variant_id TEXT,
              food_name_snapshot TEXT NOT NULL,
              brand_snapshot TEXT,
              quantity REAL NOT NULL,
              unit TEXT NOT NULL,
              serving_label TEXT,
              serving_grams_equivalent REAL,
              serving_ml_equivalent REAL,
              order_index INTEGER NOT NULL DEFAULT 0,
              FOREIGN KEY (saved_meal_id) REFERENCES saved_meals(id) ON DELETE CASCADE,
              FOREIGN KEY (food_id) REFERENCES foods(id) ON DELETE SET NULL,
              FOREIGN KEY (food_variant_id) REFERENCES food_variants(id) ON DELETE SET NULL
            )
          ''');
        },
      ),
    );
    DatabaseHelper.overrideDatabase = database;
    repository = NutritionRepository();
  });

  tearDown(() async {
    DatabaseHelper.overrideDatabase = null;
    await database.close();
  });

  group('local search', () {
    setUp(() async {
      final now = DateTime.now().toIso8601String();
      await database.insert('foods', {
        'id': 'f1',
        'source': 'manual',
        'external_id': 'f1',
        'name': 'Pão integral',
        'search_name': Food.normalizeForSearch('Pão integral'),
        'brand': 'Sadia',
        'fetched_at': now,
      });
      await database.insert('food_variants', {
        'id': 'v1',
        'food_id': 'f1',
        'reference_amount': 100,
        'reference_unit': 'g',
        'calories': 250,
        'protein_g': 9,
        'carbs_g': 45,
        'fat_g': 4,
        'is_estimated': 0,
      });
      await database.insert('foods', {
        'id': 'f2',
        'source': 'manual',
        'external_id': 'f2',
        'name': 'Banana prata',
        'search_name': Food.normalizeForSearch('Banana prata'),
        'fetched_at': now,
      });
    });

    test('matches ignoring case and accents', () async {
      final results = await repository.searchLocalFoods('pão');
      expect(results, hasLength(1));
      expect(results.first.food.name, 'Pão integral');
    });

    test('matches by brand token', () async {
      final results = await repository.searchLocalFoods('Sadia');
      expect(results, hasLength(1));
      expect(results.first.food.name, 'Pão integral');
    });

    test('single-word queries never match every branded food', () async {
      // 'zzz' matches no food name and no brand. With the old empty
      // brand token the predicate degraded into `LIKE '%%'`, which
      // matched every food with a brand.
      final results = await repository.searchLocalFoods('zzz');
      expect(results, isEmpty);
    });
  });

  group('food upserts and meals', () {
    test('manual food registers and is retrievable with details', () async {
      final food = await repository.createManualFood(
        name: 'Maçã',
        referenceAmount: 100,
        referenceUnit: 'g',
        referenceValues: const NutritionValues(
          calories: 52,
          proteinG: 0.3,
          carbsG: 14,
          fatG: 0.2,
        ),
      );
      final details = await repository.getFoodWithDetails(food.id);
      expect(details, isNotNull);
      expect(details!.variants, hasLength(1));
      expect(details.variants.first.values.calories, 52);
    });

    test(
      'user-created food can be edited while preserving its variant link',
      () async {
        final food = await repository.createManualFood(
          name: 'Iogurte natural',
          brand: 'Minha marca',
          referenceAmount: 100,
          referenceUnit: 'g',
          referenceValues: const NutritionValues(calories: 60, proteinG: 5),
          servings: const [
            ManualServingInput(
              label: 'Pote',
              quantity: 1,
              unit: 'unidade',
              gramsEquivalent: 170,
            ),
          ],
        );
        final before = await repository.getFoodWithDetails(food.id);
        final variantId = before!.variants.first.id;

        final updated = await repository.updateManualFood(
          foodId: food.id,
          name: 'Iogurte grego',
          brand: 'Nova marca',
          referenceAmount: 100,
          referenceUnit: 'g',
          referenceValues: const NutritionValues(calories: 90, proteinG: 8),
          servings: const [
            ManualServingInput(
              label: 'Pote grande',
              quantity: 1,
              unit: 'unidade',
              gramsEquivalent: 200,
            ),
          ],
        );
        final after = await repository.getFoodWithDetails(updated.id);

        expect(updated.id, food.id);
        expect(updated.name, 'Iogurte grego');
        expect(updated.searchName, 'iogurte grego');
        expect(after!.variants.first.id, variantId);
        expect(after.variants.first.values.calories, 90);
        expect(after.servings[variantId]!.single.label, 'Pote grande');
      },
    );

    test('upserting the same gateway food is idempotent', () async {
      final now = DateTime.now();
      final first = await repository.upsertFoodWithDetails(
        food: Food(
          id: 'remote-1',
          source: 'gateway',
          externalId: 'gw-1',
          name: 'Greek Yogurt',
          searchName: Food.normalizeForSearch('Greek Yogurt'),
          fetchedAt: now,
        ),
        variants: const [
          FoodVariant(
            id: 'v_remote',
            foodId: 'remote-1',
            referenceAmount: 100,
            referenceUnit: 'g',
            values: NutritionValues(calories: 60, proteinG: 10),
          ),
        ],
      );
      final second = await repository.upsertFoodWithDetails(
        food: Food(
          id: 'remote-1',
          source: 'gateway',
          externalId: 'gw-1',
          name: 'Greek Yogurt',
          searchName: Food.normalizeForSearch('Greek Yogurt'),
          fetchedAt: now,
        ),
        variants: const [
          FoodVariant(
            id: 'v_remote',
            foodId: 'remote-1',
            referenceAmount: 100,
            referenceUnit: 'g',
            values: NutritionValues(calories: 70, proteinG: 11),
          ),
        ],
      );
      expect(second.id, first.id);
      final details = await repository.getFoodWithDetails(second.id);
      expect(details!.variants.first.values.calories, 70);
    });

    test('ensures a meal log lazily and adds an item with snapshot', () async {
      final food = await repository.createManualFood(
        name: 'Aveia',
        referenceAmount: 100,
        referenceUnit: 'g',
        referenceValues: const NutritionValues(
          calories: 389,
          proteinG: 16.9,
          carbsG: 66.3,
          fatG: 6.9,
        ),
      );
      final details = await repository.getFoodWithDetails(food.id);
      final variant = details!.variants.first;
      final item = await repository.addMealLogItem(
        date: '2026-07-26',
        mealType: 'breakfast',
        food: food,
        variant: variant,
        conversion: NutritionConversion(
          quantity: 30,
          unit: 'g',
          referenceAmount: 100,
          referenceUnit: 'g',
        ),
      );
      expect(item.calories, closeTo(389 * 0.3, 0.001));
      expect(item.snapshot.consumed.proteinG, closeTo(16.9 * 0.3, 0.001));
      final meals = await repository.getDayMeals('2026-07-26');
      expect(meals, hasLength(1));
      expect(meals.first.log.mealType, 'breakfast');
      expect(meals.first.items, hasLength(1));
    });

    test('scales, snapshots and aggregates micronutrients by day', () async {
      final food = await repository.createManualFood(
        name: 'Espinafre',
        referenceAmount: 100,
        referenceUnit: 'g',
        referenceValues: const NutritionValues(
          calories: 23,
          fatG: 4,
          saturatedFatG: 1,
          monounsaturatedFatG: 1.5,
          polyunsaturatedFatG: 1.2,
          transFatG: 0.1,
          potassiumMg: 558,
          calciumMg: 99,
          ironMg: 2.7,
          magnesiumMg: 79,
          zincMg: 0.53,
          vitaminAUg: 469,
          vitaminCMg: 28.1,
          vitaminDUg: 0,
          vitaminB12Ug: 0,
        ),
      );
      final variant = (await repository.getFoodWithDetails(
        food.id,
      ))!.variants.first;
      final item = await repository.addMealLogItem(
        date: '2026-07-27',
        mealType: 'lunch',
        food: food,
        variant: variant,
        conversion: NutritionConversion(
          quantity: 50,
          unit: 'g',
          referenceAmount: 100,
          referenceUnit: 'g',
        ),
      );

      expect(item.potassiumMg, closeTo(279, 0.001));
      expect(item.saturatedFatG, closeTo(0.5, 0.001));
      expect(item.snapshot.consumed.monounsaturatedFatG, closeTo(0.75, 0.001));
      expect(item.snapshot.consumed.vitaminAUg, closeTo(234.5, 0.001));
      final summary = await repository.getDailySummary('2026-07-27');
      expect(summary.consumed.calciumMg, closeTo(49.5, 0.001));
      expect(summary.consumed.ironMg, closeTo(1.35, 0.001));
      expect(summary.consumed.vitaminCMg, closeTo(14.05, 0.001));
      expect(summary.consumed.vitaminB12Ug, 0);
      expect(summary.consumed.polyunsaturatedFatG, closeTo(0.6, 0.001));
      expect(summary.consumed.transFatG, closeTo(0.05, 0.001));
    });

    test('editing an item recomputes the snapshot', () async {
      final food = await repository.createManualFood(
        name: 'Arroz',
        referenceAmount: 100,
        referenceUnit: 'g',
        referenceValues: const NutritionValues(calories: 130, proteinG: 2.7),
      );
      final details = await repository.getFoodWithDetails(food.id);
      final variant = details!.variants.first;
      final item = await repository.addMealLogItem(
        date: '2026-07-26',
        mealType: 'lunch',
        food: food,
        variant: variant,
        conversion: NutritionConversion(
          quantity: 100,
          unit: 'g',
          referenceAmount: 100,
          referenceUnit: 'g',
        ),
      );
      final updated = await repository.updateMealLogItem(
        itemId: item.id,
        conversion: NutritionConversion(
          quantity: 200,
          unit: 'g',
          referenceAmount: 100,
          referenceUnit: 'g',
        ),
        variant: variant,
      );
      expect(updated.calories, 260);
      expect(updated.snapshot.consumed.calories, 260);
    });

    test('deleting a cached food keeps past meals intact', () async {
      final food = await repository.createManualFood(
        name: 'Iogurte',
        referenceAmount: 100,
        referenceUnit: 'g',
        referenceValues: const NutritionValues(calories: 60, proteinG: 5),
      );
      final details = await repository.getFoodWithDetails(food.id);
      final variant = details!.variants.first;
      final item = await repository.addMealLogItem(
        date: '2026-07-26',
        mealType: 'snacks',
        food: food,
        variant: variant,
        conversion: NutritionConversion(
          quantity: 100,
          unit: 'g',
          referenceAmount: 100,
          referenceUnit: 'g',
        ),
      );
      await repository.deleteManualFood(food.id);
      final meals = await repository.getDayMeals('2026-07-26');
      final snacks = meals.firstWhere((m) => m.log.mealType == 'snacks');
      expect(snacks.items, hasLength(1));
      expect(snacks.items.first.foodNameSnapshot, 'Iogurte');
      expect(snacks.items.first.calories, 60);
      // food_id is set to null on cascade
      expect(snacks.items.first.foodId, isNull);
      expect(item.snapshot.foodName, 'Iogurte');
    });

    test(
      'refreshing the cache keeps the history links of past meals',
      () async {
        final now = DateTime.now();
        Future<Food> upsertYogurt(int calories) =>
            repository.upsertFoodWithDetails(
              food: Food(
                id: 'remote-1',
                source: 'gateway',
                externalId: 'gw-1',
                name: 'Greek Yogurt',
                searchName: Food.normalizeForSearch('Greek Yogurt'),
                fetchedAt: now,
              ),
              variants: [
                FoodVariant(
                  id: 'v_remote',
                  foodId: 'remote-1',
                  referenceAmount: 100,
                  referenceUnit: 'g',
                  values: NutritionValues(
                    calories: calories.toDouble(),
                    proteinG: 10,
                  ),
                ),
              ],
            );

        final first = await upsertYogurt(60);
        final details = await repository.getFoodWithDetails(first.id);
        final variant = details!.variants.first;
        final item = await repository.addMealLogItem(
          date: '2026-07-26',
          mealType: 'breakfast',
          food: details.food,
          variant: variant,
          conversion: NutritionConversion(
            quantity: 100,
            unit: 'g',
            referenceAmount: 100,
            referenceUnit: 'g',
          ),
        );
        // Re-fetch of the same gateway product: previously this used
        // REPLACE + delete/recreate, nulling food_id and
        // food_variant_id of the logged item (ON DELETE SET NULL) and
        // silently breaking the "edit item" flow.
        await upsertYogurt(70);
        final meals = await repository.getDayMeals('2026-07-26');
        final after = meals.first.items.first;
        expect(after.foodId, item.foodId);
        expect(after.foodVariantId, item.foodVariantId);
        // The item is still editable through its linked food/variant.
        final reloaded = await repository.getFoodWithDetails(after.foodId!);
        expect(reloaded, isNotNull);
        expect(reloaded!.variants.first.values.calories, 70);
      },
    );

    test('restoreMealLogItem puts a deleted item back (undo)', () async {
      final food = await repository.createManualFood(
        name: 'Castanhas',
        referenceAmount: 100,
        referenceUnit: 'g',
        referenceValues: const NutritionValues(calories: 600, proteinG: 15),
      );
      final details = await repository.getFoodWithDetails(food.id);
      final variant = details!.variants.first;
      final item = await repository.addMealLogItem(
        date: '2026-07-26',
        mealType: 'snacks',
        food: food,
        variant: variant,
        conversion: NutritionConversion(
          quantity: 30,
          unit: 'g',
          referenceAmount: 100,
          referenceUnit: 'g',
        ),
      );
      await repository.deleteMealLogItem(item.id);
      var meals = await repository.getDayMeals('2026-07-26');
      expect(meals.first.items, isEmpty);
      await repository.restoreMealLogItem(item);
      meals = await repository.getDayMeals('2026-07-26');
      expect(meals.first.items, hasLength(1));
      final restored = meals.first.items.first;
      expect(restored.id, item.id);
      expect(restored.foodNameSnapshot, 'Castanhas');
      expect(restored.calories, closeTo(600 * 0.3, 0.001));
      expect(restored.snapshot.quantity, 30);
    });

    test('aggregates the daily summary with incomplete flag', () async {
      final food = await repository.createManualFood(
        name: 'Queijo',
        referenceAmount: 100,
        referenceUnit: 'g',
        referenceValues: const NutritionValues(
          calories: 350,
          proteinG: 21,
          carbsG: 1,
          fatG: 28,
        ),
      );
      final details = await repository.getFoodWithDetails(food.id);
      final variant = details!.variants.first;
      // Item with incomplete macros (variant lacks fiber)
      await repository.addMealLogItem(
        date: '2026-07-26',
        mealType: 'dinner',
        food: food,
        variant: variant,
        conversion: NutritionConversion(
          quantity: 50,
          unit: 'g',
          referenceAmount: 100,
          referenceUnit: 'g',
        ),
      );
      final summary = await repository.getDailySummary('2026-07-26');
      expect(summary.consumed.calories, 175);
      expect(summary.hasIncompleteData, isTrue);
    });
  });

  group('transactions', () {
    test('rejects a variant id already owned by another food', () async {
      final now = DateTime.now();
      Future<void> upsert({
        required String foodId,
        required String externalId,
      }) async {
        await repository.upsertFoodWithDetails(
          food: Food(
            id: foodId,
            source: 'gateway',
            externalId: externalId,
            name: externalId,
            searchName: externalId,
            fetchedAt: now,
          ),
          variants: [
            FoodVariant(
              id: 'shared-variant',
              foodId: foodId,
              referenceAmount: 100,
              referenceUnit: 'g',
              values: const NutritionValues(calories: 100),
            ),
          ],
        );
      }

      await upsert(foodId: 'food-a', externalId: 'a');
      await expectLater(
        upsert(foodId: 'food-b', externalId: 'b'),
        throwsA(
          isA<NutritionValidationException>().having(
            (error) => error.code,
            'code',
            'variant_id_conflict',
          ),
        ),
      );
      expect(
        await repository.getFoodBySource(source: 'gateway', externalId: 'b'),
        isNull,
      );
    });

    test('upsertFoodWithDetails rolls back on failure', () async {
      // Insert a parent food with a controlled id, then attempt an
      // upsert that references an invalid foreign key for the variant.
      // The repository should not leave the foods row in a partial
      // state.
      try {
        await database.transaction((txn) async {
          await txn.insert('foods', {
            'id': 'a',
            'source': 'gateway',
            'external_id': 'a',
            'name': 'A',
            'search_name': 'a',
            'fetched_at': DateTime.now().toIso8601String(),
          });
          // Force a failure
          throw Exception('boom');
        });
      } catch (_) {}
      final rows = await database.query(
        'foods',
        where: 'id = ?',
        whereArgs: ['a'],
      );
      expect(rows, isEmpty);
    });
  });

  group('goals', () {
    test('only one active goal is kept at a time', () async {
      await repository.saveGoal(calories: 2000, proteinG: 100);
      await repository.saveGoal(calories: 2500, proteinG: 130);
      final active = await repository.getActiveGoal();
      expect(active, isNotNull);
      expect(active!.calories, 2500);
      final rows = await database.query('nutrition_goals');
      expect(rows.where((r) => r['is_active'] == 1), hasLength(1));
    });

    test('clearing the goal keeps history but deactivates it', () async {
      await repository.saveGoal(calories: 2200);
      await repository.clearActiveGoal();
      final active = await repository.getActiveGoal();
      expect(active, isNull);
      final rows = await database.query('nutrition_goals');
      expect(rows, hasLength(1));
      expect(rows.first['is_active'], 0);
    });
  });

  group('barcode lookup', () {
    setUp(() async {
      final now = DateTime.now().toIso8601String();
      await database.insert('foods', {
        'id': 'bc1',
        'source': FoodSource.openFoodFacts,
        'external_id': '7891234567890',
        'name': 'Arroz integral',
        'search_name': Food.normalizeForSearch('Arroz integral'),
        'barcode': '7891234567890',
        'fetched_at': now,
      });
      await database.insert('food_variants', {
        'id': 'bcv1',
        'food_id': 'bc1',
        'reference_amount': 100,
        'reference_unit': 'g',
        'calories': 350,
        'protein_g': 7,
        'carbs_g': 77,
        'fat_g': 2,
        'is_estimated': 0,
      });
    });

    test('returns null when the barcode is unknown', () async {
      final found = await repository.getFoodByBarcode('0000000000000');
      expect(found, isNull);
    });

    test('returns the food with details for a known barcode', () async {
      final found = await repository.getFoodByBarcode('7891234567890');
      expect(found, isNotNull);
      expect(found!.food.name, 'Arroz integral');
      expect(found.food.source, FoodSource.openFoodFacts);
      expect(found.variants, hasLength(1));
      expect(found.variants.first.values.calories, 350);
    });
  });

  group('AI vision source', () {
    test(
      'manual food created with ai_vision source keeps the source',
      () async {
        final food = await repository.createManualFood(
          name: 'Iogurte natural',
          barcode: '7896000000000',
          source: FoodSource.aiVision,
          referenceAmount: 100,
          referenceUnit: 'g',
          referenceValues: const NutritionValues(
            calories: 64,
            proteinG: 5.5,
            carbsG: 7,
            fatG: 3.5,
          ),
          isEstimated: true,
        );
        expect(food.isManual, isFalse);
        final details = await repository.getFoodWithDetails(food.id);
        expect(details!.food.source, FoodSource.aiVision);
        expect(details.variants.first.isEstimated, isTrue);
        expect(details.food.barcode, '7896000000000');
      },
    );

    test('AI Coach food remains user-editable and deletable', () async {
      final food = await repository.createManualFood(
        name: 'Banana prata',
        source: FoodSource.aiCoach,
        referenceAmount: 100,
        referenceUnit: 'g',
        referenceValues: const NutritionValues(
          calories: 98,
          proteinG: 1.3,
          carbsG: 26,
          fatG: 0.1,
        ),
        isEstimated: true,
      );

      expect(food.isUserCreated, isTrue);
      await repository.deleteManualFood(food.id);
      expect(await repository.getFoodWithDetails(food.id), isNull);
    });
  });

  group('calorie balance', () {
    test('counts the calorie goal only on days with logged food', () async {
      final food = await repository.createManualFood(
        name: 'Refeição do dia',
        referenceAmount: 100,
        referenceUnit: 'g',
        referenceValues: const NutritionValues(calories: 1500),
      );
      final details = await repository.getFoodWithDetails(food.id);
      final variant = details!.variants.first;
      final today = DateTime.now().toIso8601String().substring(0, 10);
      await repository.addMealLogItem(
        date: today,
        mealType: 'lunch',
        food: food,
        variant: variant,
        conversion: const NutritionConversion(
          quantity: 100,
          unit: 'g',
          referenceAmount: 100,
          referenceUnit: 'g',
        ),
      );

      for (final days in [7, 30]) {
        final balance = await repository.getCalorieBalance(
          days: days,
          goal: 2000,
        );
        expect(balance.daysLogged, 1);
        expect(balance.totalConsumed, 1500);
        expect(balance.totalGoal, 2000);
        expect(balance.balance, -500);
      }
    });

    test('calendar range queries exclude records outside the period', () async {
      final food = await repository.createManualFood(
        name: 'Range food',
        referenceAmount: 100,
        referenceUnit: 'g',
        referenceValues: const NutritionValues(calories: 500, fiberG: 5),
      );
      final details = await repository.getFoodWithDetails(food.id);
      final variant = details!.variants.first;
      const conversion = NutritionConversion(
        quantity: 100,
        unit: 'g',
        referenceAmount: 100,
        referenceUnit: 'g',
      );
      for (final date in ['2026-07-31', '2026-08-02', '2026-08-09']) {
        await repository.addMealLogItem(
          date: date,
          mealType: 'lunch',
          food: food,
          variant: variant,
          conversion: conversion,
        );
      }

      final start = DateTime(2026, 8, 2);
      final end = DateTime(2026, 8, 8);
      final dailies = await repository.getDailyCalorieTotalsForRange(
        startDate: start,
        endDate: end,
      );
      final balance = await repository.getCalorieBalanceForRange(
        startDate: start,
        endDate: end,
        goal: 1000,
      );
      final history = await repository.getDailyNutritionHistoryForRange(
        startDate: start,
        endDate: end,
      );
      final contributors = await repository.getTopCalorieContributorsForRange(
        startDate: start,
        endDate: end,
      );

      expect(dailies, hasLength(7));
      expect(dailies.where((day) => day.calories != null), hasLength(1));
      expect(balance.days, 7);
      expect(balance.daysLogged, 1);
      expect(balance.totalConsumed, 500);
      expect(history, hasLength(1));
      expect(history.single['date'], '2026-08-02');
      expect(contributors.single.totalCalories, 500);
    });
  });

  group('CSV export', () {
    test('returns a row per meal_log_item with the food source', () async {
      final food = await repository.createManualFood(
        name: 'Banana',
        referenceAmount: 100,
        referenceUnit: 'g',
        referenceValues: const NutritionValues(
          calories: 89,
          proteinG: 1.1,
          carbsG: 22.8,
          fatG: 0.3,
          saturatedFatG: 0.1,
          monounsaturatedFatG: 0.05,
          polyunsaturatedFatG: 0.12,
          transFatG: 0,
        ),
      );
      final details = await repository.getFoodWithDetails(food.id);
      final variant = details!.variants.first;
      await repository.addMealLogItem(
        date: '2026-07-26',
        mealType: 'snacks',
        food: food,
        variant: variant,
        conversion: NutritionConversion(
          quantity: 120,
          unit: 'g',
          referenceAmount: 100,
          referenceUnit: 'g',
        ),
      );
      final rows = await repository.exportRows(
        startDate: DateTime(2026, 7, 26),
        endDate: DateTime(2026, 7, 26),
      );
      expect(rows, hasLength(1));
      expect(rows.first.food, 'Banana');
      expect(rows.first.calories, closeTo(89 * 1.2, 0.001));
      expect(rows.first.saturatedFatG, closeTo(0.12, 0.001));
      expect(rows.first.monounsaturatedFatG, closeTo(0.06, 0.001));
      expect(rows.first.polyunsaturatedFatG, closeTo(0.144, 0.001));
      expect(rows.first.transFatG, 0);
      expect(rows.first.source, 'manual');
    });
  });
}
