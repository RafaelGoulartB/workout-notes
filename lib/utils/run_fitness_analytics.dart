import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/services/run_pace_calculator.dart';

/// Pure calculations behind the running insights screen: fitness estimate,
/// race predictions, training load, intensity distribution, calendar heatmap,
/// consistency and the year in review.
///
/// Everything here works on already-loaded [RunActivity] lists so it can be
/// unit-tested without a database. Fitness numbers are estimates (Daniels'
/// VDOT model) and are never more precise than the effort data feeding them.
abstract final class RunFitnessAnalytics {
  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime _monday(DateTime d) {
    final day = _day(d);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  static bool _completedRun(RunActivity a) => a.isCompleted && a.isRunning;

  // ===================== FITNESS (VDOT) =====================

  /// Fixed race distances for the predictor table.
  static const List<double> raceDistances = [
    RunPaceCalculator.fiveKMeters,
    RunPaceCalculator.tenKMeters,
    RunPaceCalculator.halfMeters,
    RunPaceCalculator.marathonMeters,
  ];

  /// Best-effort samples usable for a VDOT estimate. 1 km is left out: the
  /// model overrates sub-4-minute efforts.
  static List<RunEffortSample> effortsOf(RunActivity a) {
    if (!a.isRun) return const [];
    final date = a.startedAt.toLocal();
    RunEffortSample? sample(double meters, int? seconds) =>
        seconds == null || seconds <= 0
        ? null
        : RunEffortSample(
            activityId: a.id,
            date: date,
            distanceMeters: meters,
            timeSeconds: seconds,
          );
    return [
      ?sample(3000, a.bestEffort3kSec),
      ?sample(RunPaceCalculator.fiveKMeters, a.bestEffort5kSec),
      ?sample(RunPaceCalculator.tenKMeters, a.bestEffort10kSec),
      ?sample(RunPaceCalculator.halfMeters, a.bestEffortHalfSec),
      ?sample(RunPaceCalculator.marathonMeters, a.bestEffortMarathonSec),
    ];
  }

  /// Whole-run sample for activities with no usable best effort. A training
  /// run is rarely a maximal effort, so this only ever underestimates.
  static RunEffortSample? trainingRunSample(RunActivity a) {
    if (!a.isRun) return null;
    final seconds = a.movingTimeSeconds > 0
        ? a.movingTimeSeconds
        : a.durationSeconds;
    if (a.distanceMeters < 3000 || seconds <= 0) return null;
    if (!RunPaceCalculator.isPlausibleRace(
      distanceMeters: a.distanceMeters,
      timeSeconds: seconds,
    )) {
      return null;
    }
    return RunEffortSample(
      activityId: a.id,
      date: a.startedAt.toLocal(),
      distanceMeters: a.distanceMeters,
      timeSeconds: seconds,
    );
  }

  static double vdotOf(RunEffortSample sample) => RunPaceCalculator.vdotFor(
    distanceMeters: sample.distanceMeters,
    timeSeconds: sample.timeSeconds,
  );

  /// Current fitness from the best recent effort. Looks at the last
  /// [windowDays] days first, then the last year (flagged [RunFitnessEstimate.isStale]),
  /// and only falls back to plain training runs when no effort exists.
  static RunFitnessEstimate? estimate(
    List<RunActivity> activities, {
    DateTime? now,
    int windowDays = 90,
  }) {
    final today = _day(now ?? DateTime.now());
    final runs = activities.where(_completedRun).toList();

    RunEffortSample? best(Iterable<RunEffortSample> samples, int days) {
      final from = today.subtract(Duration(days: days));
      RunEffortSample? top;
      var topVdot = 0.0;
      for (final s in samples) {
        if (_day(s.date).isBefore(from) || _day(s.date).isAfter(today)) {
          continue;
        }
        final v = vdotOf(s);
        if (v > topVdot) {
          topVdot = v;
          top = s;
        }
      }
      return top;
    }

    final efforts = [for (final a in runs) ...effortsOf(a)];
    var source = best(efforts, windowDays);
    var stale = false;
    var fromTraining = false;
    if (source == null) {
      source = best(efforts, 365);
      stale = source != null;
    }
    if (source == null) {
      final training = <RunEffortSample>[
        for (final a in runs) ?trainingRunSample(a),
      ];
      source = best(training, windowDays);
      fromTraining = source != null;
    }
    if (source == null) return null;
    final vdot = vdotOf(source);
    if (!vdot.isFinite || vdot < 15 || vdot > 90) return null;
    return RunFitnessEstimate(
      vdot: vdot,
      source: source,
      isStale: stale,
      fromTrainingRuns: fromTraining,
      paces: RunPaceCalculator.fromVdot(vdot),
      predictions: predictRaces(vdot),
    );
  }

  static List<RunRacePrediction> predictRaces(double vdot) => [
    for (final meters in raceDistances)
      () {
        final pace = RunPaceCalculator.racePaceFor(vdot, meters);
        return RunRacePrediction(
          distanceMeters: meters,
          paceSecPerKm: pace,
          timeSeconds: (pace * meters / 1000).round(),
        );
      }(),
  ];

  /// Best VDOT per calendar month over the last [months] months, oldest
  /// first. Months without data are skipped. Uses best efforts; when the
  /// range has none at all it falls back to whole training runs.
  static List<RunVdotPoint> vdotByMonth(
    List<RunActivity> activities, {
    int months = 12,
    DateTime? now,
  }) {
    final today = _day(now ?? DateTime.now());
    final firstMonth = DateTime(today.year, today.month - (months - 1));
    final runs = activities.where(_completedRun).where((a) {
      final d = a.startedAt.toLocal();
      return !d.isBefore(firstMonth) && !_day(d).isAfter(today);
    }).toList();

    var samples = [for (final a in runs) ...effortsOf(a)];
    if (samples.isEmpty) {
      samples = [for (final a in runs) ?trainingRunSample(a)];
    }
    final byMonth = <DateTime, double>{};
    for (final s in samples) {
      final key = DateTime(s.date.year, s.date.month);
      final v = vdotOf(s);
      if (!v.isFinite || v < 15 || v > 90) continue;
      if (v > (byMonth[key] ?? 0)) byMonth[key] = v;
    }
    final keys = byMonth.keys.toList()..sort();
    return [for (final k in keys) RunVdotPoint(month: k, vdot: byMonth[k]!)];
  }

  // ===================== TRAINING LOAD =====================

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
    final today = _day(now ?? DateTime.now());
    final runs = activities.where(_completedRun).toList();
    final loadByDay = <DateTime, double>{};
    final distanceByDay = <DateTime, double>{};
    for (final a in runs) {
      final d = _day(a.startedAt.toLocal());
      loadByDay[d] = (loadByDay[d] ?? 0) + sessionLoad(a, zones);
      distanceByDay[d] = (distanceByDay[d] ?? 0) + a.distanceMeters;
    }

    double sumBack(Map<DateTime, double> map, DateTime end, int length) {
      var total = 0.0;
      for (var i = 0; i < length; i++) {
        total += map[end.subtract(Duration(days: i))] ?? 0;
      }
      return total;
    }

    final series = <RunLoadDay>[
      for (var i = days - 1; i >= 0; i--)
        () {
          final d = today.subtract(Duration(days: i));
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
      if ((loadByDay[today.subtract(Duration(days: i))] ?? 0) > 0) {
        activeDays++;
      }
    }
    final last = series.last;
    final acwr = activeDays >= 3 && last.chronic > 0
        ? last.acute / last.chronic
        : null;

    final last7 = sumBack(distanceByDay, today, 7);
    final prev7 = sumBack(
      distanceByDay,
      today.subtract(const Duration(days: 7)),
      7,
    );
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
    final thisWeek = _monday(now ?? DateTime.now());
    final starts = [
      for (var i = weeks - 1; i >= 0; i--)
        thisWeek.subtract(Duration(days: 7 * i)),
    ];
    final index = {for (var i = 0; i < starts.length; i++) starts[i]: i};
    final seconds = List.generate(weeks, (_) => List<double>.filled(5, 0));

    for (final a in activities.where(_completedRun)) {
      final w = index[_monday(a.startedAt.toLocal())];
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

  // ===================== CALENDAR / VOLUME =====================

  /// Distance per local calendar day.
  static Map<DateTime, double> dailyDistance(
    List<RunActivity> activities, {
    int? year,
  }) {
    final map = <DateTime, double>{};
    for (final a in activities.where(_completedRun)) {
      final d = _day(a.startedAt.toLocal());
      if (year != null && d.year != year) continue;
      map[d] = (map[d] ?? 0) + a.distanceMeters;
    }
    return map;
  }

  /// Heatmap intensity 0..4 for [meters], relative to the runner's own days
  /// (quartiles of the days that had a run).
  static List<double> heatThresholds(Iterable<double> positiveDays) {
    final sorted = positiveDays.where((v) => v > 0).toList()..sort();
    if (sorted.isEmpty) return const [0, 0, 0];
    double q(double f) => sorted[((sorted.length - 1) * f).round()];
    return [q(0.25), q(0.5), q(0.75)];
  }

  static int heatLevel(double meters, List<double> thresholds) {
    if (meters <= 0) return 0;
    if (meters <= thresholds[0]) return 1;
    if (meters <= thresholds[1]) return 2;
    if (meters <= thresholds[2]) return 3;
    return 4;
  }

  /// Totals for each of the last [months] calendar months, oldest first.
  static List<RunMonthTotal> monthlyTotals(
    List<RunActivity> activities, {
    int months = 12,
    DateTime? now,
  }) {
    final today = _day(now ?? DateTime.now());
    final starts = [
      for (var i = months - 1; i >= 0; i--)
        DateTime(today.year, today.month - i),
    ];
    final index = {for (var i = 0; i < starts.length; i++) starts[i]: i};
    final distance = List<double>.filled(months, 0);
    final runs = List<int>.filled(months, 0);
    final time = List<int>.filled(months, 0);
    for (final a in activities.where(_completedRun)) {
      final d = a.startedAt.toLocal();
      final i = index[DateTime(d.year, d.month)];
      if (i == null) continue;
      distance[i] += a.distanceMeters;
      runs[i]++;
      time[i] += a.movingTimeSeconds;
    }
    return [
      for (var i = 0; i < months; i++)
        RunMonthTotal(
          month: starts[i],
          distanceMeters: distance[i],
          runCount: runs[i],
          movingTimeSeconds: time[i],
        ),
    ];
  }

  /// Running total (meters) at the end of each month of [year]. Months after
  /// [now] in the current year are null so the line stops today.
  static List<double?> cumulativeMonthly(
    List<RunActivity> activities,
    int year, {
    DateTime? now,
  }) {
    final today = _day(now ?? DateTime.now());
    final perMonth = List<double>.filled(12, 0);
    for (final a in activities.where(_completedRun)) {
      final d = a.startedAt.toLocal();
      if (d.year != year) continue;
      perMonth[d.month - 1] += a.distanceMeters;
    }
    var running = 0.0;
    return [
      for (var m = 0; m < 12; m++)
        () {
          running += perMonth[m];
          if (year > today.year ||
              (year == today.year && m + 1 > today.month)) {
            return null;
          }
          return running;
        }(),
    ];
  }

  /// Years that have at least one run, newest first. Always contains the
  /// current year so the selector is never empty.
  static List<int> availableYears(
    List<RunActivity> activities, {
    DateTime? now,
  }) {
    final years = <int>{
      (now ?? DateTime.now()).year,
      for (final a in activities.where(_completedRun))
        a.startedAt.toLocal().year,
    };
    return years.toList()..sort((a, b) => b.compareTo(a));
  }

  // ===================== CONSISTENCY =====================

  static RunConsistency consistency(
    List<RunActivity> activities, {
    DateTime? now,
    int windowWeeks = 12,
  }) {
    final today = _day(now ?? DateTime.now());
    final runs = activities.where(_completedRun).toList();
    final days = <DateTime>{for (final a in runs) _day(a.startedAt.toLocal())};
    final weeks = <DateTime>{
      for (final a in runs) _monday(a.startedAt.toLocal()),
    };
    final thisWeek = _monday(today);

    // Day streaks: a day without a run yet today does not break the streak.
    var currentDays = 0;
    var cursor = days.contains(today)
        ? today
        : today.subtract(const Duration(days: 1));
    while (days.contains(cursor)) {
      currentDays++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    var longestDays = 0;
    final sortedDays = days.toList()..sort();
    var run = 0;
    DateTime? prev;
    for (final d in sortedDays) {
      run = prev != null && d.difference(prev).inDays == 1 ? run + 1 : 1;
      if (run > longestDays) longestDays = run;
      prev = d;
    }

    var currentWeeks = 0;
    var weekCursor = weeks.contains(thisWeek)
        ? thisWeek
        : thisWeek.subtract(const Duration(days: 7));
    while (weeks.contains(weekCursor)) {
      currentWeeks++;
      weekCursor = weekCursor.subtract(const Duration(days: 7));
    }
    var longestWeeks = 0;
    final sortedWeeks = weeks.toList()..sort();
    run = 0;
    prev = null;
    for (final w in sortedWeeks) {
      run = prev != null && w.difference(prev).inDays == 7 ? run + 1 : 1;
      if (run > longestWeeks) longestWeeks = run;
      prev = w;
    }

    // Share of recent weeks with a run, never counting weeks before the
    // first run ever recorded.
    var considered = windowWeeks;
    if (sortedWeeks.isNotEmpty) {
      final sinceFirst = thisWeek.difference(sortedWeeks.first).inDays ~/ 7 + 1;
      if (sinceFirst < considered) considered = sinceFirst;
    }
    var withRuns = 0;
    for (var i = 0; i < considered; i++) {
      if (weeks.contains(thisWeek.subtract(Duration(days: 7 * i)))) withRuns++;
    }
    return RunConsistency(
      currentDayStreak: currentDays,
      longestDayStreak: longestDays,
      currentWeekStreak: currentWeeks,
      longestWeekStreak: longestWeeks,
      weeksConsidered: sortedWeeks.isEmpty ? 0 : considered,
      weeksWithRuns: withRuns,
    );
  }

  // ===================== EFFORT / FEELING =====================

  /// Average RPE and feeling per week for the last [weeks] weeks (oldest
  /// first). Weeks with no rated run carry nulls.
  static List<RunWeeklyEffort> weeklyEffort(
    List<RunActivity> activities, {
    int weeks = 12,
    DateTime? now,
  }) {
    final thisWeek = _monday(now ?? DateTime.now());
    final starts = [
      for (var i = weeks - 1; i >= 0; i--)
        thisWeek.subtract(Duration(days: 7 * i)),
    ];
    final index = {for (var i = 0; i < starts.length; i++) starts[i]: i};
    final rpeSum = List<double>.filled(weeks, 0);
    final rpeCount = List<int>.filled(weeks, 0);
    final feelSum = List<double>.filled(weeks, 0);
    final feelCount = List<int>.filled(weeks, 0);
    for (final a in activities.where(_completedRun)) {
      final i = index[_monday(a.startedAt.toLocal())];
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

  // ===================== ELEVATION =====================

  static RunElevationSummary elevation(List<RunActivity> activities) {
    var total = 0.0;
    var withData = 0;
    RunActivity? highest;
    for (final a in activities.where(_completedRun)) {
      final gain = a.elevationGainMeters;
      if (gain == null || !gain.isFinite || gain <= 0) continue;
      total += gain;
      withData++;
      if (highest == null || gain > highest.elevationGainMeters!) highest = a;
    }
    return RunElevationSummary(
      totalGainMeters: total,
      runsWithData: withData,
      highest: highest,
    );
  }

  // ===================== YEAR IN REVIEW =====================

  static RunYearReview yearReview(List<RunActivity> activities, int year) {
    final runs = activities
        .where(_completedRun)
        .where((a) => a.startedAt.toLocal().year == year)
        .toList();
    var distance = 0.0;
    var seconds = 0;
    RunActivity? longest;
    RunActivity? fastest5k;
    final monthDistance = List<double>.filled(12, 0);
    final weekdayCount = List<int>.filled(7, 0);
    final dayPartCount = <RunDayPart, int>{};
    for (final a in runs) {
      final start = a.startedAt.toLocal();
      distance += a.distanceMeters;
      seconds += a.movingTimeSeconds;
      monthDistance[start.month - 1] += a.distanceMeters;
      weekdayCount[start.weekday - 1]++;
      final part = RunDayPart.forHour(start.hour);
      dayPartCount[part] = (dayPartCount[part] ?? 0) + 1;
      if (longest == null || a.distanceMeters > longest.distanceMeters) {
        longest = a;
      }
      final t = a.isRun ? a.bestEffort5kSec : null;
      if (t != null && t > 0) {
        if (fastest5k == null || t < fastest5k.bestEffort5kSec!) fastest5k = a;
      }
    }

    int? bestMonth;
    var bestMonthDistance = 0.0;
    for (var m = 0; m < 12; m++) {
      if (monthDistance[m] > bestMonthDistance) {
        bestMonthDistance = monthDistance[m];
        bestMonth = m + 1;
      }
    }
    int? weekday;
    var weekdayBest = 0;
    for (var i = 0; i < 7; i++) {
      if (weekdayCount[i] > weekdayBest) {
        weekdayBest = weekdayCount[i];
        weekday = i + 1;
      }
    }
    RunDayPart? dayPart;
    var dayPartBest = 0;
    for (final part in RunDayPart.values) {
      final count = dayPartCount[part] ?? 0;
      if (count > dayPartBest) {
        dayPartBest = count;
        dayPart = part;
      }
    }
    return RunYearReview(
      year: year,
      runCount: runs.length,
      totalDistanceMeters: distance,
      totalMovingSeconds: seconds,
      longestRun: longest,
      fastest5kRun: fastest5k,
      mostActiveMonth: bestMonth,
      mostActiveMonthMeters: bestMonthDistance,
      favoriteWeekday: weekday,
      favoriteDayPart: dayPart,
      elevation: elevation(runs),
    );
  }
}

/// A distance/time pair that can be turned into a VDOT.
class RunEffortSample {
  final String activityId;
  final DateTime date;
  final double distanceMeters;
  final int timeSeconds;

  const RunEffortSample({
    required this.activityId,
    required this.date,
    required this.distanceMeters,
    required this.timeSeconds,
  });
}

class RunFitnessEstimate {
  final double vdot;

  /// The effort the estimate comes from.
  final RunEffortSample source;

  /// Best effort is older than the recent window (up to a year old).
  final bool isStale;

  /// No best effort was available; estimated from an ordinary training run,
  /// so the real fitness is likely higher.
  final bool fromTrainingRuns;
  final RunPaces paces;
  final List<RunRacePrediction> predictions;

  const RunFitnessEstimate({
    required this.vdot,
    required this.source,
    required this.isStale,
    required this.fromTrainingRuns,
    required this.paces,
    required this.predictions,
  });

  RunZoneBounds get zones => RunZoneBounds.fromPaces(paces);
}

class RunVdotPoint {
  final DateTime month;
  final double vdot;

  const RunVdotPoint({required this.month, required this.vdot});
}

class RunRacePrediction {
  final double distanceMeters;
  final int timeSeconds;
  final double paceSecPerKm;

  const RunRacePrediction({
    required this.distanceMeters,
    required this.timeSeconds,
    required this.paceSecPerKm,
  });
}

/// Pace zones from a fitness index. Boundaries are slower-than pace limits:
/// easy pace (~66% VO2max), marathon pace, threshold (T) and interval (I).
enum RunZone { z1, z2, z3, z4, z5 }

class RunZoneBounds {
  final double easySecPerKm;
  final double marathonSecPerKm;
  final double tempoSecPerKm;
  final double intervalSecPerKm;

  const RunZoneBounds({
    required this.easySecPerKm,
    required this.marathonSecPerKm,
    required this.tempoSecPerKm,
    required this.intervalSecPerKm,
  });

  factory RunZoneBounds.fromPaces(RunPaces paces) => RunZoneBounds(
    easySecPerKm: paces.easySecPerKm,
    marathonSecPerKm: paces.marathonSecPerKm,
    tempoSecPerKm: paces.tempoSecPerKm,
    intervalSecPerKm: paces.intervalSecPerKm,
  );

  RunZone zoneFor(double paceSecPerKm) {
    if (paceSecPerKm >= easySecPerKm) return RunZone.z1;
    if (paceSecPerKm >= marathonSecPerKm) return RunZone.z2;
    if (paceSecPerKm >= tempoSecPerKm) return RunZone.z3;
    if (paceSecPerKm >= intervalSecPerKm) return RunZone.z4;
    return RunZone.z5;
  }

  /// Slowest and fastest pace of [zone] in sec/km; the open ends are null.
  (double? slowest, double? fastest) rangeOf(RunZone zone) => switch (zone) {
    RunZone.z1 => (null, easySecPerKm),
    RunZone.z2 => (easySecPerKm, marathonSecPerKm),
    RunZone.z3 => (marathonSecPerKm, tempoSecPerKm),
    RunZone.z4 => (tempoSecPerKm, intervalSecPerKm),
    RunZone.z5 => (intervalSecPerKm, null),
  };
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

class RunMonthTotal {
  final DateTime month;
  final double distanceMeters;
  final int runCount;
  final int movingTimeSeconds;

  const RunMonthTotal({
    required this.month,
    required this.distanceMeters,
    required this.runCount,
    required this.movingTimeSeconds,
  });
}

class RunConsistency {
  final int currentDayStreak;
  final int longestDayStreak;
  final int currentWeekStreak;
  final int longestWeekStreak;
  final int weeksConsidered;
  final int weeksWithRuns;

  const RunConsistency({
    required this.currentDayStreak,
    required this.longestDayStreak,
    required this.currentWeekStreak,
    required this.longestWeekStreak,
    required this.weeksConsidered,
    required this.weeksWithRuns,
  });

  /// 0..1 share of recent weeks with at least one run.
  double get weeksWithRunsShare =>
      weeksConsidered == 0 ? 0 : weeksWithRuns / weeksConsidered;
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

class RunElevationSummary {
  final double totalGainMeters;
  final int runsWithData;
  final RunActivity? highest;

  const RunElevationSummary({
    required this.totalGainMeters,
    required this.runsWithData,
    required this.highest,
  });

  bool get hasData => runsWithData > 0;

  double? get avgGainPerRunMeters =>
      runsWithData == 0 ? null : totalGainMeters / runsWithData;
}

enum RunDayPart {
  morning,
  afternoon,
  evening,
  night;

  static RunDayPart forHour(int hour) {
    if (hour >= 5 && hour < 12) return RunDayPart.morning;
    if (hour >= 12 && hour < 18) return RunDayPart.afternoon;
    if (hour >= 18 && hour < 22) return RunDayPart.evening;
    return RunDayPart.night;
  }
}

class RunYearReview {
  final int year;
  final int runCount;
  final double totalDistanceMeters;
  final int totalMovingSeconds;
  final RunActivity? longestRun;
  final RunActivity? fastest5kRun;

  /// 1-12, null when the year has no runs.
  final int? mostActiveMonth;
  final double mostActiveMonthMeters;

  /// ISO weekday 1-7.
  final int? favoriteWeekday;
  final RunDayPart? favoriteDayPart;
  final RunElevationSummary elevation;

  const RunYearReview({
    required this.year,
    required this.runCount,
    required this.totalDistanceMeters,
    required this.totalMovingSeconds,
    required this.longestRun,
    required this.fastest5kRun,
    required this.mostActiveMonth,
    required this.mostActiveMonthMeters,
    required this.favoriteWeekday,
    required this.favoriteDayPart,
    required this.elevation,
  });

  bool get isEmpty => runCount == 0;
}
