import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/database/database_schema.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/screens/workout/workout_home_screen.dart';

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

    for (var index = 0; index < 6; index++) {
      final workoutDay = 25 - index * 2;
      final runDay = workoutDay - 1;
      await database.insert('workouts', {
        'id': 'workout-$index',
        'date': '2026-08-${workoutDay.toString().padLeft(2, '0')}',
        'start_time':
            '2026-08-${workoutDay.toString().padLeft(2, '0')}T10:00:00',
        'end_time': '2026-08-${workoutDay.toString().padLeft(2, '0')}T11:00:00',
        'duration_seconds': 3600,
        'feeling_rating': 4,
        'created_at':
            '2026-08-${workoutDay.toString().padLeft(2, '0')}T10:00:00',
      });
      await database.insert('run_activities', {
        'id': 'run-$index',
        'started_at': '2026-08-${runDay.toString().padLeft(2, '0')}T10:00:00',
        'ended_at': '2026-08-${runDay.toString().padLeft(2, '0')}T10:30:00',
        'duration_seconds': 1800,
        'moving_time_seconds': 1750,
        'distance_meters': 5000,
        'feeling_rating': 5,
        'status': 'completed',
        'created_at': '2026-08-${runDay.toString().padLeft(2, '0')}T10:00:00',
        'updated_at': '2026-08-${runDay.toString().padLeft(2, '0')}T10:30:00',
      });
    }
  });

  tearDown(() async {
    DatabaseHelper.overrideDatabase = null;
    await database.close();
  });

  testWidgets('mixes workouts and runs and limits completed list to eight', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('pt'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const WorkoutHomeScreen(),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
    });
    await tester.pump();
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, -2400),
      3000,
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('completed-workout-workout-0')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('completed-run-run-0')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('completed-run-run-0')),
        matching: find.byIcon(Icons.directions_run_rounded),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('completed-run-run-3')), findsOneWidget);
    expect(find.byKey(const ValueKey('completed-run-run-4')), findsNothing);
    expect(
      find.byKey(const ValueKey('completed-workout-workout-4')),
      findsNothing,
    );

    final completedCards = find.byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith('completed-'),
    );
    expect(completedCards, findsNWidgets(8));
    debugDefaultTargetPlatformOverride = null;
  });
}
