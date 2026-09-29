import 'dart:convert';
import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:workout_notes/models/run_plan.dart';
import 'package:workout_notes/models/run_plan_ledger.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/models/run_voice_settings.dart';
import 'package:workout_notes/models/run_workout_step.dart';
import 'package:workout_notes/models/scheduled_run.dart';
import 'package:workout_notes/repositories/base_repository.dart';

/// Repository for structured running plans, their sessions, steps, the dated
/// schedule and per-step results.
class RunPlanRepository extends BaseRepository {
  static const _uuid = Uuid();

  // ===================== PLANS =====================

  /// Lists plans. With [hydrate] the sessions come along, which is what the
  /// library screen needs to show each plan's weekly volume.
  Future<List<RunPlan>> listPlans({
    bool includeArchived = false,
    bool hydrate = false,
  }) async {
    final database = await db;
    if (!await _tableExists(database, 'run_plans')) return const [];
    final rows = await database.query(
      'run_plans',
      where: includeArchived ? null : 'status = ?',
      whereArgs: includeArchived ? null : [RunPlanStatus.active.value],
      orderBy: 'updated_at DESC',
    );
    if (!hydrate ||
        rows.isEmpty ||
        !await _tableExists(database, 'run_plan_workouts')) {
      return rows.map((row) => RunPlan.fromMap(row)).toList();
    }
    final byPlan = await _loadWorkoutsByPlan(
      database,
      rows.map((row) => row['id'] as String).toList(),
    );
    return [
      for (final row in rows)
        RunPlan.fromMap(row, workouts: byPlan[row['id'] as String] ?? const []),
    ];
  }

