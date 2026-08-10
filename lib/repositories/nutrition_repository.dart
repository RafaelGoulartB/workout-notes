import 'dart:async';
import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'package:workout_notes/models/nutrition/daily_nutrition_summary.dart';
import 'package:workout_notes/models/nutrition/food.dart';
import 'package:workout_notes/models/nutrition/food_serving.dart';
import 'package:workout_notes/models/nutrition/food_variant.dart';
import 'package:workout_notes/models/nutrition/meal_log.dart';
import 'package:workout_notes/models/nutrition/meal_log_item.dart';
import 'package:workout_notes/models/nutrition/meal_type.dart';
import 'package:workout_notes/models/nutrition/nutrition_goal.dart';
import 'package:workout_notes/models/nutrition/nutrition_values.dart';
import 'package:workout_notes/models/nutrition/saved_meal.dart';
import 'package:workout_notes/utils/nutrition_conversion.dart';

import 'base_repository.dart';

/// Thrown when user input fails nutrition-level validation (non-positive
/// quantities, negative nutrients, etc).
class NutritionValidationException implements Exception {
  final String code;
  const NutritionValidationException(this.code);
  @override
  String toString() => 'NutritionValidationException($code)';
}

/// Repository responsible for the nutrition module: food cache,
/// meal logs, daily aggregation, and the user-defined goal.
///
/// All write operations that touch more than one table (food + variants
/// + servings) are wrapped in a transaction so a partial failure does
/// not leave the cache in an inconsistent state.
class NutritionRepository extends BaseRepository {
  static const _uuid = Uuid();

  // ===================================================================
  // Food cache
  // ===================================================================

  /// Local search using a normalized name and optional brand token.
  /// Returns up to [limit] results ordered by closest match.
  Future<List<FoodSearchResultLite>> searchLocalFoods(
    String query, {
    int limit = 30,
  }) async {
    final normalized = Food.normalizeForSearch(query);
    if (normalized.isEmpty) return const [];
    final db = await this.db;
    final like = '%${_escapeLike(normalized)}%';
    final brand = _extractBrand(query);
    // `_extractBrand` always yields a real token (for single-word
    // queries the word itself), so the brand predicate below can
    // never degrade into `LIKE '%%'` — which previously matched
    // every branded food for any single-word query.
    final rows = await db.rawQuery(
      '''
      SELECT f.*,
        (CASE WHEN f.search_name = ? THEN 0
              WHEN f.search_name LIKE ? THEN 1
              WHEN f.brand IS NOT NULL AND LOWER(f.brand) LIKE ? THEN 2
              ELSE 3 END) as match_rank
      FROM foods f
      WHERE f.search_name LIKE ? ESCAPE '\\' OR (f.brand IS NOT NULL AND LOWER(f.brand) LIKE ? ESCAPE '\\')
      ORDER BY match_rank ASC, f.name ASC
      LIMIT ?
      ''',
      <Object?>[
        normalized,
        '$normalized%',
        '%${_escapeLike(brand.toLowerCase())}%',
        like,
        '%${_escapeLike(brand.toLowerCase())}%',
        limit,
      ],
    );
    return _hydrateResults(rows);
  }

  /// Returns one food with its variants and servings, or null if not
  /// found. The lookup is by the local id.
  Future<FoodWithDetails?> getFoodWithDetails(String foodId) async {
    final db = await this.db;
    final foodRows = await db.query(
      'foods',
      where: 'id = ?',
      whereArgs: [foodId],
      limit: 1,
    );
    if (foodRows.isEmpty) return null;
    return _detailsFor(Food.fromMap(foodRows.first));
  }

  /// Returns one food by its barcode, or null when missing. Used by
  /// the barcode scan flow to surface cached items without a network
  /// call.
  Future<FoodWithDetails?> getFoodByBarcode(String barcode) async {
    final db = await this.db;
    final foodRows = await db.query(
      'foods',
      where: 'barcode = ?',
      whereArgs: [barcode],
      limit: 1,
    );
    if (foodRows.isEmpty) return null;
    return _detailsFor(Food.fromMap(foodRows.first));
  }

  /// Returns one food by (source, externalId), or null when missing.
  Future<FoodWithDetails?> getFoodBySource({
    required String source,
    required String externalId,
  }) async {
    final db = await this.db;
    final foodRows = await db.query(
      'foods',
      where: 'source = ? AND external_id = ?',
      whereArgs: [source, externalId],
      limit: 1,
    );
    if (foodRows.isEmpty) return null;
    return _detailsFor(Food.fromMap(foodRows.first));
  }

  /// Upserts a food plus its variants and servings in a single
  /// transaction. Used both for remote gateway results and manual
  /// entries.
  ///
  /// The (source, externalId) pair is the natural key; an existing
  /// row is updated in-place and its variants/servings are replaced.
  Future<Food> upsertFoodWithDetails({
    required Food food,
    required List<FoodVariant> variants,
    Map<String, List<FoodServing>>? servings,
  }) async {
    final db = await this.db;
    return db.transaction((txn) async {
      final existing = await txn.query(
        'foods',
        where: 'source = ? AND external_id = ?',
        whereArgs: [food.source, food.externalId],
        limit: 1,
      );
      final resolvedFood = existing.isEmpty
          ? food
          : food.copyWith(
              id: existing.first['id'] as String,
              fetchedAt: food.fetchedAt,
              // Fresh remote/manual results carry no `lastUsedAt`; keep
              // the existing recency instead of wiping it (a re-fetch
              // must not make a recently logged food disappear from
              // the "recently used" list).
              lastUsedAt: food.lastUsedAt ??
                  _parseIsoDate(existing.first['last_used_at'] as String?),
            );
      // UPDATE in place (never REPLACE): REPLACE deletes the row
      // before inserting, which fires `ON DELETE SET NULL` on
      // meal_log_items and silently breaks the food links of past
      // meals. Updating keeps the row identity intact.
      if (existing.isEmpty) {
        await txn.insert('foods', resolvedFood.toMap());
      } else {
        await txn.update(
          'foods',
          resolvedFood.toMap(),
          where: 'id = ?',
          whereArgs: [resolvedFood.id],
        );
      }

      // Upsert variants by id instead of delete + recreate. Deleting a
      // variant row nulls `food_variant_id` on referenced meal log
      // items via `ON DELETE SET NULL`, so past meals would silently
      // lose the link that keeps them editable. Same for the food row.
      for (final variant in variants) {
        final resolved = variant.foodId == resolvedFood.id
            ? variant
            : variant.copyWith(foodId: resolvedFood.id);
        final existingVariant = await txn.query(
          'food_variants',
          where: 'id = ?',
          whereArgs: [resolved.id],
          limit: 1,
        );
        if (existingVariant.isNotEmpty &&
            existingVariant.first['food_id'] != resolvedFood.id) {
          throw const NutritionValidationException('variant_id_conflict');
        }
        if (existingVariant.isEmpty) {
          await txn.insert('food_variants', resolved.toMap());
        } else {
          await txn.update(
            'food_variants',
            resolved.toMap(),
            where: 'id = ?',
            whereArgs: [resolved.id],
          );
        }
        // Servings carry no history links, so they can be safely
        // replaced wholesale.
        await txn.delete(
          'food_servings',
          where: 'food_variant_id = ?',
          whereArgs: [resolved.id],
        );
        final list = servings?[variant.id] ?? const <FoodServing>[];
        for (final serving in list) {
          final resolvedServing = serving.foodVariantId == resolved.id
              ? serving
              : serving.copyWith(foodVariantId: resolved.id);
          await txn.insert('food_servings', resolvedServing.toMap());
        }
      }
      return resolvedFood;
    });
  }

