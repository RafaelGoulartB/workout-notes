import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/utils/date_utils.dart';
import 'package:workout_notes/utils/run_analytics_dates.dart';
import 'package:workout_notes/utils/run_fitness_analytics.dart';

/// Training load: session load with its acute:chronic ratio, time per pace
/// zone, and the weekly effort/feeling trend.
abstract final class RunTrainingLoadAnalytics {
  /// RPE assumed when a run has none: from how hard the pace is against the
  /// runner's pace zones, or a moderate 5 without a fitness estimate.
  static double fallbackRpe(RunActivity a, RunZoneBounds? zones) {
    final pace = a.avgPaceSecPerKm;
    if (zones == null || pace == null || !pace.isFinite || pace <= 0) return 5;
    return switch (zones.zoneFor(pace)) {
      RunZone.z1 => 3,
      RunZone.z2 => 4,
      RunZone.z3 => 6,
      RunZone.z4 => 8,
      RunZone.z5 => 9,
    };
  }

  /// Session load: moving minutes x RPE (10-point scale).
  static double sessionLoad(RunActivity a, RunZoneBounds? zones) {
    final seconds = a.movingTimeSeconds > 0
        ? a.movingTimeSeconds
        : a.durationSeconds;
    if (seconds <= 0) return 0;
    final rpe = (a.rpe != null && a.rpe! > 0)
        ? a.rpe!.clamp(1.0, 10.0)
        : fallbackRpe(a, zones);
    return seconds / 60.0 * rpe;
  }

  /// Daily load with acute (7-day) and chronic (28-day) rolling averages for
  /// the last [days] days, plus the acute:chronic ratio for today.
  static RunTrainingLoad trainingLoad(
    List<RunActivity> activities, {
    DateTime? now,
    int days = 84,
    RunZoneBounds? zones,
  }) {
    final today = dayOf(now ?? DateTime.now());
    final runs = activities.where(RunAnalyticsDates.completedRun).toList();
    final loadByDay = <DateTime, double>{};
    final distanceByDay = <DateTime, double>{};
    for (final a in runs) {
      final d = dayOf(a.startedAt.toLocal());
      loadByDay[d] = (loadByDay[d] ?? 0) + sessionLoad(a, zones);
      distanceByDay[d] = (distanceByDay[d] ?? 0) + a.distanceMeters;
    }

    double sumBack(Map<DateTime, double> map, DateTime end, int length) {
      var total = 0.0;
      for (var i = 0; i < length; i++) {
        total += map[addDays(end, -i)] ?? 0;
      }
      return total;
    }

    final series = <RunLoadDay>[
      for (var i = days - 1; i >= 0; i--)
        () {
          final d = addDays(today, -i);
          return RunLoadDay(
            date: d,
            load: loadByDay[d] ?? 0,
            acute: sumBack(loadByDay, d, 7) / 7,
            chronic: sumBack(loadByDay, d, 28) / 28,
          );
        }(),
    ];

    var activeDays = 0;
    for (var i = 0; i < 28; i++) {
      if ((loadByDay[addDays(today, -i)] ?? 0) > 0) {
        activeDays++;
      }
    }
    final last = series.last;
    final acwr = activeDays >= 3 && last.chronic > 0
        ? last.acute / last.chronic
        : null;

    final last7 = sumBack(distanceByDay, today, 7);
    final prev7 = sumBack(distanceByDay, addDays(today, -7), 7);
    return RunTrainingLoad(
      days: series,
      acwr: acwr,
      status: RunLoadStatus.fromAcwr(acwr),
      weeklyLoad: sumBack(loadByDay, today, 7),
      last7DaysMeters: last7,
      previous7DaysMeters: prev7,
    );
  }

  // ===================== INTENSITY =====================

  /// Time per pace zone for each of the last [weeks] calendar weeks (oldest
  /// first). Per-km [splits] give a faithful mix inside a run; runs without
  /// splits (treadmill, older imports) count entirely at their average pace.
  static RunIntensityDistribution intensityDistribution(
    List<RunActivity> activities, {
    required RunZoneBounds zones,
    Map<String, List<RunSplitSample>> splits = const {},
    int weeks = 12,
    DateTime? now,
  }) {
    final thisWeek = mondayOf(now ?? DateTime.now());
    final starts = [
      for (var i = weeks - 1; i >= 0; i--) addDays(thisWeek, -(7 * i)),
    ];
    final index = {for (var i = 0; i < starts.length; i++) starts[i]: i};
    final seconds = List.generate(weeks, (_) => List<double>.filled(5, 0));

    for (final a in activities.where(RunAnalyticsDates.completedRun)) {
      final w = index[mondayOf(a.startedAt.toLocal())];
      if (w == null) continue;
      final runSplits = splits[a.id];
      var counted = false;
      if (runSplits != null && runSplits.isNotEmpty) {
        for (final s in runSplits) {
          final pace = s.paceSecPerKm;
          if (pace == null ||
              !pace.isFinite ||
              pace <= 0 ||
              s.durationSeconds <= 0) {
            continue;
          }
          seconds[w][zones.zoneFor(pace).index] += s.durationSeconds;
          counted = true;
        }
      }
      if (counted) continue;
      final pace = a.avgPaceSecPerKm;
      final time = a.movingTimeSeconds > 0
          ? a.movingTimeSeconds
          : a.durationSeconds;
      if (pace == null || !pace.isFinite || pace <= 0 || time <= 0) continue;
      seconds[w][zones.zoneFor(pace).index] += time;
    }

    return RunIntensityDistribution([
      for (var i = 0; i < starts.length; i++)
        RunWeekZones(weekStart: starts[i], secondsPerZone: seconds[i]),
    ]);
  }

