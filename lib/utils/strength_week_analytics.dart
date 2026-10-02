import 'package:workout_notes/models/strength_workout_summary.dart';
import 'package:workout_notes/utils/date_utils.dart';
import 'package:workout_notes/utils/run_progress_analytics.dart';

/// One bar of the gym trend charts: a calendar week, or a calendar month when
/// the selected range is too long to draw week by week.
class StrengthTrendBucket {
  final DateTime start;
  final int spanDays;
  final int sessions;
  final double volumeKg;
  final int workingSets;
  final int durationSeconds;

  const StrengthTrendBucket({
    required this.start,
    required this.spanDays,
    required this.sessions,
    required this.volumeKg,
    required this.workingSets,
    required this.durationSeconds,
  });

  bool get isMonthly => spanDays > 7;

  /// Average session length in seconds; 0 without sessions.
  double get avgDurationSeconds =>
      sessions == 0 ? 0 : durationSeconds / sessions;
}

/// One day of the current week for the weekday strip.
class StrengthDayBucket {
  final DateTime date;
  final int sessions;
  final int workingSets;
  final double volumeKg;

  /// Muscle group trained the most that day.
  final String? categoryId;

  const StrengthDayBucket({
    required this.date,
    required this.sessions,
    required this.workingSets,
    required this.volumeKg,
    this.categoryId,
  });

  bool get hasSession => sessions > 0;
}

/// Totals of a window of time.
class StrengthPeriodTotals {
  final int sessions;
  final double volumeKg;
  final int workingSets;
  final int durationSeconds;

  const StrengthPeriodTotals({
    required this.sessions,
    required this.volumeKg,
    required this.workingSets,
    required this.durationSeconds,
  });

  static const empty = StrengthPeriodTotals(
    sessions: 0,
    volumeKg: 0,
    workingSets: 0,
    durationSeconds: 0,
  );

  bool get isEmpty => sessions == 0;

  int get avgDurationSeconds =>
      sessions == 0 ? 0 : (durationSeconds / sessions).round();
}

enum StrengthWeekGoalSource { plan, user, average }

/// The number of sessions aimed for this week and where it comes from.
class StrengthWeekGoal {
  final int sessions;
  final StrengthWeekGoalSource source;

  const StrengthWeekGoal(this.sessions, this.source);

  /// Plan target first, then the goal set by hand, then the (rounded) weekly
  /// average of the selected period. Null when none of them is above zero.
  static StrengthWeekGoal? resolve({
    int? planSessions,
    int? userSessions,
    double? averageSessions,
  }) {
    if (planSessions != null && planSessions > 0) {
      return StrengthWeekGoal(planSessions, StrengthWeekGoalSource.plan);
    }
    if (userSessions != null && userSessions > 0) {
      return StrengthWeekGoal(userSessions, StrengthWeekGoalSource.user);
    }
    if (averageSessions != null && averageSessions >= 0.5) {
      return StrengthWeekGoal(
        averageSessions.round().clamp(1, 14),
        StrengthWeekGoalSource.average,
      );
    }
    return null;
  }
}

/// Compact value + unit for a volume in kilograms: tonnes from 10 t up.
class StrengthVolumeValue {
  final double value;
  final bool tonnes;

  const StrengthVolumeValue(this.value, this.tonnes);

  factory StrengthVolumeValue.of(double kg) => kg >= 10000
      ? StrengthVolumeValue(kg / 1000, true)
      : StrengthVolumeValue(kg, false);

  String get unit => tonnes ? 't' : 'kg';

  int get digits => tonnes ? 1 : 0;
}

/// Everything the gym hub shows about a period, computed once from the
/// finished workouts: totals, the previous window, weekly/monthly buckets,
/// the current week and the week streak. Pure, so it is unit-tested.
class StrengthWeekAnalytics {
  /// Longer weekly charts fall back to monthly bars.
  static const int maxWeeklyChartBuckets = 60;

