import 'package:workout_notes/models/run_activity.dart';

enum RunStatsPeriod { weeks4, weeks12, year, all }

extension RunStatsPeriodDays on RunStatsPeriod {
  /// Calendar weeks (Monday to Sunday, current week included) the period
  /// spans. Null means no lower bound (all time).
  int? get weekCount => switch (this) {
    RunStatsPeriod.weeks4 => 4,
    RunStatsPeriod.weeks12 => 12,
    RunStatsPeriod.year => 52,
    RunStatsPeriod.all => null,
  };

  /// Null means no lower bound (all time).
  int? get lookbackDays => weekCount == null ? null : weekCount! * 7;
}

/// One bar of the trend charts: a calendar week, or a calendar month when the
/// selected range is too long to draw week by week ([spanDays] > 7).
class RunWeekBucket {
  final DateTime weekStart;
  final int runCount;
  final double distanceMeters;
  final int movingTimeSeconds;
  final int spanDays;

  const RunWeekBucket({
    required this.weekStart,
    required this.runCount,
    required this.distanceMeters,
    required this.movingTimeSeconds,
    this.spanDays = 7,
  });

  bool get isMonthly => spanDays > 7;
}

/// One day of the current week, used by the weekday strip.
class RunDayBucket {
  final DateTime date;
  final int runCount;
  final double distanceMeters;

  const RunDayBucket({
    required this.date,
    required this.runCount,
    required this.distanceMeters,
  });

  bool get hasRun => runCount > 0;
}

class RunPacePoint {
  final DateTime date;
  final double paceSecPerKm;
  final double distanceMeters;

  const RunPacePoint({
    required this.date,
    required this.paceSecPerKm,
    required this.distanceMeters,
  });
}

/// Least-squares line through (x, y) pairs. Used for the pace trend line.
class RunLinearFit {
  final double slope;
  final double intercept;

  const RunLinearFit({required this.slope, required this.intercept});

  double at(double x) => intercept + slope * x;

  /// Null with fewer than two points or a degenerate x spread.
  static RunLinearFit? fit(List<double> xs, List<double> ys) {
    if (xs.length != ys.length || xs.length < 2) return null;
    final n = xs.length;
    final meanX = xs.reduce((a, b) => a + b) / n;
    final meanY = ys.reduce((a, b) => a + b) / n;
    var num = 0.0;
    var den = 0.0;
    for (var i = 0; i < n; i++) {
      num += (xs[i] - meanX) * (ys[i] - meanY);
      den += (xs[i] - meanX) * (xs[i] - meanX);
    }
    if (den <= 0) return null;
    final slope = num / den;
    return RunLinearFit(slope: slope, intercept: meanY - slope * meanX);
  }
}

/// Totals for an arbitrary date window, used to compare periods.
class RunWindowTotals {
  final int runCount;
  final double distanceMeters;
  final int movingTimeSeconds;
  final double? avgPaceSecPerKm;

  const RunWindowTotals({
    required this.runCount,
    required this.distanceMeters,
    required this.movingTimeSeconds,
    required this.avgPaceSecPerKm,
  });

  static const empty = RunWindowTotals(
    runCount: 0,
    distanceMeters: 0,
    movingTimeSeconds: 0,
    avgPaceSecPerKm: null,
  );

  bool get isEmpty => runCount == 0;
}

/// Running dashboard numbers for one selected period.
///
/// Volume, time and frequency count every running session (outdoor and
/// treadmill). Metrics that need a GPS track - best pace, best kilometre and
/// the pace trend - only look at outdoor runs ([RunActivity.isRun]).
///
/// Weekly averages have a single definition everywhere: the total over the
/// period divided by [periodWeekCount], the calendar weeks the period covers
/// (the week in progress included).
class RunProgressAnalytics {
  /// Above this many weeks the trend charts group by month.
  static const int maxWeeklyChartBuckets = 60;

  final RunStatsPeriod period;
  final List<RunActivity> activities;
  final DateTime now;

