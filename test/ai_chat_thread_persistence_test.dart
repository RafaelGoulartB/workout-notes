import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/models/ai_chat_thread.dart';
import 'package:workout_notes/models/ai_chat_message.dart';
import 'package:workout_notes/models/ai_image_attachment.dart';
import 'package:workout_notes/models/ai_message_role.dart';

import 'support/ai_test_db.dart';

void main() {
  setUp(installAiTestDb);
  tearDown(uninstallAiTestDb);

  test('AiChatThread serializes its pinned state', () {
    final thread = AiChatThread(
      id: 'thread-1',
      title: 'Pinned thread',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 2),
      isPinned: true,
    );

    expect(AiChatThread.fromRow(thread.toRow()).isPinned, isTrue);
  });

  test('pinned threads sort first and remain pinned after an upsert', () async {
    final helper = DatabaseHelper.instance;
    final older = DateTime.utc(2026, 1, 1);
    final newer = DateTime.utc(2026, 1, 2);

    await helper.upsertAiChatThread(
      id: 'recent',
      title: 'Recent',
      createdAt: older,
      updatedAt: newer,
    );
    await helper.upsertAiChatThread(
      id: 'pinned',
      title: 'Pinned',
      createdAt: older,
      updatedAt: older,
      isPinned: true,
    );

    var threads = await helper.getAiChatThreads();
    expect(threads.map((thread) => thread['id']), ['pinned', 'recent']);

    await helper.upsertAiChatThread(
      id: 'pinned',
      title: 'Pinned updated',
      createdAt: older,
      updatedAt: newer,
      isPinned: true,
    );
    threads = await helper.getAiChatThreads();
    expect(threads.first['is_pinned'], 1);
  });

  test(
    'upserting a thread does not cascade-delete its routine proposal',
    () async {
      final helper = DatabaseHelper.instance;
      final database = await helper.database;
      final timestamp = DateTime.utc(2026, 1, 2);
      await helper.upsertAiChatThread(
        id: 'proposal-thread',
        title: 'Before',
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      await database.insert('ai_routine_proposals', {
        'id': 'proposal',
        'thread_id': 'proposal-thread',
        'tool_call_id': 'call',
        'action': 'create',
        'target_json': '{"name":"Test","days":[]}',
        'diff_json': '{}',
        'status': 'awaitingApproval',
        'created_at': timestamp.toIso8601String(),
      });

      await helper.upsertAiChatThread(
        id: 'proposal-thread',
        title: 'After',
        createdAt: timestamp,
        updatedAt: timestamp.add(const Duration(minutes: 1)),
      );

      expect(await helper.getAiRoutineProposal('proposal'), isNotNull);
    },
  );

  test('renaming preserves the conversation activity timestamp', () async {
    final helper = DatabaseHelper.instance;
    final timestamp = DateTime.utc(2026, 1, 3, 12);
    await helper.upsertAiChatThread(
      id: 'thread',
      title: 'Before',
      createdAt: timestamp,
      updatedAt: timestamp,
    );

    await helper.renameAiChatThread('thread', 'After');
    final thread = (await helper.getAiChatThreads()).single;
    expect(thread['title'], 'After');
    expect(thread['updated_at'], timestamp.toIso8601String());
  });

  test('message image metadata survives SQLite persistence', () async {
    final helper = DatabaseHelper.instance;
    final timestamp = DateTime.utc(2026, 1, 3, 12);
    await helper.upsertAiChatThread(
      id: 'thread-images',
      title: 'Images',
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    final message = AiChatMessage(
      id: 'message-images',
      threadId: 'thread-images',
      role: AiMessageRole.user,
      content: 'Analise',
      attachments: const [
        AiImageAttachment(
          id: 'image',
          path: '/local/image.jpg',
          mimeType: 'image/jpeg',
          fileName: 'image.jpg',
          sizeBytes: 42,
        ),
      ],
      createdAt: timestamp,
    );

    await helper.replaceAiChatMessages('thread-images', [message.toRow()]);
    final restored = AiChatMessage.fromRow(
      (await helper.getAiChatMessagesThread('thread-images')).single,
    );
    expect(restored.attachments.single.fileName, 'image.jpg');
    expect(restored.attachments.single.sizeBytes, 42);
  });
}
