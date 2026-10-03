part of 'nutrition_repository.dart';

/// The single active nutrition goal.
extension NutritionRepositoryGoals on NutritionRepository {
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
  ///
  /// Two equivalent entry points exist:
  /// * **Direct**: pass [calories] / [proteinG] / [carbsG] / [fatG] (the
  ///   daily consumption goal). [tdee] and the adjustment are left
  ///   untouched.
  /// * **TDEE-driven**: pass [tdee] + [adjustmentKind] +
  ///   [adjustmentPercent]. The goal calories are derived from them
  ///   (`calories = tdee × (1 + adjustmentPercent / 100)`) and stored
  ///   alongside the inputs so every consumer (dashboard, progress,
  ///   AI) keeps reading the same `calories` field.
  ///
  /// At least one positive value must be supplied, otherwise the call
  /// throws `goal_empty`.
  Future<NutritionGoal> saveGoal({
    double? calories,
    double? proteinG,
    double? carbsG,
    double? fatG,
    double? tdee,
    String? adjustmentKind,
    double? adjustmentPercent,
  }) async {
    final db = await this.db;
    return db.transaction(
      (txn) => saveGoalIn(
        txn,
        calories: calories,
        proteinG: proteinG,
        carbsG: carbsG,
        fatG: fatG,
        tdee: tdee,
        adjustmentKind: adjustmentKind,
        adjustmentPercent: adjustmentPercent,
      ),
    );
  }

  /// [saveGoal] on an explicit executor, so callers can fold it into their own
  /// transaction. A caller-supplied [id] becomes the primary key (a repeated
  /// call with the same id fails instead of storing a second goal).
  Future<NutritionGoal> saveGoalIn(
    DatabaseExecutor executor, {
    String? id,
    double? calories,
    double? proteinG,
    double? carbsG,
    double? fatG,
    double? tdee,
    String? adjustmentKind,
    double? adjustmentPercent,
  }) async {
    // Derive the goal calories from TDEE + adjustment when the caller
    // configured the goal via the new TDEE-driven flow.
    final tdeeDriven = tdee != null && tdee > 0 && adjustmentPercent != null;
    final derivedCalories = tdeeDriven
        ? tdee * (1 + adjustmentPercent / 100)
        : null;
    final resolvedCalories = calories ?? derivedCalories;

    if ((resolvedCalories ?? 0) <= 0 &&
        (proteinG ?? 0) <= 0 &&
        (carbsG ?? 0) <= 0 &&
        (fatG ?? 0) <= 0) {
      throw const NutritionValidationException('goal_empty');
    }
    for (final pair in <(String, double?)>[
      ('calories', resolvedCalories),
      ('protein_g', proteinG),
      ('carbs_g', carbsG),
      ('fat_g', fatG),
      ('tdee', tdee),
    ]) {
      final v = pair.$2;
      if (v == null) continue;
      if (v.isNaN || v.isInfinite || v < 0) {
        throw NutritionValidationException('goal_invalid_${pair.$1}');
      }
    }
    // A deficit adjustment is negative by design, so it only needs a sane
    // band rather than the non-negative rule above.
    final percent = adjustmentPercent;
    if (percent != null &&
        (percent.isNaN ||
            percent.isInfinite ||
            percent <= -100 ||
            percent >= 100)) {
      throw const NutritionValidationException(
        'goal_invalid_adjustment_percent',
      );
    }
    final now = DateTime.now();
    final goal = NutritionGoal(
      id: id ?? _uuid.v4(),
      calories: resolvedCalories,
      proteinG: proteinG,
      carbsG: carbsG,
      fatG: fatG,
      tdee: tdee,
      adjustmentKind: adjustmentKind,
      adjustmentPercent: adjustmentPercent,
      createdAt: now,
      updatedAt: now,
      isActive: true,
    );
    await executor.update('nutrition_goals', {
      'is_active': 0,
    }, where: 'is_active = 1');
    await executor.insert('nutrition_goals', goal.toMap());
    return goal;
  }

  /// [getActiveGoal] on an explicit executor.
  Future<NutritionGoal?> getActiveGoalIn(DatabaseExecutor executor) async {
    final rows = await executor.query(
      'nutrition_goals',
      where: 'is_active = 1',
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : NutritionGoal.fromMap(rows.first);
  }

  /// Removes the active goal, leaving the user without a target.
  Future<void> clearActiveGoal() async {
    final db = await this.db;
    await db.update('nutrition_goals', {
      'is_active': 0,
    }, where: 'is_active = 1');
  }
}
