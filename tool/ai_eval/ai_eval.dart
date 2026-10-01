// AI Coach evaluation harness.
//
// Runs scripted conversations (Portuguese and English) against a REAL
// provider over a seeded "heavy user" database and reports, per scenario and
// in total: which tools the model called, whether that matches what the
// question needs, provider rounds, prompt / cached / completion tokens,
// latency, failures, and whether the numbers in the answer appear in the tool
// results (a cheap groundedness signal).
//
// It lives outside test/ so `flutter test` never runs it. Usage:
//
//   AI_EVAL_BASE_URL=https://api.openai.com/v1 AI_EVAL_TOKEN=sk-... \
//   AI_EVAL_MODEL=gpt-5-mini flutter test tool/ai_eval/ai_eval.dart
//
// Optional: AI_EVAL_API_STYLE=responses, AI_EVAL_EFFORT=low|medium|high,
// AI_EVAL_ONLY=<scenario id prefix>, AI_EVAL_REPORT=/path/report.json.
// Without a provider (AI_EVAL_DRY=1 or no AI_EVAL_BASE_URL) it only measures
// the static request size (system prompt, catalog, snapshot) offline.
// Runs under `flutter test`, so the test-only preference mocks are fine here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/models/ai_chat_message.dart';
import 'package:workout_notes/models/ai_message_role.dart';
import 'package:workout_notes/models/ai_tool_domain.dart';
import 'package:workout_notes/services/ai_context_service.dart';
import 'package:workout_notes/services/ai_service.dart';
import 'package:workout_notes/state/ai_chat_service.dart';
import 'package:workout_notes/state/ai_settings_notifier.dart';

import '../../test/support/ai_heavy_user_fixture.dart';
import '../../test/support/test_db.dart';
import 'scenarios.dart';

