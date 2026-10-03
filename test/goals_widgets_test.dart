import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/models/goal.dart';
import 'package:workout_notes/screens/goals/goal_detail_screen.dart';
import 'package:workout_notes/utils/date_utils.dart';
import 'package:workout_notes/widgets/goals/goal_card.dart';
import 'package:workout_notes/widgets/goals/goal_form_sheet.dart';
import 'package:workout_notes/widgets/goals/goals_section.dart';

import 'support/goals_ui_support.dart';
import 'support/test_db.dart';

/// A goal progress for a Monday-to-Sunday week with fixed dates, so the pace
/// rules do not depend on the day the tests run.
GoalProgress _progress({
  double current = 400,
  double target = 2000,
  int elapsed = 4,
  bool complete = false,
  int periodDays = 7,
}) {
  final start = DateTime(2026, 6, 1);
  return GoalProgress(
    currentValue: current,
    targetValue: target,
    percent: target > 0 ? (current / target).clamp(0.0, 1.5) : 0,
    isComplete: complete,
    periodStart: start,
    periodEnd: DateTime(2026, 6, periodDays),
    daysRemaining: periodDays - elapsed,
    daysElapsed: elapsed,
  );
}

Widget _cardApp(
  Goal goal,
  GoalProgress progress, {
  Locale locale = const Locale('en'),
  bool isKm = true,
  VoidCallback? onTap,
  VoidCallback? onEdit,
  VoidCallback? onTogglePause,
  VoidCallback? onDelete,
}) => goalsApp(
  Scaffold(
    body: GoalCard(
      goal: goal,
      progress: progress,
      isKm: isKm,
      onTap: onTap ?? () {},
      onEdit: onEdit,
      onTogglePause: onTogglePause,
      onDelete: onDelete,
    ),
  ),
  locale: locale,
);

