import 'dart:math' as math;

import '../database/database_helper.dart';

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
      'coveragePct': _round(rows.length / days * 100),
      'averageSleepMinutes': _roundOrNull(_average(durations)),
      'minimumSleepMinutes': _roundOrNull(_minimum(durations)),
      'maximumSleepMinutes': _roundOrNull(_maximum(durations)),
      'averageEfficiencyPct': _roundOrNull(_average(efficiencies)),
      'scheduleRegularityScore': _roundOrNull(
        _scheduleRegularity(bedtimes, wakeTimes),
      ),
      'recentNights': rows.take(14).map(_compactSleepRow).toList(),
      'dataQuality': {
        'durationSamples': durations.length,
        'efficiencySamples': efficiencies.length,
        'scheduleSamples': math.min(bedtimes.length, wakeTimes.length),
      },
    };
  }

  Future<Map<String, dynamic>> nutritionSummary({int days = 14}) async {
    days = days.clamp(3, 90);
    final database = await db.database;
    final start = _date(_today().subtract(Duration(days: days - 1)));
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
          incomplete_items
      FROM meal_logs ml
      JOIN meal_log_items mli ON mli.meal_log_id = ml.id
      WHERE ml.date >= ?
      GROUP BY ml.date
      ORDER BY ml.date DESC
      ''',
      [start],
    );
    final goalRows = await database.query(
      'nutrition_goals',
      where: 'is_active = 1',
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    final goal = goalRows.isEmpty ? null : goalRows.first;

    double? avg(String key) => _average(
      rows.map((row) => (row[key] as num?)?.toDouble()).whereType<double>(),
    );

    return {
      'windowDays': days,
      'loggedDays': rows.length,
      'coveragePct': _round(rows.length / days * 100),
      'dailyAverage': {
        'calories': _roundOrNull(avg('calories')),
        'proteinG': _roundOrNull(avg('protein_g')),
        'carbsG': _roundOrNull(avg('carbs_g')),
        'fatG': _roundOrNull(avg('fat_g')),
        'saturatedFatG': _roundOrNull(avg('saturated_fat_g')),
        'monounsaturatedFatG': _roundOrNull(avg('monounsaturated_fat_g')),
        'polyunsaturatedFatG': _roundOrNull(avg('polyunsaturated_fat_g')),
        'transFatG': _roundOrNull(avg('trans_fat_g')),
        'fiberG': _roundOrNull(avg('fiber_g')),
        'sodiumMg': _roundOrNull(avg('sodium_mg')),
        'potassiumMg': _roundOrNull(avg('potassium_mg')),
        'calciumMg': _roundOrNull(avg('calcium_mg')),
        'ironMg': _roundOrNull(avg('iron_mg')),
        'magnesiumMg': _roundOrNull(avg('magnesium_mg')),
        'zincMg': _roundOrNull(avg('zinc_mg')),
        'vitaminAUg': _roundOrNull(avg('vitamin_a_ug')),
        'vitaminCMg': _roundOrNull(avg('vitamin_c_mg')),
        'vitaminDUg': _roundOrNull(avg('vitamin_d_ug')),
        'vitaminB12Ug': _roundOrNull(avg('vitamin_b12_ug')),
      },
      'activeDailyGoal': goal == null
          ? null
          : {
              'calories': goal['calories'],
              'proteinG': goal['protein_g'],
              'carbsG': goal['carbs_g'],
              'fatG': goal['fat_g'],
            },
      'daysWithIncompleteMacros': rows
          .where((row) => ((row['incomplete_items'] as num?) ?? 0) > 0)
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
      });
    }
    return {
      'windowDays': days,
      'pairingRule': 'sleep and workouts recorded on the same calendar date',
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
    final start = _date(_today().subtract(Duration(days: days - 1)));
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
          : _round(weightValues.last - weightValues.first),
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
    final start = _date(_today().subtract(Duration(days: days - 1)));
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
    final start = _date(_today().subtract(Duration(days: days - 1)));
    return database.rawQuery(
      '''
      SELECT date, COUNT(*) workout_count, SUM(duration_seconds) duration_seconds,
        AVG(feeling_rating) feeling, SUM(volume_kg) volume_kg,
        SUM(completed_sets) completed_sets
      FROM (
        SELECT w.id, w.date, w.duration_seconds, w.feeling_rating,
          SUM(CASE WHEN s.is_complete = 1 AND COALESCE(s.is_warmup, 0) = 0
            THEN COALESCE(s.weight, 0) * COALESCE(s.reps, 0) ELSE 0 END) volume_kg,
          SUM(CASE WHEN s.is_complete = 1 AND COALESCE(s.is_warmup, 0) = 0
            THEN 1 ELSE 0 END) completed_sets
        FROM workouts w
        LEFT JOIN exercise_entries ee ON ee.workout_id = w.id
        LEFT JOIN sets s ON s.exercise_entry_id = ee.id
        WHERE w.date >= ?
        GROUP BY w.id
      ) daily
      GROUP BY date ORDER BY date ASC
      ''',
      [start],
    );
  }

  DateTime _today() {
    final value = _now();
    return DateTime(value.year, value.month, value.day);
  }

  static Map<String, dynamic> _compactSleepRow(Map<String, dynamic> row) => {
    'date': row['date'],
    'sleepMinutes': _effectiveSleep(row),
    'bedtimeMinutes': row['bedtime_minutes'],
    'wakeTimeMinutes': row['wake_time_minutes'],
    'efficiencyPct': _roundOrNull(_sleepEfficiency(row)),
    'source': row['source'],
  };

  static Map<String, dynamic> _compactNutritionRow(
    Map<String, dynamic> row,
  ) => {
    'date': row['date'],
    'calories': _roundOrNull((row['calories'] as num?)?.toDouble()),
    'proteinG': _roundOrNull((row['protein_g'] as num?)?.toDouble()),
    'carbsG': _roundOrNull((row['carbs_g'] as num?)?.toDouble()),
    'fatG': _roundOrNull((row['fat_g'] as num?)?.toDouble()),
    'saturatedFatG': _roundOrNull((row['saturated_fat_g'] as num?)?.toDouble()),
    'monounsaturatedFatG': _roundOrNull(
      (row['monounsaturated_fat_g'] as num?)?.toDouble(),
    ),
    'polyunsaturatedFatG': _roundOrNull(
      (row['polyunsaturated_fat_g'] as num?)?.toDouble(),
    ),
    'transFatG': _roundOrNull((row['trans_fat_g'] as num?)?.toDouble()),
    'potassiumMg': _roundOrNull((row['potassium_mg'] as num?)?.toDouble()),
    'calciumMg': _roundOrNull((row['calcium_mg'] as num?)?.toDouble()),
    'ironMg': _roundOrNull((row['iron_mg'] as num?)?.toDouble()),
    'magnesiumMg': _roundOrNull((row['magnesium_mg'] as num?)?.toDouble()),
    'zincMg': _roundOrNull((row['zinc_mg'] as num?)?.toDouble()),
    'vitaminAUg': _roundOrNull((row['vitamin_a_ug'] as num?)?.toDouble()),
    'vitaminCMg': _roundOrNull((row['vitamin_c_mg'] as num?)?.toDouble()),
    'vitaminDUg': _roundOrNull((row['vitamin_d_ug'] as num?)?.toDouble()),
    'vitaminB12Ug': _roundOrNull((row['vitamin_b12_ug'] as num?)?.toDouble()),
  };

  static double? _effectiveSleep(Map<String, dynamic> row) =>
      ((row['actual_sleep_minutes'] ??
                  row['estimated_sleep_minutes'] ??
                  row['sleep_minutes'])
              as num?)
          ?.toDouble();

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
      final center = _circularCenter(values);
      final deviation = _average(
        values.map((value) {
          final direct = (value - center).abs();
          return math.min(direct, 1440 - direct);
        }),
      )!;
      return (100 * (1 - math.min(deviation, 180) / 180)).clamp(0, 100);
    }

    return (score(bedtimes) + score(wakeTimes)) / 2;
  }

  static double _circularCenter(List<double> values) {
    var sinSum = 0.0;
    var cosSum = 0.0;
    for (final value in values) {
      final angle = value / 1440 * 2 * math.pi;
      sinSum += math.sin(angle);
      cosSum += math.cos(angle);
    }
    var angle = math.atan2(sinSum, cosSum);
    if (angle < 0) angle += 2 * math.pi;
    return angle / (2 * math.pi) * 1440;
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
    final meanX = _average(pairs.map((pair) => pair.$1))!;
    final meanY = _average(pairs.map((pair) => pair.$2))!;
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
      'coefficient': _roundOrNull(coefficient),
      'sampleSize': pairs.length,
      'quality': pairs.length >= 14 ? 'usable' : 'low_sample',
    };
  }

  static double? _average(Iterable<double> values) {
    final list = values.toList();
    if (list.isEmpty) return null;
    return list.reduce((a, b) => a + b) / list.length;
  }

  static double? _minimum(List<double> values) =>
      values.isEmpty ? null : values.reduce(math.min);
  static double? _maximum(List<double> values) =>
      values.isEmpty ? null : values.reduce(math.max);
  static double _round(double value) => (value * 10).round() / 10;
  static double? _roundOrNull(double? value) =>
      value == null ? null : _round(value);
  static String _date(DateTime value) =>
      value.toIso8601String().substring(0, 10);

  static String _weekStart(String date) {
    final parsed = DateTime.parse(date);
    return _date(parsed.subtract(Duration(days: parsed.weekday - 1)));
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
    'averageCalories': AiWellnessAnalyticsService._roundOrNull(
      AiWellnessAnalyticsService._average(calories),
    ),
    'averageProteinG': AiWellnessAnalyticsService._roundOrNull(
      AiWellnessAnalyticsService._average(protein),
    ),
    'averageCarbsG': AiWellnessAnalyticsService._roundOrNull(
      AiWellnessAnalyticsService._average(carbs),
    ),
    'averageFatG': AiWellnessAnalyticsService._roundOrNull(
      AiWellnessAnalyticsService._average(fat),
    ),
    'weightKg': weights.isEmpty
        ? null
        : AiWellnessAnalyticsService._round(weights.last),
  };
}

class _RecoveryBucket {
  final List<double> sleepMinutes = [];
  final List<double> efficiencies = [];
  final List<double> bedtimes = [];
  final List<double> wakeTimes = [];
  final List<double> feelings = [];
  double volumeKg = 0;
  int workoutCount = 0;

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
    volumeKg += (row['volume_kg'] as num?)?.toDouble() ?? 0;
    final feeling = (row['feeling'] as num?)?.toDouble();
    if (feeling != null) feelings.add(feeling);
  }

  Map<String, dynamic> toMap(String weekStart) {
    final avgSleep = AiWellnessAnalyticsService._average(sleepMinutes);
    final avgEfficiency = AiWellnessAnalyticsService._average(efficiencies);
    final regularity = AiWellnessAnalyticsService._scheduleRegularity(
      bedtimes,
      wakeTimes,
    );
    final avgFeeling = AiWellnessAnalyticsService._average(feelings);
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
      'recoveryScore': AiWellnessAnalyticsService._roundOrNull(score),
      'sleepNights': sleepMinutes.length,
      'averageSleepMinutes': AiWellnessAnalyticsService._roundOrNull(avgSleep),
      'averageEfficiencyPct': AiWellnessAnalyticsService._roundOrNull(
        avgEfficiency,
      ),
      'regularityScore': AiWellnessAnalyticsService._roundOrNull(regularity),
      'averageWorkoutFeeling': AiWellnessAnalyticsService._roundOrNull(
        avgFeeling,
      ),
      'workoutCount': workoutCount,
      'trainingVolumeKg': AiWellnessAnalyticsService._round(volumeKg),
    };
  }
}
