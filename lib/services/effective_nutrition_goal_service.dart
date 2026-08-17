import 'package:workout_notes/models/nutrition/nutrition_goal.dart';
import 'package:workout_notes/models/periodization_phase.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';

/// The nutrition goal in effect for a given day.
///
/// When an active periodization plan covers [date], the current phase's
/// effective weekly target overrides the settings goal: every nutrition
/// field set on the target wins and the remaining ones fall back to the
/// settings goal. Without a plan the settings goal is returned as is.
class EffectiveNutritionGoal {
  /// Merged goal (plan target with settings fallback), or null when
  /// nothing is configured at all.
  final NutritionGoal? goal;

  /// Phase whose weekly target is overriding the settings goal, or null
  /// when the goal comes from the nutrition settings.
  final PeriodizationPhase? phase;

  /// 1-based week of [phase] the goal belongs to.
  final int? weekNumber;

  /// Total weeks of [phase].
  final int? totalWeeks;

  const EffectiveNutritionGoal({
    this.goal,
    this.phase,
    this.weekNumber,
    this.totalWeeks,
  });

  bool get fromPlan => phase != null;
}

/// Resolves the effective daily nutrition goal for a date by composing
/// the settings goal with the active plan's current phase/week target.
///
/// Screens and services should read the goal through [resolve] instead
/// of `NutritionRepository.getActiveGoal` so an active plan always
/// overrides the settings everywhere the goal is displayed.
class EffectiveNutritionGoalService {
  const EffectiveNutritionGoalService._();

  static Future<EffectiveNutritionGoal> resolve({
    NutritionRepository? nutritionRepository,
    PeriodizationRepository? periodizationRepository,
    DateTime? date,
  }) async {
    final day = date ?? DateTime.now();
    final nutrition = nutritionRepository ?? NutritionRepository();
    final periodization = periodizationRepository ?? PeriodizationRepository();
    final base = await nutrition.getActiveGoal();
    try {
      final phase = await periodization.getEffectivePhase(day);
      if (phase == null) {
        return EffectiveNutritionGoal(goal: base);
      }
      final target = await periodization.getEffectiveTarget(
        phase.id,
        date: day,
      );
      if (target == null || target.nutritionJson.isEmpty) {
        return EffectiveNutritionGoal(goal: base);
      }
      return EffectiveNutritionGoal(
        goal: NutritionGoal(
          id: 'periodization:${target.id}',
          calories: target.calories ?? base?.calories,
          proteinG: target.proteinG ?? base?.proteinG,
          carbsG: target.carbsG ?? base?.carbsG,
          fatG: target.fatG ?? base?.fatG,
          createdAt: target.createdAt,
          updatedAt: DateTime.now(),
        ),
        phase: phase,
        weekNumber: phase.weekAt(day),
        totalWeeks: phase.totalWeeks,
      );
    } catch (_) {
      // Nutrition stays fully usable on databases that have not reached
      // the periodization migration.
      return EffectiveNutritionGoal(goal: base);
    }
  }
}
