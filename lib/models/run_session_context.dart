import 'dart:convert';

import 'package:workout_notes/models/run_session_goal.dart';
import 'package:workout_notes/models/run_voice_settings.dart';

/// Durable identity and per-run configuration for an active GPS session.
///
/// This payload is mirrored into the native spool before tracking starts. It
/// is intentionally made only of IDs and small value objects: plan/session
/// details are rehydrated from SQLite when Flutter returns after navigation or
/// process death.
class RunSessionContext {
  final String? planWorkoutId;
  final String? scheduledRunId;
  final RunSessionGoal goal;
  final bool intervalsOn;
  final List<Map<String, dynamic>> planSteps;

  const RunSessionContext({
    this.planWorkoutId,
    this.scheduledRunId,
    this.goal = const RunSessionGoal.defaults(),
    this.intervalsOn = false,
    this.planSteps = const [],
  });

  bool get hasPlan => planWorkoutId != null && planWorkoutId!.isNotEmpty;

  Map<String, dynamic> toMap() => {
    'plan_workout_id': planWorkoutId,
    'scheduled_run_id': scheduledRunId,
    'goal': {
      'enabled': goal.enabled,
      'metric': goal.metric.name,
      'value': goal.value,
    },
    'intervals_on': intervalsOn,
    'plan_steps': planSteps,
  };

  factory RunSessionContext.fromMap(Map<String, dynamic> map) {
    final rawGoal = map['goal'];
    Map<String, dynamic> goalMap = const {};
    if (rawGoal is Map) {
      goalMap = Map<String, dynamic>.from(rawGoal);
    } else if (rawGoal is String && rawGoal.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawGoal);
        if (decoded is Map) goalMap = Map<String, dynamic>.from(decoded);
      } catch (_) {
        // A malformed optional goal must not make an active run unreachable.
      }
    }
    return RunSessionContext(
      planWorkoutId: map['plan_workout_id'] as String?,
      scheduledRunId: map['scheduled_run_id'] as String?,
      goal: RunSessionGoal(
        enabled: goalMap['enabled'] as bool? ?? false,
        metric: goalMap['metric'] == 'time'
            ? RunIntervalMetric.time
            : RunIntervalMetric.distance,
        value: (goalMap['value'] as num?)?.toInt() ?? 5000,
      ),
      intervalsOn: map['intervals_on'] as bool? ?? false,
      planSteps: (map['plan_steps'] as List? ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false),
    );
  }
}
