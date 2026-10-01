import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/services/ai_tool_result_shaper.dart';
import 'package:workout_notes/services/ai_wellness_analytics_service.dart';
import 'package:workout_notes/utils/date_utils.dart';

import 'support/ai_heavy_user_fixture.dart';
import 'support/test_db.dart';

void main() {
  late Database database;
  late AiWellnessAnalyticsService service;
  // A Thursday: the current week (Mon 2026-08-10) is partial, the last full
  // week is 2026-08-03..2026-08-09.
  final now = DateTime(2026, 8, 13, 12);

  setUp(() async {
    database = await installTestDb(seed: true);
    service = AiWellnessAnalyticsService(now: () => now);
  });

  tearDown(uninstallTestDb);

  group('analyze_sleep_performance', () {
    Future<void> seed() async {
      for (var i = 0; i <= 6; i++) {
        await _sleep(database, dateKey(addDays(now, -i)), 400 + i * 10);
      }
      // Finished strength days with different feelings and volumes.
      await _workout(
        database,
        'w12',
        '2026-08-12',
        feeling: 4,
        sets: [
          (100, 10, true, false),
          (100, 8, true, false),
          (20, 10, true, true), // warm-up: not counted
          (100, 5, false, false), // not completed: not counted
        ],
      );
      await _workout(
        database,
        'w11',
        '2026-08-11',
        feeling: 2,
        sets: [(50, 10, true, false)],
      );
      await _workout(
        database,
        'w10',
        '2026-08-10',
        feeling: 3,
        sets: [(80, 10, true, false)],
      );
      await _workout(
        database,
        'w09',
        '2026-08-09',
        feeling: 5,
        sets: [(120, 10, true, false)],
      );
      await _workout(
        database,
        'w08',
        '2026-08-08',
        feeling: 4,
        sets: [(100, 8, true, false)],
      );
      // Never counted: in progress today, planned (past and future), and a
      // finished workout dated in the future.
      await _workout(
        database,
        'w-live',
        '2026-08-13',
        started: true,
        sets: [(60, 10, true, false)],
      );
      await _workout(
        database,
        'w-planned-past',
        '2026-08-07',
        sets: [(60, 10, false, false)],
      );
      await _workout(
        database,
        'w-planned',
        '2026-08-14',
        sets: [(60, 10, false, false)],
      );
      await _workout(
        database,
        'w-future',
        '2026-08-15',
        feeling: 5,
        sets: [(60, 10, true, false)],
      );
      await _run(
        database,
        'run-12',
        '2026-08-12T07:00:00.000',
        meters: 5000,
        rpe: 6,
      );
      await _run(
        database,
        'run-tomorrow',
        '2026-08-14T07:00:00.000',
        meters: 9000,
      );
      await _run(
        database,
        'run-draft',
        '2026-08-06T07:00:00.000',
        status: 'draft',
      );
    }

    test('pairs nights with finished training only', () async {
      await seed();

      final result = await service.sleepPerformance(days: 7);

      expect((result['applied'] as Map)['start_date'], '2026-08-07');
      expect((result['applied'] as Map)['end_date'], '2026-08-13');
      expect(result['sleep_nights'], 7);
      expect(result['paired_days'], 5);
      final pairs = (result['pairs'] as List).cast<Map<String, dynamic>>();
      expect(pairs.map((p) => p['date']), [
        '2026-08-12',
        '2026-08-11',
        '2026-08-10',
        '2026-08-09',
        '2026-08-08',
      ]);
      final first = pairs.first;
      expect(first['sleep_min'], 410);
      expect(first['volume_kg'], 1800);
      expect(first['sets'], 2);
      expect(first['feeling'], 4);
      expect(first['runs'], 1);
      expect(first['bike_rides'], 0);
      expect(first['cardio_km'], 5);
      expect(first['cardio_rpe'], 6);
      // A strength-only day has no cardio measurements (absent, not zero).
      expect(pairs[1]['cardio_km'], isNull);
      expect(pairs[1]['cardio_rpe'], isNull);
    });

    test('correlations keep three decimals and a quality label', () async {
      await seed();

      final result = await service.sleepPerformance(days: 7);
      final shaped = const AiToolResultShaper().shape(result);
      final feeling =
          (shaped['correlations'] as Map)['sleep_vs_feeling'] as Map;

      // r = 30 / sqrt(1000 * 5.2) = 0.41603...; one decimal would be 0.4.
      expect(feeling['coefficient'], 0.416);
      expect(feeling['sample_size'], 5);
      expect(feeling['quality'], 'low_sample');
      final volume = (shaped['correlations'] as Map)['sleep_vs_volume'] as Map;
      expect(volume['sample_size'], 5);
      expect(volume, contains('coefficient'));
    });

    test('too few pairs gives no coefficient', () async {
      await _sleep(database, '2026-08-12', 420);
      await _workout(
        database,
        'w',
        '2026-08-12',
        feeling: 4,
        sets: [(100, 10, true, false)],
      );

      final result = await service.sleepPerformance();

      final feeling =
          (result['correlations'] as Map)['sleep_vs_feeling'] as Map;
      expect(feeling['quality'], 'insufficient');
      expect(feeling['sample_size'], 1);
      expect(feeling, isNot(contains('coefficient')));
    });

    test(
      'uses the shared sleep resolver (session efficiency, estimates)',
      () async {
        await _sleep(database, '2026-08-12', 500, actual: null, estimated: 430);
        await database.insert('sleep_monitor_sessions', {
          'id': 's',
          'sleep_entry_id': 'sleep-2026-08-12',
          'status': 'completed',
          'started_at': '2026-08-11T23:00:00.000',
          'utc_offset_start_minutes': 0,
          'algorithm_version': 'audio-features-v5',
          'estimated_sleep_minutes': 415,
          'sleep_efficiency': 88.0,
          'created_at': '2026-08-11T23:00:00.000',
        });
        await _workout(
          database,
          'w',
          '2026-08-12',
          feeling: 4,
          sets: [(100, 10, true, false)],
        );

        final result = await service.sleepPerformance();

        final pair = (result['pairs'] as List).single as Map;
        expect(pair['sleep_min'], 415); // monitor estimate beats entry estimate
        expect(pair['efficiency_pct'], 88);
      },
    );

    test('lists at most 14 pairs, newest first, and a total', () async {
      for (var i = 1; i <= 20; i++) {
        final date = dateKey(addDays(now, -i));
        await _sleep(database, date, 420);
        await _workout(
          database,
          'w$i',
          date,
          feeling: 3,
          sets: [(50, 10, true, false)],
        );
      }

      final result = await service.sleepPerformance(days: 90);

      expect(result['paired_days'], 20);
      final pairs = result['pairs'] as List;
      expect(pairs, hasLength(14));
      expect((pairs.first as Map)['date'], '2026-08-12');
    });
  });

  group('analyze_nutrition_body_trend', () {
    test(
      'uses full weeks only, caps at today and converts weight to kg',
      () async {
        await _meal(database, '2026-08-09', 2000, 150);
        await _meal(database, '2026-08-08', 2400, 170);
        await _meal(database, '2026-08-03', 1800, 130);
        await _meal(database, '2026-07-28', 2200, 160);
        // Never counted: current partial week, the future, before the window.
        await _meal(database, '2026-08-12', 5000, 400);
        await _meal(database, '2026-08-14', 5000, 400);
        await _meal(database, '2026-07-26', 5000, 400);
        await _weight(database, '2026-08-09', 176, 'lb');
        await _weight(database, '2026-07-28', 180, 'lb');
        await _weight(database, '2026-08-12', 70, 'kg'); // partial week

        final result = await service.nutritionBodyTrend(days: 14);

        expect(result['applied'], containsPair('start_date', '2026-07-27'));
        expect(result['applied'], containsPair('end_date', '2026-08-09'));
        expect(result['logged_days'], 4);
        expect(result['weight_measurements'], 2);
        final weeks = (result['weeks'] as List).cast<Map<String, dynamic>>();
        expect(weeks.map((w) => w['week_start']), ['2026-08-03', '2026-07-27']);
        expect(weeks[0]['logged_days'], 3);
        expect(weeks[0]['calories'], closeTo(2066.67, 0.01));
        expect(weeks[0]['protein_g'], closeTo(150, 0.001));
        expect(weeks[0]['weight_kg'], closeTo(176 / 2.2046226218, 0.001));
        expect(weeks[1]['calories'], 2200);
        expect(
          result['weight_change_kg'],
          closeTo((176 - 180) / 2.2046226218, 0.001),
        );
        final correlation = result['calories_weight_correlation'] as Map;
        expect(correlation['quality'], 'insufficient');
      },
    );

    test('correlates weekly calories with weekly weight', () async {
      // 5 full weeks ending 2026-08-09, calories and weight rising together.
      for (var i = 0; i < 5; i++) {
        final monday = dateKey(addDays(DateTime(2026, 7, 6), 7 * i));
        await _meal(database, monday, 2000 + i * 100, 150);
        await _weight(database, monday, 80 + i * 0.5, 'kg');
      }

      final result = await service.nutritionBodyTrend(days: 35);

      final weeks = result['weeks'] as List;
      expect(weeks, hasLength(5));
      expect((weeks.first as Map)['week_start'], '2026-08-03');
      final correlation = result['calories_weight_correlation'] as Map;
      expect(correlation['sample_size'], 5);
      expect(correlation['coefficient'], closeTo(1, 0.0001));
      expect(result['weight_change_kg'], closeTo(2, 0.0001));
    });

    test('has no boilerplate, camelCase or zero placeholders', () async {
      final result = await service.nutritionBodyTrend();

      final json = jsonEncode(const AiToolResultShaper().shape(result));
      expect(json, isNot(contains('interpretationWarning')));
      expect(json, isNot(contains('weeklyTrend')));
      expect(result['weeks'], isEmpty);
      expect(result['weight_change_kg'], isNull);
    });
  });

  group('get_weekly_recovery_trend', () {
    Future<void> weekOfSleep(String monday, int minutes) async {
      await _sleep(database, monday, minutes);
    }

    test(
      'derives direction from the recent half versus the earlier half',
      () async {
        // Scores (sleep only, goal 480): 83.3, 41.7, 100, 83.3 oldest -> newest.
        // First vs last would say "stable"; the half means say "improving".
        await weekOfSleep('2026-07-13', 400);
        await weekOfSleep('2026-07-20', 200);
        await weekOfSleep('2026-07-27', 480);
        await weekOfSleep('2026-08-03', 400);
        // The partial current week must not become a row.
        await weekOfSleep('2026-08-10', 60);

        final result = await service.weeklyRecoveryTrend(weeks: 4);

        final weeks = (result['weeks'] as List).cast<Map<String, dynamic>>();
        expect(weeks.map((w) => w['week_start']), [
          '2026-08-03',
          '2026-07-27',
          '2026-07-20',
          '2026-07-13',
        ]);
        expect(weeks[0]['recovery_score'], closeTo(83.33, 0.01));
        expect(weeks[2]['recovery_score'], closeTo(41.67, 0.01));
        expect(result['direction'], 'improving');
        expect(result['score_change'], closeTo(29.17, 0.01));
        expect((result['applied'] as Map)['end_date'], '2026-08-09');
      },
    );

    test('is declining when the recent weeks are clearly worse', () async {
      await weekOfSleep('2026-07-20', 480);
      await weekOfSleep('2026-07-27', 460);
      await weekOfSleep('2026-08-03', 300);

      final result = await service.weeklyRecoveryTrend(weeks: 3);

      expect(result['direction'], 'declining');
    });

    test('needs at least two scored weeks', () async {
      await weekOfSleep('2026-08-03', 450);

      final result = await service.weeklyRecoveryTrend();

      expect(result['direction'], 'insufficient_data');
      expect(result['score_change'], isNull);
    });

    test(
      'counts finished training only and combines every component',
      () async {
        for (var i = 0; i < 7; i++) {
          await _sleep(
            database,
            dateKey(addDays(DateTime(2026, 8, 3), i)),
            450,
            timeInBed: 480,
            bedtime: 1380,
            wake: 450,
          );
        }
        await _workout(
          database,
          'w1',
          '2026-08-04',
          feeling: 4,
          sets: [(100, 10, true, false)],
        );
        await _workout(
          database,
          'w-planned',
          '2026-08-05',
          sets: [(100, 10, false, false)],
        );
        await _workout(
          database,
          'w-live',
          '2026-08-06',
          started: true,
          sets: [(100, 10, true, false)],
        );
        await _run(
          database,
          'r1',
          '2026-08-06T07:00:00.000',
          meters: 10000,
          rpe: 7,
        );
        await _run(
          database,
          'r-next-week',
          '2026-08-10T07:00:00.000',
          meters: 10000,
        );

        final result = await service.weeklyRecoveryTrend(weeks: 2);

        final row = (result['weeks'] as List).single as Map<String, dynamic>;
        expect(row['week_start'], '2026-08-03');
        expect(row['sleep_nights'], 7);
        expect(row['sleep_min'], 450);
        expect(row['efficiency_pct'], closeTo(93.75, 0.001));
        expect(row['regularity_score'], 100);
        expect(row['workouts'], 1);
        expect(row['volume_kg'], 1000);
        expect(row['runs'], 1);
        expect(row['cardio_km'], 10);
        expect(row['workout_feeling'], 4);
        // 0.5 * 93.75 + 0.2 * 93.75 + 0.2 * 100 + 0.1 * 80
        expect(row['recovery_score'], closeTo(93.625, 0.001));
      },
    );

    test('a week without sleep duration gets no score', () async {
      await _workout(
        database,
        'w1',
        '2026-08-04',
        feeling: 4,
        sets: [(100, 10, true, false)],
      );

      final result = await service.weeklyRecoveryTrend(weeks: 2);

      final shaped = const AiToolResultShaper().shape(result);
      final row = (shaped['weeks'] as List).single as Map;
      expect(row, isNot(contains('sleep_nights')));
      // A feeling alone cannot be compared with weeks scored on sleep.
      expect(row, isNot(contains('recovery_score')));
    });
  });

  group('result size on the heavy user', () {
    test('every wellness call fits in 6000 chars', () async {
      final today = DateTime(2026, 9, 30, 12);
      await uninstallTestDb();
      database = await installTestDb(seed: true);
      await seedHeavyUser(database, now: today);
      service = AiWellnessAnalyticsService(now: () => today);

      final calls = <String, Map<String, dynamic>>{
        'sleep_performance': await service.sleepPerformance(),
        'sleep_performance 90': await service.sleepPerformance(days: 90),
        'nutrition_body_trend': await service.nutritionBodyTrend(),
        'nutrition_body_trend 180': await service.nutritionBodyTrend(days: 180),
        'weekly_recovery_trend': await service.weeklyRecoveryTrend(),
        'weekly_recovery_trend 12': await service.weeklyRecoveryTrend(
          weeks: 12,
        ),
      };
      final sizes = {
        for (final e in calls.entries)
          e.key: jsonEncode(const AiToolResultShaper().shape(e.value)).length,
      };
      // ignore: avoid_print
      print('wellness tool sizes: $sizes');
      for (final entry in sizes.entries) {
        expect(entry.value, lessThanOrEqualTo(6000), reason: entry.key);
      }
      expect(calls['weekly_recovery_trend']!['weeks'] as List, isNotEmpty);
      expect(
        (calls['sleep_performance']!['pairs'] as List).length,
        lessThanOrEqualTo(14),
      );
    });
  });
}

