import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/models/periodization_checkin.dart';
import 'package:workout_notes/models/periodization_metrics.dart';
import 'package:workout_notes/models/periodization_phase.dart';
import 'package:workout_notes/models/periodization_phase_draft.dart';
import 'package:workout_notes/models/periodization_plan.dart';
import 'package:workout_notes/models/periodization_routine_suggestion.dart';
import 'package:workout_notes/models/periodization_run_schedule_result.dart';
import 'package:workout_notes/models/periodization_run_suggestion.dart';
import 'package:workout_notes/models/periodization_schedule.dart';
import 'package:workout_notes/models/periodization_target.dart';
import 'package:workout_notes/models/run_plan.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/periodization/phase_kind.dart';
import 'package:workout_notes/periodization/phase_week_plan.dart';
import 'package:workout_notes/periodization/run_plan_week_resolver.dart';
import 'package:workout_notes/repositories/base_repository.dart';
import 'package:workout_notes/repositories/run_plan_repository.dart';
import 'package:workout_notes/utils/date_utils.dart';
import 'package:workout_notes/utils/sql_helpers.dart';

part 'periodization_repository_day_plan.dart';
part 'periodization_repository_metrics.dart';
part 'periodization_repository_suggestions.dart';

/// Plans, phases and weekly targets. Read-only day plans, suggestions and
/// metrics live in `part` files as extensions
/// (`periodization_repository_*.dart`) so the public API is unchanged.
class PeriodizationRepository extends BaseRepository {
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
      if (dayOf(endDate).isBefore(dayOf(DateTime.now()))) {
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
      startDate: dayOf(startDate),
      endDate: dayOf(endDate),
      status: activate
          ? PeriodizationPlanStatus.active
          : PeriodizationPlanStatus.draft,
      notes: optionalText(notes),
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
          dayOf(phase.startDate),
          dayOf(phase.startDate),
          dayOf(phase.endDate),
          phase.weeklyTargets!,
        );
      }
      if (i > 0 && !phase.startDate.isAfter(sorted[i - 1].endDate)) {
        throw const PeriodizationValidationException('phase_overlap');
      }
    }
    if (dayOf(sorted.first.startDate).isBefore(dayOf(startDate))) {
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
      startDate: dayOf(startDate),
      endDate: dayOf(planEnd),
      status: activate
          ? PeriodizationPlanStatus.active
          : PeriodizationPlanStatus.draft,
      notes: optionalText(notes),
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
          startDate: dayOf(draft.startDate),
          endDate: dayOf(draft.endDate),
          intent: optionalText(draft.intent),
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

  /// Creates a plan whose phases run back to back from [startDate], each
  /// lasting its entry's weeks. New phases store their `seedTarget` as the
  /// first target version.
  Future<PeriodizationPlan> createChainedPlan({
    required String name,
    required DateTime startDate,
    required List<PhaseScheduleEntry> phases,
    String? notes,
    bool activate = true,
  }) {
    final ranges = chainPhaseRanges(startDate, phases.map((p) => p.weeks));
    return createPlanWithPhases(
      name: name,
      startDate: startDate,
      notes: notes,
      activate: activate,
      phases: [
        for (var i = 0; i < phases.length; i++)
          PeriodizationPhaseDraft(
            name: phases[i].name,
            templateKey: phases[i].templateKey,
            color: phases[i].color,
            intent: phases[i].intent,
            startDate: ranges[i].start,
            endDate: ranges[i].end,
            target: phases[i].seedTarget,
          ),
      ],
    );
  }

  /// Rewrites a plan's schedule: name, start and the ordered phase list.
  ///
  /// Phases are chained (each starts the day after the previous one ends).
  /// An existing phase that moves carries its target versions along, keeping
  /// each version on the same phase week; versions that end up past the
  /// phase's new end are dropped. Phases missing from [phases] are deleted
  /// (their targets and check-ins cascade); entries without an id are
  /// created with their `seedTarget`.
  Future<void> replanPlan({
    required String planId,
    required String name,
    required DateTime startDate,
    required List<PhaseScheduleEntry> phases,
    String? notes,
  }) async {
    if (name.trim().isEmpty) {
      throw const PeriodizationValidationException('name_required');
    }
    if (phases.isEmpty) {
      throw const PeriodizationValidationException('plan_requires_phase');
    }
    for (final entry in phases) {
      _validateNameAndDates(entry.name, startDate, startDate);
      if (entry.weeks < 1 || entry.weeks > 104) {
        throw const PeriodizationValidationException('invalid_date_range');
      }
      final seed = entry.id == null ? entry.seedTarget : null;
      if (seed != null && !seed.isEmpty) _validateTarget(seed);
    }
    final plan = await getPlan(planId);
    if (plan == null) {
      throw const PeriodizationValidationException('plan_not_found');
    }
    final existing = {
      for (final phase in await getPhases(planId)) phase.id: phase,
    };
    final ranges = chainPhaseRanges(startDate, phases.map((p) => p.weeks));
    final keptIds = phases.map((p) => p.id).whereType<String>().toSet();
    final now = DateTime.now().toIso8601String();
    final database = await db;
    await database.transaction((txn) async {
      await txn.update(
        'periodization_plans',
        {
          'name': name.trim(),
          'notes': optionalText(notes),
          'start_date': dateKey(ranges.first.start),
          'end_date': dateKey(ranges.last.end),
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [planId],
      );
      for (final id in existing.keys.where((id) => !keptIds.contains(id))) {
        await txn.delete(
          'periodization_phases',
          where: 'id = ?',
          whereArgs: [id],
        );
      }
      for (var index = 0; index < phases.length; index++) {
        final entry = phases[index];
        final range = ranges[index];
        final original = entry.id == null ? null : existing[entry.id];
        if (original == null) {
          final phaseId = _uuid.v4();
          await txn.insert(
            'periodization_phases',
            PeriodizationPhase(
              id: phaseId,
              planId: planId,
              name: entry.name.trim(),
              templateKey: entry.templateKey,
              color: entry.color,
              startDate: range.start,
              endDate: range.end,
              intent: optionalText(entry.intent),
              orderIndex: index,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ).toMap(),
          );
          if (entry.seedTarget case final target? when !target.isEmpty) {
            await _validateRoutineReferences(txn, [target]);
            await txn.insert(
              'phase_targets',
              _targetMap(
                target,
                phaseId: phaseId,
                version: 1,
                validFrom: range.start,
              ),
            );
          }
          continue;
        }
        await txn.update(
          'periodization_phases',
          {
            'name': entry.name.trim(),
            'template_key': entry.templateKey,
            'color': entry.color,
            'intent': optionalText(entry.intent),
            'start_date': dateKey(range.start),
            'end_date': dateKey(range.end),
            'order_index': index,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [original.id],
        );
        final shift = daysBetween(original.startDate, range.start);
        if (shift != 0) {
          await txn.rawUpdate(
            'UPDATE phase_targets SET valid_from = date(valid_from, ?) '
            'WHERE phase_id = ?',
            ['${shift >= 0 ? '+' : ''}$shift days', original.id],
          );
        }
        // A version starting after the new end can never apply; keep the
        // first version even then so a shrunk phase never loses its targets.
        await txn.rawDelete(
          '''
          DELETE FROM phase_targets
          WHERE phase_id = ? AND valid_from > ?
            AND version != (
              SELECT MIN(version) FROM phase_targets WHERE phase_id = ?
            )
          ''',
          [original.id, dateKey(range.end), original.id],
        );
      }
    });
  }

  /// Appends [entry] after the plan's last phase and returns the new phase.
  Future<PeriodizationPhase> appendPhase(
    String planId,
    PhaseScheduleEntry entry,
  ) async {
    final plan = await getPlan(planId);
    if (plan == null) {
      throw const PeriodizationValidationException('plan_not_found');
    }
    final phases = await getPhases(planId);
    await replanPlan(
      planId: planId,
      name: plan.name,
      notes: plan.notes,
      startDate: phases.isEmpty ? plan.startDate : phases.first.startDate,
      phases: [
        for (final item in phases)
          PhaseScheduleEntry(
            id: item.id,
            name: item.name,
            templateKey: item.templateKey ?? PhaseKind.custom.key,
            color: item.color,
            intent: item.intent,
            weeks: item.totalWeeks,
          ),
        entry,
      ],
    );
    return (await getPhases(planId)).last;
  }

  /// Start/end dates of phases laid back to back from [start].
  static List<({DateTime start, DateTime end})> chainPhaseRanges(
    DateTime start,
    Iterable<int> weeks,
  ) {
    var cursor = dayOf(start);
    final ranges = <({DateTime start, DateTime end})>[];
    for (final count in weeks) {
      final end = addDays(cursor, 7 * count - 1);
      ranges.add((start: cursor, end: end));
      cursor = addDays(end, 1);
    }
    return ranges;
  }

  /// Saves a phase's identity and its weekly targets from phase week
  /// [fromWeek] on (`weeks[0]` is week [fromWeek]). Earlier weeks keep their
  /// stored targets — they are history.
  Future<void> savePhaseSetup(
    String phaseId, {
    required String name,
    required String templateKey,
    required int color,
    String? intent,
    required List<PeriodizationTarget> weeks,
    required int fromWeek,
  }) async {
    final phase = await getPhase(phaseId);
    if (phase == null) {
      throw const PeriodizationValidationException('phase_not_found');
    }
    _validateNameAndDates(name, phase.startDate, phase.endDate);
    final boundary = addDays(phase.startDate, 7 * fromWeek);
    if (weeks.isNotEmpty) {
      _validateWeeklyWindow(boundary, phase.startDate, phase.endDate, weeks);
    }
    final database = await db;
    await database.transaction((txn) async {
      await txn.update(
        'periodization_phases',
        {
          'name': name.trim(),
          'template_key': templateKey,
          'color': color,
          'intent': optionalText(intent),
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [phaseId],
      );
      if (weeks.isNotEmpty) {
        await _replaceTargetsFrom(
          txn,
          phaseId: phaseId,
          phaseEnd: phase.endDate,
          boundary: boundary,
          weeks: weeks,
        );
      }
    });
  }

  /// Sets the calorie/macro targets of [phase] from phase week [fromWeek]
  /// (0-based) through its last week, on [executor] so a caller can fold it
  /// into its own transaction. Earlier weeks keep their stored targets (lived
  /// weeks are history and never rewritten); every other field of each week's
  /// target (training days, run plan, sleep…) is preserved. Returns the number
  /// of weeks written.
  Future<int> applyNutritionFromWeekIn(
    DatabaseExecutor executor,
    PeriodizationPhase phase, {
    required int fromWeek,
    double? calories,
    double? proteinG,
    double? carbsG,
    double? fatG,
  }) async {
    if (fromWeek < 0 || fromWeek >= phase.totalWeeks) {
      throw const PeriodizationValidationException('target_outside_phase');
    }
    final rows = await executor.query(
      'phase_targets',
      where: 'phase_id = ?',
      whereArgs: [phase.id],
    );
    final history = rows.map(PeriodizationTarget.fromMap).toList();
    final boundary = addDays(phase.startDate, 7 * fromWeek);
    final weeks = <PeriodizationTarget>[
      for (var week = fromWeek; week < phase.totalWeeks; week++)
        (_targetForDate(history, addDays(phase.startDate, 7 * week)) ??
                PeriodizationTarget(
                  id: '',
                  phaseId: phase.id,
                  version: 0,
                  validFrom: boundary,
                  createdAt: DateTime.now(),
                ))
            .copyWith(
              calories: calories,
              proteinG: proteinG,
              carbsG: carbsG,
              fatG: fatG,
            ),
    ];
    _validateWeeklyWindow(boundary, phase.startDate, phase.endDate, weeks);
    await _replaceTargetsFrom(
      executor,
      phaseId: phase.id,
      phaseEnd: phase.endDate,
      boundary: boundary,
      weeks: weeks,
    );
    return weeks.length;
  }

  /// Ends [phaseId] at the end of its current week and pulls the following
  /// phases earlier so the plan stays back to back.
  Future<void> endPhaseThisWeek(String phaseId, {DateTime? today}) async {
    final phase = await getPhase(phaseId);
    if (phase == null) {
      throw const PeriodizationValidationException('phase_not_found');
    }
    final plan = await getPlan(phase.planId);
    if (plan == null) {
      throw const PeriodizationValidationException('plan_not_found');
    }
    final weeks = phase.weekAt(dayOf(today ?? DateTime.now())).clamp(1, 104);
    final phases = await getPhases(plan.id);
    await replanPlan(
      planId: plan.id,
      name: plan.name,
      notes: plan.notes,
      startDate: phases.first.startDate,
      phases: [
        for (final item in phases)
          PhaseScheduleEntry(
            id: item.id,
            name: item.name,
            templateKey: item.templateKey ?? PhaseKind.custom.key,
            color: item.color,
            intent: item.intent,
            weeks: item.id == phaseId ? weeks : item.totalWeeks,
          ),
      ],
    );
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
        'start_date': dateKey(plan.startDate),
        'end_date': dateKey(plan.endDate),
        'notes': optionalText(plan.notes),
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

  Future<PeriodizationPhase?> getPhase(String id) async =>
      getPhaseIn(await db, id);

  /// [getPhase] on an explicit executor.
  Future<PeriodizationPhase?> getPhaseIn(
    DatabaseExecutor database,
    String id,
  ) async {
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
    final day = dateKey(date);
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
}

Future<void> _deactivateCurrent(
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

void _validateNameAndDates(String name, DateTime start, DateTime end) {
  if (name.trim().isEmpty) {
    throw const PeriodizationValidationException('name_required');
  }
  if (dayOf(end).isBefore(dayOf(start))) {
    throw const PeriodizationValidationException('invalid_date_range');
  }
}

void _validateTarget(PeriodizationTarget target) {
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
  if (target.runSessionsPerWeek != null &&
      (target.runSessionsPerWeek! < 0 || target.runSessionsPerWeek! > 14)) {
    throw const PeriodizationValidationException('invalid_target');
  }
  if (target.qualitySessionsPerWeek != null &&
      (target.qualitySessionsPerWeek! < 0 ||
          target.qualitySessionsPerWeek! > 7)) {
    throw const PeriodizationValidationException('invalid_target');
  }
  for (final value in [
    target.runWeeklyDistanceMeters,
    target.longRunDistanceMeters,
  ]) {
    if (value != null && (!value.isFinite || value < 0)) {
      throw const PeriodizationValidationException('invalid_target');
    }
  }
  if (target.runSessionsPerWeek != null &&
      target.qualitySessionsPerWeek != null &&
      target.qualitySessionsPerWeek! > target.runSessionsPerWeek!) {
    throw const PeriodizationValidationException('invalid_target_range');
  }
}

Map<String, dynamic> _targetMap(
  PeriodizationTarget target, {
  required String phaseId,
  required int version,
  required DateTime validFrom,
}) {
  final remapped = target.copyWith(
    id: _uuid.v4(),
    phaseId: phaseId,
    version: version,
    validFrom: validFrom,
    createdAt: DateTime.now(),
  );
  return remapped.toMap();
}

PeriodizationTarget? _targetForDate(
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

void _validateWeeklyWindow(
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
    if (addDays(boundary, 7 * i).isAfter(phaseEnd)) {
      throw const PeriodizationValidationException('target_outside_phase');
    }
  }
}

/// Replaces every target version with `valid_from >= [boundary]` by the
/// collapsed representation of [weeks] (one effective target per week,
/// starting exactly at [boundary]). Versions before [boundary] — the
/// locked history — are left untouched.
Future<void> _replaceTargetsFrom(
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
  final baseline = _targetForDate(retained, addDays(boundary, -1));
  final nextVersion = history.isEmpty
      ? 1
      : history.map((target) => target.version).reduce(math.max) + 1;
  await txn.delete(
    'phase_targets',
    where: 'phase_id = ? AND valid_from >= ?',
    whereArgs: [phaseId, dateKey(boundary)],
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

Future<void> _insertWeeklyTargets(
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
          validFrom: addDays(firstValidFrom, 7 * i),
        ),
      );
      version++;
    }
    previous = week;
  }
}

bool _sameTargets(PeriodizationTarget a, PeriodizationTarget b) =>
    a.nutritionJson.toString() == b.nutritionJson.toString() &&
    a.trainingJson.toString() == b.trainingJson.toString() &&
    a.bodyJson.toString() == b.bodyJson.toString() &&
    a.sleepJson.toString() == b.sleepJson.toString();

/// Rejects targets that reference a routine that no longer exists in the
/// library (the weekly targets store only the routine id, with no FK).
Future<void> _validateRoutineReferences(
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

/// Exclusive upper bound for "started on or before [date]" on a
/// `started_at` text column: the day after, as `yyyy-MM-dd`.
String _dayAfter(DateTime date) => dateKey(addDays(date, 1));

const _uuid = Uuid();

class PeriodizationValidationException implements Exception {
  final String code;
  const PeriodizationValidationException(this.code);

  @override
  String toString() => 'PeriodizationValidationException($code)';
}
