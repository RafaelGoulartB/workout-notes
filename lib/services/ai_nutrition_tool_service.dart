// Read-only queries built for the AI Coach may run SQL directly (a documented
// exception to the repository-only rule); writes never happen in this file.
import 'dart:convert';

import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/models/nutrition/food.dart';
import 'package:workout_notes/models/nutrition/nutrition_values.dart';
import 'package:workout_notes/models/nutrition/saved_meal.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';
import 'package:workout_notes/services/ai_tool_math.dart';
import 'package:workout_notes/services/ai_tool_spec.dart';
import 'package:workout_notes/services/effective_nutrition_goal_service.dart';
import 'package:workout_notes/utils/date_utils.dart';

/// Read-only nutrition queries exposed to the AI Coach.
///
/// Four tools cover the domain: a ranged report (`nutrition`), one diary day,
/// the food library and the saved meals. Nutrient keys keep their database
/// column names. A nutrient that was not reported is absent from a result,
/// never zero, and averages only use the days (or items) that reported it.
class AiNutritionToolService {
  final DatabaseHelper db;
  final NutritionRepository nutritionRepository;
  final PeriodizationRepository periodizationRepository;
  final DateTime Function() _now;

  AiNutritionToolService({
    DatabaseHelper? db,
    NutritionRepository? nutritionRepository,
    PeriodizationRepository? periodizationRepository,
    DateTime Function()? now,
  }) : db = db ?? DatabaseHelper.instance,
       nutritionRepository =
           nutritionRepository ?? DatabaseHelper.instance.nutritionRepo,
       periodizationRepository =
           periodizationRepository ?? DatabaseHelper.instance.periodizationRepo,
       _now = now ?? DateTime.now;

  /// Allowed values of the `detail` argument of [nutrition].
  static const details = ['summary', 'daily', 'micros', 'foods'];

  // -------------------------------------------------------------------------
  // get_nutrition
  // -------------------------------------------------------------------------

  /// Intake over a window ending at [endDate] (default today, never later
  /// than today). [detail] picks the view: `summary`, `daily`, `micros` or
  /// `foods`.
  Future<Map<String, dynamic>> nutrition({
    int? days,
    String? startDate,
    String? endDate,
    String detail = 'summary',
  }) async {
    if (!details.contains(detail)) {
      throw AiToolArgException.invalid(
        'detail',
        'one of ${details.join(', ')}',
        detail,
      );
    }
    final window = _window(days: days, startDate: startDate, endDate: endDate);
    final applied = {...window.toApplied(), 'detail': detail};
    final body = switch (detail) {
      'daily' => await _daily(window),
      'micros' => await _micros(window),
      'foods' => await _foods(window),
      _ => await _summary(window),
    };
    return {'applied': applied, ...body};
  }

  AiDateWindow _window({int? days, String? startDate, String? endDate}) {
    final today = dayOf(_now());
    final window = AiToolMath.window(
      today: today,
      days: days,
      startDate: _checkedDate('start_date', startDate),
      endDate: _checkedDate('end_date', endDate),
      defaultDays: 14,
      maxDays: 90,
    );
    // Days after today cannot have been eaten: never look past today.
    if (!window.end.isAfter(today)) return window;
    final start = window.start.isAfter(today) ? today : window.start;
    return AiDateWindow(start, today, capped: true);
  }

