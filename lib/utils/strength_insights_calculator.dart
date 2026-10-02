import 'package:workout_notes/repositories/strength_records_repository.dart';
import 'package:workout_notes/utils/date_utils.dart';

/// Window of the volume tab: last 4 weeks, 12 weeks or a year.
enum StrengthPeriod {
  weeks4(28),
  weeks12(84),
  year(365);

  /// Length in days.
  final int days;

  const StrengthPeriod(this.days);
}

/// Inclusive range of local calendar days.
class StrengthRange {
  final DateTime from;
  final DateTime to;

  const StrengthRange(this.from, this.to);

  int get days => daysBetween(from, to) + 1;

  double get weeks => days / 7;

  bool contains(DateTime date) {
    final d = dayOf(date);
    return !d.isBefore(from) && !d.isAfter(to);
  }
}

/// Headline numbers of a range.
class StrengthTotals {
  final double volume;
  final int sets;
  final int sessions;
  final int activeDays;

  const StrengthTotals({
    required this.volume,
    required this.sets,
    required this.sessions,
    required this.activeDays,
  });

  static const empty = StrengthTotals(
    volume: 0,
    sets: 0,
    sessions: 0,
    activeDays: 0,
  );
}

/// Volume, sets and sessions of one week or month.
class StrengthVolumeBucket {
  final DateTime start;
  final bool monthly;
  final double volume;
  final int sets;
  final int sessions;

  const StrengthVolumeBucket({
    required this.start,
    required this.monthly,
    required this.volume,
    required this.sets,
    required this.sessions,
  });
}

enum StrengthLoadStatus { below, within, above }

/// Working sets of one muscle group compared with the recommended range.
class StrengthMuscleLoad {
  final String categoryId;
  final int sets;
  final double volume;

  /// Average sets per week over the range.
  final double weeklySets;

  const StrengthMuscleLoad({
    required this.categoryId,
    required this.sets,
    required this.volume,
    required this.weeklySets,
  });

  StrengthLoadStatus get status {
    if (weeklySets < StrengthInsightsCalculator.recommendedMinWeeklySets) {
      return StrengthLoadStatus.below;
    }
    if (weeklySets > StrengthInsightsCalculator.recommendedMaxWeeklySets) {
      return StrengthLoadStatus.above;
    }
    return StrengthLoadStatus.within;
  }
}

/// One exercise's total work in a range.
class StrengthExerciseVolume {
  final String exerciseId;
  final String exerciseName;
  final String? exerciseLocaleKey;
  final String categoryId;
  final double volume;
  final int sets;

  const StrengthExerciseVolume({
    required this.exerciseId,
    required this.exerciseName,
    required this.exerciseLocaleKey,
    required this.categoryId,
    required this.volume,
    required this.sets,
  });

  Map<String, dynamic> get exerciseRow => {
    'name': exerciseName,
    'locale_key': exerciseLocaleKey,
    'category_id': categoryId,
  };
}

/// Progress line of one exercise across its sessions.
class StrengthExerciseSummary {
  final String exerciseId;
  final String exerciseName;
  final String? exerciseLocaleKey;
  final String categoryId;
  final int sessions;
  final DateTime lastDate;

  /// Best estimated 1RM ever (null for bodyweight/timed exercises).
  final double? bestE1rm;

  /// Best e1RM of each session, oldest first (last [seriesLength] sessions).
  final List<double> e1rmSeries;
  final double maxWeight;
  final int maxReps;

  const StrengthExerciseSummary({
    required this.exerciseId,
    required this.exerciseName,
    required this.exerciseLocaleKey,
    required this.categoryId,
    required this.sessions,
    required this.lastDate,
    required this.bestE1rm,
    required this.e1rmSeries,
    required this.maxWeight,
    required this.maxReps,
  });