  final RunStatsPeriod period;
  final DateTime now;
  final DateTime? periodStart;
  final int periodWeekCount;
  final StrengthPeriodTotals totals;
  final StrengthPeriodTotals previous;
  final bool hasPreviousPeriod;
  final List<StrengthTrendBucket> trendBuckets;
  final List<StrengthDayBucket> thisWeekDays;
  final int thisWeekSessions;
  final int thisWeekSets;
  final double thisWeekVolumeKg;
  final int lastWeekSessions;
  final int lastWeekSets;
  final double lastWeekVolumeKg;

  /// Consecutive calendar weeks (ending this week, or last week while this
  /// one is still empty) with at least one session.
  final int weekStreak;

  /// Workouts inside the period, oldest first.
  final List<StrengthWorkoutSummary> workouts;

  const StrengthWeekAnalytics({
    required this.period,
    required this.now,
    required this.periodStart,
    required this.periodWeekCount,
    required this.totals,
    required this.previous,
    required this.hasPreviousPeriod,
    required this.trendBuckets,
    required this.thisWeekDays,
    required this.thisWeekSessions,
    required this.thisWeekSets,
    required this.thisWeekVolumeKg,
    required this.lastWeekSessions,
    required this.lastWeekSets,
    required this.lastWeekVolumeKg,
    required this.weekStreak,
    required this.workouts,
  });

  bool get trendIsMonthly => trendBuckets.any((b) => b.isMonthly);

  int get sessionCount => totals.sessions;

  /// Average sessions per calendar week over the period.
  double get avgWeeklySessions =>
      periodWeekCount <= 0 ? 0 : totals.sessions / periodWeekCount;

  bool get hasWeekComparison => lastWeekSessions > 0 || thisWeekSessions > 0;

  /// Average per trend bucket (week or month).
  double get trendAvgVolumeKg =>
      trendBuckets.isEmpty ? 0 : totals.volumeKg / trendBuckets.length;

  double get trendAvgSessions =>
      trendBuckets.isEmpty ? 0 : totals.sessions / trendBuckets.length;

  /// Average session length across the buckets that had sessions, seconds.
  double get trendAvgDurationSeconds => totals.avgDurationSeconds.toDouble();

  /// Volume change against the previous window of the same length as a
  /// fraction (0.12 = +12%); null with nothing to compare.
  double? get volumeRatioVsPreviousPeriod {
    if (!hasPreviousPeriod || previous.volumeKg <= 0) return null;
    return totals.volumeKg / previous.volumeKg - 1;
  }