  Future<Map<String, dynamic>> _summary(AiDateWindow window) async {
    final all = await _dailyTotals(window.startKey, window.endKey);
    final goal = await effectiveGoal(window.end);
    // Today is usually only half logged: leave it out of the averages when
    // there are other days to average.
    final todayKey = dateKey(dayOf(_now()));
    final daily = all.length > 1
        ? all.where((row) => row['date'] != todayKey).toList()
        : all;
    final todayLeftOut = daily.length != all.length;
    final result = <String, dynamic>{
      'logged_days': all.length,
      'coverage_pct': all.length / window.days * 100,
      'today_excluded_from_averages': todayLeftOut ? true : null,
    };
    final incompleteDays = daily.where((row) => row['incomplete'] == 1).length;
    if (daily.isNotEmpty) result['incomplete_days'] = incompleteDays;
    if (goal != null) result['goal'] = goal;
    if (daily.isEmpty) return result;

    final averages = <String, dynamic>{};
    for (final key in _summaryNutrients) {
      final values = _reported(daily, key);
      if (values.isNotEmpty) averages[key] = AiToolMath.average(values);
    }
    result['averages'] = averages;
    if (goal != null) {
      // The target can change from day to day (training vs rest day, phase
      // week): compare with the mean of the targets of the days averaged.
      final targets = <String, List<double>>{};
      for (final row in daily) {
        final dayGoal = await effectiveGoal(DateTime.parse(row['date'] as String));
        if (dayGoal == null) continue;
        for (final (key, _) in _goalNutrients) {
          final value = (dayGoal[key] as num?)?.toDouble();
          if (value != null && value > 0) {
            targets.putIfAbsent(key, () => []).add(value);
          }
        }
      }
      for (final (key, label) in _goalNutrients) {
        final target = AiToolMath.average(targets[key] ?? const <double>[]);
        final average = averages[key] as double?;
        if (target == null || average == null) continue;
        result['${label}_vs_goal_pct'] = average / target * 100;
      }
    }
    final mealEnd = todayLeftOut
        ? dateKey(addDays(window.end, -1))
        : window.endKey;
    final meals = await _caloriesByMealType(window.startKey, mealEnd);
    final total = meals.fold<double>(0, (sum, meal) => sum + meal.calories);
    result['calories_by_meal'] = [
      for (final meal in meals)
        _compact({
          'meal_type': meal.mealType,
          'name': meal.name,
          'calories': meal.calories / daily.length,
          'share_pct': total > 0 ? meal.calories / total * 100 : null,
        }),
    ];
    return result;
  }

  Future<Map<String, dynamic>> _daily(AiDateWindow window) async {
    final daily = await _dailyTotals(window.startKey, window.endKey);
    final goal = await effectiveGoal(window.end);
    return {
      'logged_days': daily.length,
      'goal': ?goal,
      'days': [
        for (final row in daily)
          _compact({
            'date': row['date'],
            'items': row['items'],
            for (final key in _dailyNutrients) key: row[key],
            if (row['incomplete'] == 1) 'incomplete': true,
          }),
      ],
    };
  }

  Future<Map<String, dynamic>> _micros(AiDateWindow window) async {
    final daily = await _dailyTotals(window.startKey, window.endKey);
    final sources = await _microSources(window.startKey, window.endKey);
    return {
      'logged_days': daily.length,
      'nutrients': [
        for (final (key, unit) in _microNutrients)
          _microRow(key, unit, daily, sources[key] ?? const []),
      ],
    };
  }

  Map<String, dynamic> _microRow(
    String key,
    String unit,
    List<Map<String, Object?>> daily,
    List<({String name, double total})> sources,
  ) {
    final values = _reported(daily, key);
    return _compact({
      'nutrient': key,
      'unit': unit,
      'avg_on_reported_days': AiToolMath.average(values),
      'min': AiToolMath.minimum(values),
      'max': AiToolMath.maximum(values),
      'reported_days': values.length,
      'coverage_pct': daily.isEmpty ? 0.0 : values.length / daily.length * 100,
      'top_foods': sources.isEmpty
          ? null
          : sources
                .map((source) => '${source.name} (${_short(source.total)})')
                .join('; '),
    });
  }

  Future<Map<String, dynamic>> _foods(AiDateWindow window) async {
    final database = await db.database;
    final meals = await _caloriesByMealType(window.startKey, window.endKey);
    final total = meals.fold<double>(0, (sum, meal) => sum + meal.calories);
    final rows = await database.rawQuery(
      '''
      SELECT mli.food_name_snapshot AS name, mli.brand_snapshot AS brand,
        COUNT(*) AS times_logged, SUM(mli.calories) AS calories,
        SUM(mli.protein_g) AS protein_g
      FROM meal_log_items mli
      JOIN meal_logs ml ON ml.id = mli.meal_log_id
      WHERE ml.date >= ? AND ml.date <= ? AND mli.calories IS NOT NULL
      GROUP BY mli.food_name_snapshot, mli.brand_snapshot
      ORDER BY calories DESC, name ASC
      LIMIT 10
      ''',
      [window.startKey, window.endKey],
    );
    return {
      if (total > 0) 'total_calories': total,
      'top_foods': [
        for (final row in rows)
          _compact({
            'name': row['name'],
            'brand': row['brand'],
            'times_logged': row['times_logged'],
            'calories': row['calories'],
            'share_pct': total > 0
                ? ((row['calories'] as num).toDouble() / total * 100)
                : null,
            'protein_g': row['protein_g'],
          }),
      ],
      'calories_by_meal': [
        for (final meal in meals)
          _compact({
            'meal_type': meal.mealType,
            'name': meal.name,
            'calories': meal.calories,
            'share_pct': total > 0 ? meal.calories / total * 100 : null,
          }),
      ],
    };
  }

