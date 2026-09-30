// Read-only queries built for the AI Coach may run SQL directly (a documented
// exception to the repository-only rule); writes never happen in this file.
import 'dart:math' as math;

import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/services/ai_tool_math.dart';
import 'package:workout_notes/services/effective_nutrition_goal_service.dart';
import 'package:workout_notes/utils/date_utils.dart';

/// Read-only, compact wellness analytics used by the AI Coach tools.
///
/// The service deliberately aggregates in SQLite and returns bounded time
/// series. Raw meal items and sleep-monitor segments never enter the model
/// context. Correlations are descriptive and are only reported with enough
/// paired observations.
class AiWellnessAnalyticsService {
  final DatabaseHelper db;
  final DateTime Function() _now;

  AiWellnessAnalyticsService({DatabaseHelper? db, DateTime Function()? now})
    : db = db ?? DatabaseHelper.instance,
      _now = now ?? DateTime.now;

  Future<Map<String, dynamic>> sleepSummary({int days = 14}) async {
    days = days.clamp(3, 90);
    final rows = await _sleepRows(days);
    final durations = rows.map(_effectiveSleep).whereType<double>().toList();
    final efficiencies = rows
        .map(_sleepEfficiency)
        .whereType<double>()
        .toList();
    final bedtimes = rows
        .map((row) => (row['bedtime_minutes'] as num?)?.toDouble())
        .whereType<double>()
        .toList();
    final wakeTimes = rows
        .map((row) => (row['wake_time_minutes'] as num?)?.toDouble())
        .whereType<double>()
        .toList();

    return {
      'windowDays': days,
      'recordedNights': rows.length,
      'coveragePct': AiToolMath.round1(rows.length / days * 100),
      'averageSleepMinutes': AiToolMath.round1OrNull(
        AiToolMath.average(durations),
      ),
      'minimumSleepMinutes': AiToolMath.round1OrNull(
        AiToolMath.minimum(durations),
      ),
      'maximumSleepMinutes': AiToolMath.round1OrNull(
        AiToolMath.maximum(durations),
      ),
      'averageEfficiencyPct': AiToolMath.round1OrNull(
        AiToolMath.average(efficiencies),
      ),
      'scheduleRegularityScore': AiToolMath.round1OrNull(
        _scheduleRegularity(bedtimes, wakeTimes),
      ),
      'recentNights': rows.take(14).map(_compactSleepRow).toList(),
      'dataQuality': {
        'durationSamples': durations.length,
        'efficiencySamples': efficiencies.length,
        'scheduleSamples': math.min(bedtimes.length, wakeTimes.length),
        'durationSourceCounts': {
          'actual': rows
              .where((row) => _effectiveSleepSource(row) == 'actual')
              .length,
          'estimated': rows
              .where((row) => _effectiveSleepSource(row) == 'estimated')
              .length,
          'recorded': rows
              .where((row) => _effectiveSleepSource(row) == 'recorded')
              .length,
        },
      },
    };
  }

