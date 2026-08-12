import 'dart:convert';

import 'test_data_context.dart';

class WellnessGenerationResult {
  final int sleepNights;
  final int monitoredNights;
  final int nutritionDays;
  final int meals;
  final int goals;

  const WellnessGenerationResult({
    required this.sleepNights,
    required this.monitoredNights,
    required this.nutritionDays,
    required this.meals,
    required this.goals,
  });
}

/// Generates the wellness domains that used to be absent from the debug seed:
/// sleep monitoring/stages and a complete nutrition diary.
class TestDataWellnessGenerator {
  final TestDataContext context;

  TestDataWellnessGenerator(this.context);

  Future<WellnessGenerationResult> generate() async {
    final sleep = await _sleep();
    final nutrition = await _nutrition();
    return WellnessGenerationResult(
      sleepNights: sleep.$1,
      monitoredNights: sleep.$2,
      nutritionDays: nutrition.$1,
      meals: nutrition.$2,
      goals: nutrition.$3,
    );
  }

  Future<(int, int)> _sleep() async {
    final totalDays = context.now.difference(context.start).inDays;
    var nights = 0;
    var monitored = 0;
    for (var day = 0; day <= totalDays; day++) {
      if (context.random.nextDouble() < 0.06) continue;
      final wakeDate = context.start.add(Duration(days: day));
      final date = context.date(wakeDate);
      final existing = await context.database.query(
        'sleep_entries',
        columns: const ['id'],
        where: 'date = ?',
        whereArgs: [date],
        limit: 1,
      );
      // Never replace a real sleep record that happens to occupy this date.
      if (existing.isNotEmpty) continue;

      final weekend =
          wakeDate.weekday == DateTime.saturday ||
          wakeDate.weekday == DateTime.sunday;
      final bedtime =
          (context.jitter(22 * 60 + 50 + (weekend ? 35 : 0), 38)).round() %
          1440;
      final timeInBed = context
          .jitter(475 + (weekend ? 30 : 0), 48)
          .round()
          .clamp(330, 600);
      final awake = context.jitter(37, 16).round().clamp(12, 95);
      final actual = (timeInBed - awake).clamp(270, timeInBed);
      final wakeMinutes = (bedtime + timeInBed) % 1440;
      final entryId = context.id('sleep', day);
      final isMonitored =
          day >= totalDays - 28 && context.random.nextDouble() < 0.55;
      await context.database.insert('sleep_entries', {
        'id': entryId,
        'date': date,
        'sleep_minutes': timeInBed,
        'actual_sleep_minutes': actual,
        'bedtime_minutes': bedtime,
        'wake_time_minutes': wakeMinutes,
        'comment': actual < 390
            ? 'Noite mais curta que o habitual'
            : context.random.nextDouble() < 0.12
            ? 'Acordei descansado'
            : null,
        'source': isMonitored ? 'monitored' : 'manual',
        'time_in_bed_minutes': timeInBed,
        'estimated_sleep_minutes': isMonitored ? actual : null,
        'created_at': wakeDate
            .add(Duration(minutes: wakeMinutes))
            .toIso8601String(),
      });
      nights++;
      if (isMonitored) {
        await _monitoredNight(
          entryId: entryId,
          sequence: day,
          wakeDate: wakeDate,
          bedtimeMinutes: bedtime,
          timeInBed: timeInBed,
          actualSleep: actual,
          awakeMinutes: awake,
        );
        monitored++;
      }
    }
    return (nights, monitored);
  }

