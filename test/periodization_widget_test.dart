import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/periodization_schedule.dart';
import 'package:workout_notes/models/periodization_target.dart';
import 'package:workout_notes/periodization/phase_kind.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';
import 'package:workout_notes/screens/planning/periodization_home_screen.dart';
import 'package:workout_notes/screens/planning/periodization_phase_editor_screen.dart';
import 'package:workout_notes/screens/planning/periodization_plan_editor_screen.dart';
import 'support/test_db.dart';

Widget _app(Widget home) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('pt'),
  home: home,
);

void main() {
  setUpAll(initSqfliteFfiForTests);

  setUp(() async {
    await installTestDb();
  });

  tearDown(uninstallTestDb);

  DateTime today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime thisMonday() =>
      today().subtract(Duration(days: today().weekday - 1));

  PeriodizationTarget target({
    List<int> strengthDays = const [],
    double? rest,
  }) => PeriodizationTarget(
    id: '',
    phaseId: '',
    version: 0,
    validFrom: DateTime(2000),
    calories: 2400,
    proteinG: 160,
    fatG: 70,
    carbsG: 405,
    restCalories: rest,
    restProteinG: rest == null ? null : 160,
    restFatG: rest == null ? null : 70,
    strengthDays: strengthDays,
    createdAt: DateTime(2000),
  );

  /// Active plan whose first phase started last Monday a week ago, so today
  /// falls in its second week.
  Future<String> seedActivePlan({PeriodizationTarget? seed}) async {
    final plan = await PeriodizationRepository().createChainedPlan(
      name: 'Plano do ano',
      startDate: thisMonday().subtract(const Duration(days: 7)),
      phases: [
        PhaseScheduleEntry(
          name: 'Cutting',
          templateKey: PhaseKind.cut.key,
          color: PhaseKind.cut.color,
          weeks: 4,
          seedTarget: seed ?? target(),
        ),
        PhaseScheduleEntry(
          name: 'Bulking',
          templateKey: PhaseKind.bulk.key,
          color: PhaseKind.bulk.color,
          weeks: 8,
        ),
      ],
    );
    return plan.id;
  }

  /// Lets real (sqflite ffi) I/O complete between frames. Screens chain
  /// several awaits, so one round is not enough; pumpAndSettle cannot be
  /// used while a progress indicator spins.
  Future<void> settle(WidgetTester tester, {int rounds = 10}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Scrolls [finder] to the middle of the screen, clear of the bottom bar.
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app(screen));
    await settle(tester);
  }

  testWidgets('empty state offers ready-made plans and creates one', (
    tester,
  ) async {
    await pumpScreen(tester, const PeriodizationHomeScreen());

    expect(find.text('Progresso'), findsOneWidget);
    expect(find.text('Planeje suas fases'), findsOneWidget);
    expect(find.text('Recomposição'), findsOneWidget);

    await tester.tap(find.byKey(const Key('blueprint-strength')));
    await settle(tester);

    expect(find.text('Novo plano'), findsOneWidget);
    expect(find.text('Acumulação'), findsWidgets);
    expect(find.text('Pico'), findsWidgets);
    expect(find.text('4 FASES'), findsOneWidget);

    await tester.tap(find.byKey(const Key('planEditorSave')));
    await settle(tester);

    final plan = await tester.runAsync(
      () => PeriodizationRepository().getActivePlan(),
    );
    expect(plan, isNotNull);
    final phases = await tester.runAsync(
      () => PeriodizationRepository().getPhases(plan!.id),
    );
    expect(phases!.map((p) => p.totalWeeks), [6, 4, 1, 2]);
    expect(phases.first.startDate.weekday, DateTime.monday);
    for (var i = 1; i < phases.length; i++) {
      expect(
        phases[i].startDate,
        phases[i - 1].endDate.add(const Duration(days: 1)),
      );
    }
    // The home reloads after the editor pops; let it finish.
    await settle(tester, rounds: 20);
    expect(tester.takeException(), isNull);
  });

  testWidgets('active plan shows today, this week and the phases', (
    tester,
  ) async {
    await tester.runAsync(
      () => seedActivePlan(
        seed: target(strengthDays: [today().weekday], rest: 2000),
      ),
    );
    await pumpScreen(tester, const PeriodizationHomeScreen());

    expect(find.text('Plano do ano'), findsOneWidget);
    expect(find.byKey(const Key('planningToday')), findsOneWidget);
    expect(find.text('Treino'), findsWidgets); // training-day pill
    expect(find.textContaining(RegExp(r'2[.,]400 kcal')), findsWidgets);
    expect(find.text('Semana 2 de 4'), findsWidgets);

    await reveal(tester, find.text('Toque para definir as metas'));
    expect(find.text('2 FASES'), findsOneWidget);
    expect(find.text('Toque para definir as metas'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phase editor saves the template week and rest-day target', (
    tester,
  ) async {
    final planId = (await tester.runAsync(seedActivePlan))!;
    final repository = PeriodizationRepository();
    final plan = (await tester.runAsync(() => repository.getPlan(planId)))!;
    final phases = await tester.runAsync(() => repository.getPhases(planId));
    final phase = phases!.first;

    await pumpScreen(
      tester,
      PeriodizationPhaseEditorScreen(plan: plan, phase: phase),
    );
    expect(find.text('Editar fase'), findsOneWidget);
    expect(find.text('SEMANA-MODELO'), findsOneWidget);

    final strengthDays = find.byKey(const Key('phaseStrengthDays'));
    await reveal(tester, strengthDays);
    for (final index in [0, 2, 4]) {
      await tester.tap(
        find
            .descendant(of: strengthDays, matching: find.byType(InkWell))
            .at(index),
      );
      await tester.pump();
    }
    expect(find.text('3 treinos por semana'), findsOneWidget);

    final restToggle = find.byKey(const Key('phaseRestToggle'));
    await reveal(tester, restToggle);
    await tester.tap(restToggle);
    await tester.pump();
    await tester.enterText(find.byKey(const Key('phaseRestCalories')), '1900');
    await tester.pump();

    await tester.tap(find.byKey(const Key('phaseEditorSave')));
    await settle(tester);

    final saved = await tester.runAsync(
      () => repository.getEffectiveTarget(phase.id),
    );
    expect(saved!.strengthDays, [1, 3, 5]);
    expect(saved.workoutsPerWeek, 3);
    expect(saved.restCalories, 1900);
    expect(saved.calories, 2400);
    expect(tester.takeException(), isNull);
  });

  testWidgets('week sheet labels a week and changes its calories', (
    tester,
  ) async {
    final planId = (await tester.runAsync(seedActivePlan))!;
    final repository = PeriodizationRepository();
    final plan = (await tester.runAsync(() => repository.getPlan(planId)))!;
    final phases = await tester.runAsync(() => repository.getPhases(planId));
    final phase = phases!.first;

    await pumpScreen(
      tester,
      PeriodizationPhaseEditorScreen(plan: plan, phase: phase),
    );

    final week = find.byKey(const Key('phaseWeek2'));
    await reveal(tester, week);
    await tester.tap(week);
    await settle(tester, rounds: 4);
    await tester.tap(find.text('Refeed'));
    await tester.enterText(find.byKey(const Key('weekSheetCalories')), '2800');
    await tester.tap(find.byKey(const Key('weekSheetApply')));
    await settle(tester, rounds: 4);

    await tester.tap(find.byKey(const Key('phaseEditorSave')));
    await settle(tester);

    final weekly = await tester.runAsync(
      () => repository.getWeeklyTargets(phase),
    );
    expect(weekly!.map((t) => t?.calories), [2400, 2400, 2800, 2400]);
    expect(weekly[2]?.weekLabel, 'Refeed');
    expect(tester.takeException(), isNull);
  });

  testWidgets('plan editor lengthens a phase and re-chains the next ones', (
    tester,
  ) async {
    final planId = (await tester.runAsync(seedActivePlan))!;
    final repository = PeriodizationRepository();
    final plan = (await tester.runAsync(() => repository.getPlan(planId)))!;

    await pumpScreen(tester, PeriodizationPlanEditorScreen(plan: plan));
    expect(find.text('Editar plano'), findsOneWidget);
    expect(find.text('4 sem'), findsOneWidget);

    final stepper = find
        .ancestor(of: find.text('4 sem'), matching: find.byType(Row))
        .first;
    await tester.tap(
      find.descendant(of: stepper, matching: find.byIcon(Icons.add_rounded)),
    );
    await tester.pump();
    expect(find.text('5 sem'), findsOneWidget);

    await tester.tap(find.byKey(const Key('planEditorSave')));
    await settle(tester);

    final phases = (await tester.runAsync(() => repository.getPhases(planId)))!;
    expect(phases.first.totalWeeks, 5);
    expect(
      phases.last.startDate,
      phases.first.endDate.add(const Duration(days: 1)),
    );
    expect(tester.takeException(), isNull);
  });
}
