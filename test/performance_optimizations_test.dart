import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/database/database_schema.dart';
import 'package:workout_notes/repositories/workout_repository.dart';

import 'support/ai_test_db.dart';

void main() {
  tearDown(uninstallAiTestDb);

  test('monthly workout summary aggregates the month in one query', () async {
    final db = await installAiTestDb();
    await db.insert('workouts', {
      'id': 'july',
      'date': '2026-07-31',
      'created_at': '2026-07-31T10:00:00.000',
    });
    await db.insert('workouts', {
      'id': 'august',
      'date': '2026-08-20',
      'created_at': '2026-08-20T10:00:00.000',
    });
    await db.insert('exercise_categories', {
      'id': 'strength',
      'name': 'Strength',
      'color': 1,
      'order_index': 0,
    });
    await db.insert('exercises', {
      'id': 'squat',
      'name': 'Squat',
      'category_id': 'strength',
      'created_at': '2026-08-20T10:00:00.000',
    });
    await db.insert('exercise_entries', {
      'id': 'entry',
      'workout_id': 'august',
      'exercise_id': 'squat',
      'order_index': 0,
    });
    await db.insert('sets', {
      'id': 'warmup',
      'exercise_entry_id': 'entry',
      'weight': 20.0,
      'reps': 10,
      'distance': 100.0,
      'time_seconds': 30,
      'is_warmup': 1,
      'order_index': 0,
    });
    await db.insert('sets', {
      'id': 'working',
      'exercise_entry_id': 'entry',
      'weight': 80.0,
      'reps': 5,
      'distance': 250.0,
      'time_seconds': 60,
      'is_warmup': 0,
      'order_index': 1,
    });

    final summary = await WorkoutRepository().getMonthlySummary(
      DateTime(2026, 8),
    );

    expect(summary['workout_count'], 1);
    expect(summary['total_volume'], 400.0);
    expect(summary['cardio_distance'], 250.0);
    expect(summary['cardio_time'], 60);
  });

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

      final latest = await helper.getAiChatMessagesThreadPage(
        'thread',
        limit: 3,
      );
      expect(latest.map((row) => row['id']), [
        'message-102',
        'message-103',
        'message-104',
      ]);

      await helper.upsertAiChatMessages('thread', [
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

  test('v44 migration creates the dashboard composite indexes', () async {
    final db = await installAiTestDb();
    await DatabaseSchema.onUpgrade(db, 43, 44);
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'index'",
    );
    final names = rows.map((row) => row['name']).toSet();
    expect(
      names,
      containsAll({
        'idx_workouts_date_end',
        'idx_sets_entry_state',
        'idx_measurements_type_date',
      }),
    );
  });
}
