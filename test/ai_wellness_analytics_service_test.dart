import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/services/ai_wellness_analytics_service.dart';

import 'support/ai_test_db.dart';

void main() {
  late Database database;
  late AiWellnessAnalyticsService service;
  final now = DateTime(2026, 8, 10, 12);

  setUp(() async {
    database = await installAiTestDb();
    service = AiWellnessAnalyticsService(now: () => now);
  });

  tearDown(uninstallAiTestDb);

  test(
    'sleep summary reports coverage, effective duration and regularity',
    () async {
      for (var i = 0; i < 7; i++) {
        await database.insert('sleep_entries', {
          'id': 'sleep-$i',
          'date': _date(now.subtract(Duration(days: i))),
          'sleep_minutes': 480,
          'actual_sleep_minutes': 450 + i,
          'bedtime_minutes': 1380 + i * 2,
          'wake_time_minutes': 420 + i * 2,
          'time_in_bed_minutes': 480,
          'source': 'manual',
          'created_at': now.toIso8601String(),
        });
      }

      final result = await service.sleepSummary(days: 7);

      expect(result['recordedNights'], 7);
      expect(result['coveragePct'], 100.0);
      expect(result['averageSleepMinutes'], 453.0);
      expect(result['scheduleRegularityScore'], greaterThan(90));
      expect(result['recentNights'], hasLength(7));
    },
  );

  test(
    'nutrition summary aggregates macros without treating missing days as zero',
    () async {
      await insertMeal(
        database,
        now,
        date: '2026-08-10',
        calories: 2200,
        protein: 150,
      );
      await insertMeal(
        database,
        now,
        date: '2026-08-09',
        calories: 1800,
        protein: 130,
      );
      await database.insert('nutrition_goals', {
        'id': 'goal',
        'calories': 2000,
        'protein_g': 140,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
        'is_active': 1,
      });

      final result = await service.nutritionSummary(days: 7);
      final averages = result['dailyAverage'] as Map;

      expect(result['loggedDays'], 2);
      expect(averages['calories'], 2000.0);
      expect(averages['proteinG'], 140.0);
      expect((result['activeDailyGoal'] as Map)['calories'], 2000.0);
    },
  );

  test(
    'sleep-performance analysis returns sample size and descriptive correlation',
    () async {
      for (var i = 0; i < 5; i++) {
        final date = _date(now.subtract(Duration(days: i)));
        await database.insert('sleep_entries', {
          'id': 'sleep-$i',
          'date': date,
          'sleep_minutes': 360 + i * 30,
          'actual_sleep_minutes': 360 + i * 30,
          'source': 'manual',
          'created_at': now.toIso8601String(),
        });
        await database.insert('workouts', {
          'id': 'workout-$i',
          'date': date,
          'feeling_rating': 2 + i * .5,
          'duration_seconds': 3600,
          'is_from_routine': 0,
          'created_at': now.toIso8601String(),
        });
      }

      final result = await service.sleepPerformance(days: 7);
      final correlations = result['correlations'] as Map;
      final feeling = correlations['sleepMinutesVsFeeling'] as Map;

      expect(result['pairedDays'], 5);
      expect(feeling['sampleSize'], 5);
      expect((feeling['coefficient'] as num).abs(), greaterThan(.99));
      expect(result['interpretationWarning'], contains('causation'));
    },
  );

  test(
    'nutrition-body trend groups intake and normalized weight by week',
    () async {
      for (var i = 0; i < 4; i++) {
        final day = now.subtract(Duration(days: i * 7));
        final date = _date(day);
        await insertMeal(
          database,
          now,
          date: date,
          calories: 1800 + i * 100,
          protein: 130 + i * 5,
        );
        await database.insert('body_measurements', {
          'id': 'weight-$i',
          'type': 'weight',
          'value': 176 + i * 2.2,
          'unit': 'lb',
          'date': date,
          'created_at': now.toIso8601String(),
        });
      }

      final result = await service.nutritionBodyTrend(days: 35);
      final correlation = result['caloriesVsWeightCorrelation'] as Map;

      expect(result['loggedNutritionDays'], 4);
      expect(result['weightMeasurements'], 4);
      expect(result['weeklyTrend'], hasLength(4));
      expect(correlation['sampleSize'], 4);
      expect((correlation['coefficient'] as num).abs(), greaterThan(.99));
    },
  );

  test(
    'weekly recovery is bounded and reports its non-clinical method',
    () async {
      for (var i = 0; i < 14; i++) {
        final date = _date(now.subtract(Duration(days: i)));
        await database.insert('sleep_entries', {
          'id': 'recovery-sleep-$i',
          'date': date,
          'sleep_minutes': 450,
          'actual_sleep_minutes': 430 + (i % 3) * 10,
          'time_in_bed_minutes': 470,
          'bedtime_minutes': 1380 + i % 4,
          'wake_time_minutes': 390 + i % 4,
          'source': 'manual',
          'created_at': now.toIso8601String(),
        });
        if (i.isEven) {
          await database.insert('workouts', {
            'id': 'recovery-workout-$i',
            'date': date,
            'feeling_rating': 4,
            'duration_seconds': 3000,
            'is_from_routine': 0,
            'created_at': now.toIso8601String(),
          });
        }
      }

      final result = await service.weeklyRecoveryTrend(weeks: 2);
      final trend = result['weeklyTrend'] as List;

      expect(trend, isNotEmpty);
      for (final raw in trend) {
        final score = (raw as Map)['recoveryScore'] as num?;
        if (score != null) expect(score, inInclusiveRange(0, 100));
      }
      expect(result['method'], contains('non-clinical'));
    },
  );
}

String _date(DateTime value) => value.toIso8601String().substring(0, 10);

Future<void> insertMeal(
  Database database,
  DateTime now, {
  required String date,
  required double calories,
  required double protein,
}) async {
  final id = date.replaceAll('-', '');
  await database.insert('meal_logs', {
    'id': 'meal-$id',
    'date': date,
    'meal_type': 'daily-$id',
    'created_at': now.toIso8601String(),
  });
  await database.insert('meal_log_items', {
    'id': 'item-$id',
    'meal_log_id': 'meal-$id',
    'food_name_snapshot': 'Total do dia',
    'quantity': 1,
    'unit': 'porção',
    'calories': calories,
    'protein_g': protein,
    'carbs_g': 200,
    'fat_g': 60,
    'fiber_g': 25,
    'sugars_g': 20,
    'sodium_mg': 1000,
    'nutrition_snapshot_json': '{}',
    'created_at': now.toIso8601String(),
  });
}
