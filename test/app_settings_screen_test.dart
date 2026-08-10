import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/screens/workout/settings_screen.dart';

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('pt'),
  home: child,
);

void main() {
  testWidgets('settings hub separates app and section settings', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app(const AppSettingsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Configurações'), findsOneWidget);
    expect(find.text('Preferências do aplicativo'), findsOneWidget);
    expect(find.text('Treino'), findsOneWidget);
    expect(find.text('Sono'), findsOneWidget);
    expect(find.text('Alimentação'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();

    expect(find.text('Inteligência artificial'), findsOneWidget);
    expect(find.text('Dados e privacidade'), findsOneWidget);
  });
}
