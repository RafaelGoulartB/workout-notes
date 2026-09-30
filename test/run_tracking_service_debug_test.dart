import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/database/database_schema.dart';
import 'package:workout_notes/models/run_tracking_state.dart';
import 'package:workout_notes/services/run_tracking_service.dart';

/// The service drives whichever backend is active; in debug builds off
/// Android that is the simulated GPS run.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database database;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
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
    await RunTrackingService.instance.discard();
    DatabaseHelper.overrideDatabase = null;
    await database.close();
    debugDefaultTargetPlatformOverride = null;
  });

  test('a simulated run pauses, resumes and marks laps through the service', () async {
    final service = RunTrackingService.instance;
    expect(service.isDebugSimulating, isFalse);

    expect(await service.startDebugSimulation(), isTrue);
    expect(service.isDebugSimulating, isTrue);
    expect(service.state.status, RunTrackingState.recording);

    await service.pause();
    expect(service.state.status, RunTrackingState.paused);
    await service.resume();
    expect(service.state.status, RunTrackingState.recording);

    // Laps under two moving seconds are ignored, like the native tracker.
    expect(await service.lap(), isNull);
  });

  test('stopping keeps the review in memory and returns to the native backend', () async {
    final service = RunTrackingService.instance;
    await service.startDebugSimulation();

    final draft = await service.stopForReview();

    expect(draft, isNotNull);
    expect((draft!.spool['activity'] as Map)['status'], 'pending_review');
    expect(service.isDebugSimulating, isFalse);
    expect(service.state.status, RunTrackingState.idle);
    final pending = await service.listPendingReviews();
    expect(pending.map((d) => d.id), contains(draft.id));

    await service.discardReview(draft);
    expect(
      (await service.listPendingReviews()).map((d) => d.id),
      isNot(contains(draft.id)),
    );
  });

  test('discarding a simulated run resets the service', () async {
    final service = RunTrackingService.instance;
    await service.startDebugSimulation();

    await service.discard();

    expect(service.isDebugSimulating, isFalse);
    expect(service.state.isActive, isFalse);
  });
}
