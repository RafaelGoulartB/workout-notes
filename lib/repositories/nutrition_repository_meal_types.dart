part of 'nutrition_repository.dart';

/// Meal type catalog (managed in the nutrition settings).
extension NutritionRepositoryMealTypes on NutritionRepository {
  /// All configured meal types, in display order. The four legacy keys
  /// are seeded with `name` null and resolve to localized labels.
  Future<List<MealTypeDefinition>> getMealTypes() async {
    final db = await this.db;
    final rows = await db.query('meal_types', orderBy: 'order_index ASC');
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
    final count =
        Sqflite.firstIntValue(
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

  /// The meal type with [key] (the stable id stored in meal logs), or null.
  Future<MealTypeDefinition?> getMealTypeByKeyIn(
    DatabaseExecutor executor,
    String key,
  ) async {
    final rows = await executor.query(
      'meal_types',
      where: '"key" = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : MealTypeDefinition.fromMap(rows.first);
  }
}
