import 'package:workout_notes/models/periodization_target.dart';
import 'package:workout_notes/periodization/phase_kind.dart';
import 'package:workout_notes/periodization/phase_week_plan.dart';

/// First targets of a new phase of [kind]: the kind's calories from [tdee],
/// protein and fat from [weightKg], the kind's weight trend, and the
/// training setup of [training] (usually the previous phase's target) so a
/// new phase keeps the routine and weekdays already planned.
///
/// Null when there is nothing to seed.
PeriodizationTarget? seedTargetForKind(
  PhaseKind kind, {
  double? tdee,
  double? weightKg,
  PeriodizationTarget? training,
}) {
  double? calories;
  double? protein;
  double? fat;
  if (tdee != null && kind.calorieFactor != null) {
    calories = ((tdee * kind.calorieFactor!) / 10).round() * 10.0;
    if (weightKg != null) {
      protein = (weightKg * kind.proteinPerKg!).roundToDouble();
      fat = (weightKg * kind.fatPerKg!).roundToDouble();
    }
  }
  final strengthDays = training?.strengthDays ?? const <int>[];
  final target = PeriodizationTarget(
    id: '',
    phaseId: '',
    version: 1,
    validFrom: DateTime(2000),
    calories: calories,
    proteinG: protein,
    fatG: fat,
    carbsG: remainingCarbsG(calories: calories, proteinG: protein, fatG: fat),
    weeklyWeightChangePercent: kind.weeklyWeightChangePercent,
    routineIds: training?.routineIds ?? const [],
    strengthDays: strengthDays,
    workoutsPerWeek: strengthDays.isEmpty ? null : strengthDays.length,
    runDays: training?.runDays ?? const [],
    runPlanIds: training?.runPlanIds ?? const [],
    sleepHours: training?.sleepHours,
    createdAt: DateTime.now(),
  );
  return target.isEmpty ? null : target;
}
