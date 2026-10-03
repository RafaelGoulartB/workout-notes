part of 'periodization_repository.dart';

/// What to train today (routine / run) and scheduling a linked running plan.
extension PeriodizationRepositorySuggestions on PeriodizationRepository {
  /// Resolves the routine linked to the active phase on [date].
  ///
  /// The routines come from the effective weekly target (`routine_ids` inside
  /// `training_json`) — each phase week may carry its own routine sequence.
  Future<PeriodizationRoutineSuggestion?> getRoutineSuggestion(
    DateTime date,
  ) async {
    final day = dayOf(date);
    final phase = await getEffectivePhase(day);
    if (phase == null) return null;
    final database = await db;
    final target = await getEffectiveTarget(phase.id, date: day);
    final routineIds = target?.routineIds ?? const <String>[];
    if (routineIds.isNotEmpty) {
      final sequence =
          <
            ({
              String routineId,
              String routineName,
              String dayId,
              String dayName,
            })
          >[];
      // Two queries for every linked routine instead of two per routine.
      final routineRows = await database.query(
        'routines',
        columns: ['id', 'name'],
        where: 'id IN (${List.filled(routineIds.length, '?').join(', ')})',
        whereArgs: routineIds,
      );
      final routineNames = {
        for (final row in routineRows) row['id'] as String: row['name'],
      };
      final dayRows = await database.query(
        'routine_days',
        where:
            'routine_id IN (${List.filled(routineIds.length, '?').join(', ')})',
        whereArgs: routineIds,
        orderBy: 'order_index ASC',
      );
      final daysByRoutine = <String, List<Map<String, Object?>>>{};
      for (final row in dayRows) {
        daysByRoutine
            .putIfAbsent(row['routine_id'] as String, () => [])
            .add(row);
      }
      for (final routineId in routineIds) {
        final routineName = routineNames[routineId];
        if (routineName == null) continue;
        for (final routineDay
            in daysByRoutine[routineId] ?? const <Map<String, Object?>>[]) {
          sequence.add((
            routineId: routineId,
            routineName: routineName as String,
            dayId: routineDay['id'] as String,
            dayName: routineDay['name'] as String? ?? '',
          ));
        }
      }
      if (sequence.isEmpty) return null;
      final completed =
          Sqflite.firstIntValue(
            await database.rawQuery(
              '''
              SELECT COUNT(*) FROM workouts
              WHERE routine_id IN (${List.filled(routineIds.length, '?').join(', ')})
                AND end_time IS NOT NULL
                AND date BETWEEN ? AND ?
              ''',
              [
                ...routineIds,
                dateKey(
                  mondayOf(day).isBefore(phase.startDate)
                      ? phase.startDate
                      : mondayOf(day),
                ),
                dateKey(day),
              ],
            ),
          ) ??
          0;
      final index = completed % sequence.length;
      final nextDay = sequence[index];
      return PeriodizationRoutineSuggestion(
        phaseId: phase.id,
        routineId: nextDay.routineId,
        routineName: nextDay.routineName,
        routineDayId: nextDay.dayId,
        routineDayName: nextDay.dayName,
        routineDayIndex: index,
        routineDayCount: sequence.length,
        completedWorkouts: completed,
      );
    }
    return null;
  }

