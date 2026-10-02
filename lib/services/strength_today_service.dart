import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/models/periodization_target.dart';
import 'package:workout_notes/models/strength_workout_summary.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';
import 'package:workout_notes/repositories/strength_repository.dart';
import 'package:workout_notes/utils/date_utils.dart';

/// `app_settings` key of the weekly session goal the lifter set by hand.
const String kStrengthWeeklyGoalSettingKey = 'strength_weekly_goal_sessions';

enum StrengthTodayStatus {
  /// A routine day is suggested for today.
  planned,

  /// A gym workout was already finished today.
  done,

  /// The plan's template week has no strength session today.
  rest,

  /// There is no routine to suggest.
  none,
}

class StrengthTodayInfo {
  final StrengthTodayStatus status;
  final DateTime date;

  /// Today's suggested day ([StrengthTodayStatus.planned]).
  final StrengthRoutineDayInfo? day;

  /// The workout finished today ([StrengthTodayStatus.done]).
  final StrengthWorkoutSummary? doneWorkout;

  /// The next suggested day, for rest and finished days.
  final StrengthRoutineDayInfo? next;

  /// When [next] is expected (rest days), null when unknown.
  final DateTime? nextDate;

  /// The suggestion comes from the planning phase rather than the routines.
  final bool fromPlan;

  const StrengthTodayInfo({
    required this.status,
    required this.date,
    this.day,
    this.doneWorkout,
    this.next,
    this.nextDate,
    this.fromPlan = false,
  });

  /// The routine day a "Treinar" button should start: today's, else the
  /// next one.
  StrengthRoutineDayInfo? get startDay => day ?? next;
}

/// Everything the gym hub needs from routines and the planning phase.
class StrengthHomeSnapshot {
  final StrengthTodayInfo today;

  /// Sessions per week targeted by the active phase.
  final int? planSessionsPerWeek;
  final int? planMinSetsPerWeek;
  final int? planMaxSetsPerWeek;

  /// ISO weekdays (1 = Monday) with a strength session in the template week.
  final List<int> plannedStrengthDays;

  /// Weekly session goal set by hand.
  final int? userWeeklyGoalSessions;
  final List<StrengthUpcomingWorkout> upcoming;
  final bool hasRoutines;

  const StrengthHomeSnapshot({
    required this.today,
    this.planSessionsPerWeek,
    this.planMinSetsPerWeek,
    this.planMaxSetsPerWeek,
    this.plannedStrengthDays = const [],
    this.userWeeklyGoalSessions,
    this.upcoming = const [],
    this.hasRoutines = false,
  });
}

/// Pure decision logic, kept apart from the repositories for plain tests.
abstract final class StrengthTodayResolver {
  /// The day after [lastDayId] in [days] (already ordered), wrapping around.
  /// Without a known last day, [fallbackIndex] (modulo the length) or the
  /// first day is used.
  static StrengthRoutineDayRef? nextDayAfter(
    List<StrengthRoutineDayRef> days,
    String? lastDayId, {
    int? fallbackIndex,
  }) {
    if (days.isEmpty) return null;
    final at = lastDayId == null
        ? -1
        : days.indexWhere((d) => d.dayId == lastDayId);
    if (at >= 0) return days[(at + 1) % days.length];
    return days[(fallbackIndex ?? 0) % days.length];
  }

  /// First date after [today] (within a week) whose ISO weekday is in
  /// [strengthDays]; null when the list is empty.
  static DateTime? nextStrengthDate(DateTime today, List<int> strengthDays) {
    if (strengthDays.isEmpty) return null;
    final day = dayOf(today);
    for (var i = 1; i <= 7; i++) {
      final date = addDays(day, i);
      if (strengthDays.contains(date.weekday)) return date;
    }
    return null;
  }

  /// Decides what today looks like: a finished workout wins, then a rest
  /// day of the template week, then the suggested day, then "no routine".
  static StrengthTodayStatus status({
    required DateTime today,
    required bool doneToday,
    required bool hasSuggestion,
    List<int> plannedStrengthDays = const [],
  }) {
    if (doneToday) return StrengthTodayStatus.done;
    if (plannedStrengthDays.isNotEmpty &&
        !plannedStrengthDays.contains(dayOf(today).weekday)) {
      return StrengthTodayStatus.rest;
    }
    return hasSuggestion
        ? StrengthTodayStatus.planned
        : StrengthTodayStatus.none;
  }
}

/// Loads [StrengthHomeSnapshot] from the repositories.
class StrengthTodayService {
  final StrengthRepository _repo;

  StrengthTodayService({StrengthRepository? repo})
    : _repo = repo ?? DatabaseHelper.instance.strengthRepo;

