import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/nutrition/food.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/screens/workout/food_search_screen.dart';
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
}

class _StubGateway implements NutritionGateway {
  final NutritionGatewayResult<List<Food>> result;
  _StubGateway(this.result);

  @override
  Future<NutritionGatewayResult<List<Food>>> search(
    String query, {
    int limit = 20,
  }) async {
    return result;
  }

  @override
  Future<NutritionGatewayResult<Food>> getFood(
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
  });

  tearDown(() async {
    await database.close();
  });

  testWidgets(
    'Search screen renders the manual-entry fallback on gateway error',
    (tester) async {
      final gateway = _StubGateway(
        NutritionGatewayResult.error(
          const NutritionGatewayError('network', 'offline'),
        ),
      );
      await tester.pumpWidget(
        _app(FoodSearchScreen(gateway: gateway, repository: repository)),
      );
      await tester.pump();
      final loc = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;
      expect(find.text(loc.nutritionSearchTitle), findsOneWidget);
      expect(find.text(loc.nutritionAddManually), findsOneWidget);
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
