// Read-only queries built for the AI Coach may run SQL directly (a documented
// exception to the repository-only rule); writes never happen in this file.
import 'dart:math' as math;

import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/services/ai_sleep_tool_service.dart';
import 'package:workout_notes/services/ai_tool_math.dart';
import 'package:workout_notes/utils/date_utils.dart';

/// Read-only, compact cross-domain analytics for the AI Coach (sleep x
/// training, nutrition x body weight, weekly recovery).
///
/// Everything is aggregated in SQLite and returned as bounded series, newest
/// first. Only FINISHED workouts up to today, completed non-warm-up sets and
/// completed cardio count; weekly series use FULL Monday-Sunday weeks only.
/// Sleep nights are resolved by [AiSleepNight], the same resolver as the sleep
/// tools. Correlations are descriptive and need enough paired observations.
class AiWellnessAnalyticsService {
  final DatabaseHelper db;
  final DateTime Function() _now;

  AiWellnessAnalyticsService({DatabaseHelper? db, DateTime Function()? now})
    : db = db ?? DatabaseHelper.instance,
      _now = now ?? DateTime.now;

  static const int _maxPairRows = 14;

  /// Sleep versus training: each recorded night (dated by the wake-up day) is
  /// paired with the strength/cardio finished on that same date.
  Future<Map<String, dynamic>> sleepPerformance({int days = 42}) async {
    days = days.clamp(7, 90);
    final window = AiToolMath.window(
      today: _now(),
      days: days,
      defaultDays: 42,
      maxDays: 90,
    );
    final nights = await AiSleepNight.load(
      db,
      startKey: window.startKey,
      endKey: window.endKey,
    );
    final training = await _trainingByDate(window.start, window.end);
    final pairs = <Map<String, dynamic>>[];
    for (final night in nights) {
      final day = training[night.date];
      if (day == null) continue;
      pairs.add({
        'date': night.date,
        'sleep_min': night.minutes,
        'efficiency_pct': night.efficiencyPct,
        'volume_kg': day.volumeKg,
        'feeling': day.feeling,
        'sets': day.sets,
        'runs': day.runs,
        'bike_rides': day.bikes,
        'cardio_km': day.cardioKm,
        'cardio_rpe': day.cardioRpe,
      });
    }
    return {
      'applied': window.toApplied(),
      'sleep_nights': nights.length,
      'paired_days': pairs.length,
      'correlations': {
        'sleep_vs_volume': _correlation(pairs, 'sleep_min', 'volume_kg'),
        'sleep_vs_feeling': _correlation(pairs, 'sleep_min', 'feeling'),
        'efficiency_vs_feeling': _correlation(
          pairs,
          'efficiency_pct',
          'feeling',
        ),
      },
      'pairs': pairs.take(_maxPairRows).toList(),
    };
  }