Future<void> _sleep(
  Database database,
  String date,
  int minutes, {
  int? actual,
  int? estimated,
  int? timeInBed,
  int? bedtime,
  int? wake,
}) => database.insert('sleep_entries', {
  'id': 'sleep-$date',
  'date': date,
  'sleep_minutes': minutes,
  'actual_sleep_minutes': actual ?? (estimated == null ? minutes : null),
  'estimated_sleep_minutes': estimated,
  'time_in_bed_minutes': timeInBed,
  'bedtime_minutes': bedtime,
  'wake_time_minutes': wake,
  'source': 'manual',
  'created_at': '2026-08-13T07:00:00.000',
});

/// [sets] are `(weight, reps, complete, warmup)`. A workout with neither
/// [started] nor [feeling] is planned; one that has a feeling is finished.
Future<void> _workout(
  Database database,
  String id,
  String date, {
  int? feeling,
  bool started = false,
  required List<(double, int, bool, bool)> sets,
}) async {
  final finished = feeling != null;
  await database.insert('workouts', {
    'id': id,
    'date': date,
    'start_time': finished || started ? '${date}T18:00:00.000' : null,
    'end_time': finished ? '${date}T19:00:00.000' : null,
    'duration_seconds': finished ? 3600 : null,
    'feeling_rating': feeling,
    'is_from_routine': 0,
    'created_at': '${date}T18:00:00.000',
  });
  await database.insert('exercise_entries', {
    'id': '$id-e',
    'workout_id': id,
    'exercise_id': 'bench_press',
    'order_index': 0,
  });
  for (var i = 0; i < sets.length; i++) {
    final (weight, reps, complete, warmup) = sets[i];
    await database.insert('sets', {
      'id': '$id-s$i',
      'exercise_entry_id': '$id-e',
      'weight': weight,
      'reps': reps,
      'is_complete': complete ? 1 : 0,
      'is_warmup': warmup ? 1 : 0,
      'order_index': i,
    });
  }
}

