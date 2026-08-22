import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/models/scheduled_run.dart';

/// The running session the plan expects on a given date.
///
/// Unlike the strength side — where the next routine day is picked by counting
/// completed workouts — running sessions are weekday-specific: the long run
/// belongs on Sunday and the interval session on Tuesday. So this resolves by
/// phase week + weekday, and prefers an already materialised [ScheduledRun].
class PeriodizationRunSuggestion {
  final String phaseId;
  final String runPlanId;
  final String runPlanName;

  /// Zero-based week of the plan that [date] maps onto.
  final int weekIndex;
  final RunPlanWorkout workout;

  /// Set when the session was already materialised onto the calendar.
  final ScheduledRun? scheduled;

  /// Completed runs logged in the phase week containing [date].
  final int completedRunsThisWeek;

  const PeriodizationRunSuggestion({
    required this.phaseId,
    required this.runPlanId,
    required this.runPlanName,
    required this.weekIndex,
    required this.workout,
    this.scheduled,
    this.completedRunsThisWeek = 0,
  });

  bool get isCompleted => scheduled?.isCompleted ?? false;
  bool get isSkipped => scheduled?.isSkipped ?? false;
}
