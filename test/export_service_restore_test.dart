import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/repositories/export_import_repository.dart';
import 'package:workout_notes/services/export_service.dart';

void main() {
  late Database database;
  late ExportService service;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    database = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          for (final table in [
            'exercise_categories',
            'exercises',
            'workouts',
            'exercise_entries',
            'sets',
            'routines',
            'routine_days',
            'routine_exercises',
            'predefined_sets',
            'body_measurements',
          ]) {
            await db.execute('CREATE TABLE $table (id TEXT PRIMARY KEY)');
          }
          await db.execute(
            'CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT)',
          );
        },
      ),
    );
    await database.insert('app_settings', {
      'key': 'current',
      'value': 'unchanged',
    });
    service = ExportService(
      exportRepo: ExportImportRepository(
        databaseProvider: () async => database,
      ),
    );
  });

  tearDown(() => database.close());

  Future<void> expectInvalidAndUnchanged(
    Future<int> Function() restore,
  ) async {
    await expectLater(restore, throwsA(isA<FormatException>()));
    expect(
      await database.query('app_settings'),
      [
        {'key': 'current', 'value': 'unchanged'},
      ],
    );
  }

  test('restores a valid backup from bytes', () async {
    final count = await service.restoreFromBytes(_bytes(_validBackup()));

    expect(count, 1);
    expect(
      await database.query('app_settings'),
      [
        {'key': 'restored', 'value': 'yes'},
      ],
    );
  });

  test('rejects invalid JSON without changing current data', () async {
    await expectInvalidAndUnchanged(() => service.restoreFromBytes(
          Uint8List.fromList(utf8.encode('{invalid json')),
        ));
  });

  test('rejects JSON that is not an object without changing current data', () async {
    await expectInvalidAndUnchanged(
      () => service.restoreFromBytes(_bytes([1, 2, 3])),
    );
  });

  test('rejects a backup without version without changing current data', () async {
    final backup = _validBackup()..remove('version');

    await expectInvalidAndUnchanged(
      () => service.restoreFromBytes(_bytes(backup)),
    );
  });

  test('rejects an incompatible backup version without changing current data', () async {
    final backup = _validBackup()..['version'] = 999;

    await expectInvalidAndUnchanged(
      () => service.restoreFromBytes(_bytes(backup)),
    );
  });

}

Uint8List _bytes(Object data) =>
    Uint8List.fromList(utf8.encode(jsonEncode(data)));

Map<String, dynamic> _validBackup() => {
      'version': ExportImportRepository.currentBackupVersion,
      'categories': <Map<String, dynamic>>[],
      'exercises': <Map<String, dynamic>>[],
      'workouts': <Map<String, dynamic>>[],
      'exercise_entries': <Map<String, dynamic>>[],
      'sets': <Map<String, dynamic>>[],
      'routines': <Map<String, dynamic>>[],
      'routine_days': <Map<String, dynamic>>[],
      'routine_exercises': <Map<String, dynamic>>[],
      'predefined_sets': <Map<String, dynamic>>[],
      'body_measurements': <Map<String, dynamic>>[],
      'settings': [
        {'key': 'restored', 'value': 'yes'},
      ],
    };
