import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/screens/workout/active_workout_screen.dart';
import 'package:workout_notes/screens/workout/future_workout_planner_screen.dart';
import 'package:workout_notes/services/rest_timer_service.dart';

import 'support/strength_home_fixtures.dart'
    show seedRoutine, seedRoutineExercise;
import 'support/strength_workout_seed.dart';
import 'support/test_db.dart';

// A Wednesday far enough ahead to be a "future" workout for any test run.
const _date = '2029-03-14';

/// Opens the planner from a host route and records what it popped with.
class _Host extends StatelessWidget {
  final String workoutId;
  final ValueChanged<Object?> onResult;

  const _Host({required this.workoutId, required this.onResult});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () async {
          final result = await Navigator.push<Object?>(
            context,
            MaterialPageRoute(
              builder: (_) => FutureWorkoutPlannerScreen(workoutId: workoutId),
            ),
          );
          onResult(result);
        },
        child: const Text('open-planner'),
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

  /// Seeds a planned workout with a two-set bench press and one row set.
  Future<void> seedPlanned() => seedWorkout(
    db,
    'plan',
    date: _date,
    finished: false,
    exercises: [
      ('bench', [seedSet(40, 10, warmup: true), seedSet(80, 8, done: false)]),
      ('row', [seedSet(60, 12, done: false)]),
    ],
  );

  /// Pumps a host and opens the planner for [workoutId]; the returned list
  /// collects what the planner popped with.
  Future<List<Object?>> open(
    WidgetTester tester, {
    String workoutId = 'plan',
    String locale = 'en',
  }) async {
    tester.view.physicalSize = const Size(600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // The test font is much wider than a real one: shrink it so popup menu
    // rows fit like they do on a device.
    tester.platformDispatcher.textScaleFactorTestValue = 0.7;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final results = <Object?>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale(locale),
        home: _Host(workoutId: workoutId, onResult: results.add),
      ),
    );
    await tester.tap(find.text('open-planner'));
    await tester.pump();
    await settle(tester);
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

  /// The floating snack bar's action can sit under the bottom buttons of
  /// the planner, so it is pressed through its callback instead of a tap.
  Future<void> pressSnackBarAction(WidgetTester tester) async {
    tester.widget<SnackBarAction>(find.byType(SnackBarAction)).onPressed();
    await settle(tester);
  }