  final int runCount;
  final double totalDistanceMeters;
  final int totalMovingTimeSeconds;
  final int totalCalories;
  final double totalElevationGainMeters;
  final double? avgPaceSecPerKm;
  final double? bestPaceSecPerKm;
  final double? bestKmSplitSecPerKm;
  final RunActivity? longestRun;
  final RunActivity? fastestRun;

  /// Outdoor run holding [bestKmSplitSecPerKm].
  final RunActivity? bestKmSplitRun;
  final double thisWeekDistanceMeters;
  final double lastWeekDistanceMeters;
  final int thisWeekRunCount;
  final int lastWeekRunCount;

  /// Calendar weeks the period covers; the divisor of every weekly average.
  final int periodWeekCount;

  /// One bucket per calendar week of the period (at least four for all-time).
  final List<RunWeekBucket> weeklyBuckets;

  /// Buckets the trend charts draw: [weeklyBuckets], or months when the
  /// period is longer than [maxWeeklyChartBuckets] weeks.
  final List<RunWeekBucket> trendBuckets;
  final List<RunDayBucket> thisWeekDays;
  final List<RunPacePoint> paceTrend;

  /// First day covered by the selected period (period start, or the first
  /// recorded run for [RunStatsPeriod.all]).
  final DateTime? periodStart;

  /// Same-length window immediately before the selected period. Empty (and
  /// [hasPreviousPeriod] false) for all-time.
  final RunWindowTotals previousPeriod;
  final bool hasPreviousPeriod;

  /// Consecutive weeks with at least one run, counting back from the current
  /// week (or the previous one when the current week has no run yet).
  final int weekStreak;

  const RunProgressAnalytics({
    required this.period,
    required this.activities,
    required this.now,
    required this.runCount,
    required this.totalDistanceMeters,
    required this.totalMovingTimeSeconds,
    required this.totalCalories,
    this.totalElevationGainMeters = 0,
    required this.avgPaceSecPerKm,
    required this.bestPaceSecPerKm,
    required this.bestKmSplitSecPerKm,
    this.bestKmSplitRun,
    required this.longestRun,
    required this.fastestRun,
    required this.thisWeekDistanceMeters,
    required this.lastWeekDistanceMeters,
    required this.thisWeekRunCount,
    required this.lastWeekRunCount,
    required this.periodWeekCount,
    required this.weeklyBuckets,
    required this.trendBuckets,
    required this.thisWeekDays,
    required this.paceTrend,
    required this.periodStart,
    required this.previousPeriod,
    required this.hasPreviousPeriod,
    required this.weekStreak,
  });

  bool get isEmpty => runCount == 0;

  double get distanceDeltaVsLastWeek =>
      thisWeekDistanceMeters - lastWeekDistanceMeters;

  /// False when neither this week nor last week has a run: there is nothing
  /// to compare, so no comparison line should be shown.
  bool get hasWeekComparison =>
      thisWeekDistanceMeters > 0 || lastWeekDistanceMeters > 0;

  /// Average distance per calendar week across the period.
  double get avgWeeklyDistanceMeters =>
      periodWeekCount <= 0 ? 0 : totalDistanceMeters / periodWeekCount;

  /// Average number of runs per calendar week across the period.
  double get avgRunsPerWeek =>
      periodWeekCount <= 0 ? 0 : runCount / periodWeekCount;

  /// True when [trendBuckets] are months instead of weeks.
  bool get trendIsMonthly => trendBuckets.any((b) => b.isMonthly);

  /// Average distance per trend bucket (week or month), for the chart's
  /// dashed reference line.
  double get trendAvgDistanceMeters =>
      trendBuckets.isEmpty ? 0 : totalDistanceMeters / trendBuckets.length;

  /// Average runs per trend bucket (week or month).
  double get trendAvgRuns =>
      trendBuckets.isEmpty ? 0 : runCount / trendBuckets.length;

  /// Distance change against the previous window of the same length, as a
  /// fraction (0.12 means +12%). Null when there is nothing to compare with.
  double? get distanceRatioVsPreviousPeriod {
    if (!hasPreviousPeriod || previousPeriod.distanceMeters <= 0) return null;
    return totalDistanceMeters / previousPeriod.distanceMeters - 1;
  }

