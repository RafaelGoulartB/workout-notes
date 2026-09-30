import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/database/database_schema.dart';
import 'package:workout_notes/repositories/export_import_repository.dart';
import 'support/test_db.dart';

/// Restores against the production schema with foreign keys enforced, the
/// way the app opens its database.
void main() {
  late Database database;

  setUpAll(initSqfliteFfiForTests);

  setUp(() async {
    database = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 52,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: DatabaseSchema.onCreate,
      ),
    );
  });

  tearDown(() => database.close());

  test('drops orphan rows left by older versions instead of failing', () async {
    final backup = _v16Backup({
      'categories': [
        {'id': 'chest', 'name': 'Chest', 'color': 1},
      ],
      'exercises': [
        {
          'id': 'bench',
          'name': 'Bench',
          'category_id': 'chest',
          'created_at': '2026-09-01T10:00:00',
        },
      ],
      'workouts': [
        {'id': 'kept', 'date': '2026-09-01', 'created_at': '2026-09-01'},
      ],
      'exercise_entries': [
        {'id': 'e-kept', 'workout_id': 'kept', 'exercise_id': 'bench'},
        {'id': 'e-orphan', 'workout_id': 'deleted', 'exercise_id': 'bench'},
      ],
      'sets': [
        {'id': 's-kept', 'exercise_entry_id': 'e-kept'},
        {'id': 's-orphan', 'exercise_entry_id': 'e-orphan'},
      ],
    });

    await ExportImportRepository(
      databaseProvider: () async => database,
    ).restoreFromBackup(backup);

    expect(await database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    expect((await database.query('exercise_entries')).map((r) => r['id']), [
      'e-kept',
    ]);
    expect((await database.query('sets')).map((r) => r['id']), ['s-kept']);
    expect((await database.query('workouts')).map((r) => r['id']), ['kept']);
  });
}

Map<String, dynamic> _v16Backup(Map<String, List<Map<String, Object?>>> rows) {
  final keys = ExportImportRepository.collectionKeysForVersion(16);
  return {
    'backup_type': ExportImportRepository.backupType,
    'version': 16,
    for (final key in keys) key: rows[key] ?? <Map<String, Object?>>[],
    'record_counts': {for (final key in keys) key: rows[key]?.length ?? 0},
  };
}
