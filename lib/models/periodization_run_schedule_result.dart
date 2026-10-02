/// Outcome of [PeriodizationRepository.scheduleRunPlanForPhase].
class PeriodizationRunScheduleResult {
  /// Rows actually created (already-scheduled sessions are skipped). Kept as
  /// ids rather than a count so the caller can offer an undo.
  final List<String> createdIds;

  /// Phase weeks that had a linked plan to schedule.
  final int weeksCovered;

  const PeriodizationRunScheduleResult({
    this.createdIds = const [],
    this.weeksCovered = 0,
  });

  int get created => createdIds.length;

  bool get isEmpty => createdIds.isEmpty;
}
