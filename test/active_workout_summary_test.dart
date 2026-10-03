import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/exercise_with_sets.dart';
import 'package:workout_notes/models/strength_workout_summary.dart';
import 'package:workout_notes/repositories/workout_repository.dart';
import 'package:workout_notes/screens/workout/active_workout_screen.dart';
import 'package:workout_notes/widgets/strength/workout/active_workout_header.dart';
import 'package:workout_notes/widgets/workout/finish_workout_sheet.dart';

import 'support/ai_test_db.dart';
import 'support/strength_home_fixtures.dart'
    show seedRoutine, seedRoutineExercise;
import 'support/strength_workout_seed.dart';

Widget _app(Widget home) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
    child: child!,
  ),
  home: Scaffold(body: home),
);

void main() {
  setUpAll(() => Intl.defaultLocale = 'en');
  tearDownAll(() => Intl.defaultLocale = null);

  group('FinishWorkoutSheet', () {
    testWidgets('lists the records of the session with what they beat', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _app(
          const FinishWorkoutSheet(
            summary: WorkoutSummary(
              durationSeconds: 3900,
              totalVolume: 4300,
              totalSets: 10,
              completedSets: 9,
              prs: [
                PR(
                  exerciseName: 'Bench Press',
                  type: 'e1rm',
                  value: '120 kg (105 kg × 5)',
                  previous: '116.7 kg',
                ),
                PR(
                  exerciseName: 'Bench Press',
                  type: 'volume',
                  value: '1.1 t',
                  previous: '1 t',
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('2 personal records'), findsOneWidget);
      expect(find.text('NEW PERSONAL RECORDS'), findsOneWidget);
      expect(find.text('Estimated 1RM · 120 kg (105 kg × 5)'), findsOneWidget);
      expect(find.text('Previous: 116.7 kg'), findsOneWidget);
      expect(find.text('Session volume · 1.1 t'), findsOneWidget);
      // Volume of the summary in tonnes, working sets done/planned.
      expect(find.text('4.3 t'), findsOneWidget);
      expect(find.text('9/10'), findsOneWidget);
    });

    testWidgets('without records shows the plain subtitle', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _app(
          const FinishWorkoutSheet(
            summary: WorkoutSummary(
              durationSeconds: 600,
              totalVolume: 500,
              totalSets: 2,
              completedSets: 2,
            ),
          ),
        ),
      );
      expect(find.text('NEW PERSONAL RECORDS'), findsNothing);
      expect(find.text('Great job! Here\'s the summary:'), findsOneWidget);
      expect(find.text('500 kg'), findsOneWidget);
    });
  });

  group('ActiveWorkoutHeader', () {
    Widget header({
      ActiveWorkoutTimerPhase phase = ActiveWorkoutTimerPhase.running,
      bool expanded = false,
      VoidCallback? onPause,
    }) => _app(
      ActiveWorkoutHeader(
        phase: phase,
        elapsed: ValueNotifier('12:34'),
        startedAt: DateTime(2026, 9, 1, 18, 5),
        endedAt: null,
        onStart: () {},
        onPause: onPause ?? () {},
        onResume: () {},
        completedSets: 3,
        totalSets: 8,
        volume: 4200,
        categories: const [
          CategoryVolumeComparison(
            categoryId: '',
            categoryName: 'Chest',
            categoryColor: Colors.red,
            currentVolume: 2000,
            lastVolume: 1500,
          ),
        ],
        expanded: expanded,
        onToggleExpanded: () {},
      ),
    );

    testWidgets('shows timer, sets done and live volume', (tester) async {
      var paused = false;
      await tester.pumpWidget(header(onPause: () => paused = true));
      // Ring with sets done, the clock, and its status with live volume.
      expect(find.text('3/8'), findsOneWidget);
      expect(find.text('12:34'), findsOneWidget);
      expect(find.textContaining('Started at 18:05'), findsOneWidget);
      expect(find.textContaining('4.2 t'), findsOneWidget);
      await tester.tap(find.byTooltip('Pause'));
      expect(paused, isTrue);
    });

    testWidgets('paused shows the pill and a resume action', (tester) async {
      await tester.pumpWidget(header(phase: ActiveWorkoutTimerPhase.paused));
      expect(find.textContaining('PAUSED'), findsOneWidget);
      expect(find.byTooltip('Resume'), findsOneWidget);
    });

    testWidgets('expanded reveals the per-muscle comparison', (tester) async {
      await tester.pumpWidget(header());
      expect(find.text('By muscle group'), findsNothing);
      await tester.pumpWidget(header(expanded: true));
      await tester.pumpAndSettle();
      expect(find.text('By muscle group'), findsOneWidget);
      expect(find.text('+500 kg (+33%)'), findsOneWidget);
    });
  });

  group('ActiveWorkoutScreen blank workouts', () {
    late Database db;

    setUp(() async {
      db = await installAiTestDb();
      await seedStrengthBasics(db);
    });

    tearDown(uninstallAiTestDb);

    Future<void> openAndLeave(
      WidgetTester tester, {
      Future<void> Function()? whileOpen,
      ActiveWorkoutScreen screen = const ActiveWorkoutScreen(),
    }) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => screen),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
        await whileOpen?.call();
        final navigator = tester.state<NavigatorState>(find.byType(Navigator));
        navigator.pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 500));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
    }

    Future<int> workoutCount() async =>
        (await db.rawQuery('SELECT COUNT(*) AS n FROM workouts')).first['n']
            as int;

    testWidgets('leaving a blank workout leaves no row behind', (tester) async {
      var duringVisit = -1;
      await openAndLeave(
        tester,
        whileOpen: () async => duringVisit = await workoutCount(),
      );
      expect(duringVisit, 1);
      expect(await tester.runAsync(workoutCount), 0);
    });

    Future<void> seedPushDay() async {
      await seedRoutine(
        db,
        id: 'draft-routine',
        name: 'PPL',
        days: [(id: 'draft-day', name: 'Push')],
      );
      await seedRoutineExercise(
        db,
        id: 'draft-bench',
        dayId: 'draft-day',
        exerciseId: 'bench',
      );
    }

    testWidgets('an untouched routine preview is discarded on leave', (
      tester,
    ) async {
      await tester.runAsync(seedPushDay);
      var duringVisit = -1;
      await openAndLeave(
        tester,
        screen: const ActiveWorkoutScreen(
          routineId: 'draft-routine',
          routineDayId: 'draft-day',
        ),
        whileOpen: () async => duringVisit = await workoutCount(),
      );
      expect(duringVisit, 1);
      expect(await tester.runAsync(workoutCount), 0);
    });

    testWidgets('a routine workout with a completed set is kept', (
      tester,
    ) async {
      await tester.runAsync(seedPushDay);
      await openAndLeave(
        tester,
        screen: const ActiveWorkoutScreen(
          routineId: 'draft-routine',
          routineDayId: 'draft-day',
        ),
        whileOpen: () async => db.rawUpdate(
          'UPDATE sets SET is_complete = 1 WHERE id = '
          '(SELECT id FROM sets LIMIT 1)',
        ),
      );
      expect(await tester.runAsync(workoutCount), 1);
    });

    testWidgets('a new workout starts empty and only suggests the day', (
      tester,
    ) async {
      await tester.runAsync(seedPushDay);
      var entriesBefore = -1;
      var entriesAfter = -1;
      Future<int> entryCount() async =>
          (await db.rawQuery(
                'SELECT COUNT(*) AS n FROM exercise_entries',
              )).first['n']
              as int;
      await openAndLeave(
        tester,
        screen: const ActiveWorkoutScreen(
          suggestedDay: StrengthRoutineDayInfo(
            routineId: 'draft-routine',
            routineName: 'PPL',
            routineDayId: 'draft-day',
            dayName: 'Push',
            exerciseCount: 1,
            categories: [],
            estimatedSeconds: 0,
          ),
        ),
        whileOpen: () async {
          entriesBefore = await entryCount();
          await tester.pump();
          expect(
            find.byKey(const Key('active-workout-suggestion')),
            findsOneWidget,
          );
          await tester.tap(
            find.byKey(const Key('active-workout-use-suggestion')),
          );
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 300));
          await tester.pump();
          entriesAfter = await entryCount();
        },
      );
      expect(entriesBefore, 0);
      expect(entriesAfter, 1);
      // Picked but never started: still only a preview.
      expect(await tester.runAsync(workoutCount), 0);
    });

    testWidgets('a workout with an exercise is kept', (tester) async {
      await openAndLeave(
        tester,
        whileOpen: () async {
          final id =
              (await db.query('workouts', columns: ['id'])).single['id']
                  as String;
          await WorkoutRepository().addExerciseToWorkout(id, 'bench');
        },
      );
      // The screen still believes it is blank (its list was not reloaded);
      // the repository check protects the row.
      expect(await tester.runAsync(workoutCount), 1);
    });

    testWidgets('starting a new workout clears older blank leftovers', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await db.insert('workouts', {
          'id': 'orphan',
          'date': '2026-01-01',
          'created_at': '2026-01-01T10:00:00.000',
        });
        await seedWorkout(
          db,
          'done',
          date: '2026-01-02',
          exercises: [
            ('bench', [seedSet(100, 5)]),
          ],
        );
      });
      await openAndLeave(tester);
      final ids = (await tester.runAsync(
        () => db.query('workouts', columns: ['id']),
      ))!.map((r) => r['id']);
      expect(ids, ['done']);
    });
  });
}
