class PeriodizationMetrics {
  final DateTime startDate;
  final DateTime endDate;
  final int elapsedDays;
  final int workoutCount;
  final int completedSets;
  final double volume;
  final int? plannedWorkouts;
  final int? plannedSetsMinimum;
  final int nutritionDaysLogged;
  final double? averageCalories;
  final double? averageProteinG;
  final double? nutritionAdherencePercent;
  final double? startingWeightKg;
  final double? endingWeightKg;
  final double? weightChangeKg;
  final double? averageSleepHours;
  final int sleepDaysLogged;

  const PeriodizationMetrics({
    required this.startDate,
    required this.endDate,
    required this.elapsedDays,
    required this.workoutCount,
    required this.completedSets,
    required this.volume,
    this.plannedWorkouts,
    this.plannedSetsMinimum,
    required this.nutritionDaysLogged,
    this.averageCalories,
    this.averageProteinG,
    this.nutritionAdherencePercent,
    this.startingWeightKg,
    this.endingWeightKg,
    this.weightChangeKg,
    this.averageSleepHours,
    required this.sleepDaysLogged,
  });

  double? get workoutAdherencePercent =>
      plannedWorkouts == null || plannedWorkouts == 0
      ? null
      : (workoutCount / plannedWorkouts! * 100).clamp(0, 200);

  Map<String, dynamic> toSnapshot() => {
    'start_date': _date(startDate),
    'end_date': _date(endDate),
    'elapsed_days': elapsedDays,
    'workout_count': workoutCount,
    'completed_sets': completedSets,
    'volume': volume,
    'planned_workouts': plannedWorkouts,
    'planned_sets_minimum': plannedSetsMinimum,
    'workout_adherence_percent': workoutAdherencePercent,
    'nutrition_days_logged': nutritionDaysLogged,
    'average_calories': averageCalories,
    'average_protein_g': averageProteinG,
    'nutrition_adherence_percent': nutritionAdherencePercent,
    'starting_weight_kg': startingWeightKg,
    'ending_weight_kg': endingWeightKg,
    'weight_change_kg': weightChangeKg,
    'average_sleep_hours': averageSleepHours,
    'sleep_days_logged': sleepDaysLogged,
  };

  static String _date(DateTime value) => DateTime(
    value.year,
    value.month,
    value.day,
  ).toIso8601String().substring(0, 10);
}
