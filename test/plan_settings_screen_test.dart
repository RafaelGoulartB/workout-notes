import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/main.dart';
import 'package:workout_notes/screens/workout/plan_settings_screen.dart';
import 'package:workout_notes/state/sections_notifier.dart';

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('pt'),
  home: child,
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    WorkoutNotesApp.sections = SectionsNotifier();
  });

  testWidgets('plan settings shows the section toggle', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app(const PlanSettingsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Configurações do plano'), findsOneWidget);
    expect(find.text('Seção Plano'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
  });

  testWidgets('toggling the switch disables the plan section', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app(const PlanSettingsScreen()));
    await tester.pumpAndSettle();

    expect(WorkoutNotesApp.sections.planEnabled, isTrue);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(WorkoutNotesApp.sections.planEnabled, isFalse);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(WorkoutNotesApp.sections.planEnabled, isTrue);
  });
}
