import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/widgets/ai/ai_coach_header_button.dart';

void main() {
  testWidgets('AI Coach header entry is compact and accessible', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('pt'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(appBar: AppBar(actions: const [AiCoachHeaderButton()])),
      ),
    );

    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byType(AiCoachHeaderButton), findsOneWidget);
    expect(find.byIcon(Icons.auto_awesome_rounded), findsOneWidget);
    expect(find.byTooltip('Abrir Treinador IA'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
