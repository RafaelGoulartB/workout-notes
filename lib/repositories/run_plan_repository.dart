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
import 'package:workout_notes/repositories/phase_target_training.dart';
import 'package:workout_notes/utils/date_utils.dart';
import 'package:workout_notes/utils/sql_helpers.dart';

part 'run_plan_repository_ledger.dart';
part 'run_plan_repository_replan.dart';
part 'run_plan_repository_schedule.dart';

/// Repository for structured running plans, their sessions, steps, the dated
/// schedule and per-step results.
class RunPlanRepository extends BaseRepository {
  // ===================== PLANS =====================

  /// Lists plans. With [hydrate] the sessions come along, which is what the
  /// library screen needs to show each plan's weekly volume.
  Future<List<RunPlan>> listPlans({
    bool includeArchived = false,
    bool hydrate = false,
  }) async {
    final database = await db;
    final rows = await database.query(
      'run_plans',
      where: includeArchived ? null : 'status = ?',
      whereArgs: includeArchived ? null : [RunPlanStatus.active.value],
      orderBy: 'updated_at DESC',
    );
    if (!hydrate || rows.isEmpty) {
      return rows.map(RunPlan.fromMap).toList();
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
    final today = dayOf(from ?? DateTime.now());
    var start = today;
    if (from == null) {
      final existing = await getPlan(id);
      final race = existing?.raceDate;
      if (existing != null && race != null && existing.weeks > 0) {
        final raceWeek = mondayOf(race);
        if (!raceWeek.isBefore(mondayOf(today))) {
          start = addDays(raceWeek, -(7 * (existing.weeks - 1)));
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
        {'activated_at': dateKey(start), 'updated_at': now},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
    final plan = await getPlan(id);
    if (plan == null) return 0;
    var created = 0;
    final anchorWeek = mondayOf(start);
    // Only the weeks from here on: back-filling earlier weeks would invent
    // planned sessions the user never had a chance to run.
    final firstWeek = start.isBefore(today)
        ? plan.activeWeekIndexOn(today) ?? 0
        : 0;
    for (var week = firstWeek; week < plan.weeks; week++) {
      created += (await materializeWeek(
        planId: id,
        weekIndex: week,
        weekStart: addDays(anchorWeek, 7 * week),
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
    await database.update(
      'run_plans',
      {'activated_at': null, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
    if (!clearPlanned) return 0;
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
    final total =
        Sqflite.firstIntValue(
          await database.rawQuery(
            'SELECT COUNT(*) FROM run_plan_workouts WHERE run_plan_id = ?',
            [planId],
          ),
        ) ??
        0;
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
    if (plan == null) return 0;
    final wasActivated = plan.isActivated;
    final progress = await getPlanProgress(planId);
    if (progress.isComplete && plan.completionCount == 0) {
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
    final planId = await _planIdForWorkout(database, planWorkoutId);
    if (planId == null) return null;
    final wasComplete = (await getPlanProgress(planId)).isComplete;
    final day = dayOf(date);
    // A plan session is one logical unit, so running Wednesday's workout on
    // Saturday must tick off that same row rather than spawn a twin and leave
    // the original planned forever. Exact date first, then the session's own
    // still-planned row, which is moved to the day it was actually run.
    var existing = await database.query(
      'scheduled_runs',
      columns: ['id'],
      where: 'run_plan_workout_id = ? AND date = ?',
      whereArgs: [planWorkoutId, dateKey(day)],
      limit: 1,
    );
    var moved = false;
    if (existing.isEmpty) {
      // Bounded to the same week either way: a session run a few days late
      // (or early) is the same session, but a row two weeks out belongs to a
      // different week of the plan and must not be cannibalised.
      final from = addDays(day, -6);
      final to = addDays(day, 6);
      existing = await database.query(
        'scheduled_runs',
        columns: ['id'],
        where:
            'run_plan_workout_id = ? AND status = ? AND date BETWEEN ? AND ?',
        whereArgs: [
          planWorkoutId,
          ScheduledRunStatus.planned.value,
          dateKey(from),
          dateKey(to),
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
        'date': dateKey(day),
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
          if (moved) 'date': dateKey(day),
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    final scheduled = await getScheduledRun(id);
    final progress = await getPlanProgress(planId);
    if (!wasComplete && progress.isComplete) {
      await database.rawUpdate(
        'UPDATE run_plans '
        'SET completion_count = completion_count + 1, updated_at = ? '
        'WHERE id = ?',
        [now, planId],
      );
    }
    if (progress.isComplete) {
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
      notes: optionalText(notes),
      goalKind: goalKind,
      raceDate: raceDate,
      weeks: weeks < 1 ? 1 : weeks,
      status: RunPlanStatus.active,
      createdAt: now,
      updatedAt: now,
      templateKey: templateKey,
      config: config,
    );
    await database.insert('run_plans', plan.toMap());
    return plan;
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
      updates['notes'] = optionalText(notes as String?);
    }
    if (goalKind != null) updates['goal_kind'] = goalKind.value;
    if (!identical(raceDate, _sentinel)) {
      final value = raceDate as DateTime?;
      updates['race_date'] = value == null ? null : dateKey(value);
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
    final row = copy.toMap();
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
      notes: optionalText(notes),
      targetDistanceMeters: targetDistanceMeters,
      targetDurationSeconds: targetDurationSeconds,
      targetPaceSecPerKm: targetPaceSecPerKm,
      effortZone: optionalText(effortZone),
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
      updates['notes'] = optionalText(notes as String?);
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
      updates['effort_zone'] = optionalText(effortZone as String?);
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
      notes: optionalText(notes),
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

  /// The session as [scaleWeek] leaves it. Pure, so a preview can show the
  /// exact result before anything is written.
  static RunPlanWorkout scaledWorkout(RunPlanWorkout workout, double factor) {
    int round10(num meters) => ((meters * factor) / 10).round() * 10;
    if (!workout.hasSteps) {
      final distance = workout.targetDistanceMeters;
      final duration = workout.targetDurationSeconds;
      if (distance != null) {
        return workout.copyWith(
          targetDistanceMeters: round10(distance).toDouble(),
        );
      }
      if (duration != null) {
        return workout.copyWith(
          targetDurationSeconds: (duration * factor).round(),
        );
      }
      return workout;
    }
    return workout.copyWith(
      steps: [
        for (final step in workout.steps)
          if (step.role == RunStepRole.work ||
              step.role == RunStepRole.recovery)
            step
          else
            step.copyWith(
              value: step.isDistance
                  ? round10(step.value)
                  : (step.value * factor).round(),
            ),
      ],
    );
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
  Future<void> _clearPlanFromTargets(DatabaseExecutor txn, String planId) =>
      PhaseTargetTraining.removeRunPlan(txn, planId);

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
}

const _uuid = Uuid();

Map<String, dynamic> _decodeJson(String raw) {
  final decoded = jsonDecode(raw);
  return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
}

const Object _sentinel = Object();
