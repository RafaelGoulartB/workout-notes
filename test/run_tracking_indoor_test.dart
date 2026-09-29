import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/database/database_schema.dart';
import 'package:workout_notes/models/cardio_activity_type.dart';
import 'package:workout_notes/models/run_review_draft.dart';
import 'package:workout_notes/repositories/run_repository.dart';
import 'package:workout_notes/services/run_tracking_service.dart';
import 'package:workout_notes/services/stationary_bike_tracking_service.dart';

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

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

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
    await StationaryBikeTrackingService.instance.discard();
    DatabaseHelper.overrideDatabase = null;
    await database.close();
  });

  group('indoor timer service', () {
    test('times a treadmill session without GPS', () async {
      final service = StationaryBikeTrackingService.instance;
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
      final service = StationaryBikeTrackingService.instance;
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
}