  /// Change of the newest session's e1RM against the oldest of the series.
  double? get trendPercent {
    if (e1rmSeries.length < 2 || e1rmSeries.first <= 0) return null;
    return (e1rmSeries.last - e1rmSeries.first) / e1rmSeries.first * 100;
  }

  Map<String, dynamic> get exerciseRow => {
    'name': exerciseName,
    'locale_key': exerciseLocaleKey,
    'category_id': categoryId,
  };
}

/// Weekly training consistency.
class StrengthConsistency {
  final int currentWeekStreak;
  final int longestWeekStreak;
  final int weeksConsidered;
  final int weeksTrained;
  final double sessionsPerWeek;

  const StrengthConsistency({
    required this.currentWeekStreak,
    required this.longestWeekStreak,
    required this.weeksConsidered,
    required this.weeksTrained,
    required this.sessionsPerWeek,
  });

  double get share => weeksConsidered == 0 ? 0 : weeksTrained / weeksConsidered;
}

/// Average of a week (null value = nothing recorded that week).
class StrengthWeekAverage {
  final DateTime weekStart;
  final double? value;

  const StrengthWeekAverage(this.weekStart, this.value);
}

enum StrengthDayPart { morning, afternoon, evening, night }

/// Average session volume for a given feeling rating (1 to 5).
class StrengthFeelingVolume {
  final int rating;
  final double averageVolume;
  final int sessions;

  const StrengthFeelingVolume(this.rating, this.averageVolume, this.sessions);
}

/// Pure calculations behind the strength analysis screen. Everything takes
/// the completed working sets / finished workouts loaded by
/// [StrengthRecordsRepository] so it can be tested without a database.
abstract final class StrengthInsightsCalculator {
  /// Weekly working sets per muscle group that most programs recommend for
  /// hypertrophy and strength (10 to 20).
  static const recommendedMinWeeklySets = 10;
  static const recommendedMaxWeeklySets = 20;

  /// Sessions kept in an exercise's sparkline.
  static const seriesLength = 12;

  /// The range of [period] ending [today]; [previous] gives the one right
  /// before it (same length), used for deltas.
  static StrengthRange rangeFor(
    StrengthPeriod period,
    DateTime today, {
    bool previous = false,
  }) {
    final end = dayOf(today);
    final to = previous ? addDays(end, -period.days) : end;
    return StrengthRange(addDays(to, -(period.days - 1)), to);
  }

  static StrengthTotals totals(
    List<StrengthSetSample> sets,
    List<StrengthWorkoutInfo> workouts,
    StrengthRange range,
  ) {
    var volume = 0.0;
    var count = 0;
    final days = <DateTime>{};
    for (final s in sets) {
      if (!range.contains(s.date)) continue;
      volume += s.volume;
      count++;
      days.add(dayOf(s.date));
    }
    final sessions = workouts.where((w) => range.contains(w.date)).length;
    return StrengthTotals(
      volume: volume,
      sets: count,
      sessions: sessions,
      activeDays: days.length,
    );
  }

  /// Last [count] weeks (Monday-based, oldest first), the current one last.
  static List<StrengthVolumeBucket> weeklyBuckets(
    List<StrengthSetSample> sets,
    List<StrengthWorkoutInfo> workouts,
    DateTime today, {
    int count = 12,
  }) {
    final current = mondayOf(today);
    final starts = [
      for (var i = count - 1; i >= 0; i--) addDays(current, -7 * i),
    ];
    return _buckets(sets, workouts, starts, monthly: false);
  }

  /// Last [count] calendar months, oldest first, the current one last.
  static List<StrengthVolumeBucket> monthlyBuckets(
    List<StrengthSetSample> sets,
    List<StrengthWorkoutInfo> workouts,
    DateTime today, {
    int count = 12,
  }) {
    final starts = [
      for (var i = count - 1; i >= 0; i--)
        DateTime(today.year, today.month - i),
    ];
    return _buckets(sets, workouts, starts, monthly: true);
  }

