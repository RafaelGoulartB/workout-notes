import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/sleep_monitor_segment.dart';
import 'package:workout_notes/models/sleep_monitor_session.dart';
import 'package:workout_notes/models/sleep_stage_epoch.dart';
import 'package:workout_notes/models/sleep_stage_type.dart';
import 'package:workout_notes/services/sleep_audio_evidence.dart';
import 'package:workout_notes/services/sleep_stage_analysis_service.dart';
import 'package:workout_notes/services/sleep_wake_engine.dart';
import 'support/sleep_bedside_fixture.dart';

void main() {
  const engine = SleepWakeEngine();

  /// Every band [db] above the quiet fixture level.
  SleepMonitorSegment broadband(
    int index, {
    double db = 10,
    double seconds = 3,
    double noise = 12,
  }) {
    final gain = math.pow(10, db / 10);
    return SleepMonitorSegment.fromMap({
      ...bedsideSegment(index).toMap(),
      'noise_score': noise,
      'noise_active_seconds': seconds,
      'audio_level_stddev_db': 6.0,
      'spectral_band_energy_0': 10 * gain,
      'spectral_band_energy_1': 20 * gain,
      'spectral_band_energy_2': 5 * gain,
      'spectral_band_energy_3': 1 * gain,
      'spectral_band_energy_4': 1 * gain,
    });
  }

  /// A turn in bed: a few seconds, every band 10 dB up.
  SleepMonitorSegment brief(int index, double seconds) =>
      broadband(index, seconds: seconds);

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
      expect(
        cursor.add(bedsideSegment(60)).epoch.stage,
        SleepStageType.sleeping,
      );
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
      expect(result.decisionReasons.values.toSet(), {
        'calibrating',
        'steady_background',
      });
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

    test('sound confined to a few bands is the room, not the person', () {
      // Traffic or a compressor: almost everything below 200 Hz.
      SleepMonitorSegment rumble(int i) => SleepMonitorSegment.fromMap({
        ...bedsideSegment(i).toMap(),
        'noise_active_seconds': 16.0,
        'noise_score': 12.0,
        'audio_level_stddev_db': 6.0,
        'spectral_band_energy_0': 1000.0,
        'spectral_band_energy_1': 40.0,
      });
      // Dawn birdsong: only above 1.5 kHz.
      SleepMonitorSegment birds(int i) => SleepMonitorSegment.fromMap({
        ...bedsideSegment(i).toMap(),
        'noise_active_seconds': 14.0,
        'noise_score': 13.0,
        'audio_level_stddev_db': 6.0,
        'spectral_band_energy_3': 60.0,
        'spectral_band_energy_4': 300.0,
      });
      // A dove or a distant voice: only the middle.
      SleepMonitorSegment cooing(int i) => SleepMonitorSegment.fromMap({
        ...bedsideSegment(i).toMap(),
        'noise_active_seconds': 8.0,
        'noise_score': 10.0,
        'audio_level_stddev_db': 5.0,
        'spectral_band_energy_1': 400.0,
        'spectral_band_energy_2': 100.0,
      });
      for (final ambient in [rumble, birds, cooing]) {
        final cursor = SleepWakeCursor(sessionId: 'bedside', startsAwake: true);
        for (var i = 0; i < 60; i++) {
          cursor.add(bedsideSegment(i));
        }
        // Two hours of it, like a whole morning.
        for (var i = 60; i < 300; i++) {
          final decision = cursor.add(ambient(i));
          expect(decision.reason, 'environmental_sound');
          expect(decision.epoch.stage, SleepStageType.sleeping);
          expect(decision.epoch.movementSeconds, 0);
          expect(decision.epoch.ambientSeconds, greaterThan(0));
        }
        // A person moving is still heard on top of it.
        final stages = [
          for (var i = 300; i < 304; i++)
            cursor.add(bedsideSegment(i, activity: true)),
        ];
        // Masked bands may hide part of it, never all of it.
        expect(stages.first.reason, anyOf('movement', 'strong_movement'));
        expect(stages.first.epoch.movementSeconds, 10);
        expect(stages.last.epoch.stage, SleepStageType.awake);
      }
    });

    test('a loud vehicle that leaks into every band is rumble', () {
      // 40 dB below 200 Hz, falling to 9 dB at 1.5-4 kHz: every band is up,
      // but practically none of the added energy is above 1.5 kHz.
      SleepMonitorSegment truck(int i) => SleepMonitorSegment.fromMap({
        ...bedsideSegment(i).toMap(),
        'noise_active_seconds': 18.0,
        'noise_score': 30.0,
        'audio_level_stddev_db': 11.0,
        'spectral_band_energy_0': 100000.0,
        'spectral_band_energy_1': 6000.0,
        'spectral_band_energy_2': 150.0,
        'spectral_band_energy_3': 8.0,
        'spectral_band_energy_4': 3.0,
      });
      final cursor = SleepWakeCursor(sessionId: 'bedside', startsAwake: true);
      for (var i = 0; i < 60; i++) {
        cursor.add(bedsideSegment(i));
      }
      for (var i = 60; i < 66; i++) {
        final decision = cursor.add(truck(i));
        expect(decision.reason, 'low_rumble');
        expect(decision.epoch.stage, SleepStageType.sleeping);
        expect(decision.epoch.movementSeconds, 0);
      }
    });

    test('a broadband rise without bursts is not a movement', () {
      // Rain: every band 12 dB up, nothing standing out of its own level.
      SleepMonitorSegment rain(int i) =>
          broadband(i, db: 12, seconds: 0.25, noise: 3);
      final cursor = SleepWakeCursor(sessionId: 'bedside', startsAwake: true);
      for (var i = 0; i < 60; i++) {
        cursor.add(bedsideSegment(i));
      }
      final reasons = <String>[];
      for (var i = 60; i < 180; i++) {
        final decision = cursor.add(rain(i));
        reasons.add(decision.reason);
        expect(decision.epoch.stage, SleepStageType.sleeping);
      }
      expect(reasons.first, 'sustained_sound');
      // Five minutes without a pause and the rain is the room's new floor.
      expect(
        reasons[SleepAudioEvidenceExtractor.recentFloorWindows],
        'quiet_audio',
      );
      expect(reasons.last, 'quiet_audio');
      // A movement is then judged against the rain, not the old silence.
      expect(cursor.add(broadband(180, db: 12 + 10)).reason, 'movement');
      expect(
        cursor.add(broadband(181, db: 12 + 3)).reason,
        'environmental_sound',
      );
    });

    test('a room sound with bursts in it is not hours awake', () {
      // Two hours of rain and wind in the middle of the night: every band
      // 12-18 dB up, changing from window to window, with gusts that stand
      // out of the level. Only its first minutes can pass for a person.
      final random = math.Random(7);
      SleepMonitorSegment storm(int i) => broadband(
        i,
        db: 15 + (random.nextDouble() - 0.5) * 6,
        seconds: 1.5 + random.nextDouble() * 4.5,
        noise: 8,
      );
      final segments = [
        for (var i = 0; i < 960; i++)
          i >= 300 && i < 540 ? storm(i) : bedsideSegment(i),
      ];
      for (final smooth in [true, false]) {
        final epochs = runNight(segments, smooth: smooth).epochs;
        final awake = epochs.skip(300).where((e) => !e.isSleep).length;
        expect(awake, lessThanOrEqualTo(16), reason: 'smooth $smooth');
        expect(epochs.skip(330).take(210).every((e) => e.isSleep), true);
      }
    });

    test('a sound that never pauses becomes the room', () {
      // A podcast next to the phone for the first 40 minutes at a constant
      // level. Nobody can tell from it when the listener fell asleep, so it
      // must not read as 40 minutes awake; a movement on top of it still
      // counts.
      final segments = [
        for (var i = 0; i < 80; i++) sustainedBedsideActivity(i),
        for (var i = 80; i < 600; i++) bedsideSegment(i),
      ];
      final result = runNight(segments);
      expect(result.epochs.first.stage, SleepStageType.awake);
      expect(
        result.decisionReasons[result.epochs[40].id],
        'environmental_sound',
      );
      expect(firstSleep(result.epochs), lessThan(40));
      final cursor = SleepWakeCursor(sessionId: 'bedside', startsAwake: true);
      for (var i = 0; i < 40; i++) {
        cursor.add(sustainedBedsideActivity(i));
      }
      final podcast = sustainedBedsideActivity(40).toMap();
      final onTop = SleepMonitorSegment.fromMap({
        ...podcast,
        for (var band = 0; band < 5; band++)
          'spectral_band_energy_$band':
              (podcast['spectral_band_energy_$band'] as num) * 20,
      });
      expect(cursor.add(onTop).reason, 'movement');
    });

    test('a person whose sound comes and goes stays awake', () {
      // Twenty minutes awake in the middle of the night, the way recorded
      // wake looks: levels all over the place and silent windows in between.
      // The five-minute floor must not turn that into the room.
      final random = math.Random(11);
      final segments = [
        for (var i = 0; i < 600; i++)
          i >= 300 && i < 340 && random.nextDouble() < 0.7
              ? broadband(
                  i,
                  db: 14 + random.nextDouble() * 18,
                  seconds: 4 + random.nextDouble() * 10,
                  noise: 20,
                )
              : bedsideSegment(i),
      ];
      for (final smooth in [true, false]) {
        final wake = runNight(
          segments,
          smooth: smooth,
        ).epochs.sublist(302, 340);
        expect(
          wake.where((e) => e.stage == SleepStageType.awake).length,
          greaterThan(wake.length * 0.9),
          reason: 'smooth $smooth',
        );
      }
    });

    test('talk at an even level is awake until it becomes the room', () {
      // The price of the five-minute floor: the first minutes are a person,
      // what never drops after that is not.
      final segments = [
        for (var i = 0; i < 600; i++)
          i >= 300 && i < 340
              ? broadband(i, db: 20, seconds: 15, noise: 20)
              : bedsideSegment(i),
      ];
      final result = runNight(segments);
      expect(
        result.epochs
            .sublist(300, 300 + SleepAudioEvidenceExtractor.recentFloorWindows)
            .every((e) => e.stage == SleepStageType.awake),
        true,
      );
      expect(
        result.decisionReasons[result.epochs[320].id],
        'environmental_sound',
      );
      expect(result.epochs[339].isSleep, true);
    });

    test('a window is judged over its own duration', () {
      // The session ends 3 s into the last window: its energy still belongs
      // to 30 s, not to the 3 s that get a label.
      final result = engine.run(
        session: SleepMonitorSession.fromMap({
          ...bedsideSession(minutes: 30).toMap(),
          'ended_at': bedsideStart
              .add(const Duration(minutes: 29, seconds: 33))
              .toIso8601String(),
        }),
        segments: [for (var i = 0; i < 60; i++) bedsideSegment(i)],
      );
      expect(result.epochs.last.durationSeconds, 3);
      expect(result.decisionReasons[result.epochs.last.id], 'quiet_audio');
      // The 3 s keep a tenth of the window's sound, not all of it.
      final cursor = SleepWakeCursor(sessionId: 'bedside');
      for (var i = 0; i < 10; i++) {
        cursor.add(bedsideSegment(i));
      }
      final clipped = cursor.add(
        bedsideSegment(10, activity: true),
        durationSeconds: 3,
      );
      expect(clipped.reason, 'strong_movement');
      expect(clipped.epoch.movementSeconds, closeTo(1, 1e-9));
    });

    test('bands without any signal are left out of the score', () {
      SleepMonitorSegment window(
        int i, {
        required int deadBands,
        double gain = 1,
      }) => SleepMonitorSegment.fromMap({
        ...bedsideSegment(i).toMap(),
        'noise_active_seconds': gain > 1 ? 5.0 : 0.0,
        'noise_score': gain > 1 ? 15.0 : 1.0,
        'audio_level_stddev_db': 6.0,
        for (var band = 0; band < 5; band++)
          'spectral_band_energy_$band': band >= 5 - deadBands
              ? 0.0
              : [10.0, 20.0, 5.0, 1.0, 1.0][band] * gain,
      });
      // One silent band: the other four still tell a movement from quiet.
      final one = SleepWakeCursor(sessionId: 'bedside');
      for (var i = 0; i < 20; i++) {
        expect(
          one.add(window(i, deadBands: 1)).reason,
          anyOf('calibrating', 'quiet_audio'),
        );
      }
      expect(
        one.add(window(20, deadBands: 1, gain: 100)).reason,
        'strong_movement',
      );
      // Two: too little left to say anything, and never "still".
      final two = SleepWakeCursor(sessionId: 'bedside');
      for (var i = 0; i < 20; i++) {
        two.add(window(i, deadBands: 2));
      }
      for (final gain in [1.0, 100.0]) {
        final decision = two.add(window(20, deadBands: 2, gain: gain));
        expect(decision.reason, 'silent_bands');
        expect(decision.likelihoods, isNull);
      }
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
      SleepWakeCursor quietCursor() {
        final cursor = SleepWakeCursor(sessionId: 'bedside');
        for (var i = 0; i < 10; i++) {
          cursor.add(bedsideSegment(i));
        }
        return cursor;
      }

      // One periodic window can be chance; snoring goes on.
      final once = quietCursor();
      expect(once.add(snore(10)).reason, 'environmental_sound');
      expect(once.add(snore(11)).reason, 'snoring');
      expect(once.add(bedsideSegment(12)).reason, 'quiet_audio');
      expect(once.add(snore(13)).reason, 'environmental_sound');
      // A periodic sound faster than breathing is something else.
      final fast = quietCursor();
      for (var i = 10; i < 13; i++) {
        expect(
          fast
              .add(
                SleepMonitorSegment.fromMap({
                  ...snore(i).toMap(),
                  'breathing_rate_hz': 0.6,
                }),
              )
              .reason,
          'environmental_sound',
        );
      }
      // Not loud, or not mostly below 600 Hz: not snoring.
      for (final change in <Map<String, Object?>>[
        {'noise_score': 9.0},
        {'spectral_band_energy_3': 300.0, 'spectral_band_energy_4': 300.0},
      ]) {
        final other = quietCursor();
        for (var i = 10; i < 13; i++) {
          expect(
            other
                .add(
                  SleepMonitorSegment.fromMap({...snore(i).toMap(), ...change}),
                )
                .reason,
            isNot('snoring'),
          );
        }
      }
      // A capture failure or a gap ends the run.
      final broken = quietCursor();
      broken.add(snore(10));
      broken.add(bedsideSegment(11, invalid: true));
      expect(broken.add(snore(12)).reason, 'environmental_sound');
      expect(broken.add(snore(30)).reason, 'environmental_sound');
      expect(broken.add(snore(31)).reason, 'snoring');
      // Loud snoring next to the phone reaches every band: one periodic
      // window is still a movement, a run of them is snoring.
      SleepMonitorSegment loudSnore(int i) =>
          bedsideSegment(i, periodic: true, activity: true);
      final loud = quietCursor();
      expect(loud.add(loudSnore(10)).reason, 'strong_movement');
      final second = loud.add(loudSnore(11));
      expect(second.reason, 'snoring');
      expect(second.epoch.movementSeconds, 0);
    });

    test('quiet wake is never less likely to move than sleep', () {
      // Otherwise every silent window would count against sleep and a long
      // quiet night would read as lying awake.
      const quiet = SleepAudioEvidenceExtractor.quietWakeScore;
      const sleep = SleepAudioEvidenceExtractor.sleepScore;
      const active = SleepAudioEvidenceExtractor.activeWakeScore;
      expect(quiet[0], lessThanOrEqualTo(sleep[0]));
      for (var bin = 2; bin < 4; bin++) {
        expect(quiet[bin], greaterThanOrEqualTo(sleep[bin]));
        expect(active[bin], greaterThan(quiet[bin]));
      }
      for (final group in [quiet, sleep, active]) {
        expect(group.fold<double>(0, (a, b) => a + b), closeTo(1, 1e-9));
      }
    });

    test(
      'invalid zero-sample fractions and near-total silence are rejected',
      () {
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
      },
    );
  });

  group('timing', () {
    test('a quiet night is estimable without audible breathing', () {
      final result = runNight([
        for (var i = 0; i < 960; i++) bedsideSegment(i),
      ]);
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

    test(
      'offline onset lands after the last activity, before live confirms',
      () {
        // Awake and moving on and off for the first ten minutes.
        final segments = [
          for (var i = 0; i < 120; i++)
            bedsideSegment(i, activity: i < 20 && i.isEven),
        ];
        final smoothed = firstSleep(runNight(segments).epochs);
        final causal = firstSleep(runNight(segments, smooth: false).epochs);
        expect(smoothed, greaterThanOrEqualTo(20));
        expect(smoothed, lessThan(causal));
      },
    );

    test(
      'a wake is dated to its first sustained sound, not its confirmation',
      () {
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
      },
    );

    test('falling back asleep is faster than the first sleep onset', () {
      // Moving on and off for five minutes, at bedtime and again later.
      final segments = [
        for (var i = 0; i < 400; i++)
          bedsideSegment(
            i,
            activity: (i < 10 || (i >= 200 && i < 210)) && i.isEven,
          ),
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
          // The first movement comes well after falling asleep; earlier it
          // would be part of settling down.
          bedsideSegment(
            i,
            periodic: i % 3 == 0,
            activity: i > 60 && i % 10 == 9,
          ),
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
          i >= 200 && i < 260 && i % 4 == 0 ? brief(i, 3) : bedsideSegment(i),
      ]);
      final summary = const SleepStageAnalysisService().summarize(
        sessionStart: bedsideStart,
        sessionEnd: bedsideSession(minutes: 240).endedAt!,
        epochs: result.epochs,
      )!;
      expect(result.epochs.skip(200).take(60).every((e) => e.isSleep), true);
      expect(summary.restlessSleepMinutes, inInclusiveRange(20, 30));
    });
  });

  group('capture', () {
    test('invalid capture is unknown without erasing the night', () {
      final result = runNight([
        for (var i = 0; i < 120; i++) bedsideSegment(i, invalid: i == 80),
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
      expect(result.epochs.fold<int>(0, (s, e) => s + e.durationSeconds), 3600);
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

    test(
      'duplicates, overlapping windows and input order do not double count',
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
        expect(result.epochs.where((e) => e.isSleep), isEmpty);
        expect(result.epochs.last.stage, SleepStageType.unknown);
      },
    );

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
          (e) =>
              (e.awakeProbability! + e.sleepingProbability! - 1).abs() < 1e-9,
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
      expect(
        cursor.add(bedsideSegment(66)).epoch.stage,
        SleepStageType.sleeping,
      );
    });

    test('a live gap lets the model drift instead of resetting', () {
      final cursor = SleepWakeCursor(sessionId: 'bedside', startsAwake: true);
      for (var i = 0; i < 60; i++) {
        cursor.add(bedsideSegment(i));
      }
      // Ten minutes of windows never arrived.
      expect(
        cursor.add(bedsideSegment(80)).epoch.stage,
        SleepStageType.sleeping,
      );
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
      // The only long wake on record: a noisy first hour and a bit.
      final onset = firstSleep(result.epochs);
      expect(onset, inInclusiveRange(130, 160));
      expect(
        result.epochs.take(onset).every((e) => e.stage == SleepStageType.awake),
        true,
      );
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
      // Loud activity around the fan being switched off (local 05:00-05:07)
      // and again at 06:31-06:38 wakes.
      expect(
        span(131, 136).every((e) => e.stage == SleepStageType.awake),
        true,
      );
      expect(
        span(222, 227).every((e) => e.stage == SleepStageType.awake),
        true,
      );
      expect(summary.awakeMinutes, inInclusiveRange(20, 60));
      expect(summary.awakeningCount, greaterThanOrEqualTo(2));
      expect(summary.restlessSleepMinutes, lessThan(summary.sleepingMinutes));
    });

    test('morning night: birds and traffic for hours are not time awake', () {
      // 02:39-09:00 local, audio-features-v5. Quiet until 03:54,
      // then a dawn chorus, then traffic and birds until the alarm. The v6
      // engine counted that sound as the person's and reported 3 h 18 min of
      // sleep. The phone was picked up at 07:51.
      final segments = quantizedBedsideSegments(
        fileName: 'sleep_morning_bedside.json',
      );
      final start = bedsideStart.add(const Duration(milliseconds: 288));
      final session = SleepMonitorSession.fromMap({
        ...bedsideSession().toMap(),
        'started_at': start.toIso8601String(),
        'ended_at': start
            .add(const Duration(seconds: 22840, milliseconds: 861))
            .toIso8601String(),
        'algorithm_version': 'audio-features-v5',
        'time_in_bed_minutes': 381,
        'end_reason': 'alarm',
      });
      final result = engine.run(session: session, segments: segments);
      final summary = const SleepStageAnalysisService().summarize(
        sessionStart: session.startedAt,
        sessionEnd: session.endedAt!,
        epochs: result.epochs,
      )!;
      List<SleepStageEpoch> span(int from, int to) =>
          result.epochs.sublist(from * 2, to * 2);
      int count(List<SleepStageEpoch> epochs, String reason) =>
          epochs.where((e) => result.decisionReasons[e.id] == reason).length;

      expect(result.epochs.first.stage, SleepStageType.awake);
      expect(summary.unknownMinutes, 0);
      expect(summary.sleepLatencyMinutes, inInclusiveRange(5, 20));
      expect(summary.sleepingMinutes, inInclusiveRange(350, 372));
      expect(summary.awakeMinutes, inInclusiveRange(9, 30));
      // 03:54-07:49: nearly four hours of birds and traffic. Nothing says
      // the night had no short awakening in there, only that it was not
      // hours of them.
      final morning = span(75, 310);
      expect(
        morning.where((e) => e.isSleep).length,
        greaterThan(morning.length * 0.95),
      );
      var longestAwake = 0;
      var run = 0;
      for (final epoch in morning) {
        run = epoch.isSleep ? 0 : run + 1;
        longestAwake = math.max(longestAwake, run);
      }
      expect(longestAwake, lessThanOrEqualTo(10));
      expect(
        count(morning, 'environmental_sound'),
        greaterThan(morning.length * 0.6),
      );
      // The trucks loud enough to leak into every band are still the street.
      expect(count(morning, 'low_rumble'), greaterThanOrEqualTo(1));
      // Picking the phone up is a real awakening.
      final handling = span(312, 315);
      expect(handling.every((e) => e.stage == SleepStageType.awake), true);
      expect(count(handling, 'strong_movement'), greaterThanOrEqualTo(2));
      expect(summary.awakeningCount, inInclusiveRange(1, 3));
      expect(summary.restlessSleepMinutes, lessThan(30));
      expect(summary.finalWakeAt, isNull);
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