  /// Weekly intake (mean of logged days) next to weekly mean body weight, over
  /// the last full Monday-Sunday weeks.
  Future<Map<String, dynamic>> nutritionBodyTrend({int days = 84}) async {
    days = days.clamp(14, 180);
    final weeks = (days ~/ 7).clamp(2, 25);
    final range = _fullWeeks(weeks);
    final startKey = dateKey(range.start);
    final endKey = dateKey(range.end);
    final database = await db.database;

    final nutrition = await database.rawQuery(
      '''
      SELECT ml.date, SUM(mli.calories) calories, SUM(mli.protein_g) protein_g,
        SUM(mli.carbs_g) carbs_g, SUM(mli.fat_g) fat_g
      FROM meal_logs ml
      JOIN meal_log_items mli ON mli.meal_log_id = ml.id
      WHERE ml.date >= ? AND ml.date <= ?
      GROUP BY ml.date
      ''',
      [startKey, endKey],
    );
    final weights = await database.query(
      'body_measurements',
      columns: ['date', 'value', 'unit'],
      where: 'type = ? AND date >= ? AND date <= ?',
      whereArgs: ['weight', startKey, endKey],
      orderBy: 'date ASC, created_at ASC',
    );

    final buckets = <String, _NutritionWeek>{};
    for (final row in nutrition) {
      buckets
          .putIfAbsent(_weekKey(row['date']! as String), _NutritionWeek.new)
          .addNutrition(row);
    }
    var weightCount = 0;
    for (final row in weights) {
      final kg = _weightKg(row);
      if (kg == null) continue;
      weightCount++;
      buckets
          .putIfAbsent(_weekKey(row['date']! as String), _NutritionWeek.new)
          .weights
          .add(kg);
    }

    final rows = <Map<String, dynamic>>[];
    final weeklyWeights = <double>[]; // newest first
    final correlationPairs = <Map<String, dynamic>>[];
    for (var i = 0; i < weeks; i++) {
      final key = dateKey(addDays(range.end, -(7 * i) - 6));
      final bucket = buckets[key];
      if (bucket == null) continue;
      final row = bucket.toRow(key);
      rows.add(row);
      final weight = row['weight_kg'] as double?;
      if (weight != null) weeklyWeights.add(weight);
      correlationPairs.add(row);
    }

    return {
      'applied': {
        ...AiDateWindow(range.start, range.end).toApplied(),
        'weeks': weeks,
      },
      'logged_days': nutrition.length,
      'weight_measurements': weightCount,
      'weight_change_kg': weeklyWeights.length < 2
          ? null
          : weeklyWeights.first - weeklyWeights.last,
      'calories_weight_correlation': _correlation(
        correlationPairs,
        'calories',
        'weight_kg',
      ),
      'weeks': rows,
    };
  }

  /// Weekly 0-100 recovery score over the last [weeks] full weeks, and the
  /// direction of its recent half versus the earlier half.
  Future<Map<String, dynamic>> weeklyRecoveryTrend({int weeks = 8}) async {
    weeks = weeks.clamp(2, 12);
    final range = _fullWeeks(weeks);
    final nights = await AiSleepNight.load(
      db,
      startKey: dateKey(range.start),
      endKey: dateKey(range.end),
    );
    final training = await _trainingByDate(range.start, range.end);
    final goal = await AiSleepNight.goalMinutes(db);

    final buckets = <String, _RecoveryWeek>{};
    for (final night in nights) {
      buckets
          .putIfAbsent(_weekKey(night.date), _RecoveryWeek.new)
          .nights
          .add(night);
    }
    for (final entry in training.entries) {
      buckets
          .putIfAbsent(_weekKey(entry.key), _RecoveryWeek.new)
          .training
          .add(entry.value);
    }

    final rows = <Map<String, dynamic>>[];
    final scores = <double>[]; // newest first
    for (var i = 0; i < weeks; i++) {
      final key = dateKey(addDays(range.end, -(7 * i) - 6));
      final bucket = buckets[key];
      if (bucket == null) continue;
      final row = bucket.toRow(key, goal);
      rows.add(row);
      final score = row['recovery_score'] as double?;
      if (score != null) scores.add(score);
    }

    final half = scores.length ~/ 2;
    final recent = half == 0 ? null : AiToolMath.average(scores.take(half));
    final earlier = half == 0
        ? null
        : AiToolMath.average(scores.skip(scores.length - half));
    final change = recent == null || earlier == null ? null : recent - earlier;
    return {
      'applied': {
        ...AiDateWindow(range.start, range.end).toApplied(),
        'weeks': weeks,
      },
      'direction': change == null
          ? 'insufficient_data'
          : change >= 5
          ? 'improving'
          : change <= -5
          ? 'declining'
          : 'stable',
      'score_change': change,
      'weeks': rows,
    };
  }

  // ---------------------------------------------------------------------------
  // Queries
  // ---------------------------------------------------------------------------

