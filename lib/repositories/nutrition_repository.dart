import 'dart:async';
import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:workout_notes/models/nutrition/calorie_analytics.dart';
import 'package:workout_notes/models/nutrition/daily_nutrition_summary.dart';
import 'package:workout_notes/models/nutrition/food.dart';
import 'package:workout_notes/models/nutrition/food_lookup.dart';
import 'package:workout_notes/models/nutrition/food_serving.dart';
import 'package:workout_notes/models/nutrition/food_variant.dart';
import 'package:workout_notes/models/nutrition/manual_serving_input.dart';
import 'package:workout_notes/models/nutrition/meal_log.dart';
import 'package:workout_notes/models/nutrition/meal_log_item.dart';
import 'package:workout_notes/models/nutrition/meal_log_with_items.dart';
import 'package:workout_notes/models/nutrition/meal_type.dart';
import 'package:workout_notes/models/nutrition/nutrition_export_row.dart';
import 'package:workout_notes/models/nutrition/nutrition_goal.dart';
import 'package:workout_notes/models/nutrition/nutrition_values.dart';
import 'package:workout_notes/models/nutrition/saved_meal.dart';
import 'package:workout_notes/models/nutrition/saved_meal_item_draft.dart';
import 'package:workout_notes/repositories/base_repository.dart';
import 'package:workout_notes/utils/date_utils.dart';
import 'package:workout_notes/utils/nutrition_conversion.dart';
import 'package:workout_notes/utils/sql_helpers.dart';

