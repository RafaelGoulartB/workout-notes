import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/database/database_schema.dart';
import 'package:workout_notes/repositories/export_import_repository.dart';
import 'package:workout_notes/services/run_route_codec.dart';

void main() {
  late Database database;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    database = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 51,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: DatabaseSchema.onCreate,
      ),
    );
  });

  tearDown(() => database.close());

  test(
    'current backup preserves essential data and omits secondary history',
    () async {
      const now = '2026-08-29T08:00:00.000Z';
      await database.insert('meal_types', {
        'id': 'meal-type-1',
        'key': 'pre_workout',
        'name': 'Pré-treino',
        'order_index': 7,
        'created_at': now,
      });
      await database.insert('sleep_entries', {
        'id': 'sleep-1',
        'date': '2026-08-28',
        'sleep_minutes': 450,
        'source': 'monitor',
        'created_at': now,
      });
      await database.insert('sleep_monitor_sessions', {
        'id': 'session-1',
        'sleep_entry_id': 'sleep-1',
        'status': 'completed',
        'started_at': now,
        'utc_offset_start_minutes': -180,
        'sensor_mode': 'audio',
        'algorithm_version': '1',
        'analysis_status': 'available',
        'deep_sleep_minutes': 120,
        'stage_confidence': 0.9,
        'created_at': now,
      });
      await database.insert('sleep_stage_epochs', {
        'id': 'stage-1',
        'session_id': 'session-1',
        'started_at': now,
        'duration_seconds': 30,
        'stage': 'deep',
        'confidence': 0.9,
        'algorithm_version': '1',
        'source': 'acoustic_model',
      });
      await database.insert('sleep_monitor_segments', {
        'id': 'segment-cache',
        'session_id': 'session-1',
        'started_at': now,
        'duration_seconds': 30,
        'classification': 'quiet',
        'valid_fraction': 1,
        'noise_burst_count': 0,
      });
      await database.insert('ai_chat_threads', {
        'id': 'thread-1',
        'title': 'Meu treino',
        'created_at': now,
        'updated_at': now,
      });
      await database.insert('ai_chat_messages', {
        'id': 'message-1',
        'thread_id': 'thread-1',
        'role': 'user',
        'content': 'Como evoluí?',
        'created_at': now,
      });
      await database.insert('ai_chat_thread_summaries', {
        'thread_id': 'thread-1',
        'summary': 'cache',
        'through_message_id': 'message-1',
        'updated_at': now,
      });
      await database.insert('ai_routine_proposals', {
        'id': 'proposal-1',
        'thread_id': 'thread-1',
        'tool_call_id': 'tool-1',
        'action': 'create',
        'target_json': '{}',
        'diff_json': '{}',
        'status': 'rejected',
        'created_at': now,
      });
      await database.insert('foods', {
        'id': 'unused-cache',
        'source': 'open_food_facts',
        'external_id': 'remote-1',
        'name': 'Cache remoto',
        'search_name': 'cache remoto',
        'fetched_at': now,
      });
      await database.insert('run_activities', {
        'id': 'run-compact',
        'activity_type': 'running',
        'started_at': now,
        'ended_at': now,
        'duration_seconds': 1,
        'moving_time_seconds': 1,
        'distance_meters': 3.0,
        'status': 'completed',
        'created_at': now,
        'updated_at': now,
      });
      await database.insert('run_route_data', {
        'activity_id': 'run-compact',
        'codec_version': 1,
        'quality': 'detailed',
        'point_count': 2,
        'original_point_count': 2,
        'payload': Uint8List.fromList([1, 2, 3, 4]),
        'checksum': RunRouteCodec.checksum(Uint8List.fromList([1, 2, 3, 4])),
        'compacted_at': now,
      });
      await database.insert('run_splits', {
        'activity_id': 'run-compact',
        'split_index': 1,
        'distance_meters': 3.0,
        'duration_seconds': 1,
        'is_partial': 1,
      });

      final repository = ExportImportRepository(
        databaseProvider: () async => database,
      );
      final backup = await repository.exportAllData();

      expect(
        (backup['meal_types'] as List).where(
          (row) => (row as Map)['id'] == 'meal-type-1',
        ),
        hasLength(1),
      );
      expect(backup, isNot(contains('sleep_monitor_segments')));
      expect(backup, isNot(contains('sleep_stage_epochs')));
      expect(backup, isNot(contains('ai_chat_threads')));
      expect(backup, isNot(contains('ai_chat_messages')));
      expect(backup, isNot(contains('ai_chat_thread_summaries')));
      expect(backup, isNot(contains('ai_routine_proposals')));
      final exportedSession =
          (backup['sleep_monitor_sessions'] as List).single as Map;
      expect(exportedSession, isNot(contains('analysis_status')));
      expect(exportedSession, isNot(contains('deep_sleep_minutes')));
      expect(exportedSession, isNot(contains('stage_confidence')));
      expect(
        (backup['foods'] as List).where(
          (row) => (row as Map)['id'] == 'unused-cache',
        ),
        isEmpty,
      );
      expect(
        ((backup['run_route_data'] as List).single as Map)['payload_base64'],
        'AQIDBA==',
      );

      await database.delete('meal_types');
      await database.delete('ai_chat_thread_summaries');
      await repository.restoreFromBackup(backup);

      expect(
        await database.query(
          'meal_types',
          where: 'id = ?',
          whereArgs: ['meal-type-1'],
        ),
        hasLength(1),
      );
      expect(await database.query('sleep_stage_epochs'), isEmpty);
      final restoredSession = (await database.query(
        'sleep_monitor_sessions',
        where: 'id = ?',
        whereArgs: ['session-1'],
      )).single;
      expect(restoredSession['analysis_status'], 'legacy_unavailable');
      expect(restoredSession['deep_sleep_minutes'], isNull);
      expect(await database.query('ai_chat_threads'), isEmpty);
      expect(await database.query('ai_chat_messages'), isEmpty);
      expect(await database.query('ai_routine_proposals'), isEmpty);
      expect(await database.query('sleep_monitor_segments'), isEmpty);
      expect(await database.query('ai_chat_thread_summaries'), isEmpty);
      expect(
        await database.query(
          'foods',
          where: 'id = ?',
          whereArgs: ['unused-cache'],
        ),
        isEmpty,
      );
      final restoredRoute = (await database.query('run_route_data')).single;
      expect(restoredRoute['payload'], Uint8List.fromList([1, 2, 3, 4]));
      expect(await database.query('run_splits'), hasLength(1));
    },
  );
}
