import 'package:workout_notes/models/run_activity.dart';

enum RunStatsPeriod {
  weeks4,
  weeks12,
  year,
  all,
}

extension RunStatsPeriodDays on RunStatsPeriod {
  /// Null means no lower bound (all time).
  int? get lookbackDays => switch (this) {
        RunStatsPeriod.weeks4 => 28,
        RunStatsPeriod.weeks12 => 84,
        RunStatsPeriod.year => 365,
        RunStatsPeriod.all => null,
      };
}

class RunWeekBucket {
  final DateTime weekStart;
  final int runCount;
  final double distanceMeters;
  final int movingTimeSeconds;

  const RunWeekBucket({
    required this.weekStart,
    required this.runCount,
    required this.distanceMeters,
    required this.movingTimeSeconds,
  });
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

class RunProgressAnalytics {
  final RunStatsPeriod period;
  final List<RunActivity> activities;
  final DateTime now;

  final int runCount;
  final double totalDistanceMeters;
  final int totalMovingTimeSeconds;
  final int totalCalories;
  final double? avgPaceSecPerKm;
  final double? bestPaceSecPerKm;
  final double? bestKmSplitSecPerKm;
  final RunActivity? longestRun;
  final RunActivity? fastestRun;
  final double thisWeekDistanceMeters;
  final double lastWeekDistanceMeters;
  final int thisWeekRunCount;
  final int lastWeekRunCount;
  final double avgRunsPerWeek;
  final List<RunWeekBucket> weeklyBuckets;
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
    required this.avgPaceSecPerKm,
    required this.bestPaceSecPerKm,
    required this.bestKmSplitSecPerKm,
    required this.longestRun,
    required this.fastestRun,
    required this.thisWeekDistanceMeters,
    required this.lastWeekDistanceMeters,
    required this.thisWeekRunCount,
    required this.lastWeekRunCount,
    required this.avgRunsPerWeek,
    required this.weeklyBuckets,
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

  /// Average distance per week across the whole period window.
  double get avgWeeklyDistanceMeters =>
      weeklyBuckets.isEmpty ? 0 : totalDistanceMeters / weeklyBuckets.length;

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

  factory RunProgressAnalytics.fromActivities(
    List<RunActivity> all, {
    required RunStatsPeriod period,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final localNow = DateTime(clock.year, clock.month, clock.day);
    final lookback = period.lookbackDays;
    final cutoff = lookback == null
        ? null
        : localNow.subtract(Duration(days: lookback));

    final completed = all.where((a) => a.status == 'completed').toList();

    final activities = completed.where((a) {
      if (cutoff == null) return true;
      final d = _dateOnly(a.startedAt.toLocal());
      return !d.isBefore(cutoff);
    }).toList()
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));

    var totalDistance = 0.0;
    var totalMoving = 0;
    var totalCalories = 0;
    var paceWeight = 0.0;
    var paceWeightedSum = 0.0;
    double? bestKmSplit;
    RunActivity? longest;
    RunActivity? fastest;

    for (final a in activities) {
      totalDistance += a.distanceMeters;
      totalMoving += a.movingTimeSeconds;
      totalCalories += a.calories ?? 0;

      if (longest == null || a.distanceMeters > longest.distanceMeters) {
        longest = a;
      }

      final split = a.bestSplitPaceSecPerKm;
      if (split != null && split.isFinite && split > 0) {
        if (bestKmSplit == null || split < bestKmSplit) bestKmSplit = split;
      }

      final pace = a.avgPaceSecPerKm;
      if (pace != null &&
          pace.isFinite &&
          pace > 0 &&
          a.distanceMeters >= 1000) {
        paceWeightedSum += pace * a.distanceMeters;
        paceWeight += a.distanceMeters;
        if (fastest == null ||
            pace < (fastest.avgPaceSecPerKm ?? double.infinity)) {
          fastest = a;
        }
      }
    }

    final thisWeekStart = _mondayOf(localNow);
    final lastWeekStart = thisWeekStart.subtract(const Duration(days: 7));
    final nextWeekStart = thisWeekStart.add(const Duration(days: 7));
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

    final weekly = _buildWeeklyBuckets(
      activities: activities,
      period: period,
      localNow: localNow,
    );

    final spanWeeks = weekly.isEmpty ? 1 : weekly.length;
    final avgRunsPerWeek =
        activities.isEmpty ? 0.0 : activities.length / spanWeeks;

    final paceTrend = <RunPacePoint>[
      for (final a in activities)
        if (a.avgPaceSecPerKm != null &&
            a.avgPaceSecPerKm!.isFinite &&
            a.avgPaceSecPerKm! > 0 &&
            a.distanceMeters >= 1000)
          RunPacePoint(
            date: a.startedAt.toLocal(),
            paceSecPerKm: a.avgPaceSecPerKm!,
            distanceMeters: a.distanceMeters,
          ),
    ];

    final previous = (cutoff == null || lookback == null)
        ? RunWindowTotals.empty
        : _windowTotals(
            completed,
            start: cutoff.subtract(Duration(days: lookback)),
            end: cutoff,
          );

    final periodStart = cutoff ??
        (activities.isEmpty
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
      avgPaceSecPerKm: paceWeight > 0 ? paceWeightedSum / paceWeight : null,
      bestPaceSecPerKm: fastest?.avgPaceSecPerKm,
      bestKmSplitSecPerKm: bestKmSplit,
      longestRun: longest,
      fastestRun: fastest,
      thisWeekDistanceMeters: thisWeekDistance,
      lastWeekDistanceMeters: lastWeekDistance,
      thisWeekRunCount: thisWeekRuns,
      lastWeekRunCount: lastWeekRuns,
      avgRunsPerWeek: avgRunsPerWeek,
      weeklyBuckets: weekly,
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
      hasPreviousPeriod: cutoff != null && !previous.isEmpty,
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
    required RunStatsPeriod period,
    required DateTime localNow,
  }) {
    final thisWeekStart = _mondayOf(localNow);
    final weekCount = switch (period) {
      RunStatsPeriod.weeks4 => 4,
      RunStatsPeriod.weeks12 => 12,
      RunStatsPeriod.year => 52,
      RunStatsPeriod.all => () {
          if (activities.isEmpty) return 8;
          final first = _mondayOf(activities.first.startedAt.toLocal());
          final weeks =
              thisWeekStart.difference(first).inDays ~/ 7 + 1;
          return weeks.clamp(4, 52);
        }(),
    };

    final starts = <DateTime>[
      for (var i = weekCount - 1; i >= 0; i--)
        thisWeekStart.subtract(Duration(days: 7 * i)),
    ];

    final counts = List<int>.filled(starts.length, 0);
    final distances = List<double>.filled(starts.length, 0);
    final times = List<int>.filled(starts.length, 0);

    for (final a in activities) {
      final week = _mondayOf(a.startedAt.toLocal());
      final idx = starts.indexWhere((s) => s == week);
      if (idx < 0) continue;
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
}