  Future<void> _monitoredNight({
    required String entryId,
    required int sequence,
    required DateTime wakeDate,
    required int bedtimeMinutes,
    required int timeInBed,
    required int actualSleep,
    required int awakeMinutes,
  }) async {
    final startDay = bedtimeMinutes > 12 * 60
        ? wakeDate.subtract(const Duration(days: 1))
        : wakeDate;
    final startedAt = DateTime(
      startDay.year,
      startDay.month,
      startDay.day,
    ).add(Duration(minutes: bedtimeMinutes));
    final endedAt = startedAt.add(Duration(minutes: timeInBed));
    final latency = context.random.nextInt(22) + 6;
    final deep = (actualSleep * context.jitter(0.21, 0.035)).round();
    final sleeping = (actualSleep - deep).clamp(0, actualSleep);
    final sessionId = context.id('sleep_session', sequence);
    await context.database.insert('sleep_monitor_sessions', {
      'id': sessionId,
      'sleep_entry_id': entryId,
      'status': 'completed',
      'started_at': startedAt.toIso8601String(),
      'ended_at': endedAt.toIso8601String(),
      'alarm_at': endedAt.toIso8601String(),
      'monitor_mode': sequence.isEven
          ? 'alarm_without_mission'
          : 'monitoring_only',
      'alarm_dismiss_method': sequence.isEven ? 'button' : null,
      'alarm_dismissed_at': sequence.isEven
          ? endedAt.add(const Duration(minutes: 2)).toIso8601String()
          : null,
      'utc_offset_start_minutes': -180,
      'utc_offset_end_minutes': -180,
      'sensor_mode': 'audio',
      'algorithm_version': 'dev-scenario-v1',
      'time_in_bed_minutes': timeInBed,
      'quiet_minutes': (timeInBed * 0.82).round(),
      'noisy_minutes': (timeInBed * 0.18).round(),
      'estimated_sleep_minutes': actualSleep,
      'noise_event_count': 2 + context.random.nextInt(9),
      'signal_quality_score': double.parse(
        context.jitter(0.86, 0.09).clamp(0.5, 0.99).toStringAsFixed(2),
      ),
      'analysis_status': 'available',
      'sleep_onset_at': startedAt
          .add(Duration(minutes: latency))
          .toIso8601String(),
      'final_wake_at': endedAt
          .subtract(const Duration(minutes: 3))
          .toIso8601String(),
      'sleep_latency_minutes': latency,
      'awake_minutes': awakeMinutes,
      'sleeping_minutes': sleeping,
      'deep_sleep_minutes': deep,
      'unknown_minutes': 0,
      'awakening_count': 1 + context.random.nextInt(5),
      'sleep_efficiency': double.parse(
        (actualSleep / timeInBed * 100).toStringAsFixed(1),
      ),
      'stage_confidence': double.parse(
        context.jitter(0.81, 0.08).clamp(0.5, 0.98).toStringAsFixed(2),
      ),
      'stage_algorithm_version': 'dev-stage-v1',
      'end_reason': 'alarm',
      'created_at': endedAt.toIso8601String(),
    });

    final epochCount = (timeInBed / 30).ceil();
    for (var epoch = 0; epoch < epochCount; epoch++) {
      final progress = epoch / epochCount;
      final stage = epoch == 0 || epoch == epochCount - 1
          ? 'awake'
          : progress < 0.58 && epoch % 4 != 0
          ? 'deep'
          : 'sleeping';
      await context.database.insert('sleep_stage_epochs', {
        'id': context.id('sleep_epoch', '$sequence:$epoch'),
        'session_id': sessionId,
        'started_at': startedAt
            .add(Duration(minutes: epoch * 30))
            .toIso8601String(),
        'duration_seconds': epoch == epochCount - 1
            ? (timeInBed - epoch * 30) * 60
            : 1800,
        'stage': stage,
        'confidence': double.parse(
          context.jitter(0.84, 0.1).clamp(0.5, 0.99).toStringAsFixed(2),
        ),
        'awake_probability': stage == 'awake' ? 0.82 : 0.08,
        'sleeping_probability': stage == 'sleeping' ? 0.82 : 0.14,
        'deep_probability': stage == 'deep' ? 0.78 : 0.06,
        'algorithm_version': 'dev-stage-v1',
        'source': 'acoustic_model',
      });
    }

    // A small representative sample is enough to exercise diagnostics without
    // creating thousands of sensor rows per click.
    for (var segment = 0; segment < 8; segment++) {
      final noisy = segment == 2 || segment == 6;
      await context.database.insert('sleep_monitor_segments', {
        'id': context.id('sleep_segment', '$sequence:$segment'),
        'session_id': sessionId,
        'started_at': startedAt
            .add(Duration(minutes: segment * timeInBed ~/ 8))
            .toIso8601String(),
        'duration_seconds': 30,
        'audio_rms_dbfs': noisy ? -31.0 : -52.0,
        'audio_peak_dbfs': noisy ? -16.0 : -39.0,
        'noise_score': noisy ? 0.76 : 0.16,
        'classification': noisy ? 'noisy' : 'quiet',
        'valid_fraction': 0.98,
        'noise_burst_count': noisy ? 2 : 0,
        'spectral_flatness': noisy ? 0.58 : 0.24,
        'spectral_centroid_hz': noisy ? 1380.0 : 420.0,
        'breathing_regularity': noisy ? 0.55 : 0.88,
        'breathing_rate_hz': 0.24,
        'motion_active_seconds': noisy ? 4.5 : 0.6,
        'motion_mean_deviation_g': noisy ? 0.09 : 0.015,
        'motion_max_deviation_g': noisy ? 0.32 : 0.06,
      });
    }
  }