  Future<Map<String, dynamic>> nutritionSummary({int days = 14}) async {
    days = days.clamp(3, 90);
    final database = await db.database;
    final start = dateKey(
      _today().subtract(Duration(days: days - 1)),
    );
    final rows = await database.rawQuery(
      '''
      SELECT ml.date,
        SUM(mli.calories) calories,
        SUM(mli.protein_g) protein_g,
        SUM(mli.carbs_g) carbs_g,
        SUM(mli.fat_g) fat_g,
        SUM(mli.saturated_fat_g) saturated_fat_g,
        SUM(mli.monounsaturated_fat_g) monounsaturated_fat_g,
        SUM(mli.polyunsaturated_fat_g) polyunsaturated_fat_g,
        SUM(mli.trans_fat_g) trans_fat_g,
        SUM(mli.fiber_g) fiber_g,
        SUM(mli.sugars_g) sugars_g,
        SUM(mli.sodium_mg) sodium_mg,
        SUM(mli.potassium_mg) potassium_mg,
        SUM(mli.calcium_mg) calcium_mg,
        SUM(mli.iron_mg) iron_mg,
        SUM(mli.magnesium_mg) magnesium_mg,
        SUM(mli.zinc_mg) zinc_mg,
        SUM(mli.vitamin_a_ug) vitamin_a_ug,
        SUM(mli.vitamin_c_mg) vitamin_c_mg,
        SUM(mli.vitamin_d_ug) vitamin_d_ug,
        SUM(mli.vitamin_b12_ug) vitamin_b12_ug,
        COUNT(mli.id) item_count,
        SUM(CASE WHEN mli.calories IS NULL OR mli.protein_g IS NULL OR
          mli.carbs_g IS NULL OR mli.fat_g IS NULL THEN 1 ELSE 0 END)
          incomplete_items,
        SUM(CASE WHEN mli.fiber_g IS NULL OR mli.sugars_g IS NULL OR
          mli.sodium_mg IS NULL OR mli.potassium_mg IS NULL OR
          mli.calcium_mg IS NULL OR mli.iron_mg IS NULL OR
          mli.magnesium_mg IS NULL OR mli.zinc_mg IS NULL OR
          mli.vitamin_a_ug IS NULL OR mli.vitamin_c_mg IS NULL OR
          mli.vitamin_d_ug IS NULL OR mli.vitamin_b12_ug IS NULL
          THEN 1 ELSE 0 END) incomplete_detail_items
      FROM meal_logs ml
      JOIN meal_log_items mli ON mli.meal_log_id = ml.id
      WHERE ml.date >= ?
      GROUP BY ml.date
      ORDER BY ml.date DESC
      ''',
      [start],
    );
    // An active plan's current week overrides the settings goal.
    final effective = await EffectiveNutritionGoalService.resolve(date: _now());
    final goal = effective.goal;

    double? avg(String key) => AiToolMath.average(
      rows.map((row) => (row[key] as num?)?.toDouble()).whereType<double>(),
    );

    return {
      'windowDays': days,
      'loggedDays': rows.length,
      'coveragePct': AiToolMath.round1(rows.length / days * 100),
      'dailyAverage': {
        'calories': AiToolMath.round1OrNull(avg('calories')),
        'proteinG': AiToolMath.round1OrNull(avg('protein_g')),
        'carbsG': AiToolMath.round1OrNull(avg('carbs_g')),
        'fatG': AiToolMath.round1OrNull(avg('fat_g')),
        'saturatedFatG': AiToolMath.round1OrNull(avg('saturated_fat_g')),
        'monounsaturatedFatG': AiToolMath.round1OrNull(
          avg('monounsaturated_fat_g'),
        ),
        'polyunsaturatedFatG': AiToolMath.round1OrNull(
          avg('polyunsaturated_fat_g'),
        ),
        'transFatG': AiToolMath.round1OrNull(avg('trans_fat_g')),
        'fiberG': AiToolMath.round1OrNull(avg('fiber_g')),
        'sugarsG': AiToolMath.round1OrNull(avg('sugars_g')),
        'sodiumMg': AiToolMath.round1OrNull(avg('sodium_mg')),
        'potassiumMg': AiToolMath.round1OrNull(avg('potassium_mg')),
        'calciumMg': AiToolMath.round1OrNull(avg('calcium_mg')),
        'ironMg': AiToolMath.round1OrNull(avg('iron_mg')),
        'magnesiumMg': AiToolMath.round1OrNull(avg('magnesium_mg')),
        'zincMg': AiToolMath.round1OrNull(avg('zinc_mg')),
        'vitaminAUg': AiToolMath.round1OrNull(avg('vitamin_a_ug')),
        'vitaminCMg': AiToolMath.round1OrNull(avg('vitamin_c_mg')),
        'vitaminDUg': AiToolMath.round1OrNull(avg('vitamin_d_ug')),
        'vitaminB12Ug': AiToolMath.round1OrNull(avg('vitamin_b12_ug')),
      },
      'activeDailyGoal': goal == null
          ? null
          : {
              'calories': goal.calories,
              'proteinG': goal.proteinG,
              'carbsG': goal.carbsG,
              'fatG': goal.fatG,
              if (effective.fromPlan)
                'source': 'plan'
              else
                'source': 'settings',
            },
      'daysWithIncompleteMacros': rows
          .where((row) => ((row['incomplete_items'] as num?) ?? 0) > 0)
          .length,
      'daysWithIncompleteDetailedNutrients': rows
          .where((row) => ((row['incomplete_detail_items'] as num?) ?? 0) > 0)
          .length,
      'recentDays': rows.take(14).map(_compactNutritionRow).toList(),
    };
  }