  factory StrengthWeekAnalytics.fromWorkouts(
    List<StrengthWorkoutSummary> all, {
    required RunStatsPeriod period,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final today = dayOf(clock);
    final thisWeekStart = mondayOf(today);
    final nextWeekStart = addDays(thisWeekStart, 7);
    final lastWeekStart = addDays(thisWeekStart, -7);

    final finished = all.where((w) => !w.date.isAfter(today)).toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    final fixedWeeks = period.weekCount;
    DateTime? windowStart;
    int weekCount;
    if (fixedWeeks != null) {
      weekCount = fixedWeeks;
      windowStart = addDays(thisWeekStart, -7 * (fixedWeeks - 1));
    } else if (finished.isEmpty) {
      weekCount = 1;
    } else {
      windowStart = mondayOf(finished.first.date);
      weekCount = daysBetween(windowStart, thisWeekStart) ~/ 7 + 1;
    }

    final inPeriod = finished
        .where((w) => windowStart == null || !w.date.isBefore(windowStart))
        .toList();

    final bucketWeeks = fixedWeeks ?? (weekCount < 4 ? 4 : weekCount);
    final weekly = _weeklyBuckets(inPeriod, bucketWeeks, thisWeekStart);
    final trend = weekly.length > maxWeeklyChartBuckets
        ? _monthlyBuckets(inPeriod, today)
        : weekly;

    var thisSessions = 0;
    var thisSets = 0;
    var thisVolume = 0.0;
    var lastSessions = 0;
    var lastSets = 0;
    var lastVolume = 0.0;
    final daySessions = List<int>.filled(7, 0);
    final daySets = List<int>.filled(7, 0);
    final dayVolume = List<double>.filled(7, 0);
    final dayCategories = List<Map<String, int>>.generate(7, (_) => {});
    for (final w in finished) {
      if (!w.date.isBefore(thisWeekStart) && w.date.isBefore(nextWeekStart)) {
        thisSessions++;
        thisSets += w.workingSets;
        thisVolume += w.volumeKg;
        final i = daysBetween(thisWeekStart, w.date).clamp(0, 6);
        daySessions[i]++;
        daySets[i] += w.workingSets;
        dayVolume[i] += w.volumeKg;
        final top = w.dominantCategoryId;
        if (top != null) {
          dayCategories[i][top] = (dayCategories[i][top] ?? 0) + w.workingSets;
        }
      } else if (!w.date.isBefore(lastWeekStart) &&
          w.date.isBefore(thisWeekStart)) {
        lastSessions++;
        lastSets += w.workingSets;
        lastVolume += w.volumeKg;
      }
    }

    String? dominant(Map<String, int> counts) {
      String? best;
      counts.forEach((id, n) {
        if (best == null || n > counts[best]!) best = id;
      });
      return best;
    }

    final previous = (windowStart == null || fixedWeeks == null)
        ? StrengthPeriodTotals.empty
        : _totals(
            finished,
            start: addDays(windowStart, -(7 * weekCount)),
            end: windowStart,
          );

    return StrengthWeekAnalytics(
      period: period,
      now: clock,
      periodStart: fixedWeeks != null
          ? windowStart
          : (inPeriod.isEmpty ? null : inPeriod.first.date),
      periodWeekCount: weekCount,
      totals: _totals(inPeriod),
      previous: previous,
      hasPreviousPeriod: fixedWeeks != null && !previous.isEmpty,
      trendBuckets: trend,
      thisWeekDays: [
        for (var i = 0; i < 7; i++)
          StrengthDayBucket(
            date: addDays(thisWeekStart, i),
            sessions: daySessions[i],
            workingSets: daySets[i],
            volumeKg: dayVolume[i],
            categoryId: dominant(dayCategories[i]),
          ),
      ],
      thisWeekSessions: thisSessions,
      thisWeekSets: thisSets,
      thisWeekVolumeKg: thisVolume,
      lastWeekSessions: lastSessions,
      lastWeekSets: lastSets,
      lastWeekVolumeKg: lastVolume,
      weekStreak: weekStreakOfDates([
        for (final w in finished) w.date,
      ], thisWeekStart),
      workouts: inPeriod,
    );
  }

  static StrengthPeriodTotals _totals(
    List<StrengthWorkoutSummary> workouts, {
    DateTime? start,
    DateTime? end,
  }) {
    var sessions = 0;
    var volume = 0.0;
    var sets = 0;
    var duration = 0;
    for (final w in workouts) {
      if (start != null && w.date.isBefore(start)) continue;
      if (end != null && !w.date.isBefore(end)) continue;
      sessions++;
      volume += w.volumeKg;
      sets += w.workingSets;
      duration += w.durationSeconds;
    }
    return StrengthPeriodTotals(
      sessions: sessions,
      volumeKg: volume,
      workingSets: sets,
      durationSeconds: duration,
    );
  }

  /// Counts back week by week while every week has at least one activity in
  /// [days]. A week still in progress with none yet does not break the
  /// streak.
  static int weekStreakOfDates(
    Iterable<DateTime> days,
    DateTime thisWeekStart,
  ) {
    final weeks = <DateTime>{for (final d in days) mondayOf(d)};
    if (weeks.isEmpty) return 0;
    var cursor = weeks.contains(thisWeekStart)
        ? thisWeekStart
        : addDays(thisWeekStart, -7);
    var streak = 0;
    while (weeks.contains(cursor)) {
      streak++;
      cursor = addDays(cursor, -7);
    }
    return streak;
  }

  static List<StrengthTrendBucket> _weeklyBuckets(
    List<StrengthWorkoutSummary> workouts,
    int weekCount,
    DateTime thisWeekStart,
  ) {
    final starts = [
      for (var i = weekCount - 1; i >= 0; i--)
        addDays(thisWeekStart, -(7 * i)),
    ];
    final index = {for (var i = 0; i < starts.length; i++) starts[i]: i};
    final sessions = List<int>.filled(starts.length, 0);
    final volume = List<double>.filled(starts.length, 0);
    final sets = List<int>.filled(starts.length, 0);
    final duration = List<int>.filled(starts.length, 0);
    for (final w in workouts) {
      final i = index[mondayOf(w.date)];
      if (i == null) continue;
      sessions[i]++;
      volume[i] += w.volumeKg;
      sets[i] += w.workingSets;
      duration[i] += w.durationSeconds;
    }
    return [
      for (var i = 0; i < starts.length; i++)
        StrengthTrendBucket(
          start: starts[i],
          spanDays: 7,
          sessions: sessions[i],
          volumeKg: volume[i],
          workingSets: sets[i],
          durationSeconds: duration[i],
        ),
    ];
  }

  static List<StrengthTrendBucket> _monthlyBuckets(
    List<StrengthWorkoutSummary> workouts,
    DateTime today,
  ) {
    if (workouts.isEmpty) return const [];
    final first = workouts.first.date;
    final months =
        (today.year - first.year) * 12 + today.month - first.month + 1;
    final sessions = List<int>.filled(months, 0);
    final volume = List<double>.filled(months, 0);
    final sets = List<int>.filled(months, 0);
    final duration = List<int>.filled(months, 0);
    for (final w in workouts) {
      final i = (w.date.year - first.year) * 12 + w.date.month - first.month;
      if (i < 0 || i >= months) continue;
      sessions[i]++;
      volume[i] += w.volumeKg;
      sets[i] += w.workingSets;
      duration[i] += w.durationSeconds;
    }
    return [
      for (var i = 0; i < months; i++)
        () {
          final start = DateTime(first.year, first.month + i);
          final next = DateTime(first.year, first.month + i + 1);
          return StrengthTrendBucket(
            start: start,
            spanDays: daysBetween(start, next),
            sessions: sessions[i],
            volumeKg: volume[i],
            workingSets: sets[i],
            durationSeconds: duration[i],
          );
        }(),
    ];
  }
}

/// A completed run or other cardio session, for the Treino overview.
class WorkoutCardioStamp {
  final DateTime date;
  final int durationSeconds;

