import 'dart:math' as math;

/// Lookback windows offered by the body stats screen.
enum BodyStatsPeriod {
  weeks4,
  weeks12,
  weeks26,
  all,
}

extension BodyStatsPeriodWeeks on BodyStatsPeriod {
  /// How many Sunday-to-Saturday weeks the window spans, counting the current
  /// (partial) week. Null means no lower bound (all time).
  int? get weekCount => switch (this) {
    BodyStatsPeriod.weeks4 => 4,
    BodyStatsPeriod.weeks12 => 12,
    BodyStatsPeriod.weeks26 => 26,
    BodyStatsPeriod.all => null,
  };
}

/// One day of measurements collapsed to a single value. Several entries on the
/// same day (morning/evening, left/right) are averaged so a day with three
/// weigh-ins does not outweigh a day with one.
class BodyDailyPoint {
  final DateTime date;
  final double value;
  final int entryCount;

  const BodyDailyPoint({
    required this.date,
    required this.value,
    required this.entryCount,
  });
}

/// A Sunday-to-Saturday week of daily points.
class BodyWeekBucket {
  final DateTime weekStart;
  final double? average;
  final double? min;
  final double? max;
  final double? first;
  final double? last;

  /// Number of raw entries (not days) recorded in the week.
  final int entryCount;

  /// Number of distinct days with at least one entry.
  final int dayCount;

  /// Average minus the average of the closest preceding week that has data.
  /// Null for the first week with data.
  final double? deltaVsPreviousWeek;

  const BodyWeekBucket({
    required this.weekStart,
    required this.average,
    required this.min,
    required this.max,
    required this.first,
    required this.last,
    required this.entryCount,
    required this.dayCount,
    required this.deltaVsPreviousWeek,
  });

  bool get hasData => average != null;

  DateTime get weekEnd => weekStart.add(const Duration(days: 6));
}

/// A calendar month of daily points, used by the monthly summary list.
class BodyMonthBucket {
  final DateTime monthStart;
  final double average;
  final double min;
  final double max;
  final int entryCount;
  final double? deltaVsPreviousMonth;

  const BodyMonthBucket({
    required this.monthStart,
    required this.average,
    required this.min,
    required this.max,
    required this.entryCount,
    required this.deltaVsPreviousMonth,
  });
}

/// Current week against the reference week it is compared with.
class BodyWeekComparison {
  final BodyWeekBucket current;
  final BodyWeekBucket? reference;

  const BodyWeekComparison({required this.current, this.reference});

  /// Positive means the current week average is higher than the reference.
  double? get delta {
    final a = current.average;
    final b = reference?.average;
    if (a == null || b == null) return null;
    return a - b;
  }

  double? get percent {
    final b = reference?.average;
    final d = delta;
    if (d == null || b == null || b == 0) return null;
    return d / b * 100;
  }

  /// True when the reference week is the week immediately before the current
  /// one; false when an empty week was skipped to find data.
  bool get referenceIsAdjacent {
    final ref = reference;
    if (ref == null) return false;
    return current.weekStart.difference(ref.weekStart).inDays == 7;
  }
}

/// Progress of the current value toward a target value.
class BodyGoalProgress {
  final double startValue;
  final double currentValue;
  final double targetValue;

  /// Observed change per week, used for the projection. Null disables the ETA.
  final double? ratePerWeek;

  const BodyGoalProgress({
    required this.startValue,
    required this.currentValue,
    required this.targetValue,
    required this.ratePerWeek,
  });

  double get totalDistance => (targetValue - startValue).abs();

  double get remaining => (targetValue - currentValue).abs();

  /// 0 when nothing moved, 1 when the target is reached. Clamped, so
  /// overshooting still reads as complete.
  double get fraction {
    if (totalDistance <= 0.001) return currentValue == targetValue ? 1 : 0;
    final done = (currentValue - startValue).abs();
    // Moving away from the target counts as zero progress, not negative.
    final towardTarget =
        (targetValue - currentValue).abs() < (targetValue - startValue).abs();
    if (!towardTarget) return 0;
    return (done / totalDistance).clamp(0.0, 1.0);
  }

  bool get reached => remaining < 0.05;

  /// True when the current value went past the target in the direction of
  /// travel — e.g. a cut to 77.8 kg that is already at 77.3 kg. Overshooting
  /// is success, not a deviation.
  bool get passed {
    final direction = (targetValue - startValue).sign;
    if (direction == 0) return false;
    return (currentValue - targetValue).sign == direction;
  }

