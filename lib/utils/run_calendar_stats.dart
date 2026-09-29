import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/utils/run_analytics_dates.dart';
import 'package:workout_notes/utils/date_utils.dart';

/// Calendar statistics: daily distance for the heatmap, monthly totals,
/// consistency streaks, elevation and the year in review.
abstract final class RunCalendarStats {
  /// Distance per local calendar day.
  static Map<DateTime, double> dailyDistance(
    List<RunActivity> activities, {
    int? year,
  }) {
    final map = <DateTime, double>{};
    for (final a in activities.where(RunAnalyticsDates.completedRun)) {
      final d = dayOf(a.startedAt.toLocal());
      if (year != null && d.year != year) continue;
      map[d] = (map[d] ?? 0) + a.distanceMeters;
    }
    return map;
  }

  /// Totals for each of the last [months] calendar months, oldest first.
  static List<RunMonthTotal> monthlyTotals(
    List<RunActivity> activities, {
    int months = 12,
    DateTime? now,
  }) {
    final today = dayOf(now ?? DateTime.now());
    final starts = [
      for (var i = months - 1; i >= 0; i--)
        DateTime(today.year, today.month - i),
    ];
    final index = {for (var i = 0; i < starts.length; i++) starts[i]: i};
    final distance = List<double>.filled(months, 0);
    final runs = List<int>.filled(months, 0);
    final time = List<int>.filled(months, 0);
    for (final a in activities.where(RunAnalyticsDates.completedRun)) {
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
    final today = dayOf(now ?? DateTime.now());
    final perMonth = List<double>.filled(12, 0);
    for (final a in activities.where(RunAnalyticsDates.completedRun)) {
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
      for (final a in activities.where(RunAnalyticsDates.completedRun))
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
    final today = dayOf(now ?? DateTime.now());
    final runs = activities.where(RunAnalyticsDates.completedRun).toList();
    final days = <DateTime>{
      for (final a in runs) dayOf(a.startedAt.toLocal()),
    };
    final weeks = <DateTime>{
      for (final a in runs) mondayOf(a.startedAt.toLocal()),
    };
    final thisWeek = mondayOf(today);

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

  // ===================== ELEVATION =====================

  static RunElevationSummary elevation(List<RunActivity> activities) {
    var total = 0.0;
    var withData = 0;
    RunActivity? highest;
    for (final a in activities.where(RunAnalyticsDates.completedRun)) {
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
        .where(RunAnalyticsDates.completedRun)
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