  /// Training per local date: finished workouts and completed cardio only,
  /// from [start] to [end] (inclusive; callers never pass a future end).
  Future<Map<String, _DayTraining>> _trainingByDate(
    DateTime start,
    DateTime end,
  ) async {
    final database = await db.database;
    final rows = await database.rawQuery(
      '''
      SELECT date, SUM(workouts) workouts, SUM(runs) runs, SUM(bikes) bikes,
        AVG(feeling) feeling, AVG(cardio_rpe) cardio_rpe,
        SUM(volume_kg) volume_kg, SUM(sets) sets, SUM(distance_m) distance_m
      FROM (
        SELECT w.date AS date, 1 AS workouts, 0 AS runs, 0 AS bikes,
          w.feeling_rating AS feeling, NULL AS cardio_rpe,
          SUM(CASE WHEN s.is_complete = 1 AND s.is_warmup = 0
            THEN COALESCE(s.weight, 0) * COALESCE(s.reps, 0) ELSE 0 END)
            AS volume_kg,
          SUM(CASE WHEN s.is_complete = 1 AND s.is_warmup = 0
            THEN 1 ELSE 0 END) AS sets,
          0.0 AS distance_m
        FROM workouts w
        LEFT JOIN exercise_entries ee ON ee.workout_id = w.id
        LEFT JOIN sets s ON s.exercise_entry_id = ee.id
        WHERE w.end_time IS NOT NULL AND w.date >= ? AND w.date <= ?
        GROUP BY w.id
        UNION ALL
        SELECT substr(ra.started_at, 1, 10) AS date, 0 AS workouts,
          CASE WHEN ra.activity_type IN ('running', 'treadmill') THEN 1 ELSE 0 END
            AS runs,
          CASE WHEN ra.activity_type = 'stationary_bike' THEN 1 ELSE 0 END
            AS bikes,
          ra.feeling_rating AS feeling, ra.rpe AS cardio_rpe,
          0.0 AS volume_kg, 0 AS sets, ra.distance_meters AS distance_m
        FROM run_activities ra
        WHERE ra.status = 'completed' AND ra.started_at >= ?
          AND ra.started_at < ?
      ) daily
      GROUP BY date
      ''',
      [dateKey(start), dateKey(end), dateKey(start), dateKey(addDays(end, 1))],
    );
    return {for (final row in rows) row['date']! as String: _DayTraining(row)};
  }

  /// Monday of the last COMPLETED week and the window of [weeks] full weeks
  /// ending on its Sunday (the current, partial week is never included).
  ({DateTime start, DateTime end}) _fullWeeks(int weeks) {
    final lastMonday = addDays(mondayOf(dayOf(_now())), -7);
    return (
      start: addDays(lastMonday, -7 * (weeks - 1)),
      end: addDays(lastMonday, 6),
    );
  }

  static String _weekKey(String date) =>
      dateKey(mondayOf(DateTime.parse(date)));

  static double? _weightKg(Map<String, Object?> row) {
    final value = (row['value'] as num?)?.toDouble();
    if (value == null) return null;
    switch (((row['unit'] as String?) ?? 'kg').toLowerCase()) {
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

  /// Pearson correlation of [xKey] vs [yKey] over the rows that have both.
  static Map<String, dynamic> _correlation(
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
      return {'sample_size': pairs.length, 'quality': 'insufficient'};
    }
    final meanX = AiToolMath.average(pairs.map((p) => p.$1))!;
    final meanY = AiToolMath.average(pairs.map((p) => p.$2))!;
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
    return {
      'coefficient': denominator == 0 ? null : numerator / denominator,
      'sample_size': pairs.length,
      'quality': pairs.length >= 14 ? 'usable' : 'low_sample',
    };
  }
}

/// One local date of finished training. Absent measurements stay null.
class _DayTraining {
  final int workouts;
  final int runs;
  final int bikes;
  final int? sets;
  final double? volumeKg;
  final double? feeling;
  final double? cardioKm;
  final double? cardioRpe;

  _DayTraining(Map<String, Object?> row)
    : workouts = (row['workouts'] as num?)?.toInt() ?? 0,
      runs = (row['runs'] as num?)?.toInt() ?? 0,
      bikes = (row['bikes'] as num?)?.toInt() ?? 0,
      sets = _positiveInt(row['sets']),
      volumeKg = _positive(row['volume_kg']),
      feeling = (row['feeling'] as num?)?.toDouble(),
      cardioKm = _km(row['distance_m']),
      cardioRpe = (row['cardio_rpe'] as num?)?.toDouble();

