import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/repositories/base_repository.dart';
import 'package:workout_notes/utils/text_fold.dart';

/// Repository for AI Coach persistence: chat threads, messages and rolling
/// thread summaries. Proposals live in `AiProposalRepository`, memories in
/// `AiMemoryRepository`.
class AiChatRepository extends BaseRepository {
  /// Creates or updates a thread row. `archived` is never touched here.
  Future<String> upsertAiChatThread({
    required String id,
    required String title,
    required DateTime createdAt,
    required DateTime updatedAt,
    String? lastMessagePreview,
    bool isPinned = false,
  }) async {
    final db = await this.db;
    final values = {
      'title': title,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'last_message_preview': lastMessagePreview,
      'is_pinned': isPinned ? 1 : 0,
      'search_text': foldForSearch('$title ${lastMessagePreview ?? ''}'),
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

  /// Inserts or replaces message rows of [threadId] in one batch.
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

  /// Deletes messages of [threadId] by id, plus the proposals their tool
  /// calls created (used when a turn is retried from an earlier message).
  Future<void> deleteAiChatMessages(
    String threadId,
    List<String> messageIds, {
    List<String> toolCallIds = const [],
  }) async {
    if (messageIds.isEmpty && toolCallIds.isEmpty) return;
    final db = await this.db;
    await db.transaction((txn) async {
      for (final chunk in _chunks(messageIds)) {
        await txn.delete(
          'ai_chat_messages',
          where:
              'thread_id = ? AND id IN (${List.filled(chunk.length, '?').join(',')})',
          whereArgs: [threadId, ...chunk],
        );
      }
      for (final chunk in _chunks(toolCallIds)) {
        await txn.delete(
          'ai_proposals',
          where:
              "thread_id = ? AND status = 'awaiting' AND tool_call_id IN (${List.filled(chunk.length, '?').join(',')})",
          whereArgs: [threadId, ...chunk],
        );
      }
    });
  }

  /// Sets the turn status stored on a user message.
  Future<void> setTurnStatus(String messageId, String status) async {
    final db = await this.db;
    await db.update(
      'ai_chat_messages',
      {'turn_status': status},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  /// Replaces the content of old tool messages (already sent as stubs) with
  /// a compact archived marker, so stored payloads stop growing.
  Future<void> archiveToolPayloads(
    String threadId, {
    required String throughCreatedAt,
    required String archivedContent,
    int minLength = 2000,
  }) async {
    final db = await this.db;
    await db.rawUpdate(
      '''
      UPDATE ai_chat_messages SET content = ?
      WHERE thread_id = ? AND role = 'tool' AND created_at <= ?
        AND LENGTH(content) > ?
        AND tool_name NOT LIKE 'propose_%'
      ''',
      [archivedContent, threadId, throughCreatedAt, minLength],
    );
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

  /// Pages through the threads whose title, preview or message text contains
  /// [query] (case- and accent-insensitive), pinned first, then most
  /// recently updated.
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
    final pattern = '%${escapeLike(foldForSearch(trimmed))}%';
    return (
      sql:
          " AND (t.search_text LIKE ? ESCAPE '\\'"
          ' OR EXISTS (SELECT 1 FROM ai_chat_messages m'
          ' WHERE m.thread_id = t.id'
          " AND m.search_text LIKE ? ESCAPE '\\'))",
      args: [pattern, pattern],
    );
  }

  /// Only the attachment column of a thread's messages (for file cleanup).
  Future<List<String>> getAttachmentsJson(String threadId) async {
    final db = await this.db;
    final rows = await db.query(
      'ai_chat_messages',
      columns: ['attachments_json'],
      where: 'thread_id = ? AND attachments_json IS NOT NULL',
      whereArgs: [threadId],
    );
    return [for (final row in rows) row['attachments_json'] as String];
  }

  /// Every stored attachment column (orphan image cleanup).
  Future<List<String>> getAllAttachmentsJson() async {
    final db = await this.db;
    final rows = await db.query(
      'ai_chat_messages',
      columns: ['attachments_json'],
      where: 'attachments_json IS NOT NULL',
    );
    return [for (final row in rows) row['attachments_json'] as String];
  }

  /// The newest [limit] messages of a thread older than the keyset
  /// ([beforeCreatedAt], [beforeId]); oldest first. Without a keyset, the
  /// newest page. `(created_at, id)` is a total order, so pages never skip
  /// or repeat rows whatever is added or removed meanwhile.
  Future<List<Map<String, dynamic>>> getAiChatMessagesPage(
    String threadId, {
    required int limit,
    String? beforeCreatedAt,
    String? beforeId,
  }) async {
    final db = await this.db;
    final keyset = beforeCreatedAt != null && beforeId != null;
    final rows = await db.query(
      'ai_chat_messages',
      where: keyset
          ? 'thread_id = ? AND (created_at < ? OR (created_at = ? AND id < ?))'
          : 'thread_id = ?',
      whereArgs: keyset
          ? [threadId, beforeCreatedAt, beforeCreatedAt, beforeId]
          : [threadId],
      orderBy: 'created_at DESC, id DESC',
      limit: limit,
    );
    return rows.reversed.toList(growable: false);
  }

  /// Every message of a thread after the keyset ([afterCreatedAt],
  /// [afterId]), oldest first; the whole thread without a keyset. This is
  /// what a turn sends: everything after the summarized part.
  Future<List<Map<String, dynamic>>> getAiChatMessagesAfter(
    String threadId, {
    String? afterCreatedAt,
    String? afterId,
  }) async {
    final db = await this.db;
    final keyset = afterCreatedAt != null && afterId != null;
    return db.query(
      'ai_chat_messages',
      where: keyset
          ? 'thread_id = ? AND (created_at > ? OR (created_at = ? AND id > ?))'
          : 'thread_id = ?',
      whereArgs: keyset
          ? [threadId, afterCreatedAt, afterCreatedAt, afterId]
          : [threadId],
      orderBy: 'created_at ASC, id ASC',
    );
  }

  Future<Map<String, dynamic>?> getAiChatMessage(String id) async {
    final db = await this.db;
    final rows = await db.query(
      'ai_chat_messages',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<bool> messageExists(String id) async {
    final db = await this.db;
    final rows = await db.query(
      'ai_chat_messages',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> renameAiChatThread(String threadId, String title) async {
    final db = await this.db;
    final rows = await db.query(
      'ai_chat_threads',
      columns: ['last_message_preview'],
      where: 'id = ?',
      whereArgs: [threadId],
      limit: 1,
    );
    final preview = rows.isEmpty
        ? ''
        : (rows.first['last_message_preview'] as String? ?? '');
    await db.update(
      'ai_chat_threads',
      {'title': title, 'search_text': foldForSearch('$title $preview')},
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
    String? toolsThroughMessageId,
  }) async {
    final db = await this.db;
    await db.insert('ai_chat_thread_summaries', {
      'thread_id': threadId,
      'summary': summary,
      'through_message_id': throughMessageId,
      'tools_through_message_id': toolsThroughMessageId,
      'updated_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteAiChatThreadSummary(String threadId) async {
    final db = await this.db;
    await db.delete(
      'ai_chat_thread_summaries',
      where: 'thread_id = ?',
      whereArgs: [threadId],
    );
  }

  static Iterable<List<String>> _chunks(List<String> ids) sync* {
    const size = 400;
    for (var i = 0; i < ids.length; i += size) {
      yield ids.sublist(i, i + size > ids.length ? ids.length : i + size);
    }
  }
}