  /// Registers a manual food entry and returns the persisted [Food].
  /// [source] defaults to [FoodSource.manual]; the AI label flow uses
  /// [FoodSource.aiVision] so estimated foods stay distinguishable.
  Future<Food> createManualFood({
    required String name,
    String? brand,
    String? barcode,
    required double referenceAmount,
    required String referenceUnit,
    required NutritionValues referenceValues,
    bool isEstimated = false,
    String source = FoodSource.manual,
    List<ManualServingInput> servings = const [],
  }) async {
    final now = DateTime.now();
    final foodId = _uuid.v4();
    final food = Food(
      id: foodId,
      source: source,
      externalId: foodId,
      name: name,
      searchName: Food.normalizeForSearch(name),
      brand: brand,
      barcode: barcode,
      fetchedAt: now,
    );
    final variant = FoodVariant(
      id: _uuid.v4(),
      foodId: foodId,
      referenceAmount: referenceAmount,
      referenceUnit: referenceUnit,
      values: referenceValues,
      isEstimated: isEstimated,
    );
    final servingModels = <FoodServing>[];
    for (final s in servings) {
      servingModels.add(
        FoodServing(
          id: _uuid.v4(),
          foodVariantId: variant.id,
          label: s.label,
          quantity: s.quantity,
          unit: s.unit,
          gramsEquivalent: s.gramsEquivalent,
          mlEquivalent: s.mlEquivalent,
        ),
      );
    }
    return upsertFoodWithDetails(
      food: food,
      variants: [variant],
      servings: {variant.id: servingModels},
    );
  }

  // ===================================================================
  // Favorites, recents and meal suggestions
  // ===================================================================

  /// Marks a food as favorite (or removes the mark).
  Future<void> setFoodFavorite(String foodId, bool favorite) async {
    final db = await this.db;
    await db.update(
      'foods',
      {'is_favorite': favorite ? 1 : 0},
      where: 'id = ?',
      whereArgs: [foodId],
    );
  }

  /// Foods the user pinned as favorites, alphabetically.
  Future<List<FoodSearchResultLite>> getFavoriteFoods({int limit = 20}) async {
    final db = await this.db;
    final rows = await db.query(
      'foods',
      where: 'is_favorite = 1',
      orderBy: 'name ASC',
      limit: limit,
    );
    return _hydrateResults(rows);
  }

  /// All foods cached in the local library, favorites first and then
  /// alphabetically. Used by the standalone food-library screen.
  Future<List<FoodSearchResultLite>> getAllFoods({int limit = 500}) async {
    final db = await this.db;
    final rows = await db.query(
      'foods',
      orderBy: 'is_favorite DESC, name COLLATE NOCASE ASC',
      limit: limit,
    );
    return _hydrateResults(rows);
  }

  /// Most recently logged foods (`last_used_at DESC`; nulls sort last).
  Future<List<FoodSearchResultLite>> getRecentFoods({int limit = 12}) async {
    final db = await this.db;
    final rows = await db.query(
      'foods',
      orderBy: 'last_used_at DESC',
      limit: limit,
    );
    return _hydrateResults(rows);
  }

  /// Foods most often logged in a given [mealType], by usage count.
  /// Powers the "suggested for this meal" section of the search screen.
  Future<List<FoodSearchResultLite>> getMealSuggestions(
    String mealType, {
    int limit = 12,
  }) async {
    final db = await this.db;
    final rows = await db.rawQuery(
      '''
      SELECT f.*, COUNT(mli.id) as use_count
      FROM meal_log_items mli
      JOIN meal_logs ml ON mli.meal_log_id = ml.id
      JOIN foods f ON mli.food_id = f.id
      WHERE ml.meal_type = ?
      GROUP BY f.id
      ORDER BY use_count DESC, f.name ASC
      LIMIT ?
      ''',
      [mealType, limit],
    );
    return _hydrateResults(rows);
  }

  // ===================================================================
  // Meal type catalog (managed in the nutrition settings)
  // ===================================================================

  /// All configured meal types, in display order. The four legacy keys
  /// are seeded with `name` null and resolve to localized labels.
  Future<List<MealTypeDefinition>> getMealTypes() async {
    final db = await this.db;
    final rows = await db.query(
      'meal_types',
      orderBy: 'order_index ASC',
    );
    return rows.map(MealTypeDefinition.fromMap).toList();
  }

