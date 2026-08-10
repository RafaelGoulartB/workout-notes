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
          await _installNutritionSchema(db);
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

  /// Creates a manual food with one variant (per [amount] values) and
  /// returns the persisted [Food].
  Future<Food> createFood(
    String name, {
    double calories = 100,
    double protein = 10,
    double carbs = 10,
    double fat = 2,
  }) async {
    return repository.createManualFood(
      name: name,
      referenceAmount: 100,
      referenceUnit: 'g',
      referenceValues: NutritionValues(
        calories: calories,
        proteinG: protein,
        carbsG: carbs,
        fatG: fat,
      ),
    );
  }

  Future<FoodVariant> variantOf(Food food) async {
    final details = await repository.getFoodWithDetails(food.id);
    return details!.variants.first;
  }

  Future<void> logMeal(
    String date,
    String mealType,
    Food food, {
    double quantity = 100,
  }) async {
    await repository.addMealLogItem(
      date: date,
      mealType: mealType,
      food: food,
      variant: await variantOf(food),
      conversion: NutritionConversion(
        quantity: quantity,
        unit: 'g',
        referenceAmount: 100,
        referenceUnit: 'g',
      ),
    );
  }

  // ===================================================================
  // Saved meals
  // ===================================================================

  group('saved meals', () {
    test('save, load with live totals, update and delete', () async {
      final rice = await createFood('Arroz', calories: 130, carbs: 28);
      final chicken = await createFood(
        'Frango',
        calories: 165,
        protein: 31,
        fat: 3.6,
      );

      final saved = await repository.saveSavedMeal(
        name: 'Marmita',
        mealType: 'lunch',
        items: [
          SavedMealItemDraft(
            foodId: rice.id,
            foodVariantId: (await variantOf(rice)).id,
            foodNameSnapshot: rice.name,
            quantity: 200,
            unit: 'g',
          ),
          SavedMealItemDraft(
            foodId: chicken.id,
            foodVariantId: (await variantOf(chicken)).id,
            foodNameSnapshot: chicken.name,
            quantity: 150,
            unit: 'g',
          ),
        ],
      );

      final loaded = await repository.getSavedMeal(saved.id);
      expect(loaded, isNotNull);
      expect(loaded!.meal.name, 'Marmita');
      expect(loaded.meal.mealType, 'lunch');
      expect(loaded.items, hasLength(2));
      // 200 g rice (2 × 130 kcal, 2 × 10 g protein) + 150 g chicken
      // (1.5 × 165 kcal, 1.5 × 31 g protein)
      expect(loaded.totals!.calories, closeTo(260 + 247.5, 0.01));
      expect(loaded.totals!.proteinG, closeTo(20 + 46.5, 0.01));

      final list = await repository.getSavedMeals();
      expect(list, hasLength(1));

      await repository.deleteSavedMeal(saved.id);
      expect(await repository.getSavedMeal(saved.id), isNull);
      expect(await repository.getSavedMeals(), isEmpty);
    });

    test('totals recalculate when a cached food value changes', () async {
      final banana = await createFood('Banana', calories: 90, carbs: 22);
      final variant = await variantOf(banana);
      final saved = await repository.saveSavedMeal(
        name: 'Lanche',
        items: [
          SavedMealItemDraft(
            foodId: banana.id,
            foodVariantId: variant.id,
            foodNameSnapshot: banana.name,
            quantity: 100,
            unit: 'g',
          ),
        ],
      );

      var loaded = await repository.getSavedMeal(saved.id);
      expect(loaded!.totals!.calories, 90);

      // The banana's cached values change (fresh fetch).
      await repository.upsertFoodWithDetails(
        food: banana.copyWith(fetchedAt: DateTime.now()),
        variants: [
          variant.copyWith(
            values: const NutritionValues(
              calories: 120,
              proteinG: 4,
              carbsG: 30,
              fatG: 1,
            ),
          ),
        ],
      );

      loaded = await repository.getSavedMeal(saved.id);
      expect(loaded!.totals!.calories, 120);
      expect(loaded.totals!.proteinG, 4);
    });

    test('update replaces items wholesale', () async {
      final a = await createFood('A', calories: 50);
      final b = await createFood('B', calories: 60);
      final saved = await repository.saveSavedMeal(
        name: 'Teste',
        items: [
          SavedMealItemDraft(
            foodId: a.id,
            foodVariantId: (await variantOf(a)).id,
            foodNameSnapshot: a.name,
            quantity: 100,
            unit: 'g',
          ),
        ],
      );
      final updated = await repository.saveSavedMeal(
        id: saved.id,
        name: 'Teste novo',
        portions: 2,
        items: [
          SavedMealItemDraft(
            foodId: b.id,
            foodVariantId: (await variantOf(b)).id,
            foodNameSnapshot: b.name,
            quantity: 50,
            unit: 'g',
          ),
        ],
      );
      final loaded = await repository.getSavedMeal(updated.id);
      expect(loaded!.meal.name, 'Teste novo');
      expect(loaded.meal.portions, 2);
      expect(loaded.items, hasLength(1));
      expect(loaded.items.first.foodNameSnapshot, 'B');
      // Totals mirror the logging flow: 50 g × 2 portions × 0.6 kcal/g.
      expect(loaded.totals!.calories, 60);
    });

    test(
      'previewSavedMealTotals returns live totals for unsaved drafts',
      () async {
        final rice = await createFood(
          'Arroz',
          calories: 130,
          protein: 0,
          carbs: 28,
          fat: 0,
        );
        final chicken = await createFood(
          'Frango',
          calories: 165,
          protein: 31,
          fat: 3.6,
        );
        // Mirror the editor's in-memory drafts: no id, no
        // persisted saved_meal row.
        final totals = await repository.previewSavedMealTotals(
          portions: 1,
          items: [
            SavedMealItemDraft(
              foodId: rice.id,
              foodVariantId: (await variantOf(rice)).id,
              foodNameSnapshot: rice.name,
              quantity: 200,
              unit: 'g',
            ),
            SavedMealItemDraft(
              foodId: chicken.id,
              foodVariantId: (await variantOf(chicken)).id,
              foodNameSnapshot: chicken.name,
              quantity: 150,
              unit: 'g',
            ),
          ],
        );
        expect(totals, isNotNull);
        // 200 g rice (2 × 130 kcal, 2 × 28 g carbs) + 150 g chicken
        // (1.5 × 165 kcal, 1.5 × 31 g protein, 1.5 × 3.6 g fat, plus
        // the default 10 g carbs per 100 g of frango).
        expect(totals!.calories, closeTo(260 + 247.5, 0.01));
        expect(totals.carbsG, closeTo(56 + 15, 0.01));
        expect(totals.proteinG, closeTo(46.5, 0.01));
        expect(totals.fatG, closeTo(5.4, 0.01));
      },
    );

    test(
      'previewSavedMealTotals scales drafts by portions and returns null '
      'when no item resolves',
      () async {
        final rice = await createFood('Arroz', calories: 130);
        // Empty list -> null totals.
        expect(
          await repository.previewSavedMealTotals(
            portions: 2,
            items: const [],
          ),
          isNull,
        );
        // Items without a food/variant id contribute nothing -> null.
        final totals = await repository.previewSavedMealTotals(
          portions: 2,
          items: [
            SavedMealItemDraft(
              foodNameSnapshot: 'Invisível',
              quantity: 100,
              unit: 'g',
            ),
          ],
        );
        expect(totals, isNull);
        // Portions multiplier still applies when an item resolves.
        final scaled = await repository.previewSavedMealTotals(
          portions: 2,
          items: [
            SavedMealItemDraft(
              foodId: rice.id,
              foodVariantId: (await variantOf(rice)).id,
              foodNameSnapshot: rice.name,
              quantity: 100,
              unit: 'g',
            ),
          ],
        );
        expect(scaled!.calories, closeTo(260, 0.01));
      },
    );

    test('validates name and portions', () async {
      await expectLater(
        repository.saveSavedMeal(name: '  '),
        throwsA(isA<NutritionValidationException>()),
      );
      await expectLater(
        repository.saveSavedMeal(name: 'X', portions: 0),
        throwsA(isA<NutritionValidationException>()),
      );
    });

    test('logging scales quantities by portions', () async {
      final rice = await createFood('Arroz', calories: 130);
      final saved = await repository.saveSavedMeal(
        name: 'Marmita',
        mealType: 'lunch',
        portions: 2,
        items: [
          SavedMealItemDraft(
            foodId: rice.id,
            foodVariantId: (await variantOf(rice)).id,
            foodNameSnapshot: rice.name,
            quantity: 100,
            unit: 'g',
          ),
        ],
      );
      final result = await repository.addSavedMealToDate(
        date: '2026-08-09',
        mealType: 'lunch',
        mealName: 'Almoço',
        savedMealId: saved.id,
      );
      expect(result.added, 1);
      expect(result.skipped, 0);
      final summary = await repository.getDailySummary('2026-08-09');
      // 100 g × 2 portions = 200 g = 2 × 130 kcal
      expect(summary.consumed.calories, 260);
    });

    test('logging skips items whose food was deleted', () async {
      final a = await createFood('A', calories: 50);
      final b = await createFood('B', calories: 60);
      final saved = await repository.saveSavedMeal(
        name: 'Combo',
        items: [
          SavedMealItemDraft(
            foodId: a.id,
            foodVariantId: (await variantOf(a)).id,
            foodNameSnapshot: a.name,
            quantity: 100,
            unit: 'g',
          ),
          SavedMealItemDraft(
            foodId: b.id,
            foodVariantId: (await variantOf(b)).id,
            foodNameSnapshot: b.name,
            quantity: 100,
            unit: 'g',
          ),
        ],
      );
      await database.delete('foods', where: 'id = ?', whereArgs: [b.id]);
      final result = await repository.addSavedMealToDate(
        date: '2026-08-09',
        mealType: 'lunch',
        mealName: 'Almoço',
        savedMealId: saved.id,
      );
      expect(result.added, 1);
      expect(result.skipped, 1);
      final summary = await repository.getDailySummary('2026-08-09');
      expect(summary.consumed.calories, 50);
    });
  });

  // ===================================================================
  // Copy / repeat
  // ===================================================================

  group('copy and repeat', () {
    test('copyItemsToMeal clones with new ids and preserved snapshot',
        () async {
      final banana = await createFood('Banana', calories: 90);
      await logMeal('2026-08-08', 'breakfast', banana, quantity: 100);
      final day = await repository.getDayMeals('2026-08-08');
      final items = day.first.items;

      final copied = await repository.copyItemsToMeal(
        date: '2026-08-09',
        mealType: 'breakfast',
        items: items,
      );
      expect(copied, 1);

      final target = await repository.getDayMeals('2026-08-09');
      expect(target.single.items, hasLength(1));
      expect(target.single.items.first.id, isNot(items.first.id));
      expect(target.single.items.first.snapshotJson, items.first.snapshotJson);
      expect(target.single.items.first.calories, 90);
    });

    test('getLatestMealItems returns the most recent meal before a date',
        () async {
      final banana = await createFood('Banana', calories: 90);
      final apple = await createFood('Maçã', calories: 52);
      await logMeal('2026-08-05', 'breakfast', banana, quantity: 100);
      await logMeal('2026-08-07', 'breakfast', apple, quantity: 100);
      await logMeal('2026-08-07', 'lunch', banana, quantity: 100);

      final latest = await repository.getLatestMealItems(
        'breakfast',
        beforeDate: '2026-08-08',
      );
      expect(latest, hasLength(1));
      expect(latest.first.foodNameSnapshot, 'Maçã');

      expect(
        await repository.getLatestMealItems(
          'breakfast',
          beforeDate: '2026-08-06',
        ),
        hasLength(1),
      );
      expect(
        await repository.getLatestMealItems('breakfast'),
        hasLength(1),
      );
      expect(
        await repository.getLatestMealItems(
          'breakfast',
          beforeDate: '2026-08-04',
        ),
        isEmpty,
      );
    });

    test('copying bumps last_used_at on the referenced foods', () async {
      final banana = await createFood('Banana', calories: 90);
      await logMeal('2026-08-08', 'breakfast', banana, quantity: 100);
      final day = await repository.getDayMeals('2026-08-08');
      await repository.copyItemsToMeal(
        date: '2026-08-09',
        mealType: 'lunch',
        items: day.first.items,
      );
      final recents = await repository.getRecentFoods();
      expect(recents.single.food.id, banana.id);
    });
  });

  // ===================================================================
  // Favorites, recents and meal suggestions
  // ===================================================================

  group('favorites, recents and meal suggestions', () {
    test('favorite toggle and favorite list', () async {
      final a = await createFood('Arroz', calories: 130);
      final b = await createFood('Feijão', calories: 76);
      await repository.setFoodFavorite(a.id, true);
      await repository.setFoodFavorite(b.id, true);
      var favorites = await repository.getFavoriteFoods();
      expect(favorites.map((f) => f.food.name), ['Arroz', 'Feijão']);
      expect(favorites.first.food.isFavorite, isTrue);

      await repository.setFoodFavorite(a.id, false);
      favorites = await repository.getFavoriteFoods();
      expect(favorites.map((f) => f.food.name), ['Feijão']);
    });

    test('recent foods are ordered by last_used_at', () async {
      final a = await createFood('Arroz', calories: 130);
      final b = await createFood('Feijão', calories: 76);
      // Logging bumps last_used_at; later logs win.
      await logMeal('2026-08-01', 'lunch', a);
      await logMeal('2026-08-02', 'lunch', b);
      final recents = await repository.getRecentFoods();
      expect(recents.map((f) => f.food.name), ['Feijão', 'Arroz']);
    });

    test('meal suggestions rank by usage count per meal type', () async {
      final a = await createFood('Banana', calories: 90);
      final b = await createFood('Iogurte', calories: 60);
      final c = await createFood('Salada', calories: 40);
      for (var i = 0; i < 3; i++) {
        await logMeal('2026-08-0${i + 1}', 'breakfast', a);
        await logMeal('2026-08-0${i + 1}', 'breakfast', b);
      }
      await logMeal('2026-08-04', 'lunch', c);

      final suggestions = await repository.getMealSuggestions('breakfast');
      expect(suggestions.map((f) => f.food.name), ['Banana', 'Iogurte']);
      expect(suggestions, isNot(contains(anyElement(
        (f) => f.food.name == 'Salada',
      ))));
    });
  });

  // ===================================================================
  // History
  // ===================================================================

  group('daily history', () {
    test('aggregates per-date totals across meals', () async {
      final banana = await createFood('Banana', calories: 90, carbs: 22);
      final rice = await createFood('Arroz', calories: 130, carbs: 28);
      final today = DateTime.now();
      final date1 = DateTime(
        today.year,
        today.month,
        today.day,
      ).subtract(const Duration(days: 1)).toIso8601String().substring(0, 10);
      final date2 = DateTime(
        today.year,
        today.month,
        today.day,
      ).toIso8601String().substring(0, 10);
      await logMeal(date1, 'breakfast', banana);
      await logMeal(date1, 'lunch', rice, quantity: 200);
      await logMeal(date2, 'breakfast', banana, quantity: 50);

      final history = await repository.getDailyNutritionHistory(days: 2);
      expect(history, hasLength(2));
      expect(history.first['date'], date1);
      expect(
        (history.first['calories'] as num).toDouble(),
        closeTo(90 + 260, 0.01),
      );
      expect(history.last['date'], date2);
      expect(
        (history.last['calories'] as num).toDouble(),
        closeTo(45, 0.01),
      );
      expect(
        (history.last['protein_g'] as num).toDouble(),
        closeTo(5, 0.01),
      );
    });
  });

  // ===================================================================
  // Meal types catalog (configured in the nutrition settings)
  // ===================================================================

  group('meal types catalog', () {
    test('seeded legacy types are returned in order', () async {
      final types = await repository.getMealTypes();
      expect(
        types.map((t) => t.key),
        ['breakfast', 'lunch', 'dinner', 'snacks'],
      );
      expect(types.map((t) => t.orderIndex), [0, 1, 2, 3]);
      expect(types.every((t) => t.name == null), isTrue);
    });

    test('createMealType appends a custom type and rejects empty names',
        () async {
      final created = await repository.createMealType('Pré-treino');
      expect(created.name, 'Pré-treino');
      expect(
        created.key,
        isNot(anyOf('breakfast', 'lunch', 'dinner', 'snacks')),
      );

      final types = await repository.getMealTypes();
      expect(types, hasLength(5));
      expect(types.last.name, 'Pré-treino');
      expect(types.last.orderIndex, 4);

      await expectLater(
        repository.createMealType('   '),
        throwsA(isA<NutritionValidationException>()),
      );
    });

    test('renameMealType only affects the catalog; logs keep snapshots',
        () async {
      final banana = await createFood('Banana', calories: 90);
      // Logged BEFORE the rename: the section keeps its old snapshot.
      await repository.addMealLogItem(
        date: '2026-08-05',
        mealType: 'breakfast',
        name: 'Café da manhã',
        food: banana,
        variant: await variantOf(banana),
        conversion: NutritionConversion(
          quantity: 100,
          unit: 'g',
          referenceAmount: 100,
          referenceUnit: 'g',
        ),
      );
      final types = await repository.getMealTypes();
      final breakfast = types.firstWhere((t) => t.key == 'breakfast');
      await repository.renameMealType(breakfast.id, 'Pré-treino');

      final renamed = await repository.getMealTypes();
      expect(renamed.firstWhere((t) => t.key == 'breakfast').name, 'Pré-treino');

      // The existing log keeps the snapshot taken at log time.
      final day = await repository.getDayMeals('2026-08-05');
      expect(day.single.log.name, 'Café da manhã');

      // A new log takes the new catalog name as snapshot.
      await repository.addMealLogItem(
        date: '2026-08-06',
        mealType: 'breakfast',
        name: 'Pré-treino',
        food: banana,
        variant: await variantOf(banana),
        conversion: NutritionConversion(
          quantity: 100,
          unit: 'g',
          referenceAmount: 100,
          referenceUnit: 'g',
        ),
      );
      final nextDay = await repository.getDayMeals('2026-08-06');
      expect(nextDay.single.log.name, 'Pré-treino');
    });

    test('deleteMealType keeps the logged history visible', () async {
      final banana = await createFood('Banana', calories: 90);
      await repository.addMealLogItem(
        date: '2026-08-05',
        mealType: 'dinner',
        name: 'Jantar',
        food: banana,
        variant: await variantOf(banana),
        conversion: NutritionConversion(
          quantity: 100,
          unit: 'g',
          referenceAmount: 100,
          referenceUnit: 'g',
        ),
      );
      final types = await repository.getMealTypes();
      final dinner = types.firstWhere((t) => t.key == 'dinner');
      await repository.deleteMealType(dinner.id);

      expect(
        (await repository.getMealTypes()).any((t) => t.key == 'dinner'),
        isFalse,
      );
      // The day still exposes the section with its stored name.
      final day = await repository.getDayMeals('2026-08-05');
      expect(day.single.log.mealType, 'dinner');
      expect(day.single.log.name, 'Jantar');
      expect(day.single.items, hasLength(1));
    });

    test('reorderMealTypes writes the given order', () async {
      final types = await repository.getMealTypes();
      final reversed = types.reversed.map((t) => t.id).toList();
      await repository.reorderMealTypes(reversed);

      final reordered = await repository.getMealTypes();
      expect(
        reordered.map((t) => t.key),
        ['snacks', 'dinner', 'lunch', 'breakfast'],
      );
      expect(reordered.map((t) => t.orderIndex), [0, 1, 2, 3]);
    });

    test('addSavedMealToDate snapshots the meal name onto the section',
        () async {
      final rice = await createFood('Arroz', calories: 130);
      final saved = await repository.saveSavedMeal(
        name: 'Marmita',
        items: [
          SavedMealItemDraft(
            foodId: rice.id,
            foodVariantId: (await variantOf(rice)).id,
            foodNameSnapshot: rice.name,
            quantity: 200,
            unit: 'g',
          ),
        ],
      );
      final result = await repository.addSavedMealToDate(
        date: '2026-08-09',
        mealType: 'lunch',
        mealName: 'Almoço',
        savedMealId: saved.id,
      );
      expect(result.added, 1);
      final day = await repository.getDayMeals('2026-08-09');
      expect(day.single.log.name, 'Almoço');
      expect(day.single.log.mealType, 'lunch');
      expect(day.single.items, hasLength(1));
      expect(day.single.items.first.calories, 260);
    });

    test('copyItemsToMeal carries the name into a new day', () async {
      final banana = await createFood('Banana', calories: 90);
      await logMeal('2026-08-08', 'breakfast', banana, quantity: 100);
      final source = await repository.getDayMeals('2026-08-08');
      expect(source.single.items, hasLength(1));

      await repository.copyItemsToMeal(
        date: '2026-08-09',
        mealType: source.single.log.mealType,
        name: 'Café da manhã',
        items: source.single.items,
      );

      final target = await repository.getDayMeals('2026-08-09');
      expect(target.single.log.name, 'Café da manhã');
      expect(target.single.items, hasLength(1));
    });

    test('copying into a day with an existing section keeps its name',
        () async {
      final banana = await createFood('Banana', calories: 90);
      await logMeal('2026-08-08', 'lunch', banana);
      final source = await repository.getDayMeals('2026-08-08');

      await repository.ensureMealLog(
        date: '2026-08-09',
        mealType: source.single.log.mealType,
        name: 'Jantar',
      );
      await repository.copyItemsToMeal(
        date: '2026-08-09',
        mealType: source.single.log.mealType,
        name: 'Outro nome',
        items: source.single.items,
      );

      final target = await repository.getDayMeals('2026-08-09');
      expect(target.single.log.name, 'Jantar');
      expect(target.single.items, hasLength(1));
    });

    test('getLatestMealName returns the previous custom name', () async {
      await repository.ensureMealLog(
        date: '2026-08-05',
        mealType: 'lunch',
        name: 'Almoço',
      );
      expect(
        await repository.getLatestMealName(
          'lunch',
          beforeDate: '2026-08-08',
        ),
        'Almoço',
      );
      expect(
        await repository.getLatestMealName(
          'lunch',
          beforeDate: '2026-08-04',
        ),
        isNull,
      );
    });
  });
}

/// Production-like nutrition schema used by these tests.
Future<void> _installNutritionSchema(Database db) async {
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
    CREATE TABLE meal_types (
      id TEXT PRIMARY KEY,
      key TEXT UNIQUE NOT NULL,
      name TEXT,
      order_index INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL
    )
  ''');
  final now = DateTime.now().toIso8601String();
  for (var i = 0; i < 4; i++) {
    await db.insert('meal_types', {
      'id': ['breakfast', 'lunch', 'dinner', 'snacks'][i],
      'key': ['breakfast', 'lunch', 'dinner', 'snacks'][i],
      'name': null,
      'order_index': i,
      'created_at': now,
    });
  }
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
      order_index INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (saved_meal_id) REFERENCES saved_meals(id) ON DELETE CASCADE,
      FOREIGN KEY (food_id) REFERENCES foods(id) ON DELETE SET NULL,
      FOREIGN KEY (food_variant_id) REFERENCES food_variants(id) ON DELETE SET NULL
    )
  ''');
}