  static List<StrengthVolumeBucket> _buckets(
    List<StrengthSetSample> sets,
    List<StrengthWorkoutInfo> workouts,
    List<DateTime> starts, {
    required bool monthly,
  }) {
    DateTime key(DateTime d) =>
        monthly ? DateTime(d.year, d.month) : mondayOf(d);
    final index = {for (var i = 0; i < starts.length; i++) starts[i]: i};
    final volume = List<double>.filled(starts.length, 0);
    final setCount = List<int>.filled(starts.length, 0);
    final sessions = List<int>.filled(starts.length, 0);
    for (final s in sets) {
      final i = index[key(s.date)];
      if (i == null) continue;
      volume[i] += s.volume;
      setCount[i]++;
    }
    for (final w in workouts) {
      final i = index[key(w.date)];
      if (i != null) sessions[i]++;
    }
    return [
      for (var i = 0; i < starts.length; i++)
        StrengthVolumeBucket(
          start: starts[i],
          monthly: monthly,
          volume: volume[i],
          sets: setCount[i],
          sessions: sessions[i],
        ),
    ];
  }

  /// Sets per muscle group in [range]. Groups in [categoryIds] with no work
  /// are included with zero sets, so neglected muscles show up too. Sorted by
  /// sets, most first.
  static List<StrengthMuscleLoad> muscleLoad(
    List<StrengthSetSample> sets,
    StrengthRange range, {
    Iterable<String> categoryIds = const [],
  }) {
    final count = <String, int>{for (final id in categoryIds) id: 0};
    final volume = <String, double>{for (final id in categoryIds) id: 0};
    for (final s in sets) {
      if (!range.contains(s.date)) continue;
      count[s.categoryId] = (count[s.categoryId] ?? 0) + 1;
      volume[s.categoryId] = (volume[s.categoryId] ?? 0) + s.volume;
    }
    final weeks = range.weeks;
    final result = [
      for (final id in count.keys)
        StrengthMuscleLoad(
          categoryId: id,
          sets: count[id]!,
          volume: volume[id]!,
          weeklySets: count[id]! / weeks,
        ),
    ];
    result.sort((a, b) => b.sets.compareTo(a.sets));
    return result;
  }

  /// Exercises ranked by volume (sets when volumes tie, as bodyweight
  /// exercises have none).
  static List<StrengthExerciseVolume> topExercises(
    List<StrengthSetSample> sets,
    StrengthRange range, {
    int limit = 5,
  }) {
    final volume = <String, double>{};
    final count = <String, int>{};
    final first = <String, StrengthSetSample>{};
    for (final s in sets) {
      if (!range.contains(s.date)) continue;
      volume[s.exerciseId] = (volume[s.exerciseId] ?? 0) + s.volume;
      count[s.exerciseId] = (count[s.exerciseId] ?? 0) + 1;
      first.putIfAbsent(s.exerciseId, () => s);
    }
    final result = [
      for (final id in volume.keys)
        StrengthExerciseVolume(
          exerciseId: id,
          exerciseName: first[id]!.exerciseName,
          exerciseLocaleKey: first[id]!.exerciseLocaleKey,
          categoryId: first[id]!.categoryId,
          volume: volume[id]!,
          sets: count[id]!,
        ),
    ];
    result.sort((a, b) {
      final v = b.volume.compareTo(a.volume);
      return v != 0 ? v : b.sets.compareTo(a.sets);
    });
    return result.take(limit).toList();
  }

