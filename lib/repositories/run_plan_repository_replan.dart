part of 'run_plan_repository.dart';

/// Re-planning: replacing future weeks, scaling, moving sessions and the
/// weekly-review log.
extension RunPlanRepositoryReplan on RunPlanRepository {
  // ===================== RE-PLANNING =====================

  /// Every calendar row of [planId], with its session hydrated.
  Future<List<ScheduledRun>> getScheduledRunsForPlan(String planId) async {
    final database = await db;
    final rows = await database.query(
      'scheduled_runs',
      where: 'run_plan_id = ?',
      whereArgs: [planId],
      orderBy: 'date ASC',
    );
    return _hydrateScheduled(database, rows);
  }

  /// Replaces every session from [fromWeek] on with [weeks] (one list of
  /// sessions per week), atomically, and re-schedules them when the plan is
  /// being followed.
  ///
  /// Weeks before [fromWeek] — the athlete's history — are untouched. A week
  /// at or after [fromWeek] that already has a run ticked off is refused: the
  /// caller must start re-planning after it.
  Future<void> replaceWeeksFrom(
    String planId, {
    required int fromWeek,
    required List<List<RunPlanSessionDraft>> weeks,
    Map<String, dynamic>? config,
  }) async {
    final database = await db;
    final touched = Sqflite.firstIntValue(
      await database.rawQuery(
        'SELECT COUNT(*) FROM scheduled_runs s '
        'JOIN run_plan_workouts w ON w.id = s.run_plan_workout_id '
        'WHERE w.run_plan_id = ? AND w.week_index >= ? AND s.status != ?',
        [planId, fromWeek, ScheduledRunStatus.planned.value],
      ),
    );
    if ((touched ?? 0) > 0) {
      throw StateError('run_plan_replan_over_history');
    }
    final now = DateTime.now();
    await database.transaction((txn) async {
      // Planned calendar rows of these sessions go with them (FK cascade).
      await txn.delete(
        'run_plan_workouts',
        where: 'run_plan_id = ? AND week_index >= ?',
        whereArgs: [planId, fromWeek],
      );
      for (var w = 0; w < weeks.length; w++) {
        for (var order = 0; order < weeks[w].length; order++) {
          final draft = weeks[w][order];
          final workoutId = _uuid.v4();
          await txn.insert('run_plan_workouts', {
            ...draft.workout,
            'id': workoutId,
            'run_plan_id': planId,
            'week_index': fromWeek + w,
            'order_index': order,
            'created_at': now.toIso8601String(),
          });
          for (var i = 0; i < draft.steps.length; i++) {
            await txn.insert('run_workout_steps', {
              ...draft.steps[i],
              'id': _uuid.v4(),
              'run_plan_workout_id': workoutId,
              'order_index': i,
            });
          }
        }
      }
      await txn.update(
        'run_plans',
        {
          'weeks': math.max(1, fromWeek + weeks.length),
          if (config != null) 'config_json': jsonEncode(config),
          'updated_at': now.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [planId],
      );
    });
    final plan = await getPlan(planId);
    final anchor = plan?.activatedAt;
    if (plan == null || !plan.isActivated || anchor == null) return;
    final today = mondayOf(DateTime.now());
    for (var week = fromWeek; week < plan.weeks; week++) {
      final start = addDays(mondayOf(anchor), 7 * week);
      if (start.isBefore(today)) continue;
      await materializeWeek(planId: planId, weekIndex: week, weekStart: start);
    }
  }

  /// Logs a weekly review for [weekIndex] of [planId]. [status] is
  /// `applied` or `dismissed`; either way the same week is not proposed
  /// again.
  Future<void> recordAdaptation({
    required String planId,
    required int weekIndex,
    required String kind,
    required String status,
    Map<String, dynamic>? payload,
  }) async {
    final database = await db;
    await database.insert('run_plan_adaptations', {
      'id': _uuid.v4(),
      'run_plan_id': planId,
      'week_index': weekIndex,
      'kind': kind,
      'status': status,
      'payload_json': payload == null ? null : jsonEncode(payload),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Weekly reviews of [planId], newest first.
  Future<List<RunPlanAdaptationRecord>> listAdaptations(String planId) async {
    final database = await db;
    final rows = await database.query(
      'run_plan_adaptations',
      where: 'run_plan_id = ?',
      whereArgs: [planId],
      orderBy: 'created_at DESC',
    );
    return rows.map(RunPlanAdaptationRecord.fromMap).toList();
  }

  /// Scales the easy volume of week [weekIndex] by [factor] — continuous
  /// runs and the warm-up, cool-down and steady parts of structured ones.
  /// Work reps keep their shape: a lighter week is less running, not
  /// different intervals. Used to adjust plans that cannot be re-composed.
  Future<void> scaleWeek(String planId, int weekIndex, double factor) async {
    if (factor <= 0 || factor == 1) return;
    final database = await db;
    await database.transaction(
      (txn) => scaleWeekIn(txn, planId, weekIndex, factor),
    );
  }

  /// [scaleWeek] on an explicit executor (callers fold it into their own
  /// transaction). Only values that change are written.
  Future<void> scaleWeekIn(
    DatabaseExecutor executor,
    String planId,
    int weekIndex,
    double factor,
  ) async {
    if (factor <= 0 || factor == 1) return;
    final plan = await getPlanIn(executor, planId);
    if (plan == null) return;
    for (final workout in plan.workoutsForWeek(weekIndex)) {
      final scaled = RunPlanRepository.scaledWorkout(workout, factor);
      if (!workout.hasSteps) {
        final updates = <String, Object?>{
          if (scaled.targetDistanceMeters != workout.targetDistanceMeters)
            'target_distance_meters': scaled.targetDistanceMeters,
          if (scaled.targetDurationSeconds != workout.targetDurationSeconds)
            'target_duration_seconds': scaled.targetDurationSeconds,
        };
        if (updates.isNotEmpty) {
          await executor.update(
            'run_plan_workouts',
            updates,
            where: 'id = ?',
            whereArgs: [workout.id],
          );
        }
        continue;
      }
      for (var i = 0; i < workout.steps.length; i++) {
        final before = workout.steps[i];
        final after = scaled.steps[i];
        if (before.value == after.value) continue;
        await executor.update(
          'run_workout_steps',
          {'value': after.value},
          where: 'id = ?',
          whereArgs: [before.id],
        );
      }
    }
    await _touchPlan(executor, planId);
  }

  /// [getPlan] on an explicit executor.
  Future<RunPlan?> getPlanIn(DatabaseExecutor executor, String id) async {
    final rows = await executor.query(
      'run_plans',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final byPlan = await _loadWorkoutsByPlan(executor, [id]);
    return RunPlan.fromMap(rows.first, workouts: byPlan[id] ?? const []);
  }

  /// `(run_plan_workout_id, status, date)` of every calendar row of
  /// [planId]: what is already run, skipped or still planned.
  Future<List<Map<String, Object?>>> scheduledRowsIn(
    DatabaseExecutor executor,
    String planId,
  ) => executor.query(
    'scheduled_runs',
    columns: ['id', 'run_plan_workout_id', 'status', 'date'],
    where: 'run_plan_id = ?',
    whereArgs: [planId],
    orderBy: 'date ASC, id ASC',
  );

  /// [recordAdaptation] on an explicit executor with a caller-chosen [id].
  Future<void> recordAdaptationIn(
    DatabaseExecutor executor, {
    required String id,
    required String planId,
    required int weekIndex,
    required String kind,
    required String status,
    Map<String, dynamic>? payload,
  }) async {
    await executor.insert('run_plan_adaptations', {
      'id': id,
      'run_plan_id': planId,
      'week_index': weekIndex,
      'kind': kind,
      'status': status,
      'payload_json': payload == null ? null : jsonEncode(payload),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Moves a session to another weekday and takes its still-planned
  /// calendar rows along (same week), so the plan and the calendar agree.
  Future<void> moveWorkoutToDay(String workoutId, int dayOfWeek) async {
    final database = await db;
    await database.transaction(
      (txn) => moveWorkoutToDayIn(txn, workoutId, dayOfWeek),
    );
  }

  /// [moveWorkoutToDay] on an explicit executor. Throws [StateError] when the
  /// session does not exist.
  Future<void> moveWorkoutToDayIn(
    DatabaseExecutor executor,
    String workoutId,
    int dayOfWeek,
  ) async {
    final changed = await executor.update(
      'run_plan_workouts',
      {'day_of_week': dayOfWeek},
      where: 'id = ?',
      whereArgs: [workoutId],
    );
    if (changed != 1) throw StateError('run plan workout $workoutId not found');
    await _touchPlanForWorkout(executor, workoutId);
    final rows = await executor.query(
      'scheduled_runs',
      columns: ['id', 'date'],
      where: 'run_plan_workout_id = ? AND status = ?',
      whereArgs: [workoutId, ScheduledRunStatus.planned.value],
    );
    for (final row in rows) {
      final date = DateTime.parse(row['date'] as String);
      final moved = addDays(mondayOf(date), dayOfWeek - 1);
      await executor.update(
        'scheduled_runs',
        {
          'date': dateKey(moved),
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
  }
}

/// A session to insert while re-planning: `run_plan_workouts` columns (minus
/// ids, plan, week and order, which the repository assigns) and its steps.
class RunPlanSessionDraft {
  final Map<String, Object?> workout;
  final List<Map<String, Object?>> steps;

  const RunPlanSessionDraft({required this.workout, this.steps = const []});
}

/// One row of the weekly-review log.
class RunPlanAdaptationRecord {
  final String id;
  final String planId;
  final int weekIndex;
  final String kind;
  final String status;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  const RunPlanAdaptationRecord({
    required this.id,
    required this.planId,
    required this.weekIndex,
    required this.kind,
    required this.status,
    required this.payload,
    required this.createdAt,
  });

  bool get applied => status == 'applied';

  factory RunPlanAdaptationRecord.fromMap(Map<String, Object?> map) =>
      RunPlanAdaptationRecord(
        id: map['id'] as String,
        planId: map['run_plan_id'] as String,
        weekIndex: (map['week_index'] as num?)?.toInt() ?? 0,
        kind: map['kind'] as String? ?? 'none',
        status: map['status'] as String? ?? 'applied',
        payload: map['payload_json'] == null
            ? const {}
            : _decodeJson(map['payload_json'] as String),
        createdAt:
            DateTime.tryParse(map['created_at'] as String? ?? '') ??
            DateTime(2000),
      );
}
