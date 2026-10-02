import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/periodization_checkin.dart';
import 'package:workout_notes/models/periodization_phase.dart';
import 'package:workout_notes/models/periodization_plan.dart';
import 'package:workout_notes/models/periodization_schedule.dart';
import 'package:workout_notes/models/periodization_target.dart';
import 'package:workout_notes/periodization/phase_kind.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';
import 'package:workout_notes/screens/planning/periodization_checkin_screen.dart';
import 'package:workout_notes/screens/planning/periodization_phase_screen.dart';
import 'package:workout_notes/utils/date_utils.dart';

import 'support/strength_routines_seed.dart';
import 'support/test_db.dart';

Widget _app(Widget home, {String locale = 'en'}) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: Locale(locale),
  home: home,
);

/// The rating button announced as [label] (for example `Energy 5/5`).
Finder _semantics(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);

/// Pumps a route that opens [screen] and records what it popped with, so the
/// tests can see the value the screen hands back to its caller.
class _Host extends StatefulWidget {
  final Widget screen;
  final ValueChanged<Object?> onResult;

  const _Host({required this.screen, required this.onResult});

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () async {
          final result = await Navigator.push<Object?>(
            context,
            MaterialPageRoute(builder: (_) => widget.screen),
          );
          widget.onResult(result);
        },
        child: const Text('open-screen'),
      ),
    ),
  );
}