  Future<Map<String, dynamic>> sleepPerformance({int days = 42}) async {
    days = days.clamp(7, 90);
    final sleep = await _sleepRows(days);
    final workouts = await _dailyWorkoutRows(days);
    final sleepByDate = {for (final row in sleep) row['date'] as String: row};
    final pairs = <Map<String, dynamic>>[];
    for (final workout in workouts) {
      final night = sleepByDate[workout['date']];
      if (night == null) continue;
      pairs.add({
        'date': workout['date'],
        'sleepMinutes': _effectiveSleep(night),
        'sleepEfficiencyPct': _sleepEfficiency(night),
        'workoutVolumeKg': (workout['volume_kg'] as num?)?.toDouble(),
        'feeling': (workout['feeling'] as num?)?.toDouble(),
        'completedSets': (workout['completed_sets'] as num?)?.toInt(),
        'recordedRuns': (workout['run_count'] as num?)?.toInt() ?? 0,
        'stationaryBikeSessions': (workout['bike_count'] as num?)?.toInt() ?? 0,
        'cardioDistanceMeters':
            (workout['cardio_distance_meters'] as num?)?.toDouble() ?? 0,
        'cardioMovingTimeSeconds':
            (workout['cardio_moving_seconds'] as num?)?.toInt() ?? 0,
        'averageCardioRpe': (workout['cardio_rpe'] as num?)?.toDouble(),
      });
    }
    return {
      'windowDays': days,
      'pairingRule':
          'sleep and completed strength/cardio activities recorded on the same calendar date',
      'pairedDays': pairs.length,
      'correlations': {
        'sleepMinutesVsWorkoutVolume': _correlationFrom(
          pairs,
          'sleepMinutes',
          'workoutVolumeKg',
        ),
        'sleepMinutesVsFeeling': _correlationFrom(
          pairs,
          'sleepMinutes',
          'feeling',
        ),
        'sleepEfficiencyVsFeeling': _correlationFrom(
          pairs,
          'sleepEfficiencyPct',
          'feeling',
        ),
      },
      'recentPairs': pairs.reversed.take(14).toList(),
      'interpretationWarning':
          'observational association only; correlation does not establish causation',
    };
  }

  Future<Map<String, dynamic>> nutritionBodyTrend({int days = 84}) async {
    days = days.clamp(14, 180);
    final database = await db.database;
    final start = dateKey(
      _today().subtract(Duration(days: days - 1)),
    );
    final nutrition = await database.rawQuery(
      '''
      SELECT ml.date, SUM(mli.calories) calories,
        SUM(mli.protein_g) protein_g, SUM(mli.carbs_g) carbs_g,
        SUM(mli.fat_g) fat_g
      FROM meal_logs ml
      JOIN meal_log_items mli ON mli.meal_log_id = ml.id
      WHERE ml.date >= ?
      GROUP BY ml.date ORDER BY ml.date ASC
      ''',
      [start],
    );
    final weights = await database.query(
      'body_measurements',
      columns: ['date', 'value', 'unit'],
      where: 'type = ? AND date >= ?',
      whereArgs: ['weight', start],
      orderBy: 'date ASC, created_at ASC',
    );
    final weekly = <String, _WeeklyWellnessBucket>{};
    for (final row in nutrition) {
      final key = _weekStart(row['date'] as String);
      weekly.putIfAbsent(key, _WeeklyWellnessBucket.new).addNutrition(row);
    }
    for (final row in weights) {
      final key = _weekStart(row['date'] as String);
      weekly.putIfAbsent(key, _WeeklyWellnessBucket.new).addWeight(row);
    }
    final points =
        weekly.entries
            .map((entry) => entry.value.toMap(entry.key))
            .where(
              (point) =>
                  point['loggedNutritionDays'] != 0 ||
                  point['weightKg'] != null,
            )
            .toList()
          ..sort(
            (a, b) =>
                (a['weekStart'] as String).compareTo(b['weekStart'] as String),
          );
    final weightValues = weights.map(_weightKg).whereType<double>().toList();
    return {
      'windowDays': days,
      'loggedNutritionDays': nutrition.length,
      'weightMeasurements': weights.length,
      'weightChangeKg': weightValues.length < 2
          ? null
          : AiToolMath.round1(weightValues.last - weightValues.first),
      'weeklyTrend': points.take(26).toList(),
      'caloriesVsWeightCorrelation': _correlationFrom(
        points,
        'averageCalories',
        'weightKg',
      ),
      'interpretationWarning':
          'weight is influenced by hydration and measurement conditions; sparse food logs can bias the trend',
    };
  }

