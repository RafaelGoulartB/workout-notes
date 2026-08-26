import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/database/database_schema.dart';
import 'package:workout_notes/models/run_review_draft.dart';
import 'package:workout_notes/repositories/run_plan_repository.dart';
import 'package:workout_notes/repositories/run_repository.dart';
import 'package:workout_notes/services/run_tracking_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Database database;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    messenger.setMockMethodCallHandler(
      RunTrackingService.methods,
      (_) async => true,
    );
    database = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 48,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: DatabaseSchema.onCreate,
      ),
    );
    DatabaseHelper.overrideDatabase = database;
  });

  tearDown(() async {
    DatabaseHelper.overrideDatabase = null;
    await database.close();
    messenger.setMockMethodCallHandler(RunTrackingService.methods, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('saving a short review can preserve the planned session', () async {
    final planRepository = RunPlanRepository();
    final plan = await planRepository.createPlan(name: 'Base', weeks: 1);
    final workout = await planRepository.addWorkout(
      planId: plan.id,
      weekIndex: 0,
      name: 'Rodagem',
    );
    final scheduled = await planRepository.scheduleRun(
      date: DateTime(2026, 8, 25),
      runPlanId: plan.id,
      runPlanWorkoutId: workout.id,
    );
    final spool = <String, dynamic>{
      'activity': <String, dynamic>{
        'id': 'short-review',
        'status': 'pending_review',
        'started_at': '2026-08-25T10:00:00.000Z',
        'ended_at': '2026-08-25T10:00:12.000Z',
        'duration_seconds': 12,
        'moving_time_seconds': 10,
        'distance_meters': 18.0,
        'plan_workout_id': workout.id,
        'scheduled_run_id': scheduled.id,
      },
      'points': <Map<String, dynamic>>[],
    };
    final runRepository = RunRepository();
    final draft = RunReviewDraft.fromSpool(
      activity: runRepository.previewNativeSpool(spool),
      spool: spool,
    );

    final saved = await RunTrackingService.instance.saveReviewedRun(
      draft: draft,
      completePlannedWorkout: false,
      title: 'Teste curto',
      rpe: 2,
      feelingRating: 3,
    );

    expect(saved, isNotNull);
    expect(saved!.rpe, 2);
    expect(saved.feelingRating, 3);
    final unchanged = await planRepository.getScheduledRun(scheduled.id);
    expect(unchanged!.isPlanned, isTrue);
    expect(unchanged.runActivityId, isNull);
  });
}
