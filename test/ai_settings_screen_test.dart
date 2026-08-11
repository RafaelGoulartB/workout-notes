import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/main.dart';
import 'package:workout_notes/models/ai_settings.dart';
import 'package:workout_notes/screens/workout/ai_settings_screen.dart';
import 'package:workout_notes/state/ai_settings_notifier.dart';

void main() {
  testWidgets('AI settings remains usable on a narrow mobile viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final notifier = AiSettingsNotifier(prefs: prefs);
    await notifier.load();
    WorkoutNotesApp.aiSettings = notifier;

    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('pt'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AiSettingsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> scrollTo(String label) async {
      final target = find.text(label);
      for (var attempt = 0; attempt < 14; attempt++) {
        if (target.evaluate().isNotEmpty) {
          final center = tester.getCenter(target);
          if (center.dy > 80 && center.dy < 800) return;
        }
        await tester.drag(find.byType(ListView).first, const Offset(0, -240));
        await tester.pumpAndSettle();
      }
      fail('Could not scroll to $label');
    }

    expect(find.text('Configuração necessária'), findsOneWidget);
    expect(find.text('Provedores'), findsOneWidget);
    expect(find.text('Estilo das respostas'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await scrollTo('Conciso');
    await tester.tap(find.text('Conciso'));
    await tester.pumpAndSettle();
    expect(notifier.settings.responseStyle, AiResponseStyle.concise);

    await scrollTo('APARÊNCIA DO CHAT');
    expect(find.text('APARÊNCIA DO CHAT'), findsOneWidget);
    expect(find.text('Mostrar horários'), findsOneWidget);
    expect(find.text('Expandir consultas automaticamente'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await scrollTo('Prompt do sistema');
    await tester.tap(find.text('Prompt do sistema'));
    await tester.pumpAndSettle();
    expect(find.text('Restaurar padrão'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