  Future<Map<String, dynamic>> weeklyRecoveryTrend({int weeks = 8}) async {
    weeks = weeks.clamp(2, 12);
    final days = weeks * 7;
    final sleep = await _sleepRows(days);
    final workouts = await _dailyWorkoutRows(days);
    final buckets = <String, _RecoveryBucket>{};
    for (final row in sleep) {
      final key = _weekStart(row['date'] as String);
      buckets.putIfAbsent(key, _RecoveryBucket.new).addSleep(row);
    }
    for (final row in workouts) {
      final key = _weekStart(row['date'] as String);
      buckets.putIfAbsent(key, _RecoveryBucket.new).addWorkout(row);
    }
    final trend =
        buckets.entries.map((entry) => entry.value.toMap(entry.key)).toList()
          ..sort(
            (a, b) =>
                (a['weekStart'] as String).compareTo(b['weekStart'] as String),
          );
    final scores = trend
        .map((row) => (row['recoveryScore'] as num?)?.toDouble())
        .whereType<double>()
        .toList();
    return {
      'weeks': weeks,
      'weeklyTrend': trend,
      'direction': scores.length < 2
          ? 'insufficient_data'
          : scores.last - scores.first >= 5
          ? 'improving'
          : scores.last - scores.first <= -5
          ? 'declining'
          : 'stable',
      'method':
          'non-clinical 0-100 score from available sleep duration, efficiency, schedule regularity and workout feeling; missing components are reweighted',
    };
  }

  Future<List<Map<String, dynamic>>> _sleepRows(int days) async {
    final database = await db.database;
    final start = dateKey(
      _today().subtract(Duration(days: days - 1)),
    );
    return database.query(
      'sleep_entries',
      where: 'date >= ?',
      whereArgs: [start],
      orderBy: 'date DESC',
      limit: days,
    );
  }

  Future<List<Map<String, dynamic>>> _dailyWorkoutRows(int days) async {
    final database = await db.database;
    final start = dateKey(
      _today().subtract(Duration(days: days - 1)),
    );
    return database.rawQuery(
      '''
      SELECT date, SUM(workout_count) workout_count,
        SUM(run_count) run_count, SUM(bike_count) bike_count,
        SUM(duration_seconds) duration_seconds,
        AVG(feeling_rating) feeling, AVG(cardio_rpe) cardio_rpe,
        SUM(volume_kg) volume_kg, SUM(completed_sets) completed_sets,
        SUM(cardio_distance_meters) cardio_distance_meters,
        SUM(cardio_moving_seconds) cardio_moving_seconds
      FROM (
        SELECT w.id, w.date, 1 AS workout_count, 0 AS run_count,
          0 AS bike_count, w.duration_seconds, w.feeling_rating,
          NULL AS cardio_rpe, 0.0 AS cardio_distance_meters,
          0 AS cardio_moving_seconds,
          SUM(CASE WHEN s.is_complete = 1 AND COALESCE(s.is_warmup, 0) = 0
            THEN COALESCE(s.weight, 0) * COALESCE(s.reps, 0) ELSE 0 END) volume_kg,
          SUM(CASE WHEN s.is_complete = 1 AND COALESCE(s.is_warmup, 0) = 0
            THEN 1 ELSE 0 END) completed_sets
        FROM workouts w
        LEFT JOIN exercise_entries ee ON ee.workout_id = w.id
        LEFT JOIN sets s ON s.exercise_entry_id = ee.id
        WHERE w.date >= ?
        GROUP BY w.id
        UNION ALL
        SELECT ra.id, substr(ra.started_at, 1, 10) AS date,
          0 AS workout_count,
          CASE WHEN ra.activity_type = 'running' THEN 1 ELSE 0 END AS run_count,
          CASE WHEN ra.activity_type = 'stationary_bike' THEN 1 ELSE 0 END
            AS bike_count,
          ra.duration_seconds, ra.feeling_rating, ra.rpe AS cardio_rpe,
          ra.distance_meters AS cardio_distance_meters,
          CASE WHEN ra.moving_time_seconds > 0 THEN ra.moving_time_seconds
            ELSE ra.duration_seconds END AS cardio_moving_seconds,
          0.0 AS volume_kg, 0 AS completed_sets
        FROM run_activities ra
        WHERE ra.status = 'completed' AND ra.started_at >= ?
      ) daily
      GROUP BY date ORDER BY date ASC
      ''',
      [start, start],
    );
  }

