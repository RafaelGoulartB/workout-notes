import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/models/ai_proposal.dart';
import 'package:workout_notes/models/periodization_phase_draft.dart';
import 'package:workout_notes/models/periodization_target.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';
import 'package:workout_notes/services/ai_proposal_service.dart';

import 'support/ai_proposal_fixtures.dart';
import 'support/test_db.dart';

const _tool = 'propose_nutrition_goal';

void main() {
  late Database db;
  late DateTime clock;
  late AiProposalService service;
  late NutritionRepository nutrition;
  late PeriodizationRepository periodization;

  setUp(() async {
    db = await installTestDb();
    // Week 3 (index 2) of the phase below.
    clock = DateTime(2026, 8, 17, 9);
    service = AiProposalService(now: () => clock);
    nutrition = NutritionRepository();
    periodization = PeriodizationRepository();
    await AiProposalFixtures.seedThread(db);
  });

  tearDown(uninstallTestDb);

  PeriodizationTarget week(
    DateTime from, {
    double? calories,
    double? protein,
    int? workouts,
  }) => PeriodizationTarget(
    id: '',
    phaseId: '',
    version: 0,
    validFrom: from,
    calories: calories,
    proteinG: protein,
    workoutsPerWeek: workouts,
    createdAt: DateTime(2026, 8, 1),
  );

  /// Four-week phase 2026-08-01..08-28 with a different calorie target per
  /// week (2600, 2500, 2400, 2300) and 4 workouts a week.
  Future<String> seedPlan() async {
    final start = DateTime(2026, 8, 1);
    final plan = await periodization.createPlanWithPhases(
      name: 'Cut',
      startDate: start,
      phases: [
        PeriodizationPhaseDraft(
          name: 'Deficit',
          color: 0xFF4F8EF7,
          startDate: start,
          endDate: DateTime(2026, 8, 28),
          weeklyTargets: [
            for (var i = 0; i < 4; i++)
              week(
                start.add(Duration(days: 7 * i)),
                calories: 2600.0 - 100 * i,
                protein: 160,
                workouts: 4,
              ),
          ],
        ),
      ],
    );
    return (await periodization.getPhases(plan.id)).first.id;
  }

  Future<Map<String, dynamic>> refused(Map<String, dynamic> args) async {
    final result = await service.prepare(
      threadId: AiProposalFixtures.threadId,
      toolCallId: 'c',
      toolName: _tool,
      args: args,
    );
    expect(result.ok, isFalse, reason: '${result.toMap()}');
    return result.toMap();
  }

  group('settings goal', () {
    test(
      'merges the new values into the current goal and keeps one active',
      () async {
        await nutrition.saveGoal(
          calories: 2400,
          proteinG: 150,
          carbsG: 250,
          fatG: 70,
        );
        final id = await prepareProposal(service, _tool, {'calories': 2200});
        final preview = (await service.get(id))!.preview;
        expect(preview['scope'], 'settings');
        expect(dig(preview, 'before.calories'), 2400);
        expect(preview['after'], {
          'calories': 2200,
          'protein_g': 150,
          'carbs_g': 250,
          'fat_g': 70,
        });
        expect(await db.query('nutrition_goals'), hasLength(1));

        final applied = await service.approve(id);
        expect(applied.status, AiProposalStatus.applied);
        await service.approve(id);
        final rows = await db.query('nutrition_goals');
        expect(rows, hasLength(2));
        final active = rows.where((r) => r['is_active'] == 1).single;
        expect(active['id'], id);
        expect(active['calories'], 2200);
        expect(active['protein_g'], 150);
      },
    );

    test(
      'works with no goal yet, and warns when macros do not add up',
      () async {
        final id = await prepareProposal(service, _tool, {
          'calories': 3000,
          'protein_g': 100,
          'carbs_g': 100,
          'fat_g': 30,
        });
        final warnings = (await service.get(id))!.preview['warnings'] as List;
        expect(codes(warnings), contains('macros_do_not_match_calories'));
        await service.approve(id);
        expect((await db.query('nutrition_goals')).single['calories'], 3000);
      },
    );

    test('warns that a TDEE-driven goal becomes a direct one', () async {
      await nutrition.saveGoal(
        tdee: 2500,
        adjustmentKind: 'cut',
        adjustmentPercent: -20,
      );
      final id = await prepareProposal(service, _tool, {'calories': 1900});
      final warnings = (await service.get(id))!.preview['warnings'] as List;
      expect(codes(warnings), contains('tdee_reset'));
    });

    test('validates ranges, requires a field and refuses a no-op', () async {
      expect((await refused({}))['code'], 'invalid_args');
      expect((await refused({'calories': 50}))['code'], 'invalid_args');
      expect((await refused({'protein_g': 5000}))['code'], 'invalid_args');
      expect((await refused({'calories': '2000'}))['code'], 'invalid_args');
      expect(
        (await refused({'calories': 2000, 'tdee': 3000}))['code'],
        'invalid_args',
      );
      await nutrition.saveGoal(calories: 2000);
      expect((await refused({'calories': 2000}))['code'], 'no_changes');
    });

    test('a goal changed before approval makes the proposal stale', () async {
      await nutrition.saveGoal(calories: 2400);
      final id = await prepareProposal(service, _tool, {'calories': 2200});
      await nutrition.saveGoal(calories: 2500);
      final result = await service.approve(id);
      expect(result.status, AiProposalStatus.stale);
      expect(result.errorCode, 'stale_revision');
      expect((await nutrition.getActiveGoal())!.calories, 2500);
    });

    test(
      'with a plan running, an explicit settings change warns that the plan wins',
      () async {
        await seedPlan();
        final id = await prepareProposal(service, _tool, {
          'calories': 2000,
          'scope': 'settings',
        });
        final warnings = (await service.get(id))!.preview['warnings'] as List;
        final override = warnings.firstWhere(
          (w) => dig(w, 'code') == 'plan_overrides_goal',
        );
        expect(dig(override, 'phase'), 'Deficit');
        expect(dig(override, 'fields'), ['calories']);
      },
    );
  });

  group('active phase', () {
    test(
      'defaults to the phase and rewrites only the current and later weeks',
      () async {
        final phaseId = await seedPlan();
        final id = await prepareProposal(service, _tool, {'calories': 2000});
        final proposal = (await service.get(id))!;
        expect(proposal.preview['scope'], 'active_phase');
        expect(dig(proposal.preview, 'phase.from_week'), 3);
        expect(dig(proposal.preview, 'phase.weeks_changed'), 2);
        expect(dig(proposal.preview, 'before.calories'), 2400);

        final applied = await service.approve(id);
        expect(
          applied.status,
          AiProposalStatus.applied,
          reason: '${applied.errorCode}',
        );
        final phase = (await periodization.getPhase(phaseId))!;
        final weekly = await periodization.getWeeklyTargets(phase);
        expect(weekly.map((t) => t!.calories), [
          2600,
          2500,
          2000,
          2000,
        ], reason: 'lived weeks keep their targets');
        expect(weekly.map((t) => t!.proteinG), everyElement(160));
        expect(weekly.map((t) => t!.workoutsPerWeek), everyElement(4));
      },
    );

    test('requires an active phase when asked for explicitly', () async {
      final error = await refused({'calories': 2000, 'scope': 'active_phase'});
      expect(error['code'], 'no_active_phase');
    });

    test('a week that starts before approval makes it stale', () async {
      final phaseId = await seedPlan();
      final id = await prepareProposal(service, _tool, {'calories': 2000});
      clock = DateTime(2026, 8, 24, 9);
      final result = await service.approve(id);
      expect(result.status, AiProposalStatus.stale);
      expect(result.errorCode, 'stale_week_started');
      final phase = (await periodization.getPhase(phaseId))!;
      expect(
        (await periodization.getWeeklyTargets(phase)).map((t) => t!.calories),
        [2600, 2500, 2400, 2300],
      );
    });

    test('targets edited before approval make it stale', () async {
      final phaseId = await seedPlan();
      final id = await prepareProposal(service, _tool, {'protein_g': 180});
      final phase = (await periodization.getPhase(phaseId))!;
      await periodization.applyNutritionFromWeekIn(
        db,
        phase,
        fromWeek: 3,
        calories: 2100,
      );
      final result = await service.approve(id);
      expect(result.status, AiProposalStatus.stale);
      expect(result.errorCode, 'stale_revision');
    });
  });

  test(
    '0 and blanks for macros the user did not mention are ignored',
    () async {
      await nutrition.saveGoal(calories: 2400, proteinG: 150);
      final id = await prepareProposal(service, _tool, {
        'calories': 2200,
        'protein_g': 0,
        'carbs_g': 0,
        'fat_g': 0,
        'scope': '',
      });
      final preview = (await service.get(id))!.preview;
      expect(dig(preview, 'scope'), 'settings');
      expect(dig(preview, 'after.protein_g'), 150);
      await service.approve(id);
      final active = (await db.query(
        'nutrition_goals',
        where: 'is_active = 1',
      )).single;
      expect(active['calories'], 2200);
      expect(active['protein_g'], 150);
      expect(active['carbs_g'], isNull);
    },
  );
}
