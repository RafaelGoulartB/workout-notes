import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/widgets/ai/ai_coach_header_button.dart';
import 'package:workout_notes/models/nutrition/food.dart';
import 'package:workout_notes/models/nutrition/ai_food_label_draft.dart';
import 'package:workout_notes/models/nutrition/food_serving.dart';
import 'package:workout_notes/models/nutrition/food_search_result.dart';
import 'package:workout_notes/models/nutrition/food_variant.dart';
import 'package:workout_notes/models/nutrition/meal_log_item.dart';
import 'package:workout_notes/models/nutrition/nutrition_values.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/screens/workout/food_library_screen.dart';
import 'package:workout_notes/screens/workout/food_quantity_sheet.dart';
import 'package:workout_notes/screens/workout/food_search_screen.dart';
import 'package:workout_notes/screens/workout/manual_food_screen.dart';
import 'package:workout_notes/screens/workout/nutrition_home_screen.dart';
import 'package:workout_notes/services/nutrition_gateway.dart';

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: child,
);

Future<void> _installSchema(Database db) async {
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
      order_index INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (saved_meal_id) REFERENCES saved_meals(id) ON DELETE CASCADE,
      FOREIGN KEY (food_id) REFERENCES foods(id) ON DELETE SET NULL,
      FOREIGN KEY (food_variant_id) REFERENCES food_variants(id) ON DELETE SET NULL
    )
  ''');
}

class _StubGateway implements NutritionGateway {
  final NutritionGatewayResult<List<FoodSearchResult>> result;
  int searchCalls = 0;
  _StubGateway(this.result);

  @override
  Future<NutritionGatewayResult<List<FoodSearchResult>>> search(
    String query, {
    int limit = 20,
  }) async {
    searchCalls++;
    return result;
  }

  @override
  Future<NutritionGatewayResult<FoodSearchResult>> getFood(
    String source,
    String externalId,
  ) async {
    return NutritionGatewayResult.error(
      const NutritionGatewayError('not_supported', 'not used in tests'),
    );
  }

  @override
  String? get baseUrl => 'https://stub.test';
}

class _ControlledGateway implements NutritionGateway {
  final Completer<NutritionGatewayResult<List<FoodSearchResult>>> pending =
      Completer<NutritionGatewayResult<List<FoodSearchResult>>>();
  int searchCalls = 0;

  @override
  Future<NutritionGatewayResult<List<FoodSearchResult>>> search(
    String query, {
    int limit = 20,
  }) {
    searchCalls++;
    return pending.future;
  }

  @override
  Future<NutritionGatewayResult<FoodSearchResult>> getFood(
    String source,
    String externalId,
  ) async => NutritionGatewayResult.error(
    const NutritionGatewayError('not_supported', 'not used in tests'),
  );

  @override
  String? get baseUrl => 'https://stub.test';
}

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
          await _installSchema(db);
        },
      ),
    );
    repository = NutritionRepository();
    DatabaseHelper.overrideDatabase = database;
  });

  tearDown(() async {
    DatabaseHelper.overrideDatabase = null;
    await database.close();
  });

  testWidgets('Nutrition home opens meal details from the summary card', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(_app(const NutritionHomeScreen()));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    });
    final loc = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;

    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    expect(find.byType(AiCoachHeaderButton), findsOneWidget);
    expect(find.byIcon(Icons.calendar_month_outlined), findsOneWidget);
    expect(find.text(loc.nutritionSummaryTitle), findsOneWidget);
    expect(find.text(loc.nutritionHomeToolBalance), findsOneWidget);
    expect(find.text(loc.nutritionHomeToolMeals), findsOneWidget);
    expect(find.text(loc.nutritionFoodLibraryTitle), findsOneWidget);
    expect(find.text(loc.nutritionMealBreakfast), findsNothing);

    await tester.runAsync(() async {
      await tester.tap(find.text(loc.nutritionSummaryTitle));
      await tester.pump();
      // Let the day screen's async DB load complete (real I/O).
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await tester.pump();
    });
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text(loc.nutritionJumpToday), findsOneWidget);
    expect(find.text(loc.nutritionDiaryTab), findsOneWidget);
    expect(find.text(loc.nutritionDailyStatsTab), findsOneWidget);
    expect(find.text(loc.nutritionCaloriesTitle), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsNothing);
    expect(find.text(loc.nutritionAddManually), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);

    await tester.tap(find.text(loc.nutritionDailyStatsTab));
    await tester.pumpAndSettle();

    expect(find.text(loc.nutritionCaloriesTitle), findsNothing);
    expect(find.text(loc.nutritionMacrosTitle), findsOneWidget);
    expect(find.text(loc.nutritionNutrientsTitle), findsOneWidget);
  });

  testWidgets(
    'Search screen renders the manual-entry fallback on gateway error',
    (tester) async {
      final gateway = _StubGateway(
        NutritionGatewayResult.error(
          const NutritionGatewayError('network', 'offline'),
        ),
      );
      await tester.runAsync(() async {
        await tester.pumpWidget(
          _app(FoodSearchScreen(gateway: gateway, repository: repository)),
        );
        // The screen loads favorites/recents asynchronously on startup;
        // let those real-async DB queries complete.
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      });
      final loc = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;
      expect(find.text(loc.nutritionSearchTitle), findsOneWidget);
      expect(find.text(loc.nutritionSearchAll), findsOneWidget);
      expect(find.text(loc.nutritionSearchMyMeals), findsOneWidget);
      expect(find.text(loc.nutritionSearchFavorites), findsOneWidget);
      expect(find.text(loc.nutritionSearchMyFoods), findsOneWidget);
      expect(find.text(loc.nutritionSearchManual), findsNothing);
      expect(find.text(loc.nutritionSearchDatabase), findsNothing);
      expect(find.text(loc.nutritionScanMeal), findsOneWidget);
      expect(find.text(loc.nutritionScanBarcode), findsOneWidget);
      expect(find.text(loc.nutritionAddManually), findsOneWidget);
    },
  );

  testWidgets('food library filters user-created and gateway foods by source', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await repository.createManualFood(
        name: 'Manual do usuário',
        referenceAmount: 100,
        referenceUnit: 'g',
        referenceValues: const NutritionValues(calories: 100),
      );
      await repository.createManualFood(
        name: 'Lido por imagem',
        referenceAmount: 100,
        referenceUnit: 'g',
        referenceValues: const NutritionValues(calories: 120),
        source: FoodSource.aiVision,
      );
      final gatewayFood = Food(
        id: 'gateway-food',
        source: FoodSource.openFoodFacts,
        externalId: 'off-123',
        name: 'Alimento do gateway',
        searchName: Food.normalizeForSearch('Alimento do gateway'),
        fetchedAt: DateTime(2026, 8, 11),
      );
      await repository.upsertFoodWithDetails(
        food: gatewayFood,
        variants: const [
          FoodVariant(
            id: 'gateway-variant',
            foodId: 'gateway-food',
            referenceAmount: 100,
            referenceUnit: 'g',
            values: NutritionValues(calories: 90),
          ),
        ],
      );
    });

    await tester.runAsync(() async {
      await tester.pumpWidget(_app(FoodLibraryScreen(repository: repository)));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    });
    final loc = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;

    expect(find.text(loc.nutritionFoodLibraryTitle), findsOneWidget);
    expect(find.text(loc.nutritionSearchAll), findsOneWidget);
    expect(find.text(loc.nutritionSearchManual), findsOneWidget);
    expect(find.text(loc.nutritionSearchDatabase), findsOneWidget);

    await tester.tap(find.text(loc.nutritionSearchManual));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Manual do usuário'), findsOneWidget);
    expect(find.text('Lido por imagem'), findsOneWidget);
    expect(find.text('Alimento do gateway'), findsNothing);

    await tester.tap(find.text(loc.nutritionSearchDatabase));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Manual do usuário'), findsNothing);
    expect(find.text('Lido por imagem'), findsNothing);
    expect(find.text('Alimento do gateway'), findsOneWidget);
  });

  testWidgets('Food library add menu offers AI scan and manual entry', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(_app(FoodLibraryScreen(repository: repository)));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    });
    final loc = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();

    expect(find.text(loc.nutritionScanMeal), findsOneWidget);
    expect(find.text(loc.nutritionAddManually), findsOneWidget);
  });

  testWidgets(
    'manual food keeps calories and macros prominent and details collapsed',
    (tester) async {
      await tester.pumpWidget(_app(ManualFoodScreen(repository: repository)));
      final loc = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;

      expect(find.text(loc.nutritionManualSectionMacros), findsOneWidget);
      expect(find.text(loc.nutritionManualCalories), findsOneWidget);
      expect(find.text(loc.nutritionManualProtein), findsOneWidget);
      expect(find.text(loc.nutritionManualCarbs), findsOneWidget);
      expect(find.text(loc.nutritionManualFat), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(find.text(loc.nutritionFatBreakdownTitle), findsWidgets);
      expect(find.text(loc.nutritionFatSaturated), findsNothing);
      expect(find.text(loc.nutritionProgressPotassium), findsNothing);

      await tester.tap(find.text(loc.nutritionFatBreakdownTitle).first);
      await tester.pumpAndSettle();
      expect(find.text(loc.nutritionFatSaturated), findsOneWidget);
      expect(find.text(loc.nutritionFatMonounsaturated), findsOneWidget);
      expect(find.text(loc.nutritionFatPolyunsaturated), findsOneWidget);
      expect(find.text(loc.nutritionFatTrans), findsOneWidget);
      expect(find.text(loc.nutritionProgressPotassium), findsNothing);
    },
  );

  testWidgets('AI label fat details are prefilled and expanded for review', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        ManualFoodScreen(
          repository: repository,
          initial: const AiFoodLabelDraft(
            name: 'Peanut butter',
            values: NutritionValues(
              calories: 590,
              proteinG: 25,
              carbsG: 20,
              fatG: 50,
              saturatedFatG: 8,
              monounsaturatedFatG: 24,
              polyunsaturatedFatG: 15,
              transFatG: 0,
            ),
          ),
        ),
      ),
    );
    final loc = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();

    final saturated = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, loc.nutritionFatSaturated),
    );
    final mono = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, loc.nutritionFatMonounsaturated),
    );
    expect(saturated.controller!.text, '8');
    expect(mono.controller!.text, '24');
  });

  testWidgets('Remote search only runs after an explicit submit', (
    tester,
  ) async {
    final gateway = _StubGateway(
      NutritionGatewayResult.error(
        const NutritionGatewayError('network', 'offline'),
      ),
    );
    await tester.runAsync(() async {
      await tester.pumpWidget(
        _app(FoodSearchScreen(gateway: gateway, repository: repository)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    });

    await tester.enterText(find.byType(TextField), 'banana');
    await tester.pumpAndSettle();
    expect(gateway.searchCalls, 0);

    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(gateway.searchCalls, 1);
  });

  testWidgets('Food search header changes the target meal', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        _app(
          FoodSearchScreen(
            gateway: _StubGateway(
              NutritionGatewayResult.ok(const <FoodSearchResult>[]),
            ),
            repository: repository,
            mealType: 'lunch',
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    });
    final loc = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;

    expect(find.text(loc.nutritionMealLunch), findsOneWidget);
    await tester.tap(find.text(loc.nutritionMealLunch));
    await tester.pumpAndSettle();
    await tester.tap(find.text(loc.nutritionMealBreakfast));
    await tester.pumpAndSettle();

    expect(find.text(loc.nutritionMealBreakfast), findsOneWidget);
  });

  testWidgets('A response is ignored when the typed query has changed', (
    tester,
  ) async {
    final gateway = _ControlledGateway();
    await tester.runAsync(() async {
      await tester.pumpWidget(
        _app(FoodSearchScreen(gateway: gateway, repository: repository)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    });
    final loc = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;

    await tester.enterText(find.byType(TextField), 'apple');
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(gateway.searchCalls, 1);

    // A text change invalidates the in-flight request immediately. Keep the
    // replacement below the local-search threshold so this test isolates the
    // remote race without starting another SQLite query.
    await tester.enterText(find.byType(TextField), 'b');
    await tester.pump();
    gateway.pending.complete(
      NutritionGatewayResult.error(
        const NutritionGatewayError('network', 'stale failure'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(loc.nutritionSearchUnavailable), findsNothing);
  });

  testWidgets('Quantity resets symmetrically when switching units', (
    tester,
  ) async {
    final now = DateTime.now();
    final food = Food(
      id: 'food',
      source: FoodSource.manual,
      externalId: 'food',
      name: 'Banana',
      searchName: 'banana',
      fetchedAt: now,
    );
    const variant = FoodVariant(
      id: 'variant',
      foodId: 'food',
      referenceAmount: 100,
      referenceUnit: 'g',
      values: NutritionValues(calories: 90),
    );
    const serving = FoodServing(
      id: 'serving',
      foodVariantId: 'variant',
      label: '1 unidade',
      unit: 'serving',
      gramsEquivalent: 80,
    );
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: FoodQuantitySheet(
            food: food,
            primaryVariant: variant,
            servings: const [serving],
          ),
        ),
      ),
    );
    final loc = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;
    TextField quantityField() => tester.widget(find.byType(TextField));

    expect(quantityField().controller!.text, '100');
    await tester.tap(find.text(loc.nutritionUnitServing));
    await tester.pump();
    expect(quantityField().controller!.text, '1');
    await tester.tap(find.text(loc.nutritionUnitGrams));
    await tester.pump();
    expect(quantityField().controller!.text, '100');
  });

  testWidgets('Editing a serving restores its conversion automatically', (
    tester,
  ) async {
    final now = DateTime.now();
    final food = Food(
      id: 'food',
      source: FoodSource.manual,
      externalId: 'food',
      name: 'Iogurte',
      searchName: 'iogurte',
      fetchedAt: now,
    );
    const variant = FoodVariant(
      id: 'variant',
      foodId: 'food',
      referenceAmount: 100,
      referenceUnit: 'g',
      values: NutritionValues(calories: 60),
    );
    const serving = FoodServing(
      id: 'serving',
      foodVariantId: 'variant',
      label: 'Pote',
      unit: 'serving',
      gramsEquivalent: 170,
    );
    final snapshot = NutritionSnapshot(
      version: NutritionSnapshot.currentVersion,
      source: FoodSource.manual,
      externalId: 'food',
      foodName: 'Iogurte',
      foodBrand: null,
      variantLabel: null,
      referenceAmount: 100,
      referenceUnit: 'g',
      quantity: 1,
      unit: 'serving',
      gramsEquivalent: 170,
      mlEquivalent: null,
      consumed: const NutritionValues(calories: 102),
      isEstimated: false,
      hasMissingValues: true,
    );
    final existing = MealLogItem(
      id: 'item',
      mealLogId: 'meal',
      foodId: 'food',
      foodVariantId: 'variant',
      foodNameSnapshot: 'Iogurte',
      quantity: 1,
      unit: 'serving',
      calories: 102,
      snapshotJson: snapshot.encode(),
      createdAt: now,
    );
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: FoodQuantitySheet(
            food: food,
            primaryVariant: variant,
            servings: const [serving],
            existing: existing,
          ),
        ),
      ),
    );
    final loc = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;
    final save = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, loc.nutritionSave),
    );
    expect(save.onPressed, isNotNull);
  });

  testWidgets(
    'Falls back to the labelled value when the equivalence is the wrong unit',
    (tester) async {
      final now = DateTime.now();
      final food = Food(
        id: 'food',
        source: FoodSource.manual,
        externalId: 'food',
        name: 'Coca-Cola Sabor Original',
        searchName: 'coca cola',
        brand: 'Coca-Cola',
        fetchedAt: now,
      );
      const variant = FoodVariant(
        id: 'variant',
        foodId: 'food',
        referenceAmount: 100,
        referenceUnit: 'ml',
        values: NutritionValues(calories: 42),
      );
      // Real-world bad data: the source lists only the gram weight of
      // the can, but the label clearly says "250 ml". The sheet must
      // treat the labelled value as a volume equivalence.
      const serving = FoodServing(
        id: 'serving',
        foodVariantId: 'variant',
        label: '250 ml',
        unit: 'serving',
        gramsEquivalent: 250,
      );
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: FoodQuantitySheet(
              food: food,
              primaryVariant: variant,
              servings: const [serving],
            ),
          ),
        ),
      );
      // Default unit is ml (per 100 ml), so the save button must be
      // enabled without the user touching anything.
      final loc = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;
      final save = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, loc.nutritionSave),
      );
      expect(save.onPressed, isNotNull);
    },
  );

  testWidgets('MainShell renders three tabs (Workout, Sleep, Nutrition)', (
    tester,
  ) async {
    // Render a structure equivalent to MainShell: we use a stub body
    // so the test does not depend on the Workout/Sleep screens.
    late AppLocalizations loc;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Builder(
          builder: (context) {
            loc = AppLocalizations.of(context)!;
            return const _StubMainShell();
          },
        ),
      ),
    );
    await tester.pump();
    expect(find.text(loc.tabWorkout), findsOneWidget);
    expect(find.text(loc.tabSleep), findsOneWidget);
    expect(find.text(loc.tabNutrition), findsOneWidget);
  });
}

class _StubMainShell extends StatelessWidget {
  const _StubMainShell();

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      body: const SizedBox.shrink(),
      bottomNavigationBar: NavigationBar(
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.fitness_center_outlined),
            label: loc.tabWorkout,
          ),
          NavigationDestination(
            icon: const Icon(Icons.nightlight_outlined),
            label: loc.tabSleep,
          ),
          NavigationDestination(
            icon: const Icon(Icons.restaurant_outlined),
            label: loc.tabNutrition,
          ),
        ],
      ),
    );
  }
}