  Future<(int, int, int)> _nutrition() async {
    final foods = _foods;
    for (var index = 0; index < foods.length; index++) {
      final food = foods[index];
      final foodId = context.id('food', index);
      final variantId = context.id('food_variant', index);
      await context.database.insert('foods', {
        'id': foodId,
        'source': 'manual',
        'external_id': context.id('food_external', index),
        'name': food.name,
        'search_name': food.name.toLowerCase(),
        'brand': food.brand,
        'fetched_at': context.now.toIso8601String(),
        'last_used_at': context.now
            .subtract(Duration(days: context.random.nextInt(8)))
            .toIso8601String(),
        'is_favorite': index < 4 ? 1 : 0,
      });
      await context.database.insert('food_variants', {
        'id': variantId,
        'food_id': foodId,
        'label': 'Porção habitual',
        'reference_amount': 1.0,
        'reference_unit': 'serving',
        ...food.values,
        'is_estimated': 0,
      });
      await context.database.insert('food_servings', {
        'id': context.id('food_serving', index),
        'food_variant_id': variantId,
        'label': '1 porção',
        'quantity': 1.0,
        'unit': 'serving',
        'grams_equivalent': food.grams,
      });
    }
    await _savedMeals();

    var days = 0;
    var meals = 0;
    final totalDays = context.now.difference(context.start).inDays;
    final firstNutritionDay = (totalDays - 83).clamp(0, totalDays);
    for (var day = firstNutritionDay; day <= totalDays; day++) {
      if (context.random.nextDouble() < 0.08) continue;
      final date = context.start.add(Duration(days: day));
      var dayHasMeal = false;
      for (final meal in _mealPlans) {
        if (meal.type == 'snacks' && context.random.nextDouble() < 0.28) {
          continue;
        }
        final dateString = context.date(date);
        final occupied = await context.database.query(
          'meal_logs',
          columns: const ['id'],
          where: 'date = ? AND meal_type = ?',
          whereArgs: [dateString, meal.type],
          limit: 1,
        );
        // Keep user-entered meals intact; the generated diary simply skips
        // occupied sections.
        if (occupied.isNotEmpty) continue;
        final logId = context.id('meal', '$day:${meal.type}');
        final createdAt = date.add(
          Duration(hours: meal.hour, minutes: context.random.nextInt(35)),
        );
        await context.database.insert('meal_logs', {
          'id': logId,
          'date': dateString,
          'meal_type': meal.type,
          'created_at': createdAt.toIso8601String(),
        });
        final choices =
            meal.options[context.random.nextInt(meal.options.length)];
        for (var itemIndex = 0; itemIndex < choices.length; itemIndex++) {
          final foodIndex = choices[itemIndex];
          final food = foods[foodIndex];
          final multiplier = context.jitter(1.0, 0.12).clamp(0.75, 1.3);
          final consumed = <String, double?>{
            for (final entry in food.values.entries)
              entry.key: entry.value == null
                  ? null
                  : double.parse(
                      (entry.value! * multiplier).toStringAsFixed(2),
                    ),
          };
          final snapshot = {
            'version': 3,
            'source': 'manual',
            'external_id': context.id('food_external', foodIndex),
            'food_name': food.name,
            'food_brand': food.brand,
            'variant_label': 'Porção habitual',
            'reference_amount': 1.0,
            'reference_unit': 'serving',
            'quantity': double.parse(multiplier.toStringAsFixed(2)),
            'unit': 'serving',
            'grams_equivalent': food.grams,
            'ml_equivalent': null,
            'consumed': consumed,
            'is_estimated': false,
            'has_missing_values': false,
          };
          await context.database.insert('meal_log_items', {
            'id': context.id('meal_item', '$day:${meal.type}:$itemIndex'),
            'meal_log_id': logId,
            'food_id': context.id('food', foodIndex),
            'food_variant_id': context.id('food_variant', foodIndex),
            'food_name_snapshot': food.name,
            'brand_snapshot': food.brand,
            'quantity': double.parse(multiplier.toStringAsFixed(2)),
            'unit': 'serving',
            ...consumed,
            'nutrition_snapshot_json': jsonEncode(snapshot),
            'created_at': createdAt
                .add(Duration(minutes: itemIndex))
                .toIso8601String(),
          });
        }
        meals++;
        dayHasMeal = true;
      }
      if (dayHasMeal) days++;
    }

    await context.database.insert('nutrition_goals', {
      'id': context.id('nutrition_goal', 0),
      'calories': 2200.0,
      'protein_g': 150.0,
      'carbs_g': 245.0,
      'fat_g': 68.0,
      'created_at': context.start.toIso8601String(),
      'updated_at': context.now.toIso8601String(),
      'is_active': 1,
    });
    return (days, meals, 1);
  }

