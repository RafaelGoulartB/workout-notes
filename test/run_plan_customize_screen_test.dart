import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_plan.dart';
import 'package:workout_notes/repositories/run_plan_repository.dart';
import 'package:workout_notes/screens/run/run_plan_customize_screen.dart';
import 'package:workout_notes/services/run_plan_history.dart';
import 'package:workout_notes/services/run_plan_templates.dart';
import 'package:workout_notes/widgets/run/run_plan_volume_sparkline.dart';
import 'support/test_db.dart';

Widget _app({RunPlanTemplate? template, RunPlanHistoryInsights? history}) =>
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('pt'),
      home: RunPlanCustomizeScreen(
        template: template ?? RunPlanTemplates.tenK,
        history: history ?? const RunPlanHistoryInsights(),
      ),
    );

Finder get _nextButton => find.widgetWithText(FilledButton, 'Próximo');

void main() {
  testWidgets('wizard lets the athlete pick where hill work happens', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app());

    await tester.tap(_nextButton);
    await tester.pump();

    expect(find.text('Onde você pode fazer treino de subida?'), findsOneWidget);
    ChoiceChip chip(String label) =>
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label));
    expect(chip('Ladeira').selected, isTrue);

    await tester.tap(find.text('Escadaria'));
    await tester.pump();
    expect(chip('Escadaria').selected, isTrue);
    expect(find.textContaining('corrimão'), findsOneWidget);

    await tester.tap(find.text('Só plano'));
    await tester.pump();
    expect(chip('Só plano').selected, isTrue);
    expect(find.textContaining('fartlek em terreno plano'), findsOneWidget);
  });

  testWidgets('maintain plan lets the athlete pick plan length', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(template: RunPlanTemplates.keepFit));

    expect(find.text('Duração do plano'), findsOneWidget);
    expect(find.text('12 semanas'), findsOneWidget);

    await tester.tap(find.text('12 semanas'));
    await tester.pump();

    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '12 semanas'))
          .selected,
      isTrue,
    );
  });

  testWidgets('explicit zero baseline blocks plan creation', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app());

    await tester.tap(_nextButton);
    await tester.pump();
    await tester.enterText(find.byType(TextField), '0');

    await tester.tap(_nextButton);
    await tester.pump();

    await tester.tap(_nextButton);
    await tester.pump();

    expect(
      find.textContaining('Você informou 0 km por semana'),
      findsOneWidget,
    );
    expect(find.text('Abrir “Começar a correr”'), findsOneWidget);
    expect(
      find.text('Ajuste as opções acima para criar um plano seguro.'),
      findsOneWidget,
    );
    final create = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Criar plano'),
    );
    expect(create.onPressed, isNull);
  });

  testWidgets('preview shows the volume curve and peak summary', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app());

    await tester.tap(_nextButton);
    await tester.pump();
    await tester.tap(_nextButton);
    await tester.pump();
    await tester.tap(_nextButton);
    await tester.pump();

    expect(find.text('Seu plano'), findsOneWidget);
    expect(find.textContaining('Semana 1 de 12'), findsOneWidget);
    expect(find.textContaining('Pico'), findsOneWidget);
    expect(find.textContaining('Prova na semana'), findsOneWidget);
    expect(find.byType(RunPlanVolumeSparkline), findsOneWidget);

    // The athlete can browse every week before committing, in day order.
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pump();
    expect(find.textContaining('Semana 2 de 12'), findsOneWidget);
    final days = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((tile) => (tile.subtitle! as Text).data!.split(' · ').first)
        .toList();
    const order = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
    final indexes = days.map(order.indexOf).toList();
    expect(indexes, orderedEquals([...indexes]..sort()));
  });

  testWidgets('a full week of days asks before swapping one', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app());

    await tester.tap(find.widgetWithText(FilterChip, 'Seg'));
    await tester.pump();

    expect(find.textContaining('desmarque um antes'), findsOneWidget);
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, 'Seg'))
          .selected,
      isFalse,
    );
  });

  testWidgets('implausible times are rejected instead of read as seconds', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(template: RunPlanTemplates.fiveK));

    await tester.tap(_nextButton);
    await tester.pump();
    await tester.tap(_nextButton);
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, '5');
    await tester.pump();
    expect(find.textContaining('Confira o tempo'), findsOneWidget);
    expect(tester.widget<FilledButton>(_nextButton).onPressed, isNull);

    // A bare number is minutes: "27" is a 27-minute 5K.
    await tester.enterText(find.byType(TextField).first, '27');
    await tester.pump();
    expect(find.textContaining('Confira o tempo'), findsNothing);
    expect(find.textContaining('Leve'), findsOneWidget);
    expect(tester.widget<FilledButton>(_nextButton).onPressed, isNotNull);
  });

  testWidgets('prefills weekly km and recent race from GPS history', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _app(
        template: RunPlanTemplates.fiveK,
        history: RunPlanHistoryInsights(
          medianWeeklyKm: 24.5,
          medianWeekCount: 4,
          suggestedRace: RunPlanSuggestedRace(
            distanceMeters: 5100,
            timeSeconds: 28 * 60 + 14,
            startedAt: DateTime(2026, 8, 1),
          ),
        ),
      ),
    );

    await tester.tap(_nextButton);
    await tester.pump();

    expect(find.text('24,5'), findsNothing);
    final kmField = tester.widget<TextField>(find.byType(TextField));
    expect(kmField.controller?.text, '24.5');
    expect(
      find.textContaining('Mediana das suas últimas 4 semanas'),
      findsOneWidget,
    );

    await tester.tap(_nextButton);
    await tester.pump();

    expect(find.textContaining('Usando seus'), findsOneWidget);
    final timeField = tester.widget<TextField>(find.byType(TextField).first);
    // 5.1 km in 28:14 is shown as its 5 km equivalent, matching the chip.
    expect(timeField.controller?.text, '27:39');
  });

  testWidgets('warns when the goal time is far faster than recent fitness', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _app(
        template: RunPlanTemplates.fiveK,
        history: RunPlanHistoryInsights(
          suggestedRace: RunPlanSuggestedRace(
            distanceMeters: 5000,
            timeSeconds: 28 * 60,
            startedAt: DateTime(2026, 8, 1),
          ),
        ),
      ),
    );

    await tester.tap(_nextButton);
    await tester.pump();
    await tester.tap(_nextButton);
    await tester.pump();
    // Current time is prefilled from history; the goal goes in its own field.
    await tester.enterText(find.byType(TextField).last, '22:00');
    await tester.pump();

    expect(find.textContaining('Esta meta precisa de mais de'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, '27:00');
    await tester.pump();
    expect(find.textContaining('Meta realista'), findsOneWidget);
  });

  group('closing the wizard', () {
    Future<void> openWizard(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_host(onResult: (_) {}));
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
    }

    testWidgets('closes straight away when nothing was touched', (
      tester,
    ) async {
      await openWizard(tester);
      expect(find.byType(RunPlanCustomizeScreen), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.text('Descartar este plano?'), findsNothing);
      expect(find.byType(RunPlanCustomizeScreen), findsNothing);
    });

    testWidgets('asks before discarding once the athlete changed something', (
      tester,
    ) async {
      await openWizard(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, '3 dias / semana'));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text('Descartar este plano?'), findsOneWidget);

      await tester.tap(find.text('Continuar editando'));
      await tester.pumpAndSettle();
      expect(find.text('Descartar este plano?'), findsNothing);
      expect(find.byType(RunPlanCustomizeScreen), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Descartar'));
      await tester.pumpAndSettle();
      expect(find.byType(RunPlanCustomizeScreen), findsNothing);
    });

    testWidgets('system back asks too after moving past the first step', (
      tester,
    ) async {
      await openWizard(tester);
      await tester.tap(_nextButton);
      await tester.pump();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Descartar este plano?'), findsOneWidget);
      expect(find.byType(RunPlanCustomizeScreen), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Descartar'));
      await tester.pumpAndSettle();
      expect(find.byType(RunPlanCustomizeScreen), findsNothing);
    });
  });

  group('creating a plan', () {
    late RunPlanRepository repo;

    setUpAll(initSqfliteFfiForTests);

    setUp(() async {
      await installTestDb();
      repo = RunPlanRepository();
    });

    tearDown(uninstallTestDb);

    /// Runs real-async work from inside a `testWidgets` body (see
    /// run_plans_widget_test.dart for why).
    Future<T> real<T>(WidgetTester tester, Future<T> Function() body) async {
      late T result;
      await tester.runAsync(() async => result = await body());
      return result;
    }

    /// Lets the DB-backed work finish on the real event loop, until [done]
    /// (default: the wizard closed) or the time budget runs out.
    Future<void> settle(WidgetTester tester, {bool Function()? done}) async {
      final finished =
          done ?? () => find.byType(RunPlanCustomizeScreen).evaluate().isEmpty;
      for (var i = 0; i < 300 && !finished(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(milliseconds: 100));
    }

    Future<RunPlan?> runWizard(
      WidgetTester tester, {
      String? name,
      bool declineSwitch = false,
    }) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      RunPlan? result;
      await tester.pumpWidget(
        _host(
          onResult: (plan) => result = plan,
          template: RunPlanTemplates.keepFit,
        ),
      );
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await tester.tap(_nextButton);
        await tester.pump();
      }
      if (name != null) {
        await tester.enterText(
          find.widgetWithText(TextField, 'Nome do plano'),
          name,
        );
        await tester.pump();
      }
      await tester.tap(find.widgetWithText(FilledButton, 'Criar plano'));
      await tester.pump();
      if (declineSwitch) {
        await settle(
          tester,
          done: () => find.text('Trocar o plano ativo?').evaluate().isNotEmpty,
        );
        expect(find.text('Trocar o plano ativo?'), findsOneWidget);
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextButton),
          ),
        );
      }
      await settle(tester);
      return result;
    }

    testWidgets('names the plan after the template until edited', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_app(template: RunPlanTemplates.keepFit));
      for (var i = 0; i < 3; i++) {
        await tester.tap(_nextButton);
        await tester.pump();
      }
      final field = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Nome do plano'),
      );
      expect(field.controller?.text, RunPlanTemplates.keepFit.title(true));
    });

    testWidgets('the typed name and an active plan come out of creation', (
      tester,
    ) async {
      final plan = await runWizard(tester, name: '  Meu 10 km  ');

      expect(plan, isNotNull);
      expect(plan!.name, 'Meu 10 km');
      final stored = await real(tester, () => repo.getPlan(plan.id));
      expect(stored?.name, 'Meu 10 km');
      expect(stored?.isActivated, isTrue);
      expect(find.byType(RunPlanCustomizeScreen), findsNothing);
      expect(find.textContaining('Plano ativado'), findsOneWidget);
    });

    testWidgets('a blank name falls back to the template title', (
      tester,
    ) async {
      final plan = await runWizard(tester, name: '   ');

      expect(plan?.name, RunPlanTemplates.keepFit.title(true));
    });

    testWidgets('undo stops following the plan but keeps it', (tester) async {
      final plan = await runWizard(tester);
      expect(plan, isNotNull);
      expect(
        (await real(tester, () => repo.getPlan(plan!.id)))?.isActivated,
        isTrue,
      );

      await tester.tap(find.text('Desfazer'));
      await settle(tester, done: () => true);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );

      final stored = await real(tester, () => repo.getPlan(plan!.id));
      expect(stored, isNotNull);
      expect(stored!.isActivated, isFalse);
    });

    testWidgets('never replaces another active plan without asking', (
      tester,
    ) async {
      final other = await real(tester, () async {
        final plan = await repo.createPlan(name: 'Plano atual');
        await repo.activatePlan(plan.id);
        return plan;
      });

      final plan = await runWizard(tester, declineSwitch: true);

      expect(plan, isNotNull);
      final created = await real(tester, () => repo.getPlan(plan!.id));
      final previous = await real(tester, () => repo.getPlan(other.id));
      expect(created?.isActivated, isFalse);
      expect(previous?.isActivated, isTrue);
      expect(find.text('Plano criado'), findsOneWidget);
    });
  });
}

/// Opens the wizard from a button so pops and results can be observed.
Widget _host({
  required void Function(RunPlan?) onResult,
  RunPlanTemplate? template,
}) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('pt'),
  home: Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: FilledButton(
          onPressed: () async {
            final plan = await Navigator.push<RunPlan>(
              context,
              MaterialPageRoute(
                builder: (_) => RunPlanCustomizeScreen(
                  template: template ?? RunPlanTemplates.tenK,
                  history: const RunPlanHistoryInsights(),
                ),
              ),
            );
            onResult(plan);
          },
          child: const Text('Abrir'),
        ),
      ),
    ),
  ),
);
