enum PeriodizationWeightProjectionBasis { observedTrend, plannedRate }

class PeriodizationProjection {
  final double? currentWeightKg;
  final double? expectedEndWeightKg;
  final DateTime? estimatedGoalDate;
  final double? plannedVolume;
  final int? plannedWorkouts;
  final int? plannedSets;
  final double? weeklyWeightRatePercent;
  final PeriodizationWeightProjectionBasis? weightBasis;
  final int remainingDays;

  const PeriodizationProjection({
    this.currentWeightKg,
    this.expectedEndWeightKg,
    this.estimatedGoalDate,
    this.plannedVolume,
    this.plannedWorkouts,
    this.plannedSets,
    this.weeklyWeightRatePercent,
    this.weightBasis,
    required this.remainingDays,
  });

  bool get hasAnyEstimate =>
      expectedEndWeightKg != null ||
      estimatedGoalDate != null ||
      plannedVolume != null;
}