part 'nutrition_repository_calorie_analytics.dart';
part 'nutrition_repository_goals.dart';
part 'nutrition_repository_meal_logs.dart';
part 'nutrition_repository_meal_types.dart';
part 'nutrition_repository_reports.dart';
part 'nutrition_repository_saved_meals.dart';

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
  /// Local search using a normalized name and optional brand token.
  /// Returns up to [limit] results ordered by closest match.
  Future<List<FoodSearchResultLite>> searchLocalFoods(
    String query, {
    int limit = 30,
  }) async {
    final normalized = Food.normalizeForSearch(query);
    if (normalized.isEmpty) return const [];
    final db = await this.db;
    final like = '%${escapeLike(normalized)}%';
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
        '%${escapeLike(brand.toLowerCase())}%',
        like,
        '%${escapeLike(brand.toLowerCase())}%',
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
              lastUsedAt:
                  food.lastUsedAt ??
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
  /// AI-assisted flows use their own source so estimated foods remain
  /// distinguishable.
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

  /// Updates a food created by the user, preserving its local id and the
  /// variant id referenced by existing meal entries.
  Future<Food> updateManualFood({
    required String foodId,
    required String name,
    String? brand,
    String? barcode,
    required double referenceAmount,
    required String referenceUnit,
    required NutritionValues referenceValues,
    bool isEstimated = false,
    List<ManualServingInput> servings = const [],
  }) async {
    final details = await getFoodWithDetails(foodId);
    if (details == null) {
      throw const NutritionValidationException('food_not_found');
    }
    if (!details.food.isUserCreated) {
      throw const NutritionValidationException('manual_food_only');
    }

    final food = details.food.copyWith(
      name: name,
      searchName: Food.normalizeForSearch(name),
      brand: brand,
      barcode: barcode,
      fetchedAt: DateTime.now(),
    );
    final currentVariant = details.variants.isEmpty
        ? null
        : details.variants.first;
    final variant =
        currentVariant?.copyWith(
          referenceAmount: referenceAmount,
          referenceUnit: referenceUnit,
          values: referenceValues,
          isEstimated: isEstimated,
        ) ??
        FoodVariant(
          id: _uuid.v4(),
          foodId: food.id,
          referenceAmount: referenceAmount,
          referenceUnit: referenceUnit,
          values: referenceValues,
          isEstimated: isEstimated,
        );
    final servingModels = [
      for (final serving in servings)
        FoodServing(
          id: _uuid.v4(),
          foodVariantId: variant.id,
          label: serving.label,
          quantity: serving.quantity,
          unit: serving.unit,
          gramsEquivalent: serving.gramsEquivalent,
          mlEquivalent: serving.mlEquivalent,
        ),
    ];

    return upsertFoodWithDetails(
      food: food,
      variants: [variant],
      servings: {variant.id: servingModels},
    );
  }

  /// Deletes a food created by the user. Existing meal records keep their
  /// snapshots; their live food links are nulled by the database FK.
  Future<void> deleteManualFood(String foodId) async {
    final db = await this.db;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'foods',
        columns: ['source'],
        where: 'id = ?',
        whereArgs: [foodId],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final source = rows.first['source'] as String?;
      if (source != FoodSource.manual &&
          source != FoodSource.aiVision &&
          source != FoodSource.aiCoach) {
        throw const NutritionValidationException('manual_food_only');
      }
      await txn.delete('foods', where: 'id = ?', whereArgs: [foodId]);
    });
  }

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

  /// [getFoodWithDetails] on an explicit executor.
  Future<FoodWithDetails?> getFoodWithDetailsIn(
    DatabaseExecutor executor,
    String foodId,
  ) async => (await _detailsByFoodId(executor, [foodId]))[foodId];

  /// Loads a food's variants and their servings (two queries in total).
  Future<FoodWithDetails> _detailsFor(Food food) async {
    final db = await this.db;
    final details = await _loadDetails(db, [food]);
    return details[food.id]!;
  }

  /// Loads several foods with their variants and servings using two queries
  /// (all variants, then all servings) instead of one per food or variant.
  Future<Map<String, FoodWithDetails>> _loadDetails(
    DatabaseExecutor db,
    List<Food> foods,
  ) async {
    if (foods.isEmpty) return const {};
    final variantRows = await _selectIn(db, 'food_variants', 'food_id', [
      for (final food in foods) food.id,
    ], orderBy: 'reference_amount ASC');
    final variantsByFood = <String, List<FoodVariant>>{};
    for (final row in variantRows) {
      final variant = FoodVariant.fromMap(row);
      variantsByFood.putIfAbsent(variant.foodId, () => []).add(variant);
    }
    final servingRows = await _selectIn(
      db,
      'food_servings',
      'food_variant_id',
      [for (final row in variantRows) row['id'] as String],
      orderBy: 'label ASC',
    );
    final servingsByVariant = <String, List<FoodServing>>{};
    for (final row in servingRows) {
      final serving = FoodServing.fromMap(row);
      servingsByVariant
          .putIfAbsent(serving.foodVariantId, () => [])
          .add(serving);
    }
    return {
      for (final food in foods)
        food.id: FoodWithDetails(
          food: food,
          variants: variantsByFood[food.id] ?? const [],
          servings: {
            for (final variant
                in variantsByFood[food.id] ?? const <FoodVariant>[])
              variant.id:
                  servingsByVariant[variant.id] ?? const <FoodServing>[],
          },
        ),
    };
  }

  /// Foods by id with their variants and servings: three queries whatever
  /// the number of [foodIds]. Missing foods are simply absent.
  Future<Map<String, FoodWithDetails>> _detailsByFoodId(
    DatabaseExecutor db,
    List<String> foodIds,
  ) async {
    final ids = foodIds.toSet().toList();
    if (ids.isEmpty) return const {};
    final foods = (await _selectIn(
      db,
      'foods',
      'id',
      ids,
    )).map(Food.fromMap).toList();
    return _loadDetails(db, foods);
  }

  /// `SELECT * FROM [table] WHERE [column] IN (...)`, chunked to stay under
  /// SQLite's bound-variable limit. [orderBy] applies within each chunk, which
  /// keeps every group's rows ordered as long as a group's rows share a value
  /// of [column] (the usual parent-id lookups).
  Future<List<Map<String, Object?>>> _selectIn(
    DatabaseExecutor db,
    String table,
    String column,
    List<String> ids, {
    String? orderBy,
  }) async {
    const chunkSize = 500;
    final rows = <Map<String, Object?>>[];
    for (var i = 0; i < ids.length; i += chunkSize) {
      final chunk = ids.sublist(i, math.min(i + chunkSize, ids.length));
      rows.addAll(
        await db.query(
          table,
          where: '$column IN (${List.filled(chunk.length, '?').join(', ')})',
          whereArgs: chunk,
          orderBy: orderBy,
        ),
      );
    }
    return rows;
  }

  Future<List<FoodSearchResultLite>> _hydrateResults(
    List<Map<String, dynamic>> foodRows,
  ) async {
    if (foodRows.isEmpty) return const [];
    final db = await this.db;
    final foods = foodRows.map(Food.fromMap).toList();
    final details = await _loadDetails(db, foods);
    return [
      for (final food in foods)
        FoodSearchResultLite(
          food: food,
          primaryVariant: details[food.id]!.variants.firstOrNull,
          variants: details[food.id]!.variants,
          servings: details[food.id]!.servings,
        ),
    ];
  }
}

const _uuid = Uuid();

/// Brand token used for ranking/`WHERE` brand matches: the first
/// word of the query. Single-word queries use the word itself, so
/// the token is never empty (an empty token would produce a
/// match-everything `LIKE '%%'` predicate).
String _extractBrand(String input) {
  final cleaned = input.trim();
  if (cleaned.isEmpty) return '';
  return cleaned.split(' ').first;
}

double? _sum(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

DateTime? _parseIsoDate(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final parsed = DateTime.tryParse(raw);
  if (parsed != null && parsed.isUtc) return parsed.toLocal();
  return parsed;
}

void _validateDate(String date) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) {
    throw const NutritionValidationException('invalid_date_format');
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
