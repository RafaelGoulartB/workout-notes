import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/models/run_lap.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/models/run_session_goal.dart';
import 'package:workout_notes/models/run_split.dart';
import 'package:workout_notes/models/run_tracking_state.dart';
import 'package:workout_notes/models/run_voice_settings.dart';
import 'package:workout_notes/models/run_workout_step.dart';
import 'package:workout_notes/services/run_audio_gate_service.dart';
import 'package:workout_notes/services/run_voice_coach.dart';
import 'package:workout_notes/services/run_voice_phrases.dart';

void main() {
  group('RunVoicePhrases', () {
    const english = RunVoicePhrases(RunVoiceLanguage.english);
    const portuguese = RunVoicePhrases(RunVoiceLanguage.portuguese);

    test('distance milestone includes pace when present', () {
      final text = english.distanceMilestone(
        km: 2,
        durationSeconds: 724,
        avgPaceSecPerKm: 362,
      );
      expect(text, contains('2 kilometers'));
      expect(text, contains('Average'));
      expect(text.length, lessThan(70));
    });

    test('split and interval phrases are English', () {
      expect(
        english.splitComplete(km: 3, paceSecPerKm: 348),
        startsWith('Kilometer 3'),
      );
      expect(english.workIntervalStart(index: 1, total: 8), 'Rep 1 of 8. Go.');
      expect(
        english.restIntervalStart(metric: RunIntervalMetric.time, value: 90),
        contains('Recover.'),
      );
    });

    test('Portuguese phrases use natural running vocabulary', () {
      expect(
        portuguese.splitComplete(km: 3, paceSecPerKm: 348),
        'Quilômetro 3. Pace 5 minutos e 48 segundos por quilômetro.',
      );
      expect(
        portuguese.workIntervalStart(index: 2, total: 6),
        'Tiro 2 de 6. Vai!',
      );
      expect(
        portuguese.restIntervalStart(metric: RunIntervalMetric.time, value: 90),
        'Recuperação. 1 minuto e 30 segundos.',
      );
      expect(portuguese.paceOnTarget(), 'Pace dentro da meta.');
    });
  });

  group('RunVoiceSettings JSON', () {
    test('round-trips defaults', () {
      const original = RunVoiceSettings.defaults();
      final restored = RunVoiceSettings.fromJson(original.toJson());
      expect(restored.enabled, original.enabled);
      expect(restored.language, RunVoiceLanguage.app);
      expect(restored.headphonesOnly, true);
      expect(restored.distanceEveryKm, 1);
      expect(restored.interval.workValue, 400);
      expect(restored.interval.repeats, 8);
    });

    test('round-trips an explicit Portuguese voice language', () {
      final original = const RunVoiceSettings.defaults().copyWith(
        language: RunVoiceLanguage.portuguese,
      );
      final restored = RunVoiceSettings.fromJson(original.toJson());
      expect(restored.language, RunVoiceLanguage.portuguese);
    });

    test(
      'app default follows locale while an explicit language overrides it',
      () {
        expect(
          RunVoiceLanguage.app.resolve('pt_BR'),
          RunVoiceLanguage.portuguese,
        );
        expect(
          RunVoiceLanguage.english.resolve('pt_BR'),
          RunVoiceLanguage.english,
        );
        expect(
          RunVoiceLanguage.portuguese.resolve('en_US'),
          RunVoiceLanguage.portuguese,
        );
      },
    );

    test('clamps distance frequency', () {
      final restored = RunVoiceSettings.fromJson({'distanceEveryKm': 7});
      expect(restored.distanceEveryKm, 1);
    });
  });

  group('RunVoiceCoach free-run events', () {
    test(
      'announces and completes a continuous 2.8 km plan even when quick intervals are muted',
      () async {
        final spoken = <String>[];
        final coach = RunVoiceCoach(
          speak: (text) async => spoken.add(text),
          audioCaps: () async =>
              const RunAudioCapabilities(headsetConnected: true, inCall: false),
          ensureTtsReady: () async {},
          stopTts: () async {},
        );
        coach.settingsOverride = const RunVoiceSettings.defaults().copyWith(
          headphonesOnly: false,
          announceGpsStatus: false,
          announceIntervals: false,
          announceDistance: false,
          announceSplit: false,
        );
        await coach.beginSession(
          intervalsOn: false,
          planWorkout: RunPlanWorkout(
            id: 'easy-2.8k',
            runPlanId: 'p1',
            weekIndex: 0,
            orderIndex: 0,
            kind: RunWorkoutKind.easy,
            name: 'Easy run',
            targetDistanceMeters: 2800,
            targetPaceSecPerKm: 360,
            createdAt: DateTime(2026, 1, 1),
          ),
        );

        await coach.onTrackingUpdate(
          _recordingState(
            distanceMeters: 0,
            durationSeconds: 0,
            movingTimeSeconds: 0,
          ),
        );
        expect(
          spoken.single,
          'Steady. 2 kilometers and 800 meters. Target pace 6 minutes per kilometer.',
        );

        await coach.onTrackingUpdate(
          _recordingState(
            distanceMeters: 2700,
            durationSeconds: 972,
            movingTimeSeconds: 972,
          ),
        );
        expect(spoken.last, '100 meters left.');

        await coach.onTrackingUpdate(
          _recordingState(
            distanceMeters: 2800,
            durationSeconds: 1008,
            movingTimeSeconds: 1008,
          ),
        );
        expect(spoken.last, 'Workout complete.');
      },
    );

    test('follows the Portuguese app locale by default', () async {
      final previousLocale = Intl.defaultLocale;
      Intl.defaultLocale = 'pt_BR';
      addTearDown(() => Intl.defaultLocale = previousLocale);
      final spoken = <String>[];
      final coach = RunVoiceCoach(
        speak: (text) async => spoken.add(text),
        audioCaps: () async =>
            const RunAudioCapabilities(headsetConnected: true, inCall: false),
        ensureTtsReady: () async {},
        stopTts: () async {},
      );
      coach.settingsOverride = const RunVoiceSettings.defaults().copyWith(
        headphonesOnly: false,
        announceGpsStatus: false,
      );
      await coach.beginSession(intervalsOn: false);

      await coach.onTrackingUpdate(
        _recordingState(
          distanceMeters: 1000,
          durationSeconds: 360,
          movingTimeSeconds: 360,
          splits: [
            const RunSplit(
              km: 1,
              distanceMeters: 1000,
              durationSeconds: 360,
              paceSecPerKm: 360,
              isPartial: false,
            ),
          ],
        ),
      );

      expect(spoken.single, startsWith('Quilômetro 1. Pace 6 minutos'));
      expect(spoken.single, contains('Pace médio'));
    });

    test('announces distance and split with open gate', () async {
      final spoken = <String>[];
      final coach = RunVoiceCoach(
        speak: (text) async => spoken.add(text),
        audioCaps: () async =>
            const RunAudioCapabilities(headsetConnected: true, inCall: false),
        ensureTtsReady: () async {},
        stopTts: () async {},
      );
      coach.settingsOverride = const RunVoiceSettings.defaults().copyWith(
        headphonesOnly: false,
        announceGpsStatus: false,
      );
      await coach.beginSession(intervalsOn: false);

      await coach.onTrackingUpdate(
        _recordingState(
          distanceMeters: 1000,
          durationSeconds: 360,
          movingTimeSeconds: 360,
          splits: [
            const RunSplit(
              km: 1,
              distanceMeters: 1000,
              durationSeconds: 360,
              paceSecPerKm: 360,
              isPartial: false,
            ),
          ],
        ),
      );

      expect(spoken, isNotEmpty);
      expect(spoken.any((s) => s.toLowerCase().contains('kilometer')), isTrue);
      expect(spoken, hasLength(1));
      expect(spoken.single, contains('Average'));
    });

    test('skips speech when headphones required but missing', () async {
      final spoken = <String>[];
      final coach = RunVoiceCoach(
        speak: (text) async => spoken.add(text),
        audioCaps: () async =>
            const RunAudioCapabilities(headsetConnected: false, inCall: false),
        ensureTtsReady: () async {},
        stopTts: () async {},
      );
      coach.settingsOverride = const RunVoiceSettings.defaults().copyWith(
        headphonesOnly: true,
        announceGpsStatus: false,
      );
      await coach.beginSession(intervalsOn: false);
      await coach.onTrackingUpdate(
        _recordingState(
          distanceMeters: 1000,
          durationSeconds: 300,
          movingTimeSeconds: 300,
        ),
      );
      expect(spoken, isEmpty);
    });

    test('skips speech during call when mute enabled', () async {
      final spoken = <String>[];
      final coach = RunVoiceCoach(
        speak: (text) async => spoken.add(text),
        audioCaps: () async =>
            const RunAudioCapabilities(headsetConnected: true, inCall: true),
        ensureTtsReady: () async {},
        stopTts: () async {},
      );
      coach.settingsOverride = const RunVoiceSettings.defaults().copyWith(
        headphonesOnly: false,
        muteDuringCall: true,
        announceGpsStatus: false,
      );
      await coach.beginSession(intervalsOn: false);
      await coach.onTrackingUpdate(
        _recordingState(
          distanceMeters: 1000,
          durationSeconds: 300,
          movingTimeSeconds: 300,
        ),
      );
      expect(spoken, isEmpty);
    });

    test(
      'goal completion preempts other announcements in the same tick',
      () async {
        final spoken = <String>[];
        final coach = RunVoiceCoach(
          speak: (text) async => spoken.add(text),
          audioCaps: () async =>
              const RunAudioCapabilities(headsetConnected: true, inCall: false),
          ensureTtsReady: () async {},
          stopTts: () async {},
        );
        coach.settingsOverride = const RunVoiceSettings.defaults().copyWith(
          headphonesOnly: false,
          announceGpsStatus: false,
          announceDistance: true,
          announceSplit: true,
        );
        await coach.beginSession(
          intervalsOn: false,
          goal: const RunSessionGoal(
            enabled: true,
            metric: RunIntervalMetric.distance,
            value: 1000,
          ),
        );
        await coach.onTrackingUpdate(
          _recordingState(
            distanceMeters: 1000,
            durationSeconds: 360,
            movingTimeSeconds: 360,
            splits: [
              const RunSplit(
                km: 1,
                distanceMeters: 1000,
                durationSeconds: 360,
                paceSecPerKm: 360,
                isPartial: false,
              ),
            ],
          ),
        );
        expect(spoken, hasLength(1));
        expect(spoken.single, startsWith('Goal complete'));
      },
    );
  });

  group('RunVoiceCoach auto-pause, laps, skip and pace goal', () {
    RunVoiceCoach coachWith(List<String> spoken, {RunVoiceSettings? settings}) {
      final coach = RunVoiceCoach(
        speak: (text) async => spoken.add(text),
        audioCaps: () async =>
            const RunAudioCapabilities(headsetConnected: true, inCall: false),
        ensureTtsReady: () async {},
        stopTts: () async {},
      );
      coach.settingsOverride =
          settings ??
          const RunVoiceSettings.defaults().copyWith(
            headphonesOnly: false,
            announceGpsStatus: false,
            announceDistance: false,
            announceSplit: false,
          );
      return coach;
    }

    test('announces auto-pause and resume once each', () async {
      final spoken = <String>[];
      final coach = coachWith(spoken);
      await coach.beginSession(intervalsOn: false);
      await coach.onTrackingUpdate(
        _recordingState(
          distanceMeters: 500,
          durationSeconds: 200,
          movingTimeSeconds: 200,
        ),
      );
      expect(spoken, isEmpty);

      await coach.onTrackingUpdate(
        _recordingState(
          distanceMeters: 500,
          durationSeconds: 210,
          movingTimeSeconds: 200,
          autoPaused: true,
        ),
      );
      expect(spoken, ['Auto paused.']);

      // Still standing: no repeated cue.
      await coach.onTrackingUpdate(
        _recordingState(
          distanceMeters: 500,
          durationSeconds: 215,
          movingTimeSeconds: 200,
          autoPaused: true,
        ),
      );
      expect(spoken, hasLength(1));

      await coach.onTrackingUpdate(
        _recordingState(
          distanceMeters: 510,
          durationSeconds: 220,
          movingTimeSeconds: 205,
        ),
      );
      expect(spoken.last, 'Resuming.');
    });

    test('auto-pause cues can be switched off', () async {
      final spoken = <String>[];
      final coach = coachWith(
        spoken,
        settings: const RunVoiceSettings.defaults().copyWith(
          headphonesOnly: false,
          announceGpsStatus: false,
          announceAutoPause: false,
        ),
      );
      await coach.beginSession(intervalsOn: false);
      await coach.onTrackingUpdate(
        _recordingState(
          distanceMeters: 500,
          durationSeconds: 200,
          movingTimeSeconds: 200,
        ),
      );
      await coach.onTrackingUpdate(
        _recordingState(
          distanceMeters: 500,
          durationSeconds: 210,
          movingTimeSeconds: 200,
          autoPaused: true,
        ),
      );
      expect(spoken, isEmpty);
    });

    test('speaks a lap summary through the Dart path', () async {
      final spoken = <String>[];
      final coach = coachWith(spoken);
      await coach.beginSession(intervalsOn: false);
      await coach.announceLap(
        const RunLap(
          index: 2,
          startDistanceMeters: 1000,
          distanceMeters: 1200,
          durationSeconds: 372,
          paceSecPerKm: 310,
        ),
      );
      expect(spoken.single, startsWith('Lap 2.'));
      expect(spoken.single, contains('1 kilometer and 200 meters'));
      expect(
        spoken.single,
        contains('Pace 5 minutes 10 seconds per kilometer'),
      );
    });

    test('lap summaries respect the announceLaps setting', () async {
      final spoken = <String>[];
      final coach = coachWith(
        spoken,
        settings: const RunVoiceSettings.defaults().copyWith(
          headphonesOnly: false,
          announceLaps: false,
        ),
      );
      await coach.beginSession(intervalsOn: false);
      await coach.announceLap(
        const RunLap(
          index: 1,
          startDistanceMeters: 0,
          distanceMeters: 500,
          durationSeconds: 150,
          paceSecPerKm: 300,
        ),
      );
      expect(spoken, isEmpty);
    });

    test(
      'a session pace goal overrides the global target and tolerance',
      () async {
        final coach = coachWith(<String>[]);
        await coach.beginSession(intervalsOn: false);
        // Global warnings are off and there is no target.
        expect(coach.effectivePaceTargetSecPerKm, isNull);

        coach.setGoal(
          const RunSessionGoal.defaults().copyWith(
            paceTargetSecPerKm: 330,
            paceTolerancePercent: 3,
          ),
        );
        expect(coach.effectivePaceTargetSecPerKm, 330);
        expect(coach.effectivePaceTolerancePercent, 3);

        // Without a pace goal the global setting applies again.
        coach.setGoal(const RunSessionGoal.defaults());
        coach.settingsOverride = const RunVoiceSettings.defaults().copyWith(
          announcePaceWarning: true,
          targetPaceSecPerKm: 360,
          paceTolerancePercent: 15,
          headphonesOnly: false,
        );
        await coach.reloadSettings();
        expect(coach.effectivePaceTargetSecPerKm, 360);
        expect(coach.effectivePaceTolerancePercent, 15);
      },
    );

    test(
      'skipping a step announces the next one and keeps the result',
      () async {
        final spoken = <String>[];
        final coach = coachWith(spoken);
        final session = RunPlanWorkout(
          id: 'w1',
          runPlanId: 'p1',
          weekIndex: 0,
          orderIndex: 0,
          kind: RunWorkoutKind.interval,
          name: 'Tiros',
          createdAt: DateTime(2026, 1, 1),
          steps: [
            RunWorkoutStep(
              id: 's0',
              runPlanWorkoutId: 'w1',
              orderIndex: 0,
              role: RunStepRole.warmup,
              metric: RunIntervalMetric.distance,
              value: 1000,
            ),
            RunWorkoutStep(
              id: 's1',
              runPlanWorkoutId: 'w1',
              orderIndex: 1,
              role: RunStepRole.cooldown,
              metric: RunIntervalMetric.time,
              value: 300,
            ),
          ],
        );
        await coach.beginSession(intervalsOn: false, planWorkout: session);
        await coach.onTrackingUpdate(
          _recordingState(
            distanceMeters: 0,
            durationSeconds: 0,
            movingTimeSeconds: 0,
          ),
        );
        expect(spoken.single, startsWith('Warm up.'));
        expect(coach.stepSnapshot.nextRole, RunStepRole.cooldown);

        await coach.onTrackingUpdate(
          _recordingState(
            distanceMeters: 400,
            durationSeconds: 120,
            movingTimeSeconds: 120,
          ),
        );
        await coach.skipStep();
        expect(spoken.last, startsWith('Cool down.'));
        expect(coach.stepSnapshot.role, RunStepRole.cooldown);
        expect(coach.stepSnapshot.hasNext, isFalse);
        expect((await coach.collectStepResults()).single.distanceMeters, 400);
      },
    );

    test('skipping the quick interval set moves to the next phase', () async {
      final spoken = <String>[];
      final coach = coachWith(spoken);
      await coach.beginSession(intervalsOn: true);
      await coach.onTrackingUpdate(
        _recordingState(
          distanceMeters: 0,
          durationSeconds: 0,
          movingTimeSeconds: 0,
        ),
      );
      expect(spoken.single, 'Rep 1 of 8. Go.');
      await coach.skipStep();
      expect(spoken.last, startsWith('Recover.'));
      expect(coach.intervalSnapshot.phase.name, 'rest');
    });
  });
}

RunTrackingState _recordingState({
  required double distanceMeters,
  required int durationSeconds,
  required int movingTimeSeconds,
  List<RunSplit> splits = const [],
  bool autoPaused = false,
}) {
  return RunTrackingState(
    supported: true,
    locationGranted: true,
    status: RunTrackingState.recording,
    activityId: 'test',
    startedAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1, 0, 10),
    distanceMeters: distanceMeters,
    durationSeconds: durationSeconds,
    movingTimeSeconds: movingTimeSeconds,
    currentPaceSecPerKm: distanceMeters > 0
        ? movingTimeSeconds / (distanceMeters / 1000.0)
        : null,
    lat: -23.5,
    lng: -46.6,
    accuracyMeters: 8,
    trail: const [],
    splits: splits,
    currentSplit: null,
    errorCode: null,
    errorMessage: null,
    autoPaused: autoPaused,
  );
}