  // -------------------------------------------------------------------------
  // get_nutrition (detail: day)
  // -------------------------------------------------------------------------

  /// One diary day: meals with their items, day totals, the goal and what is
  /// left of it. An empty day is a normal result with no meals.
  Future<Map<String, dynamic>> diaryDay({String? date}) async {
    final key = _checkedDate('date', date) ?? dateKey(_now());
    final database = await db.database;
    final mealRows = await database.rawQuery(
      '''
      SELECT ml.id AS id, ml.meal_type AS meal_type, ml.name AS name,
        ml.notes AS notes, SUM(mli.calories) AS calories
      FROM meal_logs ml
      JOIN meal_log_items mli ON mli.meal_log_id = ml.id
      WHERE ml.date = ?
      GROUP BY ml.id
      ORDER BY ml.created_at ASC, ml.id ASC
      ''',
      [key],
    );
    final itemRows = await database.rawQuery(
      '''
      SELECT mli.* FROM meal_log_items mli
      JOIN meal_logs ml ON ml.id = mli.meal_log_id
      WHERE ml.date = ?
      ORDER BY ml.created_at ASC, ml.id ASC, mli.created_at ASC, mli.id ASC
      ''',
      [key],
    );
    final itemsByMeal = <String, List<Map<String, dynamic>>>{};
    final missing = <String, int>{};
    for (final row in itemRows) {
      itemsByMeal
          .putIfAbsent(row['meal_log_id'] as String, () => [])
          .add(_diaryItem(row));
      for (final nutrient in _allNutrients) {
        if (row[nutrient] == null) {
          missing[nutrient] = (missing[nutrient] ?? 0) + 1;
        }
      }
    }
    final totalsRow = (await _dailyTotals(key, key)).firstOrNull;
    final totals = <String, Object?>{
      if (totalsRow != null)
        for (final nutrient in _allNutrients) nutrient: totalsRow[nutrient],
    };
    final goal = await effectiveGoal(DateTime.parse(key));
    final remaining = <String, dynamic>{};
    if (goal != null) {
      for (final (nutrient, _) in _goalNutrients) {
        final target = (goal[nutrient] as num?)?.toDouble();
        if (target == null) continue;
        // Nothing logged means nothing eaten; an unreported nutrient on a
        // logged day stays unknown instead of counting as zero.
        final eaten =
            (totals[nutrient] as num?)?.toDouble() ??
            (itemRows.isEmpty ? 0.0 : null);
        if (eaten != null) remaining[nutrient] = target - eaten;
      }
    }
    return {
      'date': key,
      'item_count': itemRows.length,
      'meals': [
        for (final meal in mealRows)
          _compact({
            'meal_type': meal['meal_type'],
            'name': meal['name'],
            'notes': meal['notes'],
            'calories': meal['calories'],
            'items': itemsByMeal[meal['id']] ?? const [],
          }),
      ],
      'totals': _compact(totals),
      'goal': ?goal,
      if (remaining.isNotEmpty) 'remaining': remaining,
      if (missing.isNotEmpty) 'items_missing_nutrient': missing,
    };
  }

