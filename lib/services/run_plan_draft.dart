import 'package:workout_notes/models/run_plan_workout.dart';

/// Detects a session that was created just to open the editor and never
/// filled in, so backing out of "Add session" does not leave junk behind.
abstract final class RunPlanDraft {
  /// True when [workout] is still exactly what `addWorkout` created for
  /// [defaultName]: default kind, no targets, no notes and no steps.
  static bool isUntouched(
    RunPlanWorkout workout, {
    required String defaultName,
  }) =>
      workout.name == defaultName &&
      workout.kind == RunWorkoutKind.easy &&
      !workout.hasSteps &&
      workout.targetDistanceMeters == null &&
      workout.targetDurationSeconds == null &&
      workout.targetPaceSecPerKm == null &&
      (workout.notes == null || workout.notes!.trim().isEmpty) &&
      (workout.effortZone == null || workout.effortZone!.isEmpty);
}
