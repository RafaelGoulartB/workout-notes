import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/models/periodization_run_suggestion.dart';
import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/models/run_plan.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/models/scheduled_run.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';
import 'package:workout_notes/repositories/run_plan_repository.dart';
import 'package:workout_notes/repositories/run_repository.dart';
import 'package:workout_notes/utils/date_utils.dart';

/// `app_settings` key of the weekly distance goal the runner set by hand.
const String kRunWeeklyGoalSettingKey = 'run_weekly_goal_km';

enum RunTodayStatus {
  /// A planned session is waiting for today.
  planned,

  /// Something was already run today.
  done,

  /// A plan is followed but nothing is due today.
  rest,

  /// No plan at all.
  none,
}

/// A planned session together with the date it falls on.
class RunPlannedSession {
  final DateTime date;
  final RunPlanWorkout workout;
  final ScheduledRun? scheduled;
  final String? planName;

  const RunPlannedSession({
    required this.date,
    required this.workout,
    this.scheduled,
    this.planName,
  });
}

class RunTodayInfo {
  final RunTodayStatus status;
  final DateTime date;

  /// Today's planned session ([RunTodayStatus.planned]) or the plan session
  /// that was completed ([RunTodayStatus.done]).
  final RunPlannedSession? session;

  /// The run recorded today ([RunTodayStatus.done]).
  final RunActivity? doneActivity;

  /// Next planned session after today, for rest days and finished days.
  final RunPlannedSession? next;

  const RunTodayInfo({
    required this.status,
    required this.date,
    this.session,
    this.doneActivity,
    this.next,
  });
}

enum RunPlannedDayState {
  /// Still ahead (or today) and not run yet.
  pending,
  done,

  /// Planned for a past day and never run.
  missed,
  skipped,
}

/// A plan session on a day of the current week, for the week strip.
class RunPlannedDay {
  final DateTime date;
  final RunWorkoutKind kind;
  final String name;
  final double plannedMeters;
  final RunPlannedDayState state;

  const RunPlannedDay({
    required this.date,
    required this.kind,
    required this.name,
    required this.plannedMeters,
    required this.state,
  });
}

/// The followed plan seen from today, for the plan card and the weekly goal.
class RunPlanContext {
  final RunPlan plan;

  /// Zero-based week of the plan today falls in; null when the plan has not
  /// started yet or is over.
  final int? weekIndex;
  final RunPlanProgress progress;

  const RunPlanContext({
    required this.plan,
    required this.weekIndex,
    required this.progress,
  });

  int? get weekNumber => weekIndex == null ? null : weekIndex! + 1;

  double? get weekPlannedMeters {
    final index = weekIndex;
    if (index == null) return null;
    final meters = plan.weeklyDistanceMeters(index);
    return meters > 0 ? meters : null;
  }
}

/// Everything the running home needs from the plans and the calendar.
class RunHomeSnapshot {
  final RunTodayInfo today;
  final RunPlanContext? plan;

  /// Sessions planned for Monday to Sunday of the current week.
  final List<RunPlannedDay> weekPlan;

  /// Weekly goal set by hand, in meters.
  final double? userWeeklyGoalMeters;

  /// Next planned session after today, whatever today looks like.
  final RunPlannedSession? nextSession;

  const RunHomeSnapshot({
    required this.today,
    required this.plan,
    required this.weekPlan,
    required this.userWeeklyGoalMeters,
    this.nextSession,
  });
}

enum RunWeekGoalSource { plan, user, average }

/// The distance the runner is aiming for this week and where it comes from.
class RunWeekGoal {
  final double meters;
  final RunWeekGoalSource source;

  const RunWeekGoal(this.meters, this.source);

  /// Plan week first, then the goal set by hand, then the weekly average of
  /// the selected period. Null when none of them is above zero.
  static RunWeekGoal? resolve({
    double? planMeters,
    double? userMeters,
    double? averageMeters,
  }) {
    if (planMeters != null && planMeters > 0) {
      return RunWeekGoal(planMeters, RunWeekGoalSource.plan);
    }
    if (userMeters != null && userMeters > 0) {
      return RunWeekGoal(userMeters, RunWeekGoalSource.user);
    }
    if (averageMeters != null && averageMeters > 0) {
      return RunWeekGoal(averageMeters, RunWeekGoalSource.average);
    }
    return null;
  }
}

