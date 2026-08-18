class PeriodizationMetrics {
  final DateTime startDate;
  final DateTime endDate;
  final int elapsedDays;
  final int workoutCount;
  final int completedSets;
  final double volume;
  final int? plannedWorkouts;
  final int? plannedSetsMinimum;
  final int? plannedSetsMaximum;
  final double? setAdherencePercent;
  final int nutritionDaysLogged;
  final int nutritionTargetDays;
  final double? averageCalories;
  final double? averageProteinG;
  final double? averageCarbsG;
  final double? averageFatG;
  final double? nutritionAdherencePercent;
  final double? nutritionCoveragePercent;
  final double? startingWeightKg;
  final double? endingWeightKg;
  final double? weightChangeKg;
  final double? weeklyWeightChangePercent;
  final double? weightAdherencePercent;
  final double? averageSleepHours;
  final int sleepDaysLogged;
  final int sleepTargetDays;
  final double? sleepAdherencePercent;
  final double? sleepCoveragePercent;
  final double? averageRpe;
  final int rpeSetsLogged;
  final double? rpeAdherencePercent;
  final double? rpeCoveragePercent;

  const PeriodizationMetrics({
    required this.startDate,
    required this.endDate,
    required this.elapsedDays,
    required this.workoutCount,
    required this.completedSets,
    required this.volume,
    this.plannedWorkouts,
    this.plannedSetsMinimum,
    this.plannedSetsMaximum,
    this.setAdherencePercent,
    required this.nutritionDaysLogged,
    this.nutritionTargetDays = 0,
    this.averageCalories,
    this.averageProteinG,
    this.averageCarbsG,
    this.averageFatG,
    this.nutritionAdherencePercent,
    this.nutritionCoveragePercent,
    this.startingWeightKg,
    this.endingWeightKg,
    this.weightChangeKg,
    this.weeklyWeightChangePercent,
    this.weightAdherencePercent,
    this.averageSleepHours,
    required this.sleepDaysLogged,
    this.sleepTargetDays = 0,
    this.sleepAdherencePercent,
    this.sleepCoveragePercent,
    this.averageRpe,
    this.rpeSetsLogged = 0,
    this.rpeAdherencePercent,
    this.rpeCoveragePercent,
  });

  double? get workoutAdherencePercent =>
      plannedWorkouts == null || plannedWorkouts == 0
      ? null
      : (workoutCount / plannedWorkouts! * 100).clamp(0, 100);

  Map<String, dynamic> toSnapshot() => {
    'start_date': _date(startDate),
    'end_date': _date(endDate),
    'elapsed_days': elapsedDays,
    'workout_count': workoutCount,
    'completed_sets': completedSets,
    'volume': volume,
    'planned_workouts': plannedWorkouts,
    'planned_sets_minimum': plannedSetsMinimum,
    'planned_sets_maximum': plannedSetsMaximum,
    'set_adherence_percent': setAdherencePercent,
    'workout_adherence_percent': workoutAdherencePercent,
    'nutrition_days_logged': nutritionDaysLogged,
    'nutrition_target_days': nutritionTargetDays,
    'average_calories': averageCalories,
    'average_protein_g': averageProteinG,
    'average_carbs_g': averageCarbsG,
    'average_fat_g': averageFatG,
    'nutrition_adherence_percent': nutritionAdherencePercent,
    'nutrition_coverage_percent': nutritionCoveragePercent,
    'starting_weight_kg': startingWeightKg,
    'ending_weight_kg': endingWeightKg,
    'weight_change_kg': weightChangeKg,
    'weekly_weight_change_percent': weeklyWeightChangePercent,
    'weight_adherence_percent': weightAdherencePercent,
    'average_sleep_hours': averageSleepHours,
    'sleep_days_logged': sleepDaysLogged,
    'sleep_target_days': sleepTargetDays,
    'sleep_adherence_percent': sleepAdherencePercent,
    'sleep_coverage_percent': sleepCoveragePercent,
    'average_rpe': averageRpe,
    'rpe_sets_logged': rpeSetsLogged,
    'rpe_adherence_percent': rpeAdherencePercent,
    'rpe_coverage_percent': rpeCoveragePercent,
  };

  static String _date(DateTime value) => DateTime(
    value.year,
    value.month,
    value.day,
  ).toIso8601String().substring(0, 10);
}
