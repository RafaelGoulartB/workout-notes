import 'dart:convert';

import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/models/nutrition/food.dart';
import 'package:workout_notes/models/nutrition/nutrition_values.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';

/// Read-only nutrition queries exposed to the AI Coach.
///
/// The service keeps the nutrition domain split into small, composable tools:
/// diary, history, micronutrients, food library, saved meals and profile. Null
/// nutrient values always mean "not reported" and are never coerced to zero.
class AiNutritionToolService {
  final DatabaseHelper db;
  final NutritionRepository nutritionRepository;
  final DateTime Function() _now;

  AiNutritionToolService({
    DatabaseHelper? db,
    NutritionRepository? nutritionRepository,
    DateTime Function()? now,
  }) : db = db ?? DatabaseHelper.instance,
       nutritionRepository = nutritionRepository ?? NutritionRepository(),
       _now = now ?? DateTime.now;

  Future<Map<String, dynamic>> diaryDay({String? date}) async {
    final resolvedDate = _validatedDate(date ?? _date(_now()));
    final database = await db.database;
    final logs = await database.query(
      'meal_logs',
      where: 'date = ?',
      whereArgs: [resolvedDate],
      orderBy: 'created_at ASC, id ASC',
    );
    final allItems = <Map<String, dynamic>>[];
    final meals = <Map<String, dynamic>>[];
    for (final log in logs) {
      final rows = await database.query(
        'meal_log_items',
        where: 'meal_log_id = ?',
        whereArgs: [log['id']],
        orderBy: 'created_at ASC, id ASC',
      );
      final items = rows.map(_diaryItem).toList();
      allItems.addAll(rows);
      meals.add({
        'mealLogId': log['id'],
        'mealType': log['meal_type'],
        'name': log['name'],
        'notes': log['notes'],
        'itemCount': items.length,
        'totals': _sumNutrients(rows),
        'items': items,
      });
    }
    final goalRows = await database.query(
      'nutrition_goals',
      where: 'is_active = 1',
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    return {
      'date': resolvedDate,
      'mealCount': meals.length,
      'itemCount': allItems.length,
      'totals': _sumNutrients(allItems),
      'activeDailyGoal': goalRows.isEmpty ? null : _goalMap(goalRows.first),
      'dataCoverage': _coverage(allItems),
      'meals': meals,
      'nullSemantics':
          'null means the nutrient was not reported; zero means reported as zero',
    };
  }

  Future<Map<String, dynamic>> history({int days = 30, String? endDate}) async {
    days = days.clamp(1, 31);
    final database = await db.database;
    final end = _validatedDate(endDate ?? _date(_now()));
    final endDay = DateTime.parse(end);
    final start = _date(endDay.subtract(Duration(days: days - 1)));
    final rows = await database.rawQuery(
      '''
      SELECT ml.date, mli.*
      FROM meal_log_items mli
      JOIN meal_logs ml ON ml.id = mli.meal_log_id
      WHERE ml.date BETWEEN ? AND ?
      ORDER BY ml.date ASC, mli.created_at ASC
      ''',
      [start, end],
    );
    final byDate = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      byDate.putIfAbsent(row['date'] as String, () => []).add(row);
    }
    final daily = byDate.entries
        .map(
          (entry) => {
            'date': entry.key,
            'itemCount': entry.value.length,
            'totals': _sumNutrients(entry.value),
            'coveragePctByNutrient': _coveragePct(entry.value),
          },
        )
        .toList();
    return {
      'startDate': start,
      'endDate': end,
      'windowDays': days,
      'loggedDays': daily.length,
      'coveragePct': _round(daily.length / days * 100),
      'days': daily,
      'nullSemantics':
          'missing days are absent; null nutrients were not reported and are not zero',
    };
  }

