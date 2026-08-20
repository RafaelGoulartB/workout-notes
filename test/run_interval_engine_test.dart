import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/run_voice_settings.dart';
import 'package:workout_notes/services/run_interval_engine.dart';

void main() {
  group('RunIntervalEngine', () {
    test('distance work then time rest then next work', () {
      final engine = RunIntervalEngine(
        preset: const RunIntervalPreset(
          workMetric: RunIntervalMetric.distance,
          workValue: 400,
          restMetric: RunIntervalMetric.time,
          restValue: 60,
          repeats: 3,
        ),
      );

      expect(engine.start().single.kind, RunIntervalEventKind.workStarted);
      expect(engine.snapshot.phase, RunIntervalPhase.work);

      // Incomplete work
      var events = engine.tick(
        recording: true,
        distanceMeters: 200,
        movingTimeSeconds: 40,
      );
      expect(events, isEmpty);
      expect(engine.snapshot.phase, RunIntervalPhase.work);

      // Complete first work → rest
      events = engine.tick(
        recording: true,
        distanceMeters: 400,
        movingTimeSeconds: 80,
      );
      expect(events.map((e) => e.kind), [RunIntervalEventKind.restStarted]);
      expect(engine.snapshot.phase, RunIntervalPhase.rest);

      // Pause freezes progress
      events = engine.tick(
        recording: false,
        distanceMeters: 400,
        movingTimeSeconds: 140,
      );
      expect(events, isEmpty);
      expect(engine.snapshot.phase, RunIntervalPhase.rest);

      // Finish rest → work 2
      events = engine.tick(
        recording: true,
        distanceMeters: 400,
        movingTimeSeconds: 200,
      );
      expect(events.map((e) => e.kind), [RunIntervalEventKind.workStarted]);
      expect(engine.snapshot.workIndex, 2);
    });

    test('skips trailing rest after last work', () {
      final engine = RunIntervalEngine(
        preset: const RunIntervalPreset(
          workMetric: RunIntervalMetric.time,
          workValue: 30,
          restMetric: RunIntervalMetric.time,
          restValue: 30,
          repeats: 2,
        ),
      );
      engine.start();

      // Finish work 1
      var events = engine.tick(
        recording: true,
        distanceMeters: 0,
        movingTimeSeconds: 30,
      );
      expect(events.single.kind, RunIntervalEventKind.restStarted);

      // Finish rest → work 2
      events = engine.tick(
        recording: true,
        distanceMeters: 0,
        movingTimeSeconds: 60,
      );
      expect(events.single.kind, RunIntervalEventKind.workStarted);
      expect(engine.snapshot.workIndex, 2);

      // Finish work 2 → done (no trailing rest)
      events = engine.tick(
        recording: true,
        distanceMeters: 0,
        movingTimeSeconds: 90,
      );
      expect(events.single.kind, RunIntervalEventKind.completed);
      expect(engine.snapshot.phase, RunIntervalPhase.done);
    });

    test('zero rest jumps to next work', () {
      final engine = RunIntervalEngine(
        preset: const RunIntervalPreset(
          workMetric: RunIntervalMetric.distance,
          workValue: 100,
          restMetric: RunIntervalMetric.time,
          restValue: 0,
          repeats: 2,
        ),
      );
      engine.start();
      final events = engine.tick(
        recording: true,
        distanceMeters: 100,
        movingTimeSeconds: 20,
      );
      expect(events.single.kind, RunIntervalEventKind.workStarted);
      expect(engine.snapshot.workIndex, 2);
    });

    test('emits 30s remaining cue for long time phases', () {
      final engine = RunIntervalEngine(
        preset: const RunIntervalPreset(
          workMetric: RunIntervalMetric.time,
          workValue: 90,
          restMetric: RunIntervalMetric.time,
          restValue: 0,
          repeats: 1,
        ),
      );
      engine.start();
      final events = engine.tick(
        recording: true,
        distanceMeters: 0,
        movingTimeSeconds: 60,
      );
      expect(
        events.map((e) => e.kind),
        [RunIntervalEventKind.timeRemainingCue],
      );
      expect(engine.snapshot.phase, RunIntervalPhase.work);
    });
  });
}