  /// Pace change against the previous window, in seconds per km. Negative
  /// means faster than before.
  double? get paceDeltaVsPreviousPeriod {
    final current = avgPaceSecPerKm;
    final previous = previousPeriod.avgPaceSecPerKm;
    if (!hasPreviousPeriod || current == null || previous == null) return null;
    return current - previous;
  }

  /// Current week distance as a fraction of the period weekly average.
  double? get thisWeekVsAverageRatio {
    final average = avgWeeklyDistanceMeters;
    if (average <= 0) return null;
    return thisWeekDistanceMeters / average;
  }

  /// Line through the pace trend, x in days since the first point. Slope is
  /// seconds per km per day (negative means getting faster).
  RunLinearFit? get paceTrendFit {
    if (paceTrend.length < 3) return null;
    final origin = paceTrend.first.date;
    return RunLinearFit.fit(
      [for (final p in paceTrend) _daysSince(origin, p.date)],
      [for (final p in paceTrend) p.paceSecPerKm],
    );
  }

  /// Pace change per 30 days from [paceTrendFit] (negative is faster), or
  /// null when there is no usable trend.
  double? get paceTrendPerMonthSec {
    final fit = paceTrendFit;
    if (fit == null) return null;
    return fit.slope * 30;
  }

  static double _daysSince(DateTime origin, DateTime date) =>
      date.difference(origin).inMinutes / (60 * 24);

