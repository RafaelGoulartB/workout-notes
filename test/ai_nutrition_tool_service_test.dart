import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/services/ai_nutrition_tool_service.dart';
import 'package:workout_notes/services/ai_tool_result_shaper.dart';
import 'package:workout_notes/services/ai_tool_spec.dart';

import 'support/ai_heavy_user_fixture.dart';
import 'support/test_db.dart';

final _today = DateTime(2026, 9, 30, 12);

AiNutritionToolService _service() => AiNutritionToolService(now: () => _today);

/// The day after the seeded data, so no logged day is "today".
AiNutritionToolService _tomorrowService() =>
    AiNutritionToolService(now: () => DateTime(2026, 10, 1, 12));

Map<String, Object?> _nutrients(Map<String, double> values) => {
  for (final key in _keys) key: values[key],
};

const _keys = [
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

// Per 100 g. Vitamin D is never reported; the chicken reports fiber as 0.
const _chicken = {
  'calories': 165.0,
  'protein_g': 31.0,
  'carbs_g': 0.0,
  'fat_g': 3.6,
  'fiber_g': 0.0,
  'sodium_mg': 74.0,
  'magnesium_mg': 29.0,
  'vitamin_b12_ug': 0.3,
};
const _oats = {
  'calories': 380.0,
  'protein_g': 13.0,
  'carbs_g': 67.0,
  'fat_g': 7.0,
  'fiber_g': 10.0,
  'magnesium_mg': 177.0,
};
const _rice = {
  'calories': 130.0,
  'protein_g': 2.7,
  'carbs_g': 28.0,
  'fat_g': 0.3,
};

Future<void> _food(
  Database db,
  String id,
  String name,
  Map<String, double> nutrients, {
  String? brand,
  bool favorite = false,
  String? lastUsed,
  bool estimated = false,
}) async {
  await db.insert('foods', {
    'id': id,
    'source': 'manual',
    'external_id': id,
    'name': name,
    'search_name': name.toLowerCase(),
    'brand': brand,
    'fetched_at': '2026-09-01T10:00:00.000',
    'last_used_at': lastUsed,
    'is_favorite': favorite ? 1 : 0,
  });
  await db.insert('food_variants', {
    'id': 'fv-$id',
    'food_id': id,
    'label': 'Plain',
    'reference_amount': 100.0,
    'reference_unit': 'g',
    ..._nutrients(nutrients),
    'is_estimated': estimated ? 1 : 0,
  });
}

Future<void> _log(
  Database db,
  String id,
  String date,
  String type, {
  String? name,
  String createdAt = '2026-09-01T08:00:00.000',
}) => db.insert('meal_logs', {
  'id': id,
  'date': date,
  'meal_type': type,
  'name': name,
  'created_at': createdAt,
});

Future<void> _item(
  Database db,
  String id,
  String logId,
  String foodName,
  Map<String, double> nutrients, {
  double quantity = 100,
  String? brand,
  bool estimated = false,
  String createdAt = '2026-09-01T08:00:00.000',
}) => db.insert('meal_log_items', {
  'id': id,
  'meal_log_id': logId,
  'food_name_snapshot': foodName,
  'brand_snapshot': brand,
  'quantity': quantity,
  'unit': 'g',
  ..._nutrients(nutrients),
  'nutrition_snapshot_json': jsonEncode({
    'version': 3,
    'is_estimated': estimated,
    'has_missing_values': false,
  }),
  'created_at': createdAt,
});

Map<String, double> _scaled(Map<String, double> base, double factor) => {
  for (final entry in base.entries) entry.key: entry.value * factor,
};

/// Today: lunch (chicken + rice). 09-29: breakfast oats, dinner 2x chicken.
/// 09-27: a snack without fat. 10-02 (future): a 999 kcal item.
Future<void> _seed(Database db) async {
  await _food(
    db,
    'food-chicken',
    'Chicken breast',
    _chicken,
    favorite: true,
    lastUsed: '2026-09-29T19:00:00.000',
  );
  await _food(
    db,
    'food-oats',
    'Rolled oats',
    _oats,
    brand: 'Quaker',
    lastUsed: '2026-09-29T08:00:00.000',
  );
  await _food(db, 'food-rice', 'White rice', _rice, estimated: true);
  await db.insert('food_servings', {
    'id': 'fs-chicken',
    'food_variant_id': 'fv-food-chicken',
    'label': '1 fillet',
    'quantity': 1.0,
    'unit': 'fillet',
    'grams_equivalent': 120.0,
  });
  await db.update(
    'food_variants',
    {
      'extra_nutrients_json': jsonEncode({'selenium_ug': 27.6}),
    },
    where: 'id = ?',
    whereArgs: ['fv-food-chicken'],
  );
  // A second, estimated variant of the chicken with a larger reference.
  await db.insert('food_variants', {
    'id': 'fv-food-chicken-est',
    'food_id': 'food-chicken',
    'label': 'Estimated',
    'reference_amount': 150.0,
    'reference_unit': 'g',
    ..._nutrients({'calories': 240.0}),
    'is_estimated': 1,
  });

  await _log(db, 'ml-today', '2026-09-30', 'lunch', name: 'Almoco');
  await _item(
    db,
    'i1',
    'ml-today',
    'Chicken breast',
    _chicken,
    createdAt: '2026-09-30T12:00:00.000',
  );
  await _item(
    db,
    'i2',
    'ml-today',
    'White rice',
    _rice,
    estimated: true,
    createdAt: '2026-09-30T12:01:00.000',
  );

  await _log(
    db,
    'ml-b',
    '2026-09-29',
    'breakfast',
    createdAt: '2026-09-01T07:00:00.000',
  );
  await _item(db, 'i3', 'ml-b', 'Rolled oats', _oats, brand: 'Quaker');
  await _log(
    db,
    'ml-d',
    '2026-09-29',
    'dinner',
    createdAt: '2026-09-01T20:00:00.000',
  );
  await _item(
    db,
    'i4',
    'ml-d',
    'Chicken breast',
    _scaled(_chicken, 2),
    quantity: 200,
  );

  await _log(db, 'ml-s', '2026-09-27', 'snacks');
  await _item(db, 'i5', 'ml-s', 'Mystery bar', {
    'calories': 200.0,
    'protein_g': 5.0,
    'carbs_g': 30.0,
  });

  await _log(db, 'ml-future', '2026-10-02', 'lunch');
  await _item(db, 'i6', 'ml-future', 'Future feast', {
    'calories': 999.0,
    'protein_g': 99.0,
    'carbs_g': 99.0,
    'fat_g': 99.0,
  });

  await db.insert('nutrition_goals', {
    'id': 'goal',
    'calories': 2000.0,
    'protein_g': 150.0,
    'carbs_g': 200.0,
    'fat_g': 60.0,
    'created_at': '2026-09-01T00:00:00.000',
    'updated_at': '2026-09-01T00:00:00.000',
    'is_active': 1,
  });

  await db.insert('saved_meals', {
    'id': 'sm-old',
    'name': 'Old bowl',
    'meal_type': 'lunch',
    'portions': 1.0,
    'created_at': '2026-08-01T00:00:00.000',
    'updated_at': '2026-08-01T00:00:00.000',
  });
  await db.insert('saved_meals', {
    'id': 'sm-new',
    'name': 'Post workout',
    'meal_type': 'snacks',
    'portions': 2.0,
    'created_at': '2026-09-10T00:00:00.000',
    'updated_at': '2026-09-20T00:00:00.000',
  });
  await db.insert('saved_meal_items', {
    'id': 'smi-1',
    'saved_meal_id': 'sm-new',
    'food_id': 'food-chicken',
    'food_variant_id': 'fv-food-chicken',
    'food_name_snapshot': 'Chicken breast',
    'quantity': 200.0,
    'unit': 'g',
    'serving_label': '1 fillet',
    'order_index': 0,
  });
  await db.insert('saved_meal_items', {
    'id': 'smi-2',
    'saved_meal_id': 'sm-new',
    'food_id': 'food-oats',
    'food_variant_id': 'fv-food-oats',
    'food_name_snapshot': 'Rolled oats',
    'brand_snapshot': 'Quaker',
    'quantity': 50.0,
    'unit': 'g',
    'order_index': 1,
  });
  await db.insert('saved_meal_items', {
    'id': 'smi-3',
    'saved_meal_id': 'sm-old',
    'food_id': 'food-rice',
    'food_variant_id': 'fv-food-rice',
    'food_name_snapshot': 'White rice',
    'quantity': 100.0,
    'unit': 'g',
    'order_index': 0,
  });
}

List<Map<String, dynamic>> _rows(Object? list) =>
    (list! as List).cast<Map<String, dynamic>>();

void main() {
  late Database db;

  setUp(() async {
    db = await installTestDb();
    await _seed(db);
  });

  tearDown(uninstallTestDb);

  group('get_nutrition', () {
    test('summary averages logged days and never reads the future', () async {
      final result = await _tomorrowService().nutrition(endDate: '2026-09-30');

      expect(result['applied'], {
        'start_date': '2026-09-17',
        'end_date': '2026-09-30',
        'days': 14,
        'detail': 'summary',
      });
      expect(result['logged_days'], 3);
      expect(result['coverage_pct'], closeTo(3 / 14 * 100, 1e-9));
      expect(result['incomplete_days'], 1);

      final averages = result['averages'] as Map<String, dynamic>;
      // (295 + 710 + 200) / 3: the 999 kcal future item is not counted.
      expect(averages['calories'], closeTo(1205 / 3, 1e-9));
      expect(averages['protein_g'], closeTo((33.7 + 75 + 5) / 3, 1e-9));
      // Fat is unreported on the snack day: averaged over the two others.
      expect(averages['fat_g'], closeTo((3.9 + 14.2) / 2, 1e-9));
      // Fiber: 0 (reported zero) and 10 on two days, absent on the third.
      expect(averages['fiber_g'], closeTo(5, 1e-9));
      // Never reported anywhere: absent, not zero.
      expect(averages.containsKey('saturated_fat_g'), isFalse);
      expect(averages.containsKey('sugars_g'), isFalse);
    });

    test('goal, percentages and calories by meal', () async {
      final result = await _tomorrowService().nutrition(endDate: '2026-09-30');

      final goal = result['goal'] as Map<String, dynamic>;
      expect(goal['calories'], 2000);
      expect(goal['goal_source'], 'settings');
      expect(
        result['calories_vs_goal_pct'],
        closeTo(1205 / 3 / 2000 * 100, 1e-9),
      );
      expect(result.containsKey('protein_vs_goal_pct'), isTrue);

      final meals = _rows(result['calories_by_meal']);
      expect(meals.first['meal_type'], 'breakfast');
      final lunch = meals.firstWhere((meal) => meal['meal_type'] == 'lunch');
      expect(lunch['calories'], closeTo(295 / 3, 1e-9));
      expect(lunch['share_pct'], closeTo(295 / 1205 * 100, 1e-9));
    });

    test('today, usually half logged, is left out of the averages', () async {
      final result = await _service().nutrition();
      expect(result['logged_days'], 3);
      expect(result['today_excluded_from_averages'], isTrue);
      final averages = result['averages'] as Map<String, dynamic>;
      // Today (2026-09-30) holds the 295 kcal lunch: 710 and 200 remain.
      expect(averages['calories'], closeTo((710 + 200) / 2, 1e-9));
      final alone = await _service().nutrition(
        startDate: '2026-09-30',
        endDate: '2026-09-30',
      );
      expect(alone['today_excluded_from_averages'], isNull,
          reason: 'a single logged day is all there is to average');
      expect((alone['averages'] as Map)['calories'], 295);
    });

    test('end_date is an upper bound on the logged rows', () async {
      final result = await _service().nutrition(days: 3, endDate: '2026-09-28');

      expect(result['applied'], containsPair('end_date', '2026-09-28'));
      expect(result['logged_days'], 1);
      expect((result['averages'] as Map<String, dynamic>)['calories'], 200);
    });

    test('an end_date in the future is clamped to today', () async {
      final result = await _service().nutrition(
        endDate: '2026-10-05',
        detail: 'daily',
      );

      expect(result['applied'], containsPair('end_date', '2026-09-30'));
      expect(_rows(result['days']).map((day) => day['date']), [
        '2026-09-30',
        '2026-09-29',
        '2026-09-27',
      ]);
    });

    test(
      'daily lists the newest day first with partial nutrients absent',
      () async {
        final result = await _service().nutrition(detail: 'daily');

        final days = _rows(result['days']);
        expect(days.map((day) => day['date']), [
          '2026-09-30',
          '2026-09-29',
          '2026-09-27',
        ]);
        expect(days.first['calories'], closeTo(295, 1e-9));
        expect(days.first['items'], 2);
        expect(days.first.containsKey('incomplete'), isFalse);
        final snack = days.last;
        expect(snack['calories'], 200);
        expect(snack.containsKey('fat_g'), isFalse);
        expect(snack['incomplete'], isTrue);
        expect((result['goal'] as Map)['calories'], 2000);
      },
    );

    test(
      'micros average only reported days and name the top sources',
      () async {
        final result = await _service().nutrition(detail: 'micros');

        expect(result['logged_days'], 3);
        final rows = _rows(result['nutrients']);
        expect(rows, hasLength(12));
        final magnesium = rows.firstWhere(
          (r) => r['nutrient'] == 'magnesium_mg',
        );
        expect(magnesium['unit'], 'mg');
        // 29 on 09-30, 177 + 58 on 09-29, unreported on 09-27.
        expect(magnesium['avg_on_reported_days'], closeTo(132, 1e-9));
        expect(magnesium['min'], 29);
        expect(magnesium['max'], 235);
        expect(magnesium['reported_days'], 2);
        expect(magnesium['coverage_pct'], closeTo(2 / 3 * 100, 1e-9));
        expect(
          magnesium['top_foods'],
          'Rolled oats (177); Chicken breast (87)',
        );

        final vitaminD = rows.firstWhere(
          (r) => r['nutrient'] == 'vitamin_d_ug',
        );
        expect(vitaminD['reported_days'], 0);
        expect(vitaminD['coverage_pct'], 0);
        expect(vitaminD.containsKey('avg_on_reported_days'), isFalse);
        expect(vitaminD.containsKey('top_foods'), isFalse);
      },
    );

    test('foods rank calorie contributors and split meal types', () async {
      final result = await _service().nutrition(detail: 'foods');

      expect(result['total_calories'], closeTo(1205, 1e-9));
      final foods = _rows(result['top_foods']);
      expect(foods.first['name'], 'Chicken breast');
      expect(foods.first['times_logged'], 2);
      expect(foods.first['calories'], closeTo(495, 1e-9));
      expect(foods.first['share_pct'], closeTo(495 / 1205 * 100, 1e-9));
      expect(foods.first['protein_g'], closeTo(93, 1e-9));
      expect(foods.any((food) => food['name'] == 'Future feast'), isFalse);
      final oats = foods.firstWhere((food) => food['name'] == 'Rolled oats');
      expect(oats['brand'], 'Quaker');

      final meals = _rows(result['calories_by_meal']);
      final dinner = meals.firstWhere((meal) => meal['meal_type'] == 'dinner');
      expect(dinner['calories'], closeTo(330, 1e-9));
      expect(dinner['share_pct'], closeTo(330 / 1205 * 100, 1e-9));
    });

    test(
      'an empty window has no averages but still reports coverage',
      () async {
        final result = await _service().nutrition(
          startDate: '2026-01-01',
          endDate: '2026-01-10',
        );

        expect(result['logged_days'], 0);
        expect(result['coverage_pct'], 0);
        expect(result.containsKey('averages'), isFalse);
      },
    );

    test('rejects unusable arguments', () async {
      await expectLater(
        _service().nutrition(detail: 'everything'),
        throwsA(isA<AiToolArgException>()),
      );
      await expectLater(
        _service().nutrition(endDate: '30/09/2026'),
        throwsA(isA<AiToolArgException>()),
      );
      await expectLater(
        _service().nutrition(startDate: '2026-09-20', endDate: '2026-09-10'),
        throwsA(isA<AiToolArgException>()),
      );
    });
  });

  group('get_nutrition_diary_day', () {
    test('lists meals in order with totals, goal and remaining', () async {
      final result = await _service().diaryDay(date: '2026-09-29');

      expect(result['date'], '2026-09-29');
      final meals = _rows(result['meals']);
      expect(meals.map((meal) => meal['meal_type']), ['breakfast', 'dinner']);
      expect(meals.first['calories'], 380);
      final items = _rows(meals.first['items']);
      expect(items.single['name'], 'Rolled oats');
      expect(items.single['brand'], 'Quaker');
      expect(items.single['quantity'], 100);
      expect(items.single['calories'], 380);

      final totals = result['totals'] as Map<String, dynamic>;
      expect(totals['calories'], closeTo(710, 1e-9));
      expect(totals['magnesium_mg'], closeTo(235, 1e-9));
      expect(totals.containsKey('vitamin_d_ug'), isFalse);

      final remaining = result['remaining'] as Map<String, dynamic>;
      expect(remaining['calories'], closeTo(2000 - 710, 1e-9));
      expect(remaining['protein_g'], closeTo(150 - 75, 1e-9));
      expect((result['goal'] as Map)['goal_source'], 'settings');
    });

    test('flags estimated items and counts items missing a nutrient', () async {
      final result = await _service().diaryDay();

      expect(result['date'], '2026-09-30');
      final items = _rows(_rows(result['meals']).single['items']);
      expect(items[0].containsKey('estimated'), isFalse);
      expect(items[1]['estimated'], isTrue);
      expect(items[1]['name'], 'White rice');
      // The rice has no fiber: one of the two items.
      expect(
        (result['items_missing_nutrient'] as Map<String, dynamic>)['fiber_g'],
        1,
      );
      expect(result['item_count'], 2);
    });

    test(
      'a nutrient missing from every item stays unknown, not zero',
      () async {
        final result = await _service().diaryDay(date: '2026-09-27');

        final totals = result['totals'] as Map<String, dynamic>;
        expect(totals['calories'], 200);
        expect(totals.containsKey('fat_g'), isFalse);
        final remaining = result['remaining'] as Map<String, dynamic>;
        expect(remaining['calories'], 1800);
        expect(remaining.containsKey('fat_g'), isFalse);
        final item = _rows(_rows(result['meals']).single['items']).single;
        expect(item['has_missing_values'], isTrue);
      },
    );

    test('an empty day is a result, with the whole goal left', () async {
      final result = await _service().diaryDay(date: '2026-09-01');

      expect(result['date'], '2026-09-01');
      expect(result['meals'], isEmpty);
      expect(result['item_count'], 0);
      expect(result['totals'], isEmpty);
      expect(result['remaining'], containsPair('calories', 2000));
    });

    test('rejects an invalid date', () async {
      await expectLater(
        _service().diaryDay(date: '30/09/2026'),
        throwsA(isA<AiToolArgException>()),
      );
    });
  });

  group('search_food_library', () {
    test('matches names and brands and picks the primary variant', () async {
      final byName = await _service().searchFoods(query: 'CHICKEN');
      final foods = _rows(byName['foods']);
      expect(foods.single['id'], 'food-chicken');
      expect(foods.single['is_favorite'], isTrue);
      // The measured variant outranks the larger estimated one.
      expect(foods.single['reference_amount'], 100);
      expect(foods.single['calories'], 165);
      expect(foods.single['is_estimated'], isFalse);
      expect(foods.single['variant_count'], 2);
      expect(byName['has_more'], isFalse);

      final byBrand = await _service().searchFoods(query: 'quaker');
      expect(_rows(byBrand['foods']).single['id'], 'food-oats');
    });

    test('omits nutrients the food does not report', () async {
      final foods = _rows(
        (await _service().searchFoods(query: 'rice'))['foods'],
      );
      expect(foods.single['calories'], 130);
      expect(foods.single['is_estimated'], isTrue);
      final oats = _rows(
        (await _service().searchFoods(query: 'oats'))['foods'],
      );
      expect(oats.single.containsKey('last_used_at'), isTrue);
      expect(foods.single.containsKey('last_used_at'), isFalse);
    });

    test('filters favorites and recents and reports has_more', () async {
      final favorites = await _service().searchFoods(favoritesOnly: true);
      expect(_rows(favorites['foods']).single['id'], 'food-chicken');

      final recent = await _service().searchFoods(recentOnly: true);
      expect(_rows(recent['foods']).map((food) => food['id']), [
        'food-chicken',
        'food-oats',
      ]);

      final limited = await _service().searchFoods(limit: 1);
      expect(_rows(limited['foods']), hasLength(1));
      expect(limited['has_more'], isTrue);
    });

    test('food_id returns every variant, extras and servings', () async {
      final result = await _service().searchFoods(foodId: 'food-chicken');

      expect(result['id'], 'food-chicken');
      final variants = _rows(result['variants']);
      expect(variants, hasLength(2));
      final plain = variants.firstWhere(
        (variant) => variant['label'] == 'Plain',
      );
      expect(plain['reference_amount'], 100);
      expect(plain['nutrients'], containsPair('protein_g', 31));
      expect((plain['nutrients'] as Map).containsKey('vitamin_d_ug'), isFalse);
      expect(plain['extra_nutrients'], {'selenium_ug': 27.6});
      expect(_rows(plain['servings']).single['grams'], 120);
      final estimated = variants.firstWhere(
        (variant) => variant['label'] == 'Estimated',
      );
      expect(estimated['is_estimated'], isTrue);
      expect(estimated.containsKey('servings'), isFalse);
    });

    test('an unknown food_id is not_found with a hint', () async {
      await expectLater(
        _service().searchFoods(foodId: 'nope'),
        throwsA(
          isA<AiToolNotFoundException>().having(
            (e) => e.hint,
            'hint',
            contains('search_food_library'),
          ),
        ),
      );
    });
  });

  group('list_saved_meals', () {
    test('lists newest first with live totals', () async {
      final result = await _service().listSavedMeals();

      expect(result['total'], 2);
      expect(result['has_more'], isFalse);
      final meals = _rows(result['saved_meals']);
      expect(meals.map((meal) => meal['id']), ['sm-new', 'sm-old']);
      final fresh = meals.first;
      expect(fresh['name'], 'Post workout');
      expect(fresh['item_count'], 2);
      expect(fresh['portions'], 2);
      // 200 g chicken + 50 g oats, times 2 portions.
      expect(fresh['calories'], closeTo((330 + 190) * 2, 1e-9));
      expect(fresh['protein_g'], closeTo((62 + 6.5) * 2, 1e-9));
      expect(fresh['updated_at'], startsWith('2026-09-20'));
    });

    test('limit trims the list and sets has_more', () async {
      final result = await _service().listSavedMeals(limit: 1);

      expect(_rows(result['saved_meals']), hasLength(1));
      expect(result['has_more'], isTrue);
      expect(result['total'], 2);
    });

    test('saved_meal_id returns items and every reported total', () async {
      final result = await _service().listSavedMeals(savedMealId: 'sm-new');

      expect(result['name'], 'Post workout');
      final items = _rows(result['items']);
      expect(items.map((item) => item['name']), [
        'Chicken breast',
        'Rolled oats',
      ]);
      expect(items.first['serving_label'], '1 fillet');
      expect(items.first['calories'], closeTo(660, 1e-9));
      expect(items.last['brand'], 'Quaker');
      expect(items.last['protein_g'], closeTo(13, 1e-9));
      final totals = result['totals'] as Map<String, dynamic>;
      expect(totals['magnesium_mg'], closeTo((58 + 88.5) * 2, 1e-9));
      expect(totals.containsKey('vitamin_d_ug'), isFalse);
    });

    test('an unknown saved_meal_id is not_found with a hint', () async {
      await expectLater(
        _service().listSavedMeals(savedMealId: 'nope'),
        throwsA(
          isA<AiToolNotFoundException>().having(
            (e) => e.hint,
            'hint',
            contains('list_saved_meals'),
          ),
        ),
      );
    });
  });

  group('result size on the heavy user', () {
    late HeavyUserFixture fixture;

    setUp(() async {
      await uninstallTestDb();
      final heavy = await installTestDb(seed: true);
      fixture = await seedHeavyUser(heavy);
    });

    test('every tool and mode stays within 6000 characters', () async {
      final service = AiNutritionToolService();
      final calls = <String, Future<Map<String, dynamic>> Function()>{
        'get_nutrition summary': service.nutrition,
        'get_nutrition summary 90': () => service.nutrition(days: 90),
        'get_nutrition daily 14': () => service.nutrition(detail: 'daily'),
        'get_nutrition daily 31': () =>
            service.nutrition(days: 31, detail: 'daily'),
        'get_nutrition daily 90': () =>
            service.nutrition(days: 90, detail: 'daily'),
        'get_nutrition micros 14': () => service.nutrition(detail: 'micros'),
        'get_nutrition micros 90': () =>
            service.nutrition(days: 90, detail: 'micros'),
        'get_nutrition foods 14': () => service.nutrition(detail: 'foods'),
        'get_nutrition foods 90': () =>
            service.nutrition(days: 90, detail: 'foods'),
        'diary day': () => service.diaryDay(date: fixture.diaryDate),
        'diary today': service.diaryDay,
        'search default': service.searchFoods,
        'search limit 30': () => service.searchFoods(limit: 30),
        'search query': () => service.searchFoods(query: 'a', limit: 30),
        'search food_id': () => service.searchFoods(foodId: fixture.foodId),
        'saved meals default': service.listSavedMeals,
        'saved meals 40': () => service.listSavedMeals(limit: 40),
        'saved meal detail': () =>
            service.listSavedMeals(savedMealId: fixture.savedMealId),
      };
      const shaper = AiToolResultShaper();
      final sizes = <String, int>{};
      for (final entry in calls.entries) {
        final raw = await entry.value();
        final shaped = shaper.shape(raw);
        final size = jsonEncode(shaped).length;
        sizes[entry.key] = size;
        expect(size, lessThanOrEqualTo(6000), reason: entry.key);
        // The default views must not need trimming at all.
        if (!entry.key.contains('90') && !entry.key.contains('limit 30')) {
          expect(
            shaped.containsKey('truncated_rows'),
            isFalse,
            reason: entry.key,
          );
        }
      }
      // ignore: avoid_print
      print(sizes.entries.map((e) => '${e.key}: ${e.value}').join('\n'));
    });

    test('the full 31 day listing is not trimmed', () async {
      final shaped = const AiToolResultShaper().shape(
        await AiNutritionToolService().nutrition(days: 31, detail: 'daily'),
      );
      expect(shaped.containsKey('truncated_rows'), isFalse);
      expect(shaped['logged_days'], greaterThan(25));
    });
  });
}