  /// One summary per exercise, most recently trained first.
  static List<StrengthExerciseSummary> exerciseSummaries(
    List<StrengthSetSample> sets,
  ) {
    final byExercise = <String, List<StrengthSetSample>>{};
    for (final s in sets) {
      byExercise.putIfAbsent(s.exerciseId, () => []).add(s);
    }
    final result = <StrengthExerciseSummary>[];
    byExercise.forEach((id, list) {
      // Best e1RM per session, in chronological order of the first set.
      final sessionOrder = <String>[];
      final sessionBest = <String, double?>{};
      var best = 0.0;
      var maxWeight = 0.0;
      var maxReps = 0;
      for (final s in list) {
        if (!sessionBest.containsKey(s.workoutId)) {
          sessionOrder.add(s.workoutId);
          sessionBest[s.workoutId] = null;
        }
        final e = s.e1rm;
        if (e != null) {
          final current = sessionBest[s.workoutId];
          if (current == null || e > current) sessionBest[s.workoutId] = e;
          if (e > best) best = e;
        }
        if (s.weight > maxWeight) maxWeight = s.weight;
        if (s.reps > maxReps) maxReps = s.reps;
      }
      final series = [
        for (final w in sessionOrder)
          if (sessionBest[w] != null) sessionBest[w]!,
      ];
      final first = list.first;
      result.add(
        StrengthExerciseSummary(
          exerciseId: id,
          exerciseName: first.exerciseName,
          exerciseLocaleKey: first.exerciseLocaleKey,
          categoryId: first.categoryId,
          sessions: sessionOrder.length,
          lastDate: list.last.date,
          bestE1rm: best > 0 ? best : null,
          e1rmSeries: series.length > seriesLength
              ? series.sublist(series.length - seriesLength)
              : series,
          maxWeight: maxWeight,
          maxReps: maxReps,
        ),
      );
    });
    result.sort((a, b) => b.lastDate.compareTo(a.lastDate));
    return result;
  }

  // ------------------------------------------------------------------
  // Frequency
  // ------------------------------------------------------------------

  /// Working sets per local day of [year] (heatmap values).
  static Map<DateTime, double> dailySets(
    List<StrengthSetSample> sets, {
    required int year,
  }) {
    final result = <DateTime, double>{};
    for (final s in sets) {
      if (s.date.year != year) continue;
      final d = dayOf(s.date);
      result[d] = (result[d] ?? 0) + 1;
    }
    return result;
  }

  /// Years with at least one workout, newest first (the current year is
  /// always offered).
  static List<int> availableYears(
    List<StrengthWorkoutInfo> workouts,
    DateTime today,
  ) {
    final years = {today.year, for (final w in workouts) w.date.year}.toList()
      ..sort((a, b) => b.compareTo(a));
    return years;
  }

  /// Sessions of each of the last [count] weeks, oldest first.
  static List<StrengthVolumeBucket> weeklySessions(
    List<StrengthWorkoutInfo> workouts,
    DateTime today, {
    int count = 12,
  }) => weeklyBuckets(const [], workouts, today, count: count);

  /// Sessions per weekday, Monday first (index 0) to Sunday.
  static List<int> weekdayCounts(List<StrengthWorkoutInfo> workouts) {
    final counts = List<int>.filled(7, 0);
    for (final w in workouts) {
      counts[w.date.weekday - 1]++;
    }
    return counts;
  }

  /// Sessions per part of the day, only counting workouts with a start time.
  static Map<StrengthDayPart, int> dayPartCounts(
    List<StrengthWorkoutInfo> workouts,
  ) {
    final counts = {for (final p in StrengthDayPart.values) p: 0};
    for (final w in workouts) {
      if (!w.hasTime) continue;
      final h = w.date.hour;
      final part = h >= 5 && h < 12
          ? StrengthDayPart.morning
          : h >= 12 && h < 18
          ? StrengthDayPart.afternoon
          : h >= 18
          ? StrengthDayPart.evening
          : StrengthDayPart.night;
      counts[part] = counts[part]! + 1;
    }
    return counts;
  }

  /// Average session length (minutes) per week for the last [count] weeks.
  static List<StrengthWeekAverage> weeklyDuration(
    List<StrengthWorkoutInfo> workouts,
    DateTime today, {
    int count = 12,
  }) => _weeklyAverage(
    workouts,
    today,
    count,
    (w) => (w.durationSeconds ?? 0) > 0 ? w.durationSeconds! / 60 : null,
  );

