import 'package:sqflite/sqflite.dart';

/// Incremental database upgrades extracted from the legacy schema versions.
abstract final class DatabaseFeatureMigrations {
  static Future<void> upgrade(Database db, int oldVersion) async {
    if (oldVersion < 13) {
      // User goals table
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS user_goals (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            scope TEXT NOT NULL,
            metric TEXT NOT NULL,
            period TEXT NOT NULL,
            target_value REAL NOT NULL,
            created_at TEXT NOT NULL,
            is_active INTEGER NOT NULL DEFAULT 1,
            color INTEGER
          )
        ''');
      } catch (_) {}
    }
    if (oldVersion < 14) {
      // Update cardio category color to red (was brown in earlier seeds).
      try {
        await db.rawUpdate(
          'UPDATE exercise_categories SET color = ? WHERE id = ?',
          [0xFFE53935, 'cardio'],
        );
      } catch (_) {}
    }
    if (oldVersion < 15) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS ai_chat_threads (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            last_message_preview TEXT,
            archived INTEGER NOT NULL DEFAULT 0
          )
        ''');
      } catch (_) {}
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS ai_chat_messages (
            id TEXT PRIMARY KEY,
            thread_id TEXT NOT NULL,
            role TEXT NOT NULL,
            content TEXT,
            tool_call_id TEXT,
            tool_name TEXT,
            tool_calls_json TEXT,
            created_at TEXT NOT NULL,
            FOREIGN KEY (thread_id) REFERENCES ai_chat_threads(id) ON DELETE CASCADE
          )
        ''');
      } catch (_) {}
      try {
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_ai_chat_messages_thread ON ai_chat_messages(thread_id, created_at ASC)',
        );
      } catch (_) {}
      try {
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_ai_chat_threads_updated ON ai_chat_threads(updated_at DESC)',
        );
      } catch (_) {}
    }
    if (oldVersion < 16) {
      try {
        await db.execute(
          'ALTER TABLE ai_chat_threads ADD COLUMN is_pinned INTEGER NOT NULL DEFAULT 0',
        );
      } catch (_) {}
      try {
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_ai_chat_threads_pinned_updated ON ai_chat_threads(is_pinned DESC, updated_at DESC)',
        );
      } catch (_) {}
    }
    if (oldVersion < 17) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS ai_routine_proposals (
            id TEXT PRIMARY KEY,
            thread_id TEXT NOT NULL,
            tool_call_id TEXT NOT NULL,
            action TEXT NOT NULL,
            routine_id TEXT,
            before_json TEXT,
            target_json TEXT NOT NULL,
            diff_json TEXT NOT NULL,
            status TEXT NOT NULL,
            applied_routine_id TEXT,
            error_code TEXT,
            error_message TEXT,
            created_at TEXT NOT NULL,
            resolved_at TEXT,
            FOREIGN KEY (thread_id) REFERENCES ai_chat_threads(id) ON DELETE CASCADE
          )
        ''');
      } catch (_) {}
      try {
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_ai_routine_proposals_thread_status ON ai_routine_proposals(thread_id, status, created_at ASC)',
        );
      } catch (_) {}
    }
    if (oldVersion < 18) {
      try {
        await db.execute(
          'ALTER TABLE workouts ADD COLUMN estimated_calories REAL',
        );
      } catch (_) {}
    }
    if (oldVersion < 19) {
      // Repair databases created by versions whose initial schema omitted
      // locale_key even though the seed data and queries already use it.
      try {
        await db.execute(
          'ALTER TABLE exercise_categories ADD COLUMN locale_key TEXT',
        );
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE exercises ADD COLUMN locale_key TEXT');
      } catch (_) {}
    }
  }
}