/// Pure decision logic, kept apart from the repositories so it can be tested
/// with plain fixtures.
abstract final class RunTodayResolver {
  /// Decides what today looks like.
  ///
  /// Priority: a pending scheduled session; a completed one; skipped rows
  /// (rest); the periodization suggestion; a session read straight from the
  /// followed plan when the calendar was never materialised; a free run
  /// already recorded today; then rest or "no plan".
  static RunTodayInfo resolve({
    required DateTime today,
    List<ScheduledRun> scheduledToday = const [],
    PeriodizationRunSuggestion? suggestion,
    RunPlan? followedPlan,
    List<ScheduledRun> upcoming = const [],
    List<RunActivity> todayActivities = const [],
    RunPlannedSession? nextFromSuggestions,
    String? Function(String? planId)? planNameOf,
  }) {
    final day = dayOf(today);
    final rows = scheduledToday.where((s) => s.workout != null).toList();
    final ranToday =
        todayActivities
            .where(
              (a) => a.isCompleted && isSameDay(a.startedAt.toLocal(), day),
            )
            .toList()
          ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

    RunPlannedSession sessionOf(ScheduledRun row) => RunPlannedSession(
      date: day,
      workout: row.workout!,
      scheduled: row,
      planName: planNameOf?.call(row.runPlanId),
    );

    RunPlannedSession? nextSession() => next(
      today: day,
      upcoming: upcoming,
      followedPlan: followedPlan,
      fromSuggestions: nextFromSuggestions,
      planNameOf: planNameOf,
    );

    RunTodayInfo rest() {
      final upcomingSession = nextSession();
      final hasPlan =
          followedPlan != null ||
          suggestion != null ||
          rows.isNotEmpty ||
          upcomingSession != null;
      return RunTodayInfo(
        status: hasPlan ? RunTodayStatus.rest : RunTodayStatus.none,
        date: day,
        next: upcomingSession,
      );
    }

    final pending = rows.where((s) => s.isPlanned).toList();
    if (pending.isNotEmpty) {
      return RunTodayInfo(
        status: RunTodayStatus.planned,
        date: day,
        session: sessionOf(pending.first),
      );
    }

    final completed = rows.where((s) => s.isCompleted).toList();
    if (completed.isNotEmpty) {
      final row = completed.first;
      final linked = ranToday
          .where((a) => a.id == row.runActivityId)
          .firstOrNull;
      return RunTodayInfo(
        status: RunTodayStatus.done,
        date: day,
        session: sessionOf(row),
        doneActivity: linked ?? ranToday.firstOrNull,
        next: nextSession(),
      );
    }

    if (rows.isNotEmpty) {
      // Only skipped rows: the runner chose to skip, so today is a rest day.
      return rest();
    }

    if (suggestion != null && !suggestion.isSkipped) {
      final scheduled = suggestion.scheduled;
      final session = RunPlannedSession(
        date: day,
        workout: suggestion.workout,
        scheduled: scheduled,
        planName: suggestion.runPlanName,
      );
      if (suggestion.isCompleted) {
        return RunTodayInfo(
          status: RunTodayStatus.done,
          date: day,
          session: session,
          doneActivity: ranToday.firstOrNull,
          next: nextSession(),
        );
      }
      return RunTodayInfo(
        status: RunTodayStatus.planned,
        date: day,
        session: session,
      );
    }

    if (ranToday.isEmpty) {
      final fromPlan = _sessionFromPlan(day, followedPlan);
      if (fromPlan != null) {
        return RunTodayInfo(
          status: RunTodayStatus.planned,
          date: day,
          session: fromPlan,
        );
      }
    }

    if (ranToday.isNotEmpty) {
      return RunTodayInfo(
        status: RunTodayStatus.done,
        date: day,
        doneActivity: ranToday.first,
        next: nextSession(),
      );
    }
    return rest();
  }

  static RunPlannedSession? _sessionFromPlan(DateTime day, RunPlan? plan) {
    if (plan == null) return null;
    final week = plan.activeWeekIndexOn(day);
    if (week == null) return null;
    final match = plan
        .workoutsForWeek(week)
        .where((w) => w.dayOfWeek == day.weekday)
        .firstOrNull;
    if (match == null) return null;
    return RunPlannedSession(date: day, workout: match, planName: plan.name);
  }

  /// Next planned session after [today]: calendar rows first, then the plan
  /// definition, then the periodization look-ahead.
  static RunPlannedSession? next({
    required DateTime today,
    List<ScheduledRun> upcoming = const [],
    RunPlan? followedPlan,
    RunPlannedSession? fromSuggestions,
    String? Function(String? planId)? planNameOf,
  }) {
    final day = dayOf(today);
    return _nextFromUpcoming(day, upcoming, planNameOf) ??
        _nextFromPlan(day, followedPlan) ??
        fromSuggestions;
  }

