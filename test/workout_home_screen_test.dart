import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/database/database_schema.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/screens/workout/workout_home_screen.dart';

import 'support/strength_home_fixtures.dart';
import 'support/test_db.dart';

Future<void> _pumpHome(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('pt'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const WorkoutHomeScreen(),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await tester.pump();
  });
  await tester.pump(const Duration(seconds: 1));
}

/// The run-tracking channels do not exist on the desktop test host; anything
/// else thrown (layout overflow, for instance) is a real failure.
void _expectOnlyMissingPlugins(WidgetTester tester) {
  Object? error;
  while ((error = tester.takeException()) != null) {
    expect(error, isA<MissingPluginException>());
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database database;

  setUpAll(initSqfliteFfiForTests);

  setUp(() async {
    database = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 54,
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

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(360 * 2, 800 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
  }

  testWidgets('first launch shows the empty state and both hub cards', (
    tester,
  ) async {
    phone(tester);
    await _pumpHome(tester);

    expect(find.text('Nenhum treino ainda'), findsOneWidget);
    expect(find.byKey(const Key('workout-home-strength-hub')), findsOneWidget);
    expect(find.byKey(const Key('workout-home-run-hub')), findsOneWidget);
    // The old tools grid, quick actions and long lists moved to the hubs.
    expect(find.text('FERRAMENTAS'), findsNothing);
    expect(find.text('AÇÕES RÁPIDAS'), findsNothing);
    expect(find.text('TREINOS CONCLUÍDOS'), findsNothing);
    _expectOnlyMissingPlugins(tester);
  });

  testWidgets('with history: finished-only weekly overview and hubs', (
    tester,
  ) async {
    phone(tester);
    final now = DateTime.now();
    String day(int back) => DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: back)).toIso8601String().substring(0, 10);

    await tester.runAsync(() async {
      await seedRoutine(
        database,
        id: 'ppl',
        name: 'PPL',
        days: [(id: 'push', name: 'Push A')],
      );
      await database.insert('exercises', {
        'id': 'test-bench',
        'name': 'Bench',
        'category_id': 'chest',
        'created_at': '2026-01-01T00:00:00.000',
      });
      await seedWorkout(
        database,
        id: 'today-done',
        date: day(0),
        routineId: 'ppl',
        routineDayId: 'push',
        sets: [seedSet('test-bench', 100, 5)],
      );
      // A planned workout and a set-less one never count as sessions.
      await seedWorkout(
        database,
        id: 'planned',
        date: day(0),
        finished: false,
        sets: [seedSet('test-bench', 100, 5)],
      );
    });

    await _pumpHome(tester);

    // Week rings, today's agenda (done), training areas and recents.
    expect(find.byKey(const Key('workout-home-ring-strength')), findsOneWidget);
    expect(find.text('HOJE'), findsOneWidget);
    // Legend + the done badge in today's agenda.
    expect(find.text('Feito'), findsNWidgets(2));
    expect(find.text('SEUS TREINOS'), findsOneWidget);
    // Only the finished workout counts (the planned one does not).
    expect(find.text('1 treino esta semana'), findsOneWidget);
    expect(find.text('Nenhum treino ainda'), findsNothing);
    _expectOnlyMissingPlugins(tester);
  });
  testWidgets('a failed read is an error with retry, not the empty state', (
    tester,
  ) async {
    phone(tester);
    await tester.runAsync(
      () => database.execute(
        'ALTER TABLE run_activities RENAME TO run_activities_hidden',
      ),
    );
    await _pumpHome(tester);

    expect(find.byKey(const Key('load-error-retry')), findsOneWidget);
    expect(find.text('Nenhum treino ainda'), findsNothing);

    await tester.runAsync(
      () => database.execute(
        'ALTER TABLE run_activities_hidden RENAME TO run_activities',
      ),
    );
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('load-error-retry')));
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await tester.pump();
    });
    await tester.pump(const Duration(seconds: 1));

    expect(find.byKey(const Key('load-error-retry')), findsNothing);
    expect(find.text('Nenhum treino ainda'), findsOneWidget);
    _expectOnlyMissingPlugins(tester);
  });

  testWidgets('a failed refresh keeps the data on screen with a retry', (
    tester,
  ) async {
    // Wider than the other cases: the streak chip needs room in test fonts.
    tester.view.physicalSize = const Size(480 * 2, 800 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    final today = DateTime(
      now.year,
      now.month,
      now.day,
    ).toIso8601String().substring(0, 10);
    await tester.runAsync(() async {
      await seedRoutine(
        database,
        id: 'ppl',
        name: 'PPL',
        days: [(id: 'push', name: 'Push A')],
      );
      await database.insert('exercises', {
        'id': 'test-bench',
        'name': 'Bench',
        'category_id': 'chest',
        'created_at': '2026-01-01T00:00:00.000',
      });
      await seedWorkout(
        database,
        id: 'today-done',
        date: today,
        routineId: 'ppl',
        routineDayId: 'push',
        sets: [seedSet('test-bench', 100, 5)],
      );
    });
    await _pumpHome(tester);
    expect(find.text('1 treino esta semana'), findsOneWidget);

    await tester.runAsync(
      () => database.execute(
        'ALTER TABLE run_activities RENAME TO run_activities_hidden',
      ),
    );
    // Pull to refresh.
    await tester.runAsync(() async {
      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, 400),
        1000,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await tester.pump();
    });
    await tester.pump(const Duration(seconds: 1));

    expect(find.byKey(const Key('load-error-banner-retry')), findsOneWidget);
    // The earlier data is still there (today's agenda), not an empty state.
    expect(find.text('HOJE'), findsOneWidget);
    expect(find.text('Nenhum treino ainda'), findsNothing);
    _expectOnlyMissingPlugins(tester);
  });
}
