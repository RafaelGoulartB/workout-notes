import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/periodization_phase.dart';
import 'package:workout_notes/models/periodization_plan.dart';
import 'package:workout_notes/models/periodization_target.dart';
import 'package:workout_notes/screens/workout/active_workout_screen.dart';
import 'package:workout_notes/services/rest_timer_service.dart';
import 'package:workout_notes/utils/date_utils.dart';
import 'package:workout_notes/widgets/workout/exercise_card.dart';

import 'support/strength_home_fixtures.dart'
    show seedRoutine, seedRoutineExercise;
import 'support/strength_workout_seed.dart';
import 'support/test_db.dart';

/// Opens the active workout from a host route and records what it popped with.
class _Host extends StatelessWidget {
  final ValueChanged<Object?> onResult;

  const _Host({required this.onResult});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () async {
          final result = await Navigator.push<Object?>(
            context,
            MaterialPageRoute(
              builder: (_) => const ActiveWorkoutScreen(workoutId: 'live'),
            ),
          );
          onResult(result);
        },
        child: const Text('open-workout'),
      ),
    ),
  );
}

void main() {
  late Database db;

  setUpAll(initSqfliteFfiForTests);

  setUp(() async {
    db = await installTestDb();
    await seedStrengthBasics(db);
    Intl.defaultLocale = 'en';
  });

  tearDown(() async {
    RestTimerService.instance.stop();
    Intl.defaultLocale = null;
    await uninstallTestDb();
  });

  Future<void> settle(WidgetTester tester, {int rounds = 6}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> seedLive({List<String> exercises = const ['bench']}) =>
      seedWorkout(
        db,
        'live',
        date: dateKey(DateTime.now()),
        finished: false,
        exercises: [
          for (final id in exercises)
            (id, [seedSet(80, 8, done: false), seedSet(80, 8, done: false)]),
        ],
      );

  Future<List<Object?>> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // The test font is much wider than a real one: shrink it so menu rows
    // and chips fit like they do on a device.
    tester.platformDispatcher.textScaleFactorTestValue = 0.7;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final results = <Object?>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: _Host(onResult: results.add),
      ),
    );
    await tester.tap(find.text('open-workout'));
    await tester.pump();
    await settle(tester, rounds: 8);
    return results;
  }

  Future<List<Map<String, Object?>>> query(
    WidgetTester tester,
    String table, {
    String? where,
    List<Object?>? args,
    String? orderBy,
  }) async => (await tester.runAsync(
    () => db.query(table, where: where, whereArgs: args, orderBy: orderBy),
  ))!;

  Future<void> openMenu(WidgetTester tester, String item) async {
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(item).last);
    await settle(tester, rounds: 4);
  }

  /// Taps the rest-time chip of the first exercise card.
  Future<void> openRestSheet(WidgetTester tester) async {
    await tester.tap(
      find.descendant(
        of: find.byType(ExerciseCard).first,
        matching: find.byIcon(Icons.timer_outlined),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<int?> restOf(WidgetTester tester) async =>
      (await query(
            tester,
            'exercise_entries',
            where: "id = 'live-e0'",
          )).single['rest_time_seconds']
          as int?;

  group('importing a routine day', () {
    testWidgets('without routines says so', (tester) async {
      await tester.runAsync(() async {
        await seedLive();
        await db.delete('routines');
      });
      await open(tester);

      await openMenu(tester, 'Import from Routine');
      expect(find.text('No routine found. Create one first!'), findsOneWidget);
    });

    testWidgets('a routine without days says so', (tester) async {
      await tester.runAsync(() async {
        await seedLive();
        await db.delete('routines');
        await seedRoutine(db, id: 'bare', name: 'Bare', days: const []);
      });
      await open(tester);

      await openMenu(tester, 'Import from Routine');
      await tester.tap(find.text('Bare'));
      await settle(tester);
      expect(find.text('This routine has no days.'), findsOneWidget);
    });

    testWidgets('appends the chosen day to the open workout', (tester) async {
      await tester.runAsync(() async {
        await seedLive();
        await seedRoutineExercise(
          db,
          id: 'pull-row',
          dayId: 'pull',
          exerciseId: 'row',
          sets: 3,
        );
      });
      await open(tester);
      expect(find.byType(ExerciseCard), findsOneWidget);

      await openMenu(tester, 'Import from Routine');
      expect(find.text('Select Routine'), findsOneWidget);
      await tester.tap(find.text('Push Pull Legs'));
      await settle(tester);
      expect(find.text('Select the day to import'), findsOneWidget);
      expect(find.text('Push A'), findsOneWidget);
      await tester.tap(find.text('Pull A'));
      await settle(tester);

      final entries = await query(
        tester,
        'exercise_entries',
        where: "workout_id = 'live'",
        orderBy: 'order_index',
      );
      expect(entries.map((e) => e['exercise_id']), ['bench', 'row']);
      expect(find.byType(ExerciseCard), findsNWidgets(2));
      expect(find.text('Barbell Row'), findsOneWidget);
      expect(find.text('✅ Exercises imported from routine!'), findsOneWidget);
    });

    testWidgets('backing out of the day list imports nothing', (tester) async {
      await tester.runAsync(seedLive);
      await open(tester);

      await openMenu(tester, 'Import from Routine');
      await tester.tap(find.text('Push Pull Legs'));
      await settle(tester);
      await tester.tap(find.text('Back'));
      await settle(tester);

      expect(find.text('✅ Exercises imported from routine!'), findsNothing);
      expect(await query(tester, 'exercise_entries'), hasLength(1));
    });

    testWidgets('the routine linked to today\'s plan comes first, marked', (
      tester,
    ) async {
      final today = dayOf(DateTime.now());
      final start = addDays(today, -7);
      final end = addDays(today, 21);
      final now = DateTime.now();
      await tester.runAsync(() async {
        await seedLive();
        await seedRoutine(
          db,
          id: 'full',
          name: 'Full body',
          days: [(id: 'full-a', name: 'Full A')],
        );
        await db.insert(
          'periodization_plans',
          PeriodizationPlan(
            id: 'plan',
            name: 'Plan',
            startDate: start,
            endDate: end,
            status: PeriodizationPlanStatus.active,
            createdAt: now,
            updatedAt: now,
          ).toMap(),
        );
        await db.insert(
          'periodization_phases',
          PeriodizationPhase(
            id: 'phase',
            planId: 'plan',
            name: 'Build',
            color: 0xFF2196F3,
            startDate: start,
            endDate: end,
            orderIndex: 0,
            createdAt: now,
            updatedAt: now,
          ).toMap(),
        );
        await db.insert(
          'phase_targets',
          PeriodizationTarget(
            id: 'target',
            phaseId: 'phase',
            version: 1,
            validFrom: start,
            routineIds: const ['full'],
            createdAt: now,
          ).toMap(),
        );
      });
      await open(tester);

      await openMenu(tester, 'Import from Routine');
      expect(find.text('Plan target'), findsOneWidget);
      expect(find.byIcon(Icons.star_rounded), findsOneWidget);
      final names = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(ListTile),
              matching: find.byType(Text),
            ),
          )
          .map((t) => t.data)
          .whereType<String>()
          .where((t) => t == 'Full body' || t == 'Push Pull Legs')
          .toList();
      expect(names, ['Full body', 'Push Pull Legs']);
    });

    testWidgets('lists routines in order when no plan is active', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await seedLive();
        await seedRoutine(
          db,
          id: 'full',
          name: 'Full body',
          days: [(id: 'full-a', name: 'Full A')],
        );
      });
      await open(tester);

      await openMenu(tester, 'Import from Routine');
      expect(find.text('Plan target'), findsNothing);
      expect(find.text('Full body'), findsOneWidget);
      expect(find.text('Push Pull Legs'), findsOneWidget);
    });
  });

  group('rest time', () {
    testWidgets('a preset updates the exercise', (tester) async {
      await tester.runAsync(seedLive);
      await open(tester);
      expect(find.text('1min30'), findsOneWidget);

      await openRestSheet(tester);
      expect(find.text('Rest Time'), findsOneWidget);
      expect(find.text('Bench Press'), findsWidgets);
      await tester.tap(find.text('2min0s'));
      await settle(tester);

      expect(await restOf(tester), 120);
      expect(find.text('2min0'), findsOneWidget);
      expect(find.text('Rest Time'), findsNothing);
    });

    testWidgets('a short preset is shown in seconds', (tester) async {
      await tester.runAsync(seedLive);
      await open(tester);

      await openRestSheet(tester);
      await tester.tap(find.text('30s'));
      await settle(tester);

      expect(await restOf(tester), 30);
      expect(find.text('30s'), findsOneWidget);
    });

    testWidgets('a custom time is saved, invalid ones are refused', (
      tester,
    ) async {
      await tester.runAsync(seedLive);
      await open(tester);

      await openRestSheet(tester);
      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();
      expect(find.text('Custom Time'), findsOneWidget);
      // The field starts at the current rest time.
      expect(find.text('90'), findsOneWidget);

      for (final bad in ['0', 'abc', '']) {
        await tester.enterText(find.byType(TextField), bad);
        await tester.tap(find.text('Set'));
        await tester.pumpAndSettle();
        expect(find.text('Custom Time'), findsOneWidget, reason: '"$bad"');
      }
      expect(await restOf(tester), isNull);

      await tester.enterText(find.byType(TextField), '45');
      await tester.tap(find.text('Set'));
      await settle(tester);
      expect(find.text('Custom Time'), findsNothing);
      expect(await restOf(tester), 45);
      expect(find.text('45s'), findsOneWidget);
    });

    testWidgets('cancelling the custom dialog keeps the rest time', (
      tester,
    ) async {
      await tester.runAsync(seedLive);
      await open(tester);

      await openRestSheet(tester);
      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await settle(tester);

      expect(find.text('Custom Time'), findsNothing);
      expect(await restOf(tester), isNull);
    });
  });

  group('exercise picker', () {
    testWidgets('adds an exercise with its category', (tester) async {
      await tester.runAsync(seedLive);
      await open(tester);

      await tester.tap(find.text('Add Exercise'));
      await settle(tester);
      await tester.tap(find.text('Back').first);
      await settle(tester);
      await tester.tap(find.text('Barbell Row'));
      await settle(tester);

      final entries = await query(
        tester,
        'exercise_entries',
        where: "workout_id = 'live'",
        orderBy: 'order_index',
      );
      expect(entries.map((e) => e['exercise_id']), ['bench', 'row']);
    });

    testWidgets('tapping an exercise that is already in removes it', (
      tester,
    ) async {
      await tester.runAsync(() => seedLive(exercises: ['bench', 'row']));
      await open(tester);
      expect(find.byType(ExerciseCard), findsNWidgets(2));

      await tester.tap(find.text('Add Exercise'));
      await settle(tester);
      await tester.tap(find.text('Chest').last);
      await settle(tester);
      await tester.tap(find.text('Bench Press').last);
      await settle(tester);

      final entries = await query(tester, 'exercise_entries');
      expect(entries.map((e) => e['exercise_id']), ['row']);
    });
  });

  group('deleting the workout', () {
    testWidgets('asks first and keeps it when declined', (tester) async {
      await tester.runAsync(seedLive);
      final results = await open(tester);

      await openMenu(tester, 'Delete Workout');
      expect(find.text('Are you sure?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle(tester);

      expect(await query(tester, 'workouts'), hasLength(1));
      expect(find.byType(ActiveWorkoutScreen), findsOneWidget);
      expect(results, isEmpty);
    });

    testWidgets('removes the workout and closes the screen', (tester) async {
      await tester.runAsync(seedLive);
      final results = await open(tester);

      await openMenu(tester, 'Delete Workout');
      await tester.tap(find.text('Delete').last);
      await settle(tester, rounds: 8);

      expect(await query(tester, 'workouts'), isEmpty);
      expect(await query(tester, 'exercise_entries'), isEmpty);
      expect(find.byType(ActiveWorkoutScreen), findsNothing);
      expect(results, [true]);
    });
  });
}