  Map<String, dynamic> _diaryItem(Map<String, Object?> row) {
    Map<dynamic, dynamic>? snapshot;
    try {
      final raw = jsonDecode(row['nutrition_snapshot_json'] as String);
      if (raw is Map) snapshot = raw;
    } catch (_) {
      // An unreadable snapshot only loses the two flags below.
    }
    final coreMissing = _coreMacros.any((key) => row[key] == null);
    return _compact({
      'name': row['food_name_snapshot'],
      'brand': row['brand_snapshot'],
      'quantity': row['quantity'],
      'unit': row['unit'],
      'calories': row['calories'],
      'protein_g': row['protein_g'],
      'carbs_g': row['carbs_g'],
      'fat_g': row['fat_g'],
      if (snapshot?['is_estimated'] == true) 'estimated': true,
      if (snapshot?['has_missing_values'] == true || coreMissing)
        'has_missing_values': true,
    });
  }

  // -------------------------------------------------------------------------
  // search_food_library
  // -------------------------------------------------------------------------

  /// Food library rows, or the full detail of [foodId] when given.
  Future<Map<String, dynamic>> searchFoods({
    String? query,
    bool favoritesOnly = false,
    bool recentOnly = false,
    int limit = 10,
    String? foodId,
  }) async {
    if (foodId != null) return _foodDetail(foodId);
    limit = limit.clamp(1, 30);
    final database = await db.database;
    final where = <String>[];
    final args = <Object?>[];
    final normalized = Food.normalizeForSearch(query?.trim() ?? '');
    if (normalized.isNotEmpty) {
      where.add(
        "(f.search_name LIKE ? OR LOWER(COALESCE(f.brand, '')) LIKE ?)",
      );
      args.addAll(['%$normalized%', '%$normalized%']);
    }
    if (favoritesOnly) where.add('f.is_favorite = 1');
    if (recentOnly) where.add('f.last_used_at IS NOT NULL');
    final order = recentOnly
        ? 'f.last_used_at DESC, f.name COLLATE NOCASE ASC'
        : '''f.is_favorite DESC,
        CASE WHEN f.last_used_at IS NULL THEN 1 ELSE 0 END,
        f.last_used_at DESC, f.name COLLATE NOCASE ASC''';
    final found = await database.rawQuery(
      '''
      SELECT f.* FROM foods f
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      ORDER BY $order
      LIMIT ?
      ''',
      [...args, limit + 1],
    );
    final foods = found.take(limit).toList();
    final variants = await _variantsByFood([
      for (final food in foods) food['id'] as String,
    ]);
    return {
      'has_more': found.length > limit,
      'foods': [
        for (final food in foods)
          _foodRow(food, variants[food['id']] ?? const []),
      ],
    };
  }

  Map<String, dynamic> _foodRow(
    Map<String, Object?> food,
    List<Map<String, Object?>> variants,
  ) {
    // The variant the app lists first: measured before estimated, smallest
    // reference amount first.
    final primary = variants.isEmpty ? null : variants.first;
    return _compact({
      'id': food['id'],
      'name': food['name'],
      'brand': food['brand'],
      'source': food['source'],
      'is_favorite': food['is_favorite'] == 1,
      'last_used_at': food['last_used_at'],
      'reference_amount': primary?['reference_amount'],
      'reference_unit': primary?['reference_unit'],
      'calories': primary?['calories'],
      'protein_g': primary?['protein_g'],
      'carbs_g': primary?['carbs_g'],
      'fat_g': primary?['fat_g'],
      'is_estimated': primary == null ? null : primary['is_estimated'] == 1,
      'variant_count': variants.length,
    });
  }

  /// Variants of every food in [foodIds] with one query, primary first.
  Future<Map<String, List<Map<String, Object?>>>> _variantsByFood(
    List<String> foodIds,
  ) async {
    if (foodIds.isEmpty) return const {};
    final database = await db.database;
    final rows = await database.rawQuery('''
      SELECT * FROM food_variants
      WHERE food_id IN (${_marks(foodIds.length)})
      ORDER BY is_estimated ASC, reference_amount ASC, id ASC
      ''', foodIds);
    final byFood = <String, List<Map<String, Object?>>>{};
    for (final row in rows) {
      byFood.putIfAbsent(row['food_id'] as String, () => []).add(row);
    }
    return byFood;
  }