  Future<Map<String, dynamic>> micronutrientSummary({int days = 30}) async {
    days = days.clamp(1, 90);
    final database = await db.database;
    final end = _date(_now());
    final start = _date(_now().subtract(Duration(days: days - 1)));
    final rows = await database.rawQuery(
      '''
      SELECT ml.date, mli.food_name_snapshot, mli.brand_snapshot,
        mli.fiber_g, mli.sugars_g, mli.sodium_mg, mli.potassium_mg,
        mli.calcium_mg, mli.iron_mg, mli.magnesium_mg, mli.zinc_mg,
        mli.vitamin_a_ug, mli.vitamin_c_mg, mli.vitamin_d_ug,
        mli.vitamin_b12_ug
      FROM meal_log_items mli
      JOIN meal_logs ml ON ml.id = mli.meal_log_id
      WHERE ml.date BETWEEN ? AND ?
      ORDER BY ml.date ASC, mli.created_at ASC
      ''',
      [start, end],
    );
    final loggedDays = rows.map((row) => row['date'] as String).toSet();
    final nutrients = <String, dynamic>{};
    for (final field in _detailNutrients) {
      final perDay = <String, double>{};
      final sources = <String, ({String name, String? brand, double total})>{};
      var reportedItems = 0;
      for (final row in rows) {
        final value = (row[field.$1] as num?)?.toDouble();
        if (value == null) continue;
        reportedItems++;
        final date = row['date'] as String;
        perDay[date] = (perDay[date] ?? 0) + value;
        final name = row['food_name_snapshot'] as String? ?? 'Alimento';
        final brand = row['brand_snapshot'] as String?;
        final key = '$name\u0000${brand ?? ''}';
        final current = sources[key];
        sources[key] = (
          name: name,
          brand: brand,
          total: (current?.total ?? 0) + value,
        );
      }
      final totals = perDay.values.toList();
      final total = totals.fold<double>(0, (sum, value) => sum + value);
      final topSources = sources.values.toList()
        ..sort((a, b) => b.total.compareTo(a.total));
      nutrients[field.$2] = {
        'unit': field.$3,
        'totalFromReportedValues': totals.isEmpty ? null : _round(total),
        'averageOnReportedDays': totals.isEmpty
            ? null
            : _round(total / totals.length),
        'minimumReportedDay': totals.isEmpty
            ? null
            : _round(totals.reduce((a, b) => a < b ? a : b)),
        'maximumReportedDay': totals.isEmpty
            ? null
            : _round(totals.reduce((a, b) => a > b ? a : b)),
        'reportedDays': totals.length,
        'dayCoveragePct': loggedDays.isEmpty
            ? 0.0
            : _round(totals.length / loggedDays.length * 100),
        'reportedItems': reportedItems,
        'itemCoveragePct': rows.isEmpty
            ? 0.0
            : _round(reportedItems / rows.length * 100),
        'topFoodSources': topSources
            .take(3)
            .map(
              (source) => {
                'name': source.name,
                'brand': source.brand,
                'total': _round(source.total),
              },
            )
            .toList(),
      };
    }
    return {
      'startDate': start,
      'endDate': end,
      'windowDays': days,
      'loggedDays': loggedDays.length,
      'itemCount': rows.length,
      'nutrients': nutrients,
      'dataQualityWarning':
          'averages use only days where each nutrient was reported; low coverage can bias interpretation',
    };
  }

  Future<Map<String, dynamic>> searchFoods({
    String? query,
    bool favoritesOnly = false,
    bool recentOnly = false,
    int limit = 15,
  }) async {
    limit = limit.clamp(1, 30);
    final database = await db.database;
    final where = <String>[];
    final args = <Object?>[];
    final normalized = Food.normalizeForSearch(query?.trim() ?? '');
    if (normalized.isNotEmpty) {
      where.add(
        '(f.search_name LIKE ? OR LOWER(COALESCE(f.brand, \'\')) LIKE ?)',
      );
      args.addAll(['%$normalized%', '%$normalized%']);
    }
    if (favoritesOnly) where.add('f.is_favorite = 1');
    if (recentOnly) where.add('f.last_used_at IS NOT NULL');
    args.add(limit);
    final rows = await database.rawQuery('''
      SELECT f.*
      FROM foods f
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      ORDER BY f.is_favorite DESC,
        CASE WHEN f.last_used_at IS NULL THEN 1 ELSE 0 END,
        f.last_used_at DESC, f.name COLLATE NOCASE ASC
      LIMIT ?
      ''', args);
    final foods = <Map<String, dynamic>>[];
    for (final food in rows) {
      final variants = await database.query(
        'food_variants',
        where: 'food_id = ?',
        whereArgs: [food['id']],
        orderBy: 'is_estimated ASC, reference_amount ASC',
      );
      foods.add({
        ..._foodMap(food),
        'primaryVariant': variants.isEmpty ? null : _variantMap(variants.first),
        'variantCount': variants.length,
      });
    }
    return {
      'query': query?.trim(),
      'favoritesOnly': favoritesOnly,
      'recentOnly': recentOnly,
      'foods': foods,
    };
  }

