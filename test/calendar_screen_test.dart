import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/screens/workout/calendar_screen.dart';
import 'package:workout_notes/screens/workout/future_workout_planner_screen.dart';
import 'package:workout_notes/screens/workout/workout_detail_screen.dart';
import 'package:workout_notes/utils/date_utils.dart';

import 'support/strength_home_fixtures.dart'
    show seedRoutine, seedRoutineExercise;
import 'support/strength_workout_seed.dart';
import 'support/test_db.dart';

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

  // The screen opens on the real current month and day.
  final today = dayOf(DateTime.now());
  final tomorrow = addDays(today, 1);
  final previousMonth = DateTime(today.year, today.month - 1, 15);
  final nextMonth = DateTime(today.year, today.month + 1, 15);
  // Another day of the current month (never today).
  final otherDay = DateTime(today.year, today.month, today.day == 1 ? 2 : 1);

  Future<void> settle(WidgetTester tester, {int rounds = 6}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpCalendar(WidgetTester tester, {String locale = 'en'}) async {
    tester.view.physicalSize = const Size(700, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // The test font is far wider than a real one; keep the grid readable.
    tester.platformDispatcher.textScaleFactorTestValue = 0.7;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale(locale),
        home: const CalendarScreen(),
      ),
    );
    await tester.pump();
    await settle(tester);
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

  /// A completed run that started at 07:30 on [date].
  Future<void> insertRun(
    String id,
    DateTime date, {
    String? title,
    String type = 'running',
    double meters = 5000,
    int seconds = 1500,
  }) {
    final startedAt = DateTime(date.year, date.month, date.day, 7, 30);
    return db.insert('run_activities', {
      'id': id,
      'activity_type': type,
      'started_at': startedAt.toIso8601String(),
      'duration_seconds': seconds,
      'moving_time_seconds': seconds,
      'distance_meters': meters,
      'title': title,
      'status': 'completed',
      'created_at': startedAt.toIso8601String(),
      'updated_at': startedAt.toIso8601String(),
    });
  }

  /// A plan with two named sessions, [easy] (id `w-easy`) and [long]
  /// (`w-long`); `w-tempo` carries steps so its card shows the profile bar.
  Future<void> insertPlan() async {
    const created = '2026-01-01T00:00:00';
    await db.insert('run_plans', {
      'id': 'plan',
      'name': 'Plan 10K',
      'goal_kind': '10k',
      'weeks': 4,
      'status': 'active',
      'created_at': created,
      'updated_at': created,
    });
    for (final (id, kind, name, meters) in [
      ('w-easy', 'easy', 'Easy run', 5000.0),
      ('w-long', 'long', 'Long run', 12000.0),
      ('w-tempo', 'interval', 'Intervals', null),
    ]) {
      await db.insert('run_plan_workouts', {
        'id': id,
        'run_plan_id': 'plan',
        'week_index': 0,
        'kind': kind,
        'name': name,
        'target_distance_meters': meters,
        'created_at': created,
      });
    }
    for (final (index, role, value, group, count) in [
      (0, 'warmup', 600, null, 1),
      (1, 'work', 400, 1, 4),
      (2, 'recovery', 200, 1, 4),
      (3, 'cooldown', 600, null, 1),
    ]) {
      await db.insert('run_workout_steps', {
        'id': 'step$index',
        'run_plan_workout_id': 'w-tempo',
        'order_index': index,
        'role': role,
        'metric': 'distance',
        'value': value,
        'repeat_group': group,
        'repeat_count': count,
      });
    }
  }

  Future<void> schedule(
    String id,
    DateTime date, {
    String? workoutId,
    String status = 'planned',
  }) => db.insert('scheduled_runs', {
    'id': id,
    'date': dateKey(date),
    'run_plan_id': workoutId == null ? null : 'plan',
    'run_plan_workout_id': workoutId,
    'status': status,
    'created_at': '2026-01-01T00:00:00',
    'updated_at': '2026-01-01T00:00:00',
  });

  Finder day(DateTime date) => find.descendant(
    of: find.byType(GridView),
    matching: find.text('${date.day}'),
  );

  Future<void> selectDay(WidgetTester tester, DateTime date) async {
    await tester.tap(day(date));
    await tester.pump();
  }

  Future<void> goToMonth(WidgetTester tester, {required bool next}) async {
    await tester.tap(find.byTooltip(next ? 'Next month' : 'Previous month'));
    await settle(tester);
  }

  testWidgets('shows the month, the legend and today\'s activities', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await seedWorkout(
        db,
        'w-today',
        date: dateKey(today),
        exercises: [
          ('bench', [seedSet(80, 8)]),
          ('row', [seedSet(60, 8)]),
        ],
      );
      await insertRun('run-today', today, title: 'Morning jog');
      await insertPlan();
      await schedule('planned-today', today, workoutId: 'w-easy');
    });
    await pumpCalendar(tester);

    final month = DateFormat('MMMM yyyy', 'en_US').format(today);
    expect(find.text('History'), findsOneWidget);
    expect(find.text(month), findsOneWidget);
    for (final weekday in ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']) {
      expect(find.text(weekday), findsOneWidget);
    }
    // The legend explains the markers on the grid.
    expect(find.text('Workout'), findsOneWidget);
    expect(find.text('Completed run'), findsOneWidget);
    expect(find.text('Planned run'), findsOneWidget);

    // Today's list: planned run, completed run and the workout.
    expect(find.text('Easy run'), findsOneWidget);
    expect(find.textContaining('Planned · '), findsOneWidget);
    expect(find.text('Morning jog'), findsOneWidget);
    expect(find.text('5.0 km · 25 min'), findsOneWidget);
    expect(find.text('60min'), findsOneWidget);
    expect(find.textContaining('6:00'), findsOneWidget);
    expect(find.textContaining('No workouts on'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('day cells announce what happened on them', (tester) async {
    await tester.runAsync(() async {
      await seedWorkout(
        db,
        'w-today',
        date: dateKey(today),
        exercises: [
          ('bench', [seedSet(80, 8)]),
        ],
      );
      await insertRun('run-today', today);
      await insertPlan();
      await schedule('planned-today', today, workoutId: 'w-easy');
    });
    await pumpCalendar(tester);

    final label = DateFormat.yMMMMd('en_US').format(today);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label ==
                '$label, Workout, Completed run, Planned run' &&
            widget.properties.selected == true,
      ),
      findsOneWidget,
    );
    final plainDay = DateFormat.yMMMMd('en_US').format(otherDay);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == plainDay &&
            widget.properties.selected == false,
      ),
      findsOneWidget,
    );
  });

  testWidgets('an empty day shows the empty state and selecting a day swaps '
      'the list', (tester) async {
    await tester.runAsync(
      () => seedWorkout(
        db,
        'w-open',
        date: dateKey(otherDay),
        finished: false,
        exercises: [
          ('bench', [seedSet(80, 8, done: false)]),
        ],
      ),
    );
    await pumpCalendar(tester);

    expect(find.textContaining('No workouts on'), findsOneWidget);
    expect(find.text('Create Workout'), findsOneWidget);
    expect(find.text('Import from Routine'), findsOneWidget);

    await selectDay(tester, otherDay);
    expect(find.textContaining('No workouts on'), findsNothing);
    expect(find.text('In progress'), findsOneWidget);

    await selectDay(tester, today);
    expect(find.textContaining('No workouts on'), findsOneWidget);
  });

  testWidgets('is localized in Portuguese', (tester) async {
    Intl.defaultLocale = 'pt';
    await pumpCalendar(tester, locale: 'pt');

    final month = DateFormat('MMMM yyyy', 'pt_BR').format(today);
    expect(
      find.text(month[0].toUpperCase() + month.substring(1)),
      findsOneWidget,
    );
    expect(find.text('Histórico'), findsOneWidget);
    expect(find.text('Dom'), findsOneWidget);
    expect(find.text('Sáb'), findsOneWidget);
    expect(find.text('Corrida concluída'), findsOneWidget);
    expect(find.text('Criar Treino'), findsOneWidget);
    expect(find.textContaining('Nenhum treino em'), findsOneWidget);
  });

  testWidgets('month arrows load the other months, across year ends too', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await seedWorkout(
        db,
        'w-prev',
        date: dateKey(previousMonth),
        exercises: [
          ('bench', [seedSet(80, 8)]),
        ],
      );
      await seedWorkout(
        db,
        'w-next',
        date: dateKey(nextMonth),
        finished: false,
        exercises: [
          ('row', [seedSet(60, 8, done: false)]),
        ],
      );
    });
    await pumpCalendar(tester);

    await goToMonth(tester, next: false);
    expect(
      find.text(DateFormat('MMMM yyyy', 'en_US').format(previousMonth)),
      findsOneWidget,
    );
    // Cells carry the workout marker: its category dot has a Semantics label.
    final label = DateFormat.yMMMMd('en_US').format(previousMonth);
    expect(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == '$label, Workout',
      ),
      findsOneWidget,
    );

    await goToMonth(tester, next: true);
    await goToMonth(tester, next: true);
    expect(
      find.text(DateFormat('MMMM yyyy', 'en_US').format(nextMonth)),
      findsOneWidget,
    );

    // Twelve more arrows around the year end keep month and year in step.
    for (var i = 0; i < 12; i++) {
      await goToMonth(tester, next: true);
    }
    expect(
      find.text(
        DateFormat(
          'MMMM yyyy',
          'en_US',
        ).format(DateTime(nextMonth.year + 1, nextMonth.month)),
      ),
      findsOneWidget,
    );
    for (var i = 0; i < 14; i++) {
      await goToMonth(tester, next: false);
    }
    expect(
      find.text(DateFormat('MMMM yyyy', 'en_US').format(previousMonth)),
      findsOneWidget,
    );
  });

  testWidgets('a past workout opens its detail, a future one the planner', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await seedWorkout(
        db,
        'w-prev',
        date: dateKey(previousMonth),
        exercises: [
          ('bench', [seedSet(80, 8)]),
        ],
      );
      await seedWorkout(
        db,
        'w-next',
        date: dateKey(nextMonth),
        finished: false,
        exercises: [
          ('row', [seedSet(60, 8, done: false)]),
        ],
      );
    });
    await pumpCalendar(tester);

    await goToMonth(tester, next: false);
    await selectDay(tester, previousMonth);
    await tester.tap(find.byIcon(Icons.fitness_center).last);
    await settle(tester);
    expect(find.byType(WorkoutDetailScreen), findsOneWidget);
    await tester.pageBack();
    await settle(tester);

    await goToMonth(tester, next: true);
    await goToMonth(tester, next: true);
    await selectDay(tester, nextMonth);
    await tester.tap(find.byIcon(Icons.fitness_center).last);
    await settle(tester);
    expect(find.byType(FutureWorkoutPlannerScreen), findsOneWidget);
    expect(find.text('Barbell Row'), findsOneWidget);

    // Deleting the planned workout there returns here and refreshes.
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete Workout').last);
    await settle(tester, rounds: 4);
    await tester.tap(find.text('Delete').last);
    await settle(tester, rounds: 8);
    expect(find.byType(FutureWorkoutPlannerScreen), findsNothing);
    expect(await query(tester, 'workouts', where: "id = 'w-next'"), isEmpty);
    expect(find.textContaining('No workouts on'), findsOneWidget);
  });

  testWidgets('creating a workout for the selected day', (tester) async {
    await pumpCalendar(tester);

    await tester.tap(find.text('Create Workout'));
    await settle(tester);

    final workouts = await query(tester, 'workouts');
    expect(workouts, hasLength(1));
    expect(workouts.single['date'], dateKey(today));
    expect(find.text('✅ Workout created for this day!'), findsOneWidget);
    // The month reloaded: the new workout is listed (still in progress).
    expect(find.text('In progress'), findsOneWidget);
  });

  group('import from routine', () {
    testWidgets('without routines says so', (tester) async {
      await tester.runAsync(() => db.delete('routines'));
      await pumpCalendar(tester);

      await tester.tap(find.text('Import from Routine'));
      await settle(tester);
      expect(find.text('No routine found. Create one first!'), findsOneWidget);
      expect(await query(tester, 'workouts'), isEmpty);
    });

    testWidgets('a routine without days says so', (tester) async {
      await tester.runAsync(() async {
        await db.delete('routines');
        await seedRoutine(db, id: 'bare', name: 'Bare', days: const []);
      });
      await pumpCalendar(tester);

      await tester.tap(find.text('Import from Routine'));
      await settle(tester);
      await tester.tap(find.text('Bare'));
      await settle(tester);
      expect(find.text('This routine has no days.'), findsOneWidget);
      expect(await query(tester, 'workouts'), isEmpty);
    });

    testWidgets('creates the workout with the chosen day\'s exercises', (
      tester,
    ) async {
      await tester.runAsync(
        () => seedRoutineExercise(
          db,
          id: 'push-bench',
          dayId: 'push',
          exerciseId: 'bench',
          sets: 2,
        ),
      );
      await pumpCalendar(tester);

      await tester.tap(find.text('Import from Routine'));
      await settle(tester);
      expect(find.text('Select Routine'), findsOneWidget);
      await tester.tap(find.text('Push Pull Legs'));
      await settle(tester);
      expect(find.text('Push A'), findsOneWidget);
      await tester.tap(find.text('Push A'));
      await settle(tester);

      final workouts = await query(tester, 'workouts');
      expect(workouts.single['date'], dateKey(today));
      final entries = await query(
        tester,
        'exercise_entries',
        where: 'workout_id = ?',
        args: [workouts.single['id']],
      );
      expect(entries.map((e) => e['exercise_id']), ['bench']);
      expect(await query(tester, 'sets'), hasLength(2));
      expect(find.text('✅ Exercises imported from routine!'), findsOneWidget);
    });

    testWidgets('backing out of the day list creates nothing', (tester) async {
      await pumpCalendar(tester);

      await tester.tap(find.text('Import from Routine'));
      await settle(tester);
      await tester.tap(find.text('Push Pull Legs'));
      await settle(tester);
      await tester.tap(find.text('Back'));
      await settle(tester);
      expect(await query(tester, 'workouts'), isEmpty);
    });
  });

  group('planned runs', () {
    Future<void> openRunMenu(WidgetTester tester) async {
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
    }

    testWidgets('a planned session shows its summary and step profile', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await insertPlan();
        await schedule('a', today, workoutId: 'w-tempo');
        await schedule('b', today, status: 'completed');
      });
      await pumpCalendar(tester);

      expect(find.text('Intervals'), findsOneWidget);
      expect(find.textContaining('Planned · '), findsOneWidget);
      // A completed schedule row is covered by its activity, not listed.
      expect(find.text('Planned runs'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('a session without a plan uses the generic title', (
      tester,
    ) async {
      await tester.runAsync(() => schedule('loose', today));
      await pumpCalendar(tester);
      expect(find.text('Planned runs'), findsOneWidget);
      expect(find.text('Planned'), findsOneWidget);
    });

    testWidgets('marking a run as skipped keeps it but stops offering it', (
      tester,
    ) async {
      await tester.runAsync(() => schedule('loose', today));
      await pumpCalendar(tester);

      await openRunMenu(tester);
      expect(find.text('Change date'), findsOneWidget);
      await tester.tap(find.text('Mark as skipped'));
      await settle(tester);

      expect(
        (await query(tester, 'scheduled_runs')).single['status'],
        'skipped',
      );
      expect(find.text('Skipped'), findsOneWidget);
      await openRunMenu(tester);
      expect(find.text('Mark as skipped'), findsNothing);
      expect(find.text('Change date'), findsNothing);
      expect(find.text('Remove from schedule'), findsOneWidget);
    });

    testWidgets('removing a run takes it off the schedule', (tester) async {
      await tester.runAsync(() => schedule('loose', today));
      await pumpCalendar(tester);

      await openRunMenu(tester);
      await tester.tap(find.text('Remove from schedule'));
      await settle(tester);

      expect(await query(tester, 'scheduled_runs'), isEmpty);
      expect(find.textContaining('No workouts on'), findsOneWidget);
    });

    /// Opens the date picker of the run's menu and picks [date].
    Future<void> pickDate(WidgetTester tester, DateTime date) async {
      await openRunMenu(tester);
      await tester.tap(find.text('Change date'));
      await tester.pumpAndSettle();
      if (date.month != today.month) {
        await tester.tap(find.byTooltip('Next month'));
        await tester.pumpAndSettle();
      }
      await tester.tap(
        find.descendant(
          of: find.byType(DatePickerDialog),
          matching: find.text('${date.day}'),
        ),
      );
      await tester.tap(find.text('OK'));
      await settle(tester);
    }

    testWidgets('changing the date moves the run when the week stays '
        'balanced', (tester) async {
      await tester.runAsync(() => schedule('loose', today));
      await pumpCalendar(tester);

      await pickDate(tester, tomorrow);

      expect(
        (await query(tester, 'scheduled_runs')).single['date'],
        dateKey(tomorrow),
      );
      expect(find.textContaining('Moved to '), findsOneWidget);
    });

    testWidgets('cancelling the date picker moves nothing', (tester) async {
      await tester.runAsync(() => schedule('loose', today));
      await pumpCalendar(tester);

      await openRunMenu(tester);
      await tester.tap(find.text('Change date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await settle(tester);

      expect(
        (await query(tester, 'scheduled_runs')).single['date'],
        dateKey(today),
      );
      expect(find.textContaining('Moved to '), findsNothing);
    });

    testWidgets('moving onto a day that already has a run asks, then swaps', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await insertPlan();
        await schedule('easy', today, workoutId: 'w-easy');
        await schedule('long', tomorrow, workoutId: 'w-long');
      });
      await pumpCalendar(tester);

      await pickDate(tester, tomorrow);
      expect(find.text('This leaves the week unbalanced'), findsOneWidget);
      expect(find.text('Long run is already on that day.'), findsOneWidget);
      await tester.tap(find.text('Swap with Long run'));
      await settle(tester);

      final rows = await query(tester, 'scheduled_runs', orderBy: 'id');
      expect(
        {for (final r in rows) r['id']: r['date']},
        {'easy': dateKey(tomorrow), 'long': dateKey(today)},
      );
      expect(find.textContaining('Moved to '), findsOneWidget);
    });

    testWidgets('declining the balance advice leaves everything in place', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await insertPlan();
        await schedule('easy', today, workoutId: 'w-easy');
        await schedule('long', tomorrow, workoutId: 'w-long');
      });
      await pumpCalendar(tester);

      await pickDate(tester, tomorrow);
      await tester.tap(find.text('Cancel'));
      await settle(tester);

      final rows = await query(tester, 'scheduled_runs', orderBy: 'id');
      expect(
        {for (final r in rows) r['id']: r['date']},
        {'easy': dateKey(today), 'long': dateKey(tomorrow)},
      );
    });

    testWidgets('"move anyway" overrides the advice', (tester) async {
      await tester.runAsync(() async {
        await insertPlan();
        await schedule('easy', today, workoutId: 'w-easy');
        await schedule('long', tomorrow, workoutId: 'w-long');
      });
      await pumpCalendar(tester);

      await pickDate(tester, tomorrow);
      await tester.tap(find.text('Move anyway'));
      await settle(tester);

      final rows = await query(tester, 'scheduled_runs', orderBy: 'id');
      expect(
        {for (final r in rows) r['id']: r['date']},
        {'easy': dateKey(tomorrow), 'long': dateKey(tomorrow)},
      );
    });
  });

  testWidgets('completed runs list their title or the activity kind', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await insertRun('titled', today, title: 'Parkrun');
      await insertRun('bike', today, type: 'stationary_bike', meters: 0);
    });
    await pumpCalendar(tester);

    expect(find.text('Parkrun'), findsOneWidget);
    expect(find.text('Stationary bike'), findsOneWidget);
    expect(find.byIcon(Icons.pedal_bike_rounded), findsOneWidget);
  });

  testWidgets('a failed load shows an error that retry recovers from', (
    tester,
  ) async {
    await tester.runAsync(
      () => db.execute('ALTER TABLE scheduled_runs RENAME TO scheduled_x'),
    );
    await pumpCalendar(tester);

    expect(find.text('Could not load your data.'), findsOneWidget);
    expect(find.text('Create Workout'), findsNothing);

    await tester.runAsync(
      () => db.execute('ALTER TABLE scheduled_x RENAME TO scheduled_runs'),
    );
    await tester.tap(find.byKey(const Key('load-error-retry')));
    await settle(tester);
    expect(find.text('Could not load your data.'), findsNothing);
    expect(find.text('Create Workout'), findsOneWidget);
  });
}
