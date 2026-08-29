import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/ai_chat_message.dart';
import 'package:workout_notes/models/ai_image_attachment.dart';
import 'package:workout_notes/models/ai_message_role.dart';
import 'package:workout_notes/models/ai_tool_call.dart';
import 'package:workout_notes/state/ai_chat_service.dart';

void main() {
  test('completed tool transcripts are not resent on later turns', () {
    final now = DateTime(2026, 8, 10);
    final messages = [
      _message('u1', AiMessageRole.user, now, content: 'Analise meu sono'),
      AiChatMessage(
        id: 'a-call',
        threadId: 'thread',
        role: AiMessageRole.assistant,
        toolCalls: const [
          AiToolCall(id: 'call-1', name: 'get_sleep_summary', arguments: {}),
        ],
        createdAt: now,
      ),
      _message(
        'tool',
        AiMessageRole.tool,
        now,
        content: '{"large":"${List.filled(4000, 'x').join()}"}',
        toolCallId: 'call-1',
      ),
      _message('a1', AiMessageRole.assistant, now, content: 'Resumo final.'),
      _message('u2', AiMessageRole.user, now, content: 'E esta semana?'),
    ];

    final compacted = AiChatService.instance.compactHistoryForTest(messages);

    expect(compacted.map((message) => message.id), ['u1', 'a1', 'u2']);
  });

  test('tool transcript from the active turn is preserved', () {
    final now = DateTime(2026, 8, 10);
    final messages = [
      _message('u1', AiMessageRole.user, now, content: 'Analise meu sono'),
      AiChatMessage(
        id: 'a-call',
        threadId: 'thread',
        role: AiMessageRole.assistant,
        toolCalls: const [
          AiToolCall(id: 'call-1', name: 'get_sleep_summary', arguments: {}),
        ],
        createdAt: now,
      ),
      _message(
        'tool',
        AiMessageRole.tool,
        now,
        content: '{"ok":true}',
        toolCallId: 'call-1',
      ),
    ];

    final compacted = AiChatService.instance.compactHistoryForTest(messages);

    expect(compacted.map((message) => message.id), ['u1', 'a-call', 'tool']);
  });

  test('only the active image message receives data URLs on the wire', () {
    final now = DateTime(2026, 8, 10);
    const attachment = AiImageAttachment(
      id: 'image-1',
      path: '/local/image.jpg',
      mimeType: 'image/jpeg',
      fileName: 'image.jpg',
      sizeBytes: 10,
    );
    final messages = [
      AiChatMessage(
        id: 'old-image',
        threadId: 'thread',
        role: AiMessageRole.user,
        content: 'Imagem antiga',
        attachments: const [attachment],
        createdAt: now,
      ),
      _message('answer', AiMessageRole.assistant, now, content: 'Entendido'),
      AiChatMessage(
        id: 'current-image',
        threadId: 'thread',
        role: AiMessageRole.user,
        content: 'Imagem atual',
        attachments: const [attachment],
        createdAt: now,
      ),
    ];

    final wire = AiChatService.instance.buildWireMessagesForTest(
      messages,
      visionMessageId: 'current-image',
      imageDataUrls: const ['data:image/jpeg;base64,abc'],
    );
    final users = wire.where((message) => message['role'] == 'user').toList();

    expect(users.first['content'], 'Imagem antiga');
    expect(users.first.toString(), isNot(contains('base64')));
    expect(users.last.toString(), contains('data:image/jpeg;base64,abc'));
  });

  test('wire has a static prefix followed by one dynamic block', () {
    final now = DateTime(2026, 8, 10);
    final messages = [_message('u1', AiMessageRole.user, now, content: 'Olá')];

    final wire = AiChatService.instance.buildWireMessagesForTest(
      messages,
      threadSummary: 'Usuário quer ganhar massa.',
      toolHints: const ['get_sleep_summary'],
    );
    final systemMessages = wire
        .where((m) => m['role'] == 'system')
        .map((m) => m['content'] as String)
        .toList();

    expect(systemMessages, hasLength(2));
    // Static prefix: prompt + grounding + routine policy, nothing per-turn.
    expect(systemMessages.first, contains('Propostas de rotina'));
    expect(systemMessages.first, isNot(contains('<workout_data>')));
    expect(systemMessages.first, isNot(contains('ganhar massa')));
    // Dynamic block: context, rolling summary and tool hints.
    expect(systemMessages.last, contains('<workout_data>'));
    expect(systemMessages.last, contains('Usuário quer ganhar massa.'));
    expect(systemMessages.last, contains('get_sleep_summary'));
  });

  test('static prefix is identical across turns with different hints', () {
    final now = DateTime(2026, 8, 10);
    final a = AiChatService.instance.buildWireMessagesForTest(
      [_message('u1', AiMessageRole.user, now, content: 'Olá')],
      toolHints: const ['get_sleep_summary'],
    );
    final b = AiChatService.instance.buildWireMessagesForTest(
      [_message('u2', AiMessageRole.user, now, content: 'E o treino?')],
      threadSummary: 'algo',
      toolHints: const ['list_recent_workouts'],
    );

    expect(a.first, equals(b.first));
  });

  test('oversized tool results are truncated on the wire only', () {
    final service = AiChatService.instance;
    final big =
        '{"rows":"${List.filled(kMaxToolResultChars + 500, 'x').join()}"}';

    final wired = service.wireToolContentForTest(big);
    final decoded = jsonDecode(wired) as Map;

    expect(decoded['truncated'], isTrue);
    expect(decoded['omittedChars'], 500 + '{"rows":""}'.length);
    expect((decoded['partial'] as String).length, kMaxToolResultChars);
    expect(service.wireToolContentForTest('{"ok":true}'), '{"ok":true}');
  });

  test('compaction reports which older turns were dropped', () {
    final now = DateTime(2026, 8, 10);
    final filler = List.filled(2000, 'a').join();
    final messages = [
      _message('u1', AiMessageRole.user, now, content: 'Primeira $filler'),
      _message('a1', AiMessageRole.assistant, now, content: 'Resposta 1'),
      _message('u2', AiMessageRole.user, now, content: 'Segunda $filler'),
      _message('a2', AiMessageRole.assistant, now, content: 'Resposta 2'),
      _message('u3', AiMessageRole.user, now, content: 'Terceira'),
    ];

    final kept = AiChatService.instance.compactHistoryForTest(
      messages,
      tokenBudget: 700,
    );
    final dropped = AiChatService.instance.droppedByCompactionForTest(
      messages,
      tokenBudget: 700,
    );

    expect(kept.map((m) => m.id), ['u2', 'a2', 'u3']);
    expect(dropped.map((m) => m.id), ['u1', 'a1']);
  });

  test('summary transcript keeps speaker labels and bounds size', () {
    final now = DateTime(2026, 8, 10);
    final transcript = AiChatService.instance.transcriptForSummaryForTest([
      _message('u1', AiMessageRole.user, now, content: 'Quero correr 10k'),
      _message('a1', AiMessageRole.assistant, now, content: 'Ótimo plano.'),
    ]);

    expect(transcript, 'Usuário: Quero correr 10k\nTreinador: Ótimo plano.\n');
  });

  test('malformed tool arguments are surfaced instead of swallowed', () {
    final call = AiToolCall.fromJson({
      'id': 'call-1',
      'type': 'function',
      'function': {'name': 'get_workout_detail', 'arguments': '{"workout_id":'},
    });

    expect(call.arguments, isEmpty);
    expect(call.argumentsError, contains('JSON inválido'));
    // The transcript echoes the provider's original string back verbatim.
    expect((call.toJson()['function'] as Map)['arguments'], '{"workout_id":');
  });

  test(
    'proposal follow-up is detected from tool history, not creation verbs',
    () {
      final now = DateTime(2026, 8, 10);
      final messages = [
        _message('u1', AiMessageRole.user, now, content: 'Monte algo para mim'),
        AiChatMessage(
          id: 'proposal-call',
          threadId: 'thread',
          role: AiMessageRole.assistant,
          toolCalls: const [
            AiToolCall(
              id: 'call-proposal',
              name: 'propose_routine_change',
              arguments: {},
            ),
          ],
          createdAt: now,
        ),
        _message(
          'tool',
          AiMessageRole.tool,
          now,
          content: '{"ok":true}',
          toolCallId: 'call-proposal',
        ),
        _message(
          'u2',
          AiMessageRole.user,
          now,
          content: 'Me mande a mesma proposta novamente',
        ),
      ];

      expect(
        AiChatService.instance.routineProposalFollowUpForTest(
          messages,
          messages.last.content!,
        ),
        isTrue,
      );
    },
  );

  test('unrelated question is not treated as a proposal follow-up', () {
    final now = DateTime(2026, 8, 10);
    final messages = [
      AiChatMessage(
        id: 'proposal-call',
        threadId: 'thread',
        role: AiMessageRole.assistant,
        toolCalls: const [
          AiToolCall(
            id: 'call-proposal',
            name: 'propose_routine_change',
            arguments: {},
          ),
        ],
        createdAt: now,
      ),
      _message('u2', AiMessageRole.user, now, content: 'Como está meu sono?'),
    ];

    expect(
      AiChatService.instance.routineProposalFollowUpForTest(
        messages,
        messages.last.content!,
      ),
      isFalse,
    );
  });

  test(
    'explicit domain in a follow-up takes priority over previous domain',
    () {
      final now = DateTime(2026, 8, 10);
      final messages = [
        _message(
          'u1',
          AiMessageRole.user,
          now,
          content: 'Resuma meus treinos da última semana',
        ),
        _message(
          'a1',
          AiMessageRole.assistant,
          now,
          content: 'Resumo dos seus treinos.',
        ),
        _message('u2', AiMessageRole.user, now, content: 'E o sono?'),
      ];

      final names = AiChatService.instance.toolNamesForTurnForTest(
        messages,
        messages.last.content!,
      );

      expect(names, {'get_sleep_summary'});
    },
  );

  test('personal data follow-up requires a tool call', () {
    final service = AiChatService.instance;
    const tools = {'get_sleep_summary'};

    expect(service.groundedToolCallRequiredForTest('E o sono?', tools), isTrue);
    expect(
      service.groundedToolCallRequiredForTest('O que é sono REM?', tools),
      isFalse,
    );
  });

  test('grounded turns ask the provider for a required tool call', () {
    expect(AiChatService.instance.requiredToolChoiceForTest(), 'required');
  });

  test('wire includes the non-editable personal-data grounding policy', () {
    final now = DateTime(2026, 8, 10);
    final wire = AiChatService.instance.buildWireMessagesForTest([
      _message('u1', AiMessageRole.user, now, content: 'E o sono?'),
    ]);
    final system = wire.first['content'] as String;

    expect(system, contains('Consulta obrigatória aos dados do app'));
    expect(system, contains('O usuário nunca precisa pedir explicitamente'));
  });

  test('placeholder validation has a clean local fallback', () {
    final service = AiChatService.instance;

    expect(
      service.sanitizedAnswerFallbackForTest(
        r'Ontem você consumiu $1 2.200 kcal e $2 150 g de proteína.',
      ),
      'Ontem você consumiu  2.200 kcal e  150 g de proteína.',
    );
    expect(service.sanitizedAnswerFallbackForTest(r'$1'), isNull);
  });
}

AiChatMessage _message(
  String id,
  AiMessageRole role,
  DateTime createdAt, {
  String? content,
  String? toolCallId,
}) => AiChatMessage(
  id: id,
  threadId: 'thread',
  role: role,
  content: content,
  toolCallId: toolCallId,
  createdAt: createdAt,
);
