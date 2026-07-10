import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/ai_chat_message.dart';
import 'package:workout_notes/models/ai_message_role.dart';
import 'package:workout_notes/widgets/ai/ai_message_bubble.dart';

void main() {
  testWidgets('renders markdown captures instead of literal dollar one', (
    tester,
  ) async {
    final message = AiChatMessage(
      id: 'message-1',
      threadId: 'thread-1',
      role: AiMessageRole.assistant,
      content: '**Agachamento**: 60x10\n*Supino reto*: 50x10',
      createdAt: DateTime(2026, 6, 30),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiMessageBubble(message: message, showTimestamp: false),
        ),
      ),
    );

    expect(find.textContaining('Agachamento: 60x10'), findsOneWidget);
    expect(find.textContaining('Supino reto: 50x10'), findsOneWidget);
    expect(find.textContaining(r'$1'), findsNothing);
  });
}
