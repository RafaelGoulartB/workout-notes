import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/sleep_monitor_segment.dart';
import 'package:workout_notes/models/sleep_monitor_session.dart';
import 'package:workout_notes/models/sleep_stage_type.dart';
import 'package:workout_notes/services/sleep_stage_analysis_service.dart';
import 'package:workout_notes/services/sleep_wake_engine.dart';
import 'support/sleep_bedside_fixture.dart';

void main() {
  const engine = SleepWakeEngine();

  SleepMonitorSegment ambiguous(int index) => SleepMonitorSegment.fromMap({
    ...bedsideSegment(index).toMap(),
    'noise_active_seconds': 5.0,
    'noise_score': 5.0,
  });

  test('temporary ambiguity suspends sleep without restarting sleep onset', () {
    final cursor = SleepWakeCursor(sessionId: 'bedside');
    for (var i = 0; i < 40; i++) {
      cursor.add(bedsideSegment(i));
    }
    for (var i = 40; i < 45; i++) {
      cursor.add(ambiguous(i));
    }
    expect(cursor.add(ambiguous(45)).epoch.stage, SleepStageType.unknown);
    expect(cursor.add(bedsideSegment(46)).epoch.stage, SleepStageType.sleeping);
    // A confirmed wake replaces the remembered sleep state.
    cursor.add(sustainedBedsideActivity(47));
    expect(
      cursor.add(sustainedBedsideActivity(48)).epoch.stage,
      SleepStageType.awake,
    );
    for (var i = 49; i < 54; i++) {
      cursor.add(ambiguous(i));
    }
    expect(cursor.add(bedsideSegment(54)).epoch.stage, SleepStageType.awake);
  });

  test(
    'invalid capture, gaps and prolonged ambiguity erase remembered sleep',
    () {
      for (final interruption in ['invalid', 'gap', 'ambiguous']) {
        final cursor = SleepWakeCursor(sessionId: 'bedside');
        for (var i = 0; i < 40; i++) {
          cursor.add(bedsideSegment(i));
        }
        var next = 41;
        if (interruption == 'invalid') {
          cursor.add(bedsideSegment(40, invalid: true));
        } else if (interruption == 'ambiguous') {
          for (var i = 40; i < 80; i++) {
            cursor.add(ambiguous(i));
          }
          next = 80;
        }
        expect(
          cursor.add(bedsideSegment(next)).epoch.stage,
          SleepStageType.unknown,
        );
      }
    },
  );

  test(
    'recorded ambiguous night retains usable coverage and causal labels',
    () {
      final segments = quantizedBedsideSegments(
        fileName: 'sleep_ambiguous_bedside.json',
      );
      final result = engine.run(
        session: bedsideSession(minutes: 369),
        segments: segments,
      );
      expect(result.coverage, greaterThan(0.8));
      expect(result.validEpochs, segments.length);
      expect(result.unknownEpochs, greaterThan(0));
      final causal = engine.run(
        session: bedsideSession(minutes: 369),
        segments: segments,
      );
      final cursor = SleepWakeCursor(sessionId: 'bedside', startsAwake: true);
      expect(
        const SleepWakeEngine()
            .run(
              session: bedsideSession(minutes: 369),
              segments: segments,
              refine: false,
            )
            .epochs
            .take(segments.length)
            .map((e) => e.stage),
        segments.map((s) => cursor.add(s).epoch.stage),
      );
      // The offline pass only ever turns neutral time into sleep.
      for (final (i, e) in result.epochs.indexed) {
        if (e.stage != causal.epochs[i].stage) expect(e.isSleep, true);
      }
    },
  );

  test('recorded quiet PCM zeros do not discard a usable bedside night', () {
    final segments = quantizedBedsideSegments();
    expect(segments.where((s) => s.digitalSilenceFraction! >= 0.2).length, 464);
    final result = engine.run(
      session: bedsideSession(minutes: 425),
      segments: segments,
    );
    expect(result.validEpochs, segments.length);
    expect(result.coverage, greaterThan(0.8));
    expect(result.epochs.any((e) => e.isSleep), true);
    // Zero-crossings must not change labels when all other aggregates agree.
    final withoutZeros = engine.run(
      session: bedsideSession(minutes: 425),
      segments: [
        for (final s in segments)
          SleepMonitorSegment.fromMap({
            ...s.toMap(),
            'digital_silence_fraction': 0.0,
          }),
      ],
    );
    expect(
      result.epochs.map((e) => e.stage),
      withoutZeros.epochs.map((e) => e.stage),
    );
  });

  test('brief peaks cannot turn six noisy seconds into one awake minute', () {
    final cursor = SleepWakeCursor(sessionId: 'bedside');
    for (var i = 0; i < 40; i++) {
      cursor.add(bedsideSegment(i));
    }
    for (var i = 40; i < 42; i++) {
      final decision = cursor.add(
        SleepMonitorSegment.fromMap({
          ...bedsideSegment(i, activity: true).toMap(),
          'noise_active_seconds': 3.0,
        }),
      );
      expect(decision.epoch.stage, SleepStageType.sleeping);
    }
    cursor.add(sustainedBedsideActivity(42));
    expect(
      cursor.add(sustainedBedsideActivity(43)).epoch.stage,
      SleepStageType.awake,
    );
    for (var i = 44; i < 54; i++) {
      expect(cursor.add(bedsideSegment(i)).epoch.stage, SleepStageType.awake);
    }
  });

  test('short loud peaks do not erase predominantly quiet audio', () {
    final result = engine.run(
      session: bedsideSession(),
      segments: [
        for (var i = 0; i < 120; i++)
          SleepMonitorSegment.fromMap({
            ...bedsideSegment(i).toMap(),
            'noise_score': 25.0,
            'noise_active_seconds': 0.25,
          }),
      ],
    );
    expect(result.epochs.last.stage, SleepStageType.sleeping);
    expect(
      result.epochs
          .skipWhile((e) => !e.isSleep)
          .any((e) => e.stage == SleepStageType.awake),
      false,
    );
    expect(
      result.decisionReasons.values,
      isNot(contains('sustained_audio_activity')),
    );
  });

  test('invalid zero-sample fractions and near-total silence are rejected', () {
    for (final zeros in [double.nan, double.infinity, -0.1, 0.98, 1.0]) {
      final decision = SleepWakeCursor(sessionId: 'bedside').add(
        SleepMonitorSegment.fromMap({
          ...bedsideSegment(0).toMap(),
          'digital_silence_fraction': zeros,
        }),
      );
      expect(decision.validSignal, false);
    }
  });

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
    expect(
      result.decisionReasons.values,
      isNot(contains('sustained_audio_activity')),
    );
    // Only the known-awake start is held briefly; then evidence expires.
    expect(
      result.epochs.skip(5).every((e) => e.stage == SleepStageType.unknown),
      true,
    );
  });

  test('narrowband ambient sound near the floor is not wake evidence', () {
    // Compressor/HVAC rumble: >90% below 200 Hz, peaks ~20 dB over the floor.
    SleepMonitorSegment rumble(int i) => SleepMonitorSegment.fromMap({
      ...bedsideSegment(i).toMap(),
      'noise_active_seconds': 16.0,
      'noise_score': 12.0,
      'audio_level_stddev_db': 6.0,
      'audio_peak_dbfs': -62.0,
      'audio_baseline_dbfs': -84.0,
      'spectral_band_energy_0': 97.0,
      'spectral_band_energy_1': 2.0,
      'spectral_band_energy_2': 0.5,
      'spectral_band_energy_3': 0.3,
      'spectral_band_energy_4': 0.2,
    });
    final cursor = SleepWakeCursor(sessionId: 'bedside');
    for (var i = 0; i < 40; i++) {
      cursor.add(bedsideSegment(i));
    }
    for (var i = 40; i < 60; i++) {
      final decision = cursor.add(rumble(i));
      expect(decision.reason, 'environmental_sound');
      expect(decision.epoch.stage, SleepStageType.sleeping);
    }
    // The same activity from a loud broadband source still wakes.
    SleepMonitorSegment movement(int i) => SleepMonitorSegment.fromMap({
      ...rumble(i).toMap(),
      'audio_peak_dbfs': -20.0,
      'spectral_band_energy_0': 30.0,
      'spectral_band_energy_3': 40.0,
    });
    // 16 s of activity per window: the 60 s wake threshold is met on the 4th.
    for (var i = 60; i < 63; i++) {
      expect(cursor.add(movement(i)).epoch.stage, SleepStageType.sleeping);
    }
    expect(cursor.add(movement(63)).epoch.stage, SleepStageType.awake);
  });

  test('a few noisy seconds cost only their duration of quiet support', () {
    SleepMonitorSegment brief(int i) => SleepMonitorSegment.fromMap({
      ...bedsideSegment(i).toMap(),
      'noise_active_seconds': 4.0,
      'noise_score': 6.0,
    });
    // Awake, then quiet windows with a brief sound every third window. The
    // old rule charged 30 s per brief sound, so this pattern never confirmed.
    final cursor = SleepWakeCursor(sessionId: 'bedside', startsAwake: true);
    var confirmedAt = -1;
    for (var i = 0; i < 120 && confirmedAt < 0; i++) {
      final d = cursor.add(i % 3 == 2 ? brief(i) : bedsideSegment(i));
      if (d.epoch.isSleep) confirmedAt = i;
    }
    expect(confirmedAt, inInclusiveRange(40, 70));
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
      // Known awake at the start; onset dated to the middle of the 20 min
      // quiet window that confirmed it (causally confirmed at epoch 39).
      expect(
        result.epochs.take(19).every((e) => e.stage == SleepStageType.awake),
        true,
      );
      expect(result.epochs.skip(19).every((e) => e.isSleep), true);
      expect(result.coverage, greaterThan(0.95));
      expect(result.epochs.any((e) => e.stage == SleepStageType.deep), false);
      final summary = const SleepStageAnalysisService().summarize(
        sessionStart: bedsideStart,
        sessionEnd: bedsideSession(minutes: 480).endedAt!,
        epochs: result.epochs,
      );
      expect(summary!.unknownMinutes, 0);
      expect(summary.sleepOnsetAt, result.epochs[19].startedAt);
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
      // Causal confirmation at 79 after 10 min of periodic breathing; onset is
      // dated to the middle of that window and never reaches the activity.
      expect(result.epochs.take(69).any((e) => e.isSleep), false);
      expect(result.epochs.skip(69).every((e) => e.isSleep), true);
      expect(
        result.decisionReasons[result.epochs[69].id],
        'onset_within_confirmation',
      );
      expect(result.epochs.any((e) => e.stage == SleepStageType.deep), false);
      final summary = const SleepStageAnalysisService().summarize(
        sessionStart: bedsideStart,
        sessionEnd: bedsideSession().endedAt!,
        epochs: result.epochs,
      )!;
      expect(summary.sleepOnsetAt, result.epochs[69].startedAt);
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
      cursor.add(sustainedBedsideActivity(22));
      expect(
        cursor.add(sustainedBedsideActivity(23)).epoch.stage,
        SleepStageType.awake,
      );
      for (var i = 24; i < 28; i++) {
        cursor.add(
          SleepMonitorSegment.fromMap({
            ...bedsideSegment(i).toMap(),
            'noise_active_seconds': null,
          }),
        );
      }
      expect(
        cursor
            .add(
              SleepMonitorSegment.fromMap({
                ...bedsideSegment(28).toMap(),
                'noise_active_seconds': null,
              }),
            )
            .epoch
            .stage,
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
    expect(
      result.epochs
          .skipWhile((e) => !e.isSleep)
          .any((e) => e.stage == SleepStageType.awake),
      false,
    );
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
    cursor.add(sustainedBedsideActivity(80));
    expect(
      cursor.add(sustainedBedsideActivity(81)).epoch.stage,
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
      final cursor = SleepWakeCursor(sessionId: 'bedside', startsAwake: true);
      final online = segments.map((s) => cursor.add(s).epoch.toMap()).toList();
      final batch = const SleepWakeEngine().run(
        session: bedsideSession(),
        segments: segments,
        refine: false,
      );
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
      // Only the known-awake start may be labelled; the overlap is unknown.
      expect(result.epochs.where((e) => e.isSleep), isEmpty);
      expect(result.epochs.last.stage, SleepStageType.unknown);
    },
  );

  test('a sub-second early first window is aligned, not discarded', () {
    final session = bedsideSession(minutes: 60);
    final late = SleepMonitorSession.fromMap({
      ...session.toMap(),
      'started_at': bedsideStart
          .add(const Duration(milliseconds: 502))
          .toIso8601String(),
    });
    final result = engine.run(
      session: late,
      segments: [for (var i = 0; i < 120; i++) bedsideSegment(i)],
    );
    expect(result.decisionReasons.values, isNot(contains('missing_capture')));
    expect(result.epochs.first.stage, SleepStageType.awake);
  });

  test('short neutral holes inside sleep are bridged, gaps are not', () {
    SleepMonitorSegment ambiguousAt(int i) => ambiguous(i);
    final result = engine.run(
      session: bedsideSession(minutes: 120),
      segments: [
        for (var i = 0; i < 100; i++) bedsideSegment(i),
        for (var i = 100; i < 110; i++) ambiguousAt(i),
        for (var i = 110; i < 150; i++) bedsideSegment(i),
        for (var i = 160; i < 240; i++) bedsideSegment(i),
      ],
    );
    expect(result.epochs.skip(100).take(10).every((e) => e.isSleep), true);
    expect(
      result.decisionReasons[result.epochs[105].id],
      'bridged_within_sleep',
    );
    // A recording gap is missing evidence and is never bridged.
    expect(
      result.epochs.where(
        (e) => result.decisionReasons[e.id] == 'missing_capture' && e.isSleep,
      ),
      isEmpty,
    );
  });

  test('v3 feature fields survive spool roundtrip', () {
    final original = bedsideSegment(1, periodic: true);
    expect(
      SleepMonitorSegment.fromMap(original.toMap()).toMap(),
      original.toMap(),
    );
  });
}
