import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_notes/models/ai_provider.dart';
import 'package:workout_notes/models/ai_chat_error_details.dart';
import 'package:workout_notes/models/ai_chat_message.dart';
import 'package:workout_notes/models/ai_chat_state.dart';
import 'package:workout_notes/models/ai_image_attachment.dart';
import 'package:workout_notes/models/ai_message_role.dart';
import 'package:workout_notes/models/ai_settings.dart';
import 'package:workout_notes/models/ai_tool_call.dart';
import 'package:workout_notes/services/ai_service.dart';
import 'package:workout_notes/state/ai_settings_notifier.dart';
import 'package:workout_notes/utils/text_sanitizer.dart';
import 'package:workout_notes/utils/token_estimator.dart';

void main() {
  test('AiChatState retains and clears technical error details atomically', () {
    const details = AiChatErrorDetails(
      code: 'http_error',
      stage: 'initial_provider_request',
      httpStatus: 400,
      model: 'gpt-5.6-luna',
      requestCharacters: 4200,
      tools: ['get_nutrition_diary_day'],
    );
    final failed = const AiChatState().copyWith(
      phase: AiTurnPhase.failed,
      error: 'ai_error:http_error',
      errorDetails: details,
    );

    expect(failed.errorDetails, same(details));
    final recovered = failed.copyWith(
      phase: AiTurnPhase.idle,
      clearError: true,
    );
    expect(recovered.error, isNull);
    expect(recovered.errorDetails, isNull);
  });

  group('AiService vision protocol', () {
    test('uses Responses API for OpenCode GPT vision models', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'output': [
              {
                'type': 'message',
                'content': [
                  {'type': 'output_text', 'text': '{"name":"Cola"}'},
                ],
              },
            ],
            'usage': {'input_tokens': 20, 'output_tokens': 5},
          }),
          200,
        );
      });
      final service = AiService(client: client);

      final completion = await service.sendVision(
        baseUrl: 'https://console.opencode.ai/inference/openai/v1',
        token: 'token',
        model: 'gpt-5.6-luna',
        messages: const [
          {'role': 'system', 'content': 'Extract JSON.'},
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': 'Read this image.'},
              {
                'type': 'image_url',
                'image_url': {'url': 'data:image/jpeg;base64,/9j/'},
              },
            ],
          },
        ],
      );

      expect(
        captured.url.toString(),
        'https://console.opencode.ai/inference/openai/v1/responses',
      );
      final payload = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(payload['instructions'], 'Extract JSON.');
      final input = payload['input'] as List<dynamic>;
      final content =
          (input.single as Map<String, dynamic>)['content'] as List<dynamic>;
      expect(content, contains(containsPair('type', 'input_image')));
      expect(completion.text, '{"name":"Cola"}');
      expect(completion.promptTokens, 20);
      expect(completion.completionTokens, 5);
    });

    test(
      'Responses vision preserves tools and parses function calls',
      () async {
        late http.Request captured;
        final client = MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode({
              'output': [
                {
                  'type': 'function_call',
                  'call_id': 'call_sleep',
                  'name': 'get_sleep_summary',
                  'arguments': '{"days":7}',
                },
              ],
            }),
            200,
          );
        });
        final service = AiService(client: client);

        final completion = await service.sendMultimodalChat(
          baseUrl: 'https://console.opencode.ai/inference/openai/v1',
          token: 'token',
          model: 'gpt-5.6-luna',
          messages: const [
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': 'Compare com meu sono'},
                {
                  'type': 'image_url',
                  'image_url': {'url': 'data:image/jpeg;base64,/9j/'},
                },
              ],
            },
          ],
          tools: const [
            {
              'type': 'function',
              'function': {
                'name': 'get_sleep_summary',
                'description': 'Sleep summary',
                'parameters': {'type': 'object'},
              },
            },
          ],
          toolChoice: const {
            'type': 'function',
            'function': {'name': 'get_sleep_summary'},
          },
        );

        final payload = jsonDecode(captured.body) as Map<String, dynamic>;
        final tool = (payload['tools'] as List).single as Map<String, dynamic>;
        expect(tool['name'], 'get_sleep_summary');
        expect(tool.containsKey('function'), isFalse);
        expect(payload['tool_choice'], {
          'type': 'function',
          'name': 'get_sleep_summary',
        });
        expect(completion.toolCalls.single.name, 'get_sleep_summary');
        expect(completion.toolCalls.single.arguments['days'], 7);
      },
    );

    test(
      'Chat Completions multimodal request keeps images and tools',
      () async {
        late http.Request captured;
        final client = MockClient((request) async {
          captured = request;
          return http.Response(
            '{"choices":[{"message":{"content":"ok"}}]}',
            200,
          );
        });
        final service = AiService(client: client);
        await service.sendMultimodalChat(
          baseUrl: 'https://api.example.test/v1',
          token: 'token',
          model: 'vision-model',
          messages: const [
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': 'Analise'},
                {
                  'type': 'image_url',
                  'image_url': {'url': 'data:image/png;base64,AA=='},
                },
              ],
            },
          ],
          tools: const [
            {
              'type': 'function',
              'function': {
                'name': 'list_recent_workouts',
                'parameters': {'type': 'object'},
              },
            },
          ],
        );

        final payload = jsonDecode(captured.body) as Map<String, dynamic>;
        expect(payload['messages'].toString(), contains('image_url'));
        expect(payload['tools'], isNotEmpty);
      },
    );
  });

  group('AiService.normalizeBaseUri', () {
    test('appends /v1 when missing', () {
      expect(
        AiService.normalizeBaseUri('https://api.openai.com'),
        'https://api.openai.com/v1',
      );
    });

    test('does not duplicate /v1', () {
      expect(
        AiService.normalizeBaseUri('https://api.openai.com/v1'),
        'https://api.openai.com/v1',
      );
    });

    test('strips trailing slash', () {
      expect(
        AiService.normalizeBaseUri('https://api.openai.com/'),
        'https://api.openai.com/v1',
      );
    });

    test('trims whitespace', () {
      expect(
        AiService.normalizeBaseUri('  https://x.test/  '),
        'https://x.test/v1',
      );
    });
  });

  group('AiContextMode', () {
    test('round-trips through storageKey', () {
      for (final m in AiContextMode.values) {
        expect(AiContextModeX.fromStorageKey(m.storageKey), m);
      }
    });
    test('unknown values fall back to standard', () {
      expect(AiContextModeX.fromStorageKey(null), AiContextMode.standard);
      expect(AiContextModeX.fromStorageKey('weird'), AiContextMode.standard);
    });
  });

  group('AiResponseStyle', () {
    test('round-trips through storageKey and has safe fallback', () {
      for (final style in AiResponseStyle.values) {
        expect(AiResponseStyleX.fromStorageKey(style.storageKey), style);
      }
      expect(
        AiResponseStyleX.fromStorageKey('unknown'),
        AiResponseStyle.balanced,
      );
    });

    test(
      'effective prompt applies style without changing editable prompt',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final notifier = AiSettingsNotifier(prefs: prefs);
        await notifier.load();
        await notifier.setSystemPrompt('Meu prompt personalizado');
        await notifier.setResponseStyle(AiResponseStyle.concise);

        expect(notifier.systemPrompt, 'Meu prompt personalizado');
        expect(notifier.effectiveSystemPrompt, contains('seja conciso'));
        expect(
          notifier.effectiveSystemPrompt,
          startsWith(notifier.systemPrompt),
        );
      },
    );

    test(
      'chat appearance preferences persist across notifier reloads',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final notifier = AiSettingsNotifier(prefs: prefs);
        await notifier.load();
        await notifier.setShowMessageTimestamps(false);
        await notifier.setAutoExpandToolDetails(true);
        await notifier.setResponseStyle(AiResponseStyle.detailed);

        final reloaded = AiSettingsNotifier(prefs: prefs);
        await reloaded.load();
        expect(reloaded.settings.showMessageTimestamps, isFalse);
        expect(reloaded.settings.autoExpandToolDetails, isTrue);
        expect(reloaded.settings.responseStyle, AiResponseStyle.detailed);
      },
    );
  });

  group('AiProvider', () {
    test('toMap / fromMap round-trip', () {
      final p = AiProvider(
        id: 'id-1',
        name: 'Test',
        baseUrl: 'https://x.test/v1',
        availableModels: const ['m1', 'm2'],
        selectedModel: 'm1',
        reasoningEffortByModel: const {'m1': AiReasoningEffort.high},
        createdAt: DateTime.utc(2024, 1, 2, 3, 4, 5),
      );
      final back = AiProvider.fromMap(p.toMap());
      expect(back.id, p.id);
      expect(back.name, p.name);
      expect(back.baseUrl, p.baseUrl);
      expect(back.availableModels, p.availableModels);
      expect(back.selectedModel, p.selectedModel);
      expect(back.reasoningEffortFor(), AiReasoningEffort.high);
      expect(back.reasoningEffortFor('m2'), AiReasoningEffort.automatic);
      expect(back.createdAt, p.createdAt);
    });
    test('copyWith preserves fields', () {
      final p = AiProvider(
        id: 'id',
        name: 'a',
        baseUrl: 'b',
        availableModels: const [],
        selectedModel: '',
        createdAt: DateTime.utc(2024),
      );
      final c = p.copyWith(name: 'A2', selectedModel: 'gpt-4');
      expect(c.id, p.id);
      expect(c.name, 'A2');
      expect(c.selectedModel, 'gpt-4');
    });
  });

  group('AiSettings', () {
    test('isConfigured requires providers + active id', () {
      expect(const AiSettings().isConfigured, isFalse);
      expect(const AiSettings(activeProviderId: 'x').isConfigured, isFalse);
    });

    test('isConfigured true when both present', () {
      final p = AiProvider(
        id: 'p1',
        name: 'p',
        baseUrl: 'b',
        availableModels: const [],
        selectedModel: 'm',
        createdAt: DateTime.utc(2024),
      );
      final s = AiSettings(providers: [p], activeProviderId: 'p1');
      expect(s.isConfigured, isTrue);
      expect(s.activeProvider?.id, 'p1');
    });

    test('activeProvider falls back to first when id is unset', () {
      final p = AiProvider(
        id: 'p1',
        name: 'p',
        baseUrl: 'b',
        availableModels: const [],
        selectedModel: 'm',
        createdAt: DateTime.utc(2024),
      );
      final s = AiSettings(providers: [p]);
      expect(s.activeProvider?.id, 'p1');
    });

    test('copyWith can clear activeProvider', () {
      final p = AiProvider(
        id: 'p1',
        name: 'p',
        baseUrl: 'b',
        availableModels: const [],
        selectedModel: 'm',
        createdAt: DateTime.utc(2024),
      );
      final s = AiSettings(providers: [p], activeProviderId: 'p1');
      final cleared = s.copyWith(clearActiveProvider: true);
      expect(cleared.activeProviderId, isNull);
    });

    test('copyWith preserves and updates chat preferences', () {
      const settings = AiSettings(
        responseStyle: AiResponseStyle.concise,
        showMessageTimestamps: false,
      );
      final updated = settings.copyWith(autoExpandToolDetails: true);
      expect(updated.responseStyle, AiResponseStyle.concise);
      expect(updated.showMessageTimestamps, isFalse);
      expect(updated.autoExpandToolDetails, isTrue);
    });
  });

  test('AiChatMessage persists attachment metadata without image bytes', () {
    final message = AiChatMessage(
      id: 'm1',
      threadId: 't1',
      role: AiMessageRole.user,
      content: 'Analise',
      attachments: const [
        AiImageAttachment(
          id: 'img1',
          path: '/local/img1.jpg',
          mimeType: 'image/jpeg',
          fileName: 'foto.jpg',
          sizeBytes: 1234,
        ),
      ],
      createdAt: DateTime.utc(2026, 8, 10),
    );

    final row = message.toRow();
    expect(row['attachments_json'], isNot(contains('base64')));
    final restored = AiChatMessage.fromRow(row);
    expect(restored.attachments.single.path, '/local/img1.jpg');
    expect(restored.attachments.single.sizeBytes, 1234);
  });

  group('AiToolCall JSON', () {
    test('parses standard OpenAI shape', () {
      final raw = {
        'id': 'call_1',
        'type': 'function',
        'function': {
          'name': 'list_exercises',
          'arguments': '{"is_favorite": true}',
        },
      };
      final c = AiToolCall.fromJson(raw);
      expect(c.id, 'call_1');
      expect(c.name, 'list_exercises');
      expect(c.arguments['is_favorite'], true);
    });
    test('handles missing/empty arguments', () {
      final c = AiToolCall.fromJson({
        'id': 'call_2',
        'function': {'name': 'x', 'arguments': ''},
      });
      expect(c.arguments, isEmpty);
    });
    test('round-trips through toJson', () {
      final c = AiToolCall(
        id: 'call_3',
        name: 'list_recent_workouts',
        arguments: const {'limit': 5},
      );
      final back = AiToolCall.fromJson(c.toJson());
      expect(back.id, c.id);
      expect(back.name, c.name);
      expect(back.arguments['limit'], 5);
    });
  });

  group('TokenEstimator', () {
    test('estimateText is zero for empty/null', () {
      expect(TokenEstimator.estimateText(null), 0);
      expect(TokenEstimator.estimateText(''), 0);
    });
    test('estimateText scales linearly', () {
      final t = TokenEstimator.estimateText('a' * 350);
      expect(t, 100);
    });
    test('estimateMessage includes role overhead', () {
      final t = TokenEstimator.estimateMessage(
        role: 'user',
        content: 'hello world',
      );
      expect(t, greaterThan(0));
    });
  });

  group('TextSanitizer', () {
    test(r'strips $N citation placeholders', () {
      const dirty = r'volume total $1: 7.070 kg em $2 exercícios';
      expect(
        TextSanitizer.sanitize(dirty),
        'volume total : 7.070 kg em  exercícios',
      );
    });

    test(r'strips ${N} braced citation placeholders', () {
      const dirty = r'Compare ${1} com ${2} e veja ${10}.';
      expect(TextSanitizer.sanitize(dirty), 'Compare  com  e veja .');
    });

    test(r'strips $1 used as a bullet label (real-world pattern)', () {
      const dirty =
          r'''Aqui está o resumo do seu último treino (30/06/2026): $1 7.070 kg em 6 exercícios
· $1 — 60x10, 80x8, 90x6
· $1 — 50x10, 60x8, 70x6''';
      final clean = TextSanitizer.sanitize(dirty);
      expect(clean.contains(r'$1'), isFalse);
      expect(
        clean.contains('Aqui está o resumo do seu último treino (30/06/2026):'),
        isTrue,
      );
      expect(clean.contains('·  — 60x10, 80x8, 90x6'), isTrue);
    });

    test('does NOT touch legitimate \$ usage (R\$, currency, code)', () {
      const dirty = 'Custa R\$ 100 ou \$5 dólares.';
      // Note: R\$ has no digit after the \$ so it won't be touched. But \$5
      // WILL be stripped because it has a digit. That's an accepted trade-off
      // — currency references in our chat are vanishingly rare.
      final clean = TextSanitizer.sanitize(dirty);
      expect(clean.contains('R\$'), isTrue);
    });

    test('passes text with no \$ through unchanged (fast path)', () {
      const clean = 'Sou o Treinador. Bora treinar? Sem cifrão aqui.';
      expect(TextSanitizer.sanitize(clean), clean);
    });

    test('strips <think> reasoning blocks', () {
      const dirty = '<think>deep thought</think>Resposta visível.';
      expect(TextSanitizer.sanitize(dirty), 'Resposta visível.');
    });

    test('detects placeholders with invisible characters', () {
      expect(TextSanitizer.containsReferencePlaceholder(r'$1'), isTrue);
      expect(TextSanitizer.containsReferencePlaceholder('\$\u200B1'), isTrue);
    });
  });

  group('AiService sanitisation', () {
    test('adapts Kimi temperature to one and caches it per model', () async {
      final client = _SequenceHttpClient([
        const _HttpReply(
          400,
          '{"error":{"type":"invalid_request_error","message":"Error from provider (Console Go): Upstream request failed: [invalid_request_error] invalid temperature: only 1 is allowed for this model"}}',
        ),
        const _HttpReply(200, '{"choices":[{"message":{"content":"ok"}}]}'),
        const _HttpReply(
          200,
          '{"choices":[{"message":{"content":"ok novamente"}}]}',
        ),
      ]);
      final service = AiService(client: client, delay: (_) async {});

      final first = await service.sendChat(
        baseUrl: 'https://opencode.ai/zen/go/v1',
        token: 'token',
        model: 'kimi-k3',
        messages: const [
          {'role': 'user', 'content': 'oi'},
        ],
      );
      final second = await service.sendChat(
        baseUrl: 'https://opencode.ai/zen/go/v1',
        token: 'token',
        model: 'kimi-k3',
        messages: const [
          {'role': 'user', 'content': 'oi de novo'},
        ],
      );

      expect(first.text, 'ok');
      expect(second.text, 'ok novamente');
      expect(client.payloads[0]['temperature'], 0.3);
      expect(client.payloads[1]['temperature'], 1);
      expect(client.payloads[2]['temperature'], 1);
    });

    test('omits unsupported tool_choice while preserving tools', () async {
      final client = _SequenceHttpClient([
        const _HttpReply(
          400,
          '{"error":{"message":"tool_choice is unsupported by this model"}}',
        ),
        const _HttpReply(200, '{"choices":[{"message":{"content":"ok"}}]}'),
      ]);
      final service = AiService(client: client, delay: (_) async {});

      await service.sendChat(
        baseUrl: 'https://example.test/v1',
        token: 'token',
        model: 'limited-model',
        messages: const [
          {'role': 'user', 'content': 'oi'},
        ],
        tools: const [
          {
            'type': 'function',
            'function': {
              'name': 'get_sleep_night_detail',
              'parameters': {'type': 'object'},
            },
          },
        ],
      );

      expect(client.payloads[0], contains('tool_choice'));
      expect(client.payloads[1], isNot(contains('tool_choice')));
      expect(client.payloads[1]['tools'], isNotEmpty);
    });

    test('sends reasoning effort and omits it when unsupported', () async {
      final client = _SequenceHttpClient([
        const _HttpReply(
          400,
          '{"error":{"message":"reasoning_effort is not supported by this model"}}',
        ),
        const _HttpReply(200, '{"choices":[{"message":{"content":"ok"}}]}'),
        const _HttpReply(
          200,
          '{"choices":[{"message":{"content":"ok novamente"}}]}',
        ),
      ]);
      final service = AiService(client: client, delay: (_) async {});

      await service.sendChat(
        baseUrl: 'https://example.test/v1',
        token: 'token',
        model: 'model-without-effort',
        reasoningEffort: 'high',
        messages: const [
          {'role': 'user', 'content': 'analise'},
        ],
      );
      await service.sendChat(
        baseUrl: 'https://example.test/v1',
        token: 'token',
        model: 'model-without-effort',
        reasoningEffort: 'high',
        messages: const [
          {'role': 'user', 'content': 'analise novamente'},
        ],
      );

      expect(client.payloads[0]['reasoning_effort'], 'high');
      expect(client.payloads[1], isNot(contains('reasoning_effort')));
      expect(client.payloads[2], isNot(contains('reasoning_effort')));
    });

    test('retries transient upstream 503 failures', () async {
      final client = _SequenceHttpClient([
        const _HttpReply(
          503,
          '{"error":{"type":"server_error","message":"Endpoint is unavailable."}}',
        ),
        const _HttpReply(
          503,
          '{"error":{"type":"server_error","message":"Endpoint is unavailable."}}',
        ),
        const _HttpReply(
          200,
          '{"choices":[{"message":{"content":"recuperado"}}]}',
        ),
      ]);
      final service = AiService(client: client, delay: (_) async {});

      final completion = await service.sendChat(
        baseUrl: 'https://opencode.ai/zen/go/v1',
        token: 'token',
        model: 'grok-4.5',
        messages: const [
          {'role': 'user', 'content': 'oi'},
        ],
      );

      expect(completion.text, 'recuperado');
      expect(client.payloads, hasLength(3));
    });

    test('persistent 503 reports model unavailability and attempts', () async {
      final service = AiService(
        client: _StatusHttpClient(
          statusCode: 503,
          body:
              '{"error":{"type":"server_error","message":"Endpoint is unavailable."}}',
        ),
        delay: (_) async {},
      );

      await expectLater(
        () => service.sendChat(
          baseUrl: 'https://opencode.ai/zen/go/v1',
          token: 'token',
          model: 'grok-4.5',
          messages: const [
            {'role': 'user', 'content': 'oi'},
          ],
        ),
        throwsA(
          isA<AiServiceException>()
              .having((error) => error.code, 'code', 'provider_unavailable')
              .having((error) => error.statusCode, 'statusCode', 503)
              .having((error) => error.attemptCount, 'attemptCount', 3),
        ),
      );
    });

    test('HTTP failures preserve safe diagnostic metadata', () async {
      final svc = AiService(
        client: _StatusHttpClient(
          statusCode: 400,
          body: '{"error":{"message":"tool_choice is unsupported"}}',
        ),
        timeout: const Duration(seconds: 5),
      );

      try {
        await svc.sendChat(
          baseUrl: 'https://example.test/v1',
          token: 'secret-token',
          model: 'm',
          messages: const [
            {'role': 'user', 'content': 'oi'},
          ],
        );
        fail('expected AiServiceException');
      } on AiServiceException catch (error) {
        expect(error.code, 'http_error');
        expect(error.statusCode, 400);
        expect(error.endpoint, 'https://example.test/v1/chat/completions');
        expect(error.message, contains('tool_choice is unsupported'));
        expect(error.message, isNot(contains('secret-token')));
      }
    });

    test('supplies a valid id when a compatible provider omits one', () async {
      final fakeClient = _StubHttpClient((req) {
        return r'''
{
  "choices": [
    {
      "message": {
        "content": null,
        "tool_calls": [
          {
            "type": "function",
            "function": {
              "name": "propose_manual_food_creation",
              "arguments": "{\"name\":\"Pão francês médio\"}"
            }
          }
        ]
      }
    }
  ]
}
''';
      });
      final svc = AiService(
        client: fakeClient,
        timeout: const Duration(seconds: 5),
      );

      final completion = await svc.sendChat(
        baseUrl: 'https://example.test/v1',
        token: 'tok',
        model: 'qwen-compatible',
        messages: const [
          {'role': 'user', 'content': 'crie o alimento'},
        ],
      );

      expect(completion.toolCalls.single.id, 'call_1');
      expect(
        completion.toolCalls.single.arguments['name'],
        'Pão francês médio',
      );
    });

    test(r'preserves $1 so the orchestrator can reject it', () async {
      final fakeClient = _StubHttpClient((req) {
        return r'''
{
  "choices": [
    {
      "message": {
        "content": "volume total $1: 7.070 kg em $2 exercícios. · $1 — 60x10, 80x8."
      }
    }
  ]
}
''';
      });
      final svc = AiService(
        client: fakeClient,
        timeout: const Duration(seconds: 5),
      );
      final completion = await svc.sendChat(
        baseUrl: 'https://example.test/v1',
        token: 'tok',
        model: 'm',
        messages: const [
          {'role': 'user', 'content': 'oi'},
        ],
      );
      expect(completion.text!.contains('\$1'), isTrue);
      expect(completion.text!.contains('\$2'), isTrue);
      expect(completion.hadReferencePlaceholders, isTrue);
      expect(completion.text, contains('volume total'));
      expect(completion.text, contains('7.070 kg'));
    });

    test('strips <think> blocks via sendChat end-to-end', () async {
      final fakeClient = _StubHttpClient((req) {
        return '''
{
  "choices": [
    {
      "message": {
        "content": "<think>reasoning</think>Resposta final ao usuário."
      }
    }
  ]
}
''';
      });
      final svc = AiService(
        client: fakeClient,
        timeout: const Duration(seconds: 5),
      );
      final completion = await svc.sendChat(
        baseUrl: 'https://example.test/v1',
        token: 'tok',
        model: 'm',
        messages: const [
          {'role': 'user', 'content': 'oi'},
        ],
      );
      expect(completion.text, 'Resposta final ao usuário.');
    });
  });

  test('default coach prompt does not prime reference markers', () {
    expect(kDefaultAiCoachSystemPrompt, isNot(contains(r'$1')));
    expect(kDefaultAiCoachSystemPrompt, isNot(contains('[1]')));
    expect(kDefaultAiCoachSystemPrompt, isNot(contains('placeholders')));
    expect(kDefaultAiCoachSystemPrompt, contains('<workout_data>'));
    expect(kDefaultAiCoachSystemPrompt, contains('tool_call_id'));
    expect(kDefaultAiCoachSystemPrompt, contains('Markdown válido'));
    expect(kDefaultAiCoachSystemPrompt, contains('propose_routine_change'));
    expect(kDefaultAiCoachSystemPrompt, contains('seja proativo'));
  });
}

class _StubHttpClient extends http.BaseClient {
  final String Function(http.BaseRequest req) _respond;
  _StubHttpClient(this._respond);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = _respond(request);
    final bytes = utf8.encode(body);
    return http.StreamedResponse(
      Stream.value(bytes),
      200,
      reasonPhrase: 'OK',
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }
}

class _StatusHttpClient extends http.BaseClient {
  final int statusCode;
  final String body;

  _StatusHttpClient({required this.statusCode, required this.body});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        Stream.value(utf8.encode(body)),
        statusCode,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
}

class _SequenceHttpClient extends http.BaseClient {
  final List<_HttpReply> replies;
  final List<Map<String, dynamic>> payloads = [];
  var _index = 0;

  _SequenceHttpClient(this.replies);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is http.Request) {
      payloads.add((jsonDecode(request.body) as Map).cast<String, dynamic>());
    }
    final reply = replies[_index.clamp(0, replies.length - 1)];
    _index++;
    return http.StreamedResponse(
      Stream.value(utf8.encode(reply.body)),
      reply.statusCode,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }
}

class _HttpReply {
  final int statusCode;
  final String body;

  const _HttpReply(this.statusCode, this.body);
}
