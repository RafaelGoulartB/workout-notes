import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/models/run_session_goal.dart';
import 'package:workout_notes/models/run_tracking_state.dart';
import 'package:workout_notes/models/run_voice_settings.dart';
import 'package:workout_notes/services/run_native_voice_service.dart';
import 'package:workout_notes/services/run_session_coach.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('workout_notes/run_voice/methods');
  late List<MethodCall> calls;
  late Object? Function(MethodCall call) reply;

  setUp(() {
    calls = [];
    reply = (_) => null;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return reply(call);
        });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  RunPlanWorkout continuousPlan() => RunPlanWorkout(
    id: 'easy-2.8k',
    runPlanId: 'p1',
    weekIndex: 0,
    orderIndex: 0,
    kind: RunWorkoutKind.easy,
    name: 'Easy run',
    targetDistanceMeters: 2800,
    createdAt: DateTime(2026, 1, 1),
  );

  RunTrackingState recording({
    required double distanceMeters,
    required int movingTimeSeconds,
  }) => RunTrackingState.fromMap({
    'status': RunTrackingState.recording,
    'distance_meters': distanceMeters,
    'moving_time_seconds': movingTimeSeconds,
    'duration_seconds': movingTimeSeconds,
  });

  test(
    'begin hands settings, goal and plan to the native controller',
    () async {
      final previousLocale = Intl.defaultLocale;
      Intl.defaultLocale = 'pt_BR';
      addTearDown(() => Intl.defaultLocale = previousLocale);
      final coach = RunSessionCoach();

      await coach.beginSession(
        intervalsOn: true,
        goal: const RunSessionGoal(
          enabled: true,
          metric: RunIntervalMetric.distance,
          value: 5000,
        ),
        planWorkout: continuousPlan(),
      );

      final begin = calls.singleWhere((call) => call.method == 'beginSession');
      final args = Map<String, dynamic>.from(begin.arguments as Map);
      expect((args['settings'] as Map)['resolvedLanguage'], 'pt');
      expect((args['goal'] as Map)['value'], 5000);
      // A structured plan replaces the quick interval preset.
      expect(args['intervalsOn'], isFalse);
      expect(args['plan'], hasLength(1));
      expect(coach.hasPlan, isTrue);
      expect(coach.isActive, isTrue);
    },
  );

  test('a session without native tracking never touches the channel', () async {
    final coach = RunSessionCoach();
    await coach.beginSession(intervalsOn: false, nativeVoice: false);
    expect(calls.where((call) => call.method == 'beginSession'), isEmpty);
    expect(coach.isActive, isTrue);
  });

  test('latches goal completion once the target is reached', () async {
    final coach = RunSessionCoach();
    await coach.beginSession(
      intervalsOn: false,
      goal: const RunSessionGoal(
        enabled: true,
        metric: RunIntervalMetric.distance,
        value: 1000,
      ),
    );

    coach.onTrackingUpdate(
      recording(distanceMeters: 600, movingTimeSeconds: 200),
    );
    expect(
      coach
          .goalSnapshotFor(
            recording(distanceMeters: 600, movingTimeSeconds: 200),
          )
          .completed,
      isFalse,
    );

    final finished = recording(distanceMeters: 1000, movingTimeSeconds: 330);
    coach.onTrackingUpdate(finished);
    expect(coach.goalSnapshotFor(finished).completed, isTrue);

    // Stays latched even if the distance dips (GPS noise).
    final dipped = recording(distanceMeters: 990, movingTimeSeconds: 335);
    coach.onTrackingUpdate(dipped);
    expect(coach.goalSnapshotFor(dipped).completed, isTrue);
  });

  test('skip step is forwarded only while a session is active', () async {
    final coach = RunSessionCoach();
    await coach.skipStep();
    expect(calls.where((call) => call.method == 'skipStep'), isEmpty);

    await coach.beginSession(intervalsOn: true);
    await coach.skipStep();
    expect(calls.where((call) => call.method == 'skipStep'), hasLength(1));
  });

  test('step results come back typed from the native rows', () async {
    reply = (call) => call.method == 'stepResults'
        ? [
            {
              'sequence': 0,
              'role': 'warmup',
              'repIndex': 1,
              'plannedMetric': 'distance',
              'plannedValue': 1000,
              'distanceMeters': 400.0,
              'durationSeconds': 120,
            },
          ]
        : null;
    final coach = RunSessionCoach();

    final results = await coach.collectStepResults();

    expect(results.single.plannedValue, 1000);
    expect(results.single.distanceMeters, 400);
  });

  test('the completion cue is skipped for planned sessions', () async {
    final coach = RunSessionCoach();
    await coach.beginSession(intervalsOn: false, planWorkout: continuousPlan());
    await coach.announceManualCompletion();
    expect(
      calls.where((call) => call.method == 'speakWorkoutComplete'),
      isEmpty,
    );

    final free = RunSessionCoach();
    await free.beginSession(intervalsOn: false);
    await free.announceManualCompletion();
    expect(
      calls.where((call) => call.method == 'speakWorkoutComplete'),
      hasLength(1),
    );
  });

  test('the settings test announcement uses the resolved language', () async {
    reply = (call) => true;
    final ok = await RunNativeVoiceService.instance.speakTest(
      const RunVoiceSettings.defaults().copyWith(
        language: RunVoiceLanguage.portuguese,
      ),
    );

    expect(ok, isTrue);
    final call = calls.singleWhere((c) => c.method == 'speakTest');
    expect(
      ((call.arguments as Map)['settings'] as Map)['resolvedLanguage'],
      'pt',
    );
  });
}