  Future<Map<String, dynamic>> foodDetail(String foodId) async {
    final database = await db.database;
    final foods = await database.query(
      'foods',
      where: 'id = ?',
      whereArgs: [foodId],
      limit: 1,
    );
    if (foods.isEmpty) return {'error': 'food not found'};
    final variants = await database.query(
      'food_variants',
      where: 'food_id = ?',
      whereArgs: [foodId],
      orderBy: 'reference_amount ASC, id ASC',
    );
    final outputVariants = <Map<String, dynamic>>[];
    for (final variant in variants) {
      final servings = await database.query(
        'food_servings',
        where: 'food_variant_id = ?',
        whereArgs: [variant['id']],
        orderBy: 'label COLLATE NOCASE ASC',
      );
      outputVariants.add({
        ..._variantMap(variant),
        'servings': servings
            .map(
              (serving) => {
                'id': serving['id'],
                'label': serving['label'],
                'quantity': serving['quantity'],
                'unit': serving['unit'],
                'gramsEquivalent': serving['grams_equivalent'],
                'mlEquivalent': serving['ml_equivalent'],
              },
            )
            .toList(),
      });
    }
    return {..._foodMap(foods.first), 'variants': outputVariants};
  }

  Future<Map<String, dynamic>> listSavedMeals({int limit = 20}) async {
    limit = limit.clamp(1, 50);
    final meals = (await nutritionRepository.getSavedMeals()).take(limit);
    return {
      'savedMeals': meals
          .map(
            (entry) => {
              'id': entry.meal.id,
              'name': entry.meal.name,
              'mealType': entry.meal.mealType,
              'portions': entry.meal.portions,
              'itemCount': entry.items.length,
              'totals': _valuesMap(entry.totals),
              'updatedAt': entry.meal.updatedAt.toIso8601String(),
            },
          )
          .toList(),
    };
  }

  Future<Map<String, dynamic>> savedMealDetail(String savedMealId) async {
    final entry = await nutritionRepository.getSavedMeal(savedMealId);
    if (entry == null) return {'error': 'saved meal not found'};
    return {
      'id': entry.meal.id,
      'name': entry.meal.name,
      'mealType': entry.meal.mealType,
      'portions': entry.meal.portions,
      'createdAt': entry.meal.createdAt.toIso8601String(),
      'updatedAt': entry.meal.updatedAt.toIso8601String(),
      'totals': _valuesMap(entry.totals),
      'items': entry.items
          .map(
            (item) => {
              'id': item.id,
              'foodId': item.foodId,
              'foodVariantId': item.foodVariantId,
              'foodName': item.foodNameSnapshot,
              'brand': item.brandSnapshot,
              'quantity': item.quantity,
              'unit': item.unit,
              'servingLabel': item.servingLabel,
              'servingGramsEquivalent': item.servingGramsEquivalent,
              'servingMlEquivalent': item.servingMlEquivalent,
              'nutrients': _valuesMap(entry.consumedByItem[item.id]),
            },
          )
          .toList(),
    };
  }

