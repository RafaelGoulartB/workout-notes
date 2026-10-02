import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_notes/models/ai_provider.dart';
import 'package:workout_notes/services/ai_service.dart';
import 'package:workout_notes/state/ai_settings_notifier.dart';
import 'package:workout_notes/widgets/ai/ai_provider_editor_sheet.dart';

import 'support/ai_ui_support.dart';

class _FakeAiService extends AiService {
  AiProbeResult probeResult = const AiProbeResult(
    ok: true,
    toolsSupported: true,
    streamingSupported: true,
    latencyMs: 321,
  );
  List<String> models = ['gpt-a', 'gpt-b', 'other-model'];
  Object? modelsError;
  final List<String> fetchedFrom = [];
  final List<String> probed = [];

  @override
  Future<List<String>> listModels({
    required String baseUrl,
    required String token,
  }) async {
    fetchedFrom.add(baseUrl);
    if (modelsError != null) throw modelsError!;
    return models;
  }

  @override
  Future<AiProbeResult> probe({
    required String baseUrl,
    required String token,
    required String model,
    AiApiStyle apiStyle = AiApiStyle.chatCompletions,
  }) async {
    probed.add('$model/${apiStyle.name}');
    return probeResult;
  }
}

void main() {
  late _FakeAiService service;
  late AiSettingsNotifier notifier;

  Future<void> open(WidgetTester tester, {AiProvider? existing}) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      aiTestApp(AiProviderEditorSheet(notifier: notifier, existing: existing)),
    );
    await tester.pumpAndSettle();
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    service = _FakeAiService();
    notifier = AiSettingsNotifier(
      prefs: await SharedPreferences.getInstance(),
      service: service,
    );
    await notifier.load();
  });

  Finder field(String label) => find.widgetWithText(TextField, label);

  testWidgets('refuses an empty name and an invalid base URL', (tester) async {
    await open(tester);
    await tester.enterText(field('Base URL'), 'ftp://example.com');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Enter a name.'), findsOneWidget);
    expect(
      find.text('Enter a valid address starting with http:// or https://.'),
      findsOneWidget,
    );
    expect(notifier.settings.providers, isEmpty);

    await tester.enterText(field('Base URL'), 'not a url');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(notifier.settings.providers, isEmpty);

    await tester.enterText(field('Base URL'), '');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Enter a base URL.'), findsOneWidget);
  });

  testWidgets('plain http is refused for public hosts, allowed on the LAN', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(field('Name'), 'Remote');
    await tester.enterText(field('Model'), 'm');
    await tester.enterText(field('Base URL'), 'http://api.example.com/v1');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(
      find.textContaining('Plain http:// is only allowed for addresses'),
      findsOneWidget,
    );
    expect(notifier.settings.providers, isEmpty);

    await tester.enterText(field('Base URL'), 'http://10.evil.com:11434/v1');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(notifier.settings.providers, isEmpty);

    await tester.enterText(field('Base URL'), 'http://192.168.1.20:11434/v1');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      notifier.settings.providers.single.baseUrl,
      'http://192.168.1.20:11434/v1',
    );
  });

  testWidgets('saves every setting, stores the token and fetches models', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(field('Name'), 'My OpenAI');
    await tester.enterText(field('Base URL'), 'https://api.openai.com/v1/');
    await tester.enterText(field('API token'), 'sk-test');
    await tester.enterText(field('Model'), 'gpt-a');
    await tester.enterText(field('Utility model (optional)'), 'gpt-mini');
    await tester.tap(find.text('Responses'));
    await tester.pump();
    await tester.ensureVisible(find.text('High'));
    await tester.tap(find.text('High'));
    await tester.pump();
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final provider = notifier.settings.providers.single;
    expect(provider.name, 'My OpenAI');
    expect(provider.baseUrl, 'https://api.openai.com/v1');
    expect(provider.selectedModel, 'gpt-a');
    expect(provider.utilityModel, 'gpt-mini');
    expect(provider.apiStyle, AiApiStyle.responses);
    expect(provider.reasoningEffortFor('gpt-a'), AiReasoningEffort.high);
    expect(await notifier.getToken(provider.id), 'sk-test');
    // The model list is fetched in the background after saving.
    expect(service.fetchedFrom, ['https://api.openai.com/v1']);
    expect(notifier.settings.providers.single.availableModels, service.models);
  });

  testWidgets('test connection saves first and shows what it found', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(field('Name'), 'Local');
    await tester.enterText(field('Base URL'), 'http://10.0.2.2:11434/v1');
    await tester.enterText(field('Model'), 'llama3');
    await tester.ensureVisible(find.text('Test connection'));
    await tester.tap(find.text('Test connection'));
    await tester.pumpAndSettle();

    expect(service.probed, ['llama3/chatCompletions']);
    expect(find.text('Connection works'), findsOneWidget);
    expect(find.text('Reads your data (tool calls)'), findsOneWidget);
    expect(find.text('Streams answers'), findsOneWidget);
    expect(find.textContaining('321 ms'), findsOneWidget);
    // It was saved so the result can be kept on the provider.
    expect(notifier.settings.providers.single.lastCheck?.ok, isTrue);
  });

  testWidgets('a failed test shows the localized reason', (tester) async {
    service.probeResult = const AiProbeResult(
      ok: false,
      errorCode: 'invalid_token',
    );
    await open(tester);
    await tester.enterText(field('Name'), 'OpenAI');
    await tester.enterText(field('Model'), 'gpt-a');
    await tester.ensureVisible(find.text('Test connection'));
    await tester.tap(find.text('Test connection'));
    await tester.pumpAndSettle();

    expect(find.text('Connection failed'), findsOneWidget);
    expect(
      find.text(
        'The provider did not accept the API token. Check it in the AI settings.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a model without tool calls is called out', (tester) async {
    service.probeResult = const AiProbeResult(
      ok: true,
      streamingSupported: false,
      latencyMs: 100,
    );
    await open(tester);
    await tester.enterText(field('Name'), 'OpenAI');
    await tester.enterText(field('Model'), 'tiny');
    await tester.ensureVisible(find.text('Test connection'));
    await tester.tap(find.text('Test connection'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('No tool calls: the coach cannot read your data'),
      findsOneWidget,
    );
    expect(find.textContaining('No streaming'), findsOneWidget);
  });

  testWidgets('fetch models then pick one from the list', (tester) async {
    await open(tester);
    await tester.enterText(field('Name'), 'OpenAI');
    await tester.tap(find.text('Fetch models'));
    await tester.pumpAndSettle();
    expect(find.text('3 models found'), findsOneWidget);

    await tester.tap(find.byTooltip('Pick from list'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'other');
    await tester.pump();
    expect(find.text('gpt-a'), findsNothing);
    await tester.tap(find.text('other-model'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(field('Model')).controller!.text,
      'other-model',
    );
  });

  testWidgets('a failed fetch explains why', (tester) async {
    service.modelsError = const AiServiceException(
      'no',
      code: 'connection_error',
    );
    await open(tester);
    await tester.enterText(field('Name'), 'OpenAI');
    await tester.tap(find.text('Fetch models'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Could not reach the provider. Check your connection and the base URL.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('editing keeps the token when the field stays empty', (
    tester,
  ) async {
    final created = await tester.runAsync(
      () => notifier.addProvider(
        name: 'OpenAI',
        baseUrl: 'https://api.openai.com/v1',
        token: 'sk-keep',
        model: 'gpt-a',
      ),
    );
    await open(tester, existing: created);
    expect(tester.widget<TextField>(field('Model')).controller!.text, 'gpt-a');
    await tester.enterText(field('Name'), 'Renamed');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(notifier.settings.providers.single.name, 'Renamed');
    expect(await notifier.getToken(created!.id), 'sk-keep');
  });
}
