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
  final RunActivity? longestRun;
  final RunActivity? fastestRun;
  final double thisWeekDistanceMeters;
  final double lastWeekDistanceMeters;
  final int thisWeekRunCount;
  final int lastWeekRunCount;
  final double avgRunsPerWeek;
  final List<RunWeekBucket> weeklyBuckets;
  final List<RunPacePoint> paceTrend;

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
    required this.longestRun,
    required this.fastestRun,
    required this.thisWeekDistanceMeters,
    required this.lastWeekDistanceMeters,
    required this.thisWeekRunCount,
    required this.lastWeekRunCount,
    required this.avgRunsPerWeek,
    required this.weeklyBuckets,
    required this.paceTrend,
  });

  bool get isEmpty => runCount == 0;

  double get distanceDeltaVsLastWeek =>
      thisWeekDistanceMeters - lastWeekDistanceMeters;

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

    final activities = all.where((a) {
      if (a.status != 'completed') return false;
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
    RunActivity? longest;
    RunActivity? fastest;

    for (final a in activities) {
      totalDistance += a.distanceMeters;
      totalMoving += a.movingTimeSeconds;
      totalCalories += a.calories ?? 0;

      if (longest == null || a.distanceMeters > longest.distanceMeters) {
        longest = a;
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
    var thisWeekDistance = 0.0;
    var lastWeekDistance = 0.0;
    var thisWeekRuns = 0;
    var lastWeekRuns = 0;

    for (final a in all.where((x) => x.status == 'completed')) {
      final d = _dateOnly(a.startedAt.toLocal());
      if (!d.isBefore(thisWeekStart) && d.isBefore(thisWeekStart.add(const Duration(days: 7)))) {
        thisWeekDistance += a.distanceMeters;
        thisWeekRuns++;
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

    return RunProgressAnalytics(
      period: period,
      activities: activities,
      now: clock,
      runCount: activities.length,
      totalDistanceMeters: totalDistance,
      totalMovingTimeSeconds: totalMoving,
      totalCalories: totalCalories,
      avgPaceSecPerKm:
          paceWeight > 0 ? paceWeightedSum / paceWeight : null,
      bestPaceSecPerKm: fastest?.avgPaceSecPerKm,
      longestRun: longest,
      fastestRun: fastest,
      thisWeekDistanceMeters: thisWeekDistance,
      lastWeekDistanceMeters: lastWeekDistance,
      thisWeekRunCount: thisWeekRuns,
      lastWeekRunCount: lastWeekRuns,
      avgRunsPerWeek: avgRunsPerWeek,
      weeklyBuckets: weekly,
      paceTrend: paceTrend,
    );
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime _mondayOf(DateTime d) {
    final day = _dateOnly(d);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
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
