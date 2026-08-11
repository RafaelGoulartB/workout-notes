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
