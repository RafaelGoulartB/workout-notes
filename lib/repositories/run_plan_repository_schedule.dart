part of 'run_plan_repository.dart';

/// The dated schedule (materialised weeks, calendar rows) and per-step results.
extension RunPlanRepositorySchedule on RunPlanRepository {
  // ===================== SCHEDULE =====================

  Future<List<ScheduledRun>> getScheduledRuns(
    DateTime from,
    DateTime to, {
    bool hydrate = true,
  }) async {
    final database = await db;
    final rows = await database.query(
      'scheduled_runs',
      where: 'date >= ? AND date <= ?',
      whereArgs: [dateKey(from), dateKey(to)],
      orderBy: 'date ASC',
    );
    return _hydrateScheduled(database, rows, hydrate: hydrate);
  }

  Future<List<ScheduledRun>> getScheduledRunsForDate(DateTime date) async {
    final database = await db;
    final rows = await database.query(
      'scheduled_runs',
      where: 'date = ?',
      whereArgs: [dateKey(date)],
      orderBy: 'created_at ASC',
    );
    return _hydrateScheduled(database, rows);
  }

  Future<ScheduledRun?> getScheduledRun(String id) async {
    final database = await db;
    final rows = await database.query(
      'scheduled_runs',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final hydrated = await _hydrateScheduled(database, rows);
    return hydrated.first;
  }

  /// Materialises the sessions of [weekIndex] onto the calendar week starting
  /// at [weekStart]. Idempotent: rows already scheduled for the same
  /// plan session and date are left alone, so re-running never duplicates.
  /// Returns how many rows were created.
  /// Returns the ids of the rows it created, so a bulk caller can offer undo.
  Future<List<String>> materializeWeek({
    required String planId,
    required int weekIndex,
    required DateTime weekStart,
  }) async {
    final plan = await getPlan(planId);
    if (plan == null) return const [];
    final sessions = plan.workoutsForWeek(weekIndex);
    if (sessions.isEmpty) return const [];
    final monday = mondayOf(weekStart);
    final database = await db;
    final created = <String>[];
    await database.transaction((txn) async {
      for (final session in sessions) {
        final day = session.dayOfWeek ?? 1;
        final date = addDays(monday, day - 1);
        final existing = await txn.query(
          'scheduled_runs',
          columns: ['id'],
          where:
              'run_plan_workout_id = ? AND '
              '(date = ? OR status IN (?, ?))',
          whereArgs: [
            session.id,
            dateKey(date),
            ScheduledRunStatus.completed.value,
            ScheduledRunStatus.skipped.value,
          ],
          limit: 1,
        );
        if (existing.isNotEmpty) continue;
        final now = DateTime.now();
        final id = _uuid.v4();
        await txn.insert('scheduled_runs', {
          'id': id,
          'date': dateKey(date),
          'run_plan_id': planId,
          'run_plan_workout_id': session.id,
          'status': ScheduledRunStatus.planned.value,
          'notes': null,
          'run_activity_id': null,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        });
        created.add(id);
      }
    });
    return created;
  }

  Future<void> updateScheduledRun(
    String id, {
    DateTime? date,
    ScheduledRunStatus? status,
    Object? notes = _sentinel,
    Object? runActivityId = _sentinel,
  }) async {
    final database = await db;
    final updates = <String, dynamic>{
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (date != null) updates['date'] = dateKey(date);
    if (status != null) updates['status'] = status.value;
    if (!identical(notes, _sentinel)) {
      updates['notes'] = optionalText(notes as String?);
    }
    if (!identical(runActivityId, _sentinel)) {
      updates['run_activity_id'] = runActivityId as String?;
    }
    await database.update(
      'scheduled_runs',
      updates,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteScheduledRun(String id) async {
    final database = await db;
    await database.delete('scheduled_runs', where: 'id = ?', whereArgs: [id]);
  }

  /// Links a recorded activity to a scheduled run and marks it completed.
  Future<void> attachActivity({
    required String scheduledRunId,
    required String runActivityId,
  }) => updateScheduledRun(
    scheduledRunId,
    status: ScheduledRunStatus.completed,
    runActivityId: runActivityId,
  );

  // ===================== STEP RESULTS =====================

  Future<List<RunActivityStep>> getActivitySteps(String activityId) async {
    final database = await db;
    final rows = await database.query(
      'run_activity_steps',
      where: 'run_activity_id = ?',
      whereArgs: [activityId],
      orderBy: 'order_index ASC',
    );
    return rows.map(RunActivityStep.fromMap).toList();
  }

  /// Stores the per-step outcome of a finished run. Replaces any previous rows
  /// for the activity so a re-import stays idempotent.
  Future<void> saveActivitySteps(
    String activityId,
    List<RunActivityStep> steps,
  ) async {
    final database = await db;
    await database.transaction((txn) async {
      await txn.delete(
        'run_activity_steps',
        where: 'run_activity_id = ?',
        whereArgs: [activityId],
      );
      for (var i = 0; i < steps.length; i++) {
        await txn.insert('run_activity_steps', {
          ...steps[i].toMap(),
          'id': steps[i].id.isEmpty ? _uuid.v4() : steps[i].id,
          'run_activity_id': activityId,
          'order_index': i,
        });
      }
    });
  }

  Future<void> setActivityPlanWorkout({
    required String activityId,
    required String? planWorkoutId,
  }) async {
    final database = await db;
    await database.update(
      'run_activities',
      {
        'plan_workout_id': planWorkoutId,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [activityId],
    );
  }
}
