import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/database/database_helper.dart';

import 'support/ai_test_db.dart';

void main() {
  tearDown(uninstallAiTestDb);

  test(
    'chat pages newest messages and upserts without deleting history',
    () async {
      final db = await installAiTestDb();
      final helper = DatabaseHelper.instance;
      await db.insert('ai_chat_threads', {
        'id': 'thread',
        'title': 'Thread',
        'created_at': '2026-08-20T00:00:00.000',
        'updated_at': '2026-08-20T00:00:00.000',
      });
      for (var index = 0; index < 105; index++) {
        await db.insert('ai_chat_messages', {
          'id': 'message-$index',
          'thread_id': 'thread',
          'role': 'user',
          'content': 'before-$index',
          'created_at': DateTime(
            2026,
            8,
            20,
          ).add(Duration(minutes: index)).toIso8601String(),
        });
      }

      final latest = await helper.aiChatRepo.getAiChatMessagesPage(
        'thread',
        limit: 3,
      );
      expect(latest.map((row) => row['id']), [
        'message-102',
        'message-103',
        'message-104',
      ]);

      await helper.aiChatRepo.upsertAiChatMessages('thread', [
        {
          'id': 'message-104',
          'role': 'assistant',
          'content': 'updated',
          'created_at': DateTime(2026, 8, 20, 1, 44).toIso8601String(),
        },
      ]);
      final count = (await db.rawQuery(
        'SELECT COUNT(*) AS count FROM ai_chat_messages',
      )).first['count'];
      final updated = await db.query(
        'ai_chat_messages',
        where: 'id = ?',
        whereArgs: ['message-104'],
      );
      expect(count, 105);
      expect(updated.single['content'], 'updated');
    },
  );
}