  bool get achieved => reached || passed;

  /// True when the current trend moves toward the target, or the target is
  /// already met.
  bool get onTrack {
    if (achieved) return true;
    final rate = ratePerWeek;
    if (rate == null || rate == 0) return false;
    return (targetValue - currentValue).sign == rate.sign;
  }

  /// Weeks left at the observed rate, or null when the trend does not lead to
  /// the target (wrong direction, flat, or absurdly far away).
  double? get weeksToTarget {
    if (achieved) return 0;
    final rate = ratePerWeek;
    if (rate == null || rate == 0 || !onTrack) return null;
    final weeks = remaining / rate.abs();
    if (!weeks.isFinite || weeks > 260) return null;
    return weeks;
  }

  /// Date the target is reached at the observed rate.
  DateTime? etaFrom(DateTime now) {
    final weeks = weeksToTarget;
    if (weeks == null) return null;
    return DateTime(
      now.year,
      now.month,
      now.day,
    ).add(Duration(days: (weeks * 7).ceil()));
  }
}

/// Everything the body stats screen needs for one measurement type, derived
/// from the raw `body_measurements` rows.
class BodyProgressAnalytics {
  final BodyStatsPeriod period;
  final DateTime now;

  /// Daily averages inside the period, oldest first.
  final List<BodyDailyPoint> daily;

  /// Trailing mean of the last 7 daily points, aligned with [daily]. The
  /// window counts entries rather than calendar days so it still smooths when
  /// measurements are weekly.
  final List<double> smoothed;

  /// Contiguous Sunday-start weeks covering the period, oldest first. Weeks
  /// without data are present with `hasData == false` so gaps stay visible.
  final List<BodyWeekBucket> weeks;

  final List<BodyMonthBucket> months;
  final BodyWeekComparison weekComparison;

  final int entryCount;
  final double? firstValue;
  final double? lastValue;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final double? minValue;
  final double? maxValue;
  final double? averageValue;

  /// Least-squares slope over the period, expressed per week. Null when there
  /// is not enough spread to fit a line.
  final double? ratePerWeek;

  /// Weeks in the period that have at least one entry.
  final int weeksWithData;

  /// Consecutive weeks with at least one entry counting back from the current
  /// week (a current week with nothing logged yet does not break it).
  final int weekStreak;

  const BodyProgressAnalytics({
    required this.period,
    required this.now,
    required this.daily,
    required this.smoothed,
    required this.weeks,
    required this.months,
    required this.weekComparison,
    required this.entryCount,
    required this.firstValue,
    required this.lastValue,
    required this.firstDate,
    required this.lastDate,
    required this.minValue,
    required this.maxValue,
    required this.averageValue,
    required this.ratePerWeek,
    required this.weeksWithData,
    required this.weekStreak,
  });

  bool get isEmpty => daily.isEmpty;

  /// Number of distinct days with data.
  int get dayCount => daily.length;

  double? get totalChange {
    if (firstValue == null || lastValue == null) return null;
    return lastValue! - firstValue!;
  }

  double? get amplitude {
    if (minValue == null || maxValue == null) return null;
    return maxValue! - minValue!;
  }

  double? get ratePercentPerWeek {
    final rate = ratePerWeek;
    final base = lastValue;
    if (rate == null || base == null || base == 0) return null;
    return rate / base * 100;
  }

  int? get daysSinceLast {
    final last = lastDate;
    if (last == null) return null;
    return _dateOnly(now).difference(last).inDays;
  }

  /// Entries per week across the weeks covered by the period.
  double get entriesPerWeek {
    if (weeks.isEmpty) return 0;
    return entryCount / weeks.length;
  }

  /// Share of the period's weeks that have at least one entry.
  double get consistency {
    if (weeks.isEmpty) return 0;
    return weeksWithData / weeks.length;
  }

  /// Value projected [weeks] ahead at the observed rate.
  double? projectedValue(int weeksAhead) {
    final rate = ratePerWeek;
    final base = lastValue;
    if (rate == null || base == null) return null;
    return base + rate * weeksAhead;
  }

  /// Progress toward [target], anchored at the first value of the period (or
  /// [startValue] when the caller knows a better anchor, e.g. a phase start).
  BodyGoalProgress? goalProgress(double? target, {double? startValue}) {
    final current = lastValue;
    if (target == null || current == null) return null;
    final start = startValue ?? firstValue ?? current;
    return BodyGoalProgress(
      startValue: start,
      currentValue: current,
      targetValue: target,
      ratePerWeek: ratePerWeek,
    );
  }