  Future<Map<String, dynamic>> _foodDetail(String foodId) async {
    final database = await db.database;
    final foods = await database.query(
      'foods',
      where: 'id = ?',
      whereArgs: [foodId],
      limit: 1,
    );
    if (foods.isEmpty) {
      throw const AiToolNotFoundException(
        'food not found',
        hint: 'call search_food_library to get valid ids',
      );
    }
    final food = foods.first;
    final variants = (await database.query(
      'food_variants',
      where: 'food_id = ?',
      whereArgs: [foodId],
      orderBy: 'reference_amount ASC, id ASC',
    ));
    final servings = variants.isEmpty
        ? const <Map<String, Object?>>[]
        : await database.rawQuery(
            '''
            SELECT * FROM food_servings
            WHERE food_variant_id IN (${_marks(variants.length)})
            ORDER BY label COLLATE NOCASE ASC
            ''',
            [for (final variant in variants) variant['id']],
          );
    final servingsByVariant = <Object?, List<Map<String, dynamic>>>{};
    for (final serving in servings) {
      servingsByVariant
          .putIfAbsent(serving['food_variant_id'], () => [])
          .add(
            _compact({
              'label': serving['label'],
              'quantity': serving['quantity'],
              'unit': serving['unit'],
              'grams': serving['grams_equivalent'],
              'ml': serving['ml_equivalent'],
            }),
          );
    }
    return _compact({
      'id': food['id'],
      'name': food['name'],
      'brand': food['brand'],
      'barcode': food['barcode'],
      'source': food['source'],
      'is_favorite': food['is_favorite'] == 1,
      'last_used_at': food['last_used_at'],
      'variants': [
        for (final variant in variants)
          _compact({
            'id': variant['id'],
            'label': variant['label'],
            'reference_amount': variant['reference_amount'],
            'reference_unit': variant['reference_unit'],
            'is_estimated': variant['is_estimated'] == 1,
            'nutrients': _nutrientMap(variant),
            'extra_nutrients': _decodeMap(
              variant['extra_nutrients_json'] as String?,
            ),
            'servings': servingsByVariant[variant['id']],
          }),
      ],
    });
  }

  // -------------------------------------------------------------------------
  // list_saved_meals
  // -------------------------------------------------------------------------

  /// Saved meals (newest first), or one with its items when [savedMealId] is
  /// given.
  Future<Map<String, dynamic>> listSavedMeals({
    int limit = 15,
    String? savedMealId,
  }) async {
    if (savedMealId != null) return _savedMealDetail(savedMealId);
    limit = limit.clamp(1, 40);
    // The repository loads items, variants and servings of all meals in
    // batch, so this stays a handful of queries whatever the library size.
    final all = await nutritionRepository.getSavedMeals();
    final sorted = [...all]
      ..sort((a, b) => b.meal.updatedAt.compareTo(a.meal.updatedAt));
    return {
      'total': sorted.length,
      'has_more': sorted.length > limit,
      'saved_meals': [
        for (final entry in sorted.take(limit)) _savedMealRow(entry),
      ],
    };
  }

  Map<String, dynamic> _savedMealRow(SavedMealWithItems entry) {
    final totals = _savedTotals(entry);
    return _compact({
      'id': entry.meal.id,
      'name': entry.meal.name,
      'meal_type': entry.meal.mealType,
      'portions': entry.meal.portions,
      'item_count': entry.items.length,
      for (final key in _coreMacros) key: totals[key],
      'updated_at': entry.meal.updatedAt.toIso8601String(),
    });
  }

  Future<Map<String, dynamic>> _savedMealDetail(String savedMealId) async {
    final entry = await nutritionRepository.getSavedMeal(savedMealId);
    if (entry == null) {
      throw const AiToolNotFoundException(
        'saved meal not found',
        hint: 'call list_saved_meals to get valid ids',
      );
    }
    return _compact({
      'id': entry.meal.id,
      'name': entry.meal.name,
      'meal_type': entry.meal.mealType,
      'portions': entry.meal.portions,
      'updated_at': entry.meal.updatedAt.toIso8601String(),
      'items': [
        for (final item in entry.items)
          _compact({
            'name': item.foodNameSnapshot,
            'brand': item.brandSnapshot,
            'quantity': item.quantity,
            'unit': item.unit,
            'serving_label': item.servingLabel,
            ..._macros(entry.consumedByItem[item.id]),
          }),
      ],
      'totals': _compactOrNull(_savedTotals(entry)),
    });
  }

