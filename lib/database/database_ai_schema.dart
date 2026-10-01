import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/utils/text_fold.dart';

/// AI Coach tables added in v61: generic proposals, long-term memories and
/// the columns that make a chat turn durable (turn status, provider extras,
/// folded search text). Shared by `onCreate` and the v61 upgrade.
abstract final class DatabaseAiSchema {
  /// Columns added to `ai_chat_messages` / `ai_chat_threads` in v61. `onCreate`
  /// adds them with the same statements so both paths match.
  static const List<String> v61Columns = [
    // Opaque provider fields (reasoning_content, reasoning_details, tool-call
    // extra_content…) echoed back verbatim inside the same turn.
    'ALTER TABLE ai_chat_messages ADD COLUMN provider_extras TEXT',
    // Set on user rows: running | done | failed | cancelled | interrupted.
    'ALTER TABLE ai_chat_messages ADD COLUMN turn_status TEXT',
    // Lowercased, accent-stripped content for search.
    'ALTER TABLE ai_chat_messages ADD COLUMN search_text TEXT',
    'ALTER TABLE ai_chat_threads ADD COLUMN search_text TEXT',
    // Tool results up to this message are sent as short stubs. Moves only at
    // compaction events, together with the summary cut, so the history the
    // provider caches stays byte-identical between them.
    'ALTER TABLE ai_chat_thread_summaries ADD COLUMN tools_through_message_id TEXT',
  ];

  static Future<void> create(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_proposals (
        id TEXT PRIMARY KEY,
        thread_id TEXT NOT NULL,
        tool_call_id TEXT NOT NULL,
        kind TEXT NOT NULL,
        subject_id TEXT,
        base_hash TEXT,
        base_json TEXT,
        payload_json TEXT NOT NULL,
        preview_json TEXT NOT NULL,
        status TEXT NOT NULL CHECK (status IN
          ('awaiting', 'applied', 'rejected', 'stale', 'failed', 'expired')),
        result_json TEXT,
        error_code TEXT,
        created_at TEXT NOT NULL,
        resolved_at TEXT,
        FOREIGN KEY (thread_id) REFERENCES ai_chat_threads(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ai_proposals_thread ON ai_proposals(thread_id, created_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ai_proposals_tool_call ON ai_proposals(tool_call_id)',
    );
    // Facts the coach keeps across conversations. No FK on the source thread:
    // a memory outlives the conversation it came from.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_memories (
        id TEXT PRIMARY KEY,
        content TEXT NOT NULL,
        category TEXT,
        source_thread_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    // Keyset pagination of a thread: (created_at, id) is a total order.
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ai_chat_messages_thread_keyset ON ai_chat_messages(thread_id, created_at, id)',
    );
  }

  /// Copies the v17 `ai_routine_proposals` rows into `ai_proposals` (kind
  /// `routine`). Legacy rows keep their diff as preview; the routine handler
  /// rebuilds a full preview from `payload_json` when it reads one.
  static Future<void> migrateRoutineProposals(DatabaseExecutor db) async {
    final legacy = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' "
      "AND name = 'ai_routine_proposals'",
    );
    if (legacy.isEmpty) return;
    final rows = await db.query('ai_routine_proposals');
    for (final row in rows) {
      final status = switch (row['status']) {
        'awaitingApproval' => 'awaiting',
        'applied' => 'applied',
        'rejected' => 'rejected',
        'stale' => 'stale',
        _ => 'failed',
      };
      final applied = row['applied_routine_id'] as String?;
      await db.insert('ai_proposals', {
        'id': row['id'],
        'thread_id': row['thread_id'],
        'tool_call_id': row['tool_call_id'],
        'kind': 'routine',
        'subject_id': row['routine_id'],
        'base_json': row['before_json'],
        'payload_json': jsonEncode({
          'action': row['action'],
          'routine_id': row['routine_id'],
          'routine': _decodeOr(row['target_json'], const {}),
        }),
        'preview_json': row['diff_json'] ?? '{}',
        'status': status,
        'result_json': applied == null
            ? null
            : jsonEncode({'routine_id': applied}),
        'error_code': row['error_code'],
        'created_at': row['created_at'],
        'resolved_at': row['resolved_at'],
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  static Object? _decodeOr(Object? raw, Object fallback) {
    if (raw is! String || raw.isEmpty) return fallback;
    try {
      return jsonDecode(raw);
    } on FormatException {
      return fallback;
    }
  }

  /// Fills the folded search columns for rows written before v61.
  static Future<void> backfillSearchText(DatabaseExecutor db) async {
    final messages = await db.query(
      'ai_chat_messages',
      columns: ['id', 'content'],
      where:
          "role IN ('user', 'assistant') AND content IS NOT NULL "
          'AND search_text IS NULL',
    );
    final batch = db.batch();
    for (final row in messages) {
      batch.update(
        'ai_chat_messages',
        {'search_text': foldForSearch(row['content'] as String)},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
    final threads = await db.query(
      'ai_chat_threads',
      columns: ['id', 'title', 'last_message_preview'],
    );
    for (final row in threads) {
      batch.update(
        'ai_chat_threads',
        {
          'search_text': foldForSearch(
            '${row['title'] ?? ''} ${row['last_message_preview'] ?? ''}',
          ),
        },
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
    await batch.commit(noResult: true);
  }
}
