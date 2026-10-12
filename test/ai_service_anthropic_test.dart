import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:workout_notes/services/ai_service.dart';

/// Anthropic Messages protocol: request translation, answers (plain and
/// streamed) and what is learned from refused settings.
void main() {
  const baseUrl = 'https://api.anthropic.com/v1';

  http.Response message(
    List<Map<String, dynamic>> content, {
    String stopReason = 'end_turn',
    Map<String, dynamic> usage = const {
      'input_tokens': 40,
      'cache_read_input_tokens': 900,
      'cache_creation_input_tokens': 60,
      'output_tokens': 12,
    },
  }) => http.Response(
    jsonEncode({
      'id': 'msg_1',
      'type': 'message',
      'role': 'assistant',
      'content': content,
      'stop_reason': stopReason,
      'usage': usage,
    }),
    200,
  );

  String sse(List<Map<String, dynamic>> events) => [
    for (final event in events)
      'event: ${event['type']}\ndata: ${jsonEncode(event)}\n\n',
  ].join();

  const tools = [
    {
      'type': 'function',
      'function': {
        'name': 'get_sleep',
        'description': 'Sleep entries.',
        'parameters': {
          'type': 'object',
          'properties': {
            'days': {'type': 'integer'},
          },
        },
      },
    },
  ];

  group('request', () {
    test('translates the Chat Completions transcript', () async {
      late http.Request captured;
      final service = AiService(
        client: MockClient((request) async {
          captured = request;
          return message([
            {'type': 'text', 'text': 'Ok.'},
          ]);
        }),
      );

      final completion = await service.sendChat(
        baseUrl: baseUrl,
        token: 'sk-ant-test',
        model: 'claude-opus-5-5',
        apiStyle: AiApiStyle.anthropicMessages,
        reasoningEffort: 'high',
        tools: tools,
        toolChoice: 'none',
        messages: const [
          {'role': 'system', 'content': 'You are a coach.'},
          {'role': 'user', 'content': 'How did I sleep?'},
          {
            'role': 'assistant',
            'content': null,
            'tool_calls': [
              {
                'id': 'call.1',
                'type': 'function',
                'function': {'name': 'get_sleep', 'arguments': '{"days":7}'},
              },
              {
                'id': 'call_2',
                'type': 'function',
                'function': {'name': 'get_sleep', 'arguments': 'not json'},
              },
            ],
          },
          {'role': 'tool', 'tool_call_id': 'call.1', 'content': '{"ok":true}'},
          {'role': 'tool', 'tool_call_id': 'call_2', 'content': ''},
          {
            'role': 'user',
            'content': '<app_event>{"type":"proposal_applied"}</app_event>',
          },
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': 'And this label?'},
              {
                'type': 'image_url',
                'image_url': {'url': 'data:image/png;base64,AAAA'},
              },
            ],
          },
        ],
      );

      expect(captured.url.toString(), '$baseUrl/messages');
      expect(captured.headers['x-api-key'], 'sk-ant-test');
      expect(captured.headers['anthropic-version'], '2023-06-01');
      expect(
        captured.headers['anthropic-beta'],
        'thinking-binding-controls-2026-08-01',
      );
      expect(captured.headers, isNot(contains('Authorization')));

      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['model'], 'claude-opus-5-5');
      expect(body['max_tokens'], 16000);
      expect(body['system'], [
        {
          'type': 'text',
          'text': 'You are a coach.',
          'cache_control': {'type': 'ephemeral'},
        },
      ]);
      expect(body['cache_control'], {'type': 'ephemeral'});
      expect(body['thinking'], {
        'type': 'adaptive',
        'block_binding': {'prefix_mismatch_behavior': 'drop_block'},
      });
      expect(body['output_config'], {'effort': 'high'});
      expect(body, isNot(contains('temperature')));
      expect(body['tool_choice'], {'type': 'none'});
      expect(body['tools'], [
        {
          'name': 'get_sleep',
          'description': 'Sleep entries.',
          'input_schema': {
            'type': 'object',
            'properties': {
              'days': {'type': 'integer'},
            },
          },
        },
      ]);

      final messages = (body['messages'] as List).cast<Map>();
      expect(messages.map((m) => m['role']), ['user', 'assistant', 'user']);
      expect(messages[1]['content'], [
        {
          'type': 'tool_use',
          'id': 'call_1',
          'name': 'get_sleep',
          'input': {'days': 7},
        },
        {
          'type': 'tool_use',
          'id': 'call_2',
          'name': 'get_sleep',
          'input': <String, dynamic>{},
        },
      ]);
      // Tool results, the event and the new question share one user turn,
      // results first.
      expect(messages[2]['content'], [
        {
          'type': 'tool_result',
          'tool_use_id': 'call_1',
          'content': '{"ok":true}',
        },
        {'type': 'tool_result', 'tool_use_id': 'call_2', 'content': '{}'},
        {
          'type': 'text',
          'text': '<app_event>{"type":"proposal_applied"}</app_event>',
        },
        {'type': 'text', 'text': 'And this label?'},
        {
          'type': 'image',
          'source': {
            'type': 'base64',
            'media_type': 'image/png',
            'data': 'AAAA',
          },
        },
      ]);

      expect(completion.text, 'Ok.');
      expect(completion.promptTokens, 1000);
      expect(completion.cachedTokens, 900);
      expect(completion.completionTokens, 12);
      expect(completion.providerExtras, isEmpty);
    });

    test('older models get no thinking settings; a window that starts with '
        'an assistant step gets a leading user message', () async {
      late http.Request captured;
      final service = AiService(
        client: MockClient((request) async {
          captured = request;
          return message([
            {'type': 'text', 'text': 'Ok.'},
          ]);
        }),
      );

      await service.sendChat(
        baseUrl: baseUrl,
        token: 'sk-ant-test',
        model: 'claude-haiku-4-5',
        apiStyle: AiApiStyle.anthropicMessages,
        reasoningEffort: 'low',
        messages: const [
          {'role': 'assistant', 'content': 'Earlier answer.'},
          {'role': 'user', 'content': 'Next?'},
        ],
      );

      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body, isNot(contains('thinking')));
      expect(body, isNot(contains('output_config')));
      expect(body, isNot(contains('system')));
      expect(captured.headers, isNot(contains('anthropic-beta')));
      final messages = (body['messages'] as List).cast<Map>();
      expect(messages.map((m) => m['role']), ['user', 'assistant', 'user']);
    });

    test(
      'replays a thinking step verbatim with the ids the app kept',
      () async {
        late http.Request captured;
        final service = AiService(
          client: MockClient((request) async {
            captured = request;
            return message([
              {'type': 'text', 'text': 'Done.'},
            ]);
          }),
        );
        const stored = [
          {'type': 'thinking', 'thinking': '', 'signature': 'sig=='},
          {'type': 'text', 'text': 'Let me check.'},
          {
            'type': 'tool_use',
            'id': 'toolu_1',
            'name': 'get_sleep',
            'input': {'days': 7},
          },
        ];

        await service.sendChat(
          baseUrl: baseUrl,
          token: 'sk-ant-test',
          model: 'claude-sonnet-5-5',
          apiStyle: AiApiStyle.anthropicMessages,
          tools: tools,
          messages: [
            const {'role': 'user', 'content': 'Sleep?'},
            {
              'role': 'assistant',
              'content': 'Let me check.',
              'tool_calls': const [
                {
                  'id': 'toolu_1_dup',
                  'type': 'function',
                  'function': {'name': 'get_sleep', 'arguments': '{"days":7}'},
                },
              ],
              kAnthropicContentExtra: stored,
            },
            const {
              'role': 'tool',
              'tool_call_id': 'toolu_1_dup',
              'content': '{"ok":true}',
            },
          ],
        );

        final body = jsonDecode(captured.body) as Map<String, dynamic>;
        final assistant = (body['messages'] as List)[1] as Map;
        expect(assistant['content'], [
          stored[0],
          stored[1],
          {
            'type': 'tool_use',
            'id': 'toolu_1_dup',
            'name': 'get_sleep',
            'input': {'days': 7},
          },
        ]);
      },
    );

    test('lists models with the Anthropic headers', () async {
      late http.Request captured;
      final service = AiService(
        client: MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode({
              'data': [
                {'id': 'claude-sonnet-5-5', 'type': 'model'},
                {'id': 'claude-haiku-5-5', 'type': 'model'},
              ],
              'has_more': false,
            }),
            200,
          );
        }),
      );

      final models = await service.listModels(
        baseUrl: baseUrl,
        token: 'sk-ant-test',
        apiStyle: AiApiStyle.anthropicMessages,
      );

      expect(captured.url.toString(), '$baseUrl/models?limit=1000');
      expect(captured.headers['x-api-key'], 'sk-ant-test');
      expect(captured.headers['anthropic-version'], '2023-06-01');
      expect(models, ['claude-haiku-5-5', 'claude-sonnet-5-5']);
    });
  });

  group('answer', () {
    test('keeps thinking blocks for the turn and maps tool calls', () async {
      final service = AiService(
        client: MockClient(
          (_) async => message(stopReason: 'tool_use', [
            {'type': 'thinking', 'thinking': 'summary', 'signature': 's1'},
            {'type': 'text', 'text': 'Checking.'},
            {
              'type': 'tool_use',
              'id': 'toolu_9',
              'name': 'get_sleep',
              'input': {'days': 3},
            },
          ]),
        ),
      );

      final completion = await service.sendChat(
        baseUrl: baseUrl,
        token: 'k',
        model: 'claude-opus-5-5',
        apiStyle: AiApiStyle.anthropicMessages,
        messages: const [
          {'role': 'user', 'content': 'hi'},
        ],
      );

      expect(completion.text, 'Checking.');
      expect(completion.finishReason, 'tool_use');
      expect(completion.truncated, isFalse);
      expect(completion.toolCalls.single.id, 'toolu_9');
      expect(completion.toolCalls.single.arguments, {'days': 3});
      final blocks = completion.providerExtras[kAnthropicContentExtra] as List;
      expect(blocks.map((b) => (b as Map)['type']), [
        'thinking',
        'text',
        'tool_use',
      ]);
    });

    test('max_tokens and refusals end the answer as cut off', () async {
      for (final reason in ['max_tokens', 'refusal']) {
        final service = AiService(
          client: MockClient(
            (_) async => message(stopReason: reason, [
              {'type': 'text', 'text': 'Partial'},
            ]),
          ),
        );
        final completion = await service.sendChat(
          baseUrl: baseUrl,
          token: 'k',
          model: 'claude-opus-5-5',
          apiStyle: AiApiStyle.anthropicMessages,
          messages: const [
            {'role': 'user', 'content': 'hi'},
          ],
        );
        expect(completion.truncated, isTrue, reason: reason);
      }
    });

    test(
      'reads a streamed answer with thinking, text and a tool call',
      () async {
        final events = [
          {
            'type': 'message_start',
            'message': {
              'id': 'msg_1',
              'type': 'message',
              'role': 'assistant',
              'content': <Object>[],
              'usage': {
                'input_tokens': 10,
                'cache_read_input_tokens': 500,
                'cache_creation_input_tokens': 0,
                'output_tokens': 1,
              },
            },
          },
          {
            'type': 'content_block_start',
            'index': 0,
            'content_block': {
              'type': 'thinking',
              'thinking': '',
              'signature': '',
            },
          },
          {
            'type': 'content_block_delta',
            'index': 0,
            'delta': {'type': 'signature_delta', 'signature': 'abc'},
          },
          {'type': 'content_block_stop', 'index': 0},
          {'type': 'ping'},
          {
            'type': 'content_block_start',
            'index': 1,
            'content_block': {'type': 'text', 'text': ''},
          },
          {
            'type': 'content_block_delta',
            'index': 1,
            'delta': {'type': 'text_delta', 'text': 'Look'},
          },
          {
            'type': 'content_block_delta',
            'index': 1,
            'delta': {'type': 'text_delta', 'text': 'ing.'},
          },
          {
            'type': 'content_block_start',
            'index': 2,
            'content_block': {
              'type': 'tool_use',
              'id': 'toolu_5',
              'name': 'get_sleep',
              'input': <String, dynamic>{},
            },
          },
          {
            'type': 'content_block_delta',
            'index': 2,
            'delta': {'type': 'input_json_delta', 'partial_json': '{"da'},
          },
          {
            'type': 'content_block_delta',
            'index': 2,
            'delta': {'type': 'input_json_delta', 'partial_json': 'ys": 14}'},
          },
          {
            'type': 'message_delta',
            'delta': {'stop_reason': 'tool_use'},
            'usage': {'output_tokens': 33},
          },
          {'type': 'message_stop'},
        ];
        late http.BaseRequest captured;
        final service = AiService(
          client: MockClient.streaming((request, _) async {
            captured = request;
            return http.StreamedResponse(
              Stream.value(utf8.encode(sse(events))),
              200,
            );
          }),
        );
        final deltas = <AiStreamDelta>[];

        final completion = await service.sendChat(
          baseUrl: baseUrl,
          token: 'k',
          model: 'claude-opus-5-5',
          apiStyle: AiApiStyle.anthropicMessages,
          stream: true,
          onDelta: deltas.add,
          tools: tools,
          messages: const [
            {'role': 'user', 'content': 'Sleep?'},
          ],
        );

        expect(captured.headers['Accept'], 'text/event-stream');
        expect(deltas.first.reasoning, isTrue);
        expect(deltas.last.text, 'Looking.');
        expect(deltas.last.toolNames, ['get_sleep']);
        expect(completion.text, 'Looking.');
        expect(completion.truncated, isFalse);
        expect(completion.toolCalls.single.id, 'toolu_5');
        expect(completion.toolCalls.single.arguments, {'days': 14});
        expect(completion.promptTokens, 510);
        expect(completion.cachedTokens, 500);
        expect(completion.completionTokens, 33);
        expect(completion.providerExtras[kAnthropicContentExtra], [
          {'type': 'thinking', 'thinking': '', 'signature': 'abc'},
          {'type': 'text', 'text': 'Looking.'},
          {
            'type': 'tool_use',
            'id': 'toolu_5',
            'name': 'get_sleep',
            'input': {'days': 14},
          },
        ]);
      },
    );

    test(
      'a stream without message_stop keeps only the text, as cut off',
      () async {
        final events = [
          {
            'type': 'content_block_start',
            'index': 0,
            'content_block': {'type': 'text', 'text': ''},
          },
          {
            'type': 'content_block_delta',
            'index': 0,
            'delta': {'type': 'text_delta', 'text': 'Half'},
          },
          {
            'type': 'content_block_start',
            'index': 1,
            'content_block': {
              'type': 'tool_use',
              'id': 'toolu_1',
              'name': 'get_sleep',
              'input': <String, dynamic>{},
            },
          },
        ];
        final service = AiService(
          client: MockClient.streaming(
            (_, _) async => http.StreamedResponse(
              Stream.value(utf8.encode(sse(events))),
              200,
            ),
          ),
        );

        final completion = await service.sendChat(
          baseUrl: baseUrl,
          token: 'k',
          model: 'claude-opus-5-5',
          apiStyle: AiApiStyle.anthropicMessages,
          stream: true,
          messages: const [
            {'role': 'user', 'content': 'hi'},
          ],
        );

        expect(completion.text, 'Half');
        expect(completion.toolCalls, isEmpty);
        expect(completion.truncated, isTrue);
      },
    );

    test('an overloaded error event is reported as unavailable', () async {
      final service = AiService(
        client: MockClient.streaming(
          (_, _) async => http.StreamedResponse(
            Stream.value(
              utf8.encode(
                sse([
                  {
                    'type': 'error',
                    'error': {
                      'type': 'overloaded_error',
                      'message': 'Overloaded',
                    },
                  },
                ]),
              ),
            ),
            200,
          ),
        ),
      );

      await expectLater(
        service.sendChat(
          baseUrl: baseUrl,
          token: 'k',
          model: 'claude-opus-5-5',
          apiStyle: AiApiStyle.anthropicMessages,
          stream: true,
          messages: const [
            {'role': 'user', 'content': 'hi'},
          ],
        ),
        throwsA(
          isA<AiServiceException>().having(
            (e) => e.code,
            'code',
            'provider_unavailable',
          ),
        ),
      );
    });

    test('a bad key is an invalid token', () async {
      final service = AiService(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'type': 'error',
              'error': {
                'type': 'authentication_error',
                'message': 'invalid x-api-key',
              },
            }),
            401,
          ),
        ),
      );

      await expectLater(
        service.sendChat(
          baseUrl: baseUrl,
          token: 'k',
          model: 'claude-opus-5-5',
          apiStyle: AiApiStyle.anthropicMessages,
          messages: const [
            {'role': 'user', 'content': 'hi'},
          ],
        ),
        throwsA(
          isA<AiServiceException>()
              .having((e) => e.code, 'code', 'invalid_token')
              .having((e) => e.message, 'message', contains('x-api-key')),
        ),
      );
    });
  });

  group('compatibility', () {
    Future<List<Map<String, dynamic>>> sendUntilAccepted(
      String Function(Map<String, dynamic> body) refusal,
    ) async {
      final bodies = <Map<String, dynamic>>[];
      final service = AiService(
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          bodies.add(body);
          final error = refusal(body);
          if (error.isNotEmpty) {
            return http.Response(
              jsonEncode({
                'type': 'error',
                'error': {'type': 'invalid_request_error', 'message': error},
              }),
              400,
            );
          }
          return http.Response(
            sse([
              {
                'type': 'content_block_start',
                'index': 0,
                'content_block': {'type': 'text', 'text': 'Ok.'},
              },
              {
                'type': 'message_delta',
                'delta': {'stop_reason': 'end_turn'},
              },
              {'type': 'message_stop'},
            ]),
            200,
          );
        }),
      );
      final completion = await service.sendChat(
        baseUrl: baseUrl,
        token: 'k',
        model: 'claude-opus-4-6',
        apiStyle: AiApiStyle.anthropicMessages,
        reasoningEffort: 'medium',
        stream: true,
        messages: const [
          {'role': 'user', 'content': 'hi'},
        ],
      );
      expect(completion.text, 'Ok.');
      return bodies;
    }

    test('drops the block binding an endpoint does not know', () async {
      final bodies = await sendUntilAccepted(
        (body) => (body['thinking'] as Map?)?['block_binding'] != null
            ? 'thinking.block_binding: Extra inputs are not permitted'
            : '',
      );
      expect(bodies, hasLength(2));
      expect(bodies.last['thinking'], {'type': 'adaptive'});
    });

    test('learns the output cap of a model', () async {
      final bodies = await sendUntilAccepted(
        (body) => (body['max_tokens'] as int) > 32000
            ? 'max_tokens: ${body['max_tokens']} > 32000, which is the '
                  'maximum allowed number of output tokens for this model'
            : '',
      );
      expect(bodies.map((b) => b['max_tokens']), [64000, 32000]);
    });

    test('omits effort, then thinking, when refused', () async {
      final bodies = await sendUntilAccepted((body) {
        if (body.containsKey('output_config')) {
          return 'output_config.effort: Extra inputs are not permitted';
        }
        if (body.containsKey('thinking')) {
          return "thinking.type: Input tag 'adaptive' found using 'type' does "
              'not match any of the expected tags';
        }
        return '';
      });
      expect(bodies, hasLength(3));
      expect(bodies.last, isNot(contains('thinking')));
      expect(bodies.last, isNot(contains('output_config')));
    });
  });
}