void main() {
  late Database db;

  setUpAll(initSqfliteFfiForTests);

  setUp(() async {
    db = await installTestDb();
    // Routine "r1" (PPL) is the one the phase targets link to.
    await seedStrengthRoutines(db);
    Intl.defaultLocale = 'en';
  });

  tearDown(() async {
    Intl.defaultLocale = null;
    await uninstallTestDb();
  });

  final today = dayOf(DateTime.now());
  // The phase started three Mondays ago: today is in its fourth week (of 6).
  final phaseStart = addDays(mondayOf(today), -21);

  PeriodizationTarget target({String? label}) => PeriodizationTarget(
    id: '',
    phaseId: '',
    version: 0,
    validFrom: DateTime(2000),
    calories: 2400,
    proteinG: 160,
    fatG: 70,
    carbsG: 405,
    restCalories: 2000,
    restProteinG: 160,
    restFatG: 70,
    restCarbsG: 300,
    strengthDays: const [1, 3, 5],
    routineIds: const ['r1'],
    minSetsPerWeek: 10,
    maxSetsPerWeek: 20,
    minRpe: 7,
    maxRpe: 9,
    runDays: const [2, 4],
    runWeeklyDistanceMeters: 20000,
    weeklyWeightChangePercent: -0.5,
    targetWeightKg: 80,
    sleepHours: 8,
    weekLabel: label,
    createdAt: DateTime(2000),
  );

  /// Active plan with a 6-week "Cutting" phase and an 8-week "Bulking" one.
  Future<(PeriodizationPlan, PeriodizationPhase)> seedPlan({
    PeriodizationTarget? seed,
    bool twoPhases = true,
  }) async {
    final repo = DatabaseHelper.instance.periodizationRepo;
    final plan = await repo.createChainedPlan(
      name: 'Year plan',
      startDate: phaseStart,
      phases: [
        PhaseScheduleEntry(
          name: 'Cutting',
          templateKey: PhaseKind.cut.key,
          color: PhaseKind.cut.color,
          intent: 'Lean out for summer',
          weeks: 6,
          seedTarget: seed,
        ),
        if (twoPhases)
          PhaseScheduleEntry(
            name: 'Bulking',
            templateKey: PhaseKind.bulk.key,
            color: PhaseKind.bulk.color,
            weeks: 8,
          ),
      ],
    );
    final phases = await repo.getPhases(plan.id);
    return (plan, phases.first);
  }

  Future<void> settle(WidgetTester tester, {int rounds = 10}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  void useTallPhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// Opens [screen] from a host route (so `Navigator.pop` has somewhere to go)
  /// and returns a probe holding the value it popped with.
  Future<List<Object?>> openFromHost(
    WidgetTester tester,
    Widget screen, {
    String locale = 'en',
  }) async {
    useTallPhone(tester);
    final results = <Object?>[];
    await tester.pumpWidget(
      _app(
        _Host(screen: screen, onResult: results.add),
        locale: locale,
      ),
    );
    await tester.tap(find.text('open-screen'));
    await tester.pump();
    await settle(tester);
    return results;
  }

  group('PeriodizationPhaseScreen', () {
    testWidgets('shows the phase, its grouped targets and the current week', (
      tester,
    ) async {
      final (plan, phase) = (await tester.runAsync(
        () => seedPlan(seed: target(label: 'Deload')),
      ))!;
      useTallPhone(tester);
      await tester.pumpWidget(
        _app(PeriodizationPhaseScreen(plan: plan, phase: phase)),
      );
      await settle(tester);

      expect(find.text('Cutting'), findsWidgets);
      expect(find.text('WEEK 4 OF 6'), findsOneWidget);
      expect(find.text('Lean out for summer'), findsOneWidget);
      // Phase targets, one row per area.
      expect(
        find.textContaining('2,400 kcal training · 2,000 rest'),
        findsOneWidget,
      );
      expect(find.text('P 160 g · C 405 g · F 70 g'), findsOneWidget);
      expect(find.textContaining('3 workouts per week · PPL'), findsOneWidget);
      expect(find.text('10–20 sets · RPE 7.0–9.0'), findsOneWidget);
      expect(find.textContaining('2 runs per week'), findsOneWidget);
      expect(find.textContaining('20 km'), findsWidgets);
      expect(find.textContaining('−0.5%/wk · target 80.0 kg'), findsOneWidget);
      expect(find.text('8 h of sleep per night'), findsOneWidget);

      // The strip has one tile per week and opens on the current one.
      for (var week = 0; week < 6; week++) {
        expect(find.byKey(Key('phaseWeekTile$week')), findsOneWidget);
      }
      expect(find.textContaining('Week 4 ·'), findsOneWidget);
      expect(find.byKey(const Key('phaseWeekReview')), findsOneWidget);
      expect(find.text('Weekly review'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('is localized in Portuguese', (tester) async {
      Intl.defaultLocale = 'pt';
      final (plan, phase) = (await tester.runAsync(
        () => seedPlan(seed: target()),
      ))!;
      useTallPhone(tester);
      await tester.pumpWidget(
        _app(
          PeriodizationPhaseScreen(plan: plan, phase: phase),
          locale: 'pt',
        ),
      );
      await settle(tester);

      expect(find.text('SEMANA 4 DE 6'), findsOneWidget);
      expect(find.text('METAS DA FASE'), findsOneWidget);
      expect(find.text('Revisão semanal'), findsOneWidget);
      expect(find.textContaining('3 treinos por semana'), findsOneWidget);
      expect(find.text('8 h de sono por noite'), findsOneWidget);
    });

    testWidgets('a phase without targets invites the user to set them', (
      tester,
    ) async {
      final (plan, phase) = (await tester.runAsync(seedPlan))!;
      useTallPhone(tester);
      await tester.pumpWidget(
        _app(PeriodizationPhaseScreen(plan: plan, phase: phase)),
      );
      await settle(tester);

      expect(find.textContaining('No targets yet'), findsOneWidget);

      // Tapping the card opens the phase editor.
      await tester.tap(find.textContaining('No targets yet'));
      await settle(tester);
      expect(find.text('Edit phase'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a week that has not started offers no review', (tester) async {
      final (plan, phase) = (await tester.runAsync(
        () => seedPlan(seed: target()),
      ))!;
      useTallPhone(tester);
      await tester.pumpWidget(
        _app(PeriodizationPhaseScreen(plan: plan, phase: phase)),
      );
      await settle(tester);

      expect(find.text('This week has not started yet.'), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('phaseWeekTile5')));
      await tester.tap(find.byKey(const Key('phaseWeekTile5')));
      await settle(tester);

      expect(find.text('This week has not started yet.'), findsOneWidget);
      expect(find.byKey(const Key('phaseWeekReview')), findsNothing);
      expect(find.textContaining('Week 6 ·'), findsOneWidget);

      // A finished week goes back to the review button.
      await tester.tap(find.byKey(const Key('phaseWeekTile0')));
      await settle(tester);
      expect(find.text('This week has not started yet.'), findsNothing);
      expect(find.byKey(const Key('phaseWeekReview')), findsOneWidget);
      expect(find.text('Strength workouts'), findsOneWidget);
      expect(find.text('This week has not started yet.'), findsNothing);
    });

    testWidgets('reviewing a week saves it and shows the summary', (
      tester,
    ) async {
      final (plan, phase) = (await tester.runAsync(
        () => seedPlan(seed: target()),
      ))!;
      final results = await openFromHost(
        tester,
        PeriodizationPhaseScreen(plan: plan, phase: phase),
      );

      await tester.tap(find.byKey(const Key('phaseWeekReview')));
      await settle(tester);
      expect(find.text('CALCULATED SUMMARY'), findsOneWidget);

      await tester.tap(_semantics('Energy 5/5'));
      await tester.pump();
      expect(find.text('5/5'), findsOneWidget);
      await tester.tap(find.text('Save review'));
      await settle(tester, rounds: 14);

      final rows = (await tester.runAsync(
        () => db.query('periodization_checkins'),
      ))!;
      expect(rows, hasLength(1));
      expect(rows.single['energy'], 5);
      expect(rows.single['decision'], 'maintain');
      expect(rows.single['week_start'], dateKey(mondayOf(today)));

      // Back on the phase: the week now shows the review and can edit it.
      expect(find.text('Review done'), findsOneWidget);
      expect(
        find.text('Energy 5/5 · Hunger 3/5 · Recovery 3/5'),
        findsOneWidget,
      );
      expect(find.text('Keep going'), findsOneWidget);
      expect(find.text('Edit review'), findsOneWidget);
      expect(find.byKey(const Key('phaseWeekReview')), findsNothing);
      expect(find.textContaining('Next review is due on'), findsOneWidget);

      // Leaving the phase reports that something changed.
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.maybePop();
      await settle(tester);
      expect(results, [true]);
    });

    testWidgets('ending the phase from a review asks and shortens it', (
      tester,
    ) async {
      final (plan, phase) = (await tester.runAsync(
        () => seedPlan(seed: target()),
      ))!;
      useTallPhone(tester);
      await tester.pumpWidget(
        _app(PeriodizationPhaseScreen(plan: plan, phase: phase)),
      );
      await settle(tester);

      await tester.tap(find.byKey(const Key('phaseWeekReview')));
      await settle(tester);
      await tester.tap(find.text('End phase early'));
      await tester.pump();
      await tester.tap(find.text('Save review'));
      await settle(tester);

      expect(find.text('End phase this week?'), findsOneWidget);
      await tester.tap(find.text('End phase'));
      await settle(tester, rounds: 14);

      final phases = (await tester.runAsync(
        () => DatabaseHelper.instance.periodizationRepo.getPhases(plan.id),
      ))!;
      // Today is in week 4, so the phase now ends there and Bulking moved up.
      expect(phases.first.totalWeeks, 4);
      expect(phases.first.endDate, addDays(phaseStart, 4 * 7 - 1));
      expect(phases.last.startDate, addDays(phases.first.endDate, 1));
    });

    testWidgets('the menu ends the phase this week after confirming', (
      tester,
    ) async {
      final (plan, phase) = (await tester.runAsync(
        () => seedPlan(seed: target()),
      ))!;
      useTallPhone(tester);
      await tester.pumpWidget(
        _app(PeriodizationPhaseScreen(plan: plan, phase: phase)),
      );
      await settle(tester);

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('End phase this week'));
      await tester.pumpAndSettle();
      // Declining changes nothing.
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      var phases = (await tester.runAsync(
        () => DatabaseHelper.instance.periodizationRepo.getPhases(plan.id),
      ))!;
      expect(phases.first.totalWeeks, 6);

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('End phase this week'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('End phase'));
      await settle(tester, rounds: 14);
      phases = (await tester.runAsync(
        () => DatabaseHelper.instance.periodizationRepo.getPhases(plan.id),
      ))!;
      expect(phases.first.totalWeeks, 4);
      // The tile strip follows the shortened phase.
      expect(find.byKey(const Key('phaseWeekTile4')), findsNothing);
      expect(find.byKey(const Key('phaseWeekTile3')), findsOneWidget);
    });

    testWidgets('deleting a phase removes it and closes the screen', (
      tester,
    ) async {
      final (plan, phase) = (await tester.runAsync(
        () => seedPlan(seed: target()),
      ))!;
      final results = await openFromHost(
        tester,
        PeriodizationPhaseScreen(plan: plan, phase: phase),
      );

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete phase'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Delete “Cutting”?'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await settle(tester, rounds: 14);

      final phases = (await tester.runAsync(
        () => DatabaseHelper.instance.periodizationRepo.getPhases(plan.id),
      ))!;
      expect(phases.map((p) => p.name), ['Bulking']);
      expect(results, [true]);
    });

    testWidgets('a single-phase plan cannot delete its only phase', (
      tester,
    ) async {
      final (plan, phase) = (await tester.runAsync(
        () => seedPlan(seed: target(), twoPhases: false),
      ))!;
      useTallPhone(tester);
      await tester.pumpWidget(
        _app(PeriodizationPhaseScreen(plan: plan, phase: phase)),
      );
      await settle(tester);

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      expect(find.text('Delete phase'), findsNothing);
      expect(find.text('End phase this week'), findsOneWidget);
    });

    testWidgets('a phase deleted elsewhere closes the screen', (tester) async {
      final (plan, phase) = (await tester.runAsync(seedPlan))!;
      await tester.runAsync(
        () => db.delete(
          'periodization_phases',
          where: 'id = ?',
          whereArgs: [phase.id],
        ),
      );
      final results = await openFromHost(
        tester,
        PeriodizationPhaseScreen(plan: plan, phase: phase),
      );
      expect(find.byType(PeriodizationPhaseScreen), findsNothing);
      expect(results, [true]);
    });

    testWidgets('a failed load shows an error that retry recovers from', (
      tester,
    ) async {
      final (plan, phase) = (await tester.runAsync(
        () => seedPlan(seed: target()),
      ))!;
      await tester.runAsync(
        () => db.execute('ALTER TABLE phase_targets RENAME TO phase_targets_x'),
      );
      useTallPhone(tester);
      await tester.pumpWidget(
        _app(PeriodizationPhaseScreen(plan: plan, phase: phase)),
      );
      await settle(tester);

      expect(find.text('Could not load your data.'), findsOneWidget);
      expect(find.text('No targets yet.'), findsNothing);

      await tester.runAsync(
        () => db.execute('ALTER TABLE phase_targets_x RENAME TO phase_targets'),
      );
      await tester.tap(find.byKey(const Key('load-error-retry')));
      await settle(tester);
      expect(find.text('Could not load your data.'), findsNothing);
      expect(find.text('WEEK 4 OF 6'), findsOneWidget);
    });
  });

  group('PeriodizationCheckinScreen', () {
    Future<PeriodizationPhase> phaseOf(WidgetTester tester) async =>
        (await tester.runAsync(() async => (await seedPlan()).$2))!;

    testWidgets('renders the summary and saves ratings, decision and notes', (
      tester,
    ) async {
      final phase = (await tester.runAsync(
        () async => (await seedPlan(seed: target())).$2,
      ))!;
      final results = await openFromHost(
        tester,
        PeriodizationCheckinScreen(phase: phase),
      );

      expect(find.text('Weekly review'), findsWidgets);
      expect(find.text('Cutting'), findsOneWidget);
      expect(find.text('CALCULATED SUMMARY'), findsOneWidget);
      // Nothing logged yet: no weight change or adherence, 0 of 3 workouts.
      expect(find.text('—'), findsWidgets);
      expect(find.text('Weight change'), findsOneWidget);
      expect(find.text('Workouts'), findsOneWidget);
      expect(find.text('Adherence'), findsOneWidget);
      // Every rating starts at 3/5.
      expect(find.text('3/5'), findsNWidgets(3));

      await tester.tap(_semantics('Energy 5/5'));
      await tester.tap(_semantics('Hunger 1/5'));
      await tester.tap(_semantics('Recovery 4/5'));
      await tester.tap(find.text('Improved'));
      await tester.tap(find.text('Adjust targets manually'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '  Slept badly  ');
      await tester.tap(find.text('Save review'));
      await settle(tester);

      final rows = (await tester.runAsync(
        () => db.query('periodization_checkins'),
      ))!;
      expect(rows, hasLength(1));
      expect(rows.single['energy'], 5);
      expect(rows.single['hunger'], 1);
      expect(rows.single['recovery'], 4);
      expect(rows.single['performance'], 'improved');
      expect(rows.single['decision'], 'adjust');
      expect(rows.single['notes'], 'Slept badly');
      expect(rows.single['week_start'], dateKey(mondayOf(today)));
      expect(rows.single['phase_id'], phase.id);
      expect(rows.single['metrics_json'], isNot('{}'));
      expect(results, [PeriodizationDecision.adjust]);
    });

    testWidgets('an existing review is loaded and updated in place', (
      tester,
    ) async {
      final phase = await phaseOf(tester);
      final weekStart = addDays(phaseStart, 7);
      await tester.runAsync(
        () => DatabaseHelper.instance.periodizationRepo.saveCheckin(
          PeriodizationCheckin(
            id: 'checkin-1',
            phaseId: phase.id,
            weekStart: weekStart,
            energy: 2,
            hunger: 4,
            recovery: 5,
            performance: 'worse',
            decision: PeriodizationDecision.endPhase,
            notes: 'Tough week',
            createdAt: DateTime(2026, 1, 1),
          ),
        ),
      );
      final results = await openFromHost(
        tester,
        PeriodizationCheckinScreen(phase: phase, weekStart: weekStart),
      );

      expect(find.text('2/5'), findsOneWidget);
      expect(find.text('4/5'), findsOneWidget);
      expect(find.text('5/5'), findsOneWidget);
      expect(find.text('Tough week'), findsOneWidget);

      await tester.tap(find.text('Maintain the plan'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.text('Save review'));
      await settle(tester);

      final rows = (await tester.runAsync(
        () => db.query('periodization_checkins'),
      ))!;
      expect(rows, hasLength(1));
      expect(rows.single['id'], 'checkin-1');
      expect(rows.single['energy'], 2);
      expect(rows.single['performance'], 'worse');
      expect(rows.single['decision'], 'maintain');
      // A blank note is stored as no note.
      expect(rows.single['notes'], isNull);
      expect(results, [PeriodizationDecision.maintain]);
    });

    testWidgets('a mid-week date reviews the week starting on its Monday', (
      tester,
    ) async {
      final phase = await phaseOf(tester);
      final wednesday = addDays(phaseStart, 2);
      await openFromHost(
        tester,
        PeriodizationCheckinScreen(phase: phase, weekStart: wednesday),
      );
      await tester.tap(find.text('Save review'));
      await settle(tester);
      final rows = (await tester.runAsync(
        () => db.query('periodization_checkins'),
      ))!;
      expect(rows.single['week_start'], dateKey(phaseStart));
    });

    testWidgets('shows the workout target and the logged weight change', (
      tester,
    ) async {
      final phase = (await tester.runAsync(
        () async => (await seedPlan(
          seed: PeriodizationTarget(
            id: '',
            phaseId: '',
            version: 0,
            validFrom: DateTime(2000),
            calories: 2400,
            workoutsPerWeek: 4,
            createdAt: DateTime(2000),
          ),
        )).$2,
      ))!;
      final weekStart = addDays(phaseStart, 7);
      await tester.runAsync(() async {
        await db.insert('body_measurements', {
          'id': 'w1',
          'date': dateKey(weekStart),
          'type': 'weight',
          'value': 90.0,
          'created_at': '${dateKey(weekStart)}T07:00:00',
        });
        await db.insert('body_measurements', {
          'id': 'w2',
          'date': dateKey(addDays(weekStart, 5)),
          'type': 'weight',
          'value': 89.4,
          'created_at': '${dateKey(addDays(weekStart, 5))}T07:00:00',
        });
      });
      await openFromHost(
        tester,
        PeriodizationCheckinScreen(phase: phase, weekStart: weekStart),
      );

      expect(find.text('0/4'), findsOneWidget);
      expect(find.text('-0.6 kg'), findsOneWidget);
    });

    testWidgets('saving outside the phase keeps the screen and says so', (
      tester,
    ) async {
      final phase = await phaseOf(tester);
      final results = await openFromHost(
        tester,
        PeriodizationCheckinScreen(
          phase: phase,
          weekStart: addDays(phaseStart, -70),
        ),
      );

      await tester.tap(find.text('Save review'));
      await settle(tester);

      expect(find.text('Could not save.'), findsOneWidget);
      expect(find.byType(PeriodizationCheckinScreen), findsOneWidget);
      expect(results, isEmpty);
      // The button is usable again after the failure.
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNotNull);
      expect(
        (await tester.runAsync(() => db.query('periodization_checkins')))!,
        isEmpty,
      );
    });

    testWidgets('is localized in Portuguese', (tester) async {
      Intl.defaultLocale = 'pt';
      final phase = await phaseOf(tester);
      await openFromHost(
        tester,
        PeriodizationCheckinScreen(phase: phase),
        locale: 'pt',
      );

      expect(find.text('Revisão da semana'), findsWidgets);
      expect(find.text('Energia'), findsOneWidget);
      expect(find.text('Salvar revisão'), findsOneWidget);
      expect(_semantics('Energia 3/5'), findsOneWidget);
    });

    testWidgets('a failed load shows an error without a save button', (
      tester,
    ) async {
      final phase = await phaseOf(tester);
      await tester.runAsync(
        () => db.execute(
          'ALTER TABLE periodization_checkins '
          'RENAME TO periodization_checkins_x',
        ),
      );
      await openFromHost(tester, PeriodizationCheckinScreen(phase: phase));

      expect(find.text('Could not load your data.'), findsOneWidget);
      expect(find.text('Save review'), findsNothing);
    });
  });
}
