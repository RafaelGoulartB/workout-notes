import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/repositories/export_import_repository.dart';
import 'package:workout_notes/services/export_service.dart';

void main() {
  late Database database;
  late Directory backupsDirectory;
  late ExportService service;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    backupsDirectory = await Directory.systemTemp.createTemp('workout_notes_export_test_');
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
      backupsDirectoryProvider: () async => backupsDirectory,
    );
  });

  tearDown(() async {
    await database.close();
    await backupsDirectory.delete(recursive: true);
  });

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

  test('exports valid JSON using UTF-8 bytes in the current backup format', () async {
    final bytes = await service.exportBackupBytes();
    final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;

    expect(data['version'], ExportImportRepository.currentBackupVersion);
    expect(
      data['settings'],
      [
        {'key': 'current', 'value': 'unchanged'},
      ],
    );
  });

  test('passes bytes to the save picker and handles cancellation', () async {
    Uint8List? receivedBytes;
    String? receivedFileName;
    String? receivedDialogTitle;
    final saveService = ExportService(
      exportRepo: ExportImportRepository(
        databaseProvider: () async => database,
      ),
      saveFile: ({
        required dialogTitle,
        required fileName,
        required bytes,
      }) async {
        receivedDialogTitle = dialogTitle;
        receivedFileName = fileName;
        receivedBytes = bytes;
        return null;
      },
    );

    final selectedPath = await saveService.saveJsonBackup(
      dialogTitle: 'Salvar backup JSON',
    );

    expect(selectedPath, isNull);
    expect(receivedDialogTitle, 'Salvar backup JSON');
    expect(receivedFileName, matches(RegExp(r'^backup_\d{4}-\d{2}-\d{2}_\d{6}\.json$')));
    expect(jsonDecode(utf8.decode(receivedBytes!)), isA<Map<String, dynamic>>());
  });

  test('keeps the existing share flow and shares the generated JSON file', () async {
    String? sharedPath;
    String? sharedText;
    final sharingService = ExportService(
      exportRepo: ExportImportRepository(
        databaseProvider: () async => database,
      ),
      backupsDirectoryProvider: () async => backupsDirectory,
      shareFile: (file, text) async {
        sharedPath = file.path;
        sharedText = text;
      },
    );

    final exportedPath = await sharingService.shareJsonBackup();

    expect(sharedPath, exportedPath);
    expect(sharedText, 'Workout Notes - Backup');
    expect(jsonDecode(await File(exportedPath).readAsString()), isA<Map<String, dynamic>>());
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
