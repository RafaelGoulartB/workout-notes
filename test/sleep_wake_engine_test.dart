import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/sleep_monitor_segment.dart';
import 'package:workout_notes/models/sleep_monitor_session.dart';
import 'package:workout_notes/models/sleep_stage_epoch.dart';
import 'package:workout_notes/models/sleep_stage_type.dart';
import 'package:workout_notes/services/sleep_stage_analysis_service.dart';
import 'package:workout_notes/services/sleep_wake_engine.dart';
import 'support/sleep_bedside_fixture.dart';

void main() {
  const engine = SleepWakeEngine();

  SleepMonitorSegment brief(int index, double seconds) =>
      SleepMonitorSegment.fromMap({
        ...bedsideSegment(index, activity: true).toMap(),
        'noise_active_seconds': seconds,
      });

  SleepMonitorSegment steady(int index) => SleepMonitorSegment.fromMap({
    ...bedsideSegment(index, activity: true).toMap(),
    'noise_active_seconds': 30.0,
    'audio_level_stddev_db': 0.2,
  });

  int firstSleep(List<SleepStageEpoch> epochs, {int from = 0}) {
    for (var i = from; i < epochs.length; i++) {
      if (epochs[i].isSleep) return i;
    }
    return -1;
  }

  SleepStageEngineResult runNight(
    List<SleepMonitorSegment> segments, {
    bool smooth = true,
  }) => engine.run(
    session: bedsideSession(minutes: segments.length ~/ 2),
    segments: segments,
    smooth: smooth,
  );

  group('evidence', () {
    test('short movements keep sleep; sustained activity wakes', () {
      final cursor = SleepWakeCursor(sessionId: 'bedside', startsAwake: true);
      for (var i = 0; i < 60; i++) {
        cursor.add(bedsideSegment(i));
      }
      expect(cursor.add(bedsideSegment(60)).epoch.stage, SleepStageType.sleeping);
      // A turn in bed: a few seconds of sound in two windows.
      for (var i = 61; i < 63; i++) {
        final decision = cursor.add(brief(i, 3));
        expect(decision.epoch.stage, SleepStageType.sleeping);
        expect(decision.epoch.movementSeconds, 3);
      }
      cursor.add(bedsideSegment(63));
      var awakeAt = -1;
      for (var i = 64; i < 70 && awakeAt < 0; i++) {
        if (cursor.add(sustainedBedsideActivity(i)).epoch.stage ==
            SleepStageType.awake) {
          awakeAt = i;
        }
      }
      // Live, a full minute of sound is enough.
      expect(awakeAt, inInclusiveRange(64, 66));
    });

    test('a steady loud background carries no evidence', () {
      final result = runNight([for (var i = 0; i < 120; i++) steady(i)]);
      expect(
        result.decisionReasons.values.toSet(),
        {'steady_background'},
      );
      // 60 minutes without evidence is longer than any bridge: unknown.
      expect(
        result.epochs.every((e) => e.stage == SleepStageType.unknown),
        true,
      );
      final cursor = SleepWakeCursor(sessionId: 'bedside', startsAwake: true);
      final live = [for (var i = 0; i < 10; i++) cursor.add(steady(i))];
      expect(live.first.epoch.stage, SleepStageType.awake);
      expect(live.last.epoch.stage, SleepStageType.unknown);
    });

    test('narrowband ambient sound near the floor is not wake evidence', () {
      // Compressor/HVAC rumble: >90% below 200 Hz, peaks ~20 dB over floor.
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
      final cursor = SleepWakeCursor(sessionId: 'bedside', startsAwake: true);
      for (var i = 0; i < 60; i++) {
        cursor.add(bedsideSegment(i));
      }
      for (var i = 60; i < 90; i++) {
        final decision = cursor.add(rumble(i));
        expect(decision.reason, 'environmental_sound');
        expect(decision.epoch.stage, SleepStageType.sleeping);
        expect(decision.epoch.movementSeconds, 0);
      }
      // The same activity from a loud broadband source still wakes.
      SleepMonitorSegment movement(int i) => SleepMonitorSegment.fromMap({
        ...rumble(i).toMap(),
        'noise_score': 20.0,
        'audio_peak_dbfs': -20.0,
        'spectral_band_energy_0': 30.0,
        'spectral_band_energy_2': 40.0,
      });
      final stages = [
        for (var i = 90; i < 95; i++) cursor.add(movement(i)).epoch.stage,
      ];
      expect(stages.first, SleepStageType.sleeping);
      expect(stages.last, SleepStageType.awake);
    });

    test('soft high-frequency sound relative to the room floor is ambient', () {
      // Dawn birdsong: a few seconds per window, excess energy only above
      // 1.5 kHz and well under 10x the room's own quiet spectrum. No peak or
      // baseline fields, so only the floor-relative rule can recognise it.
      SleepMonitorSegment birds(int i) => SleepMonitorSegment.fromMap({
        ...bedsideSegment(i).toMap(),
        'noise_active_seconds': 6.0,
        'noise_score': 9.0,
        'audio_level_stddev_db': 6.0,
        'spectral_band_energy_3': 20.0,
        'spectral_band_energy_4': 60.0,
      });
      // A person next to the phone: loud and below 1.5 kHz.
      SleepMonitorSegment person(int i) => SleepMonitorSegment.fromMap({
        ...bedsideSegment(i).toMap(),
        'noise_active_seconds': 6.0,
        'noise_score': 22.0,
        'audio_level_stddev_db': 9.0,
        'spectral_band_energy_0': 900.0,
        'spectral_band_energy_1': 600.0,
      });
      final cursor = SleepWakeCursor(sessionId: 'bedside', startsAwake: true);
      for (var i = 0; i < 60; i++) {
        cursor.add(bedsideSegment(i));
      }
      for (var i = 60; i < 100; i++) {
        final decision = cursor.add(birds(i));
        expect(decision.reason, 'environmental_sound');
        expect(decision.epoch.stage, SleepStageType.sleeping);
      }
      final decision = cursor.add(person(100));
      expect(decision.reason, 'audio_activity');
      expect(decision.epoch.movementSeconds, 6);
    });

    test('snoring is sleep evidence, not wake', () {
      SleepMonitorSegment snore(int i) => SleepMonitorSegment.fromMap({
        ...bedsideSegment(i, periodic: true).toMap(),
        'noise_active_seconds': 9.0,
        'noise_score': 18.0,
        'audio_level_stddev_db': 8.0,
        'spectral_band_energy_0': 400.0,
        'spectral_band_energy_1': 300.0,
      });
      final result = runNight([
        for (var i = 0; i < 60; i++) bedsideSegment(i),
        for (var i = 60; i < 180; i++) snore(i),
        for (var i = 180; i < 240; i++) bedsideSegment(i),
      ]);
      expect(result.decisionReasons[result.epochs[100].id], 'snoring');
      expect(result.epochs.skip(60).take(120).every((e) => e.isSleep), true);
      expect(result.epochs[100].snoring, true);
      expect(result.epochs[100].movementSeconds, 0);
      final summary = const SleepStageAnalysisService().summarize(
        sessionStart: bedsideStart,
        sessionEnd: bedsideStart.add(const Duration(minutes: 120)),
        epochs: result.epochs,
      )!;
      expect(summary.snoreMinutes, 60);
      expect(summary.restlessSleepMinutes, 0);
    });

    test('band-limited breathing is trusted despite microphone hiss', () {
      // Periodic breathing in a window whose total energy is mostly hiss.
      final hissy = SleepMonitorSegment.fromMap({
        ...bedsideSegment(0, periodic: true).toMap(),
        'spectral_band_energy_4': 60.0,
      });
      final v4 = SleepWakeCursor(
        sessionId: 'bedside',
        featureVersion: 'audio-features-v4',
      );
      final v5 = SleepWakeCursor(
        sessionId: 'bedside',
        featureVersion: 'audio-features-v5',
      );
      expect(v4.add(hissy).reason, 'quiet_audio');
      expect(v5.add(hissy).reason, 'periodic_breathing');
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
        expect(decision.epoch.stage, SleepStageType.unknown);
      }
    });
  });

  group('timing', () {
    test('a quiet night is estimable without audible breathing', () {
      final result = runNight([for (var i = 0; i < 960; i++) bedsideSegment(i)]);
      expect(result.ran, true);
      expect(result.epochs.first.stage, SleepStageType.awake);
      final onset = firstSleep(result.epochs);
      // Known awake at the start; silence becomes sleep after a few minutes.
      expect(onset, inInclusiveRange(4, 30));
      expect(result.epochs.skip(onset).every((e) => e.isSleep), true);
      expect(result.coverage, 1);
      expect(result.epochs.any((e) => e.stage == SleepStageType.deep), false);
      final summary = const SleepStageAnalysisService().summarize(
        sessionStart: bedsideStart,
        sessionEnd: bedsideSession(minutes: 480).endedAt!,
        epochs: result.epochs,
      )!;
      expect(summary.unknownMinutes, 0);
      expect(summary.sleepOnsetAt, result.epochs[onset].startedAt);
      expect(summary.finalWakeAt, isNull);
    });

    test('offline onset lands after the last activity, before live confirms', () {
      final segments = [
        for (var i = 0; i < 120; i++)
          i < 20 ? sustainedBedsideActivity(i) : bedsideSegment(i),
      ];
      final smoothed = firstSleep(runNight(segments).epochs);
      final causal = firstSleep(runNight(segments, smooth: false).epochs);
      expect(smoothed, greaterThanOrEqualTo(20));
      expect(smoothed, lessThan(causal));
    });

    test('a wake is dated to its first sustained sound, not its confirmation', () {
      final segments = [
        for (var i = 0; i < 80; i++) bedsideSegment(i),
        for (var i = 80; i < 90; i++) sustainedBedsideActivity(i),
        for (var i = 90; i < 200; i++) bedsideSegment(i),
      ];
      final smoothed = runNight(segments).epochs;
      final causal = runNight(segments, smooth: false).epochs;
      expect(smoothed[80].stage, SleepStageType.awake);
      expect(causal[80].stage, SleepStageType.sleeping);
      expect(smoothed.skip(80).take(10).every((e) => !e.isSleep), true);
    });

    test('falling back asleep is faster than the first sleep onset', () {
      final segments = [
        for (var i = 0; i < 10; i++) sustainedBedsideActivity(i),
        for (var i = 10; i < 200; i++) bedsideSegment(i),
        for (var i = 200; i < 210; i++) sustainedBedsideActivity(i),
        for (var i = 210; i < 400; i++) bedsideSegment(i),
      ];
      final epochs = runNight(segments).epochs;
      final firstOnset = firstSleep(epochs) - 10;
      final reOnset = firstSleep(epochs, from: 210) - 210;
      expect(reOnset, lessThan(firstOnset));
      // Re-onset within ~5 min instead of the old 10-20 min confirmation.
      expect(reOnset, lessThanOrEqualTo(10));
    });

    test('isolated noise during sleep is movement, not an awakening', () {
      final result = runNight([
        for (var i = 0; i < 960; i++)
          bedsideSegment(i, periodic: i % 3 == 0, activity: i % 10 == 9),
      ]);
      final onset = firstSleep(result.epochs);
      expect(onset, greaterThan(0));
      expect(
        result.epochs.skip(onset).any((e) => e.stage == SleepStageType.awake),
        false,
      );
      final summary = const SleepStageAnalysisService().summarize(
        sessionStart: bedsideStart,
        sessionEnd: bedsideSession(minutes: 480).endedAt!,
        epochs: result.epochs,
      )!;
      // A movement every five minutes is not restless; the synthetic
      // activity windows are also far too few for the threshold.
      expect(summary.restlessSleepMinutes, 0);
    });

    test('repeated movement inside sleep is restless sleep', () {
      final result = runNight([
        for (var i = 0; i < 480; i++)
          i >= 200 && i < 260 && i.isEven ? brief(i, 3) : bedsideSegment(i),
      ]);
      final summary = const SleepStageAnalysisService().summarize(
        sessionStart: bedsideStart,
        sessionEnd: bedsideSession(minutes: 240).endedAt!,
        epochs: result.epochs,
      )!;
      expect(result.epochs.skip(200).take(60).every((e) => e.isSleep), true);
      expect(summary.restlessSleepMinutes, inInclusiveRange(30, 40));
    });
  });

  group('capture', () {
    test('invalid capture is unknown without erasing the night', () {
      final result = runNight([
        for (var i = 0; i < 120; i++)
          bedsideSegment(i, invalid: i == 80),
      ]);
      expect(result.epochs[80].stage, SleepStageType.unknown);
      expect(result.decisionReasons[result.epochs[80].id], 'invalid_capture');
      expect(result.epochs[81].stage, SleepStageType.sleeping);
    });

    test('gaps stay unknown and time is preserved', () {
      final result = engine.run(
        session: bedsideSession(minutes: 60, reason: 'audio_error'),
        segments: [
          for (var i = 0; i < 50; i++) bedsideSegment(i),
          for (var i = 70; i < 120; i++) bedsideSegment(i),
        ],
      );
      final missing = result.epochs
          .where((e) => result.decisionReasons[e.id] == 'missing_capture')
          .toList();
      expect(missing.fold<int>(0, (s, e) => s + e.durationSeconds), 600);
      expect(missing.every((e) => e.stage == SleepStageType.unknown), true);
      expect(
        result.epochs.fold<int>(0, (s, e) => s + e.durationSeconds),
        3600,
      );
      expect(result.epochs.last.stage, SleepStageType.sleeping);
    });

    test('short stretches without evidence inside sleep are bridged', () {
      final result = runNight([
        for (var i = 0; i < 100; i++) bedsideSegment(i),
        for (var i = 100; i < 110; i++) steady(i),
        for (var i = 110; i < 240; i++) bedsideSegment(i),
      ]);
      expect(result.epochs.skip(100).take(10).every((e) => e.isSleep), true);
    });

    test('digital silence is a capture failure, not quiet sleep evidence', () {
      final result = runNight([
        for (var i = 0; i < 960; i++)
          SleepMonitorSegment.fromMap({
            ...bedsideSegment(i).toMap(),
            'digital_silence_fraction': 1.0,
          }),
      ]);
      expect(result.coverage, 0);
      expect(result.validEpochs, 0);
      expect(result.window.onsetAt, isNull);
    });

    test('duplicates, overlapping windows and input order do not double count', () {
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
      expect(result.epochs.where((e) => e.isSleep), isEmpty);
      expect(result.epochs.last.stage, SleepStageType.unknown);
    });

    for (final offsetMs in [-502, 69, 900]) {
      test('a first window ${offsetMs}ms off the session start is aligned', () {
        final session = SleepMonitorSession.fromMap({
          ...bedsideSession(minutes: 60).toMap(),
          'started_at': bedsideStart
              .subtract(Duration(milliseconds: offsetMs))
              .toIso8601String(),
        });
        final result = engine.run(
          session: session,
          segments: [for (var i = 0; i < 120; i++) bedsideSegment(i)],
        );
        expect(
          result.decisionReasons.values,
          isNot(contains('missing_capture')),
        );
        // The known-awake start survives the sub-second offset.
        expect(result.epochs.first.stage, SleepStageType.awake);
      });
    }
  });

  group('causal cursor', () {
    test('batch replay without smoothing equals the live cursor', () {
      final segments = [
        for (var i = 0; i < 120; i++)
          bedsideSegment(i, periodic: i < 70, activity: i >= 90),
      ];
      final cursor = SleepWakeCursor(sessionId: 'bedside', startsAwake: true);
      final online = segments.map((s) => cursor.add(s).epoch.toMap()).toList();
      final batch = engine.run(
        session: bedsideSession(),
        segments: segments,
        smooth: false,
      );
      expect(batch.epochs.map((e) => e.toMap()).toList(), online);
      final known = batch.epochs.where(
        (e) => e.stage != SleepStageType.unknown,
      );
      expect(known.every((e) => e.awakeProbability != null), true);
      expect(
        known.every(
          (e) => (e.awakeProbability! + e.sleepingProbability! - 1).abs() < 1e-9,
        ),
        true,
      );
    });

    test('live labels expire after two minutes without evidence', () {
      final cursor = SleepWakeCursor(sessionId: 'bedside', startsAwake: true);
      for (var i = 0; i < 60; i++) {
        cursor.add(bedsideSegment(i));
      }
      final missing = [
        for (var i = 60; i < 66; i++)
          cursor.add(
            SleepMonitorSegment.fromMap({
              ...bedsideSegment(i).toMap(),
              'noise_active_seconds': null,
            }),
          ),
      ];
      expect(missing.first.epoch.stage, SleepStageType.sleeping);
      expect(missing.last.epoch.stage, SleepStageType.unknown);
      expect(cursor.add(bedsideSegment(66)).epoch.stage, SleepStageType.sleeping);
    });

    test('a live gap lets the model drift instead of resetting', () {
      final cursor = SleepWakeCursor(sessionId: 'bedside', startsAwake: true);
      for (var i = 0; i < 60; i++) {
        cursor.add(bedsideSegment(i));
      }
      // Ten minutes of windows never arrived.
      expect(cursor.add(bedsideSegment(80)).epoch.stage, SleepStageType.sleeping);
    });
  });

  group('recorded nights', () {
    test('recorded quiet PCM zeros do not discard a usable bedside night', () {
      final segments = quantizedBedsideSegments();
      expect(
        segments.where((s) => s.digitalSilenceFraction! >= 0.2).length,
        464,
      );
      final result = engine.run(
        session: bedsideSession(minutes: 425),
        segments: segments,
      );
      expect(result.validEpochs, segments.length);
      expect(result.coverage, greaterThan(0.95));
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

    test('recorded ambiguous night keeps coverage; live equals batch', () {
      final segments = quantizedBedsideSegments(
        fileName: 'sleep_ambiguous_bedside.json',
      );
      final result = engine.run(
        session: bedsideSession(minutes: 369),
        segments: segments,
      );
      expect(result.coverage, greaterThan(0.95));
      expect(result.validEpochs, segments.length);
      final cursor = SleepWakeCursor(sessionId: 'bedside', startsAwake: true);
      expect(
        engine
            .run(
              session: bedsideSession(minutes: 369),
              segments: segments,
              smooth: false,
            )
            .epochs
            .take(segments.length)
            .map((e) => e.stage),
        segments.map((s) => cursor.add(s).epoch.stage),
      );
    });

    test('dawn night: birdsong is ambient, real movement is still wake', () {
      // 2026-09-30, phone on the nightstand, audio-features-v4. The session
      // started 69 ms before the first window (the v5 alignment bug), and the
      // dawn chorus fills 05:20-06:30 local time with soft 4-8 kHz sound.
      final segments = quantizedBedsideSegments(
        fileName: 'sleep_dawn_bedside.json',
      );
      final start = bedsideStart.subtract(const Duration(milliseconds: 69));
      final session = SleepMonitorSession.fromMap({
        ...bedsideSession().toMap(),
        'started_at': start.toIso8601String(),
        'ended_at': start
            .add(const Duration(seconds: 22394, milliseconds: 232))
            .toIso8601String(),
        'algorithm_version': 'audio-features-v4',
        'time_in_bed_minutes': 374,
      });
      final result = engine.run(session: session, segments: segments);
      final summary = const SleepStageAnalysisService().summarize(
        sessionStart: session.startedAt,
        sessionEnd: session.endedAt!,
        epochs: result.epochs,
      )!;
      int minute(int m) => m * 2;
      List<SleepStageEpoch> span(int from, int to) =>
          result.epochs.sublist(minute(from), minute(to));

      expect(result.epochs.first.stage, SleepStageType.awake);
      expect(summary.unknownMinutes, 0);
      expect(summary.sleepLatencyMinutes, inInclusiveRange(2, 15));
      // The dawn chorus (local 05:26-06:21) is mostly ambient and asleep.
      final dawn = span(160, 215);
      final ambient = dawn
          .where((e) => result.decisionReasons[e.id] == 'environmental_sound')
          .length;
      expect(ambient, greaterThan(dawn.length ~/ 3));
      expect(
        dawn.where((e) => e.isSleep).length,
        greaterThan(dawn.length * 0.9),
      );
      // Loud low-frequency activity (local 04:59-05:17, 06:28-06:33) wakes.
      expect(span(135, 150).every((e) => e.stage == SleepStageType.awake), true);
      expect(span(222, 226).every((e) => e.stage == SleepStageType.awake), true);
      expect(summary.awakeMinutes, inInclusiveRange(30, 90));
      expect(summary.awakeningCount, greaterThanOrEqualTo(2));
      expect(summary.restlessSleepMinutes, lessThan(summary.sleepingMinutes));
    });
  });

  test('v3 feature fields survive spool roundtrip', () {
    final original = bedsideSegment(1, periodic: true);
    expect(
      SleepMonitorSegment.fromMap(original.toMap()).toMap(),
      original.toMap(),
    );
  });
}
