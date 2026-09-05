import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/sleep_monitor_segment.dart';
import 'package:workout_notes/models/sleep_stage_type.dart';
import 'package:workout_notes/services/sleep_stage_engine.dart';
import 'package:workout_notes/services/sleep_stage_analysis_service.dart';
import 'package:workout_notes/services/sleep_wake_engine.dart';
import 'support/sleep_bedside_fixture.dart';

void main() {
  const engine = SleepStageEngine();

  test('steady loud background alone does not confirm wakefulness', () {
    final segments = [
      for (var i = 0; i < 120; i++)
        SleepMonitorSegment.fromMap({
          ...bedsideSegment(i, activity: true).toMap(),
          'noise_active_seconds': 30.0,
          'audio_level_stddev_db': 0.2,
        }),
    ];
    final result = engine.run(session: bedsideSession(), segments: segments);
    expect(result.epochs.every((e) => e.stage == SleepStageType.unknown), true);
  });

  test(
    'quiet bedside audio does not invent onset, deep sleep or terminal wake',
    () {
      for (final motion in <double?>[null, 0, 20]) {
        final result = engine.run(
          session: bedsideSession(),
          segments: [
            for (var i = 0; i < 120; i++) bedsideSegment(i, motion: motion),
          ],
        );
        expect(result.ran, true);
        expect(
          result.epochs.every((e) => e.stage == SleepStageType.unknown),
          true,
        );
        expect(result.window.onsetAt, isNull);
        expect(result.coverage, 0);
        final summary = const SleepStageAnalysisService().summarize(
          sessionStart: bedsideStart,
          sessionEnd: bedsideSession().endedAt!,
          epochs: result.epochs,
        );
        expect(summary!.unknownMinutes, 60);
        expect(summary.sleepOnsetAt, isNull);
        expect(summary.finalWakeAt, isNull);
      }
    },
  );

  test('delayed periodic evidence does not backdate sleep over quiet wake', () {
    final result = engine.run(
      session: bedsideSession(),
      segments: [
        for (var i = 0; i < 120; i++) bedsideSegment(i, periodic: i >= 60),
      ],
    );
    expect(
      result.epochs.take(79).every((e) => e.stage == SleepStageType.unknown),
      true,
    );
    expect(result.epochs[79].stage, SleepStageType.sleeping);
    expect(result.epochs.any((e) => e.stage == SleepStageType.deep), false);
    final summary = const SleepStageAnalysisService().summarize(
      sessionStart: bedsideStart,
      sessionEnd: bedsideSession().endedAt!,
      epochs: result.epochs,
    )!;
    expect(summary.sleepOnsetAt, result.epochs[79].startedAt);
  });

  test(
    'isolated noise holds sleep; sustained activity wakes; missing evidence expires',
    () {
      final cursor = SleepWakeCursor(sessionId: 'bedside');
      for (var i = 0; i < 20; i++) {
        cursor.add(bedsideSegment(i, periodic: true));
      }
      expect(
        cursor.add(bedsideSegment(20, activity: true)).epoch.stage,
        SleepStageType.sleeping,
      );
      expect(
        cursor.add(bedsideSegment(21, periodic: true)).epoch.stage,
        SleepStageType.sleeping,
      );
      cursor.add(bedsideSegment(22, activity: true));
      expect(
        cursor.add(bedsideSegment(23, activity: true)).epoch.stage,
        SleepStageType.awake,
      );
      for (var i = 24; i < 28; i++) {
        cursor.add(bedsideSegment(i));
      }
      expect(
        cursor.add(bedsideSegment(28)).epoch.stage,
        SleepStageType.unknown,
      );
    },
  );

  test('gaps reset confirmation and remain unknown even at session edges', () {
    final result = engine.run(
      session: bedsideSession(minutes: 20, reason: 'audio_error'),
      segments: [
        for (var i = 1; i < 18; i++) bedsideSegment(i, periodic: true),
        for (var i = 22; i < 39; i++) bedsideSegment(i, periodic: true),
      ],
    );
    expect(result.epochs.every((e) => e.stage == SleepStageType.unknown), true);
    expect(
      result.epochs.fold<int>(0, (sum, e) => sum + e.durationSeconds),
      1200,
    );
  });

  test('invalid signal immediately clears a previous sleep state', () {
    final cursor = SleepWakeCursor(sessionId: 'bedside');
    for (var i = 0; i < 20; i++) {
      cursor.add(bedsideSegment(i, periodic: true));
    }
    final invalid = cursor.add(bedsideSegment(20, invalid: true));
    expect(invalid.epoch.stage, SleepStageType.unknown);
    expect(invalid.validSignal, false);
    expect(
      cursor.add(bedsideSegment(21, periodic: true)).epoch.stage,
      SleepStageType.unknown,
    );
  });

  test(
    'batch replay and online cursor agree without future-dependent labels',
    () {
      final segments = [
        for (var i = 0; i < 120; i++)
          bedsideSegment(i, periodic: i < 70, activity: i >= 90),
      ];
      final cursor = SleepWakeCursor(sessionId: 'bedside');
      final online = segments.map((s) => cursor.add(s).epoch.toMap()).toList();
      final batch = engine.run(session: bedsideSession(), segments: segments);
      expect(batch.epochs.map((e) => e.toMap()).toList(), online);
      expect(batch.epochs.every((e) => e.awakeProbability == null), true);
    },
  );

  test(
    'duplicates, overlapping windows and input order do not double count time',
    () {
      final a = bedsideSegment(0, periodic: true, seconds: 60);
      final b = bedsideSegment(1, periodic: true, seconds: 60);
      final result = engine.run(
        session: bedsideSession(minutes: 2),
        segments: [b, a, a],
      );
      expect(
        result.epochs.fold<int>(0, (sum, e) => sum + e.durationSeconds),
        120,
      );
      expect(
        result.epochs.where((e) => e.stage != SleepStageType.unknown),
        isEmpty,
      );
    },
  );

  test('v3 feature fields survive spool roundtrip', () {
    final original = bedsideSegment(1, periodic: true);
    expect(
      SleepMonitorSegment.fromMap(original.toMap()).toMap(),
      original.toMap(),
    );
  });
}