  Future<void> openMenu(WidgetTester tester, String item) async {
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text(item).last);
    await settle(tester, rounds: 4);
  }

  testWidgets('lists the planned exercises, sets and the date', (tester) async {
    await tester.runAsync(seedPlanned);
    await open(tester);

    expect(find.text('March 14'), findsOneWidget);
    expect(find.text('Wednesday, March 14, 2029'), findsOneWidget);
    expect(find.text('2 Exercises'), findsOneWidget);
    expect(find.text('3 Sets'), findsOneWidget);
    expect(find.text('Bench Press'), findsOneWidget);
    expect(find.text('Barbell Row'), findsOneWidget);
    // The warm-up set is marked W and the others numbered by position.
    expect(find.text('W'), findsOneWidget);
    expect(find.text('80.0'), findsOneWidget);
    expect(find.text('60.0'), findsOneWidget);
    expect(find.text('Start this workout'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('is localized in Portuguese', (tester) async {
    Intl.defaultLocale = 'pt';
    await tester.runAsync(seedPlanned);
    await open(tester, locale: 'pt');

    expect(find.text('14 de março'), findsOneWidget);
    expect(find.text('Quarta-feira, 14 de março de 2029'), findsOneWidget);
    expect(find.text('2 Exercícios'), findsOneWidget);
    expect(find.text('3 Séries'), findsOneWidget);
  });

  testWidgets('an empty plan offers adding an exercise or a routine', (
    tester,
  ) async {
    await tester.runAsync(
      () => seedWorkout(db, 'empty', date: _date, finished: false),
    );
    await open(tester, workoutId: 'empty');

    expect(find.text('0 Exercises'), findsOneWidget);
    expect(find.text('Start this workout'), findsNothing);
    expect(find.text('Add Exercise'), findsWidgets);
    expect(find.text('Import from Routine'), findsWidgets);
  });

  testWidgets('a workout that no longer exists closes the screen', (
    tester,
  ) async {
    final results = await open(tester, workoutId: 'ghost');
    expect(find.byType(FutureWorkoutPlannerScreen), findsNothing);
    expect(results, [null]);
  });

  testWidgets('adding a set repeats the last set', (tester) async {
    await tester.runAsync(seedPlanned);
    await open(tester);

    await tester.tap(find.text('Add Set').first);
    await settle(tester);

    final sets = await query(
      tester,
      'sets',
      where: 'exercise_entry_id = ?',
      args: ['plan-e0'],
      orderBy: 'order_index',
    );
    expect(sets, hasLength(3));
    expect(sets.last['weight'], 80);
    expect(sets.last['reps'], 8);
    expect(sets.last['is_warmup'], 0);
    expect(find.text('4 Sets'), findsOneWidget);
  });

  testWidgets('editing a set saves weight, RPE and the warm-up flag', (
    tester,
  ) async {
    await tester.runAsync(seedPlanned);
    await open(tester);

    // Second row of the bench press: the 80 kg x 8 working set.
    await tester.tap(find.text('80.0'));
    await tester.pumpAndSettle();
    expect(find.text('Bench Press · # 2'), findsOneWidget);

    await tester.tap(find.text('8').last); // RPE 8
    await tester.tap(find.byType(Switch).first); // mark as warm-up
    await tester.pump();
    await tester.tap(find.text('Save'));
    await settle(tester);

    final set = (await query(
      tester,
      'sets',
      where: "id = 'plan-e0-s1'",
    )).single;
    expect(set['rpe'], 8);
    expect(set['is_warmup'], 1);
    expect(set['reps'], 8);
    expect(set['weight'], 80);
    // Both bench sets are now warm-ups.
    expect(find.text('W'), findsNWidgets(2));
  });

  testWidgets('cancelling the set editor changes nothing', (tester) async {
    await tester.runAsync(seedPlanned);
    await open(tester);
    final before = await query(tester, 'sets', orderBy: 'id');

    await tester.tap(find.text('80.0'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await settle(tester);

    expect(await query(tester, 'sets', orderBy: 'id'), before);
    expect(find.text('Bench Press · # 2'), findsNothing);
  });

  testWidgets('a deleted set can be restored with undo', (tester) async {
    await tester.runAsync(seedPlanned);
    await open(tester);
    final before = await query(tester, 'sets', orderBy: 'id');

    await tester.tap(find.text('60.0'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete'));
    await settle(tester);

    expect(find.text('Set deleted'), findsOneWidget);
    expect(await query(tester, 'sets'), hasLength(before.length - 1));
    expect(find.text('3 Sets'), findsNothing);
    expect(find.text('2 Sets'), findsOneWidget);

    await pressSnackBarAction(tester);
    await settle(tester);
    expect(await query(tester, 'sets', orderBy: 'id'), before);
    expect(find.text('3 Sets'), findsOneWidget);
  });

  testWidgets('removing an exercise asks first, then offers feedback', (
    tester,
  ) async {
    await tester.runAsync(seedPlanned);
    await open(tester);

    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();
    expect(find.text('Remove Exercise?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await query(tester, 'exercise_entries'), hasLength(2));

    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await settle(tester);

    final entries = await query(tester, 'exercise_entries');
    expect(entries.map((e) => e['exercise_id']), ['row']);
    expect(find.text('Bench Press'), findsNothing);
    expect(find.text('1 Exercises'), findsOneWidget);
  });

  testWidgets('reordering exercises persists the new order', (tester) async {
    await tester.runAsync(seedPlanned);
    await open(tester);

    await tester.drag(
      find.byIcon(Icons.drag_handle).first,
      const Offset(0, 400),
    );
    await settle(tester);

    final entries = await query(
      tester,
      'exercise_entries',
      orderBy: 'order_index',
    );
    expect(entries.map((e) => e['exercise_id']), ['row', 'bench']);
    final names = tester
        .widgetList<Text>(find.textContaining(RegExp(r'^(Bench|Barbell)')))
        .map((t) => t.data)
        .toList();
    expect(names, ['Barbell Row', 'Bench Press']);
  });

  testWidgets('the picker adds an exercise to the workout', (tester) async {
    await tester.runAsync(
      () => seedWorkout(db, 'empty', date: _date, finished: false),
    );
    await open(tester, workoutId: 'empty');

    await tester.tap(find.byIcon(Icons.add).first);
    await settle(tester);
    await tester.tap(find.text('Back').first);
    await settle(tester);
    await tester.tap(find.text('Barbell Row'));
    await settle(tester);

    final entries = await query(tester, 'exercise_entries');
    expect(entries.map((e) => e['exercise_id']), ['row']);
    expect(entries.single['workout_id'], 'empty');
  });

  group('importing a routine day', () {
    testWidgets('without routines says so', (tester) async {
      await tester.runAsync(
        () => seedWorkout(db, 'empty', date: _date, finished: false),
      );
      await tester.runAsync(() => db.delete('routines'));
      await open(tester, workoutId: 'empty');

      await openMenu(tester, 'Import from Routine');
      expect(find.text('No routine found. Create one first!'), findsOneWidget);
    });

    testWidgets('a routine without days says so', (tester) async {
      await tester.runAsync(() async {
        await seedWorkout(db, 'empty', date: _date, finished: false);
        await db.delete('routines');
        await seedRoutine(db, id: 'bare', name: 'Bare', days: const []);
      });
      await open(tester, workoutId: 'empty');

      await openMenu(tester, 'Import from Routine');
      await tester.tap(find.text('Bare'));
      await settle(tester);
      expect(find.text('This routine has no days.'), findsOneWidget);
      expect(await query(tester, 'exercise_entries'), isEmpty);
    });

    testWidgets('picks the routine, then the day, and copies its exercises', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await seedWorkout(db, 'empty', date: _date, finished: false);
        await seedRoutineExercise(
          db,
          id: 'push-bench',
          dayId: 'push',
          exerciseId: 'bench',
          sets: 3,
        );
      });
      await open(tester, workoutId: 'empty');

      await tester.tap(find.text('Import from Routine').first);
      await settle(tester);
      expect(find.text('Push Pull Legs'), findsOneWidget);
      await tester.tap(find.text('Push Pull Legs'));
      await settle(tester);
      expect(find.text('Push A'), findsOneWidget);
      expect(find.text('Pull A'), findsOneWidget);
      await tester.tap(find.text('Push A'));
      await settle(tester);

      final entries = await query(
        tester,
        'exercise_entries',
        where: 'workout_id = ?',
        args: ['empty'],
      );
      expect(entries.map((e) => e['exercise_id']), ['bench']);
      expect(
        await query(
          tester,
          'sets',
          where: 'exercise_entry_id = ?',
          args: [entries.single['id']],
        ),
        hasLength(3),
      );
      expect(find.text('✅ Exercises imported from routine!'), findsOneWidget);
      expect(find.text('Bench Press'), findsOneWidget);
      expect(find.text('3 Sets'), findsOneWidget);
    });

    testWidgets('going back from the day list imports nothing', (tester) async {
      await tester.runAsync(
        () => seedWorkout(db, 'empty', date: _date, finished: false),
      );
      await open(tester, workoutId: 'empty');

      await tester.tap(find.text('Import from Routine').first);
      await settle(tester);
      await tester.tap(find.text('Push Pull Legs'));
      await settle(tester);
      await tester.tap(find.text('Back'));
      await settle(tester);

      expect(find.text('✅ Exercises imported from routine!'), findsNothing);
      expect(await query(tester, 'exercise_entries'), isEmpty);
    });
  });

  testWidgets('the menu deletes the workout after confirming', (tester) async {
    await tester.runAsync(seedPlanned);
    final results = await open(tester);

    await openMenu(tester, 'Delete Workout');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await query(tester, 'workouts'), hasLength(1));

    await openMenu(tester, 'Delete Workout');
    await tester.tap(find.text('Delete'));
    await settle(tester);

    expect(await query(tester, 'workouts'), isEmpty);
    expect(find.byType(FutureWorkoutPlannerScreen), findsNothing);
    expect(results, [true]);
  });

  testWidgets('the menu moves the workout to another date', (tester) async {
    await tester.runAsync(seedPlanned);
    await open(tester);

    await openMenu(tester, 'Change Date');
    await tester.tap(find.text('20'));
    await tester.tap(find.text('OK'));
    await settle(tester);

    expect(find.text('✅ Date changed!'), findsOneWidget);
    final workout = (await query(tester, 'workouts')).single;
    expect(workout['date'], '2029-03-20');
    expect(find.text('March 20'), findsOneWidget);
  });

  testWidgets('a cancelled date picker keeps the date', (tester) async {
    await tester.runAsync(seedPlanned);
    await open(tester);

    await openMenu(tester, 'Change Date');
    await tester.tap(find.text('Cancel'));
    await settle(tester);

    expect((await query(tester, 'workouts')).single['date'], _date);
    expect(find.text('✅ Date changed!'), findsNothing);
  });

  testWidgets('copying a workout creates it on the chosen date', (
    tester,
  ) async {
    await tester.runAsync(seedPlanned);
    await open(tester);

    await openMenu(tester, 'Copy Workout');
    await tester.tap(find.text('21'));
    await tester.tap(find.text('OK'));
    await settle(tester);

    final workouts = await query(tester, 'workouts', orderBy: 'date');
    expect(workouts.map((w) => w['date']), [_date, '2029-03-21']);
    final copyId = workouts.last['id'] as String;
    final copied = await query(
      tester,
      'exercise_entries',
      where: 'workout_id = ?',
      args: [copyId],
    );
    expect(copied, hasLength(2));

    // The snackbar jumps to the copy, which replaces this screen.
    await pressSnackBarAction(tester);
    await settle(tester);
    expect(find.text('March 21'), findsOneWidget);
    expect(find.text('2 Exercises'), findsOneWidget);
  });

  testWidgets('start workout opens the active workout screen', (tester) async {
    await tester.runAsync(seedPlanned);
    await open(tester);

    await tester.tap(find.text('Start this workout'));
    await settle(tester, rounds: 8);

    expect(find.byType(ActiveWorkoutScreen), findsOneWidget);
    expect(find.text('Bench Press'), findsOneWidget);
    RestTimerService.instance.stop();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
