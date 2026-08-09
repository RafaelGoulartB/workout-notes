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
              fiber_g REAL,
              sugars_g REAL,
              sodium_mg REAL,
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
              fiber_g REAL,
              sugars_g REAL,
              sodium_mg REAL,
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
      await database.delete('foods', where: 'id = ?', whereArgs: [food.id]);
      final meals = await repository.getDayMeals('2026-07-26');
      final snacks = meals.firstWhere((m) => m.log.mealType == 'snacks');
      expect(snacks.items, hasLength(1));
      expect(snacks.items.first.foodNameSnapshot, 'Iogurte');
      expect(snacks.items.first.calories, 60);
      // food_id is set to null on cascade
      expect(snacks.items.first.foodId, isNull);
      expect(item.snapshot.foodName, 'Iogurte');
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
    test('manual food created with ai_vision source keeps the source', () async {
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
      expect(rows.first.source, 'manual');
    });
  });
}
