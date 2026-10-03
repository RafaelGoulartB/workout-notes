import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/utils/date_utils.dart';

/// A session as the week-balance check sees it.
class RunBalanceSession {
  final String id;
  final DateTime date;
  final RunWorkoutKind kind;
  final double km;

  /// Already run (or skipped): it cannot move, but it still counts.
  final bool fixed;

  RunBalanceSession({
    required this.id,
    required DateTime date,
    required this.kind,
    required this.km,
    this.fixed = false,
  }) : date = dayOf(date);

  RunBalanceSession movedTo(DateTime day) =>
      RunBalanceSession(id: id, date: day, kind: kind, km: km, fixed: fixed);
}

enum RunBalanceProblem {
  /// Two runs on the same day.
  sameDay,

  /// Two hard days (quality, long run, race, test) back to back.
  hardBackToBack,
}

class RunBalanceIssue {
  final RunBalanceProblem problem;

  /// The other session involved.
  final RunBalanceSession other;

  const RunBalanceIssue(this.problem, this.other);
}

/// What to do about a move that unbalances the week.
class RunMoveAdvice {
  final List<RunBalanceIssue> issues;

  /// A session on the target day whose day can be swapped with the moved
  /// one, leaving the week balanced.
  final RunBalanceSession? swapWith;

  /// The nearest day that keeps the week balanced, when there is one.
  final DateTime? betterDate;

  const RunMoveAdvice({this.issues = const [], this.swapWith, this.betterDate});

  bool get ok => issues.isEmpty;
}

/// Keeps hard and easy days alternating when a session is moved.
///
/// Moving a workout is normal life — the check only exists because the two
/// mistakes it catches are the ones that turn a good week into an injury:
/// two runs on one day, and two hard days in a row (a long run the day after
/// intervals). When a move causes either, it offers the fixes a coach would:
/// swap with the easy run on that day, or the nearest balanced day.
abstract final class RunWeekBalance {
  static const _hardKinds = {
    RunWorkoutKind.interval,
    RunWorkoutKind.tempo,
    RunWorkoutKind.fartlek,
    RunWorkoutKind.hills,
    RunWorkoutKind.progression,
    RunWorkoutKind.race,
    RunWorkoutKind.test,
    RunWorkoutKind.long,
  };

  static bool isHard(RunBalanceSession s, double longestKm) =>
      _hardKinds.contains(s.kind) || (longestKm > 0 && s.km >= longestKm);

  /// Problems [session] has with the rest of [week].
  static List<RunBalanceIssue> issuesFor(
    RunBalanceSession session,
    List<RunBalanceSession> week,
  ) {
    final others = week.where((s) => s.id != session.id).toList();
    final longest = [
      session,
      ...others,
    ].fold<double>(0, (m, s) => s.km > m ? s.km : m);
    final issues = <RunBalanceIssue>[];
    for (final other in others) {
      final gap = daysBetween(session.date, other.date).abs();
      if (gap == 0) {
        issues.add(RunBalanceIssue(RunBalanceProblem.sameDay, other));
      } else if (gap == 1 &&
          isHard(session, longest) &&
          isHard(other, longest)) {
        issues.add(RunBalanceIssue(RunBalanceProblem.hardBackToBack, other));
      }
    }
    return issues;
  }

  /// Advice for moving [movingId] to [to] within [week].
  ///
  /// [earliest] bounds the alternative day (no suggesting yesterday).
  static RunMoveAdvice adviseMove({
    required List<RunBalanceSession> week,
    required String movingId,
    required DateTime to,
    DateTime? earliest,
  }) {
    final moving = week.firstWhere((s) => s.id == movingId);
    final target = dayOf(to);
    List<RunBalanceSession> placed(RunBalanceSession s, DateTime day) => [
      for (final other in week)
        if (other.id == s.id) other.movedTo(day) else other,
    ];

    final after = placed(moving, target);
    final issues = issuesFor(moving.movedTo(target), after);
    if (issues.isEmpty) return const RunMoveAdvice();

    // Swap with the (movable) session already on that day, if the swap
    // leaves both of them clean.
    RunBalanceSession? swap;
    for (final other in week) {
      if (other.id == moving.id || other.fixed || other.date != target) {
        continue;
      }
      final swapped = [
        for (final s in week)
          if (s.id == moving.id)
            s.movedTo(target)
          else if (s.id == other.id)
            s.movedTo(moving.date)
          else
            s,
      ];
      final clean =
          issuesFor(moving.movedTo(target), swapped).isEmpty &&
          issuesFor(other.movedTo(moving.date), swapped).isEmpty;
      if (clean) {
        swap = other;
        break;
      }
    }

    // Nearest day in the same Monday–Sunday week that is clean.
    final monday = mondayOf(target);
    final floor = earliest == null ? null : dayOf(earliest);
    DateTime? better;
    var bestGap = 99;
    for (var i = 0; i < 7; i++) {
      final day = addDays(monday, i);
      if (day == target || day == moving.date) continue;
      if (floor != null && day.isBefore(floor)) continue;
      if (issuesFor(moving.movedTo(day), placed(moving, day)).isNotEmpty) {
        continue;
      }
      final gap = daysBetween(target, day).abs();
      if (gap < bestGap) {
        bestGap = gap;
        better = day;
      }
    }
    return RunMoveAdvice(issues: issues, swapWith: swap, betterDate: better);
  }
}
