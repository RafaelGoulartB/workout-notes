import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/screens/run/run_detail_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/database/database_schema.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_review_draft.dart';
import 'package:workout_notes/repositories/run_repository.dart';
import 'package:workout_notes/screens/run/run_post_run_review_screen.dart';
import 'package:workout_notes/services/run_tracking_service.dart';
import 'support/test_db.dart';

const _metersPerDegree = 111195.0;

/// Spool for a 1.5 km outdoor run at 6:00 /km with altitude on every point.
Map<String, dynamic> _outdoorSpool(String id) {
  final start = DateTime.utc(2026, 8, 25, 10);
  final points = <Map<String, dynamic>>[];
  for (var i = 0; i <= 60; i++) {
    final meters = i * 25.0;
    points.add({
      'lat': meters / _metersPerDegree,
      'lng': 0.0,
      'altitude': 100 + meters * 0.02,
      'accuracy': 5.0,
      'recorded_at': start
          .add(Duration(milliseconds: (meters * 360).round()))
          .toIso8601String(),
    });
  }
  return {
    'activity': {
      'id': id,
      'status': 'pending_review',
      'started_at': start.toIso8601String(),
      'ended_at': start.add(const Duration(minutes: 9)).toIso8601String(),
      'duration_seconds': 540,
      'moving_time_seconds': 540,
      'distance_meters': 1500.0,
      'avg_pace_sec_per_km': 360.0,
    },
    'points': points,
  };
}

Map<String, dynamic> _treadmillSpool(String id) => {
  'activity': {
    'id': id,
    'activity_type': 'treadmill',
    'status': 'pending_review',
    'started_at': '2026-08-25T10:00:00.000Z',
    'ended_at': '2026-08-25T10:29:10.000Z',
    'duration_seconds': 1750,
    'moving_time_seconds': 1750,
    'distance_meters': 0.0,
  },
  'points': <Map<String, dynamic>>[],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Database database;

  setUpAll(initSqfliteFfiForTests);

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
    messenger.setMockMethodCallHandler(RunTrackingService.methods, null);
  });

  /// Alternates frames with short real waits so SQLite work can finish.
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
    });
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> pumpReview(
    WidgetTester tester,
    Map<String, dynamic> spool,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final draft = RunReviewDraft.fromSpool(
      activity: RunRepository().previewNativeSpool(spool),
      spool: spool,
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('pt'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => RunPostRunReviewScreen(
                      draft: draft,
                      showMapTiles: false,
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
  }

  testWidgets('back asks to save, discard or keep editing', (tester) async {
    await pumpReview(tester, _outdoorSpool('leave-run'));
    expect(find.text('Revisar corrida'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Sair sem salvar?'), findsOneWidget);
    expect(find.text('Continuar editando'), findsOneWidget);

    await tester.tap(find.text('Continuar editando'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Sair sem salvar?'), findsNothing);
    expect(find.text('Revisar corrida'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 500));
    // "Descartar" inside the dialog leaves the screen.
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Descartar'),
      ),
    );
    await settle(tester);
    expect(find.text('Revisar corrida'), findsNothing);
    final saved = await tester.runAsync(() => RunRepository().listActivities());
    expect(saved, isEmpty);
  });

  testWidgets('saving from the leave dialog stores the run', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    messenger.setMockMethodCallHandler(
      RunTrackingService.methods,
      (_) async => true,
    );
    await pumpReview(tester, _outdoorSpool('leave-save-run'));

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Salvar'),
      ),
    );
    await settle(tester);

    final saved = await tester.runAsync(() => RunRepository().listActivities());
    expect(saved, hasLength(1));
    expect(saved!.single.id, 'leave-save-run');
    // The detail screen replaced the review and finishes loading.
    await settle(tester);
    expect(find.byType(RunDetailScreen), findsOneWidget);
    await settle(tester);
    // Invariants are checked before tearDown callbacks run.
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'outdoor review shows route and pace, without elevation or gear',
    (tester) async {
      await pumpReview(tester, _outdoorSpool('outdoor-run'));

      expect(find.text('PERCURSO'), findsOneWidget);
      expect(find.text('Médio ou mais lento'), findsOneWidget);
      // Elevation profile and shoe picker live on the run detail, not here.
      expect(find.text('Subida'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('O QUE ESSA CORRIDA SIGNIFICOU'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Informar o tênis usado'), findsNothing);
      expect(find.text('TÊNIS'), findsNothing);
      // The insights card loads asynchronously, then may sit below the fold.
      await settle(tester);
      await tester.scrollUntilVisible(
        find.textContaining('nesta semana'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('nesta semana'), findsOneWidget);
    },
  );

  testWidgets('treadmill review asks for distance and shows pace', (
    tester,
  ) async {
    await pumpReview(tester, _treadmillSpool('treadmill-run'));

    final field = find.byKey(const ValueKey('stationary-bike-distance'));
    await tester.scrollUntilVisible(
      field,
      -100,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Distância da esteira (km)'), findsOneWidget);
    expect(find.text('DADOS DA ESTEIRA'), findsOneWidget);
    // No pace yet: the distance is unknown.
    expect(find.text('--:--'), findsWidgets);

    await tester.enterText(field, '5');
    await tester.pump();
    // 1750 s over 5 km = 5:50 /km, shown as pace (not speed).
    await tester.scrollUntilVisible(
      find.text('5:50'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('5:50'), findsOneWidget);
    expect(find.text('km/h'), findsNothing);
  });
}
