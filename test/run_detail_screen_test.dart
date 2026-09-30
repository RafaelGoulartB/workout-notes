import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/database/database_schema.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_lap.dart';
import 'package:workout_notes/repositories/run_repository.dart';
import 'package:workout_notes/screens/run/run_detail_screen.dart';
import 'support/test_db.dart';

const _metersPerDegree = 111195.0;

/// 2.5 km outdoor run: 6:00 /km, +50 m climb, no calories recorded.
Map<String, dynamic> _spool(String id, {int? calories}) {
  final start = DateTime.utc(2026, 8, 25, 10);
  final points = <Map<String, dynamic>>[];
  for (var i = 0; i <= 100; i++) {
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
      'status': 'completed',
      'started_at': start.toIso8601String(),
      'ended_at': start.add(const Duration(minutes: 16)).toIso8601String(),
      'duration_seconds': 960,
      'moving_time_seconds': 900,
      'distance_meters': 2500.0,
      'avg_pace_sec_per_km': 360.0,
      'calories': ?calories,
    },
    'points': points,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
  });

  Future<void> pumpDetail(WidgetTester tester, String id) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('pt'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: RunDetailScreen(activityId: id, showMapTiles: false),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 80));
        await tester.pump(const Duration(milliseconds: 100));
      }
    });
    await tester.pump();
  }

  testWidgets('shows a de-duplicated summary, map legend and charts', (
    tester,
  ) async {
    await tester.runAsync(
      () =>
          RunRepository().importNativeSpool(_spool('detail-run', calories: 0)),
    );
    await pumpDetail(tester, 'detail-run');

    expect(find.byType(RunDetailScreen), findsOneWidget);
    // Map with legend, replay and full-screen buttons.
    expect(find.text('Médio ou mais lento'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('run-detail-replay-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('run-detail-fullscreen-button')),
      findsOneWidget,
    );
    // One grid: pace appears once, no "0 kcal", the elapsed time is a caption.
    expect(find.text('Pace médio'), findsOneWidget);
    expect(find.textContaining('0 kcal'), findsNothing);
    expect(find.text('total 16:00'), findsOneWidget);
    expect(find.text('Elevação'), findsWidgets);
    expect(find.text('Km mais rápido'), findsOneWidget);

    // Gear row is a prompt while no shoes are set.
    await tester.scrollUntilVisible(
      find.text('Informar o tênis usado'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    // The pace / elevation toggle switches the chart.
    final elevationTab = find.text('Elevação').last;
    await tester.scrollUntilVisible(
      elevationTab,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(elevationTab);
    await tester.pump();
    await tester.tap(elevationTab);
    await tester.pump();
    expect(find.text('Subida'), findsOneWidget);
    expect(find.text('Descida'), findsOneWidget);

    // Splits carry the per-km delta and climb columns.
    await tester.scrollUntilVisible(
      find.text('vs média'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Subida'), findsWidgets);
  });

  testWidgets('shows the shoe used and lets the runner pick another', (
    tester,
  ) async {
    late String gearId;
    await tester.runAsync(() async {
      final gear = await DatabaseHelper.instance.runGearRepo.saveGear(
        name: 'Pegasus 41',
      );
      gearId = gear.id;
      await RunRepository().importNativeSpool(_spool('gear-run'));
      await DatabaseHelper.instance.runGearRepo.setActivityGear(
        'gear-run',
        gearId,
      );
    });
    await pumpDetail(tester, 'gear-run');

    await tester.scrollUntilVisible(
      find.text('Pegasus 41'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('no total'), findsOneWidget);

    await tester.tap(find.text('Pegasus 41'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump();
    expect(find.text('Tênis usado'), findsOneWidget);
    expect(find.text('Sem tênis'), findsOneWidget);
  });

  testWidgets('lists manual laps when the run has them', (tester) async {
    await tester.runAsync(() async {
      await RunRepository().importNativeSpool(_spool('laps-run'));
      await DatabaseHelper.instance.runGearRepo.replaceLaps('laps-run', const [
        RunLap(
          index: 1,
          startDistanceMeters: 0,
          distanceMeters: 1000,
          durationSeconds: 360,
          paceSecPerKm: 360,
        ),
        RunLap(
          index: 2,
          startDistanceMeters: 1000,
          distanceMeters: 1500,
          durationSeconds: 500,
          paceSecPerKm: 333,
        ),
      ]);
    });
    await pumpDetail(tester, 'laps-run');

    await tester.scrollUntilVisible(
      find.text('Volta 2'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Volta 1'), findsOneWidget);
  });
}
