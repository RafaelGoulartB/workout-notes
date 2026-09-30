import 'package:workout_notes/models/scheduled_run.dart';

/// What the calendar ledger says about one plan session: whether it was run
/// (and which recorded run it points at), skipped, or is still waiting.
class RunPlanLedgerEntry {
  final String workoutId;
  final ScheduledRunStatus status;

  /// Calendar row this entry was read from, when the session was scheduled.
  final String? scheduledRunId;

  /// Date the session is (or was) scheduled for; the run date once completed.
  final DateTime? date;

  /// Recorded run that completed the session.
  final String? runActivityId;

  /// Distance / pace of that run, when the activity row is available.
  final double? actualDistanceMeters;
  final double? actualPaceSecPerKm;

  const RunPlanLedgerEntry({
    required this.workoutId,
    required this.status,
    this.scheduledRunId,
    this.date,
    this.runActivityId,
    this.actualDistanceMeters,
    this.actualPaceSecPerKm,
  });

  bool get isCompleted => status == ScheduledRunStatus.completed;
}
