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
  testWidgets('wizard lets the athlete replace hill sessions', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app());

    await tester.tap(_nextButton);
    await tester.pump();

    expect(find.text('Incluir treinos em subida'), findsOneWidget);
    final switchFinder = find.descendant(
      of: find.widgetWithText(SwitchListTile, 'Incluir treinos em subida'),
      matching: find.byType(Switch),
    );
    expect(tester.widget<Switch>(switchFinder).value, isTrue);

    await tester.tap(switchFinder);
    await tester.pump();

    expect(tester.widget<Switch>(switchFinder).value, isFalse);
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
    await tester.tap(
      find.widgetWithText(SwitchListTile, 'Pular — usar só zonas de esforço'),
    );
    await tester.pump();

    await tester.tap(_nextButton);
    await tester.pump();

    expect(
      find.textContaining('Você informou 0 km por semana'),
      findsOneWidget,
    );
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
    await tester.tap(
      find.widgetWithText(SwitchListTile, 'Pular — usar só zonas de esforço'),
    );
    await tester.pump();
    await tester.tap(_nextButton);
    await tester.pump();

    expect(find.text('Seu plano'), findsOneWidget);
    expect(find.text('Semana 1'), findsOneWidget);
    expect(find.textContaining('Pico'), findsOneWidget);
    expect(find.textContaining('Prova na semana'), findsOneWidget);
    expect(find.byType(RunPlanVolumeSparkline), findsOneWidget);
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
    await tester.tap(find.text('Prova recente'));
    await tester.pump();

    expect(find.textContaining('Usando seus'), findsOneWidget);
    final timeField = tester.widget<TextField>(find.byType(TextField));
    expect(timeField.controller?.text, '28:14');
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
    await tester.enterText(find.byType(TextField), '22:00');
    await tester.pump();

    expect(find.textContaining('Esta meta é bem mais rápida'), findsOneWidget);
  });
}
