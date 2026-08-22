import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/models/run_voice_settings.dart';
import 'package:workout_notes/models/run_workout_step.dart';
import 'package:workout_notes/services/run_workout_step_engine.dart';

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

  group('engine execution', () {
    test('executes a continuous 2.8 km planned run without stored steps', () {
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
      final engine = RunWorkoutStepEngine()..configure(continuous);

      expect(continuous.executionSteps, hasLength(1));
      expect(continuous.executionSteps.single.role, RunStepRole.steady);
      expect(continuous.executionSteps.single.value, 2800);
      expect(engine.totalSteps, 1);
      expect(engine.start().single.kind, RunStepEventKind.stepStarted);

      final nearFinish = engine.tick(
        recording: true,
        distanceMeters: 2700,
        movingTimeSeconds: 972,
      );
      expect(nearFinish.single.kind, RunStepEventKind.distanceRemainingCue);
      expect(nearFinish.single.remainingMeters, 100);

      final completed = engine.tick(
        recording: true,
        distanceMeters: 2800,
        movingTimeSeconds: 1008,
      );
      expect(completed.last.kind, RunStepEventKind.workoutCompleted);
      expect(engine.snapshot.isDone, isTrue);
    });

    test('walks a distance-only session step by step', () {
      final engine = RunWorkoutStepEngine()
        ..configure(
          workout([
            step(order: 0, role: RunStepRole.warmup, value: 1000),
            step(order: 1, role: RunStepRole.work, value: 400),
            step(order: 2, role: RunStepRole.cooldown, value: 500),
          ]),
        );

      final start = engine.start();
      expect(start.single.kind, RunStepEventKind.stepStarted);
      expect(engine.snapshot.role, RunStepRole.warmup);

      // Halfway through the warmup.
      var events = engine.tick(
        recording: true,
        distanceMeters: 500,
        movingTimeSeconds: 150,
      );
      expect(events, isEmpty);
      expect(engine.snapshot.progress, closeTo(0.5, 0.001));

      // Finish warmup, start work.
      events = engine.tick(
        recording: true,
        distanceMeters: 1000,
        movingTimeSeconds: 300,
      );
      expect(events.map((e) => e.kind), [
        RunStepEventKind.stepCompleted,
        RunStepEventKind.stepStarted,
      ]);
      expect(engine.snapshot.role, RunStepRole.work);

      // Finish work, start cooldown.
      events = engine.tick(
        recording: true,
        distanceMeters: 1400,
        movingTimeSeconds: 390,
      );
      expect(engine.snapshot.role, RunStepRole.cooldown);

      // Finish cooldown → workout complete.
      events = engine.tick(
        recording: true,
        distanceMeters: 1900,
        movingTimeSeconds: 540,
      );
      expect(events.last.kind, RunStepEventKind.workoutCompleted);
      expect(engine.snapshot.isDone, isTrue);
      expect(engine.results.length, 3);
    });

    test('mixes distance work with time recovery', () {
      final engine = RunWorkoutStepEngine()
        ..configure(
          workout([
            step(
              order: 0,
              role: RunStepRole.work,
              value: 400,
              repeatGroup: 1,
              repeatCount: 2,
            ),
            step(
              order: 1,
              role: RunStepRole.recovery,
              metric: RunIntervalMetric.time,
              value: 60,
              repeatGroup: 1,
              repeatCount: 2,
            ),
          ]),
        );
      engine.start();

      // Rep 1 work done.
      engine.tick(recording: true, distanceMeters: 400, movingTimeSeconds: 90);
      expect(engine.snapshot.role, RunStepRole.recovery);
      expect(engine.snapshot.metric, RunIntervalMetric.time);

      // 60 s of recovery — distance moves too but must not advance a time step.
      engine.tick(recording: true, distanceMeters: 500, movingTimeSeconds: 120);
      expect(engine.snapshot.role, RunStepRole.recovery);
      engine.tick(recording: true, distanceMeters: 560, movingTimeSeconds: 150);
      expect(engine.snapshot.role, RunStepRole.work);
      expect(engine.snapshot.repIndex, 2);
    });

    test('emits a 30s heads-up on long time steps', () {
      final engine = RunWorkoutStepEngine()
        ..configure(
          workout([
            step(
              order: 0,
              role: RunStepRole.steady,
              metric: RunIntervalMetric.time,
              value: 300,
            ),
          ]),
        );
      engine.start();
      var events = engine.tick(
        recording: true,
        distanceMeters: 500,
        movingTimeSeconds: 200,
      );
      expect(events, isEmpty);
      events = engine.tick(
        recording: true,
        distanceMeters: 800,
        movingTimeSeconds: 280,
      );
      expect(events.single.kind, RunStepEventKind.timeRemainingCue);
      expect(events.single.remainingSeconds, 30);
      // Only once per step.
      events = engine.tick(
        recording: true,
        distanceMeters: 820,
        movingTimeSeconds: 285,
      );
      expect(events, isEmpty);
    });

    test('emits one 100m heads-up on distance steps', () {
      final engine = RunWorkoutStepEngine()
        ..configure(
          workout([step(order: 0, role: RunStepRole.work, value: 400)]),
        );
      engine.start();
      final events = engine.tick(
        recording: true,
        distanceMeters: 300,
        movingTimeSeconds: 70,
      );
      expect(events.single.kind, RunStepEventKind.distanceRemainingCue);
      expect(events.single.remainingMeters, 100);
      expect(
        engine
            .tick(recording: true, distanceMeters: 320, movingTimeSeconds: 75)
            .where((e) => e.kind == RunStepEventKind.distanceRemainingCue),
        isEmpty,
      );
    });

    test('warns once when an effort step runs slower than the target pace', () {
      final engine = RunWorkoutStepEngine()
        ..configure(
          workout([
            step(
              order: 0,
              role: RunStepRole.work,
              value: 1000,
              paceMin: 230,
              paceMax: 250,
            ),
          ]),
        );
      engine.start();
      // 200 m in 60 s → 300 s/km, slower than the 250 s/km ceiling.
      final events = engine.tick(
        recording: true,
        distanceMeters: 200,
        movingTimeSeconds: 60,
      );
      expect(events.single.kind, RunStepEventKind.paceTooSlow);
      expect(events.single.paceSecPerKm, closeTo(300, 1));
      // No repeat warning inside the same step.
      final again = engine.tick(
        recording: true,
        distanceMeters: 260,
        movingTimeSeconds: 80,
      );
      expect(
        again.where((e) => e.kind == RunStepEventKind.paceTooSlow),
        isEmpty,
      );
    });

    test('does not advance while paused', () {
      final engine = RunWorkoutStepEngine()
        ..configure(
          workout([step(order: 0, role: RunStepRole.work, value: 400)]),
        );
      engine.start();
      final events = engine.tick(
        recording: false,
        distanceMeters: 500,
        movingTimeSeconds: 120,
      );
      expect(events, isEmpty);
      expect(engine.snapshot.isActive, isTrue);
      // The paused delta is absorbed, so resuming does not jump the step.
      engine.tick(recording: true, distanceMeters: 600, movingTimeSeconds: 140);
      expect(engine.snapshot.progress, closeTo(100 / 400, 0.001));
    });

    test('counts effort reps as they complete', () {
      final engine = RunWorkoutStepEngine()
        ..configure(
          workout([
            step(
              order: 0,
              role: RunStepRole.work,
              value: 400,
              repeatGroup: 1,
              repeatCount: 3,
            ),
          ]),
        );
      engine.start();
      expect(engine.workRepsTotal, 3);
      expect(engine.snapshot.workRepsDone, 0);
      engine.tick(recording: true, distanceMeters: 400, movingTimeSeconds: 90);
      expect(engine.snapshot.workRepsDone, 1);
      engine.tick(recording: true, distanceMeters: 800, movingTimeSeconds: 180);
      expect(engine.snapshot.workRepsDone, 2);
    });

    test('finish() closes a partial step so it still reports a result', () {
      final engine = RunWorkoutStepEngine()
        ..configure(
          workout([step(order: 0, role: RunStepRole.work, value: 5000)]),
        );
      engine.start();
      engine.tick(
        recording: true,
        distanceMeters: 1200,
        movingTimeSeconds: 300,
      );
      engine.finish();
      expect(engine.results.length, 1);
      expect(engine.results.single.distanceMeters, closeTo(1200, 0.001));
      expect(engine.results.single.actualPaceSecPerKm, closeTo(250, 1));
    });

    test('an empty session completes immediately without events', () {
      final engine = RunWorkoutStepEngine()..configure(workout(const []));
      expect(engine.start(), isEmpty);
      expect(engine.snapshot.isDone, isTrue);
    });
  });
}