  /// Builds analytics from raw `body_measurements` rows of a single type.
  /// Rows may arrive in any order and may contain several entries per day.
  factory BodyProgressAnalytics.fromRows(
    List<Map<String, dynamic>> rows, {
    required BodyStatsPeriod period,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final today = _dateOnly(clock);
    // The window is week-aligned so the daily series, the weekly buckets and
    // the monthly summary all cover exactly the same Sundays.
    final weekCount = period.weekCount;
    final cutoff = weekCount == null
        ? null
        : _sundayOf(today).subtract(Duration(days: 7 * (weekCount - 1)));

    // ── Collapse raw rows into daily averages ──────────────────────────
    final sums = <DateTime, double>{};
    final counts = <DateTime, int>{};
    for (final row in rows) {
      final date = _parseDate(row['date']);
      final value = (row['value'] as num?)?.toDouble();
      if (date == null || value == null || !value.isFinite) continue;
      if (date.isAfter(today)) continue;
      if (cutoff != null && date.isBefore(cutoff)) continue;
      sums[date] = (sums[date] ?? 0) + value;
      counts[date] = (counts[date] ?? 0) + 1;
    }

    final dates = sums.keys.toList()..sort();
    final daily = <BodyDailyPoint>[
      for (final d in dates)
        BodyDailyPoint(
          date: d,
          value: sums[d]! / counts[d]!,
          entryCount: counts[d]!,
        ),
    ];

    final entryCount = counts.values.fold<int>(0, (a, b) => a + b);
    final values = daily.map((p) => p.value).toList();

    double? minValue;
    double? maxValue;
    double? averageValue;
    if (values.isNotEmpty) {
      minValue = values.reduce(math.min);
      maxValue = values.reduce(math.max);
      averageValue = values.reduce((a, b) => a + b) / values.length;
    }

    final weeks = _buildWeeks(daily: daily, today: today, cutoff: cutoff);

    final currentWeekStart = _sundayOf(today);
    final currentWeek = weeks.isEmpty
        ? BodyWeekBucket(
            weekStart: currentWeekStart,
            average: null,
            min: null,
            max: null,
            first: null,
            last: null,
            entryCount: 0,
            dayCount: 0,
            deltaVsPreviousWeek: null,
          )
        : weeks.last;
    BodyWeekBucket? reference;
    for (var i = weeks.length - 2; i >= 0; i--) {
      if (weeks[i].hasData) {
        reference = weeks[i];
        break;
      }
    }

    return BodyProgressAnalytics(
      period: period,
      now: clock,
      daily: daily,
      smoothed: _trailingMean(values, window: 7),
      weeks: weeks,
      months: _buildMonths(daily),
      weekComparison: BodyWeekComparison(
        current: currentWeek,
        reference: reference,
      ),
      entryCount: entryCount,
      firstValue: values.isEmpty ? null : values.first,
      lastValue: values.isEmpty ? null : values.last,
      firstDate: daily.isEmpty ? null : daily.first.date,
      lastDate: daily.isEmpty ? null : daily.last.date,
      minValue: minValue,
      maxValue: maxValue,
      averageValue: averageValue,
      ratePerWeek: _ratePerWeek(daily),
      weeksWithData: weeks.where((w) => w.hasData).length,
      weekStreak: _weekStreak(daily, currentWeekStart),
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Sunday that opens the week containing [d]. `DateTime.sunday` is 7, so it
  /// wraps to 0 to keep Sunday as the first day.
  static DateTime _sundayOf(DateTime d) {
    final day = _dateOnly(d);
    return day.subtract(Duration(days: day.weekday % 7));
  }

  static DateTime? _parseDate(Object? raw) {
    if (raw is! String || raw.length < 10) return null;
    try {
      return _dateOnly(DateTime.parse(raw.substring(0, 10)));
    } catch (_) {
      return null;
    }
  }

  /// Trailing mean over up to [window] previous points (points, not days), so
  /// the series never looks into the future.
  static List<double> _trailingMean(List<double> values, {required int window}) {
    final out = <double>[];
    for (var i = 0; i < values.length; i++) {
      final start = math.max(0, i - window + 1);
      var sum = 0.0;
      for (var j = start; j <= i; j++) {
        sum += values[j];
      }
      out.add(sum / (i - start + 1));
    }
    return out;
  }

  /// Least-squares slope of value over days, scaled to a week. Needs at least
  /// three days spanning a week so a couple of noisy weigh-ins cannot produce
  /// a wild trend.
  static double? _ratePerWeek(List<BodyDailyPoint> daily) {
    if (daily.length < 3) return null;
    final spanDays = daily.last.date.difference(daily.first.date).inDays;
    if (spanDays < 7) return null;

    final origin = daily.first.date;
    var sumX = 0.0;
    var sumY = 0.0;
    var sumXY = 0.0;
    var sumXX = 0.0;
    for (final p in daily) {
      final x = p.date.difference(origin).inDays.toDouble();
      sumX += x;
      sumY += p.value;
      sumXY += x * p.value;
      sumXX += x * x;
    }
    final n = daily.length.toDouble();
    final denominator = n * sumXX - sumX * sumX;
    if (denominator.abs() < 1e-9) return null;
    final slope = (n * sumXY - sumX * sumY) / denominator;
    if (!slope.isFinite) return null;
    return slope * 7;
  }

  static List<BodyWeekBucket> _buildWeeks({
    required List<BodyDailyPoint> daily,
    required DateTime today,
    required DateTime? cutoff,
  }) {
    final currentWeekStart = _sundayOf(today);
    final DateTime firstWeekStart;
    if (cutoff != null) {
      firstWeekStart = _sundayOf(cutoff);
    } else if (daily.isNotEmpty) {
      firstWeekStart = _sundayOf(daily.first.date);
    } else {
      firstWeekStart = currentWeekStart;
    }

    final weekCount =
        (currentWeekStart.difference(firstWeekStart).inDays ~/ 7 + 1).clamp(
          1,
          260,
        );
    final starts = <DateTime>[
      for (var i = 0; i < weekCount; i++)
        firstWeekStart.add(Duration(days: 7 * i)),
    ];

    final grouped = <DateTime, List<BodyDailyPoint>>{};
    for (final p in daily) {
      grouped.putIfAbsent(_sundayOf(p.date), () => []).add(p);
    }

    final buckets = <BodyWeekBucket>[];
    double? previousAverage;
    for (final start in starts) {
      final points = grouped[start] ?? const <BodyDailyPoint>[];
      if (points.isEmpty) {
        buckets.add(
          BodyWeekBucket(
            weekStart: start,
            average: null,
            min: null,
            max: null,
            first: null,
            last: null,
            entryCount: 0,
            dayCount: 0,
            deltaVsPreviousWeek: null,
          ),
        );
        continue;
      }
      final vals = points.map((p) => p.value).toList();
      final average = vals.reduce((a, b) => a + b) / vals.length;
      buckets.add(
        BodyWeekBucket(
          weekStart: start,
          average: average,
          min: vals.reduce(math.min),
          max: vals.reduce(math.max),
          first: points.first.value,
          last: points.last.value,
          entryCount: points.fold<int>(0, (a, p) => a + p.entryCount),
          dayCount: points.length,
          deltaVsPreviousWeek: previousAverage == null
              ? null
              : average - previousAverage,
        ),
      );
      previousAverage = average;
    }
    return buckets;
  }

  static List<BodyMonthBucket> _buildMonths(List<BodyDailyPoint> daily) {
    final grouped = <DateTime, List<BodyDailyPoint>>{};
    for (final p in daily) {
      grouped
          .putIfAbsent(DateTime(p.date.year, p.date.month), () => [])
          .add(p);
    }
    final months = grouped.keys.toList()..sort();
    final out = <BodyMonthBucket>[];
    double? previousAverage;
    for (final m in months) {
      final vals = grouped[m]!.map((p) => p.value).toList();
      final average = vals.reduce((a, b) => a + b) / vals.length;
      out.add(
        BodyMonthBucket(
          monthStart: m,
          average: average,
          min: vals.reduce(math.min),
          max: vals.reduce(math.max),
          entryCount: grouped[m]!.fold<int>(0, (a, p) => a + p.entryCount),
          deltaVsPreviousMonth: previousAverage == null
              ? null
              : average - previousAverage,
        ),
      );
      previousAverage = average;
    }
    return out;
  }

  static int _weekStreak(List<BodyDailyPoint> daily, DateTime currentWeekStart) {
    if (daily.isEmpty) return 0;
    final weeksWithData = <DateTime>{for (final p in daily) _sundayOf(p.date)};
    var cursor = weeksWithData.contains(currentWeekStart)
        ? currentWeekStart
        : currentWeekStart.subtract(const Duration(days: 7));
    var streak = 0;
    while (weeksWithData.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 7));
    }
    return streak;
  }
}
