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
import 'package:workout_notes/models/nutrition/nutrition_goal.dart';
import 'package:workout_notes/models/nutrition/nutrition_values.dart';
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
    final rows = await db.rawQuery(
      '''
      SELECT f.*,
        (CASE WHEN f.search_name = ? THEN 0
              WHEN f.search_name LIKE ? THEN 1
              WHEN f.brand IS NOT NULL AND LOWER(f.brand) LIKE ? THEN 2
              ELSE 3 END) as match_rank
      FROM foods f
      WHERE f.search_name LIKE ? OR (f.brand IS NOT NULL AND LOWER(f.brand) LIKE ?)
      ORDER BY match_rank ASC, f.name ASC
      LIMIT ?
      ''',
      <Object?>[
        normalized,
        '$normalized%',
        '%${brand.toLowerCase()}%',
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
    final food = Food.fromMap(foodRows.first);
    final variants = await _loadVariants(food.id);
    final servings = <String, List<FoodServing>>{};
    for (final v in variants) {
      servings[v.id] = await _loadServings(v.id);
    }
    return FoodWithDetails(food: food, variants: variants, servings: servings);
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
    final food = Food.fromMap(foodRows.first);
    final variants = await _loadVariants(food.id);
    final servings = <String, List<FoodServing>>{};
    for (final v in variants) {
      servings[v.id] = await _loadServings(v.id);
    }
    return FoodWithDetails(food: food, variants: variants, servings: servings);
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
              lastUsedAt: food.lastUsedAt,
            );
      await txn.insert(
        'foods',
        resolvedFood.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // Replace variants.
      await txn.delete(
        'food_variants',
        where: 'food_id = ?',
        whereArgs: [resolvedFood.id],
      );
      for (final variant in variants) {
        final resolved = variant.foodId == resolvedFood.id
            ? variant
            : variant.copyWith(foodId: resolvedFood.id);
        await txn.insert('food_variants', resolved.toMap());
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
  Future<Food> createManualFood({
    required String name,
    String? brand,
    String? barcode,
    required double referenceAmount,
    required String referenceUnit,
    required NutritionValues referenceValues,
    bool isEstimated = false,
    List<ManualServingInput> servings = const [],
  }) async {
    final now = DateTime.now();
    final foodId = _uuid.v4();
    final food = Food(
      id: foodId,
      source: FoodSource.manual,
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

  /// Bumps [lastUsedAt] for a food so the cache can surface recently
  /// used items in future iterations. Safe to call multiple times.
  Future<void> markFoodUsed(String foodId) async {
    final db = await this.db;
    await db.update(
      'foods',
      {'last_used_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [foodId],
    );
  }

  // ===================================================================
  // Meal logs
  // ===================================================================

  /// Returns the [MealLog] for (date, mealType) or creates it lazily.
  Future<MealLog> ensureMealLog({
    required String date,
    required String mealType,
  }) async {
    _validateDate(date);
    _validateMealType(mealType);
    final db = await this.db;
    final existing = await db.query(
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
      createdAt: DateTime.now(),
    );
    await db.insert('meal_logs', log.toMap());
    return log;
  }

  /// Adds a food to a meal, recomputing the consumed nutrition from
  /// the [conversion] provided by the UI.
  Future<MealLogItem> addMealLogItem({
    required String date,
    required String mealType,
    required Food food,
    required FoodVariant variant,
    required NutritionConversion conversion,
    List<FoodServing> availableServings = const [],
  }) async {
    final log = await ensureMealLog(date: date, mealType: mealType);
    final db = await this.db;
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
    await db.transaction((txn) async {
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
    });
    return item;
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
    // Stable display order: breakfast → lunch → dinner → snacks.
    result.sort(
      (a, b) => MealType.displayOrder
          .indexOf(a.log.mealType)
          .compareTo(MealType.displayOrder.indexOf(b.log.mealType)),
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

  static String _extractBrand(String input) {
    final cleaned = input.trim();
    if (!cleaned.contains(' ')) return '';
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

  static void _validateDate(String date) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) {
      throw const NutritionValidationException('invalid_date_format');
    }
  }

  static void _validateMealType(String mealType) {
    if (!MealType.all.contains(mealType)) {
      throw const NutritionValidationException('invalid_meal_type');
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

/// CSV export row.
class NutritionExportRow {
  final String date;
  final String mealType;
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