  Future<void> _savedMeals() async {
    final templates = <(String, String, List<int>)>[
      ('Café da manhã rápido', 'breakfast', [0, 1, 2]),
      ('Marmita equilibrada', 'lunch', [4, 5, 6, 8]),
    ];
    for (var mealIndex = 0; mealIndex < templates.length; mealIndex++) {
      final template = templates[mealIndex];
      final savedMealId = context.id('saved_meal', mealIndex);
      await context.database.insert('saved_meals', {
        'id': savedMealId,
        'name': template.$1,
        'meal_type': template.$2,
        'portions': 1.0,
        'created_at': context.start.toIso8601String(),
        'updated_at': context.now.toIso8601String(),
      });
      for (var order = 0; order < template.$3.length; order++) {
        final foodIndex = template.$3[order];
        final food = _foods[foodIndex];
        await context.database.insert('saved_meal_items', {
          'id': context.id('saved_meal_item', '$mealIndex:$order'),
          'saved_meal_id': savedMealId,
          'food_id': context.id('food', foodIndex),
          'food_variant_id': context.id('food_variant', foodIndex),
          'food_name_snapshot': food.name,
          'brand_snapshot': food.brand,
          'quantity': 1.0,
          'unit': 'serving',
          'serving_label': '1 porção',
          'serving_grams_equivalent': food.grams,
          'order_index': order,
        });
      }
    }
  }
}

class _FoodSeed {
  final String name;
  final String? brand;
  final double grams;
  final Map<String, double?> values;

  const _FoodSeed(this.name, this.grams, this.values, [this.brand]);
}

class _MealPlan {
  final String type;
  final int hour;
  final List<List<int>> options;

  const _MealPlan(this.type, this.hour, this.options);
}

const _mealPlans = <_MealPlan>[
  _MealPlan('breakfast', 7, [
    [0, 1, 2],
    [0, 3, 7],
  ]),
  _MealPlan('lunch', 12, [
    [4, 5, 6],
    [4, 5, 8],
  ]),
  _MealPlan('dinner', 19, [
    [4, 6, 8],
    [5, 6, 9],
  ]),
  _MealPlan('snacks', 16, [
    [2, 3],
    [1, 7],
  ]),
];

