import 'package:workout_notes/models/run_achievement.dart';
import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/utils/run_achievement_engine.dart';

/// What a just-finished run means against the history: record placements,
/// month bests and the running volume of its week. Pure, so the post-run
/// review can compute it from two light queries.
class RunReviewInsights {
  /// Top-3 all-time placements this run takes (empty for treadmill runs).
  final List<RunAchievementPlacement> placements;

  /// Longest / fastest (avg pace) of the calendar month, among 2+ runs.
  final bool longestOfMonth;
  final bool fastestOfMonth;

  /// Running volume of the week (Monday start) including this run.
  final double weekMeters;
  final int weekRunCount;

  /// No earlier completed running activity exists.
  final bool isFirstRun;

  const RunReviewInsights({
    required this.placements,
    required this.longestOfMonth,
    required this.fastestOfMonth,
    required this.weekMeters,
    required this.weekRunCount,
    required this.isFirstRun,
  });

  static const empty = RunReviewInsights(
    placements: [],
    longestOfMonth: false,
    fastestOfMonth: false,
    weekMeters: 0,
    weekRunCount: 0,
    isFirstRun: false,
  );

  bool get hasHighlights =>
      placements.isNotEmpty || longestOfMonth || fastestOfMonth || isFirstRun;

  /// Monday 00:00 of the week containing [date] (local).
  static DateTime weekStart(DateTime date) {
    final local = date.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  /// [ranking]: every completed outdoor run (see
  /// `RunRepository.listActivitiesForRanking`). [recent]: running activities
  /// (outdoor + treadmill) from at least the start of the run's week and
  /// month. Both may contain [draft]; it is ignored there.
  /// [distanceMeters] overrides the draft distance for indoor sessions whose
  /// distance is typed in during the review.
  static RunReviewInsights compute({
    required RunActivity draft,
    required List<RunActivity> ranking,
    required List<RunActivity> recent,
    double? distanceMeters,
  }) {
    final meters = distanceMeters ?? draft.distanceMeters;

    final others = [
      for (final activity in recent)
        if (activity.id != draft.id && activity.isCompleted) activity,
    ];

    final placements = draft.isRun
        ? RunAchievementEngine.build([
            ...ranking.where((a) => a.id != draft.id),
            draft,
          ]).forActivity(draft.id)
        : const <RunAchievementPlacement>[];

    final started = draft.startedAt.toLocal();
    final weekBegin = weekStart(started);
    final weekEnd = weekBegin.add(const Duration(days: 7));
    var weekMeters = meters;
    var weekRuns = 1;
    for (final activity in others) {
      final at = activity.startedAt.toLocal();
      if (!at.isBefore(weekBegin) && at.isBefore(weekEnd)) {
        weekMeters += activity.distanceMeters;
        weekRuns++;
      }
    }

    final monthRuns = [
      for (final activity in others)
        if (activity.startedAt.toLocal().year == started.year &&
            activity.startedAt.toLocal().month == started.month)
          activity,
    ];
    var longest = false;
    var fastest = false;
    if (monthRuns.isNotEmpty) {
      longest = meters > 0 && monthRuns.every((a) => a.distanceMeters < meters);
      final pace = draft.avgPaceSecPerKm;
      if (draft.isRun &&
          pace != null &&
          pace > 0 &&
          draft.distanceMeters >= RunAchievementEngine.minPaceDistanceMeters) {
        final comparable = [
          for (final a in monthRuns)
            if (a.isRun &&
                a.avgPaceSecPerKm != null &&
                a.avgPaceSecPerKm! > 0 &&
                a.distanceMeters >= RunAchievementEngine.minPaceDistanceMeters)
              a.avgPaceSecPerKm!,
        ];
        fastest = comparable.isNotEmpty && comparable.every((p) => pace < p);
      }
    }

    return RunReviewInsights(
      placements: placements,
      longestOfMonth: longest,
      fastestOfMonth: fastest,
      weekMeters: weekMeters,
      weekRunCount: weekRuns,
      isFirstRun: others.isEmpty && ranking.every((a) => a.id == draft.id),
    );
  }
}
