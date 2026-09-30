import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:workout_notes/models/periodization_plan.dart';
import 'package:workout_notes/models/periodization_schedule.dart';
import 'package:workout_notes/models/periodization_target.dart';
import 'package:workout_notes/periodization/phase_editor_controller.dart';
import 'package:workout_notes/periodization/phase_kind.dart';
import 'package:workout_notes/periodization/phase_seed.dart';
import 'package:workout_notes/periodization/phase_week_plan.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';
import 'package:workout_notes/services/effective_nutrition_goal_service.dart';
import 'support/test_db.dart';

/// The planning redesign: chained phases, template week (training vs rest
/// days), per-week adjustments and the editor controller.
void main() {
  late Database database;
  late PeriodizationRepository repository;

  // A Monday, so phase weeks line up with calendar weeks.
  final start = DateTime(2026, 1, 5);

  setUpAll(initSqfliteFfiForTests);

  setUp(() async {
    database = await installTestDb();
    repository = PeriodizationRepository();
  });

  tearDown(uninstallTestDb);

  PeriodizationTarget target({
    double calories = 2400,
    double? rest,
    List<int> strengthDays = const [],
    List<int> runDays = const [],
    String? label,
  }) => PeriodizationTarget(
    id: '',
    phaseId: '',
    version: 0,
    validFrom: start,
    calories: calories,
    proteinG: 160,
    fatG: 70,
    carbsG: remainingCarbsG(calories: calories, proteinG: 160, fatG: 70),
    restCalories: rest,
    restProteinG: rest == null ? null : 160,
    restFatG: rest == null ? null : 70,
    restCarbsG: remainingCarbsG(calories: rest, proteinG: 160, fatG: 70),
    strengthDays: strengthDays,
    runDays: runDays,
    weekLabel: label,
    createdAt: start,
  );

  PhaseScheduleEntry entry(
    String name,
    int weeks, {
    String? id,
    PeriodizationTarget? seed,
  }) => PhaseScheduleEntry(
    id: id,
    name: name,
    templateKey: PhaseKind.cut.key,
    color: PhaseKind.cut.color,
    weeks: weeks,
    seedTarget: seed,
  );

  group('PeriodizationTarget template week fields', () {
    test('round-trip through the JSON columns', () {
      final original = target(
        rest: 2000,
        strengthDays: [5, 1, 3, 3, 9],
        runDays: [2],
        label: 'Deload',
      ).copyWith(id: 't', phaseId: 'p', version: 1);
      final restored = PeriodizationTarget.fromMap(original.toMap());
      expect(restored.strengthDays, [1, 3, 5]);
      expect(restored.runDays, [2]);
      expect(restored.restCalories, 2000);
      expect(restored.restCarbsG, original.restCarbsG);
      expect(restored.weekLabel, 'Deload');
      expect(restored.hasTemplateWeek, isTrue);
    });

    test('rest days fall back to training values without rest nutrition', () {
      final plain = target();
      expect(plain.nutritionFor(trainingDay: false).calories, 2400);
      final cycled = target(rest: 1900);
      expect(cycled.nutritionFor(trainingDay: false).calories, 1900);
      expect(cycled.nutritionFor(trainingDay: true).calories, 2400);
    });
  });

  group('PhaseWeekPlan', () {
    test(
      'strength and run days are training days; the rest use rest values',
      () {
        final week = PhaseWeekPlan.build(
          target: target(rest: 2000, strengthDays: [1, 3, 5], runDays: [6]),
        );
        expect(week.where((day) => day.trainingDay).map((d) => d.weekday), [
          1,
          3,
          5,
          6,
        ]);
        expect(week[1].calories, 2000); // Tuesday rests
        expect(week[0].calories, 2400);
        expect(week[2].strengthIndex, 1);
        expect(PhaseWeekPlan.averageCalories(week), closeTo(2228.6, 0.1));
      },
    );
  });

  group('chained plans', () {
    test('createChainedPlan lays phases back to back', () async {
      final plan = await repository.createChainedPlan(
        name: 'Year',
        startDate: start,
        phases: [entry('Cut', 4), entry('Maintain', 2)],
      );
      final phases = await repository.getPhases(plan.id);
      expect(phases.map((p) => p.startDate), [start, DateTime(2026, 2, 2)]);
      expect(phases.last.endDate, DateTime(2026, 2, 15));
      expect(plan.endDate, DateTime(2026, 2, 15));
    });

    test('replanPlan moves targets with their phase, drops removed phases '
        'and seeds new ones', () async {
      final plan = await repository.createChainedPlan(
        name: 'Year',
        startDate: start,
        phases: [
          entry('Cut', 4, seed: target(calories: 2000)),
          entry('Bulk', 4, seed: target(calories: 3000)),
          entry('Extra', 2),
        ],
      );
      final [cut, bulk, extra] = await repository.getPhases(plan.id);
      // Week 3 of the bulk gets its own calories.
      await repository.savePhaseSetup(
        bulk.id,
        name: 'Bulk',
        templateKey: 'bulking',
        color: bulk.color,
        fromWeek: 0,
        weeks: [
          target(calories: 3000),
          target(calories: 3000),
          target(calories: 3200),
          target(calories: 3200),
        ],
      );

      await repository.replanPlan(
        planId: plan.id,
        name: 'Year 2',
        startDate: start,
        phases: [
          entry('Bulk', 4, id: bulk.id),
          entry('Cut', 2, id: cut.id),
          entry('New', 1, seed: target(calories: 2500)),
        ],
      );

      final phases = await repository.getPhases(plan.id);
      expect(phases.map((p) => p.name), ['Bulk', 'Cut', 'New']);
      expect(phases.any((p) => p.id == extra.id), isFalse);
      final movedBulk = phases.first;
      expect(movedBulk.startDate, start);
      final weekly = await repository.getWeeklyTargets(movedBulk);
      expect(weekly.map((t) => t?.calories), [3000, 3000, 3200, 3200]);
      final newPhase = phases.last;
      expect(
        (await repository.getEffectiveTarget(
          newPhase.id,
          date: newPhase.startDate,
        ))?.calories,
        2500,
      );
      expect((await repository.getPlan(plan.id))!.name, 'Year 2');
      expect((await repository.getPlan(plan.id))!.endDate, newPhase.endDate);
    });

    test('savePhaseSetup keeps weeks before fromWeek as history', () async {
      final plan = await repository.createChainedPlan(
        name: 'Year',
        startDate: start,
        phases: [entry('Cut', 4, seed: target(calories: 2000))],
      );
      final phase = (await repository.getPhases(plan.id)).single;
      await repository.savePhaseSetup(
        phase.id,
        name: 'Cut v2',
        templateKey: 'cutting',
        color: phase.color,
        intent: 'Lose fat',
        fromWeek: 2,
        weeks: [
          target(calories: 1800, label: 'Push'),
          target(calories: 1800),
        ],
      );
      final weekly = await repository.getWeeklyTargets(phase);
      expect(weekly.map((t) => t?.calories), [2000, 2000, 1800, 1800]);
      expect(weekly[2]?.weekLabel, 'Push');
      expect(weekly[3]?.weekLabel, isNull);
      final saved = await repository.getPhase(phase.id);
      expect(saved!.name, 'Cut v2');
      expect(saved.intent, 'Lose fat');
    });

    test('endPhaseThisWeek pulls the next phase earlier', () async {
      final plan = await repository.createChainedPlan(
        name: 'Year',
        startDate: start,
        phases: [entry('Cut', 6), entry('Maintain', 2)],
      );
      final cut = (await repository.getPhases(plan.id)).first;
      await repository.endPhaseThisWeek(
        cut.id,
        today: DateTime(2026, 1, 14), // week 2
      );
      final phases = await repository.getPhases(plan.id);
      expect(phases.first.endDate, DateTime(2026, 1, 18));
      expect(phases.last.startDate, DateTime(2026, 1, 19));
    });
  });

  group('day plan and nutrition goal', () {
    Future<void> seedPlan() async {
      await repository.createChainedPlan(
        name: 'Year',
        startDate: start,
        phases: [
          entry(
            'Cut',
            4,
            seed: target(rest: 1900, strengthDays: [1, 3, 5], runDays: [6]),
          ),
        ],
      );
    }

    test('getDayPlan tells training from rest days', () async {
      await seedPlan();
      final monday = await repository.getDayPlan(start);
      final tuesday = await repository.getDayPlan(DateTime(2026, 1, 6));
      final saturday = await repository.getDayPlan(DateTime(2026, 1, 10));
      expect(monday!.trainingDay, isTrue);
      expect(tuesday!.trainingDay, isFalse);
      expect(saturday!.trainingDay, isTrue);
      expect(saturday.day.run, isTrue);
      expect(monday.weekNumber, 1);
    });

    test('the effective nutrition goal follows the day type', () async {
      await seedPlan();
      final monday = await EffectiveNutritionGoalService.resolve(date: start);
      final tuesday = await EffectiveNutritionGoalService.resolve(
        date: DateTime(2026, 1, 6),
      );
      expect(monday.goal!.calories, 2400);
      expect(monday.trainingDay, isTrue);
      expect(tuesday.goal!.calories, 1900);
      expect(tuesday.goal!.proteinG, 160);
      expect(tuesday.trainingDay, isFalse);
    });

    test('adherence compares rest days against the rest target', () async {
      await seedPlan();
      final phase = (await repository.getEffectivePhase(start))!;
      // Tuesday (rest) eaten exactly at the rest target.
      await database.insert('meal_logs', {
        'id': 'm1',
        'date': '2026-01-06',
        'meal_type': 'lunch',
        'created_at': '2026-01-01T08:00:00',
      });
      await database.insert('meal_log_items', {
        'id': 'i1',
        'meal_log_id': 'm1',
        'food_name_snapshot': 'Food',
        'quantity': 1,
        'unit': 'serving',
        'nutrition_snapshot_json': '{}',
        'created_at': '2026-01-01T08:00:00',
        'calories': 1900,
        'protein_g': 160,
        'carbs_g': remainingCarbsG(calories: 1900, proteinG: 160, fatG: 70),
        'fat_g': 70,
      });
      final metrics = await repository.getPhaseMetrics(
        phase,
        rangeStart: DateTime(2026, 1, 6),
        rangeEnd: DateTime(2026, 1, 6),
      );
      expect(metrics.nutritionAdherencePercent, closeTo(100, 0.01));
    });
  });

  group('seedTargetForKind', () {
    test('derives calories from TDEE and carries the training setup', () {
      final seed = seedTargetForKind(
        PhaseKind.cut,
        tdee: 2500,
        weightKg: 80,
        training: target(strengthDays: [1, 4]),
      )!;
      expect(seed.calories, 2000);
      expect(seed.proteinG, 176);
      expect(seed.strengthDays, [1, 4]);
      expect(seed.workoutsPerWeek, 2);
      expect(seed.weeklyWeightChangePercent, -0.5);
    });
  });

  group('PhaseEditorController', () {
    test('rebuilds week adjustments and saves base + adjustments', () async {
      final plan = await repository.createChainedPlan(
        name: 'Year',
        startDate: start,
        phases: [entry('Cut', 4, seed: target(rest: 2000))],
      );
      var phase = (await repository.getPhases(plan.id)).single;
      await repository.savePhaseSetup(
        phase.id,
        name: 'Cut',
        templateKey: 'cutting',
        color: phase.color,
        fromWeek: 0,
        weeks: [
          target(rest: 2000),
          target(rest: 2000),
          target(calories: 2600, rest: 2000, label: 'Refeed'),
          target(rest: 2000),
        ],
      );

      final controller = PhaseEditorController(
        plan: (await repository.getPlan(plan.id))!,
        phase: phase,
        today: DateTime(2025, 12, 1), // before the phase: all weeks editable
      );
      await controller.load();
      expect(controller.editableFrom, 0);
      expect(controller.restEnabled, isTrue);
      expect(controller.adjustments.keys, [2]);
      expect(controller.adjustments[2]!.calories, 2600);
      expect(controller.adjustments[2]!.label, 'Refeed');

      controller.setStrengthDays({1, 3, 5});
      controller.caloriesText.text = '2300';
      controller.setAdjustment(
        1,
        const WeekAdjustment(label: 'Deload', restCalories: 1800),
      );
      await controller.save();

      phase = (await repository.getPhase(phase.id))!;
      final weekly = await repository.getWeeklyTargets(phase);
      expect(weekly.map((t) => t?.calories), [2300, 2300, 2600, 2300]);
      expect(weekly.map((t) => t?.restCalories), [2000, 1800, 2000, 2000]);
      expect(weekly[1]?.weekLabel, 'Deload');
      expect(weekly[0]?.strengthDays, [1, 3, 5]);
      expect(weekly[0]?.workoutsPerWeek, 3);
      expect(
        weekly[2]?.carbsG,
        remainingCarbsG(calories: 2600, proteinG: 160, fatG: 70),
      );
      controller.dispose();
    });

    test('weeks already lived are locked', () async {
      final plan = await repository.createChainedPlan(
        name: 'Year',
        startDate: start,
        phases: [entry('Cut', 4, seed: target())],
      );
      final phase = (await repository.getPhases(plan.id)).single;
      final controller = PhaseEditorController(
        plan: plan,
        phase: phase,
        today: DateTime(2026, 1, 21), // week 3
      );
      await controller.load();
      expect(controller.editableFrom, 2);
      expect(controller.isLocked(1), isTrue);
      expect(controller.isLocked(2), isFalse);
      controller.caloriesText.text = '2100';
      await controller.save();
      final weekly = await repository.getWeeklyTargets(phase);
      expect(weekly.map((t) => t?.calories), [2400, 2400, 2100, 2100]);
      controller.dispose();
    });

    test('changing the length re-chains the following phases', () async {
      final plan = await repository.createChainedPlan(
        name: 'Year',
        startDate: start,
        phases: [
          entry('Cut', 4, seed: target()),
          entry('Bulk', 4),
        ],
      );
      final phases = await repository.getPhases(plan.id);
      final controller = PhaseEditorController(
        plan: plan,
        phase: phases.first,
        today: DateTime(2025, 12, 1),
      );
      await controller.load();
      controller.setWeeks(6);
      await controller.save();
      final after = await repository.getPhases(plan.id);
      expect(after.first.totalWeeks, 6);
      expect(after.last.startDate, DateTime(2026, 2, 16));
      final weekly = await repository.getWeeklyTargets(after.first);
      expect(weekly, hasLength(6));
      expect(weekly.every((t) => t?.calories == 2400), isTrue);
      expect(
        (await repository.getPlan(plan.id))!.status,
        PeriodizationPlanStatus.active,
      );
      controller.dispose();
    });
  });
}
