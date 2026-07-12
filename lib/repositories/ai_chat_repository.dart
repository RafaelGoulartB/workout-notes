import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/models/ai_chat_message.dart';
import 'package:workout_notes/models/ai_chat_thread.dart';
import 'package:workout_notes/repositories/base_repository.dart';

/// Persistence boundary for AI conversation threads and messages.
class AiChatRepository extends BaseRepository {
  AiChatRepository([super.databaseProvider]);

  Future<void> saveThread(AiChatThread thread) async {
    final database = await db;
    await database.insert(
      'ai_chat_threads',
      thread.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<AiChatThread>> getThreads() async {
    final database = await db;
    final rows = await database.query(
      'ai_chat_threads',
      where: 'archived = 0',
      orderBy: 'is_pinned DESC, updated_at DESC',
    );
    return rows.map(AiChatThread.fromRow).toList();
  }

  Future<List<AiChatMessage>> getMessages(String threadId) async {
    final database = await db;
    final rows = await database.query(
      'ai_chat_messages',
      where: 'thread_id = ?',
      whereArgs: [threadId],
      orderBy: 'created_at ASC',
    );
    return rows.map(AiChatMessage.fromRow).toList();
  }

  Future<void> replaceMessages(
    String threadId,
    List<AiChatMessage> messages,
  ) async {
    final database = await db;
    await database.transaction((transaction) async {
      await transaction.delete(
        'ai_chat_messages',
        where: 'thread_id = ?',
        whereArgs: [threadId],
      );
      for (final message in messages) {
        await transaction.insert('ai_chat_messages', message.toRow());
      }
    });
  }

  Future<void> renameThread(String threadId, String title) async {
    final database = await db;
    await database.update(
      'ai_chat_threads',
      {'title': title},
      where: 'id = ?',
      whereArgs: [threadId],
    );
  }

  Future<void> setThreadPinned(String threadId, bool isPinned) async {
    final database = await db;
    await database.update(
      'ai_chat_threads',
      {'is_pinned': isPinned ? 1 : 0},
      where: 'id = ?',
      whereArgs: [threadId],
    );
  }

  Future<void> deleteThread(String threadId) async {
    final database = await db;
    await database.delete(
      'ai_chat_threads',
      where: 'id = ?',
      whereArgs: [threadId],
    );
  }
}
