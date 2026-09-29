import 'package:workout_notes/models/run_plan.dart';
import 'package:workout_notes/models/run_plan_ledger.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/models/scheduled_run.dart';

/// Where a plan session stands today.
enum RunSessionState {
  /// Still ahead (or today), not run yet.
  planned,

  /// A recorded run completed it.
  done,

  /// Its day has passed and it was not run.
  missed,

  /// Explicitly skipped from the calendar.
  skipped,
}

/// A plan session together with its date and state.
class RunPlanSessionView {
  final RunPlanWorkout workout;
  final RunSessionState state;

  /// Calendar date of the session; null for a plan that is not being followed
  /// (or a session with no fixed weekday).
  final DateTime? date;
  final RunPlanLedgerEntry? ledger;

  const RunPlanSessionView({
    required this.workout,
    required this.state,
    required this.date,
    required this.ledger,
  });

  bool isToday(DateTime today) => date != null && _sameDay(date!, today);
}

/// Pure helpers that turn a plan and its ledger into what the plan detail
/// screen shows: real dates per weekday, one state per session and planned
/// versus done kilometres per week.
abstract final class RunPlanWeekView {
  static DateTime day(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static DateTime monday(DateTime value) {
    final d = day(value);
    return DateTime(d.year, d.month, d.day - (d.weekday - 1));
  }

  /// Monday of plan week [week], or null when the plan is not followed.
  ///
  /// Repeating plans wrap: the week shown is the one in the cycle running on
  /// [today] ([cycleShift] `1` gives the next cycle).
  static DateTime? weekStart(
    RunPlan plan,
    int week,
    DateTime today, {
    int cycleShift = 0,
  }) {
    final anchor = plan.activatedAt;
    if (anchor == null || plan.weeks < 1) return null;
    final anchorMonday = monday(anchor);
    var offset = week;
    if (plan.repeats) {
      final elapsed = monday(today).difference(anchorMonday).inDays ~/ 7;
      final cycle = elapsed < 0 ? 0 : elapsed ~/ plan.weeks;
      offset = (cycle + cycleShift) * plan.weeks + week;
    }
    return DateTime(
      anchorMonday.year,
      anchorMonday.month,
      anchorMonday.day + 7 * offset,
    );
  }

  static DateTime? dateFor(
    RunPlan plan,
    int week,
    int? dayOfWeek,
    DateTime today, {
    int cycleShift = 0,
  }) {
    if (dayOfWeek == null) return null;
    final start = weekStart(plan, week, today, cycleShift: cycleShift);
    if (start == null) return null;
    return DateTime(start.year, start.month, start.day + dayOfWeek - 1);
  }

  /// State of one session. [date] is its scheduled date (null: unknown).
  static RunSessionState stateFor({
    required RunPlanLedgerEntry? ledger,
    required DateTime? date,
    required DateTime today,
  }) {
    switch (ledger?.status) {
      case ScheduledRunStatus.completed:
        return RunSessionState.done;
      case ScheduledRunStatus.skipped:
        return RunSessionState.skipped;
      case ScheduledRunStatus.planned:
      case null:
        return date != null && day(date).isBefore(day(today))
            ? RunSessionState.missed
            : RunSessionState.planned;
    }
  }

  /// Session views of [week], in weekday order.
  static List<RunPlanSessionView> sessionsForWeek(
    RunPlan plan,
    int week,
    Map<String, RunPlanLedgerEntry> ledger,
    DateTime today, {
    int cycleShift = 0,
  }) {
    final start = weekStart(plan, week, today, cycleShift: cycleShift);
    return [
      for (final workout in plan.workoutsForWeek(week))
        _view(plan, workout, week, start, ledger, today, cycleShift),
    ];
  }

  static RunPlanSessionView _view(
    RunPlan plan,
    RunPlanWorkout workout,
    int week,
    DateTime? start,
    Map<String, RunPlanLedgerEntry> ledger,
    DateTime today,
    int cycleShift,
  ) {
    var entry = ledger[workout.id];
    final planned = dateFor(
      plan,
      week,
      workout.dayOfWeek,
      today,
      cycleShift: cycleShift,
    );
    // A repeating plan reuses its sessions every cycle: only a ledger row that
    // falls inside the week shown says anything about this cycle.
    if (entry != null && plan.repeats && start != null) {
      final at = entry.date;
      final end = DateTime(start.year, start.month, start.day + 6);
      if (at == null || day(at).isBefore(start) || day(at).isAfter(end)) {
        entry = null;
      }
    }
    // Rescheduled sessions keep their own calendar date.
    final date = entry != null && !entry.isCompleted && entry.date != null
        ? day(entry.date!)
        : planned;
    return RunPlanSessionView(
      workout: workout,
      state: stateFor(ledger: entry, date: date, today: today),
      date: date,
      ledger: entry,
    );
  }

  /// Kilometres actually run for the sessions of [week] (plan sessions only).
  static double doneMeters(
    RunPlan plan,
    int week,
    Map<String, RunPlanLedgerEntry> ledger,
  ) {
    var total = 0.0;
    for (final workout in plan.workoutsForWeek(week)) {
      final entry = ledger[workout.id];
      if (entry == null || !entry.isCompleted) continue;
      total += entry.actualDistanceMeters ?? workout.plannedDistanceMeters;
    }
    return total;
  }

  /// Today's session, or the next one still to run, for a followed plan.
  /// Missed sessions are never suggested: the day for them has passed.
  static RunPlanSessionView? nextSession(
    RunPlan plan,
    Map<String, RunPlanLedgerEntry> ledger,
    DateTime today,
  ) {
    if (!plan.isActivated || plan.isFinishedOn(today)) return null;
    RunPlanSessionView? best;
    final cycles = plan.repeats ? const [0, 1] : const [0];
    for (final shift in cycles) {
      for (var week = 0; week < plan.weeks; week++) {
        for (final view in sessionsForWeek(
          plan,
          week,
          ledger,
          today,
          cycleShift: shift,
        )) {
          final date = view.date;
          if (date == null || view.state != RunSessionState.planned) continue;
          if (day(date).isBefore(day(today))) continue;
          if (best == null || date.isBefore(best.date!)) best = view;
        }
      }
      if (best != null) break;
    }
    return best;
  }
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