const _foods = <_FoodSeed>[
  _FoodSeed('Ovos mexidos', 100, {
    'calories': 155,
    'protein_g': 13,
    'carbs_g': 1.1,
    'fat_g': 11,
    'saturated_fat_g': 3.3,
    'monounsaturated_fat_g': 4.1,
    'polyunsaturated_fat_g': 1.4,
    'trans_fat_g': 0,
    'fiber_g': 0,
    'sugars_g': 1.1,
    'sodium_mg': 124,
    'potassium_mg': 126,
    'calcium_mg': 50,
    'iron_mg': 1.2,
    'magnesium_mg': 10,
    'zinc_mg': 1.0,
    'vitamin_a_ug': 149,
    'vitamin_c_mg': 0,
    'vitamin_d_ug': 2.0,
    'vitamin_b12_ug': 1.1,
  }),
  _FoodSeed('Pão integral', 50, {
    'calories': 126,
    'protein_g': 5,
    'carbs_g': 23,
    'fat_g': 1.8,
    'saturated_fat_g': 0.3,
    'monounsaturated_fat_g': 0.4,
    'polyunsaturated_fat_g': 0.7,
    'trans_fat_g': 0,
    'fiber_g': 3.5,
    'sugars_g': 2.8,
    'sodium_mg': 210,
    'potassium_mg': 115,
    'calcium_mg': 54,
    'iron_mg': 1.3,
    'magnesium_mg': 38,
    'zinc_mg': 0.7,
    'vitamin_a_ug': 0,
    'vitamin_c_mg': 0,
    'vitamin_d_ug': 0,
    'vitamin_b12_ug': 0,
  }),
  _FoodSeed('Banana', 100, {
    'calories': 89,
    'protein_g': 1.1,
    'carbs_g': 23,
    'fat_g': 0.3,
    'saturated_fat_g': 0.1,
    'monounsaturated_fat_g': 0,
    'polyunsaturated_fat_g': 0.1,
    'trans_fat_g': 0,
    'fiber_g': 2.6,
    'sugars_g': 12,
    'sodium_mg': 1,
    'potassium_mg': 358,
    'calcium_mg': 5,
    'iron_mg': 0.3,
    'magnesium_mg': 27,
    'zinc_mg': 0.2,
    'vitamin_a_ug': 3,
    'vitamin_c_mg': 8.7,
    'vitamin_d_ug': 0,
    'vitamin_b12_ug': 0,
  }),
  _FoodSeed('Iogurte natural', 170, {
    'calories': 104,
    'protein_g': 6,
    'carbs_g': 8,
    'fat_g': 5.5,
    'saturated_fat_g': 3.5,
    'monounsaturated_fat_g': 1.5,
    'polyunsaturated_fat_g': 0.2,
    'trans_fat_g': 0.2,
    'fiber_g': 0,
    'sugars_g': 8,
    'sodium_mg': 78,
    'potassium_mg': 260,
    'calcium_mg': 207,
    'iron_mg': 0.1,
    'magnesium_mg': 20,
    'zinc_mg': 1.0,
    'vitamin_a_ug': 46,
    'vitamin_c_mg': 1,
    'vitamin_d_ug': 0.1,
    'vitamin_b12_ug': 0.6,
  }, 'Fazenda Dev'),
  _FoodSeed('Arroz integral', 160, {
    'calories': 198,
    'protein_g': 4.2,
    'carbs_g': 41,
    'fat_g': 1.6,
    'saturated_fat_g': 0.3,
    'monounsaturated_fat_g': 0.6,
    'polyunsaturated_fat_g': 0.5,
    'trans_fat_g': 0,
    'fiber_g': 2.8,
    'sugars_g': 0.3,
    'sodium_mg': 5,
    'potassium_mg': 135,
    'calcium_mg': 16,
    'iron_mg': 0.8,
    'magnesium_mg': 68,
    'zinc_mg': 1.2,
    'vitamin_a_ug': 0,
    'vitamin_c_mg': 0,
    'vitamin_d_ug': 0,
    'vitamin_b12_ug': 0,
  }),
  _FoodSeed('Feijão carioca', 140, {
    'calories': 106,
    'protein_g': 6.7,
    'carbs_g': 19,
    'fat_g': 0.7,
    'saturated_fat_g': 0.1,
    'monounsaturated_fat_g': 0.1,
    'polyunsaturated_fat_g': 0.3,
    'trans_fat_g': 0,
    'fiber_g': 8.5,
    'sugars_g': 0.5,
    'sodium_mg': 3,
    'potassium_mg': 358,
    'calcium_mg': 38,
    'iron_mg': 2.1,
    'magnesium_mg': 58,
    'zinc_mg': 1.0,
    'vitamin_a_ug': 0,
    'vitamin_c_mg': 1.2,
    'vitamin_d_ug': 0,
    'vitamin_b12_ug': 0,
  }),
  _FoodSeed('Peito de frango grelhado', 150, {
    'calories': 248,
    'protein_g': 46,
    'carbs_g': 0,
    'fat_g': 5.4,
    'saturated_fat_g': 1.5,
    'monounsaturated_fat_g': 1.8,
    'polyunsaturated_fat_g': 1.2,
    'trans_fat_g': 0,
    'fiber_g': 0,
    'sugars_g': 0,
    'sodium_mg': 111,
    'potassium_mg': 384,
    'calcium_mg': 23,
    'iron_mg': 1.5,
    'magnesium_mg': 44,
    'zinc_mg': 1.5,
    'vitamin_a_ug': 20,
    'vitamin_c_mg': 0,
    'vitamin_d_ug': 0.2,
    'vitamin_b12_ug': 0.5,
  }),
  _FoodSeed('Aveia', 40, {
    'calories': 152,
    'protein_g': 5.2,
    'carbs_g': 27,
    'fat_g': 2.8,
    'saturated_fat_g': 0.5,
    'monounsaturated_fat_g': 0.9,
    'polyunsaturated_fat_g': 1.0,
    'trans_fat_g': 0,
    'fiber_g': 4.2,
    'sugars_g': 0.4,
    'sodium_mg': 2,
    'potassium_mg': 145,
    'calcium_mg': 21,
    'iron_mg': 1.7,
    'magnesium_mg': 71,
    'zinc_mg': 1.4,
    'vitamin_a_ug': 0,
    'vitamin_c_mg': 0,
    'vitamin_d_ug': 0,
    'vitamin_b12_ug': 0,
  }),
  _FoodSeed('Legumes variados', 150, {
    'calories': 78,
    'protein_g': 3.5,
    'carbs_g': 14,
    'fat_g': 1.0,
    'saturated_fat_g': 0.2,
    'monounsaturated_fat_g': 0.3,
    'polyunsaturated_fat_g': 0.3,
    'trans_fat_g': 0,
    'fiber_g': 5.0,
    'sugars_g': 6.0,
    'sodium_mg': 65,
    'potassium_mg': 430,
    'calcium_mg': 62,
    'iron_mg': 1.4,
    'magnesium_mg': 39,
    'zinc_mg': 0.7,
    'vitamin_a_ug': 420,
    'vitamin_c_mg': 42,
    'vitamin_d_ug': 0,
    'vitamin_b12_ug': 0,
  }),
  _FoodSeed('Salmão grelhado', 140, {
    'calories': 288,
    'protein_g': 31,
    'carbs_g': 0,
    'fat_g': 18,
    'saturated_fat_g': 3.8,
    'monounsaturated_fat_g': 6.2,
    'polyunsaturated_fat_g': 5.6,
    'trans_fat_g': 0,
    'fiber_g': 0,
    'sugars_g': 0,
    'sodium_mg': 83,
    'potassium_mg': 510,
    'calcium_mg': 18,
    'iron_mg': 0.7,
    'magnesium_mg': 41,
    'zinc_mg': 0.9,
    'vitamin_a_ug': 42,
    'vitamin_c_mg': 0,
    'vitamin_d_ug': 15,
    'vitamin_b12_ug': 4.5,
  }),
];