  Future<Map<String, dynamic>> profile() async {
    final database = await db.database;
    final goals = await database.query(
      'nutrition_goals',
      orderBy: 'updated_at DESC',
    );
    final mealTypes = await database.query(
      'meal_types',
      orderBy: 'order_index ASC, created_at ASC',
    );
    final profileSettings = await database.query(
      'app_settings',
      where: 'key LIKE ?',
      whereArgs: ['nutrition_profile_%'],
    );
    final settings = {
      for (final row in profileSettings)
        row['key'] as String: row['value'] as String?,
    };
    final counts = await database.rawQuery('''
      SELECT
        (SELECT COUNT(*) FROM foods) food_count,
        (SELECT COUNT(*) FROM foods WHERE is_favorite = 1) favorite_food_count,
        (SELECT COUNT(*) FROM saved_meals) saved_meal_count,
        (SELECT COUNT(DISTINCT date) FROM meal_logs) diary_day_count
      ''');
    final count = counts.first;
    return {
      'activeDailyGoal': goals.where((row) => row['is_active'] == 1).isEmpty
          ? null
          : _goalMap(goals.firstWhere((row) => row['is_active'] == 1)),
      'goalHistory': goals
          .map((row) => {..._goalMap(row), 'isActive': row['is_active'] == 1})
          .toList(),
      'goalSuggestionProfile': {
        'sex': settings['nutrition_profile_sex'],
        'ageYears': _intOrNull(settings['nutrition_profile_age']),
        'heightCm': _doubleOrNull(settings['nutrition_profile_height_cm']),
        'weightKg': _doubleOrNull(settings['nutrition_profile_weight_kg']),
        'activityLevel': settings['nutrition_profile_activity'],
        'macroRatiosGPerKg': {
          for (final objective in const ['cut', 'maintenance', 'bulk'])
            objective: {
              'protein': _doubleOrNull(
                settings['nutrition_profile_macro_${objective}_protein_g_kg'],
              ),
              'fat': _doubleOrNull(
                settings['nutrition_profile_macro_${objective}_fat_g_kg'],
              ),
            },
        },
      },
      'mealTypes': mealTypes
          .map(
            (row) => {
              'id': row['id'],
              'key': row['key'],
              'name': row['name'],
              'order': row['order_index'],
            },
          )
          .toList(),
      'libraryCounts': {
        'foods': (count['food_count'] as num?)?.toInt() ?? 0,
        'favoriteFoods': (count['favorite_food_count'] as num?)?.toInt() ?? 0,
        'savedMeals': (count['saved_meal_count'] as num?)?.toInt() ?? 0,
        'diaryDays': (count['diary_day_count'] as num?)?.toInt() ?? 0,
      },
    };
  }

  static Map<String, dynamic> _diaryItem(Map<String, dynamic> row) {
    Map<String, dynamic>? snapshot;
    try {
      final raw = jsonDecode(row['nutrition_snapshot_json'] as String);
      if (raw is Map) snapshot = raw.cast<String, dynamic>();
    } catch (_) {}
    return {
      'itemId': row['id'],
      'foodId': row['food_id'],
      'foodVariantId': row['food_variant_id'],
      'foodName': row['food_name_snapshot'],
      'brand': row['brand_snapshot'],
      'quantity': row['quantity'],
      'unit': row['unit'],
      'variantLabel': snapshot?['variant_label'],
      'referenceAmount': snapshot?['reference_amount'],
      'referenceUnit': snapshot?['reference_unit'],
      'gramsEquivalent': snapshot?['grams_equivalent'],
      'mlEquivalent': snapshot?['ml_equivalent'],
      'source': snapshot?['source'],
      'isEstimated': snapshot?['is_estimated'] ?? false,
      'hasMissingValues': snapshot?['has_missing_values'] ?? false,
      'nutrients': _nutrientsFromRow(row),
      'loggedAt': row['created_at'],
    };
  }

  static Map<String, dynamic> _foodMap(Map<String, dynamic> row) => {
    'id': row['id'],
    'name': row['name'],
    'brand': row['brand'],
    'barcode': row['barcode'],
    'source': row['source'],
    'sourceUrl': row['source_url'],
    'isFavorite': row['is_favorite'] == 1,
    'lastUsedAt': row['last_used_at'],
    'fetchedAt': row['fetched_at'],
  };

  static Map<String, dynamic> _variantMap(Map<String, dynamic> row) => {
    'id': row['id'],
    'label': row['label'],
    'referenceAmount': row['reference_amount'],
    'referenceUnit': row['reference_unit'],
    'isEstimated': row['is_estimated'] == 1,
    'nutrients': _nutrientsFromRow(row),
    'extraNutrients': _decodeJsonMap(row['extra_nutrients_json'] as String?),
  };

  static Map<String, dynamic> _goalMap(Map<String, dynamic> row) => {
    'id': row['id'],
    'calories': row['calories'],
    'proteinG': row['protein_g'],
    'carbsG': row['carbs_g'],
    'fatG': row['fat_g'],
    'createdAt': row['created_at'],
    'updatedAt': row['updated_at'],
  };