  /// Creates a new meal type with a random key and appends it to the
  /// catalog.
  Future<MealTypeDefinition> createMealType(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const NutritionValidationException('meal_name_required');
    }
    final db = await this.db;
    final count = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM meal_types'),
        ) ??
        0;
    final type = MealTypeDefinition(
      id: _uuid.v4(),
      key: _uuid.v4(),
      name: trimmed,
      orderIndex: count,
      createdAt: DateTime.now(),
    );
    await db.insert('meal_types', type.toMap());
    return type;
  }

  /// Renames a meal type in the catalog. Existing logs keep their own
  /// name snapshot — only sections created afterwards use the new name.
  Future<void> renameMealType(String id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const NutritionValidationException('meal_name_required');
    }
    final db = await this.db;
    await db.update(
      'meal_types',
      {'name': trimmed},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Deletes a meal type from the catalog. Logged history is preserved:
  /// existing sections stay visible in their days with their stored
  /// name snapshots; only days after the deletion stop showing a new
  /// section for this type.
  Future<void> deleteMealType(String id) async {
    final db = await this.db;
    await db.delete('meal_types', where: 'id = ?', whereArgs: [id]);
  }

  /// Reorders the catalog by writing [ids] in the given order.
  Future<void> reorderMealTypes(List<String> ids) async {
    final db = await this.db;
    await db.transaction((txn) async {
      for (var i = 0; i < ids.length; i++) {
        await txn.update(
          'meal_types',
          {'order_index': i},
          where: 'id = ?',
          whereArgs: [ids[i]],
        );
      }
    });
  }

  // ===================================================================
  // Meal logs
  // ===================================================================

  /// Returns the [MealLog] for (date, mealType) or creates it lazily.
  /// When a new log is created and [name] is provided it becomes the
  /// section's display name; an existing log is never renamed here.
  Future<MealLog> ensureMealLog({
    required String date,
    required String mealType,
    String? name,
  }) async {
    _validateDate(date);
    final db = await this.db;
    return _ensureMealLogIn(db, date: date, mealType: mealType, name: name);
  }

  /// Same as [ensureMealLog] but runs on an explicit executor so callers
  /// can fold the lookup/insert into their own transaction — a check +
  /// insert outside a transaction can race and violate
  /// `UNIQUE(date, meal_type)`.
  Future<MealLog> _ensureMealLogIn(
    DatabaseExecutor executor, {
    required String date,
    required String mealType,
    String? name,
  }) async {
    final existing = await executor.query(
      'meal_logs',
      where: 'date = ? AND meal_type = ?',
      whereArgs: [date, mealType],
      limit: 1,
    );
    if (existing.isNotEmpty) return MealLog.fromMap(existing.first);
    final log = MealLog(
      id: _uuid.v4(),
      date: date,
      mealType: mealType,
      name: name,
      createdAt: DateTime.now(),
    );
    await executor.insert('meal_logs', log.toMap());
    return log;
  }

  /// Adds a food to a meal, recomputing the consumed nutrition from
  /// the [conversion] provided by the UI. [name] snapshots the meal
  /// type's display name onto a newly created log, so later renames in
  /// the catalog never rewrite past days.
  Future<MealLogItem> addMealLogItem({
    required String date,
    required String mealType,
    required Food food,
    required FoodVariant variant,
    required NutritionConversion conversion,
    List<FoodServing> availableServings = const [],
    String? name,
  }) async {
    _validateDate(date);
    final db = await this.db;
    return db.transaction((txn) async {
      final log = await _ensureMealLogIn(
        txn,
        date: date,
        mealType: mealType,
        name: name,
      );
      final consumed = conversion.apply(variant.values);
      final serving = availableServings.firstWhereOrNull(
        (s) => s.label == conversion.unit || s.unit == conversion.unit,
      );
      final snapshot = NutritionSnapshot(
        version: NutritionSnapshot.currentVersion,
        source: food.source,
        externalId: food.externalId,
        foodName: food.name,
        foodBrand: food.brand,
        variantLabel: variant.label,
        referenceAmount: variant.referenceAmount,
        referenceUnit: variant.referenceUnit,
        quantity: conversion.quantity,
        unit: conversion.unit,
        gramsEquivalent: serving?.gramsEquivalent,
        mlEquivalent: serving?.mlEquivalent,
        consumed: consumed,
        isEstimated: variant.isEstimated,
        hasMissingValues: consumed.hasMissingFields,
      );
      final item = MealLogItem(
        id: _uuid.v4(),
        mealLogId: log.id,
        foodId: food.id,
        foodVariantId: variant.id,
        foodNameSnapshot: food.name,
        brandSnapshot: food.brand,
        quantity: conversion.quantity,
        unit: conversion.unit,
        calories: consumed.calories,
        proteinG: consumed.proteinG,
        carbsG: consumed.carbsG,
        fatG: consumed.fatG,
        fiberG: consumed.fiberG,
        sugarsG: consumed.sugarsG,
        sodiumMg: consumed.sodiumMg,
        snapshotJson: snapshot.encode(),
        createdAt: DateTime.now(),
      );
      await txn.insert('meal_log_items', item.toMap());
      if (food.id.isNotEmpty) {
        try {
          await txn.update(
            'foods',
            {'last_used_at': DateTime.now().toIso8601String()},
            where: 'id = ?',
            whereArgs: [food.id],
          );
        } catch (_) {}
      }
      return item;
    });
  }

  /// Updates the quantity/unit of an existing item, regenerating its
  /// snapshot from the original food/variant.
  Future<MealLogItem> updateMealLogItem({
    required String itemId,
    required NutritionConversion conversion,
    required FoodVariant variant,
  }) async {
    final db = await this.db;
    final rows = await db.query(
      'meal_log_items',
      where: 'id = ?',
      whereArgs: [itemId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw const NutritionValidationException('item_not_found');
    }
    final current = MealLogItem.fromMap(rows.first);
    final snapshot = current.snapshot;
    final consumed = conversion.apply(variant.values);
    final updated = current.copyWith(
      quantity: conversion.quantity,
      unit: conversion.unit,
      calories: consumed.calories,
      proteinG: consumed.proteinG,
      carbsG: consumed.carbsG,
      fatG: consumed.fatG,
      fiberG: consumed.fiberG,
      sugarsG: consumed.sugarsG,
      sodiumMg: consumed.sodiumMg,
    );
    final newSnapshot = NutritionSnapshot(
      version: NutritionSnapshot.currentVersion,
      source: snapshot.source,
      externalId: snapshot.externalId,
      foodName: snapshot.foodName,
      foodBrand: snapshot.foodBrand,
      variantLabel: snapshot.variantLabel,
      referenceAmount: snapshot.referenceAmount,
      referenceUnit: snapshot.referenceUnit,
      quantity: conversion.quantity,
      unit: conversion.unit,
      gramsEquivalent:
          conversion.serving?.gramsEquivalent ?? snapshot.gramsEquivalent,
      mlEquivalent: conversion.serving?.mlEquivalent ?? snapshot.mlEquivalent,
      consumed: consumed,
      isEstimated: snapshot.isEstimated,
      hasMissingValues: consumed.hasMissingFields,
    );
    final updatedWithSnapshot = MealLogItem(
      id: updated.id,
      mealLogId: updated.mealLogId,
      foodId: updated.foodId,
      foodVariantId: updated.foodVariantId,
      foodNameSnapshot: updated.foodNameSnapshot,
      brandSnapshot: updated.brandSnapshot,
      quantity: updated.quantity,
      unit: updated.unit,
      calories: updated.calories,
      proteinG: updated.proteinG,
      carbsG: updated.carbsG,
      fatG: updated.fatG,
      fiberG: updated.fiberG,
      sugarsG: updated.sugarsG,
      sodiumMg: updated.sodiumMg,
      snapshotJson: newSnapshot.encode(),
      createdAt: updated.createdAt,
    );
    await db.update(
      'meal_log_items',
      updatedWithSnapshot.toMap(),
      where: 'id = ?',
      whereArgs: [itemId],
    );
    return updatedWithSnapshot;
  }

  /// Deletes a single item from a meal log.
  Future<void> deleteMealLogItem(String itemId) async {
    final db = await this.db;
    await db.delete('meal_log_items', where: 'id = ?', whereArgs: [itemId]);
  }

  /// Re-inserts a previously deleted item with its original id (undo).
  /// The parent meal log is kept by design (deleting an item never
  /// deletes the log), so the foreign key stays valid.
  Future<void> restoreMealLogItem(MealLogItem item) async {
    final db = await this.db;
    await db.insert('meal_log_items', item.toMap());
  }

  /// Returns the items of the most recent meal of [mealType] logged
  /// before [beforeDate] (exclusive). Used by the "repeat this meal"
  /// flow. Returns an empty list when no previous instance exists.
  Future<List<MealLogItem>> getLatestMealItems(
    String mealType, {
    String? beforeDate,
  }) async {
    final db = await this.db;
    final where = <String>['meal_type = ?'];
    final args = <Object?>[mealType];
    if (beforeDate != null) {
      where.add('date < ?');
      args.add(beforeDate);
    }
    final logs = await db.query(
      'meal_logs',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'date DESC',
      limit: 1,
    );
    if (logs.isEmpty) return const [];
    final items = await db.query(
      'meal_log_items',
      where: 'meal_log_id = ?',
      whereArgs: [logs.first['id']],
      orderBy: 'created_at ASC',
    );
    return items.map(MealLogItem.fromMap).toList();
  }

  /// Returns the display name of the most recent meal of [mealType]
  /// logged before [beforeDate] (exclusive), or null when there is no
  /// previous instance or it has no custom name. Used by "repeat this
  /// meal" so the copied section keeps the same name.
  Future<String?> getLatestMealName(
    String mealType, {
    String? beforeDate,
  }) async {
    final db = await this.db;
    final where = <String>['meal_type = ?'];
    final args = <Object?>[mealType];
    if (beforeDate != null) {
      where.add('date < ?');
      args.add(beforeDate);
    }
    final logs = await db.query(
      'meal_logs',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'date DESC',
      limit: 1,
    );
    if (logs.isEmpty) return null;
    return logs.first['name'] as String?;
  }

  /// Clones [items] into the meal (date, mealType), preserving each
  /// item's snapshot verbatim so past data stays editable and auditable.
  /// New ids are assigned; `created_at` is set to now. [name] is used
  /// only when the target log does not exist yet.
  Future<int> copyItemsToMeal({
    required String date,
    required String mealType,
    required List<MealLogItem> items,
    String? name,
  }) async {
    if (items.isEmpty) return 0;
    _validateDate(date);
    final db = await this.db;
    final now = DateTime.now();
    await db.transaction((txn) async {
      final log = await _ensureMealLogIn(
        txn,
        date: date,
        mealType: mealType,
        name: name,
      );
      final touchedFoods = <String>{};
      for (final item in items) {
        final clone = MealLogItem(
          id: _uuid.v4(),
          mealLogId: log.id,
          foodId: item.foodId,
          foodVariantId: item.foodVariantId,
          foodNameSnapshot: item.foodNameSnapshot,
          brandSnapshot: item.brandSnapshot,
          quantity: item.quantity,
          unit: item.unit,
          calories: item.calories,
          proteinG: item.proteinG,
          carbsG: item.carbsG,
          fatG: item.fatG,
          fiberG: item.fiberG,
          sugarsG: item.sugarsG,
          sodiumMg: item.sodiumMg,
          snapshotJson: item.snapshotJson,
          createdAt: now,
        );
        await txn.insert('meal_log_items', clone.toMap());
        if (item.foodId != null) touchedFoods.add(item.foodId!);
      }
      for (final foodId in touchedFoods) {
        try {
          await txn.update(
            'foods',
            {'last_used_at': now.toIso8601String()},
            where: 'id = ?',
            whereArgs: [foodId],
          );
        } catch (_) {}
      }
    });
    return items.length;
  }

  /// Returns all meal logs and their items for the given day.
  Future<List<MealLogWithItems>> getDayMeals(String date) async {
    _validateDate(date);
    final db = await this.db;
    final logs = await db.query(
      'meal_logs',
      where: 'date = ?',
      whereArgs: [date],
    );
    final result = <MealLogWithItems>[];
    for (final log in logs) {
      final meal = MealLog.fromMap(log);
      final items = await db.query(
        'meal_log_items',
        where: 'meal_log_id = ?',
        whereArgs: [meal.id],
        orderBy: 'created_at ASC',
      );
      result.add(
        MealLogWithItems(
          log: meal,
          items: items.map(MealLogItem.fromMap).toList(),
        ),
      );
    }
    // Order by creation so sections appear in the order they were
    // added to the day (custom meal sections have no fixed order).
    result.sort(
      (a, b) {
        final byTime = a.log.createdAt.compareTo(b.log.createdAt);
        if (byTime != 0) return byTime;
        return a.log.id.compareTo(b.log.id);
      },
    );
    return result;
  }

  /// Aggregates the consumed values for every item logged on [date].
  Future<DailyNutritionSummary> getDailySummary(String date) async {
    _validateDate(date);
    final db = await this.db;
    final rows = await db.rawQuery(
      '''
      SELECT
        SUM(calories) as calories,
        SUM(protein_g) as protein_g,
        SUM(carbs_g) as carbs_g,
        SUM(fat_g) as fat_g,
        SUM(fiber_g) as fiber_g,
        SUM(sugars_g) as sugars_g,
        SUM(sodium_mg) as sodium_mg
      FROM meal_log_items mli
      JOIN meal_logs ml ON mli.meal_log_id = ml.id
      WHERE ml.date = ?
      ''',
      [date],
    );
    if (rows.isEmpty) {
      return DailyNutritionSummary(date: date, consumed: NutritionValues.empty);
    }
    final row = rows.first;
    final consumed = NutritionValues(
      calories: _sum(row['calories']),
      proteinG: _sum(row['protein_g']),
      carbsG: _sum(row['carbs_g']),
      fatG: _sum(row['fat_g']),
      fiberG: _sum(row['fiber_g']),
      sugarsG: _sum(row['sugars_g']),
      sodiumMg: _sum(row['sodium_mg']),
    );
    final incomplete = await db.rawQuery(
      '''
      SELECT 1 FROM meal_log_items mli
      JOIN meal_logs ml ON mli.meal_log_id = ml.id
      WHERE ml.date = ?
        AND (
          mli.calories IS NULL OR mli.protein_g IS NULL OR
          mli.carbs_g IS NULL OR mli.fat_g IS NULL OR
          mli.fiber_g IS NULL OR mli.sugars_g IS NULL OR
          mli.sodium_mg IS NULL
        )
      LIMIT 1
      ''',
      [date],
    );
    return DailyNutritionSummary(
      date: date,
      consumed: consumed,
      hasIncompleteData: incomplete.isNotEmpty,
    );
  }

  /// Daily consumed totals for the last [days] days (including today),
  /// oldest first. Each row has `date` plus the seven nutrient sums;
  /// days without any logged item are absent.
  Future<List<Map<String, dynamic>>> getDailyNutritionHistory({
    int days = 30,
  }) async {
    final db = await this.db;
    final start = _dateString(
      DateTime.now().subtract(Duration(days: days - 1)),
    );
    final rows = await db.rawQuery(
      '''
      SELECT ml.date as date,
        SUM(mli.calories) as calories,
        SUM(mli.protein_g) as protein_g,
        SUM(mli.carbs_g) as carbs_g,
        SUM(mli.fat_g) as fat_g,
        SUM(mli.fiber_g) as fiber_g,
        SUM(mli.sugars_g) as sugars_g,
        SUM(mli.sodium_mg) as sodium_mg
      FROM meal_log_items mli
      JOIN meal_logs ml ON mli.meal_log_id = ml.id
      WHERE ml.date >= ?
      GROUP BY ml.date
      ORDER BY ml.date ASC
      ''',
      [start],
    );
    return rows;
  }

  // ===================================================================
  // Goals
  // ===================================================================

  /// Returns the active goal or null when none is configured.
  Future<NutritionGoal?> getActiveGoal() async {
    final db = await this.db;
    final rows = await db.query(
      'nutrition_goals',
      where: 'is_active = 1',
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return NutritionGoal.fromMap(rows.first);
  }

  /// Stores a new active goal. Any previously active goal is marked
  /// inactive to enforce the "at most one" rule.
  Future<NutritionGoal> saveGoal({
    double? calories,
    double? proteinG,
    double? carbsG,
    double? fatG,
  }) async {
    if ((calories ?? 0) <= 0 &&
        (proteinG ?? 0) <= 0 &&
        (carbsG ?? 0) <= 0 &&
        (fatG ?? 0) <= 0) {
      throw const NutritionValidationException('goal_empty');
    }
    for (final pair in <(String, double?)>[
      ('calories', calories),
      ('protein_g', proteinG),
      ('carbs_g', carbsG),
      ('fat_g', fatG),
    ]) {
      final v = pair.$2;
      if (v == null) continue;
      if (v.isNaN || v.isInfinite || v < 0) {
        throw NutritionValidationException('goal_invalid_${pair.$1}');
      }
    }
    final now = DateTime.now();
    final goal = NutritionGoal(
      id: _uuid.v4(),
      calories: calories,
      proteinG: proteinG,
      carbsG: carbsG,
      fatG: fatG,
      createdAt: now,
      updatedAt: now,
      isActive: true,
    );
    final db = await this.db;
    await db.transaction((txn) async {
      await txn.update('nutrition_goals', {
        'is_active': 0,
      }, where: 'is_active = 1');
      await txn.insert('nutrition_goals', goal.toMap());
    });
    return goal;
  }

  /// Removes the active goal, leaving the user without a target.
  Future<void> clearActiveGoal() async {
    final db = await this.db;
    await db.update('nutrition_goals', {
      'is_active': 0,
    }, where: 'is_active = 1');
  }

  // ===================================================================
  // Saved meals (templates)
  // ===================================================================

  /// Creates a new saved meal or updates the one identified by [id]
  /// (when provided). Items are replaced wholesale — they carry no
  /// history links, mirroring the servings upsert pattern.
  Future<SavedMeal> saveSavedMeal({
    String? id,
    required String name,
    String? mealType,
    double portions = 1,
    List<SavedMealItemDraft> items = const [],
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const NutritionValidationException('saved_meal_name_required');
    }
    if (portions <= 0 || portions.isNaN || portions.isInfinite) {
      throw const NutritionValidationException('saved_meal_portions_invalid');
    }
    final now = DateTime.now();
    final db = await this.db;
    return db.transaction((txn) async {
      Map<String, dynamic>? existingRow;
      if (id != null) {
        final rows = await txn.query(
          'saved_meals',
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        if (rows.isEmpty) {
          throw const NutritionValidationException('saved_meal_not_found');
        }
        existingRow = rows.first;
      }
      final meal = SavedMeal(
        id: id ?? _uuid.v4(),
        name: trimmed,
        mealType: mealType,
        portions: portions,
        // Preserve the original creation date when editing; only the
        // `updated_at` moves forward.
        createdAt: existingRow == null
            ? now
            : SavedMeal.fromMap(existingRow).createdAt,
        updatedAt: now,
      );
      if (id == null) {
        await txn.insert('saved_meals', meal.toMap());
      } else {
        await txn.update(
          'saved_meals',
          meal.toMap(),
          where: 'id = ?',
          whereArgs: [id],
        );
        await txn.delete(
          'saved_meal_items',
          where: 'saved_meal_id = ?',
          whereArgs: [id],
        );
      }
      for (var i = 0; i < items.length; i++) {
        final item = items[i];
        await txn.insert('saved_meal_items', {
          'id': _uuid.v4(),
          'saved_meal_id': meal.id,
          'food_id': item.foodId,
          'food_variant_id': item.foodVariantId,
          'food_name_snapshot': item.foodNameSnapshot,
          'brand_snapshot': item.brandSnapshot,
          'quantity': item.quantity,
          'unit': item.unit,
          'order_index': i,
        });
      }
      return meal;
    });
  }

  /// Returns a saved meal with its items and live-computed totals, or
  /// null when it does not exist.
  Future<SavedMealWithItems?> getSavedMeal(String id) async {
    final db = await this.db;
    final rows = await db.query(
      'saved_meals',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _savedMealWithItems(db, rows.first);
  }

  /// All saved meals, alphabetically, with items and live totals.
  Future<List<SavedMealWithItems>> getSavedMeals() async {
    final db = await this.db;
    final rows = await db.query('saved_meals', orderBy: 'name ASC');
    final result = <SavedMealWithItems>[];
    for (final row in rows) {
      result.add(await _savedMealWithItems(db, row));
    }
    return result;
  }

  /// Deletes a saved meal; its items cascade.
  Future<void> deleteSavedMeal(String id) async {
    final db = await this.db;
    await db.delete('saved_meals', where: 'id = ?', whereArgs: [id]);
  }

  /// Logs every ingredient of [savedMealId] into the (date, mealType)
  /// section, scaling quantities by the meal's portion count. [mealName]
  /// snapshots the meal type's display name onto a newly created log.
  /// Returns the number of items added and the number skipped because
  /// their food was deleted from the cache.
  Future<({int added, int skipped})> addSavedMealToDate({
    required String date,
    required String mealType,
    String? mealName,
    required String savedMealId,
  }) async {
    _validateDate(date);
    final meal = await getSavedMeal(savedMealId);
    if (meal == null) {
      throw const NutritionValidationException('saved_meal_not_found');
    }
    final section = await ensureMealLog(
      date: date,
      mealType: mealType,
      name: mealName,
    );
    var added = 0;
    var skipped = 0;
    for (final item in meal.items) {
      if (item.foodId == null || item.foodVariantId == null) {
        skipped++;
        continue;
      }
      final details = await getFoodWithDetails(item.foodId!);
      if (details == null) {
        skipped++;
        continue;
      }
      final variants = details.variants;
      if (variants.isEmpty) {
        skipped++;
        continue;
      }
      final variant = variants.firstWhere(
        (v) => v.id == item.foodVariantId,
        orElse: () => variants.first,
      );
      final servings = details.servings[variant.id] ?? const <FoodServing>[];
      final serving = servings.firstWhereOrNull(
        (s) => s.label == item.unit || s.unit == item.unit,
      );
      final conversion = NutritionConversion(
        quantity: item.quantity * meal.meal.portions,
        unit: item.unit,
        referenceAmount: variant.referenceAmount,
        referenceUnit: variant.referenceUnit,
        serving: serving,
      );
      try {
        conversion.resolveMultiplier();
      } catch (_) {
        skipped++;
        continue;
      }
      await addMealLogItem(
        date: date,
        mealType: section.mealType,
        food: details.food,
        variant: variant,
        conversion: conversion,
        availableServings: servings,
      );
      added++;
    }
    return (added: added, skipped: skipped);
  }

  // ===================================================================
  // Calorie balance analytics
  // ===================================================================

  /// Per-day totals for the [days] window, oldest first. Days with no
  /// logged items are emitted with `calories` (and the macros) null so
  /// the screen can render continuous timelines and detect missed days.
  Future<List<DailyCalorieTotal>> getDailyCalorieTotals({required int days}) async {
    final db = await this.db;
    final start = _dateString(
      DateTime.now().subtract(Duration(days: days - 1)),
    );
    final rows = await db.rawQuery(
      '''
      SELECT ml.date as date,
        SUM(mli.calories) as calories
      FROM meal_log_items mli
      JOIN meal_logs ml ON mli.meal_log_id = ml.id
      WHERE ml.date >= ?
      GROUP BY ml.date
      ORDER BY ml.date ASC
      ''',
      [start],
    );
    final totalsByDate = <String, double>{};
    for (final row in rows) {
      final v = _sum(row['calories']) ?? 0;
      if (v > 0) totalsByDate[row['date'] as String] = v;
    }
    final result = <DailyCalorieTotal>[];
    final startDate = DateTime.parse(start);
    for (var i = 0; i < days; i++) {
      final d = DateTime(startDate.year, startDate.month, startDate.day + i);
      final key = _dateString(d);
      result.add(
        DailyCalorieTotal(
          date: d,
          calories: totalsByDate[key],
        ),
      );
    }
    return result;
  }

  /// Aggregated totals for the [days] window. [goal] is the active
  /// calorie target, or null when no goal is configured.
  Future<CalorieBalance> getCalorieBalance({
    required int days,
    required double? goal,
  }) async {
    final dailies = await getDailyCalorieTotals(days: days);
    var consumed = 0.0;
    var loggedDays = 0;
    var inDeficit = 0;
    var onTarget = 0;
    var inSurplus = 0;
    final logged = <DailyCalorieTotal>[];
    for (final d in dailies) {
      if (d.calories == null) continue;
      consumed += d.calories!;
      loggedDays++;
      logged.add(d);
      if (goal != null && goal > 0) {
        final delta = d.calories! - goal;
        final ratio = (delta).abs() / goal;
        if (ratio <= 0.10) {
          onTarget++;
        } else if (delta < 0) {
          inDeficit++;
        } else {
          inSurplus++;
        }
      }
    }
    // Current streak: consecutive logged days (newest first) inside
    // the ±10% goal band. If the user has no goal configured the
    // streak is the number of consecutive days with any log.
    var streak = 0;
    if (goal != null && goal > 0) {
      for (var i = logged.length - 1; i >= 0; i--) {
        final d = logged[i];
        final delta = (d.calories! - goal).abs() / goal;
        if (delta <= 0.10) {
          streak++;
        } else {
          break;
        }
      }
    } else {
      for (var i = logged.length - 1; i >= 0; i--) {
        if (logged[i].calories != null) {
          streak++;
        } else {
          break;
        }
      }
    }
    final avg = loggedDays == 0 ? 0.0 : consumed / loggedDays;
    final totalGoal = goal == null ? null : goal * days;
    return CalorieBalance(
      days: days,
      totalConsumed: consumed,
      totalGoal: totalGoal,
      balance: totalGoal == null ? null : consumed - totalGoal,
      daysLogged: loggedDays,
      daysInDeficit: inDeficit,
      daysOnTarget: onTarget,
      daysInSurplus: inSurplus,
      currentStreak: streak,
      averageDailyIntake: avg,
    );
  }

  /// Top calorie-contributing foods in the [days] window, ordered by
  /// summed calories. Items whose food was deleted contribute nothing.
  Future<List<CalorieContributor>> getTopCalorieContributors({
    required int days,
    int limit = 10,
  }) async {
    final db = await this.db;
    final start = _dateString(
      DateTime.now().subtract(Duration(days: days - 1)),
    );
    final rows = await db.rawQuery(
      '''
      SELECT mli.food_name_snapshot as food_name,
        mli.brand_snapshot as brand,
        SUM(mli.calories) as total_calories,
        COUNT(*) as occurrences
      FROM meal_log_items mli
      JOIN meal_logs ml ON mli.meal_log_id = ml.id
      WHERE ml.date >= ?
        AND mli.food_name_snapshot IS NOT NULL
        AND mli.calories IS NOT NULL
      GROUP BY mli.food_name_snapshot, mli.brand_snapshot
      ORDER BY total_calories DESC
      LIMIT ?
      ''',
      [start, limit],
    );
    return rows
        .map(
          (r) => CalorieContributor(
            name: (r['food_name'] as String?) ?? '',
            brand: r['brand'] as String?,
            totalCalories: ((r['total_calories'] as num?) ?? 0).toDouble(),
            occurrences: ((r['occurrences'] as num?) ?? 0).toInt(),
          ),
        )
        .toList();
  }

  /// Calorie distribution across meal types in the [days] window.
  /// Excludes days with no logged items and meal types that never
  /// appear so the chart only renders what the user actually uses.
  Future<List<MealTypeCalories>> getCaloriesByMealType({
    required int days,
  }) async {
    final db = await this.db;
    final start = _dateString(
      DateTime.now().subtract(Duration(days: days - 1)),
    );
    final rows = await db.rawQuery(
      '''
      SELECT ml.meal_type as meal_type,
        COALESCE(ml.name, ml.meal_type) as display_name,
        SUM(mli.calories) as total_calories,
        COUNT(*) as item_count
      FROM meal_log_items mli
      JOIN meal_logs ml ON mli.meal_log_id = ml.id
      WHERE ml.date >= ?
        AND mli.calories IS NOT NULL
      GROUP BY ml.meal_type, display_name
      ORDER BY total_calories DESC
      ''',
      [start],
    );
    return rows
        .map(
          (r) => MealTypeCalories(
            mealType: (r['meal_type'] as String?) ?? '',
            displayName: (r['display_name'] as String?) ?? '',
            totalCalories: ((r['total_calories'] as num?) ?? 0).toDouble(),
            itemCount: ((r['item_count'] as num?) ?? 0).toInt(),
          ),
        )
        .toList();
  }

  /// Daily consumed totals for the [days] window — same shape as
  /// [getDailyNutritionHistory] but only the calories column, for the
  /// rolling-average chart.
  Future<List<DailyCalorieTotal>> getDailyCaloriesForRolling({
    required int days,
  }) async {
    return getDailyCalorieTotals(days: days);
  }

  // ===================================================================
  // CSV export
  // ===================================================================

  /// Returns the rows used by the CSV export. Each row represents a
  /// single [MealLogItem] and includes the original food source so the
  /// user can filter or audit their data later.
  Future<List<NutritionExportRow>> exportRows({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final db = await this.db;
    final where = <String>['1=1'];
    final args = <Object?>[];
    if (startDate != null) {
      where.add('ml.date >= ?');
      args.add(_dateString(startDate));
    }
    if (endDate != null) {
      where.add('ml.date <= ?');
      args.add(_dateString(endDate));
    }
    final rows = await db.rawQuery('''
      SELECT
        ml.date as date,
        ml.meal_type as meal_type,
        ml.name as meal_name,
        mli.food_name_snapshot as food,
        mli.brand_snapshot as brand,
        mli.quantity as quantity,
        mli.unit as unit,
        mli.calories as calories,
        mli.protein_g as protein_g,
        mli.carbs_g as carbs_g,
        mli.fat_g as fat_g,
        mli.fiber_g as fiber_g,
        mli.sugars_g as sugars_g,
        mli.sodium_mg as sodium_mg,
        f.source as source,
        mli.nutrition_snapshot_json as snapshot
      FROM meal_log_items mli
      JOIN meal_logs ml ON mli.meal_log_id = ml.id
      LEFT JOIN foods f ON mli.food_id = f.id
      WHERE ${where.join(' AND ')}
      ORDER BY ml.date ASC, ml.meal_type ASC, mli.created_at ASC
      ''', args);
    return rows.map(NutritionExportRow.fromMap).toList();
  }

  // ===================================================================
  // Internal helpers
  // ===================================================================

  Future<List<FoodVariant>> _loadVariants(String foodId) async {
    final db = await this.db;
    final rows = await db.query(
      'food_variants',
      where: 'food_id = ?',
      whereArgs: [foodId],
      orderBy: 'reference_amount ASC',
    );
    return rows.map(FoodVariant.fromMap).toList();
  }

  /// Loads a food's variants and their servings.
  Future<FoodWithDetails> _detailsFor(Food food) async {
    final variants = await _loadVariants(food.id);
    final servings = <String, List<FoodServing>>{};
    for (final v in variants) {
      servings[v.id] = await _loadServings(v.id);
    }
    return FoodWithDetails(food: food, variants: variants, servings: servings);
  }

  Future<List<FoodServing>> _loadServings(String variantId) async {
    final db = await this.db;
    final rows = await db.query(
      'food_servings',
      where: 'food_variant_id = ?',
      whereArgs: [variantId],
      orderBy: 'label ASC',
    );
    return rows.map(FoodServing.fromMap).toList();
  }

  /// Loads a saved meal with its items and recomputes the nutrition
  /// totals live from the current food cache.
  Future<SavedMealWithItems> _savedMealWithItems(
    DatabaseExecutor db,
    Map<String, dynamic> mealRow,
  ) async {
    final meal = SavedMeal.fromMap(mealRow);
    final itemRows = await db.query(
      'saved_meal_items',
      where: 'saved_meal_id = ?',
      whereArgs: [meal.id],
      orderBy: 'order_index ASC',
    );
    final items = itemRows.map(SavedMealItem.fromMap).toList();
    final computed = await _computeSavedMealTotals(db, items, meal.portions);
    return SavedMealWithItems(
      meal: meal,
      items: items,
      totals: computed.totals,
      consumedByItem: computed.byItem,
    );
  }

  /// Recomputes a saved meal's nutrition from the live food cache by
  /// replaying each item's conversion (same rules as the quantity
  /// sheet). [portions] scales every ingredient, mirroring
  /// [addSavedMealToDate], so the displayed totals always match what
  /// logging the template would add. Items whose food/variant was
  /// deleted or whose unit can no longer be resolved contribute
  /// nothing.
  Future<({NutritionValues? totals, Map<String, NutritionValues> byItem})>
  _computeSavedMealTotals(
    DatabaseExecutor db,
    List<SavedMealItem> items,
    double portions,
  ) async {
    if (items.isEmpty) {
      return (totals: null, byItem: <String, NutritionValues>{});
    }
    final variantIds = <String>[];
    for (final item in items) {
      if (item.foodVariantId != null) variantIds.add(item.foodVariantId!);
    }
    final variants = <String, FoodVariant>{};
    final servingsByVariant = <String, List<FoodServing>>{};
    if (variantIds.isNotEmpty) {
      final ph = List.filled(variantIds.length, '?').join(',');
      final variantRows = await db.rawQuery(
        'SELECT * FROM food_variants WHERE id IN ($ph)',
        variantIds,
      );
      for (final row in variantRows) {
        final v = FoodVariant.fromMap(row);
        variants[v.id] = v;
      }
      final servingRows = await db.rawQuery(
        'SELECT * FROM food_servings WHERE food_variant_id IN ($ph) ORDER BY label ASC',
        variantIds,
      );
      for (final row in servingRows) {
        final s = FoodServing.fromMap(row);
        servingsByVariant.putIfAbsent(s.foodVariantId, () => []).add(s);
      }
    }
    var calories = 0.0;
    var proteinG = 0.0;
    var carbsG = 0.0;
    var fatG = 0.0;
    var fiberG = 0.0;
    var sugarsG = 0.0;
    var sodiumMg = 0.0;
    var hasAny = false;
    final byItem = <String, NutritionValues>{};
    for (final item in items) {
      final variant = item.foodVariantId == null
          ? null
          : variants[item.foodVariantId];
      if (variant == null) continue;
      final servings = servingsByVariant[variant.id] ?? const <FoodServing>[];
      final serving = servings.firstWhereOrNull(
        (s) => s.label == item.unit || s.unit == item.unit,
      );
      final conversion = NutritionConversion(
        quantity: item.quantity * portions,
        unit: item.unit,
        referenceAmount: variant.referenceAmount,
        referenceUnit: variant.referenceUnit,
        serving: serving,
      );
      NutritionValues consumed;
      try {
        conversion.resolveMultiplier();
        consumed = conversion.apply(variant.values);
      } catch (_) {
        continue;
      }
      byItem[item.id] = consumed;
      calories += consumed.calories ?? 0;
      proteinG += consumed.proteinG ?? 0;
      carbsG += consumed.carbsG ?? 0;
      fatG += consumed.fatG ?? 0;
      fiberG += consumed.fiberG ?? 0;
      sugarsG += consumed.sugarsG ?? 0;
      sodiumMg += consumed.sodiumMg ?? 0;
      hasAny = true;
    }
    if (!hasAny) return (totals: null, byItem: byItem);
    return (
      totals: NutritionValues(
        calories: calories,
        proteinG: proteinG,
        carbsG: carbsG,
        fatG: fatG,
        fiberG: fiberG,
        sugarsG: sugarsG,
        sodiumMg: sodiumMg,
      ),
      byItem: byItem,
    );
  }

  Future<List<FoodSearchResultLite>> _hydrateResults(
    List<Map<String, dynamic>> foodRows,
  ) async {
    if (foodRows.isEmpty) return const [];
    final db = await this.db;
    final foodIds = foodRows.map((r) => r['id'] as String).toList();
    final placeholders = List.filled(foodIds.length, '?').join(',');
    final variantRows = await db.rawQuery(
      'SELECT * FROM food_variants WHERE food_id IN ($placeholders) ORDER BY reference_amount ASC',
      foodIds,
    );
    final variantsByFood = <String, List<FoodVariant>>{};
    for (final row in variantRows) {
      final v = FoodVariant.fromMap(row);
      variantsByFood.putIfAbsent(v.foodId, () => []).add(v);
    }
    final variantIds = variantRows.map((r) => r['id'] as String).toList();
    final servingsByVariant = <String, List<FoodServing>>{};
    if (variantIds.isNotEmpty) {
      final ph = List.filled(variantIds.length, '?').join(',');
      final servingRows = await db.rawQuery(
        'SELECT * FROM food_servings WHERE food_variant_id IN ($ph) ORDER BY label ASC',
        variantIds,
      );
      for (final row in servingRows) {
        final s = FoodServing.fromMap(row);
        servingsByVariant.putIfAbsent(s.foodVariantId, () => []).add(s);
      }
    }
    return foodRows.map((row) {
      final food = Food.fromMap(row);
      final variants = variantsByFood[food.id] ?? const <FoodVariant>[];
      return FoodSearchResultLite(
        food: food,
        primaryVariant: variants.isEmpty ? null : variants.first,
        variants: variants,
        servings: variants.isEmpty
            ? const {}
            : {
                for (final v in variants)
                  v.id: servingsByVariant[v.id] ?? const <FoodServing>[],
              },
      );
    }).toList();
  }

  /// Brand token used for ranking/`WHERE` brand matches: the first
  /// word of the query. Single-word queries use the word itself, so
  /// the token is never empty (an empty token would produce a
  /// match-everything `LIKE '%%'` predicate).
  static String _extractBrand(String input) {
    final cleaned = input.trim();
    if (cleaned.isEmpty) return '';
    return cleaned.split(' ').first;
  }

  static String _escapeLike(String value) =>
      value.replaceAll('%', r'\%').replaceAll('_', r'\_');

  static double? _sum(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static DateTime? _parseIsoDate(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed != null && parsed.isUtc) return parsed.toLocal();
    return parsed;
  }
  static void _validateDate(String date) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) {
      throw const NutritionValidationException('invalid_date_format');
    }
  }

  static String _dateString(DateTime value) => DateTime(
    value.year,
    value.month,
    value.day,
  ).toIso8601String().substring(0, 10);
}

/// Lightweight food + variant bundle returned by local search.
class FoodSearchResultLite {
  final Food food;
  final FoodVariant? primaryVariant;
  final List<FoodVariant> variants;
  final Map<String, List<FoodServing>> servings;

  const FoodSearchResultLite({
    required this.food,
    this.primaryVariant,
    this.variants = const [],
    this.servings = const {},
  });
}

/// A food with all its variants and servings loaded.
class FoodWithDetails {
  final Food food;
  final List<FoodVariant> variants;
  final Map<String, List<FoodServing>> servings;

  const FoodWithDetails({
    required this.food,
    required this.variants,
    required this.servings,
  });
}

/// A meal log with its items, used by the day screen.
class MealLogWithItems {
  final MealLog log;
  final List<MealLogItem> items;

  const MealLogWithItems({required this.log, required this.items});
}

/// Optional input for a manual serving.
class ManualServingInput {
  final String label;
  final double quantity;
  final String unit;
  final double? gramsEquivalent;
  final double? mlEquivalent;

  const ManualServingInput({
    required this.label,
    required this.quantity,
    required this.unit,
    this.gramsEquivalent,
    this.mlEquivalent,
  });
}

/// Input for a saved meal ingredient. Built by the UI from either a
/// meal log item or a food + quantity selection.
class SavedMealItemDraft {
  final String? foodId;
  final String? foodVariantId;
  final String foodNameSnapshot;
  final String? brandSnapshot;
  final double quantity;
  final String unit;

  const SavedMealItemDraft({
    this.foodId,
    this.foodVariantId,
    required this.foodNameSnapshot,
    this.brandSnapshot,
    required this.quantity,
    required this.unit,
  });

  factory SavedMealItemDraft.fromMealLogItem(MealLogItem item) {
    return SavedMealItemDraft(
      foodId: item.foodId,
      foodVariantId: item.foodVariantId,
      foodNameSnapshot: item.foodNameSnapshot,
      brandSnapshot: item.brandSnapshot,
      quantity: item.quantity,
      unit: item.unit,
    );
  }
}

/// CSV export row.
class NutritionExportRow {
  final String date;
  final String mealType;

  /// Custom display name of the meal section (null for legacy rows).
  final String? mealName;
  final String food;
  final String? brand;
  final double quantity;
  final String unit;
  final double? calories;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;
  final double? fiberG;
  final double? sugarsG;
  final double? sodiumMg;
  final String? source;
  final bool isEstimated;
  final bool hasMissingValues;

  const NutritionExportRow({
    required this.date,
    required this.mealType,
    this.mealName,
    required this.food,
    this.brand,
    required this.quantity,
    required this.unit,
    this.calories,
    this.proteinG,
    this.carbsG,
    this.fatG,
    this.fiberG,
    this.sugarsG,
    this.sodiumMg,
    this.source,
    this.isEstimated = false,
    this.hasMissingValues = false,
  });

  factory NutritionExportRow.fromMap(Map<String, dynamic> map) {
    final rawSnapshot = map['snapshot'] as String?;
    bool isEstimated = false;
    bool hasMissing = false;
    if (rawSnapshot != null && rawSnapshot.isNotEmpty) {
      try {
        final snapshot = jsonDecode(rawSnapshot);
        if (snapshot is Map) {
          isEstimated = (snapshot['is_estimated'] as bool?) ?? false;
          hasMissing = (snapshot['has_missing_values'] as bool?) ?? false;
        }
      } catch (_) {}
    }
    return NutritionExportRow(
      date: (map['date'] as String?) ?? '',
      mealType: (map['meal_type'] as String?) ?? '',
      mealName: map['meal_name'] as String?,
      food: (map['food'] as String?) ?? '',
      brand: map['brand'] as String?,
      quantity: (map['quantity'] as num?)?.toDouble() ?? 0,
      unit: (map['unit'] as String?) ?? '',
      calories: (map['calories'] as num?)?.toDouble(),
      proteinG: (map['protein_g'] as num?)?.toDouble(),
      carbsG: (map['carbs_g'] as num?)?.toDouble(),
      fatG: (map['fat_g'] as num?)?.toDouble(),
      fiberG: (map['fiber_g'] as num?)?.toDouble(),
      sugarsG: (map['sugars_g'] as num?)?.toDouble(),
      sodiumMg: (map['sodium_mg'] as num?)?.toDouble(),
      source: map['source'] as String?,
      isEstimated: isEstimated,
      hasMissingValues: hasMissing,
    );
  }
}

extension _FirstWhereOrNull<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}

/// One day of total calories consumed, or null when the day has no
/// logged items. Powers the calorie-tracking analytics screen.
class DailyCalorieTotal {
  final DateTime date;
  final double? calories;

  const DailyCalorieTotal({required this.date, required this.calories});
}

/// Aggregated calorie balance for a window of [days]. All counters
/// consider only days with at least one logged item; days without
/// any log are not counted in any bucket (deficit / on target /
/// surplus / streak) so the user's behavior on a rest day never
/// skews the totals.
class CalorieBalance {
  final int days;
  final double totalConsumed;

  /// Sum of the active goal over the whole window (or null when no
  /// goal is configured). Combined with [totalConsumed] to produce
  /// the net surplus / deficit.
  final double? totalGoal;

  /// `consumed - totalGoal`. Null when no goal is set.
  final double? balance;
  final int daysLogged;
  final int daysInDeficit;
  final int daysOnTarget;
  final int daysInSurplus;
  final int currentStreak;
  final double averageDailyIntake;

  const CalorieBalance({
    required this.days,
    required this.totalConsumed,
    required this.totalGoal,
    required this.balance,
    required this.daysLogged,
    required this.daysInDeficit,
    required this.daysOnTarget,
    required this.daysInSurplus,
    required this.currentStreak,
    required this.averageDailyIntake,
  });
}

/// A food (or food + brand pair) that contributed calories in a
/// window, used by the "top contributors" panel.
class CalorieContributor {
  final String name;
  final String? brand;
  final double totalCalories;
  final int occurrences;

  const CalorieContributor({
    required this.name,
    this.brand,
    required this.totalCalories,
    required this.occurrences,
  });
}

/// Per-meal-type calorie subtotal, used by the "where the calories
/// come from" panel.
class MealTypeCalories {
  final String mealType;
  final String displayName;
  final double totalCalories;
  final int itemCount;

  const MealTypeCalories({
    required this.mealType,
    required this.displayName,
    required this.totalCalories,
    required this.itemCount,
  });
}