  static RunPlannedSession? _nextFromUpcoming(
    DateTime day,
    List<ScheduledRun> upcoming,
    String? Function(String? planId)? planNameOf,
  ) {
    final future =
        upcoming
            .where(
              (s) =>
                  s.isPlanned &&
                  s.workout != null &&
                  dayOf(s.date).isAfter(day),
            )
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    if (future.isEmpty) return null;
    final row = future.first;
    return RunPlannedSession(
      date: dayOf(row.date),
      workout: row.workout!,
      scheduled: row,
      planName: planNameOf?.call(row.runPlanId),
    );
  }

  /// Next session read from the plan definition, scanning [horizonDays] days.
  static RunPlannedSession? _nextFromPlan(
    DateTime day,
    RunPlan? plan, {
    int horizonDays = 14,
  }) {
    if (plan == null) return null;
    for (var i = 1; i <= horizonDays; i++) {
      final date = addDays(day, i);
      final session = _sessionFromPlan(date, plan);
      if (session != null) return session;
    }
    return null;
  }

  /// Monday-to-Sunday plan sessions for the strip. Calendar rows win; when
  /// the week was never materialised the followed plan supplies them.
  static List<RunPlannedDay> weekPlan({
    required DateTime today,
    required List<ScheduledRun> scheduledThisWeek,
    RunPlan? followedPlan,
  }) {
    final day = dayOf(today);
    final rows = scheduledThisWeek.where((s) => s.workout != null).toList();
    if (rows.isNotEmpty) {
      return [
        for (final row in rows)
          RunPlannedDay(
            date: dayOf(row.date),
            kind: row.workout!.kind,
            name: row.workout!.name,
            plannedMeters: row.workout!.plannedDistanceMeters,
            state: switch (row.status) {
              ScheduledRunStatus.completed => RunPlannedDayState.done,
              ScheduledRunStatus.skipped => RunPlannedDayState.skipped,
              ScheduledRunStatus.planned =>
                dayOf(row.date).isBefore(day)
                    ? RunPlannedDayState.missed
                    : RunPlannedDayState.pending,
            },
          ),
      ];
    }
    final plan = followedPlan;
    final week = plan?.activeWeekIndexOn(day);
    if (plan == null || week == null) return const [];
    final monday = mondayOf(day);
    return [
      for (final workout in plan.workoutsForWeek(week))
        if (workout.dayOfWeek != null)
          () {
            final date = addDays(monday, workout.dayOfWeek! - 1);
            return RunPlannedDay(
              date: date,
              kind: workout.kind,
              name: workout.name,
              plannedMeters: workout.plannedDistanceMeters,
              state: date.isBefore(day)
                  ? RunPlannedDayState.missed
                  : RunPlannedDayState.pending,
            );
          }(),
    ];
  }

  /// Marks pending/missed plan days as done when a run was recorded that
  /// day, so a free run on a planned day still fills the strip.
  static List<RunPlannedDay> reconcileWithRuns(
    List<RunPlannedDay> plan,
    List<RunDayRuns> runsByDay,
  ) {
    return [
      for (final p in plan)
        if (p.state == RunPlannedDayState.missed &&
            runsByDay.any((r) => isSameDay(r.date, p.date) && r.count > 0))
          RunPlannedDay(
            date: p.date,
            kind: p.kind,
            name: p.name,
            plannedMeters: p.plannedMeters,
            state: RunPlannedDayState.done,
          )
        else
          p,
    ];
  }
}

/// Runs recorded on a day, used to reconcile the week plan.
class RunDayRuns {
  final DateTime date;
  final int count;

  const RunDayRuns(this.date, this.count);
}

/// Loads [RunHomeSnapshot] from the repositories.
class RunTodayService {
  final RunPlanRepository _planRepo;
  final RunRepository _runRepo;

  RunTodayService({RunPlanRepository? planRepo, RunRepository? runRepo})
    : _planRepo = planRepo ?? DatabaseHelper.instance.runPlanRepo,
      _runRepo = runRepo ?? DatabaseHelper.instance.runRepo;