  DateTime _today() {
    final value = _now();
    return dayOf(value);
  }

  static Map<String, dynamic> _compactSleepRow(Map<String, dynamic> row) => {
    'date': row['date'],
    'sleepMinutes': _effectiveSleep(row),
    'recordedSleepMinutes': row['sleep_minutes'],
    'actualSleepMinutes': row['actual_sleep_minutes'],
    'estimatedSleepMinutes': row['estimated_sleep_minutes'],
    'effectiveSleepSource': _effectiveSleepSource(row),
    'timeInBedMinutes': row['time_in_bed_minutes'],
    'bedtimeMinutes': row['bedtime_minutes'],
    'wakeTimeMinutes': row['wake_time_minutes'],
    'efficiencyPct': AiToolMath.round1OrNull(_sleepEfficiency(row)),
    'source': row['source'],
  };

  static Map<String, dynamic> _compactNutritionRow(
    Map<String, dynamic> row,
  ) => {
    'date': row['date'],
    'calories': AiToolMath.round1OrNull((row['calories'] as num?)?.toDouble()),
    'proteinG': AiToolMath.round1OrNull((row['protein_g'] as num?)?.toDouble()),
    'carbsG': AiToolMath.round1OrNull((row['carbs_g'] as num?)?.toDouble()),
    'fatG': AiToolMath.round1OrNull((row['fat_g'] as num?)?.toDouble()),
    'saturatedFatG': AiToolMath.round1OrNull(
      (row['saturated_fat_g'] as num?)?.toDouble(),
    ),
    'monounsaturatedFatG': AiToolMath.round1OrNull(
      (row['monounsaturated_fat_g'] as num?)?.toDouble(),
    ),
    'polyunsaturatedFatG': AiToolMath.round1OrNull(
      (row['polyunsaturated_fat_g'] as num?)?.toDouble(),
    ),
    'transFatG': AiToolMath.round1OrNull(
      (row['trans_fat_g'] as num?)?.toDouble(),
    ),
    'fiberG': AiToolMath.round1OrNull((row['fiber_g'] as num?)?.toDouble()),
    'sugarsG': AiToolMath.round1OrNull((row['sugars_g'] as num?)?.toDouble()),
    'sodiumMg': AiToolMath.round1OrNull((row['sodium_mg'] as num?)?.toDouble()),
    'potassiumMg': AiToolMath.round1OrNull(
      (row['potassium_mg'] as num?)?.toDouble(),
    ),
    'calciumMg': AiToolMath.round1OrNull(
      (row['calcium_mg'] as num?)?.toDouble(),
    ),
    'ironMg': AiToolMath.round1OrNull((row['iron_mg'] as num?)?.toDouble()),
    'magnesiumMg': AiToolMath.round1OrNull(
      (row['magnesium_mg'] as num?)?.toDouble(),
    ),
    'zincMg': AiToolMath.round1OrNull((row['zinc_mg'] as num?)?.toDouble()),
    'vitaminAUg': AiToolMath.round1OrNull(
      (row['vitamin_a_ug'] as num?)?.toDouble(),
    ),
    'vitaminCMg': AiToolMath.round1OrNull(
      (row['vitamin_c_mg'] as num?)?.toDouble(),
    ),
    'vitaminDUg': AiToolMath.round1OrNull(
      (row['vitamin_d_ug'] as num?)?.toDouble(),
    ),
    'vitaminB12Ug': AiToolMath.round1OrNull(
      (row['vitamin_b12_ug'] as num?)?.toDouble(),
    ),
  };

  static double? _effectiveSleep(Map<String, dynamic> row) =>
      ((row['actual_sleep_minutes'] ??
                  row['estimated_sleep_minutes'] ??
                  row['sleep_minutes'])
              as num?)
          ?.toDouble();