  /// Average feeling (1 to 5) per week for the last [count] weeks.
  static List<StrengthWeekAverage> weeklyFeeling(
    List<StrengthWorkoutInfo> workouts,
    DateTime today, {
    int count = 12,
  }) => _weeklyAverage(workouts, today, count, (w) => w.feeling?.toDouble());

  static List<StrengthWeekAverage> _weeklyAverage(
    List<StrengthWorkoutInfo> workouts,
    DateTime today,
    int count,
    double? Function(StrengthWorkoutInfo) valueOf,
  ) {
    final current = mondayOf(today);
    final starts = [
      for (var i = count - 1; i >= 0; i--) addDays(current, -7 * i),
    ];
    final index = {for (var i = 0; i < starts.length; i++) starts[i]: i};
    final sum = List<double>.filled(count, 0);
    final n = List<int>.filled(count, 0);
    for (final w in workouts) {
      final i = index[mondayOf(w.date)];
      final v = valueOf(w);
      if (i == null || v == null) continue;
      sum[i] += v;
      n[i]++;
    }
    return [
      for (var i = 0; i < count; i++)
        StrengthWeekAverage(starts[i], n[i] == 0 ? null : sum[i] / n[i]),
    ];
  }

  /// Average session volume for each feeling rating that was used.
  static List<StrengthFeelingVolume> feelingVsVolume(
    List<StrengthWorkoutInfo> workouts,
    List<StrengthSetSample> sets,
  ) {
    final volumeOf = <String, double>{};
    for (final s in sets) {
      volumeOf[s.workoutId] = (volumeOf[s.workoutId] ?? 0) + s.volume;
    }
    final sum = <int, double>{};
    final n = <int, int>{};
    for (final w in workouts) {
      final rating = w.feeling;
      final volume = volumeOf[w.id];
      if (rating == null || volume == null || volume <= 0) continue;
      sum[rating] = (sum[rating] ?? 0) + volume;
      n[rating] = (n[rating] ?? 0) + 1;
    }
    final ratings = sum.keys.toList()..sort();
    return [
      for (final r in ratings) StrengthFeelingVolume(r, sum[r]! / n[r]!, n[r]!),
    ];
  }

  /// Week streaks and how many of the last [weeks] weeks had a session. The
  /// week in progress never breaks a streak: with no session yet, the streak
  /// counts from last week.
  static StrengthConsistency consistency(
    List<StrengthWorkoutInfo> workouts,
    DateTime today, {
    int weeks = 12,
  }) {
    final trained = {for (final w in workouts) mondayOf(w.date)};
    final current = mondayOf(today);

    var streak = 0;
    var cursor = trained.contains(current) ? current : addDays(current, -7);
    while (trained.contains(cursor)) {
      streak++;
      cursor = addDays(cursor, -7);
    }

    var longest = 0;
    final ordered = trained.toList()..sort();
    var run = 0;
    DateTime? previous;
    for (final week in ordered) {
      run = previous != null && addDays(previous, 7) == week ? run + 1 : 1;
      if (run > longest) longest = run;
      previous = week;
    }

    // A newcomer is judged only on the weeks since the first workout.
    var considered = 0;
    if (ordered.isNotEmpty) {
      final available =
          (current.difference(ordered.first).inHours / (24 * 7)).round() + 1;
      considered = available < weeks ? available : weeks;
    }
    final window = [
      for (var i = 0; i < considered; i++) addDays(current, -7 * i),
    ];
    final sessions = considered == 0
        ? 0
        : workouts.where((w) => !dayOf(w.date).isBefore(window.last)).length;
    return StrengthConsistency(
      currentWeekStreak: streak,
      longestWeekStreak: longest,
      weeksConsidered: considered,
      weeksTrained: window.where(trained.contains).length,
      sessionsPerWeek: considered == 0 ? 0 : sessions / considered,
    );
  }
}
