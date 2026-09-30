import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/run_interval_snapshot.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/models/run_step_snapshot.dart';
import 'package:workout_notes/models/run_voice_settings.dart';
import 'package:workout_notes/models/run_workout_step.dart';

RunWorkoutStep step({
  required int order,
  required RunStepRole role,
  RunIntervalMetric metric = RunIntervalMetric.distance,
  required int value,
  int? repeatGroup,
  int repeatCount = 1,
  double? paceMin,
  double? paceMax,
}) => RunWorkoutStep(
  id: 'step-$order',
  runPlanWorkoutId: 'w1',
  orderIndex: order,
  role: role,
  metric: metric,
  value: value,
  repeatGroup: repeatGroup,
  repeatCount: repeatCount,
  targetPaceMinSecPerKm: paceMin,
  targetPaceMaxSecPerKm: paceMax,
);

RunPlanWorkout workout(List<RunWorkoutStep> steps) => RunPlanWorkout(
  id: 'w1',
  runPlanId: 'p1',
  weekIndex: 0,
  orderIndex: 0,
  kind: RunWorkoutKind.interval,
  name: 'Tiros',
  createdAt: DateTime(2026, 1, 1),
  steps: steps,
);

void main() {
  group('repeat expansion', () {
    test('expands a 6x800m block into 12 steps plus warmup and cooldown', () {
      final session = workout([
        step(order: 0, role: RunStepRole.warmup, value: 2000),
        step(
          order: 1,
          role: RunStepRole.work,
          value: 800,
          repeatGroup: 1,
          repeatCount: 6,
        ),
        step(
          order: 2,
          role: RunStepRole.recovery,
          metric: RunIntervalMetric.time,
          value: 120,
          repeatGroup: 1,
          repeatCount: 6,
        ),
        step(order: 3, role: RunStepRole.cooldown, value: 1000),
      ]);

      final expanded = session.expandSteps();

      expect(expanded.length, 14); // 1 + (2 x 6) + 1
      expect(expanded.first.step.role, RunStepRole.warmup);
      expect(expanded.last.step.role, RunStepRole.cooldown);
      expect(session.workRepCount, 6);
      expect(expanded[1].repIndex, 1);
      expect(expanded[3].repIndex, 2);
      expect(expanded[11].repIndex, 6);
      expect(expanded[1].repTotal, 6);
    });

    test('steps without a repeat group run exactly once', () {
      final session = workout([
        step(order: 0, role: RunStepRole.warmup, value: 1000),
        step(order: 1, role: RunStepRole.steady, value: 5000),
      ]);
      expect(session.expandSteps().length, 2);
    });

    test('two distinct repeat groups expand independently', () {
      final session = workout([
        step(
          order: 0,
          role: RunStepRole.work,
          value: 400,
          repeatGroup: 1,
          repeatCount: 4,
        ),
        step(
          order: 1,
          role: RunStepRole.work,
          value: 200,
          repeatGroup: 2,
          repeatCount: 3,
        ),
      ]);
      expect(session.expandSteps().length, 7);
    });

    test('planned distance sums repeats', () {
      final session = workout([
        step(order: 0, role: RunStepRole.warmup, value: 2000),
        step(
          order: 1,
          role: RunStepRole.work,
          value: 800,
          repeatGroup: 1,
          repeatCount: 6,
        ),
        step(order: 2, role: RunStepRole.cooldown, value: 1000),
      ]);
      expect(session.plannedDistanceMeters, 2000 + 4800 + 1000);
    });
  });

  group('execution steps', () {
    test('a continuous 2.8 km planned run executes as one steady step', () {
      final continuous = RunPlanWorkout(
        id: 'easy-2.8k',
        runPlanId: 'p1',
        weekIndex: 0,
        orderIndex: 0,
        kind: RunWorkoutKind.easy,
        name: 'Easy run',
        targetDistanceMeters: 2800,
        targetPaceSecPerKm: 360,
        createdAt: DateTime(2026, 1, 1),
      );

      expect(continuous.executionSteps, hasLength(1));
      expect(continuous.executionSteps.single.role, RunStepRole.steady);
      expect(continuous.executionSteps.single.value, 2800);
      expect(continuous.expandSteps(), hasLength(1));
    });
  });

  group('native wire snapshots', () {
    test('step preview survives the native snapshot wire format', () {
      final snapshot = RunStepSnapshot.fromMap({
        'phase': 'running',
        'stepIndex': 1,
        'totalSteps': 4,
        'role': 'work',
        'metric': 'distance',
        'target': 400,
        'nextRole': 'recovery',
        'nextMetric': 'time',
        'nextTarget': 90,
        'nextRepIndex': 1,
        'nextRepTotal': 2,
      });
      expect(snapshot.isActive, isTrue);
      expect(snapshot.hasNext, isTrue);
      expect(snapshot.nextRole, RunStepRole.recovery);
      expect(snapshot.nextMetric, RunIntervalMetric.time);
      final last = RunStepSnapshot.fromMap({
        'phase': 'running',
        'nextRole': null,
      });
      expect(last.hasNext, isFalse);
    });

    test('interval snapshot reads the native wire format', () {
      final work = RunIntervalSnapshot.fromMap({
        'phase': 'work',
        'workIndex': 2,
        'totalWorks': 8,
        'progress': 0.25,
        'remaining': 300.0,
        'metric': 'distance',
        'target': 400,
        'nextPhase': 'rest',
        'nextMetric': 'time',
        'nextTarget': 90,
      });
      expect(work.isActive, isTrue);
      expect(work.phase, RunIntervalPhase.work);
      expect(work.currentMetric, RunIntervalMetric.distance);
      expect(work.currentTarget, 400);
      expect(work.nextPhase, RunIntervalPhase.rest);
      expect(work.nextMetric, RunIntervalMetric.time);
      expect(work.nextTarget, 90);

      final done = RunIntervalSnapshot.fromMap({
        'phase': 'done',
        'nextPhase': null,
        'nextMetric': null,
      });
      expect(done.isActive, isFalse);
      expect(done.nextPhase, isNull);
      expect(done.nextMetric, isNull);
    });

    test('step results read the native rows', () {
      final result = RunStepResult.fromMap({
        'sequence': 3,
        'role': 'work',
        'repIndex': 2,
        'plannedMetric': 'time',
        'plannedValue': 120,
        'plannedPaceSecPerKm': 300,
        'distanceMeters': 400.0,
        'durationSeconds': 100,
      });
      expect(result.role, RunStepRole.work);
      expect(result.plannedMetric, RunIntervalMetric.time);
      expect(result.plannedPaceSecPerKm, 300.0);
      expect(result.actualPaceSecPerKm, 250.0);
    });
  });
}