  static String _effectiveSleepSource(Map<String, dynamic> row) {
    if (row['actual_sleep_minutes'] != null) return 'actual';
    if (row['estimated_sleep_minutes'] != null) return 'estimated';
    return 'recorded';
  }

  static double? _sleepEfficiency(Map<String, dynamic> row) {
    final asleep = _effectiveSleep(row);
    final inBed = ((row['time_in_bed_minutes'] ?? row['sleep_minutes']) as num?)
        ?.toDouble();
    if (asleep == null || inBed == null || inBed <= 0) return null;
    return (asleep / inBed * 100).clamp(0, 100);
  }

  static double? _weightKg(Map<String, dynamic> row) {
    final value = (row['value'] as num?)?.toDouble();
    if (value == null) return null;
    switch ((row['unit'] as String? ?? 'kg').toLowerCase()) {
      case 'kg':
        return value;
      case 'g':
        return value / 1000;
      case 'lb':
      case 'lbs':
        return value / 2.2046226218;
      default:
        return null;
    }
  }

  static double? _scheduleRegularity(
    List<double> bedtimes,
    List<double> wakeTimes,
  ) {
    if (bedtimes.length < 2 || wakeTimes.length < 2) return null;
    double score(List<double> values) {
      final center = AiToolMath.circularMeanMinutes(values);
      final deviation = AiToolMath.average(
        values.map((value) {
          return AiToolMath.circularDistanceMinutes(value, center);
        }),
      )!;
      return (100 * (1 - math.min(deviation, 180) / 180)).clamp(0, 100);
    }

    return (score(bedtimes) + score(wakeTimes)) / 2;
  }

  static Map<String, dynamic> _correlationFrom(
    Iterable<Map<String, dynamic>> rows,
    String xKey,
    String yKey,
  ) {
    final pairs = <(double, double)>[];
    for (final row in rows) {
      final x = (row[xKey] as num?)?.toDouble();
      final y = (row[yKey] as num?)?.toDouble();
      if (x != null && y != null) pairs.add((x, y));
    }
    if (pairs.length < 4) {
      return {
        'coefficient': null,
        'sampleSize': pairs.length,
        'quality': 'insufficient',
      };
    }
    final meanX = AiToolMath.average(pairs.map((pair) => pair.$1))!;
    final meanY = AiToolMath.average(pairs.map((pair) => pair.$2))!;
    var numerator = 0.0;
    var sumX = 0.0;
    var sumY = 0.0;
    for (final pair in pairs) {
      final dx = pair.$1 - meanX;
      final dy = pair.$2 - meanY;
      numerator += dx * dy;
      sumX += dx * dx;
      sumY += dy * dy;
    }
    final denominator = math.sqrt(sumX * sumY);
    final coefficient = denominator == 0 ? null : numerator / denominator;
    return {
      'coefficient': AiToolMath.round1OrNull(coefficient),
      'sampleSize': pairs.length,
      'quality': pairs.length >= 14 ? 'usable' : 'low_sample',
    };
  }

  static String _weekStart(String date) {
    return dateKey(mondayOf(DateTime.parse(date)));
  }
}

class _WeeklyWellnessBucket {
  final List<double> calories = [];
  final List<double> protein = [];
  final List<double> carbs = [];
  final List<double> fat = [];
  final List<double> weights = [];

  void addNutrition(Map<String, dynamic> row) {
    void add(String key, List<double> target) {
      final value = (row[key] as num?)?.toDouble();
      if (value != null) target.add(value);
    }

    add('calories', calories);
    add('protein_g', protein);
    add('carbs_g', carbs);
    add('fat_g', fat);
  }

  void addWeight(Map<String, dynamic> row) {
    final value = AiWellnessAnalyticsService._weightKg(row);
    if (value != null) weights.add(value);
  }

  Map<String, dynamic> toMap(String weekStart) => {
    'weekStart': weekStart,
    'loggedNutritionDays': calories.length,
    'averageCalories': AiToolMath.round1OrNull(AiToolMath.average(calories)),
    'averageProteinG': AiToolMath.round1OrNull(AiToolMath.average(protein)),
    'averageCarbsG': AiToolMath.round1OrNull(AiToolMath.average(carbs)),
    'averageFatG': AiToolMath.round1OrNull(AiToolMath.average(fat)),
    'weightKg': weights.isEmpty ? null : AiToolMath.round1(weights.last),
  };
}

