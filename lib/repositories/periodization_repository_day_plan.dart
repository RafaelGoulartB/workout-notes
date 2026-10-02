part of 'periodization_repository.dart';

/// Weekly targets resolved per date: the day plan, effective target and
/// target history.
extension PeriodizationRepositoryDayPlan on PeriodizationRepository {
  /// The effective target of each phase week (index 0 = first week), read
  /// at each week's start. Null entries are weeks without any target.
  Future<List<PeriodizationTarget?>> getWeeklyTargets(
    PeriodizationPhase phase,
  ) async => getWeeklyTargetsIn(await db, phase);

  /// [getWeeklyTargets] on an explicit executor.
  Future<List<PeriodizationTarget?>> getWeeklyTargetsIn(
    DatabaseExecutor database,
    PeriodizationPhase phase,
  ) async {
    final rows = await database.query(
      'phase_targets',
      where: 'phase_id = ?',
      whereArgs: [phase.id],
      orderBy: 'version DESC',
    );
    final history = rows.map(PeriodizationTarget.fromMap).toList();
    return [
      for (var week = 0; week < phase.totalWeeks; week++)
        history.isEmpty
            ? null
            : _targetForDate(history, addDays(phase.startDate, 7 * week)),
    ];
  }

  /// What the active plan expects on [date], or null outside any phase.
  Future<PeriodizationDayPlan?> getDayPlan(DateTime date) async {
    final day = dayOf(date);
    final phase = await getEffectivePhase(day);
    if (phase == null) return null;
    final target = await getEffectiveTarget(phase.id, date: day);
    return dayPlanFor(phase, target, day);
  }

  /// Resolves the template week of [phase] around [date] with [target].
  Future<PeriodizationDayPlan> dayPlanFor(
    PeriodizationPhase phase,
    PeriodizationTarget? target,
    DateTime date, {
    Map<String, RunPlan?>? runPlanCache,
  }) async {
    final day = dayOf(date);
    RunPlan? runPlan;
    int? runPlanWeek;
    final planId = target?.runPlanIds.firstOrNull;
    if (planId != null) {
      final cache = runPlanCache ?? <String, RunPlan?>{};
      if (!cache.containsKey(planId)) {
        cache[planId] = await DatabaseHelper.instance.runPlanRepo.getPlan(
          planId,
        );
      }
      runPlan = cache[planId];
      if (runPlan != null) {
        const resolver = RunPlanWeekResolver();
        runPlanWeek = resolver.planWeekFor(
          phaseWeek: resolver.phaseWeekOf(
            phaseStart: phase.startDate,
            date: day,
          ),
          planWeeks: runPlan.weeks,
          startWeek: target?.runPlanStartWeek ?? 0,
        );
      }
    }
    return PeriodizationDayPlan(
      phase: phase,
      target: target,
      weekNumber: phase.weekAt(day),
      totalWeeks: phase.totalWeeks,
      week: PhaseWeekPlan.build(
        target: target,
        runPlan: runPlan,
        runPlanWeek: runPlanWeek,
      ),
      runPlan: runPlan,
      runPlanWeek: runPlanWeek,
      date: day,
    );
  }

  /// Dates (`yyyy-MM-dd`) in [start]..[end] with a finished strength workout
  /// and with a completed run — what ticks days off in the week strips.
  Future<({Set<String> strength, Set<String> runs})> getActivityDates(
    DateTime start,
    DateTime end,
  ) async {
    final database = await db;
    final strengthRows = await database.rawQuery(
      '''
      SELECT DISTINCT date FROM workouts
      WHERE end_time IS NOT NULL AND date BETWEEN ? AND ?
      ''',
      [dateKey(start), dateKey(end)],
    );
    // `started_at >= day AND started_at < nextDay` matches the same rows as
    // comparing `date(started_at)` but can use the started_at indexes.
    final runRows = await database.rawQuery(
      '''
      SELECT DISTINCT date(started_at) AS day FROM run_activities
      WHERE status = 'completed' AND activity_type = 'running'
        AND started_at >= ? AND started_at < ?
      ''',
      [dateKey(start), _dayAfter(end)],
    );
    final runs = runRows.map((row) => row['day']).whereType<String>().toSet();
    return (
      strength: strengthRows
          .map((row) => (row['date'] as String?)?.substring(0, 10))
          .whereType<String>()
          .toSet(),
      runs: runs,
    );
  }

  Future<List<PeriodizationTarget>> getTargetHistory(String phaseId) async {
    final database = await db;
    final rows = await database.query(
      'phase_targets',
      where: 'phase_id = ?',
      whereArgs: [phaseId],
      orderBy: 'version DESC',
    );
    return rows.map(PeriodizationTarget.fromMap).toList();
  }

  Future<PeriodizationTarget?> getEffectiveTarget(
    String phaseId, {
    DateTime? date,
  }) async {
    final database = await db;
    final effectiveDate = dateKey(date ?? DateTime.now());
    final rows = await database.query(
      'phase_targets',
      where: 'phase_id = ? AND valid_from <= ?',
      whereArgs: [phaseId, effectiveDate],
      orderBy: 'valid_from DESC, version DESC',
      limit: 1,
    );
    if (rows.isNotEmpty) return PeriodizationTarget.fromMap(rows.first);
    return null;
  }
}