  /// Loads a plan with every session and step hydrated.
  Future<RunPlan?> getPlan(String id) async {
    final database = await db;
    if (!await _tableExists(database, 'run_plans')) return null;
    final rows = await database.query(
      'run_plans',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final byPlan = await _loadWorkoutsByPlan(database, [id]);
    return RunPlan.fromMap(rows.first, workouts: byPlan[id] ?? const []);
  }

  /// The plan currently being followed, or null when none is activated.
  ///
  /// "Activated" is a single-choice pointer: [activatePlan] clears every other
  /// plan, so this is at most one row. Archived plans are excluded even if an
  /// old activation date lingers.
  Future<RunPlan?> getActivatedPlan({bool hydrate = true}) async {
    final database = await db;
    if (!await _tableExists(database, 'run_plans')) return null;
    if (!await _columnExists(database, 'run_plans', 'activated_at')) {
      return null;
    }
    final rows = await database.query(
      'run_plans',
      where: 'activated_at IS NOT NULL AND status = ?',
      whereArgs: [RunPlanStatus.active.value],
      orderBy: 'activated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final id = rows.first['id'] as String;
    if (!hydrate) return RunPlan.fromMap(rows.first);
    final byPlan = await _loadWorkoutsByPlan(database, [id]);
    return RunPlan.fromMap(rows.first, workouts: byPlan[id] ?? const []);
  }

  /// Starts following [id] from [from] (default: today), clearing any other
  /// activation. Returns the number of scheduled rows created for the weeks
  /// from [from] to the end of the plan, so the calendar has planned sessions
  /// to tick off. Safe to call twice: [materializeWeek] skips existing rows.
  ///
  /// A plan with an upcoming race date and no explicit [from] is anchored so
  /// its last week is race week: it may start on a later Monday, or already
  /// be a few weeks in when activated late (earlier weeks are not
  /// back-filled).
  Future<int> activatePlan(String id, {DateTime? from}) async {
    final database = await db;
    if (!await _tableExists(database, 'run_plans')) return 0;
    if (!await _columnExists(database, 'run_plans', 'activated_at')) return 0;
    final today = _day(from ?? DateTime.now());
    var start = today;
    if (from == null) {
      final existing = await getPlan(id);
      final race = existing?.raceDate;
      if (existing != null && race != null && existing.weeks > 0) {
        final raceWeek = _weekStart(race);
        if (!raceWeek.isBefore(_weekStart(today))) {
          start = raceWeek.subtract(Duration(days: 7 * (existing.weeks - 1)));
        }
      }
    }
    final now = DateTime.now().toIso8601String();
    await database.transaction((txn) async {
      await txn.update(
        'run_plans',
        {'activated_at': null, 'updated_at': now},
        where: 'activated_at IS NOT NULL AND id != ?',
        whereArgs: [id],
      );
      await txn.update(
        'run_plans',
        {'activated_at': _date(start), 'updated_at': now},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
    final plan = await getPlan(id);
    if (plan == null) return 0;
    var created = 0;
    final anchorWeek = _weekStart(start);
    // Only the weeks from here on: back-filling earlier weeks would invent
    // planned sessions the user never had a chance to run.
    final firstWeek = start.isBefore(today)
        ? plan.activeWeekIndexOn(today) ?? 0
        : 0;
    for (var week = firstWeek; week < plan.weeks; week++) {
      created += (await materializeWeek(
        planId: id,
        weekIndex: week,
        weekStart: anchorWeek.add(Duration(days: 7 * week)),
      )).length;
    }
    return created;
  }

  /// Stops following [id] and, by default, clears the sessions it left in the
  /// calendar that were never run.
  ///
  /// Completed and skipped rows always survive — they are real history and the
  /// plan's progress is read from them. Only untouched `planned` rows go, so
  /// abandoning a 16-week plan does not leave four months of ghost entries.
  /// Returns how many were removed.
  Future<int> deactivatePlan(String id, {bool clearPlanned = true}) async {
    final database = await db;
    if (!await _tableExists(database, 'run_plans')) return 0;
    if (!await _columnExists(database, 'run_plans', 'activated_at')) return 0;
    await database.update(
      'run_plans',
      {'activated_at': null, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
    if (!clearPlanned || !await _tableExists(database, 'scheduled_runs')) {
      return 0;
    }
    return database.delete(
      'scheduled_runs',
      where: 'run_plan_id = ? AND status = ?',
      whereArgs: [id, ScheduledRunStatus.planned.value],
    );
  }

  /// Completed / skipped / planned counts for a plan, read from the scheduled
  /// ledger, plus how many sessions the plan defines in total.
  Future<RunPlanProgress> getPlanProgress(String planId) async {
    final database = await db;
    if (!await _tableExists(database, 'run_plan_workouts')) {
      return const RunPlanProgress();
    }
    final total =
        Sqflite.firstIntValue(
          await database.rawQuery(
            'SELECT COUNT(*) FROM run_plan_workouts WHERE run_plan_id = ?',
            [planId],
          ),
        ) ??
        0;
    if (!await _tableExists(database, 'scheduled_runs')) {
      return RunPlanProgress(totalSessions: total);
    }
    // Count logical plan sessions, not calendar rows. Pausing and resuming may
    // have scheduled the same session on different dates in older app versions.
    return _progressFrom(total, await getPlanWorkoutStatuses(planId));
  }

  /// Latest effective state for each session in a plan. Completed wins over
  /// skipped and planned if old/repeated schedules exist for the same session.
  Future<Map<String, ScheduledRunStatus>> getPlanWorkoutStatuses(
    String planId,
  ) async {
    final database = await db;
    if (!await _tableExists(database, 'scheduled_runs')) return const {};
    final rows = await database.query(
      'scheduled_runs',
      columns: ['run_plan_workout_id', 'status'],
      where: 'run_plan_id = ? AND run_plan_workout_id IS NOT NULL',
      whereArgs: [planId],
    );
    const rank = {
      ScheduledRunStatus.planned: 0,
      ScheduledRunStatus.skipped: 1,
      ScheduledRunStatus.completed: 2,
    };
    final result = <String, ScheduledRunStatus>{};
    for (final row in rows) {
      final workoutId = row['run_plan_workout_id'] as String;
      final status = ScheduledRunStatus.fromString(row['status'] as String?);
      final current = result[workoutId];
      if (current == null || rank[status]! > rank[current]!) {
        result[workoutId] = status;
      }
    }
    return result;
  }

  /// Clears only this plan's completion ledger. Recorded run activities and
  /// the plan's sessions remain untouched. If it was being followed, restart
  /// it from week 1 today and recreate its future calendar schedule.
  Future<int> resetPlanProgress(String planId) async {
    final database = await db;
    final plan = await getPlan(planId);
    if (plan == null || !await _tableExists(database, 'scheduled_runs')) {
      return 0;
    }
    final wasActivated = plan.isActivated;
    final progress = await getPlanProgress(planId);
    if (progress.isComplete &&
        plan.completionCount == 0 &&
        await _columnExists(database, 'run_plans', 'completion_count')) {
      // A plan completed before v47 still deserves its first completion.
      await database.update(
        'run_plans',
        {'completion_count': 1},
        where: 'id = ?',
        whereArgs: [planId],
      );
    }
    await database.delete(
      'scheduled_runs',
      where: 'run_plan_id = ?',
      whereArgs: [planId],
    );
    if (!wasActivated) return 0;
    return activatePlan(planId, from: DateTime.now());
  }

  /// Marks the plan session [planWorkoutId] as done on [date], attaching
  /// [runActivityId].
  ///
  /// Reuses the scheduled row for that date and session when there is one, so
  /// running from the calendar and running straight from the plan converge on
  /// the same ledger entry. When the session was never materialised (a run
  /// started from the plan screen, or a plan followed without scheduling) the
  /// row is created on the spot — otherwise finishing the run would leave no
  /// trace of progress. Returns the row, or null when the session is unknown.
  Future<ScheduledRun?> markPlanWorkoutCompleted({
    required String planWorkoutId,
    required DateTime date,
    required String runActivityId,
  }) async {
    final database = await db;
    if (!await _tableExists(database, 'scheduled_runs')) return null;
    final planId = await _planIdForWorkout(database, planWorkoutId);
    if (planId == null) return null;
    final wasComplete = (await getPlanProgress(planId)).isComplete;
    final day = _day(date);
    // A plan session is one logical unit, so running Wednesday's workout on
    // Saturday must tick off that same row rather than spawn a twin and leave
    // the original planned forever. Exact date first, then the session's own
    // still-planned row, which is moved to the day it was actually run.
    var existing = await database.query(
      'scheduled_runs',
      columns: ['id'],
      where: 'run_plan_workout_id = ? AND date = ?',
      whereArgs: [planWorkoutId, _date(day)],
      limit: 1,
    );
    var moved = false;
    if (existing.isEmpty) {
      // Bounded to the same week either way: a session run a few days late
      // (or early) is the same session, but a row two weeks out belongs to a
      // different week of the plan and must not be cannibalised.
      final from = day.subtract(const Duration(days: 6));
      final to = day.add(const Duration(days: 6));
      existing = await database.query(
        'scheduled_runs',
        columns: ['id'],
        where:
            'run_plan_workout_id = ? AND status = ? AND date BETWEEN ? AND ?',
        whereArgs: [
          planWorkoutId,
          ScheduledRunStatus.planned.value,
          _date(from),
          _date(to),
        ],
        orderBy: 'date ASC',
        limit: 1,
      );
      moved = existing.isNotEmpty;
    }
    final now = DateTime.now().toIso8601String();
    final String id;
    if (existing.isEmpty) {
      id = _uuid.v4();
      await database.insert('scheduled_runs', {
        'id': id,
        'date': _date(day),
        'run_plan_id': planId,
        'run_plan_workout_id': planWorkoutId,
        'status': ScheduledRunStatus.completed.value,
        'notes': null,
        'run_activity_id': runActivityId,
        'created_at': now,
        'updated_at': now,
      });
    } else {
      id = existing.first['id'] as String;
      await database.update(
        'scheduled_runs',
        {
          'status': ScheduledRunStatus.completed.value,
          'run_activity_id': runActivityId,
          if (moved) 'date': _date(day),
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    final scheduled = await getScheduledRun(id);
    final progress = await getPlanProgress(planId);
    if (!wasComplete &&
        progress.isComplete &&
        await _columnExists(database, 'run_plans', 'completion_count')) {
      await database.rawUpdate(
        'UPDATE run_plans '
        'SET completion_count = completion_count + 1, updated_at = ? '
        'WHERE id = ?',
        [now, planId],
      );
    }
    if (progress.isComplete &&
        await _columnExists(database, 'run_plans', 'activated_at')) {
      // Completion is terminal. Do not let activeWeekIndexOn wrap back to week
      // one after the user has finished every session.
      await database.update(
        'run_plans',
        {'activated_at': null, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [planId],
      );
    }
    return scheduled;
  }

  /// True when a periodization phase target links [planId]. The plan's weeks
  /// are then driven by the phase, so the library shows it as active through
  /// the planning instead of offering its own activation.
  Future<bool> isLinkedToPeriodization(String planId) async {
    final database = await db;
    if (!await _tableExists(database, 'phase_targets')) return false;
    final rows = await database.query(
      'phase_targets',
      columns: ['training_json'],
      where: 'training_json LIKE ?',
      whereArgs: ['%$planId%'],
    );
    for (final row in rows) {
      final training = _decodeJson(row['training_json'] as String? ?? '');
      final run = training['run'];
      if (run is! Map) continue;
      final ids = (run['run_plan_ids'] as List?)?.whereType<String>();
      if (ids != null && ids.contains(planId)) return true;
    }
    return false;
  }

  Future<RunPlan> createPlan({
    required String name,
    String? notes,
    RunPlanGoalKind goalKind = RunPlanGoalKind.base,
    DateTime? raceDate,
    int weeks = 4,
    String? templateKey,
    Map<String, dynamic>? config,
  }) async {
    final database = await db;
    final now = DateTime.now();
    final plan = RunPlan(
      id: _uuid.v4(),
      name: name.trim(),
      notes: _optional(notes),
      goalKind: goalKind,
      raceDate: raceDate,
      weeks: weeks < 1 ? 1 : weeks,
      status: RunPlanStatus.active,
      createdAt: now,
      updatedAt: now,
      templateKey: templateKey,
      config: config,
    );
    await database.insert('run_plans', await _planRow(database, plan));
    return plan;
  }

  /// [plan] as a row, minus columns a device whose v52 upgrade failed does
  /// not have — the plan still saves, it just cannot be re-planned later.
  Future<Map<String, dynamic>> _planRow(
    DatabaseExecutor database,
    RunPlan plan,
  ) async {
    final row = plan.toMap();
    if (!await _columnExists(database, 'run_plans', 'config_json')) {
      row
        ..remove('template_key')
        ..remove('config_json');
    }
    return row;
  }

  Future<void> updatePlan(
    String id, {
    String? name,
    Object? notes = _sentinel,
    RunPlanGoalKind? goalKind,
    Object? raceDate = _sentinel,
    int? weeks,
    RunPlanStatus? status,
  }) async {
    final database = await db;
    final updates = <String, dynamic>{
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (name != null) updates['name'] = name.trim();
    if (!identical(notes, _sentinel)) {
      updates['notes'] = _optional(notes as String?);
    }
    if (goalKind != null) updates['goal_kind'] = goalKind.value;
    if (!identical(raceDate, _sentinel)) {
      final value = raceDate as DateTime?;
      updates['race_date'] = value == null ? null : _date(value);
    }
    if (weeks != null) updates['weeks'] = weeks < 1 ? 1 : weeks;
    if (status != null) updates['status'] = status.value;
    await database.update(
      'run_plans',
      updates,
      where: 'id = ?',
      whereArgs: [id],
    );
    if (weeks != null) {
      // Sessions beyond the new horizon would be unreachable — drop them.
      await database.delete(
        'run_plan_workouts',
        where: 'run_plan_id = ? AND week_index >= ?',
        whereArgs: [id, weeks < 1 ? 1 : weeks],
      );
    }
  }

  /// Deletes a plan. Weekly periodization targets keep run plan ids inside
  /// `training_json`, so those references are cleared first — the same care
  /// [RoutineRepository.deleteRoutine] takes for routines.
  Future<void> deletePlan(String id) async {
    final database = await db;
    await database.transaction((txn) async {
      await _clearPlanFromTargets(txn, id);
      await txn.delete('run_plans', where: 'id = ?', whereArgs: [id]);
    });
  }

  /// Duplicates a plan (sessions + steps) under a new name.
  Future<RunPlan> duplicatePlan(String id, String newName) async {
    final source = await getPlan(id);
    if (source == null) {
      throw StateError('run_plan_not_found');
    }
    final database = await db;
    final now = DateTime.now();
    final copy = RunPlan(
      id: _uuid.v4(),
      name: newName.trim(),
      notes: source.notes,
      goalKind: source.goalKind,
      raceDate: source.raceDate,
      weeks: source.weeks,
      status: RunPlanStatus.active,
      createdAt: now,
      updatedAt: now,
      templateKey: source.templateKey,
      config: source.config,
    );
    final row = await _planRow(database, copy);
    await database.transaction((txn) async {
      await txn.insert('run_plans', row);
      for (final workout in source.workouts) {
        await _insertWorkoutCopy(txn, workout, copy.id, workout.weekIndex);
      }
    });
    return (await getPlan(copy.id))!;
  }

  /// Copies every session of [sourceWeek] into [targetWeeks], replacing what
  /// those weeks held. Mirrors the strength `WeekCopySheet` behaviour.
  Future<int> copyWeek(
    String planId, {
    required int sourceWeek,
    required Set<int> targetWeeks,
  }) async {
    final plan = await getPlan(planId);
    if (plan == null) return 0;
    final source = plan.workoutsForWeek(sourceWeek);
    final targets = targetWeeks
        .where((week) => week != sourceWeek && week >= 0 && week < plan.weeks)
        .toList();
    if (targets.isEmpty) return 0;
    final database = await db;
    await database.transaction((txn) async {
      for (final week in targets) {
        await txn.delete(
          'run_plan_workouts',
          where: 'run_plan_id = ? AND week_index = ?',
          whereArgs: [planId, week],
        );
        for (final workout in source) {
          await _insertWorkoutCopy(txn, workout, planId, week);
        }
      }
      await txn.update(
        'run_plans',
        {'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [planId],
      );
    });
    return targets.length;
  }

  /// Weeks of [planId] that already have runs on the calendar. The plan screen
  /// marks them so "did I already schedule this week?" is answered by looking,
  /// not by scheduling again and reading the "already scheduled" snack.
  Future<Set<int>> getScheduledWeeks(String planId) async {
    final database = await db;
    if (!await _tableExists(database, 'scheduled_runs') ||
        !await _tableExists(database, 'run_plan_workouts')) {
      return const {};
    }
    final rows = await database.rawQuery(
      'SELECT DISTINCT w.week_index AS week_index '
      'FROM scheduled_runs s '
      'JOIN run_plan_workouts w ON w.id = s.run_plan_workout_id '
      'WHERE s.run_plan_id = ?',
      [planId],
    );
    return {
      for (final row in rows)
        if (row['week_index'] != null) row['week_index'] as int,
    };
  }

  // ===================== SESSIONS =====================

  /// Copies one session, optionally into another week of the same plan.
  Future<void> duplicateWorkout(String id, {int? weekIndex}) async {
    final source = await getWorkout(id);
    if (source == null) return;
    final database = await db;
    await database.transaction((txn) async {
      await _insertWorkoutCopy(
        txn,
        source,
        source.runPlanId,
        weekIndex ?? source.weekIndex,
      );
    });
    await _touchPlan(database, source.runPlanId);
  }

  Future<RunPlanWorkout?> getWorkout(String id) async {
    final database = await db;
    final rows = await database.query(
      'run_plan_workouts',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final steps = await getSteps(id);
    return RunPlanWorkout.fromMap(rows.first, steps: steps);
  }

  Future<RunPlanWorkout> addWorkout({
    required String planId,
    required int weekIndex,
    required String name,
    RunWorkoutKind kind = RunWorkoutKind.easy,
    int? dayOfWeek,
    String? notes,
    double? targetDistanceMeters,
    int? targetDurationSeconds,
    double? targetPaceSecPerKm,
    String? effortZone,
  }) async {
    final database = await db;
    final count =
        Sqflite.firstIntValue(
          await database.rawQuery(
            'SELECT COUNT(*) FROM run_plan_workouts WHERE run_plan_id = ? AND week_index = ?',
            [planId, weekIndex],
          ),
        ) ??
        0;
    final workout = RunPlanWorkout(
      id: _uuid.v4(),
      runPlanId: planId,
      weekIndex: weekIndex,
      dayOfWeek: dayOfWeek,
      orderIndex: count,
      kind: kind,
      name: name.trim(),
      notes: _optional(notes),
      targetDistanceMeters: targetDistanceMeters,
      targetDurationSeconds: targetDurationSeconds,
      targetPaceSecPerKm: targetPaceSecPerKm,
      effortZone: _optional(effortZone),
      createdAt: DateTime.now(),
    );
    await database.insert('run_plan_workouts', workout.toMap());
    await _touchPlan(database, planId);
    return workout;
  }

  Future<void> updateWorkout(
    String id, {
    String? name,
    RunWorkoutKind? kind,
    Object? dayOfWeek = _sentinel,
    Object? notes = _sentinel,
    Object? targetDistanceMeters = _sentinel,
    Object? targetDurationSeconds = _sentinel,
    Object? targetPaceSecPerKm = _sentinel,
    Object? effortZone = _sentinel,
    int? weekIndex,
  }) async {
    final database = await db;
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name.trim();
    if (kind != null) updates['kind'] = kind.value;
    if (!identical(dayOfWeek, _sentinel)) {
      updates['day_of_week'] = dayOfWeek as int?;
    }
    if (!identical(notes, _sentinel)) {
      updates['notes'] = _optional(notes as String?);
    }
    if (!identical(targetDistanceMeters, _sentinel)) {
      updates['target_distance_meters'] = targetDistanceMeters as double?;
    }
    if (!identical(targetDurationSeconds, _sentinel)) {
      updates['target_duration_seconds'] = targetDurationSeconds as int?;
    }
    if (!identical(targetPaceSecPerKm, _sentinel)) {
      updates['target_pace_sec_per_km'] = targetPaceSecPerKm as double?;
    }
    if (!identical(effortZone, _sentinel)) {
      updates['effort_zone'] = _optional(effortZone as String?);
    }
    if (weekIndex != null) updates['week_index'] = weekIndex;
    if (updates.isEmpty) return;
    await database.update(
      'run_plan_workouts',
      updates,
      where: 'id = ?',
      whereArgs: [id],
    );
    final planId = await _planIdForWorkout(database, id);
    if (planId != null) await _touchPlan(database, planId);
  }

  Future<void> deleteWorkout(String id) async {
    final database = await db;
    final planId = await _planIdForWorkout(database, id);
    await database.delete(
      'run_plan_workouts',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (planId != null) await _touchPlan(database, planId);
  }

  // ===================== STEPS =====================

  Future<List<RunWorkoutStep>> getSteps(String workoutId) async {
    final database = await db;
    final rows = await database.query(
      'run_workout_steps',
      where: 'run_plan_workout_id = ?',
      whereArgs: [workoutId],
      orderBy: 'order_index ASC',
    );
    return rows.map(RunWorkoutStep.fromMap).toList();
  }

  Future<RunWorkoutStep> addStep({
    required String workoutId,
    required RunStepRole role,
    required RunIntervalMetric metric,
    required int value,
    int? repeatGroup,
    int repeatCount = 1,
    double? targetPaceMinSecPerKm,
    double? targetPaceMaxSecPerKm,
    String? notes,
  }) async {
    final database = await db;
    final count =
        Sqflite.firstIntValue(
          await database.rawQuery(
            'SELECT COUNT(*) FROM run_workout_steps WHERE run_plan_workout_id = ?',
            [workoutId],
          ),
        ) ??
        0;
    final step = RunWorkoutStep(
      id: _uuid.v4(),
      runPlanWorkoutId: workoutId,
      orderIndex: count,
      role: role,
      metric: metric,
      value: value < 0 ? 0 : value,
      repeatGroup: repeatGroup,
      repeatCount: repeatCount < 1 ? 1 : repeatCount,
      targetPaceMinSecPerKm: targetPaceMinSecPerKm,
      targetPaceMaxSecPerKm: targetPaceMaxSecPerKm,
      notes: _optional(notes),
    );
    await database.insert('run_workout_steps', step.toMap());
    await _touchPlanForWorkout(database, workoutId);
    return step;
  }

  Future<void> updateStep(RunWorkoutStep step) async {
    final database = await db;
    await database.update(
      'run_workout_steps',
      step.toMap(),
      where: 'id = ?',
      whereArgs: [step.id],
    );
    await _touchPlanForWorkout(database, step.runPlanWorkoutId);
  }

  Future<void> deleteStep(String id) async {
    final database = await db;
    final rows = await database.query(
      'run_workout_steps',
      columns: ['run_plan_workout_id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    await database.delete(
      'run_workout_steps',
      where: 'id = ?',
      whereArgs: [id],
    );
    final workoutId = rows.isEmpty
        ? null
        : rows.first['run_plan_workout_id'] as String?;
    if (workoutId != null) await _touchPlanForWorkout(database, workoutId);
  }

  Future<void> reorderSteps(String workoutId, List<String> orderedIds) async {
    final database = await db;
    final batch = database.batch();
    for (var i = 0; i < orderedIds.length; i++) {
      batch.update(
        'run_workout_steps',
        {'order_index': i},
        where: 'id = ? AND run_plan_workout_id = ?',
        whereArgs: [orderedIds[i], workoutId],
      );
    }
    await batch.commit(noResult: true);
    await _touchPlanForWorkout(database, workoutId);
  }

  // ===================== SCHEDULE =====================

  Future<List<ScheduledRun>> getScheduledRuns(
    DateTime from,
    DateTime to, {
    bool hydrate = true,
  }) async {
    final database = await db;
    if (!await _tableExists(database, 'scheduled_runs')) return const [];
    final rows = await database.query(
      'scheduled_runs',
      where: 'date >= ? AND date <= ?',
      whereArgs: [_date(from), _date(to)],
      orderBy: 'date ASC',
    );
    return _hydrateScheduled(database, rows, hydrate: hydrate);
  }

  Future<List<ScheduledRun>> getScheduledRunsForDate(DateTime date) async {
    final database = await db;
    if (!await _tableExists(database, 'scheduled_runs')) return const [];
    final rows = await database.query(
      'scheduled_runs',
      where: 'date = ?',
      whereArgs: [_date(date)],
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
    final monday = _weekStart(weekStart);
    final database = await db;
    final created = <String>[];
    await database.transaction((txn) async {
      for (final session in sessions) {
        final day = session.dayOfWeek ?? 1;
        final date = monday.add(Duration(days: day - 1));
        final existing = await txn.query(
          'scheduled_runs',
          columns: ['id'],
          where:
              'run_plan_workout_id = ? AND '
              '(date = ? OR status IN (?, ?))',
          whereArgs: [
            session.id,
            _date(date),
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
          'date': _date(date),
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
    if (date != null) updates['date'] = _date(date);
    if (status != null) updates['status'] = status.value;
    if (!identical(notes, _sentinel)) {
      updates['notes'] = _optional(notes as String?);
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
    if (!await _tableExists(database, 'run_activity_steps')) return const [];
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

  // ===================== RE-PLANNING =====================

  /// Every calendar row of [planId], with its session hydrated.
  Future<List<ScheduledRun>> getScheduledRunsForPlan(String planId) async {
    final database = await db;
    if (!await _tableExists(database, 'scheduled_runs')) return const [];
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
    final hasConfig = await _columnExists(database, 'run_plans', 'config_json');
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
          if (hasConfig && config != null) 'config_json': jsonEncode(config),
          'updated_at': now.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [planId],
      );
    });
    final plan = await getPlan(planId);
    final anchor = plan?.activatedAt;
    if (plan == null || !plan.isActivated || anchor == null) return;
    final today = _weekStart(DateTime.now());
    for (var week = fromWeek; week < plan.weeks; week++) {
      final start = _weekStart(anchor).add(Duration(days: 7 * week));
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
    if (!await _tableExists(database, 'run_plan_adaptations')) return;
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
    if (!await _tableExists(database, 'run_plan_adaptations')) {
      return const [];
    }
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
    final plan = await getPlan(planId);
    if (plan == null) return;
    final database = await db;
    int round10(num meters) => ((meters * factor) / 10).round() * 10;
    await database.transaction((txn) async {
      for (final workout in plan.workoutsForWeek(weekIndex)) {
        if (!workout.hasSteps) {
          final distance = workout.targetDistanceMeters;
          final duration = workout.targetDurationSeconds;
          await txn.update(
            'run_plan_workouts',
            {
              if (distance != null) 'target_distance_meters': round10(distance),
              if (distance == null && duration != null)
                'target_duration_seconds': (duration * factor).round(),
            },
            where: 'id = ?',
            whereArgs: [workout.id],
          );
          continue;
        }
        for (final step in workout.steps) {
          if (step.role == RunStepRole.work ||
              step.role == RunStepRole.recovery) {
            continue;
          }
          await txn.update(
            'run_workout_steps',
            {
              'value': step.isDistance
                  ? round10(step.value)
                  : (step.value * factor).round(),
            },
            where: 'id = ?',
            whereArgs: [step.id],
          );
        }
      }
    });
    await _touchPlan(database, planId);
  }

  /// Moves a session to another weekday and takes its still-planned
  /// calendar rows along (same week), so the plan and the calendar agree.
  Future<void> moveWorkoutToDay(String workoutId, int dayOfWeek) async {
    await updateWorkout(workoutId, dayOfWeek: dayOfWeek);
    final database = await db;
    if (!await _tableExists(database, 'scheduled_runs')) return;
    final rows = await database.query(
      'scheduled_runs',
      columns: ['id', 'date'],
      where: 'run_plan_workout_id = ? AND status = ?',
      whereArgs: [workoutId, ScheduledRunStatus.planned.value],
    );
    for (final row in rows) {
      final date = DateTime.parse(row['date'] as String);
      final moved = _weekStart(date).add(Duration(days: dayOfWeek - 1));
      await database.update(
        'scheduled_runs',
        {'date': _date(moved), 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
  }

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
    if (!await _tableExists(database, 'scheduled_runs')) return const {};
    // Older or minimal schemas may lack the activity columns.
    final hasActivities =
        await _tableExists(database, 'run_activities') &&
        await _columnExists(database, 'run_activities', 'distance_meters') &&
        await _columnExists(database, 'run_activities', 'avg_pace_sec_per_km');
    final activityColumns = hasActivities
        ? ', a.distance_meters AS distance, a.avg_pace_sec_per_km AS pace'
        : '';
    final activityJoin = hasActivities
        ? 'LEFT JOIN run_activities a ON a.id = s.run_activity_id'
        : '';
    final rows = await database.rawQuery(
      '''
      SELECT s.id AS id, s.run_plan_workout_id AS workout_id,
        s.status AS status, s.date AS date, s.run_activity_id AS activity_id
        $activityColumns
      FROM scheduled_runs s
      $activityJoin
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
    if (!await _tableExists(database, 'run_plan_workouts')) {
      return {for (final id in planIds) id: const RunPlanProgress()};
    }
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
    if (await _tableExists(database, 'scheduled_runs')) {
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
    }
    return {
      for (final id in planIds)
        id: _progressFrom(totals[id] ?? 0, statusesByPlan[id]),
    };
  }

  static RunPlanProgress _progressFrom(
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

  /// Which of [planIds] are linked by a periodization phase target: one scan
  /// of `phase_targets` instead of one LIKE query per plan.
  Future<Set<String>> getPlanningLinkedIds(Iterable<String> planIds) async {
    final wanted = planIds.toSet();
    if (wanted.isEmpty) return const {};
    final database = await db;
    if (!await _tableExists(database, 'phase_targets')) return const {};
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

  // ===================== HELPERS =====================

  /// Sessions of several plans in two queries, grouped by plan id. The plan
  /// library needs every plan's volume to draw its ramp, so loading them one by
  /// one would be a query per plan.
  Future<Map<String, List<RunPlanWorkout>>> _loadWorkoutsByPlan(
    DatabaseExecutor database,
    List<String> planIds,
  ) async {
    if (planIds.isEmpty) return const {};
    final planPlaceholders = List.filled(planIds.length, '?').join(', ');
    final workoutRows = await database.query(
      'run_plan_workouts',
      where: 'run_plan_id IN ($planPlaceholders)',
      whereArgs: planIds,
      orderBy: 'week_index ASC, order_index ASC',
    );
    if (workoutRows.isEmpty) return const {};
    final ids = workoutRows.map((row) => row['id'] as String).toList();
    final placeholders = List.filled(ids.length, '?').join(', ');
    final stepRows = await database.query(
      'run_workout_steps',
      where: 'run_plan_workout_id IN ($placeholders)',
      whereArgs: ids,
      orderBy: 'order_index ASC',
    );
    final stepsByWorkout = <String, List<RunWorkoutStep>>{};
    for (final row in stepRows) {
      final step = RunWorkoutStep.fromMap(row);
      stepsByWorkout.putIfAbsent(step.runPlanWorkoutId, () => []).add(step);
    }
    final byPlan = <String, List<RunPlanWorkout>>{};
    for (final row in workoutRows) {
      final workout = RunPlanWorkout.fromMap(
        row,
        steps: stepsByWorkout[row['id'] as String] ?? const [],
      );
      byPlan.putIfAbsent(workout.runPlanId, () => []).add(workout);
    }
    return byPlan;
  }

  Future<List<ScheduledRun>> _hydrateScheduled(
    DatabaseExecutor database,
    List<Map<String, Object?>> rows, {
    bool hydrate = true,
  }) async {
    if (rows.isEmpty) return const [];
    if (!hydrate) {
      return rows
          .map((row) => ScheduledRun.fromMap(Map<String, dynamic>.from(row)))
          .toList();
    }
    final workoutIds = rows
        .map((row) => row['run_plan_workout_id'] as String?)
        .whereType<String>()
        .toSet()
        .toList();
    final workouts = <String, RunPlanWorkout>{};
    if (workoutIds.isNotEmpty) {
      final placeholders = List.filled(workoutIds.length, '?').join(', ');
      final workoutRows = await database.query(
        'run_plan_workouts',
        where: 'id IN ($placeholders)',
        whereArgs: workoutIds,
      );
      final stepRows = workoutRows.isEmpty
          ? const <Map<String, Object?>>[]
          : await database.query(
              'run_workout_steps',
              where: 'run_plan_workout_id IN ($placeholders)',
              whereArgs: workoutIds,
              orderBy: 'order_index ASC',
            );
      final stepsByWorkout = <String, List<RunWorkoutStep>>{};
      for (final row in stepRows) {
        final step = RunWorkoutStep.fromMap(row);
        stepsByWorkout.putIfAbsent(step.runPlanWorkoutId, () => []).add(step);
      }
      for (final row in workoutRows) {
        final id = row['id'] as String;
        workouts[id] = RunPlanWorkout.fromMap(
          row,
          steps: stepsByWorkout[id] ?? const [],
        );
      }
    }
    return rows.map((row) {
      final map = Map<String, dynamic>.from(row);
      return ScheduledRun.fromMap(
        map,
        workout: workouts[map['run_plan_workout_id'] as String?],
      );
    }).toList();
  }

  Future<void> _insertWorkoutCopy(
    DatabaseExecutor txn,
    RunPlanWorkout source,
    String planId,
    int weekIndex,
  ) async {
    final now = DateTime.now();
    final newId = _uuid.v4();
    await txn.insert('run_plan_workouts', {
      ...source.toMap(),
      'id': newId,
      'run_plan_id': planId,
      'week_index': weekIndex,
      'created_at': now.toIso8601String(),
    });
    for (final step in source.steps) {
      await txn.insert('run_workout_steps', {
        ...step.toMap(),
        'id': _uuid.v4(),
        'run_plan_workout_id': newId,
      });
    }
  }

  /// Weekly periodization targets keep `run_plan_ids` inside `training_json`.
  Future<void> _clearPlanFromTargets(
    DatabaseExecutor txn,
    String planId,
  ) async {
    final targets = await txn.query(
      'phase_targets',
      columns: ['id', 'training_json'],
    );
    for (final target in targets) {
      final raw = target['training_json'] as String?;
      if (raw == null || raw.isEmpty || !raw.contains(planId)) continue;
      final training = _decodeJson(raw);
      final run = training['run'];
      if (run is! Map) continue;
      final ids = (run['run_plan_ids'] as List?)
          ?.whereType<String>()
          .where((id) => id != planId)
          .toList();
      if (ids == null) continue;
      final updatedRun = Map<String, dynamic>.from(run);
      if (ids.isEmpty) {
        updatedRun.remove('run_plan_ids');
      } else {
        updatedRun['run_plan_ids'] = ids;
      }
      training['run'] = updatedRun;
      await txn.update(
        'phase_targets',
        {'training_json': _encodeJson(training)},
        where: 'id = ?',
        whereArgs: [target['id']],
      );
    }
  }

  Future<String?> _planIdForWorkout(
    DatabaseExecutor database,
    String workoutId,
  ) async {
    final rows = await database.query(
      'run_plan_workouts',
      columns: ['run_plan_id'],
      where: 'id = ?',
      whereArgs: [workoutId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['run_plan_id'] as String?;
  }

  Future<void> _touchPlanForWorkout(
    DatabaseExecutor database,
    String workoutId,
  ) async {
    final planId = await _planIdForWorkout(database, workoutId);
    if (planId != null) await _touchPlan(database, planId);
  }

  Future<void> _touchPlan(DatabaseExecutor database, String planId) =>
      database.update(
        'run_plans',
        {'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [planId],
      );

  /// Older databases (or a failed v45 migration) have no run-plan tables.
  /// Reads that other modules depend on — the phase editor, the calendar, the
  /// run detail screen — degrade to empty instead of throwing.
  static Future<bool> _tableExists(
    DatabaseExecutor database,
    String table,
  ) async {
    final rows = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      [table],
    );
    return rows.isNotEmpty;
  }

  static String? _optional(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static String _date(DateTime value) => DateTime(
    value.year,
    value.month,
    value.day,
  ).toIso8601String().substring(0, 10);

  static DateTime _day(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static DateTime _weekStart(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  /// Guards reads of columns added by a later migration. A device whose
  /// upgrade failed keeps working, minus the newer feature.
  static Future<bool> _columnExists(
    DatabaseExecutor database,
    String table,
    String column,
  ) async {
    final rows = await database.rawQuery('PRAGMA table_info($table)');
    return rows.any((row) => row['name'] == column);
  }
}

Map<String, dynamic> _decodeJson(String raw) {
  final decoded = jsonDecode(raw);
  return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
}

String _encodeJson(Map<String, dynamic> value) => jsonEncode(value);

const Object _sentinel = Object();

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
