import 'package:workout_notes/models/periodization_metrics.dart';
import 'package:workout_notes/models/periodization_phase.dart';
import 'package:workout_notes/models/periodization_schedule.dart';
import 'package:workout_notes/models/periodization_target.dart';
import 'package:workout_notes/periodization/phase_week_plan.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';

/// Planned vs done for one phase week: what the template week asked for and
/// what was logged, plus the weekdays that got ticked off.
class WeekProgress {
  final int weekIndex;
  final DateTime start;
  final DateTime end;
  final PeriodizationTarget? target;
  final PeriodizationDayPlan plan;
  final PeriodizationMetrics metrics;

  /// ISO weekdays with a finished workout or completed run.
  final Set<int> doneWeekdays;

  /// Days of the week with a finished strength workout, whatever routine it
  /// came from — what "strength sessions done" counts.
  final int strengthDaysDone;

  const WeekProgress({
    required this.weekIndex,
    required this.start,
    required this.end,
    required this.target,
    required this.plan,
    required this.metrics,
    required this.doneWeekdays,
    required this.strengthDaysDone,
  });

  List<PlannedWeekday> get week => plan.week;

  int get plannedStrength => week.where((day) => day.strength).length;
  int get plannedRuns => week.where((day) => day.run).length;
  int get doneStrength => strengthDaysDone;
  int get doneRuns => metrics.runCount;

  double? get plannedRunKm {
    final fromPlan = week.fold<double>(
      0,
      (sum, day) =>
          sum + day.runs.fold(0, (s, run) => s + run.plannedDistanceMeters),
    );
    if (fromPlan > 0) return fromPlan / 1000;
    final manual = target?.runWeeklyDistanceMeters;
    return manual == null ? null : manual / 1000;
  }

  double get doneRunKm => metrics.runDistanceMeters / 1000;

  /// Average daily calorie target of the week (training/rest weighted).
  double? get targetCalories =>
      PhaseWeekPlan.averageCalories(week) ?? target?.calories;

  double? get averageCalories => metrics.averageCalories;

  /// 0..1 blend of the adherence signals that have a plan behind them, or
  /// null when the week has nothing to compare yet.
  double? get score {
    final parts = <double>[
      if (plannedStrength > 0) (doneStrength / plannedStrength).clamp(0, 1),
      if (plannedRuns > 0) (doneRuns / plannedRuns).clamp(0, 1),
      if (metrics.nutritionAdherencePercent case final value?) value / 100,
      if (metrics.sleepAdherencePercent case final value?) value / 100,
    ];
    if (parts.isEmpty) return null;
    return parts.reduce((a, b) => a + b) / parts.length;
  }

  /// Loads week [weekIndex] (0-based) of [phase].
  static Future<WeekProgress> load(
    PeriodizationRepository repository,
    PeriodizationPhase phase,
    int weekIndex,
  ) async {
    final start = phase.startDate.add(Duration(days: 7 * weekIndex));
    final nominalEnd = start.add(const Duration(days: 6));
    final end = nominalEnd.isAfter(phase.endDate) ? phase.endDate : nominalEnd;
    final target = await repository.getEffectiveTarget(phase.id, date: start);
    final results = await Future.wait<Object>([
      repository.dayPlanFor(phase, target, start),
      repository.getPhaseMetrics(phase, rangeStart: start, rangeEnd: end),
      repository.getActivityDates(start, end),
    ]);
    final activity = results[2] as ({Set<String> strength, Set<String> runs});
    final done = <int>{
      for (final date in {...activity.strength, ...activity.runs})
        DateTime.parse(date).weekday,
    };
    return WeekProgress(
      weekIndex: weekIndex,
      start: start,
      end: end,
      target: target,
      plan: results[0] as PeriodizationDayPlan,
      metrics: results[1] as PeriodizationMetrics,
      doneWeekdays: done,
      strengthDaysDone: activity.strength.length,
    );
  }
}
