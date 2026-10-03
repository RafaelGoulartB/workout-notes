part of 'nutrition_repository.dart';

/// Meal logs and their items: creation, editing, copying and day reads.
extension NutritionRepositoryMealLogs on NutritionRepository {
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
      final item = _buildMealLogItem(
        log: log,
        food: food,
        variant: variant,
        conversion: conversion,
        availableServings: availableServings,
      );
      await txn.insert('meal_log_items', item.toMap());
      await _touchFoods(txn, [food.id], item.createdAt);
      return item;
    });
  }

  /// Builds the meal-log row (with its nutrition snapshot) for logging
  /// [conversion] of [variant] into [log]. Pure: nothing is written.
  MealLogItem _buildMealLogItem({
    required MealLog log,
    required Food food,
    required FoodVariant variant,
    required NutritionConversion conversion,
    required List<FoodServing> availableServings,
    String? id,
  }) {
    final consumed = conversion.apply(variant.values);
    // The conversion already carries the exact serving chosen in the
    // quantity sheet. Looking it up by the generic `serving` unit is
    // ambiguous when a food defines more than one portion.
    final serving =
        conversion.serving ??
        availableServings.firstWhereOrNull(
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
      id: id ?? _uuid.v4(),
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
      saturatedFatG: consumed.saturatedFatG,
      monounsaturatedFatG: consumed.monounsaturatedFatG,
      polyunsaturatedFatG: consumed.polyunsaturatedFatG,
      transFatG: consumed.transFatG,
      fiberG: consumed.fiberG,
      sugarsG: consumed.sugarsG,
      sodiumMg: consumed.sodiumMg,
      potassiumMg: consumed.potassiumMg,
      calciumMg: consumed.calciumMg,
      ironMg: consumed.ironMg,
      magnesiumMg: consumed.magnesiumMg,
      zincMg: consumed.zincMg,
      vitaminAUg: consumed.vitaminAUg,
      vitaminCMg: consumed.vitaminCMg,
      vitaminDUg: consumed.vitaminDUg,
      vitaminB12Ug: consumed.vitaminB12Ug,
      snapshotJson: snapshot.encode(),
      createdAt: DateTime.now(),
    );
    return item;
  }

  /// Marks foods as recently used with one statement. Empty ids (foods that
  /// were never persisted) are ignored.
  Future<void> _touchFoods(
    DatabaseExecutor executor,
    Iterable<String> foodIds,
    DateTime usedAt,
  ) async {
    final ids = foodIds.where((id) => id.isNotEmpty).toSet().toList();
    if (ids.isEmpty) return;
    await executor.rawUpdate(
      'UPDATE foods SET last_used_at = ? '
      'WHERE id IN (${List.filled(ids.length, '?').join(', ')})',
      [usedAt.toIso8601String(), ...ids],
    );
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
      saturatedFatG: consumed.saturatedFatG,
      monounsaturatedFatG: consumed.monounsaturatedFatG,
      polyunsaturatedFatG: consumed.polyunsaturatedFatG,
      transFatG: consumed.transFatG,
      fiberG: consumed.fiberG,
      sugarsG: consumed.sugarsG,
      sodiumMg: consumed.sodiumMg,
      potassiumMg: consumed.potassiumMg,
      calciumMg: consumed.calciumMg,
      ironMg: consumed.ironMg,
      magnesiumMg: consumed.magnesiumMg,
      zincMg: consumed.zincMg,
      vitaminAUg: consumed.vitaminAUg,
      vitaminCMg: consumed.vitaminCMg,
      vitaminDUg: consumed.vitaminDUg,
      vitaminB12Ug: consumed.vitaminB12Ug,
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
      saturatedFatG: updated.saturatedFatG,
      monounsaturatedFatG: updated.monounsaturatedFatG,
      polyunsaturatedFatG: updated.polyunsaturatedFatG,
      transFatG: updated.transFatG,
      fiberG: updated.fiberG,
      sugarsG: updated.sugarsG,
      sodiumMg: updated.sodiumMg,
      potassiumMg: updated.potassiumMg,
      calciumMg: updated.calciumMg,
      ironMg: updated.ironMg,
      magnesiumMg: updated.magnesiumMg,
      zincMg: updated.zincMg,
      vitaminAUg: updated.vitaminAUg,
      vitaminCMg: updated.vitaminCMg,
      vitaminDUg: updated.vitaminDUg,
      vitaminB12Ug: updated.vitaminB12Ug,
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
    await db.transaction(
      (txn) => _copyItemsToMealIn(
        txn,
        date: date,
        mealType: mealType,
        name: name,
        items: items,
        createdAt: now,
      ),
    );
    return items.length;
  }

  /// Replicates every meal with items from [sourceDate] into each distinct
  /// date in [targetDates]. Existing items are preserved and the copied
  /// items are appended, matching [copyItemsToMeal]. All target dates are
  /// handled in one transaction so a partial replication cannot be saved.
  /// Returns the number of target dates that received the day.
  Future<int> replicateDayToDates({
    required String sourceDate,
    required Iterable<String> targetDates,
  }) async {
    _validateDate(sourceDate);
    final dates = <String>{};
    for (final date in targetDates) {
      _validateDate(date);
      if (date != sourceDate) dates.add(date);
    }
    if (dates.isEmpty) return 0;

    final db = await this.db;
    return db.transaction((txn) async {
      final sourceLogs = await txn.query(
        'meal_logs',
        where: 'date = ?',
        whereArgs: [sourceDate],
        orderBy: 'created_at ASC',
      );
      final sourceMeals = <MealLogWithItems>[];
      for (final row in sourceLogs) {
        final log = MealLog.fromMap(row);
        final itemRows = await txn.query(
          'meal_log_items',
          where: 'meal_log_id = ?',
          whereArgs: [log.id],
          orderBy: 'created_at ASC',
        );
        final items = itemRows.map(MealLogItem.fromMap).toList();
        if (items.isNotEmpty) {
          sourceMeals.add(MealLogWithItems(log: log, items: items));
        }
      }
      if (sourceMeals.isEmpty) return 0;

      final now = DateTime.now();
      for (final date in dates) {
        for (final meal in sourceMeals) {
          await _copyItemsToMealIn(
            txn,
            date: date,
            mealType: meal.log.mealType,
            name: meal.log.name,
            items: meal.items,
            createdAt: now,
          );
        }
      }
      return dates.length;
    });
  }

  Future<int> _copyItemsToMealIn(
    DatabaseExecutor executor, {
    required String date,
    required String mealType,
    required List<MealLogItem> items,
    required DateTime createdAt,
    String? name,
  }) async {
    final log = await _ensureMealLogIn(
      executor,
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
        saturatedFatG: item.saturatedFatG,
        monounsaturatedFatG: item.monounsaturatedFatG,
        polyunsaturatedFatG: item.polyunsaturatedFatG,
        transFatG: item.transFatG,
        fiberG: item.fiberG,
        sugarsG: item.sugarsG,
        sodiumMg: item.sodiumMg,
        potassiumMg: item.potassiumMg,
        calciumMg: item.calciumMg,
        ironMg: item.ironMg,
        magnesiumMg: item.magnesiumMg,
        zincMg: item.zincMg,
        vitaminAUg: item.vitaminAUg,
        vitaminCMg: item.vitaminCMg,
        vitaminDUg: item.vitaminDUg,
        vitaminB12Ug: item.vitaminB12Ug,
        snapshotJson: item.snapshotJson,
        createdAt: createdAt,
      );
      await executor.insert('meal_log_items', clone.toMap());
      if (item.foodId != null) touchedFoods.add(item.foodId!);
    }
    await _touchFoods(executor, touchedFoods, createdAt);
    return items.length;
  }

  /// Returns all meal logs and their items for the given day, with two
  /// queries however many sections the day has.
  Future<List<MealLogWithItems>> getDayMeals(String date) async {
    _validateDate(date);
    final db = await this.db;
    final logs = (await db.query(
      'meal_logs',
      where: 'date = ?',
      whereArgs: [date],
    )).map(MealLog.fromMap).toList();
    if (logs.isEmpty) return const [];
    final itemRows = await _selectIn(db, 'meal_log_items', 'meal_log_id', [
      for (final log in logs) log.id,
    ], orderBy: 'created_at ASC');
    final itemsByLog = <String, List<MealLogItem>>{};
    for (final row in itemRows) {
      final item = MealLogItem.fromMap(row);
      itemsByLog.putIfAbsent(item.mealLogId, () => []).add(item);
    }
    final result = [
      for (final log in logs)
        MealLogWithItems(log: log, items: itemsByLog[log.id] ?? const []),
    ];
    // Order by creation so sections appear in the order they were
    // added to the day (custom meal sections have no fixed order).
    result.sort((a, b) {
      final byTime = a.log.createdAt.compareTo(b.log.createdAt);
      if (byTime != 0) return byTime;
      return a.log.id.compareTo(b.log.id);
    });
    return result;
  }

  /// Logs [entries] into the (date, mealType) section on [executor]: the
  /// section is created when missing and every item gets its nutrition
  /// snapshot. [itemIdFor] derives the primary key of the n-th item.
  Future<List<MealLogItem>> addMealLogItemsIn(
    DatabaseExecutor executor, {
    required String date,
    required String mealType,
    String? mealName,
    required List<MealLogEntryDraft> entries,
    String Function(int index)? itemIdFor,
  }) async {
    _validateDate(date);
    final section = await _ensureMealLogIn(
      executor,
      date: date,
      mealType: mealType,
      name: mealName,
    );
    final items = <MealLogItem>[];
    final batch = executor.batch();
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final item = _buildMealLogItem(
        log: section,
        food: entry.food,
        variant: entry.variant,
        conversion: entry.conversion,
        availableServings: entry.servings,
        id: itemIdFor?.call(i),
      );
      batch.insert('meal_log_items', item.toMap());
      items.add(item);
    }
    await batch.commit(noResult: true);
    await _touchFoods(executor, [
      for (final entry in entries) entry.food.id,
    ], DateTime.now());
    return items;
  }
}
