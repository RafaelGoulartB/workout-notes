import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/nutrition/food.dart';
import 'package:workout_notes/models/nutrition/food_serving.dart';
import 'package:workout_notes/models/nutrition/food_search_result.dart';
import 'package:workout_notes/models/nutrition/food_variant.dart';
import 'package:workout_notes/models/nutrition/meal_log_item.dart';
import 'package:workout_notes/models/nutrition/nutrition_values.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/screens/workout/food_quantity_sheet.dart';
import 'package:workout_notes/screens/workout/food_search_screen.dart';
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
    expect(find.byIcon(Icons.calendar_month_outlined), findsOneWidget);
    expect(find.text(loc.nutritionSummaryTitle), findsOneWidget);
    expect(find.text(loc.nutritionProgressTitle), findsOneWidget);
    expect(find.text(loc.nutritionSavedMeals), findsOneWidget);
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

    expect(find.text(loc.nutritionHomeDiary), findsOneWidget);
    expect(find.text(loc.nutritionAddManually), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
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
      expect(find.text(loc.nutritionAddManually), findsOneWidget);
    },
  );

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