  /// Metres of a running session; 0 for other cardio, which still counts for
  /// active time and the streak.
  final double runDistanceMeters;

  const WorkoutCardioStamp({
    required this.date,
    required this.durationSeconds,
    this.runDistanceMeters = 0,
  });
}

/// "This week" across gym and running for the Treino tab: strength
/// sessions, kilometres run, active time and the streak of weeks in which at
/// least one of them was done. Finished sessions only.
class WorkoutWeekOverview {
  final int strengthSessions;
  final int cardioSessions;
  final double runMeters;
  final int activeSeconds;
  final int streakWeeks;

  const WorkoutWeekOverview({
    required this.strengthSessions,
    required this.cardioSessions,
    required this.runMeters,
    required this.activeSeconds,
    required this.streakWeeks,
  });

  static const empty = WorkoutWeekOverview(
    strengthSessions: 0,
    cardioSessions: 0,
    runMeters: 0,
    activeSeconds: 0,
    streakWeeks: 0,
  );

  bool get hasActivityThisWeek => strengthSessions > 0 || cardioSessions > 0;

  factory WorkoutWeekOverview.compute({
    required List<StrengthWorkoutStamp> gym,
    required List<WorkoutCardioStamp> cardio,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final today = dayOf(clock);
    final monday = mondayOf(today);
    final nextMonday = addDays(monday, 7);
    bool thisWeek(DateTime d) => !d.isBefore(monday) && d.isBefore(nextMonday);

    var strength = 0;
    var cardioCount = 0;
    var meters = 0.0;
    var seconds = 0;
    for (final g in gym) {
      if (!thisWeek(g.date)) continue;
      strength++;
      seconds += g.durationSeconds;
    }
    for (final c in cardio) {
      if (!thisWeek(c.date)) continue;
      cardioCount++;
      meters += c.runDistanceMeters;
      seconds += c.durationSeconds;
    }
    return WorkoutWeekOverview(
      strengthSessions: strength,
      cardioSessions: cardioCount,
      runMeters: meters,
      activeSeconds: seconds,
      streakWeeks: StrengthWeekAnalytics.weekStreakOfDates([
        for (final g in gym) g.date,
        for (final c in cardio) c.date,
      ], monday),
    );
  }
}
