import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/database/database_schema.dart';
import 'package:workout_notes/models/cardio_activity_type.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/models/run_review_draft.dart';
import 'package:workout_notes/models/run_voice_settings.dart';
import 'package:workout_notes/models/run_workout_step.dart';
import 'package:workout_notes/repositories/run_repository.dart';
import 'package:workout_notes/services/indoor_tracking_service.dart';
import 'package:workout_notes/services/run_native_voice_service.dart';
import 'package:workout_notes/services/run_tracking_service.dart';

import 'support/test_db.dart';

Map<String, dynamic> _treadmillSpool({
  String id = 'treadmill-1',
  int seconds = 1800,
  double distance = 0,
}) => {
  'activity': {
    'id': id,
    'activity_type': 'treadmill',
    'status': 'pending_review',
    'started_at': '2026-09-01T07:00:00.000Z',
    'ended_at': '2026-09-01T07:30:00.000Z',
    'duration_seconds': seconds,
    'moving_time_seconds': seconds,
    'distance_meters': distance,
  },
  'points': <Map<String, dynamic>>[],
};

void main() {
  late Database database;

  setUpAll(initSqfliteFfiForTests);

  setUp(() async {
    database = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 53,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: DatabaseSchema.onCreate,
      ),
    );
    DatabaseHelper.overrideDatabase = database;
  });

  tearDown(() async {
    await IndoorTrackingService.instance.discard();
    DatabaseHelper.overrideDatabase = null;
    await database.close();
  });

  group('indoor timer service', () {
    test('times a treadmill session without GPS', () async {
      final service = IndoorTrackingService.instance;
      expect(await service.start(type: CardioActivityType.treadmill), isTrue);
      expect(service.activityType, CardioActivityType.treadmill);
      expect(service.isActive, isTrue);
      expect(service.state.locationGranted, isFalse);

      await service.pause();
      expect(service.state.isPaused, isTrue);
      await service.resume();
      expect(service.state.isRecording, isTrue);

      final draft = await service.stopForReview();
      expect(draft, isNotNull);
      expect(draft!.activity.activityType, CardioActivityType.treadmill);
      final spool = draft.spool['activity'] as Map;
      expect(spool['activity_type'], 'treadmill');
      expect(spool['distance_meters'], 0.0);
      expect(draft.activity.activityType.isIndoor, isTrue);
      expect(service.isActive, isFalse);
    });

    test('a bike session is still a bike session', () async {
      final service = IndoorTrackingService.instance;
      await service.start();
      final draft = await service.stopForReview();
      expect(draft!.activity.activityType, CardioActivityType.stationaryBike);
    });
  });

  group('treadmill import and review', () {
    final repository = RunRepository();

    test(
      'without a distance the calories come from a MET-by-time estimate',
      () {
        final activity = repository.previewNativeSpool(_treadmillSpool());
        expect(activity.activityType, CardioActivityType.treadmill);
        expect(activity.avgPaceSecPerKm, isNull);
        // 30 min at ~9 MET for 70 kg is in the 300 kcal range.
        expect(activity.calories, inInclusiveRange(250, 400));
      },
    );

    test('a known distance gives a pace and a distance-based estimate', () {
      final activity = repository.previewNativeSpool(
        _treadmillSpool(distance: 5000),
      );
      expect(activity.avgPaceSecPerKm, closeTo(360, 0.01));
      expect(activity.calories, 350);
    });

    test(
      'typing the distance on review recalculates pace and calories',
      () async {
        // Not Android: the native spool channel does not exist in tests.
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final spool = _treadmillSpool();
        final draft = RunReviewDraft.fromSpool(
          activity: repository.previewNativeSpool(spool),
          spool: spool,
        );

        final saved = await RunTrackingService.instance.saveReviewedRun(
          draft: draft,
          completePlannedWorkout: false,
          distanceMeters: 5400,
        );

        expect(saved, isNotNull);
        expect(saved!.activityType, CardioActivityType.treadmill);
        expect(saved.distanceMeters, 5400);
        expect(saved.avgPaceSecPerKm, closeTo(1800 / 5.4, 0.01));
        expect(saved.calories, 378);
        // Counts as a run (plans, volume) but not as a GPS route.
        expect(saved.isRunning, isTrue);
        expect(saved.isRun, isFalse);
        final running = await repository.listActivities(
          activityTypes: RunRepository.runningTypes,
        );
        expect(running.map((a) => a.id), ['treadmill-1']);
      },
    );
  });

  group('treadmill voice coach', () {
    RunPlanWorkout intervals() => RunPlanWorkout(
      id: 'w1',
      runPlanId: 'p1',
      weekIndex: 0,
      orderIndex: 0,
      kind: RunWorkoutKind.interval,
      name: '6x400',
      targetPaceSecPerKm: 240,
      createdAt: DateTime(2026),
      steps: const [
        RunWorkoutStep(
          id: 's1',
          runPlanWorkoutId: 'w1',
          orderIndex: 0,
          role: RunStepRole.warmup,
          metric: RunIntervalMetric.time,
          value: 600,
        ),
        RunWorkoutStep(
          id: 's2',
          runPlanWorkoutId: 'w1',
          orderIndex: 1,
          role: RunStepRole.work,
          metric: RunIntervalMetric.distance,
          value: 400,
          repeatGroup: 1,
          repeatCount: 6,
          targetPaceMinSecPerKm: 230,
          targetPaceMaxSecPerKm: 250,
        ),
        RunWorkoutStep(
          id: 's3',
          runPlanWorkoutId: 'w1',
          orderIndex: 2,
          role: RunStepRole.cooldown,
          metric: RunIntervalMetric.distance,
          value: 1000,
        ),
      ],
    );

    test('distance steps become time at their target pace', () {
      final steps = intervals().treadmillStepsJson();
      expect(steps.map((s) => s['metric']), everyElement('time'));
      expect(steps[0]['value'], 600);
      // 400 m at the 4:00 band midpoint.
      expect(steps[1]['value'], 96);
      expect(steps[1]['targetPaceMinSecPerKm'], 230);
      // No band: the workout pace.
      expect(steps[2]['value'], 240);
    });

    test('the voice profile carries the kind and headline targets', () {
      final profile = intervals().voiceProfile();
      expect(profile['kind'], 'interval');
      expect(profile['targetPaceSecPerKm'], 240);
    });

    test('drives the native coach and keeps its step results', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('workout_notes/run_voice/methods');
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return switch (call.method) {
          'indoorStart' => true,
          'indoorStop' => [
            {
              'sequence': 0,
              'role': 'warmup',
              'repIndex': 1,
              'plannedMetric': 'time',
              'plannedValue': 600,
              'distanceMeters': 0.0,
              'durationSeconds': 600,
            },
          ],
          _ => null,
        };
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(channel, null);
        debugDefaultTargetPlatformOverride = null;
      });

      final workout = intervals();
      final service = IndoorTrackingService.instance;
      await service.start(
        type: CardioActivityType.treadmill,
        voice: RunIndoorVoiceSetup(
          settings: const RunVoiceSettings.defaults(),
          goal: const {'enabled': false},
          plan: workout.treadmillStepsJson(),
          workout: workout.voiceProfile(),
        ),
      );
      final start = calls.singleWhere((c) => c.method == 'indoorStart');
      final args = Map<String, dynamic>.from(start.arguments as Map);
      expect((args['plan'] as List).length, 3);
      expect((args['workout'] as Map)['kind'], 'interval');

      await service.pause();
      await service.resume();
      expect(
        calls.map((c) => c.method),
        containsAllInOrder(['indoorStart', 'indoorPause', 'indoorResume']),
      );

      final draft = await service.stopForReview();
      expect(calls.last.method, 'indoorStop');
      final results = (draft!.spool['activity'] as Map)['voice_step_results'];
      expect(results, hasLength(1));
      expect(draft.stepResults, hasLength(1));
    });

    test('the bike never starts the coach', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('workout_notes/run_voice/methods');
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(channel, null);
        debugDefaultTargetPlatformOverride = null;
      });

      await IndoorTrackingService.instance.start(
        voice: const RunIndoorVoiceSetup(
          settings: RunVoiceSettings.defaults(),
          goal: {},
          plan: [],
        ),
      );
      expect(calls, isEmpty);
    });
  });
}
