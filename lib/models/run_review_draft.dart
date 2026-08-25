import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/models/run_split.dart';
import 'package:workout_notes/models/scheduled_run.dart';

/// A completed native spool that has not been accepted into run history yet.
/// Keeping the source payload makes saving idempotent and lets Android recover
/// the review after a Flutter process restart.
class RunReviewDraft {
  final RunActivity activity;
  final Map<String, dynamic> spool;
  final List<RunSplit> splits;
  final List<RunActivityStep> stepResults;
  final String? planWorkoutId;
  final String? scheduledRunId;

  const RunReviewDraft({
    required this.activity,
    required this.spool,
    required this.splits,
    required this.stepResults,
    required this.planWorkoutId,
    required this.scheduledRunId,
  });

  String get id => activity.id;

  factory RunReviewDraft.fromSpool({
    required RunActivity activity,
    required Map<String, dynamic> spool,
  }) {
    final rawActivity = Map<String, dynamic>.from(
      spool['activity'] as Map? ?? const {},
    );
    final splits = (rawActivity['splits'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => RunSplit.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);
    final steps = (rawActivity['voice_step_results'] as List? ?? const [])
        .whereType<Map>()
        .map((row) {
          final value = Map<String, dynamic>.from(row);
          final distance = (value['distanceMeters'] as num?)?.toDouble();
          final duration = (value['durationSeconds'] as num?)?.toInt();
          return RunActivityStep(
            id: '',
            runActivityId: activity.id,
            orderIndex: (value['sequence'] as num?)?.toInt() ?? 0,
            role: value['role'] as String? ?? 'work',
            repIndex: (value['repIndex'] as num?)?.toInt() ?? 1,
            plannedMetric: value['plannedMetric'] as String?,
            plannedValue: (value['plannedValue'] as num?)?.toInt(),
            plannedPaceSecPerKm: (value['plannedPaceSecPerKm'] as num?)
                ?.toDouble(),
            actualDistanceMeters: distance,
            actualDurationSeconds: duration,
            actualPaceSecPerKm:
                distance == null ||
                    distance < 1 ||
                    duration == null ||
                    duration <= 0
                ? null
                : duration / (distance / 1000),
          );
        })
        .toList(growable: false);
    return RunReviewDraft(
      activity: activity,
      spool: spool,
      splits: splits,
      stepResults: steps,
      planWorkoutId: rawActivity['plan_workout_id'] as String?,
      scheduledRunId: rawActivity['scheduled_run_id'] as String?,
    );
  }
}
