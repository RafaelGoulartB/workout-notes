import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/models/run_session_goal.dart';
import 'package:workout_notes/models/run_split.dart';
import 'package:workout_notes/models/run_tracking_state.dart';
import 'package:workout_notes/models/run_voice_settings.dart';
import 'package:workout_notes/services/run_audio_gate_service.dart';
import 'package:workout_notes/services/run_voice_coach.dart';
import 'package:workout_notes/services/run_voice_phrases.dart';

void main() {
  group('RunVoicePhrases', () {
    test('distance milestone includes pace when present', () {
      final text = RunVoicePhrases.distanceMilestone(
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
        RunVoicePhrases.splitComplete(km: 3, paceSecPerKm: 348),
        startsWith('Kilometer 3'),
      );
      expect(
        RunVoicePhrases.workIntervalStart(index: 1, total: 8),
        'Rep 1 of 8. Go.',
      );
      expect(
        RunVoicePhrases.restIntervalStart(
          metric: RunIntervalMetric.time,
          value: 90,
        ),
        contains('Recover.'),
      );
    });
  });

  group('RunVoiceSettings JSON', () {
    test('round-trips defaults', () {
      const original = RunVoiceSettings.defaults();
      final restored = RunVoiceSettings.fromJson(original.toJson());
      expect(restored.enabled, original.enabled);
      expect(restored.headphonesOnly, true);
      expect(restored.distanceEveryKm, 1);
      expect(restored.interval.workValue, 400);
      expect(restored.interval.repeats, 8);
    });

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
          'Steady. 2.8 kilometers. Target 6 00 per kilometer.',
        );

        await coach.onTrackingUpdate(
          _recordingState(
            distanceMeters: 2700,
            durationSeconds: 972,
            movingTimeSeconds: 972,
          ),
        );
        expect(spoken.last, '100 meters.');

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
}

RunTrackingState _recordingState({
  required double distanceMeters,
  required int durationSeconds,
  required int movingTimeSeconds,
  List<RunSplit> splits = const [],
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
  );
}
