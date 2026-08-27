import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/screens/run/run_plan_customize_screen.dart';
import 'package:workout_notes/services/run_plan_templates.dart';

Widget _app() => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('pt'),
  home: RunPlanCustomizeScreen(template: RunPlanTemplates.tenK),
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

  testWidgets('maintain plan lets the athlete pick plan length', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('pt'),
        home: RunPlanCustomizeScreen(template: RunPlanTemplates.keepFit),
      ),
    );

    expect(find.text('Duração do plano'), findsOneWidget);
    expect(find.text('12 semanas'), findsOneWidget);

    await tester.tap(find.text('12 semanas'));
    await tester.pump();

    expect(
      tester
          .widget<ChoiceChip>(
            find.widgetWithText(ChoiceChip, '12 semanas'),
          )
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
}
