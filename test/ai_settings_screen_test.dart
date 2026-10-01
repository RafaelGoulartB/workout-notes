import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/main.dart';
import 'package:workout_notes/models/ai_settings.dart';
import 'package:workout_notes/models/ai_tool_domain.dart';
import 'package:workout_notes/screens/settings/ai_settings_screen.dart';
import 'package:workout_notes/state/ai_settings_notifier.dart';

Future<AiSettingsNotifier> _notifier({
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  FlutterSecureStorage.setMockInitialValues({});
  final notifier = AiSettingsNotifier(
    prefs: await SharedPreferences.getInstance(),
  );
  await notifier.load();
  WorkoutNotesApp.aiSettings = notifier;
  return notifier;
}

Future<void> _open(WidgetTester tester, {String locale = 'pt'}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(locale),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const AiSettingsScreen(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _scrollTo(WidgetTester tester, String label) async {
  final target = find.text(label);
  for (var attempt = 0; attempt < 24; attempt++) {
    if (target.evaluate().isNotEmpty) {
      final center = tester.getCenter(target);
      if (center.dy > 80 && center.dy < 780) return;
    }
    await tester.drag(find.byType(ListView).first, const Offset(0, -240));
    await tester.pumpAndSettle();
  }
  fail('Could not scroll to $label');
}

void main() {
  testWidgets('AI settings remains usable on a narrow mobile viewport', (
    tester,
  ) async {
    final notifier = await _notifier();
    await _open(tester);

    expect(find.text('Configuração necessária'), findsOneWidget);
    expect(find.text('Provedores'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _scrollTo(tester, 'Conciso');
    await tester.tap(find.text('Conciso'));
    await tester.pumpAndSettle();
    expect(notifier.settings.responseStyle, AiResponseStyle.concise);

    await _scrollTo(tester, 'Mostrar horários');
    expect(find.text('APARÊNCIA DO CHAT'), findsOneWidget);
    // The removed settings are gone.
    expect(find.text('Expandir consultas automaticamente'), findsNothing);
    expect(find.text('Prompt do sistema'), findsNothing);
    expect(find.text('Modo de contexto'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('data domains switch off and on, core stays', (tester) async {
    final notifier = await _notifier();
    await _open(tester, locale: 'en');

    await _scrollTo(tester, 'WHAT THE COACH CAN ACCESS');
    expect(find.textContaining('Turn an area off'), findsOneWidget);
    await _scrollTo(tester, 'Sleep');
    await tester.tap(find.text('Sleep'));
    await tester.pumpAndSettle();
    expect(
      notifier.settings.enabledDomains.contains(AiToolDomain.sleep),
      isFalse,
    );
    expect(notifier.effectiveDomains.contains(AiToolDomain.core), isTrue);
    expect(
      notifier.settings.enabledDomains.contains(AiToolDomain.workouts),
      isTrue,
    );

    await tester.tap(find.text('Sleep'));
    await tester.pumpAndSettle();
    expect(
      notifier.settings.enabledDomains.contains(AiToolDomain.sleep),
      isTrue,
    );
  });

  testWidgets('every optional domain has a switch', (tester) async {
    await _notifier();
    await _open(tester, locale: 'en');
    for (final label in const [
      'Workouts',
      'Running',
      'Sleep',
      'Nutrition',
      'Body',
      'Goals',
      'Planning',
    ]) {
      await _scrollTo(tester, label);
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('data sharing can be taken back', (tester) async {
    final notifier = await _notifier(
      prefs: {'ai_data_sharing_accepted_v1': true},
    );
    await _open(tester, locale: 'en');
    await _scrollTo(tester, 'Data sharing');
    await tester.tap(find.text('Data sharing'));
    await tester.pumpAndSettle();
    expect(notifier.settings.dataSharingAccepted, isFalse);
  });

  testWidgets('custom instructions: dirty state follows the text', (
    tester,
  ) async {
    final notifier = await _notifier(
      prefs: {'ai_custom_instructions_v1': 'Be brief.'},
    );
    await _open(tester, locale: 'en');

    await _scrollTo(tester, 'Custom instructions');
    expect(find.text('Be brief.'), findsOneWidget);
    await tester.tap(find.text('Custom instructions'));
    await tester.pumpAndSettle();

    expect(find.textContaining('never override'), findsOneWidget);
    final save = find.widgetWithText(FilledButton, 'Save');
    expect(tester.widget<FilledButton>(save).onPressed, isNull);

    // Typing then restoring the same text is not a change.
    await tester.enterText(find.byType(TextField), 'Be brief. Be kind.');
    await tester.pump();
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    await tester.enterText(find.byType(TextField), '  Be brief.  ');
    await tester.pump();
    expect(tester.widget<FilledButton>(save).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Be brief. Be kind.');
    await tester.pump();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(notifier.customInstructions, 'Be brief. Be kind.');
    expect(find.text('Saved'), findsOneWidget);
  });

  testWidgets('custom instructions can be cleared', (tester) async {
    final notifier = await _notifier(
      prefs: {'ai_custom_instructions_v1': 'Be brief.'},
    );
    await _open(tester, locale: 'en');
    await _scrollTo(tester, 'Custom instructions');
    await tester.tap(find.text('Custom instructions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(notifier.customInstructions, isEmpty);
  });

  testWidgets('developer mode is an explicit opt-in', (tester) async {
    final notifier = await _notifier();
    await _open(tester, locale: 'en');
    expect(notifier.settings.developerMode, isFalse);
    await _scrollTo(tester, 'Developer mode');
    await tester.tap(find.text('Developer mode'));
    await tester.pumpAndSettle();
    expect(notifier.settings.developerMode, isTrue);
  });

  testWidgets('the memory entry opens what the coach remembers', (
    tester,
  ) async {
    await _notifier();
    await _open(tester, locale: 'en');
    await _scrollTo(tester, 'What the coach remembers');
    expect(find.text('Not set'), findsOneWidget);
  });

  testWidgets('a provider shows the outcome of its last connection test', (
    tester,
  ) async {
    await _notifier(
      prefs: {
        'ai_providers_v1': jsonEncode([
          {
            'id': 'p1',
            'name': 'Local',
            'baseUrl': 'http://localhost:11434/v1',
            'availableModels': <String>[],
            'selectedModel': 'llama',
            'createdAt': '2026-01-01T00:00:00.000',
            'lastCheck': {
              'model': 'llama',
              'ok': true,
              'toolsSupported': false,
              'streamingSupported': true,
              'latencyMs': 420,
              'checkedAt': '2026-09-30T10:00:00.000',
            },
          },
        ]),
        'ai_active_provider_id_v1': 'p1',
      },
    );
    await _open(tester, locale: 'en');
    expect(find.text('Local'), findsOneWidget);
    // Reachable but without tool calls: flagged, not shown as fully working.
    expect(
      find.textContaining('No tool calls: the coach cannot read your data'),
      findsOneWidget,
    );
  });
}
