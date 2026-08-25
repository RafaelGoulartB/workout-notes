import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/run_session_context.dart';
import 'package:workout_notes/models/run_session_goal.dart';
import 'package:workout_notes/models/run_tracking_state.dart';
import 'package:workout_notes/models/run_voice_settings.dart';

void main() {
  test('session context survives native spool map round trip', () {
    const original = RunSessionContext(
      planWorkoutId: 'plan-workout-1',
      scheduledRunId: 'scheduled-1',
      goal: RunSessionGoal(
        enabled: true,
        metric: RunIntervalMetric.time,
        value: 2700,
      ),
      intervalsOn: true,
      planSteps: [
        {'role': 'work', 'metric': 'distance', 'value': 800},
      ],
    );

    final restored = RunSessionContext.fromMap(original.toMap());

    expect(restored.planWorkoutId, original.planWorkoutId);
    expect(restored.scheduledRunId, original.scheduledRunId);
    expect(restored.goal.enabled, isTrue);
    expect(restored.goal.metric, RunIntervalMetric.time);
    expect(restored.goal.value, 2700);
    expect(restored.intervalsOn, isTrue);
    expect(restored.planSteps.single['value'], 800);
  });

  test('tracking state exposes recovered context and native step cursor', () {
    final state = RunTrackingState.fromMap({
      'status': RunTrackingState.paused,
      'session_context': {
        'plan_workout_id': 'planned-1',
        'scheduled_run_id': 'scheduled-1',
        'goal': {'enabled': true, 'metric': 'distance', 'value': 5000},
        'intervals_on': false,
      },
      'step_snapshot': {
        'phase': 'running',
        'stepIndex': 3,
        'totalSteps': 8,
        'role': 'recovery',
        'repIndex': 2,
        'repTotal': 4,
        'metric': 'time',
        'target': 90,
        'progress': 0.5,
        'remaining': 45.0,
        'workRepsDone': 2,
        'workRepsTotal': 4,
      },
    });

    expect(state.sessionContext?.planWorkoutId, 'planned-1');
    expect(state.sessionContext?.scheduledRunId, 'scheduled-1');
    expect(state.nativeStepSnapshot?['stepIndex'], 3);
    expect(state.nativeStepSnapshot?['remaining'], 45.0);
  });
}