  // -------------------------------------------------------------------------
  // Shared helpers
  // -------------------------------------------------------------------------

  /// The nutrition goal in effect on [date] (plan-aware), or null when none
  /// is set. `goal_source` says whether it comes from the plan or settings.
  Future<Map<String, dynamic>?> effectiveGoal(DateTime date) async {
    final effective = await EffectiveNutritionGoalService.resolve(
      nutritionRepository: nutritionRepository,
      periodizationRepository: periodizationRepository,
      date: date,
    );
    final goal = effective.goal;
    if (goal == null) return null;
    return _compact({
      'calories': goal.calories,
      'protein_g': goal.proteinG,
      'carbs_g': goal.carbsG,
      'fat_g': goal.fatG,
      'goal_source': effective.fromPlan ? 'plan' : 'settings',
      if (effective.fromPlan) 'phase': effective.phase?.name,
      if (effective.fromPlan) 'week': effective.weekNumber,
      if (effective.fromPlan) 'total_weeks': effective.totalWeeks,
      if (effective.fromPlan && effective.trainingDay != null)
        'day_type': effective.trainingDay! ? 'training' : 'rest',
    });
  }

  /// Per logged day sums of every nutrient, newest first. A nutrient is null
  /// on a day where no item reported it. Days without items are absent.
  Future<List<Map<String, Object?>>> _dailyTotals(
    String start,
    String end,
  ) async {
    final database = await db.database;
    return database.rawQuery(
      '''
      SELECT ml.date AS date, COUNT(*) AS items,
        ${_sumColumns(_allNutrients)},
        MAX(CASE WHEN ${_coreMacros.map((key) => 'mli.$key IS NULL').join(' OR ')}
          THEN 1 ELSE 0 END) AS incomplete
      FROM meal_log_items mli
      JOIN meal_logs ml ON ml.id = mli.meal_log_id
      WHERE ml.date >= ? AND ml.date <= ?
      GROUP BY ml.date
      ORDER BY ml.date DESC
      ''',
      [start, end],
    );
  }

  Future<List<({String mealType, String? name, double calories})>>
  _caloriesByMealType(String start, String end) async {
    final database = await db.database;
    final rows = await database.rawQuery(
      '''
      SELECT ml.meal_type AS meal_type,
        COALESCE(mt.name, MAX(ml.name)) AS name,
        SUM(mli.calories) AS calories
      FROM meal_log_items mli
      JOIN meal_logs ml ON ml.id = mli.meal_log_id
      LEFT JOIN meal_types mt ON mt.key = ml.meal_type
      WHERE ml.date >= ? AND ml.date <= ? AND mli.calories IS NOT NULL
      GROUP BY ml.meal_type
      ORDER BY calories DESC
      ''',
      [start, end],
    );
    return [
      for (final row in rows)
        (
          mealType: row['meal_type'] as String,
          name: row['name'] as String?,
          calories: (row['calories'] as num).toDouble(),
        ),
    ];
  }

  /// Top three foods per micronutrient (largest summed amount first), from a
  /// single query grouped by food.
  Future<Map<String, List<({String name, double total})>>> _microSources(
    String start,
    String end,
  ) async {
    final database = await db.database;
    final keys = [for (final (key, _) in _microNutrients) key];
    final rows = await database.rawQuery(
      '''
      SELECT mli.food_name_snapshot AS name, ${_sumColumns(keys)}
      FROM meal_log_items mli
      JOIN meal_logs ml ON ml.id = mli.meal_log_id
      WHERE ml.date >= ? AND ml.date <= ?
      GROUP BY mli.food_name_snapshot
      ''',
      [start, end],
    );
    return {
      for (final key in keys)
        key: ([
          for (final row in rows)
            if ((row[key] as num?) != null && (row[key] as num) > 0)
              (
                name: row['name'] as String,
                total: (row[key] as num).toDouble(),
              ),
        ]..sort((a, b) => b.total.compareTo(a.total))).take(3).toList(),
    };
  }

  static String _sumColumns(Iterable<String> keys) =>
      keys.map((key) => 'SUM(mli.$key) AS $key').join(', ');