Future<void> _run(
  Database database,
  String id,
  String startedAt, {
  double meters = 5000,
  double? rpe,
  String status = 'completed',
}) => database.insert('run_activities', {
  'id': id,
  'activity_type': 'running',
  'started_at': startedAt,
  'duration_seconds': 1800,
  'moving_time_seconds': 1700,
  'distance_meters': meters,
  'rpe': rpe,
  'status': status,
  'created_at': startedAt,
  'updated_at': startedAt,
});

Future<void> _meal(
  Database database,
  String date,
  double calories,
  double protein,
) async {
  final id = date.replaceAll('-', '');
  await database.insert('meal_logs', {
    'id': 'meal-$id',
    'date': date,
    'meal_type': 'daily-$id',
    'created_at': '${date}T12:00:00.000',
  });
  await database.insert('meal_log_items', {
    'id': 'item-$id',
    'meal_log_id': 'meal-$id',
    'food_name_snapshot': 'Total',
    'quantity': 1,
    'unit': 'portion',
    'calories': calories,
    'protein_g': protein,
    'carbs_g': 200,
    'fat_g': 60,
    'nutrition_snapshot_json': '{}',
    'created_at': '${date}T12:00:00.000',
  });
}

Future<void> _weight(
  Database database,
  String date,
  double value,
  String unit,
) => database.insert('body_measurements', {
  'id': 'weight-$date',
  'type': 'weight',
  'value': value,
  'unit': unit,
  'date': date,
  'created_at': '${date}T07:00:00.000',
});
