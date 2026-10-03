part of 'run_plan_repository.dart';

RunPlanProgress _progressFrom(
  int total,
  Map<String, ScheduledRunStatus>? statuses,
) {
  int count(ScheduledRunStatus wanted) =>
      statuses?.values.where((status) => status == wanted).length ?? 0;
  return RunPlanProgress(
    totalSessions: total,
    completedSessions: count(ScheduledRunStatus.completed),
    skippedSessions: count(ScheduledRunStatus.skipped),
    plannedSessions: count(ScheduledRunStatus.planned),
  );
}

/// Ledger and batch reads: what was done per session, progress for many plans.
extension RunPlanRepositoryLedger on RunPlanRepository {
  // ===================== LEDGER / BATCH READS =====================

  static const _statusRank = {
    ScheduledRunStatus.planned: 0,
    ScheduledRunStatus.skipped: 1,
    ScheduledRunStatus.completed: 2,
  };

  /// One ledger entry per plan session: the strongest status among its
  /// calendar rows (completed > skipped > planned), with the run it points at.
  /// Sessions that were never scheduled have no entry.
  Future<Map<String, RunPlanLedgerEntry>> getPlanLedger(String planId) async {
    final database = await db;
    final rows = await database.rawQuery(
      '''
      SELECT s.id AS id, s.run_plan_workout_id AS workout_id,
        s.status AS status, s.date AS date, s.run_activity_id AS activity_id,
        a.distance_meters AS distance, a.avg_pace_sec_per_km AS pace
      FROM scheduled_runs s
      LEFT JOIN run_activities a ON a.id = s.run_activity_id
      WHERE s.run_plan_id = ? AND s.run_plan_workout_id IS NOT NULL
      ORDER BY s.date ASC
      ''',
      [planId],
    );
    final result = <String, RunPlanLedgerEntry>{};
    for (final row in rows) {
      final workoutId = row['workout_id'] as String;
      final status = ScheduledRunStatus.fromString(row['status'] as String?);
      final current = result[workoutId];
      if (current != null &&
          _statusRank[status]! <= _statusRank[current.status]!) {
        continue;
      }
      result[workoutId] = RunPlanLedgerEntry(
        workoutId: workoutId,
        status: status,
        scheduledRunId: row['id'] as String?,
        date: DateTime.tryParse(row['date'] as String? ?? ''),
        runActivityId: row['activity_id'] as String?,
        actualDistanceMeters: (row['distance'] as num?)?.toDouble(),
        actualPaceSecPerKm: (row['pace'] as num?)?.toDouble(),
      );
    }
    return result;
  }

  /// [getPlanProgress] for many plans in three queries: the library screen
  /// used to spend two awaits per plan.
  Future<Map<String, RunPlanProgress>> getPlanProgressBatch(
    List<String> planIds,
  ) async {
    if (planIds.isEmpty) return const {};
    final database = await db;
    final placeholders = List.filled(planIds.length, '?').join(', ');
    final totals = <String, int>{};
    for (final row in await database.rawQuery(
      'SELECT run_plan_id AS plan_id, COUNT(*) AS total '
      'FROM run_plan_workouts WHERE run_plan_id IN ($placeholders) '
      'GROUP BY run_plan_id',
      planIds,
    )) {
      totals[row['plan_id'] as String] = (row['total'] as num).toInt();
    }
    final statusesByPlan = <String, Map<String, ScheduledRunStatus>>{};
    final rows = await database.query(
      'scheduled_runs',
      columns: ['run_plan_id', 'run_plan_workout_id', 'status'],
      where:
          'run_plan_workout_id IS NOT NULL AND run_plan_id IN ($placeholders)',
      whereArgs: planIds,
    );
    for (final row in rows) {
      final byWorkout = statusesByPlan.putIfAbsent(
        row['run_plan_id'] as String,
        () => {},
      );
      final workoutId = row['run_plan_workout_id'] as String;
      final status = ScheduledRunStatus.fromString(row['status'] as String?);
      final current = byWorkout[workoutId];
      if (current == null || _statusRank[status]! > _statusRank[current]!) {
        byWorkout[workoutId] = status;
      }
    }
    return {
      for (final id in planIds)
        id: _progressFrom(totals[id] ?? 0, statusesByPlan[id]),
    };
  }

  /// Which of [planIds] are linked by a periodization phase target: one scan
  /// of `phase_targets` instead of one LIKE query per plan.
  Future<Set<String>> getPlanningLinkedIds(Iterable<String> planIds) async {
    final wanted = planIds.toSet();
    if (wanted.isEmpty) return const {};
    final database = await db;
    final rows = await database.query(
      'phase_targets',
      columns: ['training_json'],
      where: "training_json LIKE '%run_plan_ids%'",
    );
    final linked = <String>{};
    for (final row in rows) {
      final raw = row['training_json'] as String? ?? '';
      if (raw.isEmpty) continue;
      final run = _decodeJson(raw)['run'];
      if (run is! Map) continue;
      final ids = (run['run_plan_ids'] as List?)?.whereType<String>();
      if (ids == null) continue;
      linked.addAll(ids.where(wanted.contains));
    }
    return linked;
  }
}