  static String _marks(int count) => List.filled(count, '?').join(', ');

  static String? _checkedDate(String key, String? value) =>
      value == null ? null : AiToolArgs({key: value}).date(key);

  static List<double> _reported(List<Map<String, Object?>> rows, String key) =>
      [
        for (final row in rows)
          if (row[key] is num) (row[key]! as num).toDouble(),
      ];

  /// [map] without its null values ("absent" means "not reported").
  static Map<String, dynamic> _compact(Map<String, Object?> map) => {
    for (final entry in map.entries)
      if (entry.value != null) entry.key: entry.value,
  };

  static Map<String, dynamic> _nutrientMap(Map<String, Object?> row) =>
      _compact({for (final key in _allNutrients) key: row[key]});

  /// Totals of a saved meal summed over the items that report each nutrient.
  /// The repository's own totals count an unreported nutrient as zero.
  static Map<String, double> _savedTotals(SavedMealWithItems entry) {
    final totals = <String, double>{};
    for (final values in entry.consumedByItem.values) {
      values.toMap().forEach((key, value) {
        if (value is num) totals[key] = (totals[key] ?? 0) + value.toDouble();
      });
    }
    return totals;
  }

  static Map<String, dynamic>? _compactOrNull(Map<String, Object?> map) =>
      map.isEmpty ? null : map.cast<String, dynamic>();

  static Map<String, dynamic> _macros(NutritionValues? values) => {
    'calories': values?.calories,
    'protein_g': values?.proteinG,
    'carbs_g': values?.carbsG,
    'fat_g': values?.fatG,
  };

  static Map<String, dynamic>? _decodeMap(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final value = jsonDecode(raw);
      return value is Map && value.isNotEmpty
          ? value.cast<String, dynamic>()
          : null;
    } catch (_) {
      return null;
    }
  }

  /// `120` / `12.5` for a nutrient total inside a text list.
  static String _short(double value) {
    if (value.abs() >= 100) return '${value.round()}';
    final text = value.toStringAsFixed(1);
    return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
  }

  static const _coreMacros = ['calories', 'protein_g', 'carbs_g', 'fat_g'];

  /// Goal keys with the prefix used in `<prefix>_vs_goal_pct`.
  static const _goalNutrients = <(String, String)>[
    ('calories', 'calories'),
    ('protein_g', 'protein'),
    ('carbs_g', 'carbs'),
    ('fat_g', 'fat'),
  ];

  static const _summaryNutrients = [
    'calories',
    'protein_g',
    'carbs_g',
    'fat_g',
    'saturated_fat_g',
    'monounsaturated_fat_g',
    'polyunsaturated_fat_g',
    'trans_fat_g',
    'fiber_g',
    'sugars_g',
    'sodium_mg',
  ];

  static const _dailyNutrients = [
    'calories',
    'protein_g',
    'carbs_g',
    'fat_g',
    'fiber_g',
    'sugars_g',
    'sodium_mg',
  ];

  static const _allNutrients = [
    'calories',
    'protein_g',
    'carbs_g',
    'fat_g',
    'saturated_fat_g',
    'monounsaturated_fat_g',
    'polyunsaturated_fat_g',
    'trans_fat_g',
    'fiber_g',
    'sugars_g',
    'sodium_mg',
    'potassium_mg',
    'calcium_mg',
    'iron_mg',
    'magnesium_mg',
    'zinc_mg',
    'vitamin_a_ug',
    'vitamin_c_mg',
    'vitamin_d_ug',
    'vitamin_b12_ug',
  ];

  static const _microNutrients = <(String, String)>[
    ('fiber_g', 'g'),
    ('sugars_g', 'g'),
    ('sodium_mg', 'mg'),
    ('potassium_mg', 'mg'),
    ('calcium_mg', 'mg'),
    ('iron_mg', 'mg'),
    ('magnesium_mg', 'mg'),
    ('zinc_mg', 'mg'),
    ('vitamin_a_ug', 'ug'),
    ('vitamin_c_mg', 'mg'),
    ('vitamin_d_ug', 'ug'),
    ('vitamin_b12_ug', 'ug'),
  ];
}
