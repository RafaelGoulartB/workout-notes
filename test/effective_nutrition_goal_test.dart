import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/database/database_periodization_schema.dart';
import 'package:workout_notes/models/periodization_phase_draft.dart';
import 'package:workout_notes/models/periodization_target.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';
import 'package:workout_notes/services/effective_nutrition_goal_service.dart';

void main() {
  late Database database;
  late PeriodizationRepository periodization;
  late NutritionRepository nutrition;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    database = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 39,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE nutrition_goals (
              id TEXT PRIMARY KEY,
              calories REAL,
              protein_g REAL,
              carbs_g REAL,
              fat_g REAL,
              tdee REAL,
              adjustment_kind TEXT,
              adjustment_percent REAL,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              is_active INTEGER NOT NULL DEFAULT 1
            )
          ''');
          await db.execute('''
            CREATE TABLE routines (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              notes TEXT,
              created_at TEXT NOT NULL
            )
          ''');
          await DatabasePeriodizationSchema.create(db);
        },
      ),
    );
    DatabaseHelper.overrideDatabase = database;
    periodization = PeriodizationRepository();
    nutrition = NutritionRepository();
  });

  tearDown(() async {
    DatabaseHelper.overrideDatabase = null;
    await database.close();
  });

  PeriodizationTarget weekTarget({
    required DateTime validFrom,
    double? calories,
    double? proteinG,
    double? carbsG,
    double? fatG,
  }) => PeriodizationTarget(
    id: '',
    phaseId: '',
    version: 0,
    validFrom: validFrom,
    calories: calories,
    proteinG: proteinG,
    carbsG: carbsG,
    fatG: fatG,
    createdAt: DateTime(2026, 8, 1),
  );

  /// Four-week phase starting 2026-08-01, so week boundaries land on
  /// 08-01, 08-08, 08-15 and 08-22.
  Future<String> createActivePhase({List<PeriodizationTarget>? weeklyTargets}) async {
    final plan = await periodization.createPlanWithPhases(
      name: 'Plan',
      startDate: DateTime(2026, 8, 1),
      phases: [
        PeriodizationPhaseDraft(
          name: 'Base',
          color: 0xFF4F8EF7,
          startDate: DateTime(2026, 8, 1),
          endDate: DateTime(2026, 8, 28),
          target: weeklyTargets == null
              ? weekTarget(
                  validFrom: DateTime(2026, 8, 1),
                  calories: 2500,
                  proteinG: 160,
                  carbsG: 250,
                  fatG: 70,
                )
              : null,
          weeklyTargets: weeklyTargets,
        ),
      ],
    );
    final phases = await periodization.getPhases(plan.id);
    return phases.first.id;
  }

  test('without a plan the settings goal is returned unchanged', () async {
    await nutrition.saveGoal(
      tdee: 2500,
      adjustmentKind: 'cut',
      adjustmentPercent: -20,
      proteinG: 160,
      carbsG: 230,
      fatG: 64,
    );
    final effective = await EffectiveNutritionGoalService.resolve(
      nutritionRepository: nutrition,
      periodizationRepository: periodization,
      date: DateTime(2026, 8, 10),
    );
    expect(effective.fromPlan, isFalse);
    expect(effective.phase, isNull);
    expect(effective.goal!.calories, 2000);
    expect(effective.goal!.proteinG, 160);
  });

  test('nothing configured resolves to a null goal', () async {
    final effective = await EffectiveNutritionGoalService.resolve(
      nutritionRepository: nutrition,
      periodizationRepository: periodization,
      date: DateTime(2026, 8, 10),
    );
    expect(effective.goal, isNull);
    expect(effective.fromPlan, isFalse);
  });

  test('the active plan current week overrides the settings goal', () async {
    await nutrition.saveGoal(
      tdee: 2500,
      adjustmentKind: 'cut',
      adjustmentPercent: -20,
      proteinG: 160,
      carbsG: 230,
      fatG: 64,
    );
    // Weeks 1 and 2 carry their own targets; 3 and 4 inherit week 2.
    await createActivePhase(weeklyTargets: [
      weekTarget(
        validFrom: DateTime(2026, 8, 1),
        calories: 2600,
        proteinG: 170,
      ),
      weekTarget(
        validFrom: DateTime(2026, 8, 8),
        calories: 2400,
        proteinG: 165,
        carbsG: 240,
        fatG: 66,
      ),
    ]);

    // 2026-08-10 is week 2: the newest week override wins.
    final week2 = await EffectiveNutritionGoalService.resolve(
      nutritionRepository: nutrition,
      periodizationRepository: periodization,
      date: DateTime(2026, 8, 10),
    );
    expect(week2.fromPlan, isTrue);
    expect(week2.phase!.name, 'Base');
    expect(week2.weekNumber, 2);
    expect(week2.totalWeeks, 4);
    expect(week2.goal!.calories, 2400);
    expect(week2.goal!.proteinG, 165);
    expect(week2.goal!.carbsG, 240);
    expect(week2.goal!.fatG, 66);

    // 2026-08-03 is week 1.
    final week1 = await EffectiveNutritionGoalService.resolve(
      nutritionRepository: nutrition,
      periodizationRepository: periodization,
      date: DateTime(2026, 8, 3),
    );
    expect(week1.weekNumber, 1);
    expect(week1.goal!.calories, 2600);
    expect(week1.goal!.proteinG, 170);

    // 2026-08-20 is week 3, which inherits week 2's target.
    final week3 = await EffectiveNutritionGoalService.resolve(
      nutritionRepository: nutrition,
      periodizationRepository: periodization,
      date: DateTime(2026, 8, 20),
    );
    expect(week3.weekNumber, 3);
    expect(week3.goal!.calories, 2400);
  });

  test('fields missing on the plan target fall back to the settings goal', () async {
    await nutrition.saveGoal(
      tdee: 2500,
      adjustmentKind: 'cut',
      adjustmentPercent: -20,
      proteinG: 160,
      carbsG: 230,
      fatG: 64,
    );
    // The phase target only defines calories.
    await createActivePhase(weeklyTargets: [
      weekTarget(validFrom: DateTime(2026, 8, 1), calories: 2200),
    ]);
    final effective = await EffectiveNutritionGoalService.resolve(
      nutritionRepository: nutrition,
      periodizationRepository: periodization,
      date: DateTime(2026, 8, 10),
    );
    expect(effective.fromPlan, isTrue);
    expect(effective.goal!.calories, 2200);
    expect(effective.goal!.proteinG, 160);
    expect(effective.goal!.carbsG, 230);
    expect(effective.goal!.fatG, 64);
  });

  test('a target without nutrition values is ignored', () async {
    await nutrition.saveGoal(
      tdee: 2500,
      adjustmentKind: 'cut',
      adjustmentPercent: -20,
    );
    await createActivePhase(weeklyTargets: [
      weekTarget(validFrom: DateTime(2026, 8, 1)),
    ]);
    final effective = await EffectiveNutritionGoalService.resolve(
      nutritionRepository: nutrition,
      periodizationRepository: periodization,
      date: DateTime(2026, 8, 10),
    );
    expect(effective.fromPlan, isFalse);
    expect(effective.goal!.calories, 2000);
  });

  test('a date outside every phase falls back to the settings goal', () async {
    await nutrition.saveGoal(tdee: 2500, adjustmentKind: 'cut', adjustmentPercent: -20);
    await createActivePhase(weeklyTargets: [
      weekTarget(validFrom: DateTime(2026, 8, 1), calories: 2400),
    ]);
    final effective = await EffectiveNutritionGoalService.resolve(
      nutritionRepository: nutrition,
      periodizationRepository: periodization,
      date: DateTime(2026, 12, 25),
    );
    expect(effective.fromPlan, isFalse);
    expect(effective.goal!.calories, 2000);
  });
}
