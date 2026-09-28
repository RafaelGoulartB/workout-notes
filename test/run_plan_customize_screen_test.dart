import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/screens/run/run_plan_customize_screen.dart';
import 'package:workout_notes/services/run_plan_history.dart';
import 'package:workout_notes/services/run_plan_templates.dart';
import 'package:workout_notes/widgets/run/run_plan_volume_sparkline.dart';

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
}