class _RecoveryBucket {
  final List<double> sleepMinutes = [];
  final List<double> efficiencies = [];
  final List<double> bedtimes = [];
  final List<double> wakeTimes = [];
  final List<double> feelings = [];
  final List<double> cardioRpes = [];
  double volumeKg = 0;
  int workoutCount = 0;
  int runCount = 0;
  int bikeCount = 0;
  double cardioDistanceMeters = 0;
  int cardioMovingSeconds = 0;

  void addSleep(Map<String, dynamic> row) {
    final sleep = AiWellnessAnalyticsService._effectiveSleep(row);
    if (sleep != null) sleepMinutes.add(sleep);
    final efficiency = AiWellnessAnalyticsService._sleepEfficiency(row);
    if (efficiency != null) efficiencies.add(efficiency);
    final bedtime = (row['bedtime_minutes'] as num?)?.toDouble();
    final wake = (row['wake_time_minutes'] as num?)?.toDouble();
    if (bedtime != null) bedtimes.add(bedtime);
    if (wake != null) wakeTimes.add(wake);
  }

  void addWorkout(Map<String, dynamic> row) {
    workoutCount += (row['workout_count'] as num?)?.toInt() ?? 0;
    runCount += (row['run_count'] as num?)?.toInt() ?? 0;
    bikeCount += (row['bike_count'] as num?)?.toInt() ?? 0;
    volumeKg += (row['volume_kg'] as num?)?.toDouble() ?? 0;
    cardioDistanceMeters +=
        (row['cardio_distance_meters'] as num?)?.toDouble() ?? 0;
    cardioMovingSeconds += (row['cardio_moving_seconds'] as num?)?.toInt() ?? 0;
    final feeling = (row['feeling'] as num?)?.toDouble();
    if (feeling != null) feelings.add(feeling);
    final cardioRpe = (row['cardio_rpe'] as num?)?.toDouble();
    if (cardioRpe != null) cardioRpes.add(cardioRpe);
  }

  Map<String, dynamic> toMap(String weekStart) {
    final avgSleep = AiToolMath.average(sleepMinutes);
    final avgEfficiency = AiToolMath.average(efficiencies);
    final regularity = AiWellnessAnalyticsService._scheduleRegularity(
      bedtimes,
      wakeTimes,
    );
    final avgFeeling = AiToolMath.average(feelings);
    final components = <(double, double)>[];
    if (avgSleep != null) {
      components.add(((avgSleep / 480 * 100).clamp(0, 100), 0.5));
    }
    if (avgEfficiency != null) {
      components.add((avgEfficiency.clamp(0, 100), 0.2));
    }
    if (regularity != null) {
      components.add((regularity, 0.2));
    }
    if (avgFeeling != null) {
      components.add(((avgFeeling / 5 * 100).clamp(0, 100), 0.1));
    }
    final weight = components.fold<double>(0, (sum, value) => sum + value.$2);
    final score = weight == 0
        ? null
        : components.fold<double>(
                0,
                (sum, value) => sum + value.$1 * value.$2,
              ) /
              weight;
    return {
      'weekStart': weekStart,
      'recoveryScore': AiToolMath.round1OrNull(score),
      'sleepNights': sleepMinutes.length,
      'averageSleepMinutes': AiToolMath.round1OrNull(avgSleep),
      'averageEfficiencyPct': AiToolMath.round1OrNull(avgEfficiency),
      'regularityScore': AiToolMath.round1OrNull(regularity),
      'averageWorkoutFeeling': AiToolMath.round1OrNull(avgFeeling),
      'workoutCount': workoutCount,
      'trainingVolumeKg': AiToolMath.round1(volumeKg),
      'recordedRuns': runCount,
      'stationaryBikeSessions': bikeCount,
      'cardioDistanceMeters': AiToolMath.round1(cardioDistanceMeters),
      'cardioMovingTimeSeconds': cardioMovingSeconds,
      'averageCardioRpe': AiToolMath.round1OrNull(
        AiToolMath.average(cardioRpes),
      ),
    };
  }
}
