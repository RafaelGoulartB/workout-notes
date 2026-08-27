import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/services/run_plan_composer.dart';

/// A completed GPS run the wizard can use as "recent race" calibration.
class RunPlanSuggestedRace {
  final double distanceMeters;
  final int timeSeconds;
  final DateTime startedAt;

  const RunPlanSuggestedRace({
    required this.distanceMeters,
    required this.timeSeconds,
    required this.startedAt,
  });

  RunPlanPaceCalibration get calibration => RunPlanPaceCalibration(
    distanceMeters: distanceMeters,
    timeSeconds: timeSeconds,
  );
}

/// Volume and race suggestions derived from recorded runs — no I/O.
class RunPlanHistoryInsights {
  /// Median km of the last complete weeks that had at least one run.
  final double? medianWeeklyKm;

  /// How many complete weeks went into [medianWeeklyKm].
  final int medianWeekCount;

  final RunPlanSuggestedRace? suggestedRace;

  const RunPlanHistoryInsights({
    this.medianWeeklyKm,
    this.medianWeekCount = 0,
    this.suggestedRace,
  });

  static const minRaceMeters = 3000.0;
  static const lookbackDays = 180;
  static const completeWeeks = 4;

  static RunPlanHistoryInsights from(
    List<RunActivity> activities, {
    DateTime? now,
    double? goalDistanceMeters,
  }) {
    final clock = now ?? DateTime.now();
    final runs = activities.where(_isUsableRun).toList();
    return RunPlanHistoryInsights(
      medianWeeklyKm: _medianWeeklyKm(runs, clock),
      medianWeekCount: _weeksWithRuns(runs, clock).length,
      suggestedRace: _suggestRace(runs, clock, goalDistanceMeters),
    );
  }

  static bool _isUsableRun(RunActivity activity) =>
      activity.isCompleted &&
      activity.isRun &&
      activity.distanceMeters > 0 &&
      _effortSeconds(activity) > 0;

  static int _effortSeconds(RunActivity activity) =>
      activity.movingTimeSeconds > 0
      ? activity.movingTimeSeconds
      : activity.durationSeconds;

  static double _paceSecPerKm(RunActivity activity) =>
      _effortSeconds(activity) / (activity.distanceMeters / 1000);

  /// Monday of the calendar week containing [date], local date only.
  static DateTime weekStart(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  /// Last [completeWeeks] finished weeks (excludes the current partial week).
  static List<double> _weeksWithRuns(List<RunActivity> runs, DateTime now) {
    final currentWeek = weekStart(now);
    final km = <double>[];
    for (var i = 1; i <= completeWeeks; i++) {
      final start = currentWeek.subtract(Duration(days: 7 * i));
      final end = start.add(const Duration(days: 7));
      final weekKm = runs
          .where(
            (run) =>
                !run.startedAt.isBefore(start) && run.startedAt.isBefore(end),
          )
          .fold<double>(0, (sum, run) => sum + run.distanceMeters / 1000);
      if (weekKm > 0) km.add(weekKm);
    }
    return km;
  }

  static double? _medianWeeklyKm(List<RunActivity> runs, DateTime now) {
    final weeks = _weeksWithRuns(runs, now);
    if (weeks.isEmpty) return null;
    final sorted = [...weeks]..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[mid];
    return (sorted[mid - 1] + sorted[mid]) / 2;
  }

  static RunPlanSuggestedRace? _suggestRace(
    List<RunActivity> runs,
    DateTime now,
    double? goalDistanceMeters,
  ) {
    final cutoff = now.subtract(const Duration(days: lookbackDays));
    final eligible = runs
        .where(
          (run) =>
              run.distanceMeters >= minRaceMeters &&
              !run.startedAt.isBefore(cutoff),
        )
        .toList();
    if (eligible.isEmpty) return null;

    RunActivity pick;
    if (goalDistanceMeters != null && goalDistanceMeters > 0) {
      final near = eligible
          .where(
            (run) =>
                (run.distanceMeters - goalDistanceMeters).abs() /
                    goalDistanceMeters <=
                0.20,
          )
          .toList();
      pick = (near.isNotEmpty ? near : eligible).reduce((a, b) {
        if (near.isNotEmpty) {
          return _paceSecPerKm(a) <= _paceSecPerKm(b) ? a : b;
        }
        final da = (a.distanceMeters - goalDistanceMeters).abs();
        final db = (b.distanceMeters - goalDistanceMeters).abs();
        if ((da - db).abs() < 1) {
          return _paceSecPerKm(a) <= _paceSecPerKm(b) ? a : b;
        }
        return da < db ? a : b;
      });
    } else {
      pick = eligible.reduce(
        (a, b) => _paceSecPerKm(a) <= _paceSecPerKm(b) ? a : b,
      );
    }

    return RunPlanSuggestedRace(
      distanceMeters: pick.distanceMeters,
      timeSeconds: _effortSeconds(pick),
      startedAt: pick.startedAt,
    );
  }
}