void main() {
  final env = Platform.environment;
  final baseUrl = env['AI_EVAL_BASE_URL'];
  final dry = env['AI_EVAL_DRY'] == '1' || baseUrl == null;

  test('AI Coach evaluation', () async {
    initSqfliteFfiForTests();
    final db = await installTestDb(seed: true, seedMealTypes: true);
    final fixture = await seedHeavyUser(db, now: DateTime.now());
    if (dry) {
      await _measureStatic(fixture);
      return;
    }
    final report = await _runScenarios(
      baseUrl: AiService.normalizeBaseUri(baseUrl),
      token: env['AI_EVAL_TOKEN'] ?? '',
      model: env['AI_EVAL_MODEL'] ?? '',
      apiStyle: AiApiStyle.fromStorageKey(env['AI_EVAL_API_STYLE']),
      effort: env['AI_EVAL_EFFORT'],
      only: env['AI_EVAL_ONLY'],
    );
    final path = env['AI_EVAL_REPORT'] ?? '/tmp/ai_eval_report.json';
    File(
      path,
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
    stdout.writeln('\nReport written to $path');
    await uninstallTestDb();
  }, timeout: const Timeout(Duration(hours: 2)));
}

Future<AiChatService> _setUpChat({
  required String baseUrl,
  required String token,
  required String model,
  required AiApiStyle apiStyle,
  required String language,
  String? effort,
  http.Client? client,
}) async {
  SharedPreferences.setMockInitialValues({
    'app_locale': language,
    'ai_providers_v1': jsonEncode([
      {
        'id': 'eval',
        'name': 'Eval',
        'baseUrl': baseUrl,
        'availableModels': [model],
        'selectedModel': model,
        'apiStyle': apiStyle.storageKey,
        if (effort != null) 'reasoningEffortByModel': {model: effort},
        'createdAt': DateTime.now().toIso8601String(),
      },
    ]),
    'ai_active_provider_id_v1': 'eval',
    'ai_data_sharing_accepted_v1': true,
  });
  FlutterSecureStorage.setMockInitialValues({'ai_token:eval': token});
  final service = AiService(client: client);
  final settings = AiSettingsNotifier(
    prefs: await SharedPreferences.getInstance(),
    service: service,
  );
  await settings.load();
  final chat = AiChatService.instance..reset();
  chat.overrideForTest(
    service: service,
    settings: settings,
    context: AiContextService(),
  );
  return chat;
}

Future<void> _waitIdle(AiChatService chat) async {
  while (chat.state.turn != null) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// Offline numbers: what every request carries before any history.
Future<void> _measureStatic(HeavyUserFixture fixture) async {
  final client = _CapturingClient();
  for (final language in ['pt', 'en']) {
    final chat = await _setUpChat(
      baseUrl: 'https://offline.test/v1',
      token: 'x',
      model: 'offline',
      apiStyle: AiApiStyle.chatCompletions,
      language: language,
      client: client,
    );
    await chat.send(language == 'pt' ? 'Oi' : 'Hi');
    await _waitIdle(chat);
  }
  final payload = client.payloads.first;
  final messages = (payload['messages'] as List).cast<Map>();
  final system = '${messages.first['content']}';
  final user = '${messages.last['content']}';
  final tools = jsonEncode(payload['tools']);
  final snapshot = await AiContextService().buildSnapshot(
    domains: {...AiToolDomain.values},
  );
  final total = jsonEncode(payload).length;
  stdout
    ..writeln('== Static request size (heavy user, first message) ==')
    ..writeln('system message: ${system.length} chars')
    ..writeln(
      'tool catalog:   ${tools.length} chars '
      '(${(payload['tools'] as List).length} tools)',
    )
    ..writeln('snapshot:       ${snapshot.length} chars')
    ..writeln('user message:   ${user.length} chars')
    ..writeln('whole request:  $total chars ≈ ${(total / 3.5).round()} tokens')
    ..writeln('\nSnapshot:\n$snapshot');
}

Future<Map<String, Object?>> _runScenarios({
  required String baseUrl,
  required String token,
  required String model,
  required AiApiStyle apiStyle,
  required String? effort,
  required String? only,
}) async {
  final results = <Map<String, Object?>>[];
  for (final scenario in evalScenarios) {
    if (only != null && !scenario.id.startsWith(only)) continue;
    final chat = await _setUpChat(
      baseUrl: baseUrl,
      token: token,
      model: model,
      apiStyle: apiStyle,
      language: scenario.language,
      effort: effort,
    );
    final turns = <Map<String, Object?>>[];
    for (final message in scenario.turns) {
      final watch = Stopwatch()..start();
      final sent = await chat.send(message);
      await _waitIdle(chat);
      watch.stop();
      final threadId = chat.state.activeThreadId;
      final stored = threadId == null
          ? const <AiChatMessage>[]
          : (await DatabaseHelper.instance.aiChatRepo.getAiChatMessagesAfter(
              threadId,
            )).map(AiChatMessage.fromRow).toList();
      final lastUser = stored.lastIndexWhere((m) => m.isUser);
      final turnMessages = lastUser < 0
          ? const <AiChatMessage>[]
          : stored.sublist(lastUser + 1);
      final tools = [
        for (final m in turnMessages)
          for (final c in m.toolCalls) c.name,
      ];
      final toolText = turnMessages
          .where((m) => m.isTool)
          .map((m) => m.content ?? '')
          .join('\n');
      final answer = turnMessages.lastWhere(
        (m) => m.isAssistant && (m.content?.isNotEmpty ?? false),
        orElse: () => AiChatMessage(
          id: '',
          threadId: '',
          role: AiMessageRole.assistant,
          createdAt: DateTime.now(),
        ),
      );
      final diagnostics = chat.state.lastTurnDiagnostics;
      turns.add({
        'message': message,
        'sent': sent,
        'error': chat.state.error,
        'latency_ms': watch.elapsedMilliseconds,
        'rounds': diagnostics.length,
        'tools': tools,
        'prompt_tokens': _sum(diagnostics.map((d) => d.promptTokens)),
        'cached_tokens': _sum(diagnostics.map((d) => d.cachedTokens)),
        'completion_tokens': _sum(diagnostics.map((d) => d.completionTokens)),
        'request_chars': _sum(diagnostics.map((d) => d.requestChars)),
        'grounded_numbers': _groundedNumbers(answer.content ?? '', toolText),
        'answer': answer.content,
        'proposals': [for (final p in chat.state.proposals) p.kind],
      });
    }
    final verdict = scenario.check(turns);
    results.add({
      'id': scenario.id,
      'language': scenario.language,
      'pass': verdict.pass,
      'notes': verdict.notes,
      'turns': turns,
    });
    stdout.writeln(
      '${verdict.pass ? 'PASS' : 'FAIL'}  ${scenario.id.padRight(34)} '
      'rounds=${turns.map((t) => t['rounds']).join('/')} '
      'tools=${turns.map((t) => (t['tools'] as List).join('+')).join(' | ')}'
      '${verdict.notes.isEmpty ? '' : '  (${verdict.notes.join('; ')})'}',
    );
  }
  final allTurns = [
    for (final r in results)
      ...(r['turns'] as List).cast<Map<String, Object?>>(),
  ];
  final prompt = _sum(allTurns.map((t) => t['prompt_tokens'] as int?)) ?? 0;
  final cached = _sum(allTurns.map((t) => t['cached_tokens'] as int?)) ?? 0;
  final summary = {
    'model': model,
    'scenarios': results.length,
    'passed': results.where((r) => r['pass'] == true).length,
    'turns': allTurns.length,
    'failed_turns': allTurns.where((t) => t['error'] != null).length,
    'avg_rounds': allTurns.isEmpty
        ? 0
        : allTurns.map((t) => t['rounds'] as int).reduce((a, b) => a + b) /
              allTurns.length,
    'avg_latency_ms': allTurns.isEmpty
        ? 0
        : allTurns.map((t) => t['latency_ms'] as int).reduce((a, b) => a + b) ~/
              allTurns.length,
    'prompt_tokens': prompt,
    'cached_tokens': cached,
    'cache_hit_ratio': prompt == 0 ? null : cached / prompt,
    'completion_tokens': _sum(
      allTurns.map((t) => t['completion_tokens'] as int?),
    ),
  };
  stdout.writeln('\n${const JsonEncoder.withIndent('  ').convert(summary)}');
  return {'summary': summary, 'results': results};
}

int? _sum(Iterable<int?> values) {
  final present = values.whereType<int>().toList();
  return present.isEmpty ? null : present.reduce((a, b) => a + b);
}

/// Share of the numbers in [answer] (≥ 2 digits, ignoring dates and list
/// markers) that also appear in the tool results. 1.0 = every number is
/// backed by data; null when the answer has no such numbers.
double? _groundedNumbers(String answer, String toolResults) {
  final numbers = RegExp(
    r'(?<![\d-])\d{2,}(?:[.,]\d+)?(?![\d-])',
  ).allMatches(answer).map((m) => m.group(0)!.replaceAll(',', '.')).toSet();
  if (numbers.isEmpty) return null;
  final found = numbers.where((n) {
    final integer = n.split('.').first;
    return toolResults.contains(n) || toolResults.contains(integer);
  });
  return found.length / numbers.length;
}

/// Records the first payload and answers "ok" (offline size measurement).
class _CapturingClient extends http.BaseClient {
  final List<Map<String, dynamic>> payloads = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    payloads.add(
      (jsonDecode((request as http.Request).body) as Map)
          .cast<String, dynamic>(),
    );
    const body =
        'data: {"choices":[{"delta":{"content":"ok"},"finish_reason":"stop"}]}\n\n'
        'data: [DONE]\n\n';
    return http.StreamedResponse(Stream.value(utf8.encode(body)), 200);
  }
}
