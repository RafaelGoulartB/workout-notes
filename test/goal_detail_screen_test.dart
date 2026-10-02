import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/models/goal.dart';
import 'package:workout_notes/screens/goals/goal_detail_screen.dart';
import 'package:workout_notes/screens/workout/workout_detail_screen.dart';
import 'package:workout_notes/utils/date_utils.dart';

import 'support/goals_ui_support.dart';
import 'support/test_db.dart';

void main() {
  late DatabaseHelper helper;
  final today = dayOf(DateTime.now());
  final todayKey = dateKey(today);
  // Seven days back is always inside the previous Monday-to-Sunday week.
  final lastWeekKey = dateKey(addDays(today, -7));

  setUpAll(() async {
    initSqfliteFfiForTests();
    await initDateSymbolsForTests();
  });

  setUp(() async {
    await installTestDb();
    helper = DatabaseHelper.instance;
  });
  tearDown(uninstallTestDb);

  Future<void> seed(WidgetTester tester, List<Goal> goals) async {
    await tester.runAsync(() async {
      await seedGoalExercises(await helper.database);
      for (final goal in goals) {
        await helper.goalRepo.insert(goal);
      }
    });
  }

  /// Opens the detail screen on top of a home page so that popping (after a
  /// delete) is observable.
  Future<void> openDetail(
    WidgetTester tester,
    Goal goal, {
    Locale locale = const Locale('en'),
  }) async {
    useLogicalViewSize(tester, const Size(500, 1800));
    await tester.pumpWidget(
      goalsApp(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => GoalDetailScreen(goal: goal, db: helper),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
        locale: locale,
      ),
    );
    await tester.tap(find.text('open'));
    await settleDb(tester);
  }

  Future<void> seedWorkout(
    WidgetTester tester, {
    required String id,
    required String date,
    String exercise = 'bench',
    double weight = 100,
    int reps = 10,
    double? distance,
    int? seconds,
  }) async {
    await tester.runAsync(() async {
      await seedFinishedWorkout(
        await helper.database,
        id: id,
        date: date,
        exerciseId: exercise,
        weight: weight,
        reps: reps,
        distance: distance,
        seconds: seconds,
      );
    });
  }

  group('in progress', () {
    final goal = sampleGoal(title: 'Bench volume', target: 2000);

    Future<void> openWithData(WidgetTester tester) async {
      await seed(tester, [goal]);
      await seedWorkout(tester, id: 'now', date: todayKey);
      await seedWorkout(tester, id: 'before', date: lastWeekKey, weight: 250);
      await openDetail(tester, goal);
    }

    testWidgets('shows the hero, pace, contributors and history', (
      tester,
    ) async {
      await openWithData(tester);

      expect(find.text('Bench volume'), findsOneWidget);
      // Hero.
      expect(find.text('Volume · Weekly · Strength'), findsOneWidget);
      expect(find.text('In progress'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
      expect(find.text('Current progress'), findsOneWidget);
      expect(find.text('1.0t / 2.0t'), findsOneWidget);
      expect(find.textContaining('Day '), findsOneWidget);
      // 50 % lands in the "on track" motivation band.
      expect(find.text('On track. Keep going!'), findsOneWidget);
      // Pace card: 1000 kg to go, a projection and a per-day need.
      expect(find.text('GOAL PACE'), findsOneWidget);
      expect(find.text('To go'), findsOneWidget);
      expect(find.text('Needed / day'), findsOneWidget);
      expect(find.text('Projection'), findsOneWidget);
      // Contributors: only today's workout is in this week.
      expect(find.text('WORKOUTS THIS PERIOD'), findsOneWidget);
      expect(find.text('1 set'), findsOneWidget);
      expect(find.text('1.0t'), findsWidgets);
      // History: six past weeks, one of them reached (2500 of 2000).
      expect(find.text('HISTORY'), findsOneWidget);
      expect(find.text('17% success'), findsOneWidget);
      expect(find.text('1 period streak'), findsOneWidget);
      expect(find.text('2.5t / 2.0t'), findsOneWidget);
      expect(find.text('125%'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsNWidgets(5));
    });

    testWidgets('tapping a contributing workout opens it', (tester) async {
      await openWithData(tester);

      await tester.tap(find.text('1 set'));
      await settleDb(tester);

      expect(find.byType(WorkoutDetailScreen), findsOneWidget);
    });

    testWidgets('pausing and resuming toggles the badge and persists', (
      tester,
    ) async {
      await openWithData(tester);
      expect(find.byTooltip('Pause'), findsOneWidget);

      await tester.tap(find.byTooltip('Pause'));
      await settleDb(tester);

      expect(find.byTooltip('Resume'), findsOneWidget);
      expect(find.text('PAUSED'), findsOneWidget);
      expect(find.text('In progress'), findsNothing);
      var stored = await tester.runAsync(() => helper.goalRepo.getById('g1'));
      expect(stored!.isActive, isFalse);

      await tester.tap(find.byTooltip('Resume'));
      await settleDb(tester);

      expect(find.text('PAUSED'), findsNothing);
      expect(find.text('In progress'), findsOneWidget);
      stored = await tester.runAsync(() => helper.goalRepo.getById('g1'));
      expect(stored!.isActive, isTrue);
    });

    testWidgets('editing saves the goal and refreshes the screen', (
      tester,
    ) async {
      await openWithData(tester);

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit Goal'));
      await settleDb(tester);

      expect(find.text('2000'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Title (optional)'),
        'Heavier bench',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Target value'),
        '1000',
      );
      await tester.tap(find.text('Save'));
      await settleDb(tester);

      expect(find.text('Goal saved'), findsOneWidget);
      expect(find.text('Heavier bench'), findsOneWidget);
      // 1000 of 1000 reached: the goal is now achieved.
      expect(find.text('Achieved'), findsWidgets);
      final stored = await tester.runAsync(() => helper.goalRepo.getById('g1'));
      expect(stored!.title, 'Heavier bench');
      expect(stored.targetValue, 1000);
    });

    testWidgets('cancelling the edit sheet changes nothing', (tester) async {
      await openWithData(tester);

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit Goal'));
      await settleDb(tester);
      await tester.tap(find.text('Cancel'));
      await settleDb(tester);

      expect(find.text('Goal saved'), findsNothing);
      expect(find.text('Bench volume'), findsOneWidget);
    });

    testWidgets('deleting asks first, then removes the goal and leaves', (
      tester,
    ) async {
      await openWithData(tester);

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete goal'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this goal?'), findsOneWidget);
      expect(find.text('This action cannot be undone.'), findsOneWidget);

      // Cancel keeps it.
      await tester.tap(find.text('Cancel'));
      await settleDb(tester);
      expect(find.byType(GoalDetailScreen), findsOneWidget);
      expect(
        await tester.runAsync(() => helper.goalRepo.getById('g1')),
        isNotNull,
      );

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete goal'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await settleDb(tester);
      await tester.pumpAndSettle();

      expect(find.byType(GoalDetailScreen), findsNothing);
      expect(find.text('Goal deleted'), findsOneWidget);
      expect(
        await tester.runAsync(() => helper.goalRepo.getById('g1')),
        isNull,
      );
    });
  });

  testWidgets('a goal already reached shows the surplus and no motivation', (
    tester,
  ) async {
    final goal = sampleGoal(title: 'Reached', target: 500);
    await seed(tester, [goal]);
    await seedWorkout(tester, id: 'now', date: todayKey);
    await openDetail(tester, goal);

    expect(find.text('Achieved'), findsWidgets);
    expect(find.text('Surplus'), findsOneWidget);
    expect(find.text('+500kg'), findsOneWidget);
    // Needed per day makes no sense once reached.
    expect(find.text('—'), findsOneWidget);
    expect(find.text('Amazing! You crushed your goal!'), findsNothing);
    expect(find.text('To go'), findsNothing);
  });

  testWidgets('a goal met exactly shows 100% instead of a surplus', (
    tester,
  ) async {
    final goal = sampleGoal(title: 'Exact', target: 1000);
    await seed(tester, [goal]);
    await seedWorkout(tester, id: 'now', date: todayKey);
    await openDetail(tester, goal);

    expect(find.text('Achieved'), findsWidgets);
    expect(find.text('100%'), findsWidgets);
    expect(find.text('Surplus'), findsNothing);
  });

  testWidgets('a days goal shows days left instead of a per-day need', (
    tester,
  ) async {
    final goal = sampleGoal(metric: GoalMetric.days, target: 3);
    await seed(tester, [goal]);
    await seedWorkout(tester, id: 'now', date: todayKey);
    await openDetail(tester, goal);

    expect(find.text('Days left'), findsOneWidget);
    expect(find.text('Needed / day'), findsNothing);
    expect(find.text('1 / 3'), findsOneWidget);
    // Contributors of a days goal are ticked, not valued.
    expect(find.text('Workout completed'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    // Untitled: the app bar combines metric and period.
    expect(find.text('Days · Weekly'), findsOneWidget);
  });

  testWidgets('a monthly goal with no activity shows empty states', (
    tester,
  ) async {
    final goal = sampleGoal(
      title: 'Quiet month',
      period: GoalPeriod.monthly,
      target: 10000,
    );
    await seed(tester, [goal]);
    await openDetail(tester, goal);

    expect(find.text('No workouts in this period yet'), findsOneWidget);
    expect(find.text('0%'), findsWidgets);
    expect(find.text('Let\'s start! Every workout counts.'), findsOneWidget);
    // Six empty months: nothing was achieved, so no streak pill.
    expect(find.text('0% success'), findsOneWidget);
    expect(find.textContaining('streak'), findsNothing);
    expect(find.byIcon(Icons.close_rounded), findsNWidgets(6));
  });

  testWidgets('distance values follow the miles setting', (tester) async {
    final goal = sampleGoal(
      title: 'Run far',
      scope: GoalScope.aerobic,
      metric: GoalMetric.distance,
      target: 20,
    );
    await seed(tester, [goal]);
    await tester.runAsync(
      () => helper.settingsRepo.setSetting('distance_unit', 'mi'),
    );
    await openDetail(tester, goal);

    // The hero and every history tile use miles.
    expect(find.text('0.0 mi / 20.0 mi'), findsWidgets);
    expect(find.textContaining('km'), findsNothing);
  });

  testWidgets('renders its labels in Portuguese', (tester) async {
    final goal = sampleGoal(target: 2000);
    await seed(tester, [goal]);
    await seedWorkout(tester, id: 'now', date: todayKey);
    await openDetail(tester, goal, locale: const Locale('pt'));

    expect(find.text('Volume · Semanal'), findsOneWidget);
    expect(find.text('Volume · Semanal · Força'), findsOneWidget);
    expect(find.text('Em andamento'), findsOneWidget);
    expect(find.text('Progresso atual'), findsOneWidget);
    expect(find.text('RITMO DA META'), findsOneWidget);
    expect(find.text('TREINOS DESTE PERÍODO'), findsOneWidget);
    expect(find.text('HISTÓRICO'), findsOneWidget);
    expect(find.text('Projeção'), findsOneWidget);
  });

  testWidgets('a failed load shows an error with a retry', (tester) async {
    final goal = sampleGoal(title: 'Broken');
    await seed(tester, [goal]);
    await tester.runAsync(() async {
      await (await helper.database).execute('DROP TABLE sets');
    });
    await openDetail(tester, goal);

    expect(find.text('Could not load your data.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    // Retrying while the data is still unreadable stays on the error.
    await tester.tap(find.text('Try again'));
    await settleDb(tester);
    expect(find.text('Could not load your data.'), findsOneWidget);
  });
}
