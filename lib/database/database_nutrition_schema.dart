import 'package:sqflite/sqflite.dart';

/// Creates the tables and indexes owned by the nutrition feature.
abstract final class DatabaseNutritionSchema {
  /// Creates the full nutrition module schema (v22) using
  /// `IF NOT EXISTS` so it can be invoked both from `_onCreate` and
  /// `_onUpgrade` without duplicating SQL.
  static Future<void> create(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS foods (
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
      CREATE TABLE IF NOT EXISTS food_variants (
        id TEXT PRIMARY KEY,
        food_id TEXT NOT NULL,
        label TEXT,
        reference_amount REAL NOT NULL,
        reference_unit TEXT NOT NULL,
        calories REAL,
        protein_g REAL,
        carbs_g REAL,
        fat_g REAL,
        saturated_fat_g REAL,
        monounsaturated_fat_g REAL,
        polyunsaturated_fat_g REAL,
        trans_fat_g REAL,
        fiber_g REAL,
        sugars_g REAL,
        sodium_mg REAL,
        potassium_mg REAL,
        calcium_mg REAL,
        iron_mg REAL,
        magnesium_mg REAL,
        zinc_mg REAL,
        vitamin_a_ug REAL,
        vitamin_c_mg REAL,
        vitamin_d_ug REAL,
        vitamin_b12_ug REAL,
        extra_nutrients_json TEXT,
        is_estimated INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (food_id) REFERENCES foods(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS food_servings (
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
      CREATE TABLE IF NOT EXISTS meal_logs (
        id TEXT PRIMARY KEY,
        date TEXT NOT NULL,
        meal_type TEXT NOT NULL,
        name TEXT,
        notes TEXT,
        created_at TEXT NOT NULL,
        UNIQUE(date, meal_type)
      )
    ''');
    // User-defined meal types (v31). The catalog is managed in the
    // nutrition settings; the diary renders one section per type. The
    // four legacy keys are seeded with `name = NULL`, which resolves to
    // a localized label; renamed/custom types carry their own name.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS meal_types (
        id TEXT PRIMARY KEY,
        key TEXT UNIQUE NOT NULL,
        name TEXT,
        order_index INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS meal_log_items (
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
        saturated_fat_g REAL,
        monounsaturated_fat_g REAL,
        polyunsaturated_fat_g REAL,
        trans_fat_g REAL,
        fiber_g REAL,
        sugars_g REAL,
        sodium_mg REAL,
        potassium_mg REAL,
        calcium_mg REAL,
        iron_mg REAL,
        magnesium_mg REAL,
        zinc_mg REAL,
        vitamin_a_ug REAL,
        vitamin_c_mg REAL,
        vitamin_d_ug REAL,
        vitamin_b12_ug REAL,
        nutrition_snapshot_json TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (meal_log_id) REFERENCES meal_logs(id) ON DELETE CASCADE,
        FOREIGN KEY (food_id) REFERENCES foods(id) ON DELETE SET NULL,
        FOREIGN KEY (food_variant_id) REFERENCES food_variants(id) ON DELETE SET NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS nutrition_goals (
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
      CREATE TABLE IF NOT EXISTS saved_meals (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        meal_type TEXT,
        portions REAL NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS saved_meal_items (
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

    for (final statement in <String>[
      'CREATE INDEX IF NOT EXISTS idx_foods_search_name ON foods(search_name)',
      'CREATE INDEX IF NOT EXISTS idx_foods_brand ON foods(brand)',
      'CREATE INDEX IF NOT EXISTS idx_foods_barcode ON foods(barcode)',
      'CREATE INDEX IF NOT EXISTS idx_food_variants_food ON food_variants(food_id)',
      'CREATE INDEX IF NOT EXISTS idx_food_servings_variant ON food_servings(food_variant_id)',
      'CREATE INDEX IF NOT EXISTS idx_meal_logs_date ON meal_logs(date)',
      'CREATE INDEX IF NOT EXISTS idx_meal_log_items_meal ON meal_log_items(meal_log_id, created_at ASC)',
      'CREATE INDEX IF NOT EXISTS idx_meal_types_order ON meal_types(order_index)',
      'CREATE INDEX IF NOT EXISTS idx_nutrition_goals_active ON nutrition_goals(is_active)',
      'CREATE INDEX IF NOT EXISTS idx_saved_meal_items_meal ON saved_meal_items(saved_meal_id, order_index ASC)',
    ]) {
      try {
        await db.execute(statement);
      } catch (_) {}
    }
  }
}
