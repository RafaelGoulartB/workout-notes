import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/database/database_schema.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/cardio_activity_type.dart';
import 'package:workout_notes/models/run_review_draft.dart';
import 'package:workout_notes/repositories/run_repository.dart';
import 'package:workout_notes/screens/run/run_post_run_review_screen.dart';
import 'package:workout_notes/services/run_tracking_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database database;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    database = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 49,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: DatabaseSchema.onCreate,
      ),
    );
    DatabaseHelper.overrideDatabase = database;
  });

  tearDown(() async {
    DatabaseHelper.overrideDatabase = null;
    await database.close();
  });

  testWidgets('records console distance and saves a stationary bike session', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final spool = <String, dynamic>{
      'activity': <String, dynamic>{
        'id': 'bike-review',
        'activity_type': 'stationary_bike',
        'status': 'pending_review',
        'started_at': '2026-08-25T10:00:00.000Z',
        'ended_at': '2026-08-25T10:30:00.000Z',
        'duration_seconds': 1800,
        'moving_time_seconds': 1800,
        'distance_meters': 0.0,
      },
      'points': <Map<String, dynamic>>[],
    };
    final repository = RunRepository();
    final draft = RunReviewDraft.fromSpool(
      activity: repository.previewNativeSpool(spool),
      spool: spool,
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('pt'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RunPostRunReviewScreen(draft: draft),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump();

    expect(find.text('Revisar bicicleta'), findsOneWidget);
    final distanceField = find.byKey(
      const ValueKey('stationary-bike-distance'),
    );
    await tester.ensureVisible(distanceField);
    await tester.enterText(distanceField, '12,5');
    await tester.pump();
    expect(tester.widget<TextField>(distanceField).controller!.text, '12,5');

    await tester.runAsync(
      () => RunTrackingService.instance.saveReviewedRun(
        draft: draft,
        completePlannedWorkout: false,
        distanceMeters: 12500,
      ),
    );

    final saved = await tester.runAsync(
      () => repository.getActivity('bike-review'),
    );
    expect(saved, isNotNull);
    expect(saved!.activityType, CardioActivityType.stationaryBike);
    expect(saved.distanceMeters, 12500);
    expect(saved.averageSpeedKmh, closeTo(25, 0.001));
    expect(await tester.runAsync(repository.listActivities), isEmpty);
    expect(
      await tester.runAsync(
        () => repository.listActivities(activityType: null),
      ),
      hasLength(1),
    );
    debugDefaultTargetPlatformOverride = null;
  });
}
