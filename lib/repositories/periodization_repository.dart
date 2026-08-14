import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'package:workout_notes/models/periodization_checkin.dart';
import 'package:workout_notes/models/periodization_metrics.dart';
import 'package:workout_notes/models/periodization_phase.dart';
import 'package:workout_notes/models/periodization_phase_draft.dart';
import 'package:workout_notes/models/periodization_plan.dart';
import 'package:workout_notes/models/periodization_target.dart';

import 'base_repository.dart';

class PeriodizationRepository extends BaseRepository {
  static const _uuid = Uuid();

  Future<List<PeriodizationPlan>> getPlans({
    bool includeArchived = true,
  }) async {
    final database = await db;
    final rows = await database.query(
      'periodization_plans',
      where: includeArchived ? null : "status != 'archived'",
      orderBy:
          "CASE status WHEN 'active' THEN 0 WHEN 'draft' THEN 1 WHEN 'completed' THEN 2 ELSE 3 END, start_date DESC",
    );
    return rows.map(PeriodizationPlan.fromMap).toList();
  }

  Future<PeriodizationPlan?> getPlan(String id) async {
    final database = await db;
    final rows = await database.query(
      'periodization_plans',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : PeriodizationPlan.fromMap(rows.first);
  }

  Future<PeriodizationPlan?> getActivePlan() async {
    final database = await db;
    final rows = await database.query(
      'periodization_plans',
      where: "status = 'active'",
      limit: 1,
    );
    return rows.isEmpty ? null : PeriodizationPlan.fromMap(rows.first);
  }

  Future<PeriodizationPlan> createPlan({
    required String name,
    required DateTime startDate,
    required DateTime endDate,
    String? notes,
    bool activate = true,
  }) async {
    _validateNameAndDates(name, startDate, endDate);
    final now = DateTime.now();
    final plan = PeriodizationPlan(
      id: _uuid.v4(),
      name: name.trim(),
      startDate: _day(startDate),
      endDate: _day(endDate),
      status: activate
          ? PeriodizationPlanStatus.active
          : PeriodizationPlanStatus.draft,
      notes: _optional(notes),
      createdAt: now,
      updatedAt: now,
    );
    final database = await db;
    await database.transaction((txn) async {
      if (activate) await _deactivateCurrent(txn);
      await txn.insert('periodization_plans', plan.toMap());
    });
    return plan;
  }

  Future<PeriodizationPlan> createPlanWithPhases({
    required String name,
    required DateTime startDate,
    required List<PeriodizationPhaseDraft> phases,
    String? notes,
    bool activate = true,
  }) async {
    if (phases.isEmpty) {
      throw const PeriodizationValidationException('plan_requires_phase');
    }
    final sorted = [...phases]
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
    for (var i = 0; i < sorted.length; i++) {
      final phase = sorted[i];
      _validateNameAndDates(phase.name, phase.startDate, phase.endDate);
      if (i > 0 && !phase.startDate.isAfter(sorted[i - 1].endDate)) {
        throw const PeriodizationValidationException('phase_overlap');
      }
    }
    final planEnd = sorted
        .map((phase) => phase.endDate)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    _validateNameAndDates(name, startDate, planEnd);
    final now = DateTime.now();
    final plan = PeriodizationPlan(
      id: _uuid.v4(),
      name: name.trim(),
      startDate: _day(startDate),
      endDate: _day(planEnd),
      status: activate
          ? PeriodizationPlanStatus.active
          : PeriodizationPlanStatus.draft,
      notes: _optional(notes),
      createdAt: now,
      updatedAt: now,
    );
    final database = await db;
    await database.transaction((txn) async {
      if (activate) await _deactivateCurrent(txn);
      await txn.insert('periodization_plans', plan.toMap());
      for (var index = 0; index < sorted.length; index++) {
        final draft = sorted[index];
        final phaseId = _uuid.v4();
        final phase = PeriodizationPhase(
          id: phaseId,
          planId: plan.id,
          name: draft.name.trim(),
          templateKey: draft.templateKey,
          color: draft.color,
          startDate: _day(draft.startDate),
          endDate: _day(draft.endDate),
          intent: _optional(draft.intent),
          orderIndex: index,
          createdAt: now,
          updatedAt: now,
        );
        await txn.insert('periodization_phases', phase.toMap());
        if (draft.target case final target? when !target.isEmpty) {
          await txn.insert(
            'phase_targets',
            _targetMap(
              target,
              phaseId: phaseId,
              version: 1,
              validFrom: phase.startDate,
            ),
          );
        }
        if (draft.routineId case final routineId?) {
          await txn.insert('phase_routine_links', {
            'id': _uuid.v4(),
            'phase_id': phaseId,
            'routine_id': routineId,
            'starts_on': _date(phase.startDate),
            'ends_on': _date(phase.endDate),
            'created_at': now.toIso8601String(),
          });
        }
      }
    });
    return plan;
  }

  Future<void> updatePlan(PeriodizationPlan plan) async {
    _validateNameAndDates(plan.name, plan.startDate, plan.endDate);
    final phases = await getPhases(plan.id);
    if (phases.any(
      (phase) =>
          phase.startDate.isBefore(plan.startDate) ||
          phase.endDate.isAfter(plan.endDate),
    )) {
      throw const PeriodizationValidationException('plan_excludes_phases');
    }
    final database = await db;
    await database.update(
      'periodization_plans',
      {
        'name': plan.name.trim(),
        'start_date': _date(plan.startDate),
        'end_date': _date(plan.endDate),
        'notes': _optional(plan.notes),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [plan.id],
    );
  }

  Future<void> setPlanStatus(String id, PeriodizationPlanStatus status) async {
    final database = await db;
    await database.transaction((txn) async {
      if (status == PeriodizationPlanStatus.active) {
        await _deactivateCurrent(txn, exceptId: id);
      }
      await txn.update(
        'periodization_plans',
        {
          'status': status.value,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<void> deletePlan(String id) async {
    final database = await db;
    await database.delete(
      'periodization_plans',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<PeriodizationPhase>> getPhases(String planId) async {
    final database = await db;
    final rows = await database.query(
      'periodization_phases',
      where: 'plan_id = ?',
      whereArgs: [planId],
      orderBy: 'start_date ASC, order_index ASC',
    );
    return rows.map(PeriodizationPhase.fromMap).toList();
  }

  Future<PeriodizationPhase?> getPhase(String id) async {
    final database = await db;
    final rows = await database.query(
      'periodization_phases',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : PeriodizationPhase.fromMap(rows.first);
  }

  Future<PeriodizationPhase?> getEffectivePhase(DateTime date) async {
    final database = await db;
    final day = _date(date);
    try {
      final rows = await database.rawQuery(
        '''
        SELECT phase.*
        FROM periodization_phases phase
        JOIN periodization_plans plan ON plan.id = phase.plan_id
        WHERE plan.status = 'active'
          AND phase.start_date <= ? AND phase.end_date >= ?
        ORDER BY phase.start_date DESC
        LIMIT 1
      ''',
        [day, day],
      );
      return rows.isEmpty ? null : PeriodizationPhase.fromMap(rows.first);
    } on DatabaseException {
      // Lightweight legacy/test databases may not have reached v37 yet.
      return null;
    }
  }

  Future<List<PeriodizationPhase>> getPhasesInRange(
    DateTime start,
    DateTime end, {
    bool activeOnly = true,
  }) async {
    final database = await db;
    try {
      final rows = await database.rawQuery(
        '''
        SELECT phase.*
        FROM periodization_phases phase
        JOIN periodization_plans plan ON plan.id = phase.plan_id
        WHERE phase.start_date <= ? AND phase.end_date >= ?
          ${activeOnly ? "AND plan.status = 'active'" : ''}
        ORDER BY phase.start_date ASC
      ''',
        [_date(end), _date(start)],
      );
      return rows.map(PeriodizationPhase.fromMap).toList();
    } on DatabaseException {
      return const [];
    }
  }

  Future<PeriodizationPhase> addPhase({
    required String planId,
    required String name,
    required DateTime startDate,
    required DateTime endDate,
    required int color,
    String? intent,
    String? templateKey,
    PeriodizationTarget? target,
    String? routineId,
  }) async {
    _validateNameAndDates(name, startDate, endDate);
    final plan = await getPlan(planId);
    if (plan == null) {
      throw const PeriodizationValidationException('plan_not_found');
    }
    _validateInsidePlan(plan, startDate, endDate);
    await _validateNoOverlap(planId, startDate, endDate);
    final phases = await getPhases(planId);
    final now = DateTime.now();
    final phase = PeriodizationPhase(
      id: _uuid.v4(),
      planId: planId,
      name: name.trim(),
      templateKey: templateKey,
      color: color,
      startDate: _day(startDate),
      endDate: _day(endDate),
      intent: _optional(intent),
      orderIndex: phases.length,
      createdAt: now,
      updatedAt: now,
    );
    final database = await db;
    await database.transaction((txn) async {
      await txn.insert('periodization_phases', phase.toMap());
      if (target != null && !target.isEmpty) {
        await txn.insert(
          'phase_targets',
          _targetMap(
            target,
            phaseId: phase.id,
            version: 1,
            validFrom: phase.startDate,
          ),
        );
      }
      if (routineId != null) {
        await txn.insert('phase_routine_links', {
          'id': _uuid.v4(),
          'phase_id': phase.id,
          'routine_id': routineId,
          'starts_on': _date(phase.startDate),
          'ends_on': _date(phase.endDate),
          'created_at': now.toIso8601String(),
        });
      }
      await _normalizePhaseOrder(txn, planId);
    });
    return phase;
  }

  Future<void> updatePhase(
    PeriodizationPhase phase, {
    bool shiftFollowingPhases = false,
  }) async {
    _validateNameAndDates(phase.name, phase.startDate, phase.endDate);
    final existing = await getPhase(phase.id);
    if (existing == null) {
      throw const PeriodizationValidationException('phase_not_found');
    }
    final plan = await getPlan(existing.planId);
    if (plan == null) {
      throw const PeriodizationValidationException('plan_not_found');
    }
    final deltaDays = phase.endDate.difference(existing.endDate).inDays;
    final all = await getPhases(existing.planId);
    final shifted = <PeriodizationPhase>[];
    for (final candidate in all) {
      if (candidate.id == phase.id) {
        shifted.add(phase);
      } else if (shiftFollowingPhases &&
          candidate.startDate.isAfter(existing.endDate)) {
        shifted.add(
          PeriodizationPhase(
            id: candidate.id,
            planId: candidate.planId,
            name: candidate.name,
            templateKey: candidate.templateKey,
            color: candidate.color,
            startDate: candidate.startDate.add(Duration(days: deltaDays)),
            endDate: candidate.endDate.add(Duration(days: deltaDays)),
            intent: candidate.intent,
            orderIndex: candidate.orderIndex,
            createdAt: candidate.createdAt,
            updatedAt: DateTime.now(),
          ),
        );
      } else {
        shifted.add(candidate);
      }
    }
    shifted.sort((a, b) => a.startDate.compareTo(b.startDate));
    _validatePhaseSequence(shifted);
    if (shifted.first.startDate.isBefore(plan.startDate)) {
      throw const PeriodizationValidationException('phase_outside_plan');
    }
    final newPlanEnd = shifted
        .map((p) => p.endDate)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    if (!shiftFollowingPhases && newPlanEnd.isAfter(plan.endDate)) {
      throw const PeriodizationValidationException('phase_outside_plan');
    }
    final database = await db;
    final linkedRows = shiftFollowingPhases
        ? await database.rawQuery(
            '''
            SELECT link.* FROM phase_routine_links link
            JOIN periodization_phases phase ON phase.id = link.phase_id
            WHERE phase.plan_id = ?
            ''',
            [plan.id],
          )
        : const <Map<String, Object?>>[];
    final targetRows = shiftFollowingPhases
        ? await database.rawQuery(
            '''
            SELECT target.id, target.phase_id, target.valid_from
            FROM phase_targets target
            JOIN periodization_phases phase ON phase.id = target.phase_id
            WHERE phase.plan_id = ?
            ''',
            [plan.id],
          )
        : const <Map<String, Object?>>[];
    await database.transaction((txn) async {
      for (var index = 0; index < shifted.length; index++) {
        final item = shifted[index];
        final original = all.firstWhere((candidate) => candidate.id == item.id);
        final wasShifted =
            item.startDate != original.startDate ||
            item.endDate != original.endDate;
        await txn.update(
          'periodization_phases',
          {
            'name': item.name.trim(),
            'template_key': item.templateKey,
            'color': item.color,
            'start_date': _date(item.startDate),
            'end_date': _date(item.endDate),
            'intent': _optional(item.intent),
            'order_index': index,
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [item.id],
        );
        if (item.id == phase.id) {
          await txn.update(
            'phase_routine_links',
            {
              'starts_on': _date(item.startDate),
              'ends_on': _date(item.endDate),
            },
            where: 'phase_id = ? AND starts_on = ? AND ends_on = ?',
            whereArgs: [
              item.id,
              _date(existing.startDate),
              _date(existing.endDate),
            ],
          );
        } else if (wasShifted) {
          for (final link in linkedRows.where(
            (row) => row['phase_id'] == item.id,
          )) {
            final startsOn = DateTime.parse(
              link['starts_on'] as String,
            ).add(Duration(days: deltaDays));
            final endsOn = DateTime.parse(
              link['ends_on'] as String,
            ).add(Duration(days: deltaDays));
            await txn.update(
              'phase_routine_links',
              {'starts_on': _date(startsOn), 'ends_on': _date(endsOn)},
              where: 'id = ?',
              whereArgs: [link['id']],
            );
          }
          for (final target in targetRows.where(
            (row) => row['phase_id'] == item.id,
          )) {
            final validFrom = DateTime.parse(
              target['valid_from'] as String,
            ).add(Duration(days: deltaDays));
            await txn.update(
              'phase_targets',
              {'valid_from': _date(validFrom)},
              where: 'id = ?',
              whereArgs: [target['id']],
            );
          }
        }
      }
      if (shiftFollowingPhases && newPlanEnd != plan.endDate) {
        await txn.update(
          'periodization_plans',
          {
            'end_date': _date(newPlanEnd),
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [plan.id],
        );
      }
    });
  }

  Future<void> deletePhase(String id) async {
    final phase = await getPhase(id);
    if (phase == null) return;
    final database = await db;
    await database.transaction((txn) async {
      await txn.delete(
        'periodization_phases',
        where: 'id = ?',
        whereArgs: [id],
      );
      await _normalizePhaseOrder(txn, phase.planId);
    });
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
    final effectiveDate = _date(date ?? DateTime.now());
    final rows = await database.query(
      'phase_targets',
      where: 'phase_id = ? AND valid_from <= ?',
      whereArgs: [phaseId, effectiveDate],
      orderBy: 'valid_from DESC, version DESC',
      limit: 1,
    );
    if (rows.isNotEmpty) return PeriodizationTarget.fromMap(rows.first);
    final fallback = await database.query(
      'phase_targets',
      where: 'phase_id = ?',
      whereArgs: [phaseId],
      orderBy: 'version ASC',
      limit: 1,
    );
    return fallback.isEmpty
        ? null
        : PeriodizationTarget.fromMap(fallback.first);
  }

  Future<PeriodizationTarget> saveTargetVersion(
    String phaseId,
    PeriodizationTarget target, {
    DateTime? validFrom,
  }) async {
    _validateTarget(target);
    final phase = await getPhase(phaseId);
    if (phase == null) {
      throw const PeriodizationValidationException('phase_not_found');
    }
    final history = await getTargetHistory(phaseId);
    final version = history.isEmpty ? 1 : history.first.version + 1;
    final today = _day(DateTime.now());
    final effective = _day(
      validFrom ?? (today.isAfter(phase.startDate) ? today : phase.startDate),
    );
    if (effective.isAfter(phase.endDate)) {
      throw const PeriodizationValidationException('target_outside_phase');
    }
    final saved = PeriodizationTarget(
      id: _uuid.v4(),
      phaseId: phaseId,
      version: version,
      validFrom: effective,
      calories: target.calories,
      proteinG: target.proteinG,
      carbsG: target.carbsG,
      fatG: target.fatG,
      workoutsPerWeek: target.workoutsPerWeek,
      minSetsPerWeek: target.minSetsPerWeek,
      maxSetsPerWeek: target.maxSetsPerWeek,
      minRpe: target.minRpe,
      maxRpe: target.maxRpe,
      targetWeightKg: target.targetWeightKg,
      weeklyWeightChangePercent: target.weeklyWeightChangePercent,
      sleepHours: target.sleepHours,
      createdAt: DateTime.now(),
    );
    final database = await db;
    await database.insert('phase_targets', saved.toMap());
    return saved;
  }

  Future<List<Map<String, dynamic>>> getRoutineLinks(String phaseId) async {
    final database = await db;
    return database.rawQuery(
      '''
      SELECT link.*, routine.name AS routine_name
      FROM phase_routine_links link
      JOIN routines routine ON routine.id = link.routine_id
      WHERE link.phase_id = ?
      ORDER BY link.starts_on ASC
    ''',
      [phaseId],
    );
  }

  Future<String> saveRoutineLink({
    String? id,
    required String phaseId,
    required String routineId,
    required DateTime startsOn,
    required DateTime endsOn,
  }) async {
    final phase = await getPhase(phaseId);
    if (phase == null) {
      throw const PeriodizationValidationException('phase_not_found');
    }
    if (startsOn.isBefore(phase.startDate) ||
        endsOn.isAfter(phase.endDate) ||
        endsOn.isBefore(startsOn)) {
      throw const PeriodizationValidationException(
        'routine_link_outside_phase',
      );
    }
    final database = await db;
    final overlap =
        Sqflite.firstIntValue(
          await database.rawQuery(
            '''
      SELECT COUNT(*) FROM phase_routine_links
      WHERE phase_id = ? AND id != ? AND starts_on <= ? AND ends_on >= ?
    ''',
            [phaseId, id ?? '', _date(endsOn), _date(startsOn)],
          ),
        ) ??
        0;
    if (overlap > 0) {
      throw const PeriodizationValidationException('routine_link_overlap');
    }
    final linkId = id ?? _uuid.v4();
    await database.insert('phase_routine_links', {
      'id': linkId,
      'phase_id': phaseId,
      'routine_id': routineId,
      'starts_on': _date(startsOn),
      'ends_on': _date(endsOn),
      'created_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return linkId;
  }

  Future<void> deleteRoutineLink(String id) async {
    final database = await db;
    await database.delete(
      'phase_routine_links',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<PeriodizationCheckin>> getCheckins(String phaseId) async {
    final database = await db;
    final rows = await database.query(
      'periodization_checkins',
      where: 'phase_id = ?',
      whereArgs: [phaseId],
      orderBy: 'week_start DESC',
    );
    return rows.map(PeriodizationCheckin.fromMap).toList();
  }

  Future<PeriodizationCheckin?> getCheckin(
    String phaseId,
    DateTime weekStart,
  ) async {
    final database = await db;
    final rows = await database.query(
      'periodization_checkins',
      where: 'phase_id = ? AND week_start = ?',
      whereArgs: [phaseId, _date(_weekStart(weekStart))],
      limit: 1,
    );
    return rows.isEmpty ? null : PeriodizationCheckin.fromMap(rows.first);
  }

  Future<void> saveCheckin(PeriodizationCheckin checkin) async {
    if (checkin.energy < 1 ||
        checkin.energy > 5 ||
        checkin.hunger < 1 ||
        checkin.hunger > 5 ||
        checkin.recovery < 1 ||
        checkin.recovery > 5) {
      throw const PeriodizationValidationException('checkin_rating_invalid');
    }
    final database = await db;
    await database.transaction((txn) async {
      await txn.delete(
        'periodization_checkins',
        where: 'phase_id = ? AND week_start = ?',
        whereArgs: [checkin.phaseId, _date(_weekStart(checkin.weekStart))],
      );
      await txn.insert('periodization_checkins', checkin.toMap());
    });
  }

  Future<PeriodizationMetrics> getPhaseMetrics(
    PeriodizationPhase phase, {
    DateTime? rangeStart,
    DateTime? rangeEnd,
  }) async {
    final now = _day(DateTime.now());
    final start = _day(rangeStart ?? phase.startDate);
    var end = _day(rangeEnd ?? phase.endDate);
    if (end.isAfter(now)) end = now;
    if (end.isBefore(start)) end = start;
    final database = await db;
    final startText = _date(start);
    final endText = _date(end);

    final workoutRows = await database.rawQuery(
      '''
      SELECT COUNT(DISTINCT w.id) AS workout_count,
             COUNT(CASE WHEN s.is_complete = 1 AND s.is_warmup = 0 THEN 1 END) AS set_count,
             SUM(CASE WHEN s.is_complete = 1 AND s.is_warmup = 0
                      THEN COALESCE(s.weight, 0) * COALESCE(s.reps, 0) ELSE 0 END) AS volume
      FROM workouts w
      LEFT JOIN exercise_entries ee ON ee.workout_id = w.id
      LEFT JOIN sets s ON s.exercise_entry_id = ee.id
      WHERE w.date BETWEEN ? AND ? AND w.end_time IS NOT NULL
    ''',
      [startText, endText],
    );
    final workout = workoutRows.first;

    final nutritionRows = await database.rawQuery(
      '''
      SELECT ml.date,
             SUM(COALESCE(item.calories, 0)) AS calories,
             SUM(COALESCE(item.protein_g, 0)) AS protein_g
      FROM meal_logs ml
      JOIN meal_log_items item ON item.meal_log_id = ml.id
      WHERE ml.date BETWEEN ? AND ?
      GROUP BY ml.date
      ORDER BY ml.date ASC
    ''',
      [startText, endText],
    );
    final targetHistory = await getTargetHistory(phase.id);
    double calorieSum = 0;
    double proteinSum = 0;
    double adherenceSum = 0;
    var adherenceDays = 0;
    for (final row in nutritionRows) {
      final calories = (row['calories'] as num?)?.toDouble() ?? 0;
      calorieSum += calories;
      proteinSum += (row['protein_g'] as num?)?.toDouble() ?? 0;
      final date = DateTime.parse(row['date'] as String);
      final target = _targetForDate(targetHistory, date)?.calories;
      if (target != null && target > 0) {
        adherenceSum += math.max(0, 1 - (calories - target).abs() / target);
        adherenceDays++;
      }
    }

    final weights = await database.query(
      'body_measurements',
      where: "type = 'weight' AND date BETWEEN ? AND ?",
      whereArgs: [startText, endText],
      orderBy: 'date ASC, created_at ASC',
    );
    final normalizedWeights = weights
        .map(_weightKg)
        .whereType<double>()
        .toList();

    final sleepRows = await database.rawQuery(
      '''
      SELECT AVG(COALESCE(actual_sleep_minutes, estimated_sleep_minutes, sleep_minutes)) AS average_minutes,
             COUNT(*) AS logged_days
      FROM sleep_entries WHERE date BETWEEN ? AND ?
    ''',
      [startText, endText],
    );
    final latestTarget = _targetForDate(targetHistory, end);
    final elapsedDays = end.difference(start).inDays + 1;
    final elapsedWeeks = elapsedDays / 7;
    return PeriodizationMetrics(
      startDate: start,
      endDate: end,
      elapsedDays: elapsedDays,
      workoutCount: (workout['workout_count'] as num?)?.toInt() ?? 0,
      completedSets: (workout['set_count'] as num?)?.toInt() ?? 0,
      volume: (workout['volume'] as num?)?.toDouble() ?? 0,
      plannedWorkouts: latestTarget?.workoutsPerWeek == null
          ? null
          : (latestTarget!.workoutsPerWeek! * elapsedWeeks).round(),
      plannedSetsMinimum: latestTarget?.minSetsPerWeek == null
          ? null
          : (latestTarget!.minSetsPerWeek! * elapsedWeeks).round(),
      nutritionDaysLogged: nutritionRows.length,
      averageCalories: nutritionRows.isEmpty
          ? null
          : calorieSum / nutritionRows.length,
      averageProteinG: nutritionRows.isEmpty
          ? null
          : proteinSum / nutritionRows.length,
      nutritionAdherencePercent: adherenceDays == 0
          ? null
          : adherenceSum / adherenceDays * 100,
      startingWeightKg: normalizedWeights.isEmpty
          ? null
          : normalizedWeights.first,
      endingWeightKg: normalizedWeights.isEmpty ? null : normalizedWeights.last,
      weightChangeKg: normalizedWeights.length < 2
          ? null
          : normalizedWeights.last - normalizedWeights.first,
      averageSleepHours:
          (sleepRows.first['average_minutes'] as num?)?.toDouble() == null
          ? null
          : (sleepRows.first['average_minutes'] as num).toDouble() / 60,
      sleepDaysLogged: (sleepRows.first['logged_days'] as num?)?.toInt() ?? 0,
    );
  }

  Future<PeriodizationMetrics> getWeekMetrics(
    PeriodizationPhase phase,
    DateTime weekStart,
  ) => getPhaseMetrics(
    phase,
    rangeStart: _weekStart(weekStart).isBefore(phase.startDate)
        ? phase.startDate
        : _weekStart(weekStart),
    rangeEnd:
        _weekStart(
          weekStart,
        ).add(const Duration(days: 6)).isAfter(phase.endDate)
        ? phase.endDate
        : _weekStart(weekStart).add(const Duration(days: 6)),
  );

  static Future<void> _deactivateCurrent(
    DatabaseExecutor txn, {
    String? exceptId,
  }) async {
    await txn.update(
      'periodization_plans',
      {
        'status': PeriodizationPlanStatus.archived.value,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: exceptId == null
          ? "status = 'active'"
          : "status = 'active' AND id != ?",
      whereArgs: exceptId == null ? null : [exceptId],
    );
  }

  Future<void> _validateNoOverlap(
    String planId,
    DateTime start,
    DateTime end, {
    String? exceptId,
  }) async {
    final database = await db;
    final count =
        Sqflite.firstIntValue(
          await database.rawQuery(
            '''
      SELECT COUNT(*) FROM periodization_phases
      WHERE plan_id = ? AND id != ? AND start_date <= ? AND end_date >= ?
    ''',
            [planId, exceptId ?? '', _date(end), _date(start)],
          ),
        ) ??
        0;
    if (count > 0) {
      throw const PeriodizationValidationException('phase_overlap');
    }
  }

  static void _validateNameAndDates(String name, DateTime start, DateTime end) {
    if (name.trim().isEmpty) {
      throw const PeriodizationValidationException('name_required');
    }
    if (_day(end).isBefore(_day(start))) {
      throw const PeriodizationValidationException('invalid_date_range');
    }
  }

  static void _validateInsidePlan(
    PeriodizationPlan plan,
    DateTime start,
    DateTime end,
  ) {
    if (_day(start).isBefore(plan.startDate) ||
        _day(end).isAfter(plan.endDate)) {
      throw const PeriodizationValidationException('phase_outside_plan');
    }
  }

  static void _validatePhaseSequence(List<PeriodizationPhase> phases) {
    for (var i = 1; i < phases.length; i++) {
      if (!phases[i].startDate.isAfter(phases[i - 1].endDate)) {
        throw const PeriodizationValidationException('phase_overlap');
      }
    }
  }

  static void _validateTarget(PeriodizationTarget target) {
    for (final value in [
      target.calories,
      target.proteinG,
      target.carbsG,
      target.fatG,
      target.targetWeightKg,
      target.sleepHours,
    ]) {
      if (value != null && (!value.isFinite || value <= 0)) {
        throw const PeriodizationValidationException('invalid_target');
      }
    }
    if (target.workoutsPerWeek != null &&
        (target.workoutsPerWeek! < 1 || target.workoutsPerWeek! > 14)) {
      throw const PeriodizationValidationException('invalid_target');
    }
    if (target.minSetsPerWeek != null &&
        target.maxSetsPerWeek != null &&
        target.minSetsPerWeek! > target.maxSetsPerWeek!) {
      throw const PeriodizationValidationException('invalid_target_range');
    }
    if (target.minRpe != null &&
        target.maxRpe != null &&
        target.minRpe! > target.maxRpe!) {
      throw const PeriodizationValidationException('invalid_target_range');
    }
    if (target.weeklyWeightChangePercent != null &&
        (!target.weeklyWeightChangePercent!.isFinite ||
            target.weeklyWeightChangePercent!.abs() > 5)) {
      throw const PeriodizationValidationException('invalid_target');
    }
  }

  static Map<String, dynamic> _targetMap(
    PeriodizationTarget target, {
    required String phaseId,
    required int version,
    required DateTime validFrom,
  }) {
    final remapped = PeriodizationTarget(
      id: _uuid.v4(),
      phaseId: phaseId,
      version: version,
      validFrom: validFrom,
      calories: target.calories,
      proteinG: target.proteinG,
      carbsG: target.carbsG,
      fatG: target.fatG,
      workoutsPerWeek: target.workoutsPerWeek,
      minSetsPerWeek: target.minSetsPerWeek,
      maxSetsPerWeek: target.maxSetsPerWeek,
      minRpe: target.minRpe,
      maxRpe: target.maxRpe,
      targetWeightKg: target.targetWeightKg,
      weeklyWeightChangePercent: target.weeklyWeightChangePercent,
      sleepHours: target.sleepHours,
      createdAt: DateTime.now(),
    );
    return remapped.toMap();
  }

  static PeriodizationTarget? _targetForDate(
    List<PeriodizationTarget> targets,
    DateTime date,
  ) {
    final eligible =
        targets.where((target) => !target.validFrom.isAfter(date)).toList()
          ..sort((a, b) {
            final byDate = b.validFrom.compareTo(a.validFrom);
            return byDate == 0 ? b.version.compareTo(a.version) : byDate;
          });
    if (eligible.isNotEmpty) return eligible.first;
    if (targets.isEmpty) return null;
    final oldest = [...targets]..sort((a, b) => a.version.compareTo(b.version));
    return oldest.first;
  }

  static double? _weightKg(Map<String, Object?> row) {
    final value = (row['value'] as num?)?.toDouble();
    if (value == null) return null;
    final unit = (row['unit'] as String? ?? 'kg').toLowerCase();
    return unit == 'lb' || unit == 'lbs' ? value * 0.45359237 : value;
  }

  static Future<void> _normalizePhaseOrder(
    DatabaseExecutor txn,
    String planId,
  ) async {
    final rows = await txn.query(
      'periodization_phases',
      columns: ['id'],
      where: 'plan_id = ?',
      whereArgs: [planId],
      orderBy: 'start_date ASC',
    );
    for (var i = 0; i < rows.length; i++) {
      await txn.update(
        'periodization_phases',
        {'order_index': i},
        where: 'id = ?',
        whereArgs: [rows[i]['id']],
      );
    }
  }

  static DateTime _day(DateTime date) =>
      DateTime(date.year, date.month, date.day);
  static DateTime _weekStart(DateTime date) {
    final day = _day(date);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  static String _date(DateTime date) =>
      _day(date).toIso8601String().substring(0, 10);
  static String? _optional(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();
}

class PeriodizationValidationException implements Exception {
  final String code;
  const PeriodizationValidationException(this.code);

  @override
  String toString() => 'PeriodizationValidationException($code)';
}
