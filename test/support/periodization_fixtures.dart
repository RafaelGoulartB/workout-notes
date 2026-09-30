import 'package:uuid/uuid.dart';
import 'package:workout_notes/models/periodization_phase.dart';
import 'package:workout_notes/models/periodization_target.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';

/// Test fixture: appends a phase to an existing plan without the plan-level
/// validation of the production APIs (`createPlanWithPhases` /
/// `createChainedPlan`), which build phases as a whole.
///
/// [target] becomes version 1 of the phase's targets; [weeklyTargets] saves
/// one target per phase week through [PeriodizationRepository.savePhaseSetup].
Future<PeriodizationPhase> addPhaseFixture(
  PeriodizationRepository repository, {
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
  final database = await repository.db;
  final start = DateTime(startDate.year, startDate.month, startDate.day);
  final end = DateTime(endDate.year, endDate.month, endDate.day);
  final now = DateTime.now();
  final phase = PeriodizationPhase(
    id: const Uuid().v4(),
    planId: planId,
    name: name.trim(),
    templateKey: templateKey,
    color: color,
    startDate: start,
    endDate: end,
    intent: intent,
    orderIndex: (await repository.getPhases(planId)).length,
    createdAt: now,
    updatedAt: now,
  );
  await database.insert('periodization_phases', phase.toMap());
  if (weeklyTargets != null) {
    await repository.savePhaseSetup(
      phase.id,
      name: phase.name,
      templateKey: templateKey ?? '',
      color: color,
      intent: intent,
      weeks: weeklyTargets,
      fromWeek: 0,
    );
    if (templateKey == null) {
      await database.update(
        'periodization_phases',
        {'template_key': null},
        where: 'id = ?',
        whereArgs: [phase.id],
      );
    }
  } else if (target != null && !target.isEmpty) {
    await database.insert(
      'phase_targets',
      target
          .copyWith(
            id: const Uuid().v4(),
            phaseId: phase.id,
            version: 1,
            validFrom: start,
            createdAt: now,
          )
          .toMap(),
    );
  }
  return (await repository.getPhase(phase.id))!;
}
