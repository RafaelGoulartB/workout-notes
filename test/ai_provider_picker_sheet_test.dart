import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/ai_provider.dart';
import 'package:workout_notes/state/ai_settings_notifier.dart';
import 'package:workout_notes/widgets/ai/ai_provider_picker_sheet.dart';

void main() {
  testWidgets('selects model and persists reasoning effort', (tester) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final notifier = AiSettingsNotifier(prefs: prefs);
    await notifier.load();
    final provider = await notifier.addProvider(
      name: 'OpenCode',
      baseUrl: 'https://example.test/v1',
    );
    await notifier.setProviderModels(provider.id, const ['model-a', 'model-b']);
    await notifier.setSelectedModel(provider.id, 'model-a');

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('pt'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => AiProviderPickerSheet(notifier: notifier),
              ),
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    expect(find.text('Esforço de raciocínio'), findsOneWidget);
    expect(find.text('Automático'), findsOneWidget);
    expect(find.text('model-b'), findsNothing);
    expect(
      tester.getTopLeft(find.text('model-a')).dy,
      greaterThan(tester.getTopLeft(find.text('Esforço de raciocínio')).dy),
    );
    expect(
      tester.getSize(find.byType(AiProviderPickerSheet)).height,
      lessThan(650),
    );
    await tester.tap(find.text('model-a'));
    await tester.pumpAndSettle();
    expect(find.text('model-b'), findsOneWidget);
    await tester.tap(find.text('model-b'));
    await tester.pumpAndSettle();
    expect(find.text('model-a'), findsNothing);
    // Effort is stored independently per model, so choose it after changing
    // the model whose setting is being edited.
    await tester.tap(find.text('Alto'));
    await tester.tap(find.text('Usar esta configuração'));
    await tester.pumpAndSettle();

    final saved = notifier.settings.activeProvider!;
    expect(saved.selectedModel, 'model-b');
    expect(saved.reasoningEffortFor(), AiReasoningEffort.high);
    expect(tester.takeException(), isNull);
  });
}
