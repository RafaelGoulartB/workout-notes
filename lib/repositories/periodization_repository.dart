import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'package:workout_notes/models/periodization_checkin.dart';
import 'package:workout_notes/models/periodization_metrics.dart';
import 'package:workout_notes/models/periodization_phase.dart';
import 'package:workout_notes/models/periodization_phase_draft.dart';
import 'package:workout_notes/models/periodization_plan.dart';
import 'package:workout_notes/models/periodization_projection.dart';
import 'package:workout_notes/models/periodization_routine_suggestion.dart';
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
    var rows = await database.query(
      'periodization_plans',
      where: "status = 'active'",
      limit: 1,
    );
    if (rows.isNotEmpty) {
      final endDate = DateTime.parse(rows.first['end_date'] as String);
      if (_day(endDate).isBefore(_day(DateTime.now()))) {
        await database.update(
          'periodization_plans',
          {
            'status': PeriodizationPlanStatus.completed.value,
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [rows.first['id']],
        );
        rows = const [];
      }
    }
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
      if (phase.target case final target? when !target.isEmpty) {
        _validateTarget(target);
      }
      if (phase.weeklyTargets != null) {
        _validateWeeklyWindow(
          _day(phase.startDate),
          _day(phase.startDate),
          _day(phase.endDate),
          phase.weeklyTargets!,
        );
      }
      if (i > 0 && !phase.startDate.isAfter(sorted[i - 1].endDate)) {
        throw const PeriodizationValidationException('phase_overlap');
      }
    }
    if (_day(sorted.first.startDate).isBefore(_day(startDate))) {
      throw const PeriodizationValidationException('phase_outside_plan');
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
        if (draft.weeklyTargets != null) {
          await _replaceTargetsFrom(
            txn,
            phaseId: phaseId,
            phaseEnd: phase.endDate,
            boundary: phase.startDate,
            weeks: draft.weeklyTargets!,
          );
        } else if (draft.target case final target? when !target.isEmpty) {
          await _validateRoutineReferences(txn, [target]);
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
        final phaseCount =
            Sqflite.firstIntValue(
              await txn.rawQuery(
                'SELECT COUNT(*) FROM periodization_phases WHERE plan_id = ?',
                [id],
              ),
            ) ??
            0;
        if (phaseCount == 0) {
          throw const PeriodizationValidationException('plan_requires_phase');
        }
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
    List<PeriodizationTarget>? weeklyTargets,
  }) async {
    _validateNameAndDates(name, startDate, endDate);
    if (target != null && !target.isEmpty) _validateTarget(target);
    if (weeklyTargets != null) {
      _validateWeeklyWindow(
        _day(startDate),
        _day(startDate),
        _day(endDate),
        weeklyTargets,
      );
    }
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
      if (weeklyTargets != null) {
        await _replaceTargetsFrom(
          txn,
          phaseId: phase.id,
          phaseEnd: phase.endDate,
          boundary: phase.startDate,
          weeks: weeklyTargets,
        );
      } else if (target != null && !target.isEmpty) {
        await _validateRoutineReferences(txn, [target]);
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
      await _normalizePhaseOrder(txn, planId);
    });
    return phase;
  }

  Future<void> updatePhase(
    PeriodizationPhase phase, {
    bool shiftFollowingPhases = false,
  }) => _updatePhase(phase, shiftFollowingPhases: shiftFollowingPhases);

  Future<void> updatePhaseWithTargets(
    PeriodizationPhase phase, {
    required bool shiftFollowingPhases,
    required bool targetChanged,
    PeriodizationTarget? target,
    List<PeriodizationTarget>? weeklyTargets,
    DateTime? weeklyReplaceFrom,
  }) => _updatePhase(
    phase,
    shiftFollowingPhases: shiftFollowingPhases,
    targetChanged: targetChanged,
    target: target,
    weeklyTargets: weeklyTargets,
    weeklyReplaceFrom: weeklyReplaceFrom,
  );

  Future<void> _updatePhase(
    PeriodizationPhase phase, {
    required bool shiftFollowingPhases,
    bool targetChanged = false,
    PeriodizationTarget? target,
    List<PeriodizationTarget>? weeklyTargets,
    DateTime? weeklyReplaceFrom,
  }) async {
    _validateNameAndDates(phase.name, phase.startDate, phase.endDate);
    if (targetChanged) {
      if (weeklyTargets != null) {
        _validateWeeklyWindow(
          _weeklyBoundary(phase, weeklyReplaceFrom),
          phase.startDate,
          phase.endDate,
          weeklyTargets,
        );
      } else {
        if (target == null) {
          throw const PeriodizationValidationException('invalid_target');
        }
        _validateTarget(target);
      }
    }
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
    final targetRows = await database.rawQuery(
      '''
      SELECT target.id, target.phase_id, target.valid_from, target.version
      FROM phase_targets target
      JOIN periodization_phases phase ON phase.id = target.phase_id
      WHERE phase.plan_id = ?
      ''',
      [plan.id],
    );
    final checkinRows = await database.rawQuery(
      '''
      SELECT checkin.phase_id, checkin.week_start
      FROM periodization_checkins checkin
      JOIN periodization_phases phase ON phase.id = checkin.phase_id
      WHERE phase.plan_id = ?
      ''',
      [plan.id],
    );
    final startDeltaDays = phase.startDate
        .difference(existing.startDate)
        .inDays;
    final weeklyBoundary = weeklyTargets == null
        ? null
        : _weeklyBoundary(phase, weeklyReplaceFrom);

    int dateShiftFor(PeriodizationPhase item) {
      if (item.id == phase.id) return startDeltaDays;
      final original = all.firstWhere((candidate) => candidate.id == item.id);
      return item.startDate.difference(original.startDate).inDays;
    }

    for (final item in shifted) {
      for (final checkin in checkinRows.where(
        (row) => row['phase_id'] == item.id,
      )) {
        final weekStart = DateTime.parse(checkin['week_start'] as String);
        final weekEnd = weekStart.add(const Duration(days: 6));
        if (weekEnd.isBefore(item.startDate) ||
            weekStart.isAfter(item.endDate)) {
          throw const PeriodizationValidationException(
            'replan_excludes_checkins',
          );
        }
      }
      final dateShift = dateShiftFor(item);
      for (final targetRow in targetRows.where(
        (row) => row['phase_id'] == item.id,
      )) {
        final projected = DateTime.parse(
          targetRow['valid_from'] as String,
        ).add(Duration(days: dateShift));
        // Weekly replacement deletes this phase's versions on or after the
        // boundary, so those rows may shift out of bounds harmlessly.
        final replacedByWeekly =
            weeklyBoundary != null &&
            item.id == phase.id &&
            !projected.isBefore(weeklyBoundary);
        if (!replacedByWeekly &&
            (projected.isBefore(item.startDate) ||
                projected.isAfter(item.endDate))) {
          throw const PeriodizationValidationException(
            'replan_excludes_targets',
          );
        }
      }
    }

    final nextTargetVersion =
        targetRows
            .where((row) => row['phase_id'] == phase.id)
            .map((row) => (row['version'] as num).toInt())
            .fold<int>(0, math.max) +
        1;
    final today = _day(DateTime.now());
    final newTargetValidFrom = _day(
      today.isAfter(phase.startDate) ? today : phase.startDate,
    );
    if (targetChanged &&
        weeklyTargets == null &&
        newTargetValidFrom.isAfter(phase.endDate)) {
      throw const PeriodizationValidationException('target_outside_phase');
    }

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
        if (wasShifted) {
          final dateShift = dateShiftFor(item);
          for (final target in targetRows.where(
            (row) => row['phase_id'] == item.id,
          )) {
            final validFrom = DateTime.parse(
              target['valid_from'] as String,
            ).add(Duration(days: dateShift));
            await txn.update(
              'phase_targets',
              {'valid_from': _date(validFrom)},
              where: 'id = ?',
              whereArgs: [target['id']],
            );
          }
        }
      }
      if (targetChanged) {
        if (weeklyTargets != null && weeklyBoundary != null) {
          await _replaceTargetsFrom(
            txn,
            phaseId: phase.id,
            phaseEnd: phase.endDate,
            boundary: weeklyBoundary,
            weeks: weeklyTargets,
          );
        } else {
          await _validateRoutineReferences(txn, [target!]);
          await txn.insert(
            'phase_targets',
            _targetMap(
              target,
              phaseId: phase.id,
              version: nextTargetVersion,
              validFrom: newTargetValidFrom,
            ),
          );
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

  Future<void> endPhaseEarly(
    String phaseId,
    DateTime endDate, {
    required bool shiftFollowingPhases,
  }) async {
    final phase = await getPhase(phaseId);
    if (phase == null) {
      throw const PeriodizationValidationException('phase_not_found');
    }
    final effectiveEnd = _day(endDate);
    if (effectiveEnd.isBefore(phase.startDate) ||
        !effectiveEnd.isBefore(phase.endDate)) {
      throw const PeriodizationValidationException('invalid_date_range');
    }
    await updatePhase(
      PeriodizationPhase(
        id: phase.id,
        planId: phase.planId,
        name: phase.name,
        templateKey: phase.templateKey,
        color: phase.color,
        startDate: phase.startDate,
        endDate: effectiveEnd,
        intent: phase.intent,
        orderIndex: phase.orderIndex,
        createdAt: phase.createdAt,
        updatedAt: DateTime.now(),
      ),
      shiftFollowingPhases: shiftFollowingPhases,
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
    final effectiveDate = _date(date ?? DateTime.now());
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
      proteinGPerKg: target.proteinGPerKg,
      fatGPerKg: target.fatGPerKg,
      weightKgUsed: target.weightKgUsed,
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

  /// Saves one effective target per phase week (index 0 = first week).
  ///
  /// Consecutive identical weeks collapse into a single `phase_targets`
  /// version: week k starts at `phase.startDate + (k − 1) × 7` days and the
  /// effective target only changes where the week actually differs from the
  /// previous one. When [replaceFrom] is given, existing versions with
  /// `valid_from` on or after that date are replaced and earlier versions
  /// (locked history) are preserved.
  Future<void> saveWeeklyTargets(
    String phaseId,
    List<PeriodizationTarget> weeks, {
    DateTime? replaceFrom,
  }) async {
    final phase = await getPhase(phaseId);
    if (phase == null) {
      throw const PeriodizationValidationException('phase_not_found');
    }
    final boundary = _weeklyBoundary(phase, replaceFrom);
    _validateWeeklyWindow(boundary, phase.startDate, phase.endDate, weeks);
    final database = await db;
    await database.transaction((txn) async {
      await _replaceTargetsFrom(
        txn,
        phaseId: phaseId,
        phaseEnd: phase.endDate,
        boundary: boundary,
        weeks: weeks,
      );
    });
  }

  /// Resolves the routine linked to the active phase on [date].
  ///
  /// The routines come from the effective weekly target (`routine_ids` inside
  /// `training_json`) — each phase week may carry its own routine sequence.
  /// Falls back to legacy `phase_routine_links` rows for phases created before
  /// the weekly-routine model.
  Future<PeriodizationRoutineSuggestion?> getRoutineSuggestion(
    DateTime date,
  ) async {
    final day = _day(date);
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
      for (final routineId in routineIds) {
        final routineRows = await database.query(
          'routines',
          where: 'id = ?',
          whereArgs: [routineId],
          limit: 1,
        );
        if (routineRows.isEmpty) continue;
        final routineDays = await database.query(
          'routine_days',
          where: 'routine_id = ?',
          whereArgs: [routineId],
          orderBy: 'order_index ASC',
        );
        for (final day in routineDays) {
          sequence.add((
            routineId: routineId,
            routineName: routineRows.first['name'] as String,
            dayId: day['id'] as String,
            dayName: day['name'] as String? ?? '',
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
                _date(
                  _weekStart(day).isBefore(phase.startDate)
                      ? phase.startDate
                      : _weekStart(day),
                ),
                _date(day),
              ],
            ),
          ) ??
          0;
      final index = completed % sequence.length;
      final nextDay = sequence[index];
      return PeriodizationRoutineSuggestion(
        phaseId: phase.id,
        linkId: '',
        routineId: nextDay.routineId,
        routineName: nextDay.routineName,
        routineDayId: nextDay.dayId,
        routineDayName: nextDay.dayName,
        routineDayIndex: index,
        routineDayCount: sequence.length,
        completedWorkouts: completed,
      );
    }
    // Legacy phases linked before the weekly-routine model.
    final links = await database.rawQuery(
      '''
      SELECT link.*, routine.name AS routine_name
      FROM phase_routine_links link
      JOIN routines routine ON routine.id = link.routine_id
      WHERE link.phase_id = ? AND link.starts_on <= ? AND link.ends_on >= ?
      ORDER BY link.starts_on DESC
      LIMIT 1
      ''',
      [phase.id, _date(day), _date(day)],
    );
    if (links.isEmpty) return null;
    final link = links.first;
    final routineDays = await database.query(
      'routine_days',
      where: 'routine_id = ?',
      whereArgs: [link['routine_id']],
      orderBy: 'order_index ASC',
    );
    if (routineDays.isEmpty) return null;
    final completed =
        Sqflite.firstIntValue(
          await database.rawQuery(
            '''
            SELECT COUNT(*) FROM workouts
            WHERE routine_id = ? AND end_time IS NOT NULL
              AND date BETWEEN ? AND ?
            ''',
            [link['routine_id'], link['starts_on'], _date(day)],
          ),
        ) ??
        0;
    final index = completed % routineDays.length;
    final nextDay = routineDays[index];
    return PeriodizationRoutineSuggestion(
      phaseId: phase.id,
      linkId: link['id'] as String,
      routineId: link['routine_id'] as String,
      routineName: link['routine_name'] as String,
      routineDayId: nextDay['id'] as String,
      routineDayName: nextDay['name'] as String? ?? '',
      routineDayIndex: index,
      routineDayCount: routineDays.length,
      completedWorkouts: completed,
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
    final phase = await getPhase(checkin.phaseId);
    if (phase == null) {
      throw const PeriodizationValidationException('phase_not_found');
    }
    final normalizedWeek = _weekStart(checkin.weekStart);
    final weekEnd = normalizedWeek.add(const Duration(days: 6));
    if (weekEnd.isBefore(phase.startDate) ||
        normalizedWeek.isAfter(phase.endDate)) {
      throw const PeriodizationValidationException('checkin_outside_phase');
    }
    final normalized = PeriodizationCheckin(
      id: checkin.id,
      phaseId: checkin.phaseId,
      weekStart: normalizedWeek,
      energy: checkin.energy,
      hunger: checkin.hunger,
      recovery: checkin.recovery,
      performance: checkin.performance,
      decision: checkin.decision,
      notes: checkin.notes,
      metricsSnapshot: checkin.metricsSnapshot,
      targetsSnapshot: checkin.targetsSnapshot,
      createdAt: checkin.createdAt,
    );
    final database = await db;
    await database.transaction((txn) async {
      await txn.delete(
        'periodization_checkins',
        where: 'phase_id = ? AND week_start = ?',
        whereArgs: [checkin.phaseId, _date(normalizedWeek)],
      );
      await txn.insert('periodization_checkins', normalized.toMap());
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
    if (end.isBefore(start)) {
      return PeriodizationMetrics(
        startDate: start,
        endDate: end,
        elapsedDays: 0,
        workoutCount: 0,
        completedSets: 0,
        volume: 0,
        nutritionDaysLogged: 0,
        sleepDaysLogged: 0,
      );
    }
    final database = await db;
    final startText = _date(start);
    final endText = _date(end);
    final targetHistory = await getTargetHistory(phase.id);
    final routineIds = <String>{};
    for (
      var date = start;
      !date.isAfter(end);
      date = date.add(const Duration(days: 1))
    ) {
      routineIds.addAll(
        _targetForDate(targetHistory, date)?.routineIds ?? const [],
      );
    }
    final routineFilter = routineIds.isEmpty
        ? ''
        : ' AND w.routine_id IN (${List.filled(routineIds.length, '?').join(', ')})';
    final routineArgs = routineIds.toList();

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
         $routineFilter
     ''',
      [startText, endText, ...routineArgs],
    );
    final workout = workoutRows.first;

    final nutritionRows = await database.rawQuery(
      '''
      SELECT ml.date,
             SUM(COALESCE(item.calories, 0)) AS calories,
             SUM(COALESCE(item.protein_g, 0)) AS protein_g,
             SUM(COALESCE(item.carbs_g, 0)) AS carbs_g,
             SUM(COALESCE(item.fat_g, 0)) AS fat_g
      FROM meal_logs ml
      JOIN meal_log_items item ON item.meal_log_id = ml.id
      WHERE ml.date BETWEEN ? AND ?
      GROUP BY ml.date
      ORDER BY ml.date ASC
    ''',
      [startText, endText],
    );
    double calorieSum = 0;
    double proteinSum = 0;
    double carbsSum = 0;
    double fatSum = 0;
    final nutritionByDate = <String, Map<String, Object?>>{};
    for (final row in nutritionRows) {
      final calories = (row['calories'] as num?)?.toDouble() ?? 0;
      calorieSum += calories;
      proteinSum += (row['protein_g'] as num?)?.toDouble() ?? 0;
      carbsSum += (row['carbs_g'] as num?)?.toDouble() ?? 0;
      fatSum += (row['fat_g'] as num?)?.toDouble() ?? 0;
      nutritionByDate[row['date'] as String] = row;
    }

    double plannedWorkoutSum = 0;
    double plannedSetsMinimumSum = 0;
    double plannedSetsMaximumSum = 0;
    var hasPlannedWorkouts = false;
    var hasPlannedSetsMinimum = false;
    var hasPlannedSetsMaximum = false;
    var nutritionTargetDays = 0;
    var nutritionTargetDaysLogged = 0;
    double nutritionAdherenceSum = 0;
    var sleepTargetDays = 0;
    for (
      var date = start;
      !date.isAfter(end);
      date = date.add(const Duration(days: 1))
    ) {
      final target = _targetForDate(targetHistory, date);
      if (target?.workoutsPerWeek != null) {
        plannedWorkoutSum += target!.workoutsPerWeek! / 7;
        hasPlannedWorkouts = true;
      }
      if (target?.minSetsPerWeek != null) {
        plannedSetsMinimumSum += target!.minSetsPerWeek! / 7;
        hasPlannedSetsMinimum = true;
      }
      if (target?.maxSetsPerWeek != null) {
        plannedSetsMaximumSum += target!.maxSetsPerWeek! / 7;
        hasPlannedSetsMaximum = true;
      }
      final nutrientTargets = <(double?, double?)>[
        (target?.calories, null),
        (target?.proteinG, null),
        (target?.carbsG, null),
        (target?.fatG, null),
      ];
      if (nutrientTargets.any((item) => item.$1 != null)) {
        nutritionTargetDays++;
        final actual = nutritionByDate[_date(date)];
        if (actual != null) nutritionTargetDaysLogged++;
        final actualValues = [
          (actual?['calories'] as num?)?.toDouble(),
          (actual?['protein_g'] as num?)?.toDouble(),
          (actual?['carbs_g'] as num?)?.toDouble(),
          (actual?['fat_g'] as num?)?.toDouble(),
        ];
        final targetValues = [
          target?.calories,
          target?.proteinG,
          target?.carbsG,
          target?.fatG,
        ];
        var score = 0.0;
        var configured = 0;
        for (var i = 0; i < targetValues.length; i++) {
          final expected = targetValues[i];
          if (expected != null) {
            configured++;
            score += _adherenceScore(actualValues[i], expected);
          }
        }
        nutritionAdherenceSum += configured == 0 ? 0 : score / configured;
      }
      if (target?.sleepHours != null) sleepTargetDays++;
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
      SELECT date,
             COALESCE(actual_sleep_minutes, estimated_sleep_minutes, sleep_minutes) AS minutes
      FROM sleep_entries
      WHERE date BETWEEN ? AND ?
      ORDER BY date ASC
      ''',
      [startText, endText],
    );
    final sleepByDate = <String, double>{};
    for (final row in sleepRows) {
      final minutes = (row['minutes'] as num?)?.toDouble();
      if (minutes != null) sleepByDate[row['date'] as String] = minutes / 60;
    }
    final averageSleepHours = sleepByDate.isEmpty
        ? null
        : sleepByDate.values.fold<double>(0, (sum, value) => sum + value) /
              sleepByDate.length;
    double sleepAdherenceSum = 0;
    var sleepTargetDaysLogged = 0;
    for (
      var date = start;
      !date.isAfter(end);
      date = date.add(const Duration(days: 1))
    ) {
      final expected = _targetForDate(targetHistory, date)?.sleepHours;
      if (expected == null) continue;
      final actual = sleepByDate[_date(date)];
      if (actual != null) sleepTargetDaysLogged++;
      sleepAdherenceSum += _adherenceScore(actual, expected);
    }

    final rpeRows = await database.rawQuery(
      '''
      SELECT w.date, s.rpe
      FROM workouts w
      JOIN exercise_entries ee ON ee.workout_id = w.id
      JOIN sets s ON s.exercise_entry_id = ee.id
       WHERE w.date BETWEEN ? AND ? AND w.end_time IS NOT NULL
         AND s.is_complete = 1 AND s.is_warmup = 0
         $routineFilter
      ''',
      [startText, endText, ...routineArgs],
    );
    var rpeExpectedSets = 0;
    var rpeSetsLogged = 0;
    double rpeSum = 0;
    double rpeAdherenceSum = 0;
    for (final row in rpeRows) {
      final date = DateTime.parse(row['date'] as String);
      final target = _targetForDate(targetHistory, date);
      if (target?.minRpe == null && target?.maxRpe == null) continue;
      rpeExpectedSets++;
      final actual = (row['rpe'] as num?)?.toDouble();
      if (actual == null) continue;
      rpeSetsLogged++;
      rpeSum += actual;
      final minimum = target?.minRpe ?? target?.maxRpe ?? actual;
      final maximum = target?.maxRpe ?? target?.minRpe ?? actual;
      final distance = actual < minimum
          ? minimum - actual
          : actual > maximum
          ? actual - maximum
          : 0.0;
      rpeAdherenceSum += math.max(0, 1 - distance / 10);
    }
    final latestTarget = _targetForDate(targetHistory, end);
    final elapsedDays = end.difference(start).inDays + 1;
    final plannedWorkouts = hasPlannedWorkouts
        ? plannedWorkoutSum.round()
        : null;
    final plannedSetsMinimum = hasPlannedSetsMinimum
        ? plannedSetsMinimumSum.round()
        : null;
    final plannedSetsMaximum = hasPlannedSetsMaximum
        ? plannedSetsMaximumSum.round()
        : null;
    final completedSets = (workout['set_count'] as num?)?.toInt() ?? 0;
    double? setAdherence;
    if (plannedSetsMinimum != null || plannedSetsMaximum != null) {
      if (plannedSetsMinimum != null && completedSets < plannedSetsMinimum) {
        setAdherence = plannedSetsMinimum == 0
            ? 100
            : completedSets / plannedSetsMinimum * 100;
      } else if (plannedSetsMaximum != null &&
          completedSets > plannedSetsMaximum) {
        setAdherence = plannedSetsMaximum == 0
            ? 0
            : plannedSetsMaximum / completedSets * 100;
      } else {
        setAdherence = 100;
      }
    }
    final startingWeight = normalizedWeights.isEmpty
        ? null
        : normalizedWeights.first;
    final endingWeight = normalizedWeights.isEmpty
        ? null
        : normalizedWeights.last;
    final weightChange = normalizedWeights.length < 2
        ? null
        : normalizedWeights.last - normalizedWeights.first;
    final elapsedWeeks = elapsedDays / 7;
    final weeklyWeightChange =
        startingWeight == null ||
            startingWeight == 0 ||
            weightChange == null ||
            elapsedWeeks == 0
        ? null
        : weightChange / startingWeight / elapsedWeeks * 100;
    final expectedWeeklyWeightChange = latestTarget?.weeklyWeightChangePercent;
    final weightAdherence =
        weeklyWeightChange == null || expectedWeeklyWeightChange == null
        ? null
        : _adherenceScore(
                weeklyWeightChange,
                expectedWeeklyWeightChange,
                toleranceFloor: 0.1,
              ) *
              100;
    return PeriodizationMetrics(
      startDate: start,
      endDate: end,
      elapsedDays: elapsedDays,
      workoutCount: (workout['workout_count'] as num?)?.toInt() ?? 0,
      completedSets: completedSets,
      volume: (workout['volume'] as num?)?.toDouble() ?? 0,
      plannedWorkouts: plannedWorkouts,
      plannedSetsMinimum: plannedSetsMinimum,
      plannedSetsMaximum: plannedSetsMaximum,
      setAdherencePercent: setAdherence,
      nutritionDaysLogged: nutritionRows.length,
      nutritionTargetDays: nutritionTargetDays,
      averageCalories: nutritionRows.isEmpty
          ? null
          : calorieSum / nutritionRows.length,
      averageProteinG: nutritionRows.isEmpty
          ? null
          : proteinSum / nutritionRows.length,
      averageCarbsG: nutritionRows.isEmpty
          ? null
          : carbsSum / nutritionRows.length,
      averageFatG: nutritionRows.isEmpty ? null : fatSum / nutritionRows.length,
      nutritionAdherencePercent: nutritionTargetDays == 0
          ? null
          : nutritionAdherenceSum / nutritionTargetDays * 100,
      nutritionCoveragePercent: nutritionTargetDays == 0
          ? null
          : nutritionTargetDaysLogged / nutritionTargetDays * 100,
      startingWeightKg: startingWeight,
      endingWeightKg: endingWeight,
      weightChangeKg: weightChange,
      weeklyWeightChangePercent: weeklyWeightChange,
      weightAdherencePercent: weightAdherence,
      averageSleepHours: averageSleepHours,
      sleepDaysLogged: sleepByDate.length,
      sleepTargetDays: sleepTargetDays,
      sleepAdherencePercent: sleepTargetDays == 0
          ? null
          : sleepAdherenceSum / sleepTargetDays * 100,
      sleepCoveragePercent: sleepTargetDays == 0
          ? null
          : sleepTargetDaysLogged / sleepTargetDays * 100,
      averageRpe: rpeSetsLogged == 0 ? null : rpeSum / rpeSetsLogged,
      rpeSetsLogged: rpeSetsLogged,
      rpeAdherencePercent: rpeExpectedSets == 0
          ? null
          : rpeAdherenceSum / rpeExpectedSets * 100,
      rpeCoveragePercent: rpeExpectedSets == 0
          ? null
          : rpeSetsLogged / rpeExpectedSets * 100,
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

  Future<PeriodizationProjection> getPhaseProjection(
    PeriodizationPhase phase, {
    PeriodizationMetrics? phaseMetrics,
  }) async {
    final today = _day(DateTime.now());
    final projectionStart = today.isBefore(phase.startDate)
        ? phase.startDate
        : today;
    final phaseOngoing = !today.isAfter(phase.endDate);
    final remainingDays = projectionStart.isAfter(phase.endDate)
        ? 0
        : phase.endDate.difference(projectionStart).inDays + 1;
    final database = await db;
    final metrics = phaseMetrics ?? await getPhaseMetrics(phase);
    final targets = await getTargetHistory(phase.id);

    double plannedWorkoutSum = 0;
    double plannedSetSum = 0;
    var hasPlannedWorkouts = false;
    var hasPlannedSets = false;
    for (
      var date = phase.startDate;
      !date.isAfter(phase.endDate);
      date = date.add(const Duration(days: 1))
    ) {
      final target = _targetForDate(targets, date);
      if (target?.workoutsPerWeek != null) {
        plannedWorkoutSum += target!.workoutsPerWeek! / 7;
        hasPlannedWorkouts = true;
      }
      if (target?.minSetsPerWeek != null) {
        plannedSetSum += target!.minSetsPerWeek! / 7;
        hasPlannedSets = true;
      }
    }
    final plannedWorkouts = hasPlannedWorkouts
        ? plannedWorkoutSum.round()
        : null;
    final plannedSets = hasPlannedSets ? plannedSetSum.round() : null;

    double? plannedVolume;
    if (metrics.volume > 0 &&
        metrics.completedSets > 0 &&
        plannedSets != null) {
      plannedVolume = metrics.volume / metrics.completedSets * plannedSets;
    } else if (metrics.volume > 0 &&
        metrics.workoutCount > 0 &&
        plannedWorkouts != null) {
      plannedVolume = metrics.volume / metrics.workoutCount * plannedWorkouts;
    } else if (plannedWorkouts != null && plannedWorkouts > 0) {
      final historyStart = today.subtract(const Duration(days: 90));
      final history = await database.rawQuery(
        '''
        SELECT COUNT(DISTINCT w.id) AS workout_count,
               SUM(CASE WHEN s.is_complete = 1 AND s.is_warmup = 0
                        THEN COALESCE(s.weight, 0) * COALESCE(s.reps, 0)
                        ELSE 0 END) AS volume
        FROM workouts w
        LEFT JOIN exercise_entries ee ON ee.workout_id = w.id
        LEFT JOIN sets s ON s.exercise_entry_id = ee.id
        WHERE w.date BETWEEN ? AND ? AND w.end_time IS NOT NULL
        ''',
        [_date(historyStart), _date(today)],
      );
      final workoutCount =
          (history.first['workout_count'] as num?)?.toInt() ?? 0;
      final volume = (history.first['volume'] as num?)?.toDouble() ?? 0;
      if (workoutCount > 0 && volume > 0) {
        plannedVolume = volume / workoutCount * plannedWorkouts;
      }
    }

    final latestWeights = await database.query(
      'body_measurements',
      where: "type = 'weight' AND date <= ?",
      whereArgs: [_date(today)],
      orderBy: 'date DESC, created_at DESC',
      limit: 1,
    );
    final currentWeight = latestWeights.isEmpty
        ? null
        : _weightKg(latestWeights.first);
    final trendStart = today.subtract(const Duration(days: 42));
    final trendRows = await database.query(
      'body_measurements',
      where: "type = 'weight' AND date BETWEEN ? AND ?",
      whereArgs: [_date(trendStart), _date(today)],
      orderBy: 'date ASC, created_at ASC',
    );
    double? observedRate;
    if (trendRows.length >= 2) {
      final firstRow = trendRows.first;
      final lastRow = trendRows.last;
      final firstWeight = _weightKg(firstRow);
      final lastWeight = _weightKg(lastRow);
      final spanDays = DateTime.parse(
        lastRow['date'] as String,
      ).difference(DateTime.parse(firstRow['date'] as String)).inDays;
      if (firstWeight != null &&
          firstWeight > 0 &&
          lastWeight != null &&
          spanDays >= 7) {
        final rate =
            (lastWeight - firstWeight) / firstWeight / (spanDays / 7) * 100;
        if (rate.isFinite && rate.abs() <= 5) observedRate = rate;
      }
    }

    final effectiveTarget = _targetForDate(targets, projectionStart);
    final targetWeight = effectiveTarget?.targetWeightKg;
    final plannedRate = effectiveTarget?.weeklyWeightChangePercent;
    var selectedRate = phase.startDate.isAfter(today)
        ? plannedRate
        : observedRate;
    var weightBasis = selectedRate == null
        ? null
        : phase.startDate.isAfter(today) || observedRate == null
        ? PeriodizationWeightProjectionBasis.plannedRate
        : PeriodizationWeightProjectionBasis.observedTrend;
    if (currentWeight != null && targetWeight != null) {
      final direction = targetWeight.compareTo(currentWeight).sign;
      final selectedDirection = selectedRate?.compareTo(0).sign;
      final plannedDirection = plannedRate?.compareTo(0).sign;
      if (direction != 0 &&
          selectedDirection != direction &&
          plannedDirection == direction) {
        selectedRate = plannedRate;
        weightBasis = PeriodizationWeightProjectionBasis.plannedRate;
      }
    }

    double? expectedEndWeight;
    if (currentWeight != null &&
        selectedRate != null &&
        phaseOngoing &&
        remainingDays >= 0 &&
        1 + selectedRate / 100 > 0) {
      expectedEndWeight =
          currentWeight * math.pow(1 + selectedRate / 100, remainingDays / 7);
    }

    DateTime? estimatedGoalDate;
    if (phaseOngoing && currentWeight != null && targetWeight != null) {
      if ((targetWeight - currentWeight).abs() < 0.05) {
        estimatedGoalDate = today;
      } else if (selectedRate != null && selectedRate != 0) {
        final growth = 1 + selectedRate / 100;
        final movesTowardGoal =
            (targetWeight > currentWeight && selectedRate > 0) ||
            (targetWeight < currentWeight && selectedRate < 0);
        if (growth > 0 && movesTowardGoal) {
          final weeks =
              math.log(targetWeight / currentWeight) / math.log(growth);
          if (weeks.isFinite && weeks >= 0 && weeks <= 260) {
            estimatedGoalDate = today.add(Duration(days: (weeks * 7).ceil()));
          }
        }
      }
    }

    return PeriodizationProjection(
      currentWeightKg: currentWeight,
      expectedEndWeightKg: expectedEndWeight,
      estimatedGoalDate: estimatedGoalDate,
      plannedVolume: plannedVolume,
      plannedWorkouts: plannedWorkouts,
      plannedSets: plannedSets,
      weeklyWeightRatePercent: selectedRate,
      weightBasis: weightBasis,
      remainingDays: remainingDays,
    );
  }

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
    for (final value in [target.minSetsPerWeek, target.maxSetsPerWeek]) {
      if (value != null && value < 0) {
        throw const PeriodizationValidationException('invalid_target');
      }
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
    for (final value in [target.minRpe, target.maxRpe]) {
      if (value != null && (value < 1 || value > 10)) {
        throw const PeriodizationValidationException('invalid_target');
      }
    }
    if (target.sleepHours != null &&
        (target.sleepHours! < 1 || target.sleepHours! > 16)) {
      throw const PeriodizationValidationException('invalid_target');
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
      proteinGPerKg: target.proteinGPerKg,
      fatGPerKg: target.fatGPerKg,
      weightKgUsed: target.weightKgUsed,
      workoutsPerWeek: target.workoutsPerWeek,
      minSetsPerWeek: target.minSetsPerWeek,
      maxSetsPerWeek: target.maxSetsPerWeek,
      minRpe: target.minRpe,
      maxRpe: target.maxRpe,
      routineIds: target.routineIds,
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

  static DateTime _weeklyBoundary(
    PeriodizationPhase phase,
    DateTime? replaceFrom,
  ) {
    final today = _day(DateTime.now());
    final fallback = today.isAfter(phase.startDate) ? today : phase.startDate;
    return _day(replaceFrom ?? fallback);
  }

  static void _validateWeeklyWindow(
    DateTime boundary,
    DateTime phaseStart,
    DateTime phaseEnd,
    List<PeriodizationTarget> weeks,
  ) {
    if (boundary.isBefore(phaseStart) || boundary.isAfter(phaseEnd)) {
      throw const PeriodizationValidationException('target_outside_phase');
    }
    for (var i = 0; i < weeks.length; i++) {
      final week = weeks[i];
      if (!week.isEmpty) _validateTarget(week);
      if (boundary.add(Duration(days: 7 * i)).isAfter(phaseEnd)) {
        throw const PeriodizationValidationException('target_outside_phase');
      }
    }
  }

  /// Replaces every target version with `valid_from >= [boundary]` by the
  /// collapsed representation of [weeks] (one effective target per week,
  /// starting exactly at [boundary]). Versions before [boundary] — the
  /// locked history — are left untouched.
  static Future<void> _replaceTargetsFrom(
    DatabaseExecutor txn, {
    required String phaseId,
    required DateTime phaseEnd,
    required DateTime boundary,
    required List<PeriodizationTarget> weeks,
  }) async {
    final rows = await txn.query(
      'phase_targets',
      where: 'phase_id = ?',
      whereArgs: [phaseId],
    );
    final history = rows.map(PeriodizationTarget.fromMap).toList();
    final retained = history
        .where((target) => target.validFrom.isBefore(boundary))
        .toList();
    final baseline = _targetForDate(
      retained,
      boundary.subtract(const Duration(days: 1)),
    );
    final nextVersion = history.isEmpty
        ? 1
        : history.map((target) => target.version).reduce(math.max) + 1;
    await txn.delete(
      'phase_targets',
      where: 'phase_id = ? AND valid_from >= ?',
      whereArgs: [phaseId, _date(boundary)],
    );
    await _insertWeeklyTargets(
      txn,
      phaseId: phaseId,
      weeks: weeks,
      firstValidFrom: boundary,
      firstVersion: nextVersion,
      baseline: baseline,
    );
  }

  static Future<void> _insertWeeklyTargets(
    DatabaseExecutor txn, {
    required String phaseId,
    required List<PeriodizationTarget> weeks,
    required DateTime firstValidFrom,
    required int firstVersion,
    PeriodizationTarget? baseline,
  }) async {
    await _validateRoutineReferences(txn, weeks);
    // A null baseline (no retained history) behaves like an empty target so
    // leading empty weeks never create versions.
    var previous =
        baseline ??
        PeriodizationTarget(
          id: '',
          phaseId: phaseId,
          version: 0,
          validFrom: firstValidFrom,
          createdAt: DateTime.now(),
        );
    var version = firstVersion;
    for (var i = 0; i < weeks.length; i++) {
      final week = weeks[i];
      if (!_sameTargets(week, previous)) {
        await txn.insert(
          'phase_targets',
          _targetMap(
            week,
            phaseId: phaseId,
            version: version,
            validFrom: firstValidFrom.add(Duration(days: 7 * i)),
          ),
        );
        version++;
      }
      previous = week;
    }
  }

  static bool _sameTargets(PeriodizationTarget a, PeriodizationTarget b) =>
      a.nutritionJson.toString() == b.nutritionJson.toString() &&
      a.trainingJson.toString() == b.trainingJson.toString() &&
      a.bodyJson.toString() == b.bodyJson.toString() &&
      a.sleepJson.toString() == b.sleepJson.toString();

  /// Rejects targets that reference a routine that no longer exists in the
  /// library (the weekly targets store only the routine id, with no FK).
  static Future<void> _validateRoutineReferences(
    DatabaseExecutor txn,
    Iterable<PeriodizationTarget> targets,
  ) async {
    final routineIds = targets
        .expand((target) => target.routineIds)
        .where((id) => id.isNotEmpty)
        .toSet();
    if (routineIds.isEmpty) return;
    final rows = await txn.query(
      'routines',
      columns: ['id'],
      where: 'id IN (${List.filled(routineIds.length, '?').join(', ')})',
      whereArgs: routineIds.toList(),
    );
    final found = rows.map((row) => row['id']).toSet();
    if (routineIds.difference(found).isNotEmpty) {
      throw const PeriodizationValidationException('routine_not_found');
    }
  }

  static double _adherenceScore(
    double? actual,
    double expected, {
    double toleranceFloor = 1,
  }) {
    if (actual == null || !actual.isFinite || !expected.isFinite) return 0;
    final denominator = math.max(expected.abs(), toleranceFloor);
    return math.max(0, 1 - (actual - expected).abs() / denominator);
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