  Future<RunHomeSnapshot> load({
    DateTime? now,
    List<RunActivity>? activities,
  }) async {
    final today = DateTime.now();
    final day = DateTime(
      (now ?? today).year,
      (now ?? today).month,
      (now ?? today).day,
    );
    final monday = mondayOf(day);
    final helper = DatabaseHelper.instance;

    final followed = await _safe(_planRepo.getActivatedPlan());
    final scheduledToday =
        await _safe(_planRepo.getScheduledRunsForDate(day)) ??
        const <ScheduledRun>[];
    final suggestion = await _safe(
      helper.periodizationRepo.getRunSuggestion(day),
    );
    final upcoming =
        await _safe(
          _planRepo.getScheduledRuns(addDays(day, 1), addDays(day, 28)),
        ) ??
        const <ScheduledRun>[];
    final weekRows =
        await _safe(_planRepo.getScheduledRuns(monday, addDays(monday, 6))) ??
        const <ScheduledRun>[];
    final all =
        activities ??
        await _runRepo.listActivities(
          limit: 30,
          activityTypes: RunRepository.runningTypes,
        );
    final todayActivities = all.where((a) {
      final d = a.startedAt.toLocal();
      return d.year == day.year && d.month == day.month && d.day == day.day;
    }).toList();

    // A planning-linked plan (no activation) still drives the plan card.
    RunPlan? contextPlan = followed;
    if (contextPlan == null && suggestion != null) {
      contextPlan = await _safe<RunPlan?>(
        _planRepo.getPlan(suggestion.runPlanId),
      );
    }
    String? nameOf(String? planId) =>
        planId != null && contextPlan?.id == planId ? contextPlan?.name : null;

    RunPlannedSession? next;
    final needsSuggestionLookahead =
        followed == null && upcoming.every((s) => !s.isPlanned);
    if (needsSuggestionLookahead && suggestion != null) {
      for (var i = 1; i <= 7 && next == null; i++) {
        final date = addDays(day, i);
        final future = await _safe(
          helper.periodizationRepo.getRunSuggestion(date),
        );
        if (future != null && !future.isSkipped && !future.isCompleted) {
          next = RunPlannedSession(
            date: date,
            workout: future.workout,
            scheduled: future.scheduled,
            planName: future.runPlanName,
          );
        }
      }
    }

    final info = RunTodayResolver.resolve(
      today: day,
      scheduledToday: scheduledToday,
      suggestion: suggestion,
      followedPlan: followed ?? contextPlan,
      upcoming: upcoming,
      todayActivities: todayActivities,
      nextFromSuggestions: next,
      planNameOf: nameOf,
    );

    RunPlanContext? planContext;
    if (contextPlan != null) {
      final progress =
          await _safe(_planRepo.getPlanProgress(contextPlan.id)) ??
          const RunPlanProgress();
      planContext = RunPlanContext(
        plan: contextPlan,
        weekIndex:
            contextPlan.activeWeekIndexOn(day) ??
            (followed == null ? suggestion?.weekIndex : null),
        progress: progress,
      );
    }

    final weekPlan = RunTodayResolver.reconcileWithRuns(
      RunTodayResolver.weekPlan(
        today: day,
        scheduledThisWeek: weekRows,
        followedPlan: followed ?? contextPlan,
      ),
      [
        for (var i = 0; i < 7; i++)
          RunDayRuns(
            addDays(monday, i),
            all.where((a) {
              final d = a.startedAt.toLocal();
              final date = addDays(monday, i);
              return d.year == date.year &&
                  d.month == date.month &&
                  d.day == date.day;
            }).length,
          ),
      ],
    );

    return RunHomeSnapshot(
      today: info,
      plan: planContext,
      weekPlan: weekPlan,
      userWeeklyGoalMeters: await readWeeklyGoalMeters(),
      nextSession: RunTodayResolver.next(
        today: day,
        upcoming: upcoming,
        followedPlan: followed ?? contextPlan,
        fromSuggestions: next,
        planNameOf: nameOf,
      ),
    );
  }

  /// The weekly goal the runner set by hand, or null.
  Future<double?> readWeeklyGoalMeters() async {
    final raw = await DatabaseHelper.instance.settingsRepo.getSetting(
      kRunWeeklyGoalSettingKey,
    );
    final km = double.tryParse((raw ?? '').replaceAll(',', '.'));
    if (km == null || km <= 0) return null;
    return km * 1000;
  }

  /// Saves the weekly goal in km; null or non-positive clears it.
  Future<void> setWeeklyGoalKm(double? km) async {
    await DatabaseHelper.instance.settingsRepo.setSetting(
      kRunWeeklyGoalSettingKey,
      km == null || km <= 0 ? '' : km.toString(),
    );
  }

  /// Reads that must never take the whole home down: the plan tables may not
  /// exist on old databases and a failed lookup just hides that card.
  Future<T?> _safe<T>(Future<T> future) async {
    try {
      return await future;
    } catch (_) {
      return null;
    }
  }
}