  static double? _positive(Object? value) {
    final number = (value as num?)?.toDouble();
    return number == null || number <= 0 ? null : number;
  }

  static int? _positiveInt(Object? value) => _positive(value)?.toInt();

  static double? _km(Object? meters) {
    final value = _positive(meters);
    return value == null ? null : value / 1000;
  }
}

class _NutritionWeek {
  final List<double> calories = [];
  final List<double> protein = [];
  final List<double> carbs = [];
  final List<double> fat = [];
  final List<double> weights = [];

  void addNutrition(Map<String, Object?> row) {
    void add(String key, List<double> target) {
      final value = (row[key] as num?)?.toDouble();
      if (value != null) target.add(value);
    }

    add('calories', calories);
    add('protein_g', protein);
    add('carbs_g', carbs);
    add('fat_g', fat);
  }

  Map<String, dynamic> toRow(String weekStart) => {
    'week_start': weekStart,
    'logged_days': calories.isEmpty ? null : calories.length,
    'calories': AiToolMath.average(calories),
    'protein_g': AiToolMath.average(protein),
    'carbs_g': AiToolMath.average(carbs),
    'fat_g': AiToolMath.average(fat),
    'weight_kg': AiToolMath.average(weights),
  };
}

class _RecoveryWeek {
  final List<AiSleepNight> nights = [];
  final List<_DayTraining> training = [];

  Map<String, dynamic> toRow(String weekStart, int goalMinutes) {
    double? mean(Iterable<double?> values) =>
        AiToolMath.average(values.whereType<double>());
    final avgSleep = mean(nights.map((n) => n.minutes?.toDouble()));
    final avgEfficiency = mean(nights.map((n) => n.efficiencyPct));
    final regularity = AiSleepNight.regularityScore(
      [
        for (final n in nights)
          if (n.bedtimeMinutes != null) n.bedtimeMinutes!.toDouble(),
      ],
      [
        for (final n in nights)
          if (n.wakeMinutes != null) n.wakeMinutes!.toDouble(),
      ],
    );
    final feeling = mean(training.map((t) => t.feeling));

    final components = <(double, double)>[
      if (avgSleep != null) ((avgSleep / goalMinutes * 100).clamp(0, 100), 0.5),
      if (avgEfficiency != null) (avgEfficiency.clamp(0, 100), 0.2),
      if (regularity != null) (regularity, 0.2),
      if (feeling != null) ((feeling / 5 * 100).clamp(0, 100), 0.1),
    ];
    final weight = components.fold<double>(0, (sum, c) => sum + c.$2);
    // Without sleep duration (half of the weight) a week is not comparable
    // with weeks that have it, so it gets no score.
    final score = weight == 0 || avgSleep == null
        ? null
        : components.fold<double>(0, (sum, c) => sum + c.$1 * c.$2) / weight;

    final volume = training
        .map((t) => t.volumeKg)
        .whereType<double>()
        .fold<double>(0, (a, b) => a + b);
    final cardioKm = training
        .map((t) => t.cardioKm)
        .whereType<double>()
        .fold<double>(0, (a, b) => a + b);
    int total(int Function(_DayTraining) pick) =>
        training.fold<int>(0, (sum, t) => sum + pick(t));
    final workouts = total((t) => t.workouts);
    final runs = total((t) => t.runs);
    final bikes = total((t) => t.bikes);

    return {
      'week_start': weekStart,
      'recovery_score': score,
      'sleep_nights': nights.isEmpty ? null : nights.length,
      'sleep_min': avgSleep,
      'efficiency_pct': avgEfficiency,
      'regularity_score': regularity,
      'workout_feeling': feeling,
      'workouts': workouts,
      'volume_kg': volume > 0 ? volume : null,
      'runs': runs,
      'bike_rides': bikes,
      'cardio_km': cardioKm > 0 ? cardioKm : null,
      'cardio_rpe': mean(training.map((t) => t.cardioRpe)),
    };
  }
}