  factory RunProgressAnalytics.fromActivities(
    List<RunActivity> all, {
    required RunStatsPeriod period,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final localNow = DateTime(clock.year, clock.month, clock.day);
    final thisWeekStart = _mondayOf(localNow);

    final completed = all
        .where((a) => a.status == 'completed' && a.isRunning)
        .toList();

    // Period window, aligned to calendar weeks so the totals, the weekly
    // buckets and the weekly averages all describe the same span.
    final fixedWeeks = period.weekCount;
    DateTime? windowStart;
    int weekCount;
    if (fixedWeeks != null) {
      weekCount = fixedWeeks;
      windowStart = thisWeekStart.subtract(
        Duration(days: 7 * (fixedWeeks - 1)),
      );
    } else if (completed.isEmpty) {
      weekCount = 1;
    } else {
      final first = completed
          .map((a) => _dateOnly(a.startedAt.toLocal()))
          .reduce((a, b) => a.isBefore(b) ? a : b);
      windowStart = _mondayOf(first);
      weekCount = thisWeekStart.difference(windowStart).inDays ~/ 7 + 1;
    }

    final activities = completed.where((a) {
      if (windowStart == null) return true;
      return !_dateOnly(a.startedAt.toLocal()).isBefore(windowStart);
    }).toList()..sort((a, b) => a.startedAt.compareTo(b.startedAt));

    var totalDistance = 0.0;
    var totalMoving = 0;
    var totalCalories = 0;
    var totalElevation = 0.0;
    var paceWeight = 0.0;
    var paceWeightedSum = 0.0;
    double? bestKmSplit;
    RunActivity? bestKmSplitRun;
    RunActivity? longest;
    RunActivity? fastest;

    for (final a in activities) {
      totalDistance += a.distanceMeters;
      totalMoving += a.movingTimeSeconds;
      totalCalories += a.calories ?? 0;
      totalElevation += a.elevationGainMeters ?? 0;

      if (longest == null || a.distanceMeters > longest.distanceMeters) {
        longest = a;
      }

      final pace = a.avgPaceSecPerKm;
      final validPace =
          pace != null && pace.isFinite && pace > 0 && a.distanceMeters >= 1000;
      if (validPace) {
        paceWeightedSum += pace * a.distanceMeters;
        paceWeight += a.distanceMeters;
      }

      // GPS-only metrics.
      if (!a.isRun) continue;
      final split = a.bestSplitPaceSecPerKm;
      if (split != null && split.isFinite && split > 0) {
        if (bestKmSplit == null || split < bestKmSplit) {
          bestKmSplit = split;
          bestKmSplitRun = a;
        }
      }
      if (validPace &&
          (fastest == null ||
              pace < (fastest.avgPaceSecPerKm ?? double.infinity))) {
        fastest = a;
      }
    }

    final nextWeekStart = thisWeekStart.add(const Duration(days: 7));
    final lastWeekStart = thisWeekStart.subtract(const Duration(days: 7));
    var thisWeekDistance = 0.0;
    var lastWeekDistance = 0.0;
    var thisWeekRuns = 0;
    var lastWeekRuns = 0;
    final dayCounts = List<int>.filled(7, 0);
    final dayDistances = List<double>.filled(7, 0);

    for (final a in completed) {
      final d = _dateOnly(a.startedAt.toLocal());
      if (!d.isBefore(thisWeekStart) && d.isBefore(nextWeekStart)) {
        thisWeekDistance += a.distanceMeters;
        thisWeekRuns++;
        final index = d.difference(thisWeekStart).inDays;
        if (index >= 0 && index < 7) {
          dayCounts[index]++;
          dayDistances[index] += a.distanceMeters;
        }
      } else if (!d.isBefore(lastWeekStart) && d.isBefore(thisWeekStart)) {
        lastWeekDistance += a.distanceMeters;
        lastWeekRuns++;
      }
    }

    final bucketWeeks = fixedWeeks ?? (weekCount < 4 ? 4 : weekCount);
    final weekly = _buildWeeklyBuckets(
      activities: activities,
      weekCount: bucketWeeks,
      thisWeekStart: thisWeekStart,
    );
    final trend = weekly.length > maxWeeklyChartBuckets
        ? _buildMonthlyBuckets(activities: activities, localNow: localNow)
        : weekly;

    final paceTrend = <RunPacePoint>[
      for (final a in activities)
        if (a.isRun &&
            a.avgPaceSecPerKm != null &&
            a.avgPaceSecPerKm!.isFinite &&
            a.avgPaceSecPerKm! > 0 &&
            a.distanceMeters >= 1000)
          RunPacePoint(
            date: a.startedAt.toLocal(),
            paceSecPerKm: a.avgPaceSecPerKm!,
            distanceMeters: a.distanceMeters,
          ),
    ];

    final previous = (windowStart == null || fixedWeeks == null)
        ? RunWindowTotals.empty
        : _windowTotals(
            completed,
            start: windowStart.subtract(Duration(days: 7 * weekCount)),
            end: windowStart,
          );

    final periodStart = fixedWeeks != null
        ? windowStart
        : (activities.isEmpty
              ? null
              : _dateOnly(activities.first.startedAt.toLocal()));

    return RunProgressAnalytics(
      period: period,
      activities: activities,
      now: clock,
      runCount: activities.length,
      totalDistanceMeters: totalDistance,
      totalMovingTimeSeconds: totalMoving,
      totalCalories: totalCalories,
      totalElevationGainMeters: totalElevation,
      avgPaceSecPerKm: paceWeight > 0 ? paceWeightedSum / paceWeight : null,
      bestPaceSecPerKm: fastest?.avgPaceSecPerKm,
      bestKmSplitSecPerKm: bestKmSplit,
      bestKmSplitRun: bestKmSplitRun,
      longestRun: longest,
      fastestRun: fastest,
      thisWeekDistanceMeters: thisWeekDistance,
      lastWeekDistanceMeters: lastWeekDistance,
      thisWeekRunCount: thisWeekRuns,
      lastWeekRunCount: lastWeekRuns,
      periodWeekCount: weekCount,
      weeklyBuckets: weekly,
      trendBuckets: trend,
      thisWeekDays: [
        for (var i = 0; i < 7; i++)
          RunDayBucket(
            date: thisWeekStart.add(Duration(days: i)),
            runCount: dayCounts[i],
            distanceMeters: dayDistances[i],
          ),
      ],
      paceTrend: paceTrend,
      periodStart: periodStart,
      previousPeriod: previous,
      hasPreviousPeriod: fixedWeeks != null && !previous.isEmpty,
      weekStreak: _weekStreak(completed, thisWeekStart),
    );
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime _mondayOf(DateTime d) {
    final day = _dateOnly(d);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  static RunWindowTotals _windowTotals(
    List<RunActivity> completed, {
    required DateTime start,
    required DateTime end,
  }) {
    var count = 0;
    var distance = 0.0;
    var moving = 0;
    var paceWeight = 0.0;
    var paceWeightedSum = 0.0;

    for (final a in completed) {
      final d = _dateOnly(a.startedAt.toLocal());
      if (d.isBefore(start) || !d.isBefore(end)) continue;
      count++;
      distance += a.distanceMeters;
      moving += a.movingTimeSeconds;
      final pace = a.avgPaceSecPerKm;
      if (pace != null &&
          pace.isFinite &&
          pace > 0 &&
          a.distanceMeters >= 1000) {
        paceWeightedSum += pace * a.distanceMeters;
        paceWeight += a.distanceMeters;
      }
    }

    return RunWindowTotals(
      runCount: count,
      distanceMeters: distance,
      movingTimeSeconds: moving,
      avgPaceSecPerKm: paceWeight > 0 ? paceWeightedSum / paceWeight : null,
    );
  }

  /// Counts back week by week while every week has at least one run. A week
  /// still in progress with no run yet does not break the streak.
  static int _weekStreak(List<RunActivity> completed, DateTime thisWeekStart) {
    if (completed.isEmpty) return 0;
    final weeksWithRuns = <DateTime>{
      for (final a in completed) _mondayOf(a.startedAt.toLocal()),
    };

    var cursor = weeksWithRuns.contains(thisWeekStart)
        ? thisWeekStart
        : thisWeekStart.subtract(const Duration(days: 7));
    var streak = 0;
    while (weeksWithRuns.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 7));
    }
    return streak;
  }

  static List<RunWeekBucket> _buildWeeklyBuckets({
    required List<RunActivity> activities,
    required int weekCount,
    required DateTime thisWeekStart,
  }) {
    final starts = <DateTime>[
      for (var i = weekCount - 1; i >= 0; i--)
        thisWeekStart.subtract(Duration(days: 7 * i)),
    ];
    final indexByStart = <DateTime, int>{
      for (var i = 0; i < starts.length; i++) starts[i]: i,
    };

    final counts = List<int>.filled(starts.length, 0);
    final distances = List<double>.filled(starts.length, 0);
    final times = List<int>.filled(starts.length, 0);

    for (final a in activities) {
      final idx = indexByStart[_mondayOf(a.startedAt.toLocal())];
      if (idx == null) continue;
      counts[idx]++;
      distances[idx] += a.distanceMeters;
      times[idx] += a.movingTimeSeconds;
    }

    return [
      for (var i = 0; i < starts.length; i++)
        RunWeekBucket(
          weekStart: starts[i],
          runCount: counts[i],
          distanceMeters: distances[i],
          movingTimeSeconds: times[i],
        ),
    ];
  }

  /// Month buckets from the first run's month to the current one.
  static List<RunWeekBucket> _buildMonthlyBuckets({
    required List<RunActivity> activities,
    required DateTime localNow,
  }) {
    if (activities.isEmpty) return const [];
    final first = activities.first.startedAt.toLocal();
    final months =
        (localNow.year - first.year) * 12 + localNow.month - first.month + 1;
    final counts = List<int>.filled(months, 0);
    final distances = List<double>.filled(months, 0);
    final times = List<int>.filled(months, 0);

    for (final a in activities) {
      final d = a.startedAt.toLocal();
      final idx = (d.year - first.year) * 12 + d.month - first.month;
      if (idx < 0 || idx >= months) continue;
      counts[idx]++;
      distances[idx] += a.distanceMeters;
      times[idx] += a.movingTimeSeconds;
    }

    return [
      for (var i = 0; i < months; i++)
        () {
          final start = DateTime(first.year, first.month + i);
          final next = DateTime(first.year, first.month + i + 1);
          return RunWeekBucket(
            weekStart: start,
            runCount: counts[i],
            distanceMeters: distances[i],
            movingTimeSeconds: times[i],
            spanDays: next.difference(start).inDays,
          );
        }(),
    ];
  }
}
