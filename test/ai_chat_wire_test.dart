import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/ai_chat_message.dart';
import 'package:workout_notes/models/ai_image_attachment.dart';
import 'package:workout_notes/models/ai_message_role.dart';
import 'package:workout_notes/models/ai_tool_call.dart';
import 'package:workout_notes/services/ai_service.dart';
import 'package:workout_notes/state/ai_chat_service.dart';

/// Unit tests of the transcript layout (no provider, no database).
void main() {
  final chat = AiChatService.instance;
  var clock = 0;
  DateTime at() => DateTime(2026, 9, 30, 14, 5).add(Duration(seconds: clock++));

  AiChatMessage user(
    String text, {
    List<AiImageAttachment> images = const [],
  }) => AiChatMessage(
    id: 'u$clock',
    threadId: 't',
    role: AiMessageRole.user,
    content: text,
    attachments: images,
    createdAt: at(),
  );
  AiChatMessage assistant(
    String? text, {
    List<AiToolCall> calls = const [],
    Map<String, dynamic> extras = const {},
  }) => AiChatMessage(
    id: 'a$clock',
    threadId: 't',
    role: AiMessageRole.assistant,
    content: text,
    toolCalls: calls,
    providerExtras: extras,
    createdAt: at(),
  );
  AiChatMessage tool(String callId, String content) => AiChatMessage(
    id: 'r$clock',
    threadId: 't',
    role: AiMessageRole.tool,
    content: content,
    toolCallId: callId,
    toolName: 'get_sleep',
    createdAt: at(),
  );
  AiToolCall call(String id) =>
      AiToolCall(id: id, name: 'get_sleep', arguments: const {'days': 7});

  test('one system message, then history, then the snapshot on the current '
      'message only', () {
    final history = [user('primeira'), assistant('resposta')];
    final wire = chat.buildWireForTest(
      history: history,
      currentUser: user('segunda'),
      snapshot: 'today: 2026-09-30',
      memoryBlock: '- [abc] (health) dor no ombro',
      summary: 'Resumo antigo.',
    );
    expect(wire.where((m) => m['role'] == 'system'), hasLength(1));
    final system = wire.first['content'] as String;
    expect(system, startsWith('system'));
    expect(
      system,
      contains('<memory>\n- [abc] (health) dor no ombro\n</memory>'),
    );
    expect(system, contains('<conversation_summary>'));
    expect(wire[1]['content'], '[2026-09-30 14:05 Wed] primeira');
    expect(wire[1]['content'], isNot(contains('<context>')));
    expect(wire.last['content'], startsWith('<context>\ntoday: 2026-09-30'));
    expect(wire.last['content'], endsWith('Wed] segunda'));
  });

  test('images of the current message are sent; older ones become a note', () {
    const image = AiImageAttachment(
      id: 'i',
      path: '/x/i.jpg',
      mimeType: 'image/jpeg',
      fileName: 'i.jpg',
      sizeBytes: 1,
    );
    final wire = chat.buildWireForTest(
      history: [
        user('foto antiga', images: const [image]),
      ],
      currentUser: user('foto nova', images: const [image]),
      imageDataUrls: const ['data:image/jpeg;base64,AAA'],
    );
    expect(wire[1]['content'], contains('[1 image(s) were attached]'));
    final current = wire.last['content'] as List;
    expect(
      ((current.last as Map)['image_url'] as Map)['url'],
      'data:image/jpeg;base64,AAA',
    );
  });

  test('reasoning extras only inside the current turn; Responses items only '
      'for the Responses API', () {
    final old = assistant(
      null,
      calls: [call('c1')],
      extras: const {'reasoning_content': 'velho'},
    );
    final current = assistant(
      null,
      calls: [call('c2')],
      extras: const {
        'reasoning_content': 'novo',
        'responses_reasoning': [
          {'type': 'reasoning'},
        ],
      },
    );
    final wire = chat.buildWireForTest(
      history: [user('a'), old, tool('c1', '{"ok":true}')],
      currentUser: user('b'),
      turnMessages: [current, tool('c2', '{"ok":true}')],
    );
    final assistants = wire.where((m) => m['role'] == 'assistant').toList();
    expect(assistants.first, isNot(contains('reasoning_content')));
    expect(assistants.last['reasoning_content'], 'novo');
    expect(assistants.last, isNot(contains('responses_reasoning')));

    final responses = chat.buildWireForTest(
      history: const [],
      currentUser: user('b'),
      turnMessages: [current, tool('c2', '{"ok":true}')],
      apiStyle: AiApiStyle.responses,
    );
    expect(
      responses.firstWhere((m) => m['role'] == 'assistant'),
      contains('responses_reasoning'),
    );
  });

  test('stored transcripts are repaired: lost results get a stub, orphan '
      'results are dropped', () {
    final wire = chat.buildWireForTest(
      history: [
        tool('orphan', '{"ok":true}'),
        user('a'),
        assistant(null, calls: [call('c1'), call('c2')]),
        tool('c1', '{"ok":true}'),
      ],
      currentUser: user('b'),
    );
    final tools = wire.where((m) => m['role'] == 'tool').toList();
    expect(tools.map((m) => m['tool_call_id']), ['c1', 'c2']);
    expect(tools.last['content'], contains('interrupted'));
  });

  test('tool results up to the tools cut are short stubs', () {
    final big = jsonEncode({
      'ok': true,
      'data': {'rows': List.filled(200, 'x' * 20)},
    });
    final first = tool('c1', big);
    final wire = chat.buildWireForTest(
      history: [
        user('a'),
        assistant(null, calls: [call('c1')]),
        first,
        assistant('ok'),
        user('b'),
        assistant(null, calls: [call('c2')]),
        tool('c2', big),
      ],
      currentUser: user('c'),
      toolsThroughMessageId: first.id,
    );
    final tools = wire.where((m) => m['role'] == 'tool').toList();
    expect((tools.first['content'] as String).length, lessThan(200));
    expect(tools.first['content'], contains('omitted'));
    expect(tools.last['content'], big);
  });

  test('oversized results shrink to valid JSON instead of being cut', () {
    final huge = jsonEncode({
      'ok': true,
      'data': {
        'rows': [
          for (var i = 0; i < 2000; i++) {'d': '2026-01-01', 'v': i},
        ],
      },
    });
    final wire = chat.wireToolContentForTest(huge);
    expect(wire.length, lessThanOrEqualTo(kMaxToolResultChars));
    final decoded = jsonDecode(wire) as Map;
    expect(decoded['truncated_rows'], greaterThan(0));
    expect((decoded['data'] as Map)['rows'], isNotEmpty);
  });

  test('app events reach the model as tagged user messages', () {
    final event = AiChatMessage(
      id: 'e',
      threadId: 't',
      role: AiMessageRole.event,
      content: '{"type":"proposal_outcome","status":"applied"}',
      createdAt: at(),
    );
    final wire = chat.buildWireForTest(
      history: [user('a'), assistant('b'), event],
      currentUser: user('c'),
    );
    expect(wire[3], {
      'role': 'user',
      'content':
          '<app_event>{"type":"proposal_outcome","status":"applied"}</app_event>',
    });
  });

  test('summary transcript keeps speaker labels and bounds size', () {
    final text = chat.transcriptForSummaryForTest([
      user('pergunta'),
      assistant('resposta ' * 400),
    ]);
    expect(text, startsWith('User: pergunta'));
    expect(text, contains('Coach: '));
    expect(text.length, lessThan(4000));
  });

  test('malformed tool arguments are kept verbatim for the transcript', () {
    final parsed = AiToolCall.fromJson({
      'id': 'c',
      'type': 'function',
      'function': {'name': 'get_sleep', 'arguments': '{bad'},
    });
    expect(parsed.argumentsError, isNotNull);
    expect((parsed.toJson()['function'] as Map)['arguments'], '{bad');
  });

  test('tool-call extras survive a round trip', () {
    final parsed = AiToolCall.fromJson({
      'id': 'c',
      'type': 'function',
      'function': {'name': 'x', 'arguments': '{}'},
      'extra_content': {
        'google': {'thought_signature': 's'},
      },
    });
    expect(parsed.toJson()['extra_content'], {
      'google': {'thought_signature': 's'},
    });
    expect(
      parsed.toJson(includeExtras: false),
      isNot(contains('extra_content')),
    );
  });
}
