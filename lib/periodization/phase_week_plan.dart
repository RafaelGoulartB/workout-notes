import 'package:workout_notes/models/periodization_target.dart';
import 'package:workout_notes/models/run_plan.dart';
import 'package:workout_notes/models/run_plan_workout.dart';

/// One weekday of a phase's template week.
class PlannedWeekday {
  /// ISO weekday, 1 = Monday … 7 = Sunday.
  final int weekday;

  /// A strength session is planned (the weekday is in `strengthDays`).
  final bool strength;

  /// Zero-based position of this strength day in the week (0 for the first
  /// strength day…), used to preview which routine day falls here. Null when
  /// [strength] is false.
  final int? strengthIndex;

  /// Sessions of the linked running plan on this weekday.
  final List<RunPlanWorkout> runs;

  /// A run is planned: either a linked plan session or a manual run day.
  final bool run;

  /// Nutrition target for this day (training- or rest-day values).
  final double? calories;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;

  const PlannedWeekday({
    required this.weekday,
    required this.strength,
    this.strengthIndex,
    this.runs = const [],
    required this.run,
    this.calories,
    this.proteinG,
    this.carbsG,
    this.fatG,
  });

  bool get trainingDay => strength || run;
}

/// Expands a phase target into its template week (Monday → Sunday).
///
/// Training days are the weekdays with a strength session or a run. When a
/// running plan is linked, its sessions for [runPlanWeek] decide the run days;
/// otherwise the target's manual `runDays` do. Rest days use the target's
/// rest-day nutrition when it has one.
///
/// Pure, so the editor preview, the phase screen, the home "this week" strip,
/// the nutrition goal resolver and adherence metrics all agree.
abstract final class PhaseWeekPlan {
  static List<PlannedWeekday> build({
    required PeriodizationTarget? target,
    RunPlan? runPlan,
    int? runPlanWeek,
  }) {
    final strengthDays = target?.strengthDays ?? const <int>[];
    final planSessions = runPlan != null && runPlanWeek != null
        ? runPlan.workoutsForWeek(runPlanWeek)
        : const <RunPlanWorkout>[];
    final manualRunDays = runPlan == null
        ? target?.runDays ?? const <int>[]
        : const <int>[];
    return [
      for (var weekday = 1; weekday <= 7; weekday++)
        _day(
          weekday: weekday,
          target: target,
          strengthDays: strengthDays,
          runs: planSessions
              .where((session) => session.dayOfWeek == weekday)
              .toList(),
          manualRun: manualRunDays.contains(weekday),
        ),
    ];
  }

  static PlannedWeekday _day({
    required int weekday,
    required PeriodizationTarget? target,
    required List<int> strengthDays,
    required List<RunPlanWorkout> runs,
    required bool manualRun,
  }) {
    final strengthIndex = strengthDays.indexOf(weekday);
    final strength = strengthIndex >= 0;
    final run = runs.isNotEmpty || manualRun;
    final nutrition = target?.nutritionFor(trainingDay: strength || run);
    return PlannedWeekday(
      weekday: weekday,
      strength: strength,
      strengthIndex: strength ? strengthIndex : null,
      runs: runs,
      run: run,
      calories: nutrition?.calories,
      proteinG: nutrition?.proteinG,
      carbsG: nutrition?.carbsG,
      fatG: nutrition?.fatG,
    );
  }

  /// Average daily calories over the template week (training and rest days
  /// weighted by how many of each the week has).
  static double? averageCalories(List<PlannedWeekday> week) {
    final values = week.map((day) => day.calories).whereType<double>();
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }
}

/// Carbs that fill the calories left after protein and fat
/// (`(kcal − 4·P − 9·F) / 4`), never negative. Null without calories.
double? remainingCarbsG({
  required double? calories,
  double? proteinG,
  double? fatG,
}) {
  if (calories == null) return null;
  final carbs = (calories - (proteinG ?? 0) * 4 - (fatG ?? 0) * 9) / 4;
  return carbs <= 0 ? 0 : carbs.roundToDouble();
}
