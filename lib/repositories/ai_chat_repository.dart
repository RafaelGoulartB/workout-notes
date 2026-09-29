import 'package:sqflite/sqflite.dart';
import 'base_repository.dart';

/// Repository for AI Coach persistence: chat threads, messages, rolling thread
/// summaries and routine proposals.
class AiChatRepository extends BaseRepository {
  Future<void> insertAiRoutineProposal(Map<String, dynamic> row) async {
    final db = await this.db;
    await db.insert('ai_routine_proposals', row);
  }

  Future<Map<String, dynamic>?> getAiRoutineProposal(String id) async {
    final db = await this.db;
    final rows = await db.query(
      'ai_routine_proposals',
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, dynamic>>> getAiRoutineProposalsThread(
    String threadId,
  ) async {
    final db = await this.db;
    return db.query(
      'ai_routine_proposals',
      where: 'thread_id = ?',
      whereArgs: [threadId],
      orderBy: 'created_at ASC',
    );
  }

  Future<void> updateAiRoutineProposal(
    String id,
    Map<String, dynamic> values,
  ) async {
    final db = await this.db;
    await db.update(
      'ai_routine_proposals',
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<String> upsertAiChatThread({
    required String id,
    required String title,
    required DateTime createdAt,
    required DateTime updatedAt,
    String? lastMessagePreview,
    bool archived = false,
    bool isPinned = false,
  }) async {
    final db = await this.db;
    final values = {
      'title': title,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'last_message_preview': lastMessagePreview,
      'archived': archived ? 1 : 0,
      'is_pinned': isPinned ? 1 : 0,
    };
    await db.transaction((txn) async {
      final updated = await txn.update(
        'ai_chat_threads',
        values,
        where: 'id = ?',
        whereArgs: [id],
      );
      if (updated == 0) {
        await txn.insert('ai_chat_threads', {'id': id, ...values});
      }
    });
    return id;
  }

  Future<void> upsertAiChatMessages(
    String threadId,
    List<Map<String, dynamic>> messages,
  ) async {
    if (messages.isEmpty) return;
    final db = await this.db;
    final batch = db.batch();
    for (final message in messages) {
      batch.insert('ai_chat_messages', {
        ...message,
        'thread_id': threadId,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getAiChatThreadsPage({
    required int limit,
    int offset = 0,
  }) async {
    final db = await this.db;
    return db.query(
      'ai_chat_threads',
      where: 'archived = 0',
      orderBy: 'is_pinned DESC, updated_at DESC',
      limit: limit,
      offset: offset,
    );
  }

  Future<Map<String, dynamic>?> getAiChatThread(String threadId) async {
    final db = await this.db;
    final rows = await db.query(
      'ai_chat_threads',
      where: 'id = ? AND archived = 0',
      whereArgs: [threadId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// Number of visible threads, optionally only those matching [query].
  Future<int> countAiChatThreads({String? query}) async {
    final db = await this.db;
    final search = _searchClause(query);
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM ai_chat_threads t WHERE t.archived = 0'
      '${search.sql}',
      search.args,
    );
    return (rows.first['n'] as num?)?.toInt() ?? 0;
  }

  /// Pages through the threads whose title, preview or user/assistant message
  /// text contains [query], in the same order as [getAiChatThreadsPage]
  /// (pinned first, then most recently updated). Unlike filtering the loaded
  /// list this reaches every stored conversation.
  Future<List<Map<String, dynamic>>> searchAiChatThreadsPage({
    required String query,
    required int limit,
    int offset = 0,
  }) async {
    final db = await this.db;
    final search = _searchClause(query);
    return db.rawQuery(
      'SELECT t.* FROM ai_chat_threads t WHERE t.archived = 0'
      '${search.sql} '
      'ORDER BY t.is_pinned DESC, t.updated_at DESC LIMIT ? OFFSET ?',
      [...search.args, limit, offset],
    );
  }

  /// Escapes LIKE wildcards so user input is matched literally.
  static String escapeLike(String value) => value
      .replaceAll('\\', '\\\\')
      .replaceAll('%', '\\%')
      .replaceAll('_', '\\_');

  ({String sql, List<Object?> args}) _searchClause(String? query) {
    final trimmed = query?.trim() ?? '';
    if (trimmed.isEmpty) return (sql: '', args: const []);
    final pattern = '%${escapeLike(trimmed)}%';
    return (
      sql:
          " AND (t.title LIKE ? ESCAPE '\\'"
          " OR t.last_message_preview LIKE ? ESCAPE '\\'"
          ' OR EXISTS (SELECT 1 FROM ai_chat_messages m'
          ' WHERE m.thread_id = t.id'
          " AND m.role IN ('user', 'assistant')"
          " AND m.content LIKE ? ESCAPE '\\'))",
      args: [pattern, pattern, pattern],
    );
  }

  Future<List<Map<String, dynamic>>> getAiChatMessagesThread(
    String threadId,
  ) async {
    final db = await this.db;
    return db.query(
      'ai_chat_messages',
      where: 'thread_id = ?',
      whereArgs: [threadId],
      orderBy: 'created_at ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getAiChatMessagesThreadPage(
    String threadId, {
    required int limit,
    int offset = 0,
  }) async {
    final db = await this.db;
    final rows = await db.query(
      'ai_chat_messages',
      where: 'thread_id = ?',
      whereArgs: [threadId],
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );
    return rows.reversed.toList(growable: false);
  }

  Future<void> renameAiChatThread(String threadId, String title) async {
    final db = await this.db;
    await db.update(
      'ai_chat_threads',
      {'title': title},
      where: 'id = ?',
      whereArgs: [threadId],
    );
  }

  Future<void> setAiChatThreadPinned(String threadId, bool isPinned) async {
    final db = await this.db;
    await db.update(
      'ai_chat_threads',
      {'is_pinned': isPinned ? 1 : 0},
      where: 'id = ?',
      whereArgs: [threadId],
    );
  }

  Future<void> deleteAiChatThread(String threadId) async {
    final db = await this.db;
    await db.delete('ai_chat_threads', where: 'id = ?', whereArgs: [threadId]);
  }

  Future<Map<String, dynamic>?> getAiChatThreadSummary(String threadId) async {
    final db = await this.db;
    final rows = await db.query(
      'ai_chat_thread_summaries',
      where: 'thread_id = ?',
      whereArgs: [threadId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> upsertAiChatThreadSummary({
    required String threadId,
    required String summary,
    required String throughMessageId,
  }) async {
    final db = await this.db;
    await db.insert('ai_chat_thread_summaries', {
      'thread_id': threadId,
      'summary': summary,
      'through_message_id': throughMessageId,
      'updated_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