  /// Average RPE and feeling per week for the last [weeks] weeks (oldest
  /// first). Weeks with no rated run carry nulls.
  static List<RunWeeklyEffort> weeklyEffort(
    List<RunActivity> activities, {
    int weeks = 12,
    DateTime? now,
  }) {
    final thisWeek = mondayOf(now ?? DateTime.now());
    final starts = [
      for (var i = weeks - 1; i >= 0; i--) addDays(thisWeek, -(7 * i)),
    ];
    final index = {for (var i = 0; i < starts.length; i++) starts[i]: i};
    final rpeSum = List<double>.filled(weeks, 0);
    final rpeCount = List<int>.filled(weeks, 0);
    final feelSum = List<double>.filled(weeks, 0);
    final feelCount = List<int>.filled(weeks, 0);
    for (final a in activities.where(RunAnalyticsDates.completedRun)) {
      final i = index[mondayOf(a.startedAt.toLocal())];
      if (i == null) continue;
      if (a.rpe != null && a.rpe! > 0) {
        rpeSum[i] += a.rpe!;
        rpeCount[i]++;
      }
      if (a.feelingRating != null && a.feelingRating! > 0) {
        feelSum[i] += a.feelingRating!;
        feelCount[i]++;
      }
    }
    return [
      for (var i = 0; i < weeks; i++)
        RunWeeklyEffort(
          weekStart: starts[i],
          avgRpe: rpeCount[i] == 0 ? null : rpeSum[i] / rpeCount[i],
          avgFeeling: feelCount[i] == 0 ? null : feelSum[i] / feelCount[i],
        ),
    ];
  }
}

/// One kilometre (or partial kilometre) of a run.
class RunSplitSample {
  final int durationSeconds;
  final double? paceSecPerKm;

  const RunSplitSample({
    required this.durationSeconds,
    required this.paceSecPerKm,
  });
}

class RunWeekZones {
  final DateTime weekStart;
  final List<double> secondsPerZone;

  const RunWeekZones({required this.weekStart, required this.secondsPerZone});

  double get totalSeconds => secondsPerZone.fold(0.0, (a, b) => a + b);
}

class RunIntensityDistribution {
  final List<RunWeekZones> weeks;

  const RunIntensityDistribution(this.weeks);

  List<double> get totalsPerZone {
    final totals = List<double>.filled(5, 0);
    for (final week in weeks) {
      for (var i = 0; i < 5; i++) {
        totals[i] += week.secondsPerZone[i];
      }
    }
    return totals;
  }

  double get totalSeconds => totalsPerZone.fold(0.0, (a, b) => a + b);

  bool get hasData => totalSeconds > 0;

  double _share(Iterable<int> zones) {
    final total = totalSeconds;
    if (total <= 0) return 0;
    final t = totalsPerZone;
    return zones.fold(0.0, (sum, i) => sum + t[i]) / total;
  }

  /// Z1 + Z2: conversational, truly easy running.
  double get easyShare => _share(const [0, 1]);

  /// Z3, the grey zone between easy and threshold.
  double get moderateShare => _share(const [2]);

  /// Z4 + Z5: threshold pace and faster.
  double get hardShare => _share(const [3, 4]);

  /// The classic 80/20 guideline: at least ~80% of time easy.
  bool get isPolarized => hasData && easyShare >= 0.75;
}

class RunLoadDay {
  final DateTime date;
  final double load;

  /// Average daily load over the last 7 days.
  final double acute;

  /// Average daily load over the last 28 days.
  final double chronic;

  const RunLoadDay({
    required this.date,
    required this.load,
    required this.acute,
    required this.chronic,
  });
}

enum RunLoadStatus {
  insufficientData,
  detraining,
  balanced,
  rapidIncrease;

  /// Acute:chronic ratio bands: below 0.8 you are losing fitness, 0.8-1.3 is
  /// the sweet spot, above 1.3 load is climbing faster than the body adapts.
  static RunLoadStatus fromAcwr(double? acwr) {
    if (acwr == null || !acwr.isFinite) return RunLoadStatus.insufficientData;
    if (acwr < 0.8) return RunLoadStatus.detraining;
    if (acwr <= 1.3) return RunLoadStatus.balanced;
    return RunLoadStatus.rapidIncrease;
  }
}

class RunTrainingLoad {
  final List<RunLoadDay> days;
  final double? acwr;
  final RunLoadStatus status;

  /// Sum of session loads over the last 7 days.
  final double weeklyLoad;
  final double last7DaysMeters;
  final double previous7DaysMeters;

  const RunTrainingLoad({
    required this.days,
    required this.acwr,
    required this.status,
    required this.weeklyLoad,
    required this.last7DaysMeters,
    required this.previous7DaysMeters,
  });

  /// Smallest previous week that makes a percentage growth meaningful.
  static const double minComparableMeters = 3000;

  /// Last 7 days against the 7 before, as a fraction (0.12 = +12%).
  double? get weeklyVolumeGrowth => previous7DaysMeters < minComparableMeters
      ? null
      : last7DaysMeters / previous7DaysMeters - 1;

  /// More than 10% weekly growth: the usual limit for a safe build-up.
  bool get volumeGrowthWarning => (weeklyVolumeGrowth ?? 0) > 0.10;
}

class RunWeeklyEffort {
  final DateTime weekStart;
  final double? avgRpe;
  final double? avgFeeling;

  const RunWeeklyEffort({
    required this.weekStart,
    required this.avgRpe,
    required this.avgFeeling,
  });
}
