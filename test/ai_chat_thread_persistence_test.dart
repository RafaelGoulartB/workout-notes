import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/models/ai_chat_message.dart';
import 'package:workout_notes/models/ai_chat_thread.dart';
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

    await helper.aiChatRepo.upsertAiChatThread(
      id: 'recent',
      title: 'Recent',
      createdAt: older,
      updatedAt: newer,
    );
    await helper.aiChatRepo.upsertAiChatThread(
      id: 'pinned',
      title: 'Pinned',
      createdAt: older,
      updatedAt: older,
      isPinned: true,
    );

    var threads = await helper.aiChatRepo.getAiChatThreadsPage(limit: 100);
    expect(threads.map((thread) => thread['id']), ['pinned', 'recent']);

    await helper.aiChatRepo.upsertAiChatThread(
      id: 'pinned',
      title: 'Pinned updated',
      createdAt: older,
      updatedAt: newer,
      isPinned: true,
    );
    threads = await helper.aiChatRepo.getAiChatThreadsPage(limit: 100);
    expect(threads.first['is_pinned'], 1);
  });

  test('upserting a thread does not cascade-delete its proposals', () async {
    final helper = DatabaseHelper.instance;
    final database = await helper.database;
    final timestamp = DateTime.utc(2026, 1, 2);
    await helper.aiChatRepo.upsertAiChatThread(
      id: 'proposal-thread',
      title: 'Before',
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    await database.insert('ai_proposals', {
      'id': 'proposal',
      'thread_id': 'proposal-thread',
      'tool_call_id': 'call',
      'kind': 'routine',
      'payload_json': '{}',
      'preview_json': '{}',
      'status': 'awaiting',
      'created_at': timestamp.toIso8601String(),
    });

    await helper.aiChatRepo.upsertAiChatThread(
      id: 'proposal-thread',
      title: 'After',
      createdAt: timestamp,
      updatedAt: timestamp.add(const Duration(minutes: 1)),
    );

    expect(await database.query('ai_proposals'), hasLength(1));
  });

  test('renaming preserves the conversation activity timestamp', () async {
    final helper = DatabaseHelper.instance;
    final timestamp = DateTime.utc(2026, 1, 3, 12);
    await helper.aiChatRepo.upsertAiChatThread(
      id: 'thread',
      title: 'Before',
      createdAt: timestamp,
      updatedAt: timestamp,
    );

    await helper.aiChatRepo.renameAiChatThread('thread', 'After');
    final thread = (await helper.aiChatRepo.getAiChatThreadsPage(
      limit: 100,
    )).single;
    expect(thread['title'], 'After');
    expect(thread['updated_at'], timestamp.toIso8601String());
  });

  test('message image metadata survives SQLite persistence', () async {
    final helper = DatabaseHelper.instance;
    final timestamp = DateTime.utc(2026, 1, 3, 12);
    await helper.aiChatRepo.upsertAiChatThread(
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

    await helper.aiChatRepo.upsertAiChatMessages('thread-images', [
      message.toRow(),
    ]);
    final restored = AiChatMessage.fromRow(
      (await helper.aiChatRepo.getAiChatMessagesAfter('thread-images')).single,
    );
    expect(restored.attachments.single.fileName, 'image.jpg');
    expect(restored.attachments.single.sizeBytes, 42);
  });

  test('keyset pages never skip or repeat rows sharing a timestamp', () async {
    final repo = DatabaseHelper.instance.aiChatRepo;
    final timestamp = DateTime.utc(2026, 1, 3, 12);
    await repo.upsertAiChatThread(
      id: 'thread',
      title: 'T',
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    await repo.upsertAiChatMessages('thread', [
      for (var i = 0; i < 25; i++)
        AiChatMessage(
          id: 'm${i.toString().padLeft(2, '0')}',
          threadId: 'thread',
          role: AiMessageRole.user,
          content: 'msg $i',
          // Groups of five share a timestamp.
          createdAt: timestamp.add(Duration(seconds: i ~/ 5)),
        ).toRow(),
    ]);
    final seen = <String>[];
    var page = await repo.getAiChatMessagesPage('thread', limit: 7);
    seen.insertAll(0, page.map((r) => r['id'] as String));
    while (page.isNotEmpty) {
      page = await repo.getAiChatMessagesPage(
        'thread',
        limit: 7,
        beforeCreatedAt: page.first['created_at'] as String,
        beforeId: page.first['id'] as String,
      );
      seen.insertAll(0, page.map((r) => r['id'] as String));
    }
    expect(seen, [
      for (var i = 0; i < 25; i++) 'm${i.toString().padLeft(2, '0')}',
    ]);
  });

  test(
    'deleting messages also drops the pending proposals they created',
    () async {
      final helper = DatabaseHelper.instance;
      final database = await helper.database;
      final timestamp = DateTime.utc(2026, 1, 3, 12);
      await helper.aiChatRepo.upsertAiChatThread(
        id: 'thread',
        title: 'T',
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      await helper.aiChatRepo.upsertAiChatMessages('thread', [
        AiChatMessage(
          id: 'm1',
          threadId: 'thread',
          role: AiMessageRole.assistant,
          content: 'x',
          createdAt: timestamp,
        ).toRow(),
      ]);
      await database.insert('ai_proposals', {
        'id': 'p',
        'thread_id': 'thread',
        'tool_call_id': 'call',
        'kind': 'routine',
        'payload_json': '{}',
        'preview_json': '{}',
        'status': 'awaiting',
        'created_at': timestamp.toIso8601String(),
      });
      await helper.aiChatRepo.deleteAiChatMessages(
        'thread',
        ['m1'],
        toolCallIds: ['call'],
      );
      expect(await database.query('ai_chat_messages'), isEmpty);
      expect(await database.query('ai_proposals'), isEmpty);
    },
  );
}