  /// Resolves the running session the plan expects on [date].
  ///
  /// Reads `run_plan_ids` from the effective weekly target, maps the date onto
  /// the plan week (phase week, wrapping when the plan is shorter than the
  /// phase) and picks the session whose `day_of_week` matches. Prefers an
  /// already-scheduled row so a rescheduled or skipped run is respected.
  Future<PeriodizationRunSuggestion?> getRunSuggestion(DateTime date) async {
    final day = dayOf(date);
    final phase = await getEffectivePhase(day);
    if (phase == null) return null;
    final target = await getEffectiveTarget(phase.id, date: day);
    final planIds = target?.runPlanIds ?? const <String>[];
    if (planIds.isEmpty) return null;

    final runPlanRepo = DatabaseHelper.instance.runPlanRepo;
    final weekStart = mondayOf(day);
    const resolver = RunPlanWeekResolver();
    final phaseWeekIndex = resolver.phaseWeekOf(
      phaseStart: phase.startDate,
      date: day,
    );

    // An already materialised row wins: it carries reschedules and skips.
    final scheduledToday = await runPlanRepo.getScheduledRunsForDate(day);
    for (final scheduled in scheduledToday) {
      final workout = scheduled.workout;
      if (workout == null || !planIds.contains(scheduled.runPlanId)) continue;
      final plan = await runPlanRepo.getPlan(workout.runPlanId);
      if (plan == null) continue;
      return PeriodizationRunSuggestion(
        phaseId: phase.id,
        runPlanId: plan.id,
        runPlanName: plan.name,
        weekIndex: workout.weekIndex,
        workout: workout,
        scheduled: scheduled,
        completedRunsThisWeek: await _completedRunsBetween(
          weekStart,
          addDays(weekStart, 6),
        ),
      );
    }

    for (final planId in planIds) {
      final plan = await runPlanRepo.getPlan(planId);
      if (plan == null || plan.weeks < 1) continue;
      // The offset says which plan week the phase's first week is; plans
      // shorter than the phase wrap, so a 1-week maintenance plan applies to
      // every week of the phase.
      final weekIndex = resolver.planWeekFor(
        phaseWeek: phaseWeekIndex,
        planWeeks: plan.weeks,
        startWeek: target?.runPlanStartWeek ?? 0,
      );
      if (weekIndex == null) continue;
      final sessions = plan.workoutsForWeek(weekIndex);
      final match = sessions.firstWhere(
        (session) => session.dayOfWeek == day.weekday,
        orElse: () => sessions.firstWhere(
          (session) => session.dayOfWeek == null,
          orElse: () => _missingRunWorkout,
        ),
      );
      if (identical(match, _missingRunWorkout)) continue;
      return PeriodizationRunSuggestion(
        phaseId: phase.id,
        runPlanId: plan.id,
        runPlanName: plan.name,
        weekIndex: weekIndex,
        workout: match,
        completedRunsThisWeek: await _completedRunsBetween(
          weekStart,
          addDays(weekStart, 6),
        ),
      );
    }
    return null;
  }

  /// Materialises the running plans linked to [phase] across its weeks, so the
  /// calendar carries every planned session instead of only today's suggestion.
  ///
  /// Each phase week resolves its own effective target, so a phase that swaps
  /// plans mid-way schedules the right plan per week. Weeks before [from]
  /// (default: this week) are skipped — back-filling would invent sessions the
  /// user never had a chance to run. Idempotent: existing rows are kept.
  Future<PeriodizationRunScheduleResult> scheduleRunPlanForPhase(
    PeriodizationPhase phase, {
    DateTime? from,
  }) async {
    const resolver = RunPlanWeekResolver();
    final runPlanRepo = DatabaseHelper.instance.runPlanRepo;
    final phaseStartWeek = mondayOf(phase.startDate);
    final fromWeek = mondayOf(dayOf(from ?? DateTime.now()));
    final firstWeek = fromWeek.isAfter(phaseStartWeek)
        ? resolver.phaseWeekOf(phaseStart: phase.startDate, date: fromWeek)
        : 0;
    // Plans are reused across weeks; loading each one once keeps a 30-week
    // phase from re-reading the same sessions thirty times.
    final plans = <String, RunPlan?>{};
    final created = <String>[];
    var weeksCovered = 0;
    for (var week = firstWeek; week < phase.totalWeeks; week++) {
      final weekStart = addDays(phaseStartWeek, 7 * week);
      final target = await getEffectiveTarget(phase.id, date: weekStart);
      final planIds = target?.runPlanIds ?? const <String>[];
      if (planIds.isEmpty) continue;
      var weekTouched = false;
      for (final planId in planIds) {
        if (!plans.containsKey(planId)) {
          plans[planId] = await runPlanRepo.getPlan(planId);
        }
        final plan = plans[planId];
        if (plan == null || plan.weeks < 1) continue;
        final planWeek = resolver.planWeekFor(
          phaseWeek: week,
          planWeeks: plan.weeks,
          startWeek: target?.runPlanStartWeek ?? 0,
        );
        if (planWeek == null) continue;
        created.addAll(
          await runPlanRepo.materializeWeek(
            planId: planId,
            weekIndex: planWeek,
            weekStart: weekStart,
          ),
        );
        weekTouched = true;
      }
      if (weekTouched) weeksCovered++;
    }
    return PeriodizationRunScheduleResult(
      createdIds: created,
      weeksCovered: weeksCovered,
    );
  }

  Future<int> _completedRunsBetween(DateTime start, DateTime end) async {
    final database = await db;
    return Sqflite.firstIntValue(
          await database.rawQuery(
            '''
            SELECT COUNT(*) FROM run_activities
            WHERE status = 'completed' AND activity_type = 'running'
              AND started_at >= ? AND started_at < ?
            ''',
            [dateKey(start), _dayAfter(end)],
          ),
        ) ??
        0;
  }
}

/// Sentinel for "no matching session" — `firstWhere` needs a non-null default.
final RunPlanWorkout _missingRunWorkout = RunPlanWorkout(
  id: '',
  runPlanId: '',
  weekIndex: -1,
  orderIndex: -1,
  kind: RunWorkoutKind.easy,
  name: '',
  createdAt: DateTime(2000),
);
