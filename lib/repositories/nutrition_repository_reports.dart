part of 'nutrition_repository.dart';

/// Daily summaries and the rows behind the CSV export.
extension NutritionRepositoryReports on NutritionRepository {
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
        SUM(saturated_fat_g) as saturated_fat_g,
        SUM(monounsaturated_fat_g) as monounsaturated_fat_g,
        SUM(polyunsaturated_fat_g) as polyunsaturated_fat_g,
        SUM(trans_fat_g) as trans_fat_g,
        SUM(fiber_g) as fiber_g,
        SUM(sugars_g) as sugars_g,
        SUM(sodium_mg) as sodium_mg,
        SUM(potassium_mg) as potassium_mg,
        SUM(calcium_mg) as calcium_mg,
        SUM(iron_mg) as iron_mg,
        SUM(magnesium_mg) as magnesium_mg,
        SUM(zinc_mg) as zinc_mg,
        SUM(vitamin_a_ug) as vitamin_a_ug,
        SUM(vitamin_c_mg) as vitamin_c_mg,
        SUM(vitamin_d_ug) as vitamin_d_ug,
        SUM(vitamin_b12_ug) as vitamin_b12_ug
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
      saturatedFatG: _sum(row['saturated_fat_g']),
      monounsaturatedFatG: _sum(row['monounsaturated_fat_g']),
      polyunsaturatedFatG: _sum(row['polyunsaturated_fat_g']),
      transFatG: _sum(row['trans_fat_g']),
      fiberG: _sum(row['fiber_g']),
      sugarsG: _sum(row['sugars_g']),
      sodiumMg: _sum(row['sodium_mg']),
      potassiumMg: _sum(row['potassium_mg']),
      calciumMg: _sum(row['calcium_mg']),
      ironMg: _sum(row['iron_mg']),
      magnesiumMg: _sum(row['magnesium_mg']),
      zincMg: _sum(row['zinc_mg']),
      vitaminAUg: _sum(row['vitamin_a_ug']),
      vitaminCMg: _sum(row['vitamin_c_mg']),
      vitaminDUg: _sum(row['vitamin_d_ug']),
      vitaminB12Ug: _sum(row['vitamin_b12_ug']),
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
          mli.sodium_mg IS NULL OR mli.potassium_mg IS NULL OR
          mli.calcium_mg IS NULL OR mli.iron_mg IS NULL OR
          mli.magnesium_mg IS NULL OR mli.zinc_mg IS NULL OR
          mli.vitamin_a_ug IS NULL OR mli.vitamin_c_mg IS NULL OR
          mli.vitamin_d_ug IS NULL OR mli.vitamin_b12_ug IS NULL
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

  Future<List<Map<String, dynamic>>> getDailyNutritionHistoryForRange({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final db = await this.db;
    final start = dateKey(startDate);
    final end = dateKey(endDate);
    final rows = await db.rawQuery(
      '''
      SELECT ml.date as date,
        SUM(mli.calories) as calories,
        SUM(mli.protein_g) as protein_g,
        SUM(mli.carbs_g) as carbs_g,
        SUM(mli.fat_g) as fat_g,
        SUM(mli.saturated_fat_g) as saturated_fat_g,
        SUM(mli.monounsaturated_fat_g) as monounsaturated_fat_g,
        SUM(mli.polyunsaturated_fat_g) as polyunsaturated_fat_g,
        SUM(mli.trans_fat_g) as trans_fat_g,
        SUM(mli.fiber_g) as fiber_g,
        SUM(mli.sugars_g) as sugars_g,
        SUM(mli.sodium_mg) as sodium_mg,
        SUM(mli.potassium_mg) as potassium_mg,
        SUM(mli.calcium_mg) as calcium_mg,
        SUM(mli.iron_mg) as iron_mg,
        SUM(mli.magnesium_mg) as magnesium_mg,
        SUM(mli.zinc_mg) as zinc_mg,
        SUM(mli.vitamin_a_ug) as vitamin_a_ug,
        SUM(mli.vitamin_c_mg) as vitamin_c_mg,
        SUM(mli.vitamin_d_ug) as vitamin_d_ug,
        SUM(mli.vitamin_b12_ug) as vitamin_b12_ug
      FROM meal_log_items mli
      JOIN meal_logs ml ON mli.meal_log_id = ml.id
      WHERE ml.date BETWEEN ? AND ?
      GROUP BY ml.date
      ORDER BY ml.date ASC
      ''',
      [start, end],
    );
    return rows;
  }

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
      args.add(dateKey(startDate));
    }
    if (endDate != null) {
      where.add('ml.date <= ?');
      args.add(dateKey(endDate));
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
        mli.saturated_fat_g as saturated_fat_g,
        mli.monounsaturated_fat_g as monounsaturated_fat_g,
        mli.polyunsaturated_fat_g as polyunsaturated_fat_g,
        mli.trans_fat_g as trans_fat_g,
        mli.fiber_g as fiber_g,
        mli.sugars_g as sugars_g,
        mli.sodium_mg as sodium_mg,
        mli.potassium_mg as potassium_mg,
        mli.calcium_mg as calcium_mg,
        mli.iron_mg as iron_mg,
        mli.magnesium_mg as magnesium_mg,
        mli.zinc_mg as zinc_mg,
        mli.vitamin_a_ug as vitamin_a_ug,
        mli.vitamin_c_mg as vitamin_c_mg,
        mli.vitamin_d_ug as vitamin_d_ug,
        mli.vitamin_b12_ug as vitamin_b12_ug,
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
}
