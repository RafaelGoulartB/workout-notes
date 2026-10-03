part of 'nutrition_repository.dart';

/// Saved meals (templates): persistence, previews and logging them.
extension NutritionRepositorySavedMeals on NutritionRepository {
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
          'serving_label': item.servingLabel,
          'serving_grams_equivalent': item.servingGramsEquivalent,
          'serving_ml_equivalent': item.servingMlEquivalent,
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

  /// All saved meals, alphabetically, with items and live totals. Items,
  /// variants and servings are loaded in batch for every meal at once.
  Future<List<SavedMealWithItems>> getSavedMeals() async {
    final db = await this.db;
    final rows = await db.query('saved_meals', orderBy: 'name ASC');
    if (rows.isEmpty) return const [];
    final meals = rows.map(SavedMeal.fromMap).toList();
    final itemRows = await _selectIn(db, 'saved_meal_items', 'saved_meal_id', [
      for (final meal in meals) meal.id,
    ], orderBy: 'order_index ASC');
    final itemsByMeal = <String, List<SavedMealItem>>{};
    for (final row in itemRows) {
      final item = SavedMealItem.fromMap(row);
      itemsByMeal.putIfAbsent(item.savedMealId, () => []).add(item);
    }
    final context = await _loadVariantContext(db, [
      for (final item in itemRows)
        if (item['food_variant_id'] != null) item['food_variant_id'] as String,
    ]);
    return [
      for (final meal in meals)
        _savedMealFrom(meal, itemsByMeal[meal.id] ?? const [], context),
    ];
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
  ///
  /// Atomic: foods, variants and servings are resolved in batch first, then
  /// the section and every item are written in one transaction. A write
  /// failure rolls everything back and is rethrown (never counted as
  /// "skipped"), so retrying cannot duplicate ingredients.
  Future<({int added, int skipped})> addSavedMealToDate({
    required String date,
    required String mealType,
    String? mealName,
    required String savedMealId,
  }) async {
    _validateDate(date);
    final db = await this.db;
    return db.transaction(
      (txn) => addSavedMealToDateIn(
        txn,
        date: date,
        mealType: mealType,
        mealName: mealName,
        savedMealId: savedMealId,
      ),
    );
  }

  /// [addSavedMealToDate] on an explicit executor, so callers can fold it into
  /// their own transaction. [itemIdFor] derives the primary key of the n-th
  /// logged item (a repeated call then fails instead of duplicating them).
  Future<({int added, int skipped})> addSavedMealToDateIn(
    DatabaseExecutor executor, {
    required String date,
    required String mealType,
    String? mealName,
    required String savedMealId,
    String Function(int index)? itemIdFor,
  }) async {
    _validateDate(date);
    final meal = await getSavedMealIn(executor, savedMealId);
    if (meal == null) {
      throw const NutritionValidationException('saved_meal_not_found');
    }
    final details = await _detailsByFoodId(executor, [
      for (final item in meal.items)
        if (item.foodId != null && item.foodVariantId != null) item.foodId!,
    ]);

    final planned = <MealLogEntryDraft>[];
    var skipped = 0;
    for (final item in meal.items) {
      final food = item.foodId == null ? null : details[item.foodId!];
      if (food == null || item.foodVariantId == null || food.variants.isEmpty) {
        skipped++;
        continue;
      }
      final variants = food.variants;
      final variant = variants.firstWhere(
        (v) => v.id == item.foodVariantId,
        orElse: () => variants.first,
      );
      final servings = food.servings[variant.id] ?? const <FoodServing>[];
      final serving = _resolveSavedMealServing(
        servings: servings,
        variantId: variant.id,
        unit: item.unit,
        servingLabel: item.servingLabel,
        gramsEquivalent: item.servingGramsEquivalent,
        mlEquivalent: item.servingMlEquivalent,
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
      planned.add((
        food: food.food,
        variant: variant,
        conversion: conversion,
        servings: servings,
      ));
    }

    await addMealLogItemsIn(
      executor,
      date: date,
      mealType: mealType,
      mealName: mealName,
      entries: planned,
      itemIdFor: itemIdFor,
    );
    return (added: planned.length, skipped: skipped);
  }

  /// [getSavedMeal] on an explicit executor.
  Future<SavedMealWithItems?> getSavedMealIn(
    DatabaseExecutor executor,
    String id,
  ) async {
    final rows = await executor.query(
      'saved_meals',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _savedMealWithItems(executor, rows.first);
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
    final context = await _loadVariantContext(db, [
      for (final item in items)
        if (item.foodVariantId != null) item.foodVariantId!,
    ]);
    return _savedMealFrom(meal, items, context);
  }

  /// A saved meal with live totals computed from already-loaded variants.
  SavedMealWithItems _savedMealFrom(
    SavedMeal meal,
    List<SavedMealItem> items,
    _VariantContext context,
  ) {
    final computed = _computeSavedMealTotalsIn(context, items, meal.portions);
    return SavedMealWithItems(
      meal: meal,
      items: items,
      totals: computed.totals,
      consumedByItem: computed.byItem,
    );
  }

  /// Variants and servings of [variantIds], two queries in total.
  Future<_VariantContext> _loadVariantContext(
    DatabaseExecutor db,
    List<String> variantIds,
  ) async {
    final ids = variantIds.toSet().toList();
    final variants = <String, FoodVariant>{};
    final servingsByVariant = <String, List<FoodServing>>{};
    if (ids.isNotEmpty) {
      for (final row in await _selectIn(db, 'food_variants', 'id', ids)) {
        final v = FoodVariant.fromMap(row);
        variants[v.id] = v;
      }
      final servingRows = await _selectIn(
        db,
        'food_servings',
        'food_variant_id',
        ids,
        orderBy: 'label ASC',
      );
      for (final row in servingRows) {
        final s = FoodServing.fromMap(row);
        servingsByVariant.putIfAbsent(s.foodVariantId, () => []).add(s);
      }
    }
    return _VariantContext(variants, servingsByVariant);
  }

  /// Recomputes a saved meal's nutrition from the live food cache by
  /// replaying each item's conversion (same rules as the quantity
  /// sheet). [portions] scales every ingredient, mirroring
  /// [addSavedMealToDate], so the displayed totals always match what
  /// logging the template would add. Items whose food/variant was
  /// deleted or whose unit can no longer be resolved contribute
  /// nothing.
  ({NutritionValues? totals, Map<String, NutritionValues> byItem})
  _computeSavedMealTotalsIn(
    _VariantContext context,
    List<SavedMealItem> items,
    double portions,
  ) {
    final records = [
      for (final item in items)
        (
          foodVariantId: item.foodVariantId,
          quantity: item.quantity,
          unit: item.unit,
          servingLabel: item.servingLabel,
          servingGramsEquivalent: item.servingGramsEquivalent,
          servingMlEquivalent: item.servingMlEquivalent,
        ),
    ];
    final computed = _totalsFromRecords(context, records, portions);
    final byItem = <String, NutritionValues>{};
    for (var i = 0; i < items.length; i++) {
      final v = computed.byIndex[i];
      if (v != null) byItem[items[i].id] = v;
    }
    return (totals: computed.totals, byItem: byItem);
  }

  /// Public variant of [_computeSavedMealTotals] that operates on the
  /// editor's in-memory [SavedMealItemDraft] list (the meal hasn't been
  /// saved yet). Returns `totals == null` when no item could be
  /// resolved.
  Future<NutritionValues?> previewSavedMealTotals({
    required List<SavedMealItemDraft> items,
    required double portions,
  }) async {
    final preview = await previewSavedMealNutrition(
      items: items,
      portions: portions,
    );
    return preview.totals;
  }

  /// Returns both the aggregate and each ingredient's calculated values so
  /// editor cards can mirror the nutrition shown in the final total.
  Future<({NutritionValues? totals, List<NutritionValues?> byItem})>
  previewSavedMealNutrition({
    required List<SavedMealItemDraft> items,
    required double portions,
  }) async {
    final db = await this.db;
    final records = [
      for (final item in items)
        (
          foodVariantId: item.foodVariantId,
          quantity: item.quantity,
          unit: item.unit,
          servingLabel: item.servingLabel,
          servingGramsEquivalent: item.servingGramsEquivalent,
          servingMlEquivalent: item.servingMlEquivalent,
        ),
    ];
    final computed = await _computeSavedMealTotalsFromRecords(
      db,
      records,
      portions,
    );
    return (
      totals: computed.totals,
      byItem: [for (var i = 0; i < records.length; i++) computed.byIndex[i]],
    );
  }

  /// Inner computation for [previewSavedMealTotals] (editor drafts): loads the
  /// variants the records point at, then replays each conversion. Each record
  /// is the minimum shape needed to replay the conversion.
  Future<({NutritionValues? totals, Map<int, NutritionValues> byIndex})>
  _computeSavedMealTotalsFromRecords(
    DatabaseExecutor db,
    List<
      ({
        String? foodVariantId,
        double quantity,
        String unit,
        String? servingLabel,
        double? servingGramsEquivalent,
        double? servingMlEquivalent,
      })
    >
    records,
    double portions,
  ) async {
    final context = await _loadVariantContext(db, [
      for (final record in records)
        if (record.foodVariantId != null) record.foodVariantId!,
    ]);
    return _totalsFromRecords(context, records, portions);
  }

  /// Replays each record's conversion against already-loaded variants and sums
  /// the result. Shared by saved meals and editor previews.
  ({NutritionValues? totals, Map<int, NutritionValues> byIndex})
  _totalsFromRecords(
    _VariantContext context,
    List<
      ({
        String? foodVariantId,
        double quantity,
        String unit,
        String? servingLabel,
        double? servingGramsEquivalent,
        double? servingMlEquivalent,
      })
    >
    records,
    double portions,
  ) {
    if (records.isEmpty) {
      return (totals: null, byIndex: <int, NutritionValues>{});
    }
    final variants = context.variants;
    final servingsByVariant = context.servingsByVariant;
    var calories = 0.0;
    var proteinG = 0.0;
    var carbsG = 0.0;
    var fatG = 0.0;
    var saturatedFatG = 0.0;
    var monounsaturatedFatG = 0.0;
    var polyunsaturatedFatG = 0.0;
    var transFatG = 0.0;
    var fiberG = 0.0;
    var sugarsG = 0.0;
    var sodiumMg = 0.0;
    var potassiumMg = 0.0;
    var calciumMg = 0.0;
    var ironMg = 0.0;
    var magnesiumMg = 0.0;
    var zincMg = 0.0;
    var vitaminAUg = 0.0;
    var vitaminCMg = 0.0;
    var vitaminDUg = 0.0;
    var vitaminB12Ug = 0.0;
    var hasAny = false;
    final byIndex = <int, NutritionValues>{};
    for (var i = 0; i < records.length; i++) {
      final record = records[i];
      final variant = record.foodVariantId == null
          ? null
          : variants[record.foodVariantId];
      if (variant == null) continue;
      final servings = servingsByVariant[variant.id] ?? const <FoodServing>[];
      final serving = _resolveSavedMealServing(
        servings: servings,
        variantId: variant.id,
        unit: record.unit,
        servingLabel: record.servingLabel,
        gramsEquivalent: record.servingGramsEquivalent,
        mlEquivalent: record.servingMlEquivalent,
      );
      final conversion = NutritionConversion(
        quantity: record.quantity * portions,
        unit: record.unit,
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
      byIndex[i] = consumed;
      calories += consumed.calories ?? 0;
      proteinG += consumed.proteinG ?? 0;
      carbsG += consumed.carbsG ?? 0;
      fatG += consumed.fatG ?? 0;
      saturatedFatG += consumed.saturatedFatG ?? 0;
      monounsaturatedFatG += consumed.monounsaturatedFatG ?? 0;
      polyunsaturatedFatG += consumed.polyunsaturatedFatG ?? 0;
      transFatG += consumed.transFatG ?? 0;
      fiberG += consumed.fiberG ?? 0;
      sugarsG += consumed.sugarsG ?? 0;
      sodiumMg += consumed.sodiumMg ?? 0;
      potassiumMg += consumed.potassiumMg ?? 0;
      calciumMg += consumed.calciumMg ?? 0;
      ironMg += consumed.ironMg ?? 0;
      magnesiumMg += consumed.magnesiumMg ?? 0;
      zincMg += consumed.zincMg ?? 0;
      vitaminAUg += consumed.vitaminAUg ?? 0;
      vitaminCMg += consumed.vitaminCMg ?? 0;
      vitaminDUg += consumed.vitaminDUg ?? 0;
      vitaminB12Ug += consumed.vitaminB12Ug ?? 0;
      hasAny = true;
    }
    if (!hasAny) return (totals: null, byIndex: byIndex);
    return (
      totals: NutritionValues(
        calories: calories,
        proteinG: proteinG,
        carbsG: carbsG,
        fatG: fatG,
        saturatedFatG: saturatedFatG,
        monounsaturatedFatG: monounsaturatedFatG,
        polyunsaturatedFatG: polyunsaturatedFatG,
        transFatG: transFatG,
        fiberG: fiberG,
        sugarsG: sugarsG,
        sodiumMg: sodiumMg,
        potassiumMg: potassiumMg,
        calciumMg: calciumMg,
        ironMg: ironMg,
        magnesiumMg: magnesiumMg,
        zincMg: zincMg,
        vitaminAUg: vitaminAUg,
        vitaminCMg: vitaminCMg,
        vitaminDUg: vitaminDUg,
        vitaminB12Ug: vitaminB12Ug,
      ),
      byIndex: byIndex,
    );
  }
}

/// Resolves the precise serving selected for a saved-meal ingredient.
///
/// New rows carry both a label and an equivalence snapshot. The current
/// library serving wins when its label still exists, keeping saved-meal
/// totals live. The snapshot is the safe fallback when the serving was
/// edited or deleted. Legacy rows are used only when their old unit match
/// identifies exactly one serving; choosing the first of several would
/// silently calculate the wrong calories and macros.
FoodServing? _resolveSavedMealServing({
  required List<FoodServing> servings,
  required String variantId,
  required String unit,
  String? servingLabel,
  double? gramsEquivalent,
  double? mlEquivalent,
}) {
  final normalizedUnit = NutritionConversion.normalizeUnit(unit);
  if (normalizedUnit != 'serving' && normalizedUnit != 'unit') return null;

  if (servingLabel != null && servingLabel.isNotEmpty) {
    final byLabel = servings.where((s) => s.label == servingLabel);
    if (byLabel.isNotEmpty) return byLabel.first;
  }

  if (gramsEquivalent != null || mlEquivalent != null) {
    final byEquivalence = servings.where(
      (s) =>
          _sameNullableDouble(s.gramsEquivalent, gramsEquivalent) &&
          _sameNullableDouble(s.mlEquivalent, mlEquivalent),
    );
    if (byEquivalence.isNotEmpty) return byEquivalence.first;

    return FoodServing(
      id: 'saved-meal-snapshot',
      foodVariantId: variantId,
      label: servingLabel ?? unit,
      unit: unit,
      gramsEquivalent: gramsEquivalent,
      mlEquivalent: mlEquivalent,
    );
  }

  final legacyMatches = servings
      .where((s) => s.label == unit || s.unit == unit)
      .toList();
  if (legacyMatches.length == 1) return legacyMatches.first;
  // Items saved from older meal logs carry only the generic `serving`
  // unit (no label, no equivalence). When the variant defines exactly
  // one portion there is nothing ambiguous to pick.
  return servings.length == 1 ? servings.first : null;
}

bool _sameNullableDouble(double? a, double? b) {
  if (a == null || b == null) return a == b;
  return (a - b).abs() < 0.000001;
}

/// Variants and their servings, loaded together for saved-meal maths.
class _VariantContext {
  final Map<String, FoodVariant> variants;
  final Map<String, List<FoodServing>> servingsByVariant;

  const _VariantContext(this.variants, this.servingsByVariant);
}