void main() {
  setUpAll(() async {
    initSqfliteFfiForTests();
    await initDateSymbolsForTests();
  });

  group('GoalCard.paceOf', () {
    test('a paused goal is paused even when it is complete', () {
      final goal = sampleGoal(isActive: false);
      expect(GoalCard.paceOf(goal, _progress(complete: true)), GoalPace.paused);
    });

    test('a complete goal is done', () {
      expect(
        GoalCard.paceOf(sampleGoal(), _progress(complete: true)),
        GoalPace.done,
      );
    });

    test('trailing the elapsed share by more than 10 points is behind', () {
      // Day 4 of 7: 3 days completed (43 %) against 20 % done.
      expect(
        GoalCard.paceOf(sampleGoal(), _progress(current: 400)),
        GoalPace.behind,
      );
    });

    test('being within 10 points of the elapsed share is on track', () {
      // Day 4 of 7: 3 days completed (43 %) against 50 % done.
      expect(
        GoalCard.paceOf(sampleGoal(), _progress(current: 1000)),
        GoalPace.onTrack,
      );
    });

    test('day one of a week with no progress is not late', () {
      expect(
        GoalCard.paceOf(sampleGoal(), _progress(current: 0, elapsed: 1)),
        GoalPace.onTrack,
      );
    });

    test('day one of a month with no progress is not late', () {
      expect(
        GoalCard.paceOf(
          sampleGoal(period: GoalPeriod.monthly),
          _progress(current: 0, elapsed: 1, periodDays: 30),
        ),
        GoalPace.onTrack,
      );
    });
  });

  group('GoalCard', () {
    testWidgets('shows the title, metric, pace and the value left', (
      tester,
    ) async {
      await tester.pumpWidget(
        _cardApp(
          sampleGoal(title: 'Bench month', target: 2000),
          _progress(current: 1000),
        ),
      );

      expect(find.text('Bench month'), findsOneWidget);
      // Subtitle: metric, period and days left.
      expect(find.text('Volume · Weekly · 3 days left'), findsOneWidget);
      expect(find.text('On track'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
      expect(find.text('1.0t/2.0t', findRichText: true), findsOneWidget);
      expect(find.text('1.0t to go'), findsOneWidget);
    });

    testWidgets('an untitled goal falls back to its metric label', (
      tester,
    ) async {
      await tester.pumpWidget(
        _cardApp(
          sampleGoal(
            scope: GoalScope.aerobic,
            metric: GoalMetric.distance,
            period: GoalPeriod.monthly,
            target: 50,
          ),
          _progress(current: 10, target: 50),
        ),
      );

      expect(find.text('Distance'), findsOneWidget);
      expect(find.text('Monthly · 3 days left'), findsOneWidget);
      expect(find.text('Behind'), findsOneWidget);
      expect(find.text('10.0k/50.0k', findRichText: true), findsOneWidget);
    });

    testWidgets('miles are used when the unit is not km', (tester) async {
      await tester.pumpWidget(
        _cardApp(
          sampleGoal(
            scope: GoalScope.aerobic,
            metric: GoalMetric.distance,
            target: 50,
          ),
          _progress(current: 10, target: 50),
          isKm: false,
        ),
      );

      expect(find.text('10.0m/50.0m', findRichText: true), findsOneWidget);
    });

    testWidgets('a day-count goal shows days left as whole days', (
      tester,
    ) async {
      await tester.pumpWidget(
        _cardApp(
          sampleGoal(metric: GoalMetric.days, target: 4),
          _progress(current: 1, target: 4),
        ),
      );

      expect(find.text('1/4', findRichText: true), findsOneWidget);
      expect(find.text('3 days to go'), findsOneWidget);
    });

    testWidgets('a completed goal shows a check and the metric as unit', (
      tester,
    ) async {
      await tester.pumpWidget(
        _cardApp(
          sampleGoal(title: 'Done goal', target: 500),
          _progress(current: 600, target: 500, complete: true),
        ),
      );

      expect(find.text('Done'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      // Nothing left: the label under the value is the metric name.
      expect(find.text('volume'), findsOneWidget);
      // Days left are not shown once the goal is done.
      expect(find.text('Volume · Weekly'), findsOneWidget);
    });

    testWidgets('a paused goal shows the pause icon and pill', (tester) async {
      await tester.pumpWidget(
        _cardApp(sampleGoal(isActive: false), _progress(current: 1000)),
      );

      expect(find.text('Paused'), findsOneWidget);
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
      expect(find.textContaining('days left'), findsNothing);
    });

    testWidgets('renders in Portuguese', (tester) async {
      await tester.pumpWidget(
        _cardApp(
          sampleGoal(title: 'Meta de peito', target: 2000),
          _progress(current: 400),
          locale: const Locale('pt'),
        ),
      );

      expect(find.text('Meta de peito'), findsOneWidget);
      expect(find.text('Atrasada'), findsOneWidget);
      expect(find.text('Volume · Semanal · 3 dias restantes'), findsOneWidget);
    });

    testWidgets('tapping the card calls onTap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _cardApp(sampleGoal(title: 'Tap me'), _progress(), onTap: () => taps++),
      );

      await tester.tap(find.text('Tap me'));
      expect(taps, 1);
    });

    testWidgets('long press lists only the actions that were provided', (
      tester,
    ) async {
      await tester.pumpWidget(
        _cardApp(sampleGoal(title: 'Menu'), _progress(), onEdit: () {}),
      );

      await tester.longPress(find.text('Menu'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Goal'), findsOneWidget);
      expect(find.text('Pause'), findsNothing);
      expect(find.text('Delete goal'), findsNothing);
    });

    testWidgets('the context menu runs edit, pause/resume and delete', (
      tester,
    ) async {
      final calls = <String>[];
      await tester.pumpWidget(
        _cardApp(
          sampleGoal(title: 'Menu', isActive: false),
          _progress(),
          onEdit: () => calls.add('edit'),
          onTogglePause: () => calls.add('pause'),
          onDelete: () => calls.add('delete'),
        ),
      );

      for (final (label, call) in [
        ('Edit Goal', 'edit'),
        // The goal is paused, so the action offers to resume it.
        ('Resume', 'pause'),
        ('Delete goal', 'delete'),
      ]) {
        await tester.longPress(find.text('Menu'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(calls.last, call);
        // The sheet closes after choosing.
        expect(find.text(label), findsNothing);
      }
      expect(calls, ['edit', 'pause', 'delete']);
    });
  });

  group('GoalFormSheet', () {
    Goal? result;
    var closed = false;

    setUp(() async {
      await installTestDb();
      result = null;
      closed = false;
    });
    tearDown(uninstallTestDb);

    Future<void> openSheet(
      WidgetTester tester, {
      Goal? existing,
      List<GoalScope> scopes = const [GoalScope.anaerobic, GoalScope.aerobic],
      Locale locale = const Locale('en'),
    }) async {
      useLogicalViewSize(tester, const Size(500, 1400));
      await tester.pumpWidget(
        goalsApp(
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    result = await GoalFormSheet.show(
                      context,
                      DatabaseHelper.instance.settingsRepo,
                      existing: existing,
                      allowedScopes: scopes,
                    );
                    closed = true;
                  },
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

    Finder field(String label) => find.widgetWithText(TextField, label);

    testWidgets('creates a strength goal with the entered values', (
      tester,
    ) async {
      await openSheet(tester);

      expect(find.text('New Goal'), findsOneWidget);
      // Strength is the default scope, with its two metrics.
      expect(find.widgetWithText(ChoiceChip, 'Volume'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Days'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Distance'), findsNothing);

      await tester.enterText(field('Title (optional)'), '  Hypertrophy  ');
      await tester.enterText(field('Target value'), '12500');
      await tester.tap(find.text('Monthly'));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await settleDb(tester);

      expect(closed, isTrue);
      final goal = result!;
      expect(goal.title, 'Hypertrophy');
      expect(goal.scope, GoalScope.anaerobic);
      expect(goal.metric, GoalMetric.volume);
      expect(goal.period, GoalPeriod.monthly);
      expect(goal.targetValue, 12500);
      expect(goal.isActive, isTrue);
      expect(goal.id, isNotEmpty);
    });

    testWidgets('switching to cardio swaps the metrics and the unit', (
      tester,
    ) async {
      await openSheet(tester);

      await tester.tap(find.text('Cardio'));
      await tester.pump();

      expect(find.widgetWithText(ChoiceChip, 'Volume'), findsNothing);
      expect(find.widgetWithText(ChoiceChip, 'Distance'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Time'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Time'));
      await tester.pump();
      expect(find.text('min'), findsOneWidget);

      // Comma decimals are accepted.
      await tester.enterText(field('Target value'), '150,5');
      await tester.tap(find.text('Save'));
      await settleDb(tester);

      expect(result!.scope, GoalScope.aerobic);
      expect(result!.metric, GoalMetric.time);
      expect(result!.targetValue, 150.5);
    });

    testWidgets('a metric that is invalid for the new scope is reset', (
      tester,
    ) async {
      await openSheet(tester);
      await tester.tap(find.text('Cardio'));
      await tester.pump();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Distance'));
      await tester.pump();
      await tester.tap(find.text('Strength'));
      await tester.pump();
      await tester.enterText(field('Target value'), '3');
      await tester.tap(find.text('Save'));
      await settleDb(tester);

      expect(result!.scope, GoalScope.anaerobic);
      expect(result!.metric, GoalMetric.volume);
    });

    testWidgets('an empty, zero or negative target is rejected', (
      tester,
    ) async {
      await openSheet(tester);

      for (final input in ['', '0', '-5', 'abc']) {
        await tester.enterText(field('Target value'), input);
        await tester.tap(find.text('Save'));
        await tester.pump();

        expect(
          find.text('Error: Invalid value'),
          findsOneWidget,
          reason: input,
        );
        expect(closed, isFalse, reason: input);
        ScaffoldMessenger.of(
          tester.element(find.byType(GoalFormSheet)),
        ).clearSnackBars();
        await tester.pump();
      }
      expect(find.byType(GoalFormSheet), findsOneWidget);
    });

    testWidgets('cancel closes without a goal', (tester) async {
      await openSheet(tester);

      await tester.tap(find.text('Cancel'));
      await settleDb(tester);

      expect(closed, isTrue);
      expect(result, isNull);
    });

    testWidgets('a single allowed scope hides the scope selector', (
      tester,
    ) async {
      await openSheet(tester, scopes: const [GoalScope.aerobic]);

      expect(find.text('Scope'), findsNothing);
      expect(find.text('Strength'), findsNothing);
      // The cardio metrics are the only ones on offer.
      expect(find.widgetWithText(ChoiceChip, 'Distance'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Volume'), findsNothing);
    });

    testWidgets('editing prefills the form and keeps identity fields', (
      tester,
    ) async {
      final existing = sampleGoal(
        id: 'keep-me',
        title: 'Old title',
        scope: GoalScope.aerobic,
        metric: GoalMetric.distance,
        period: GoalPeriod.monthly,
        target: 42.5,
        isActive: false,
        color: 0xFF112233,
        createdAt: DateTime(2025, 3, 4),
      );
      await openSheet(tester, existing: existing);

      expect(find.text('Edit Goal'), findsOneWidget);
      expect(find.text('Old title'), findsOneWidget);
      expect(find.text('42.5'), findsOneWidget);
      expect(find.text('km'), findsOneWidget);
      // Editing never asks for a suggestion.
      expect(find.textContaining('Suggested'), findsNothing);

      await tester.enterText(field('Title (optional)'), 'New title');
      await tester.tap(find.text('Save'));
      await settleDb(tester);

      expect(
        result,
        existing.copyWith(title: 'New title'),
        reason: 'only the edited fields change',
      );
    });

    testWidgets('an existing goal outside the allowed scopes is coerced', (
      tester,
    ) async {
      final existing = sampleGoal(
        scope: GoalScope.aerobic,
        metric: GoalMetric.time,
        target: 60,
      );
      await openSheet(
        tester,
        existing: existing,
        scopes: const [GoalScope.anaerobic],
      );

      await tester.tap(find.text('Save'));
      await settleDb(tester);

      expect(result!.scope, GoalScope.anaerobic);
      expect(result!.metric, GoalMetric.volume);
    });

    testWidgets('offers a target from recent history and applies it on tap', (
      tester,
    ) async {
      final db = DatabaseHelper.instance;
      final database = await tester.runAsync(() => db.database);
      await tester.runAsync(() async {
        await seedGoalExercises(database!);
        // 100 kg x 10 reps in the previous week: 1000 kg x 1.1 = 1100 kg.
        await seedFinishedWorkout(
          database,
          id: 'last-week',
          date: dateKey(addDays(dayOf(DateTime.now()), -7)),
        );
      });
      await openSheet(tester);

      expect(find.text('Suggested: 1100 kg'), findsOneWidget);

      await tester.tap(find.text('Suggested: 1100 kg'));
      await tester.pump();

      expect(find.text('1100'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await settleDb(tester);
      expect(result!.targetValue, 1100);
    });

    testWidgets('renders in Portuguese', (tester) async {
      await openSheet(tester, locale: const Locale('pt'));

      expect(find.text('Nova Meta'), findsOneWidget);
      expect(find.text('Força'), findsOneWidget);
      expect(find.text('Periodicidade'), findsOneWidget);
      expect(find.text('Salvar'), findsOneWidget);

      await tester.enterText(field('Valor alvo'), '0');
      await tester.tap(find.text('Salvar'));
      await tester.pump();
      expect(find.text('Erro: Valor inválido'), findsOneWidget);
    });
  });

  group('GoalsSection', () {
    late DatabaseHelper helper;

    setUp(() async {
      await installTestDb();
      helper = DatabaseHelper.instance;
    });
    tearDown(uninstallTestDb);

    Future<void> pumpSection(
      WidgetTester tester, {
      List<GoalScope> scopes = const [GoalScope.anaerobic, GoalScope.aerobic],
      void Function(int, int)? onSummary,
      Locale locale = const Locale('en'),
      bool framed = true,
    }) async {
      useLogicalViewSize(tester, const Size(500, 1400));
      await tester.pumpWidget(
        goalsApp(
          Scaffold(
            body: SingleChildScrollView(
              child: GoalsSection(
                db: helper,
                settingsRepo: helper.settingsRepo,
                allowedScopes: scopes,
                onSummaryChanged: onSummary,
                framed: framed,
              ),
            ),
          ),
          locale: locale,
        ),
      );
      await settleDb(tester);
    }

    Future<void> seedGoals(WidgetTester tester, List<Goal> goals) async {
      await tester.runAsync(() async {
        final database = await helper.database;
        await seedGoalExercises(database);
        for (final g in goals) {
          await helper.goalRepo.insert(g);
        }
      });
    }

    Future<void> seedTodayVolume(WidgetTester tester, double volume) async {
      await tester.runAsync(() async {
        await seedFinishedWorkout(
          await helper.database,
          id: 'today',
          date: dateKey(DateTime.now()),
          weight: volume / 10,
          reps: 10,
        );
      });
    }

    testWidgets('shows the empty state and creates the first goal', (
      tester,
    ) async {
      final summaries = <(int, int)>[];
      await pumpSection(tester, onSummary: (a, t) => summaries.add((a, t)));

      expect(find.text('No goals yet'), findsOneWidget);
      expect(find.text('Set a weekly or monthly target'), findsOneWidget);
      expect(summaries.last, (0, 0));

      await tester.tap(find.text('No goals yet'));
      await settleDb(tester);
      expect(find.text('New Goal'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Title (optional)'),
        'Lift more',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Target value'),
        '5000',
      );
      await tester.tap(find.text('Save'));
      await settleDb(tester);

      expect(find.text('Goal saved'), findsOneWidget);
      expect(find.text('Lift more'), findsOneWidget);
      expect(find.text('No goals yet'), findsNothing);
      final stored = await tester.runAsync(() => helper.goalRepo.getAll());
      expect(stored!.single.title, 'Lift more');
      expect(stored.single.targetValue, 5000);
      expect(summaries.last, (0, 1));
    });

    testWidgets('lists goals with their progress and reports the summary', (
      tester,
    ) async {
      await seedGoals(tester, [
        sampleGoal(id: 'a', title: 'Easy one', target: 500),
        sampleGoal(id: 'b', title: 'Hard one', target: 100000),
      ]);
      await seedTodayVolume(tester, 1000);
      final summaries = <(int, int)>[];
      await pumpSection(tester, onSummary: (a, t) => summaries.add((a, t)));

      expect(find.text('Easy one'), findsOneWidget);
      expect(find.text('Hard one'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('1/100t', findRichText: true), findsNothing);
      expect(summaries.last, (1, 2));
      // The add row follows the goals.
      expect(find.text('Add goal'), findsOneWidget);
    });

    testWidgets('only lists the allowed scopes', (tester) async {
      await seedGoals(tester, [
        sampleGoal(id: 'a', title: 'Strength goal'),
        sampleGoal(
          id: 'b',
          title: 'Cardio goal',
          scope: GoalScope.aerobic,
          metric: GoalMetric.distance,
          target: 30,
        ),
      ]);
      await pumpSection(tester, scopes: const [GoalScope.aerobic]);

      expect(find.text('Cardio goal'), findsOneWidget);
      expect(find.text('Strength goal'), findsNothing);
    });

    testWidgets('pausing from the menu persists and shows the paused pill', (
      tester,
    ) async {
      await seedGoals(tester, [sampleGoal(title: 'Pause me')]);
      await pumpSection(tester);

      await tester.longPress(find.text('Pause me'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pause'));
      await settleDb(tester);

      expect(find.text('Paused'), findsOneWidget);
      final stored = await tester.runAsync(() => helper.goalRepo.getAll());
      expect(stored!.single.isActive, isFalse);

      // And resuming brings it back.
      await tester.longPress(find.text('Pause me'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Resume'));
      await settleDb(tester);
      expect(find.text('Paused'), findsNothing);
    });

    testWidgets('editing from the menu updates the goal', (tester) async {
      await seedGoals(tester, [sampleGoal(title: 'Before')]);
      await pumpSection(tester);

      await tester.longPress(find.text('Before'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit Goal'));
      await settleDb(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Title (optional)'),
        'After',
      );
      await tester.tap(find.text('Save'));
      await settleDb(tester);

      expect(find.text('After'), findsOneWidget);
      expect(find.text('Before'), findsNothing);
      expect(find.text('Goal saved'), findsOneWidget);
    });

    testWidgets('deleting asks for confirmation and can be cancelled', (
      tester,
    ) async {
      await seedGoals(tester, [sampleGoal(title: 'Delete me')]);
      await pumpSection(tester);

      await tester.longPress(find.text('Delete me'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete goal'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this goal?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await settleDb(tester);
      expect(find.text('Delete me'), findsOneWidget);

      await tester.longPress(find.text('Delete me'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete goal'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await settleDb(tester);

      expect(find.text('Goal deleted'), findsOneWidget);
      expect(find.text('Delete me'), findsNothing);
      expect(find.text('No goals yet'), findsOneWidget);
      final stored = await tester.runAsync(() => helper.goalRepo.getAll());
      expect(stored, isEmpty);
    });

    testWidgets('tapping a goal opens its detail and reloads on return', (
      tester,
    ) async {
      await seedGoals(tester, [sampleGoal(title: 'Open me')]);
      await pumpSection(tester);

      await tester.tap(find.text('Open me'));
      await settleDb(tester);
      expect(find.byType(GoalDetailScreen), findsOneWidget);

      // Delete from the detail screen, then come back to a refreshed list.
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete goal'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await settleDb(tester);
      await tester.pumpAndSettle();

      expect(find.byType(GoalDetailScreen), findsNothing);
      expect(find.text('Open me'), findsNothing);
      expect(find.text('No goals yet'), findsOneWidget);
    });

    testWidgets('a goal whose progress cannot be read shows a retry row', (
      tester,
    ) async {
      await seedGoals(tester, [sampleGoal(title: 'Broken progress')]);
      // Progress reads the workout tables; without them only the goal list
      // can be read.
      await tester.runAsync(() async {
        final database = await helper.database;
        await database.execute('DROP TABLE sets');
      });
      await pumpSection(tester);

      expect(find.text('Broken progress'), findsOneWidget);
      expect(find.text('Could not load your data.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Done'), findsNothing);
      expect(find.text('0%'), findsNothing);
    });

    testWidgets('renders the empty state and the add row in Portuguese', (
      tester,
    ) async {
      await pumpSection(tester, locale: const Locale('pt'));

      expect(find.text('Nenhuma meta criada'), findsOneWidget);
      expect(find.text('Defina um alvo semanal ou mensal'), findsOneWidget);
    });

    testWidgets('unframed renders just the list', (tester) async {
      await seedGoals(tester, [sampleGoal(title: 'Bare')]);
      await pumpSection(tester, framed: false);

      expect(find.text('Bare'), findsOneWidget);
    });
  });
}
