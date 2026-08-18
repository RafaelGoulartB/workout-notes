class PeriodizationRoutineSuggestion {
  final String phaseId;
  final String linkId;
  final String routineId;
  final String routineName;
  final String routineDayId;
  final String routineDayName;
  final int routineDayIndex;
  final int routineDayCount;
  final int completedWorkouts;

  const PeriodizationRoutineSuggestion({
    required this.phaseId,
    required this.linkId,
    required this.routineId,
    required this.routineName,
    required this.routineDayId,
    required this.routineDayName,
    required this.routineDayIndex,
    required this.routineDayCount,
    required this.completedWorkouts,
  });
}
