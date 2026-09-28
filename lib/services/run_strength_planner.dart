import 'package:workout_notes/models/run_plan.dart';
import 'package:workout_notes/models/run_plan_workout.dart';

/// One running session as the strength planner sees it.
typedef RunStrengthSession = ({int day, RunWorkoutKind kind, double km});

/// Picks the weekdays for runner-specific strength work around a week of
/// running.
///
/// Strength is what most reduces injury in recreational runners, but it must
/// not blunt the sessions that build fitness. The rules a coach applies:
/// - never on the long-run, race or test day, and never the day before a
///   hard day (legs arrive heavy);
/// - preferably after an easy run (keeps rest days as rest), else a rest day;
///   when the week has no such day left, after a quality session on the same
///   day ("keep hard days hard") rather than squeezing it in before one;
/// - two sessions at least two days apart; one in the week before a race and
///   none in race week.
abstract final class RunStrengthPlanner {
  static const _hard = {
    RunWorkoutKind.interval,
    RunWorkoutKind.tempo,
    RunWorkoutKind.fartlek,
    RunWorkoutKind.hills,
    RunWorkoutKind.progression,
    RunWorkoutKind.race,
    RunWorkoutKind.test,
  };

  /// Weekdays (ISO, sorted) for strength this week.
  static List<int> daysFor(
    List<RunStrengthSession> sessions, {
    bool raceWeek = false,
    bool weekBeforeRace = false,
  }) {
    if (raceWeek || sessions.isEmpty) return const [];
    final count = weekBeforeRace ? 1 : 2;
    final longest = sessions.fold<double>(0, (m, s) => s.km > m ? s.km : m);
    // The long run, a race or a time trial: the day must stay untouched.
    final keyDays = <int>{
      for (final s in sessions)
        if (s.kind == RunWorkoutKind.race ||
            s.kind == RunWorkoutKind.test ||
            (s.km >= longest && longest > 0))
          s.day,
    };
    final hardDays = <int>{
      ...keyDays,
      for (final s in sessions)
        if (_hard.contains(s.kind)) s.day,
    };
    final runDays = {for (final s in sessions) s.day};

    int score(int day) {
      if (keyDays.contains(day)) return -1000;
      // After a quality session on the same day ("hard days hard") is the
      // fallback when the week has no free easy day left.
      if (hardDays.contains(day)) return -300;
      final next = day % 7 + 1;
      var value = 0;
      if (hardDays.contains(next)) value -= 500;
      value += runDays.contains(day) ? 20 : 10;
      // A little room after a hard day recovers better than straight after.
      final previous = (day + 5) % 7 + 1;
      if (hardDays.contains(previous)) value -= 3;
      return value;
    }

    // Few enough combinations to try them all: greedily taking the best
    // single day first can leave no acceptable partner for the second.
    List<int>? best;
    var bestScore = -1 << 30;
    void consider(List<int> days) {
      var total = 0;
      for (final day in days) {
        total += score(day);
      }
      for (var i = 0; i < days.length; i++) {
        for (var j = i + 1; j < days.length; j++) {
          final gap = (days[i] - days[j]).abs();
          if ((gap > 3 ? 7 - gap : gap) < 2) total -= 400;
        }
      }
      if (total > bestScore) {
        bestScore = total;
        best = days;
      }
    }

    for (var a = 1; a <= 7; a++) {
      if (count == 1) {
        consider([a]);
        continue;
      }
      for (var b = a + 1; b <= 7; b++) {
        consider([a, b]);
      }
    }
    // Nothing acceptable (e.g. a hard session every day): no strength.
    if (best == null || bestScore <= -400 * count) return const [];
    return best!;
  }

  /// Strength days for week [weekIndex] of a stored plan.
  static List<int> daysForPlanWeek(RunPlan plan, int weekIndex) {
    bool hasRace(int week) =>
        plan.workoutsForWeek(week).any((w) => w.kind == RunWorkoutKind.race);
    return daysFor(
      [
        for (final w in plan.workoutsForWeek(weekIndex))
          if (w.dayOfWeek != null)
            (
              day: w.dayOfWeek!,
              kind: w.kind,
              km: w.plannedDistanceMeters / 1000,
            ),
      ],
      raceWeek: hasRace(weekIndex),
      weekBeforeRace: weekIndex + 1 < plan.weeks && hasRace(weekIndex + 1),
    );
  }
}
