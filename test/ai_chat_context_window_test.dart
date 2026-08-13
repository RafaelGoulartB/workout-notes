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

  test('routine safety policy is omitted from unrelated turns', () {
    final now = DateTime(2026, 8, 10);
    final messages = [_message('u1', AiMessageRole.user, now, content: 'Olá')];

    final wire = AiChatService.instance.buildWireMessagesForTest(messages);
    final systemMessages = wire.where((m) => m['role'] == 'system');

    expect(systemMessages, hasLength(1));
  });

  test('routine safety policy remains present for mutation turns', () {
    final now = DateTime(2026, 8, 10);
    final wire = AiChatService.instance.buildWireMessagesForTest([
      _message('u1', AiMessageRole.user, now, content: 'Crie uma rotina'),
    ], includeRoutinePolicy: true);

    expect(wire.where((m) => m['role'] == 'system'), hasLength(2));
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

  test('single selected data tool uses portable auto choice', () {
    final choice = AiChatService.instance.requiredToolChoiceForTest(const {
      'get_sleep_summary',
    });

    expect(choice, 'auto');
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
