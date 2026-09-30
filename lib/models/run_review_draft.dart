import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/models/run_lap.dart';
import 'package:workout_notes/models/run_split.dart';
import 'package:workout_notes/models/run_track_point.dart';
import 'package:workout_notes/models/scheduled_run.dart';
import 'package:workout_notes/utils/run_formatters.dart';

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

  /// GPS points carried by the spool, in recording order. Empty for indoor
  /// sessions. Parsed on every call, so read it once.
  List<RunTrackPoint> get trackPoints {
    final rows = (spool['points'] as List? ?? const []).whereType<Map>();
    final points = <RunTrackPoint>[];
    var index = 0;
    for (final row in rows) {
      final lat = (row['lat'] as num?)?.toDouble();
      final lng = (row['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      points.add(
        RunTrackPoint(
          id: row['id'] as String? ?? '$id-$index',
          activityId: id,
          seq: (row['seq'] as num?)?.toInt() ?? index,
          lat: lat,
          lng: lng,
          altitude: (row['altitude'] as num?)?.toDouble(),
          accuracy: (row['accuracy'] as num?)?.toDouble(),
          speed: (row['speed'] as num?)?.toDouble(),
          recordedAt:
              DateTime.tryParse(row['recorded_at'] as String? ?? '') ??
              activity.startedAt.add(Duration(seconds: index)),
        ),
      );
      index++;
    }
    return points;
  }

  /// Manual laps marked while recording (empty when none).
  List<RunLap> get laps {
    final rawActivity = spool['activity'];
    final raw = rawActivity is Map ? rawActivity['laps'] : null;
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((row) => RunLap.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

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
            actualPaceSecPerKm: distance == null || duration == null
                ? null
                : RunFormatters.paceOrNull(distance, duration),
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