  Future<StrengthHomeSnapshot> load({
    DateTime? now,
    List<StrengthWorkoutSummary>? finished,
  }) async {
    final clock = now ?? DateTime.now();
    final day = dayOf(clock);
    final helper = DatabaseHelper.instance;

    final todayWorkouts =
        (finished ?? await _repo.loadFinishedWorkouts(from: day, to: day))
            .where((w) => w.date == day)
            .toList();
    final doneToday = todayWorkouts.isEmpty ? null : todayWorkouts.first;

    final dayPlan = await _safe(helper.periodizationRepo.getDayPlan(day));
    final target = dayPlan?.target;
    final plannedDays = <int>[
      if (dayPlan != null)
        for (final d in dayPlan.week)
          if (d.strength) d.weekday,
    ];

    final suggestion = await _safe(
      helper.periodizationRepo.getRoutineSuggestion(day),
    );
    String? dayId = suggestion?.routineDayId;
    final fromPlan = dayId != null;
    dayId ??= await _safe<String?>(_fallbackDayId());
    final info = dayId == null
        ? null
        : await _safe(_repo.loadRoutineDayInfo(dayId));

    final status = StrengthTodayResolver.status(
      today: day,
      doneToday: doneToday != null,
      hasSuggestion: info != null,
      plannedStrengthDays: plannedDays,
    );
    final today = switch (status) {
      StrengthTodayStatus.planned => StrengthTodayInfo(
        status: status,
        date: day,
        day: info,
        fromPlan: fromPlan,
      ),
      StrengthTodayStatus.done => StrengthTodayInfo(
        status: status,
        date: day,
        doneWorkout: doneToday,
        next: info,
        fromPlan: fromPlan,
      ),
      StrengthTodayStatus.rest => StrengthTodayInfo(
        status: status,
        date: day,
        next: info,
        nextDate: StrengthTodayResolver.nextStrengthDate(day, plannedDays),
        fromPlan: fromPlan,
      ),
      StrengthTodayStatus.none => StrengthTodayInfo(status: status, date: day),
    };

    return StrengthHomeSnapshot(
      today: today,
      planSessionsPerWeek: target?.sessionsPerWeek,
      planMinSetsPerWeek: target?.minSetsPerWeek,
      planMaxSetsPerWeek: target?.maxSetsPerWeek,
      plannedStrengthDays: plannedDays,
      userWeeklyGoalSessions: await readWeeklyGoalSessions(),
      upcoming: await _safe(_repo.loadUpcoming(after: day)) ?? const [],
      hasRoutines: await _repo.routineCount() > 0,
    );
  }

  /// Without a planning suggestion: the day after the one last trained from
  /// the most recently used routine (or the first day of the newest routine).
  Future<String?> _fallbackDayId() async {
    final last = await _repo.lastRoutineUse();
    final routineId = last?.routineId ?? await _repo.firstRoutineWithDays();
    if (routineId == null) return null;
    final days = await _repo.routineDays(routineId);
    final next = StrengthTodayResolver.nextDayAfter(
      days,
      last?.routineDayId,
      // Older workouts do not record their day: rotate by session count.
      fallbackIndex: last?.routineDayId == null && last != null
          ? await _repo.routineSessionCount(routineId)
          : null,
    );
    return next?.dayId;
  }

  /// The weekly session goal the lifter set by hand, or null.
  Future<int?> readWeeklyGoalSessions() async {
    final raw = await DatabaseHelper.instance.settingsRepo.getSetting(
      kStrengthWeeklyGoalSettingKey,
    );
    final sessions = int.tryParse((raw ?? '').trim());
    if (sessions == null || sessions <= 0) return null;
    return sessions;
  }

  /// Saves the weekly session goal; null or non-positive clears it.
  Future<void> setWeeklyGoalSessions(int? sessions) async {
    await DatabaseHelper.instance.settingsRepo.setSetting(
      kStrengthWeeklyGoalSettingKey,
      sessions == null || sessions <= 0 ? '' : '$sessions',
    );
  }

  /// Reads that must never take the whole hub down: planning tables may not
  /// exist on old databases and a failed lookup just hides that piece.
  Future<T?> _safe<T>(Future<T> future) async {
    try {
      return await future;
    } catch (_) {
      return null;
    }
  }
}

/// Plan-derived numbers for tests and widgets.
extension StrengthTargetSessions on PeriodizationTarget {
  /// Sessions per week the target asks for, falling back to the number of
  /// planned strength days.
  int? get sessionsPerWeek =>
      workoutsPerWeek ?? (strengthDays.isEmpty ? null : strengthDays.length);
}
