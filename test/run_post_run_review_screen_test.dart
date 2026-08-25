import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/database/database_schema.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_review_draft.dart';
import 'package:workout_notes/repositories/run_repository.dart';
import 'package:workout_notes/screens/run/run_post_run_review_screen.dart';

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
  });

  testWidgets('shows the complete review before the run is saved', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final spool = <String, dynamic>{
      'activity': <String, dynamic>{
        'id': 'review-widget',
        'status': 'pending_review',
        'started_at': '2026-08-25T10:00:00.000Z',
        'ended_at': '2026-08-25T10:30:00.000Z',
        'duration_seconds': 1800,
        'moving_time_seconds': 1750,
        'distance_meters': 5000.0,
        'avg_pace_sec_per_km': 350.0,
        'splits': <Map<String, dynamic>>[
          <String, dynamic>{
            'km': 1,
            'distance_meters': 1000.0,
            'duration_seconds': 350,
            'pace_sec_per_km': 350.0,
            'is_partial': false,
          },
        ],
      },
      'points': <Map<String, dynamic>>[],
    };
    final draft = RunReviewDraft.fromSpool(
      activity: RunRepository().previewNativeSpool(spool),
      spool: spool,
    );

    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('pt'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: RunPostRunReviewScreen(draft: draft),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await tester.pump();
    });

    expect(find.text('Revisar corrida'), findsOneWidget);
    expect(find.text('5.00 km'), findsOneWidget);
    expect(find.text('ESFORÇO PERCEBIDO'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('COMO VOCÊ SE SENTIU?'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('COMO VOCÊ SE SENTIU?'), findsOneWidget);
    expect(find.text('Salvar'), findsOneWidget);
    expect(find.text('Descartar'), findsOneWidget);
    final thirdStar = find.byKey(const ValueKey('run-review-feeling-3'));
    await tester.scrollUntilVisible(
      thirdStar,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byIcon(Icons.star_outline_rounded), findsNWidgets(5));
    await tester.ensureVisible(thirdStar);
    await tester.pumpAndSettle();
    await tester.tap(thirdStar);
    await tester.pump();
    expect(find.byIcon(Icons.star_rounded), findsNWidgets(3));
    expect(find.byIcon(Icons.star_outline_rounded), findsNWidgets(2));

    final firstRpe = tester.getCenter(
      find.byKey(const ValueKey('run-review-rpe-1')),
    );
    final lastRpe = tester.getCenter(
      find.byKey(const ValueKey('run-review-rpe-10')),
    );
    expect((firstRpe.dy - lastRpe.dy).abs(), lessThan(0.1));
    final saved = await tester.runAsync(() => RunRepository().listActivities());
    expect(saved, isEmpty);
  });
}
