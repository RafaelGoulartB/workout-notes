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

  test('a quiet bedside night remains estimable without audible breathing', () {
    for (final motion in <double?>[null, 0, 20]) {
      final result = engine.run(
        session: bedsideSession(minutes: 480),
        segments: [
          for (var i = 0; i < 960; i++) bedsideSegment(i, motion: motion),
        ],
      );
      expect(result.ran, true);
      expect(
        result.epochs.take(39).every((e) => e.stage == SleepStageType.unknown),
        true,
      );
      expect(result.epochs.skip(39).every((e) => e.isSleep), true);
      expect(result.coverage, greaterThan(0.95));
      expect(result.epochs.any((e) => e.stage == SleepStageType.deep), false);
      final summary = const SleepStageAnalysisService().summarize(
        sessionStart: bedsideStart,
        sessionEnd: bedsideSession(minutes: 480).endedAt!,
        epochs: result.epochs,
      );
      expect(summary!.unknownMinutes, 20);
      expect(summary.sleepOnsetAt, result.epochs[39].startedAt);
      expect(summary.finalWakeAt, isNull);
    }
  });

  test(
    'sleep confirmation does not backdate over sustained awake activity',
    () {
      final result = engine.run(
        session: bedsideSession(),
        segments: [
          for (var i = 0; i < 120; i++)
            bedsideSegment(i, periodic: i >= 60, activity: i < 60),
        ],
      );
      expect(result.epochs.take(79).any((e) => e.isSleep), false);
      expect(result.epochs[79].stage, SleepStageType.sleeping);
      expect(result.epochs.any((e) => e.stage == SleepStageType.deep), false);
      final summary = const SleepStageAnalysisService().summarize(
        sessionStart: bedsideStart,
        sessionEnd: bedsideSession().endedAt!,
        epochs: result.epochs,
      )!;
      expect(summary.sleepOnsetAt, result.epochs[79].startedAt);
    },
  );

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

  test('intermittent breathing and brief noises still allow bedside sleep', () {
    final result = engine.run(
      session: bedsideSession(minutes: 480),
      segments: [
        for (var i = 0; i < 960; i++)
          bedsideSegment(i, periodic: i % 3 == 0, activity: i % 10 == 9),
      ],
    );
    expect(result.coverage, greaterThan(0.94));
    expect(result.epochs.any((e) => e.stage == SleepStageType.awake), false);
    expect(result.epochs.last.stage, SleepStageType.sleeping);
    expect(
      result.decisionReasons.values,
      contains('sustained_low_audio_activity'),
    );
  });

  test('quiet audio maintains sleep after breathing becomes inaudible', () {
    final result = engine.run(
      session: bedsideSession(),
      segments: [
        for (var i = 0; i < 120; i++) bedsideSegment(i, periodic: i < 20),
      ],
    );
    expect(result.epochs.skip(19).every((e) => e.isSleep), true);
  });

  test('sustained activity clears quiet support before sleep can resume', () {
    final cursor = SleepWakeCursor(sessionId: 'bedside');
    for (var i = 0; i < 80; i++) {
      cursor.add(bedsideSegment(i));
    }
    cursor.add(bedsideSegment(80, activity: true));
    expect(
      cursor.add(bedsideSegment(81, activity: true)).epoch.stage,
      SleepStageType.awake,
    );
    for (var i = 82; i < 121; i++) {
      expect(cursor.add(bedsideSegment(i)).epoch.isSleep, false);
    }
    expect(cursor.add(bedsideSegment(121)).epoch.isSleep, true);
  });

  test('digital silence is a capture failure, not quiet sleep evidence', () {
    final result = engine.run(
      session: bedsideSession(minutes: 480),
      segments: [
        for (var i = 0; i < 960; i++)
          SleepMonitorSegment.fromMap({
            ...bedsideSegment(i).toMap(),
            'digital_silence_fraction': 1.0,
          }),
      ],
    );
    expect(result.coverage, 0);
    expect(result.validEpochs, 0);
    expect(result.window.onsetAt, isNull);
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