  static Map<String, dynamic> _sumNutrients(
    Iterable<Map<String, dynamic>> rows,
  ) {
    final result = <String, dynamic>{};
    for (final field in _allNutrients) {
      var seen = false;
      var sum = 0.0;
      for (final row in rows) {
        final value = (row[field.$1] as num?)?.toDouble();
        if (value == null) continue;
        seen = true;
        sum += value;
      }
      result[field.$2] = seen ? _round(sum) : null;
    }
    return result;
  }

  static Map<String, dynamic> _coverage(List<Map<String, dynamic>> rows) {
    final fields = <String, dynamic>{};
    for (final field in _allNutrients) {
      final reported = rows.where((row) => row[field.$1] != null).length;
      fields[field.$2] = {
        'reportedItems': reported,
        'totalItems': rows.length,
        'pct': rows.isEmpty ? 0.0 : _round(reported / rows.length * 100),
      };
    }
    return {'byNutrient': fields};
  }

  static Map<String, dynamic> _coveragePct(List<Map<String, dynamic>> rows) => {
    for (final field in _allNutrients)
      field.$2: rows.isEmpty
          ? 0.0
          : _round(
              rows.where((row) => row[field.$1] != null).length /
                  rows.length *
                  100,
            ),
  };

  static Map<String, dynamic> _nutrientsFromRow(Map<String, dynamic> row) => {
    for (final field in _allNutrients) field.$2: row[field.$1],
  };

  static Map<String, dynamic>? _valuesMap(NutritionValues? values) {
    if (values == null) return null;
    final row = values.toMap();
    return _nutrientsFromRow(row);
  }

  static Map<String, dynamic>? _decodeJsonMap(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final value = jsonDecode(raw);
      return value is Map ? value.cast<String, dynamic>() : null;
    } catch (_) {
      return null;
    }
  }

  static String _validatedDate(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      throw const FormatException('date must use YYYY-MM-DD');
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null || _date(parsed) != value) {
      throw const FormatException('date is invalid');
    }
    return value;
  }

  static String _date(DateTime value) =>
      value.toIso8601String().substring(0, 10);

  static double _round(double value) => (value * 10).round() / 10;

  static double? _doubleOrNull(String? value) =>
      value == null ? null : double.tryParse(value);

  static int? _intOrNull(String? value) =>
      value == null ? null : int.tryParse(value);

  static const _allNutrients = <(String, String)>[
    ('calories', 'calories'),
    ('protein_g', 'proteinG'),
    ('carbs_g', 'carbsG'),
    ('fat_g', 'fatG'),
    ('saturated_fat_g', 'saturatedFatG'),
    ('monounsaturated_fat_g', 'monounsaturatedFatG'),
    ('polyunsaturated_fat_g', 'polyunsaturatedFatG'),
    ('trans_fat_g', 'transFatG'),
    ('fiber_g', 'fiberG'),
    ('sugars_g', 'sugarsG'),
    ('sodium_mg', 'sodiumMg'),
    ('potassium_mg', 'potassiumMg'),
    ('calcium_mg', 'calciumMg'),
    ('iron_mg', 'ironMg'),
    ('magnesium_mg', 'magnesiumMg'),
    ('zinc_mg', 'zincMg'),
    ('vitamin_a_ug', 'vitaminAUg'),
    ('vitamin_c_mg', 'vitaminCMg'),
    ('vitamin_d_ug', 'vitaminDUg'),
    ('vitamin_b12_ug', 'vitaminB12Ug'),
  ];

  static const _detailNutrients = <(String, String, String)>[
    ('fiber_g', 'fiberG', 'g'),
    ('sugars_g', 'sugarsG', 'g'),
    ('sodium_mg', 'sodiumMg', 'mg'),
    ('potassium_mg', 'potassiumMg', 'mg'),
    ('calcium_mg', 'calciumMg', 'mg'),
    ('iron_mg', 'ironMg', 'mg'),
    ('magnesium_mg', 'magnesiumMg', 'mg'),
    ('zinc_mg', 'zincMg', 'mg'),
    ('vitamin_a_ug', 'vitaminAUg', 'µg'),
    ('vitamin_c_mg', 'vitaminCMg', 'mg'),
    ('vitamin_d_ug', 'vitaminDUg', 'µg'),
    ('vitamin_b12_ug', 'vitaminB12Ug', 'µg'),
  ];
}
