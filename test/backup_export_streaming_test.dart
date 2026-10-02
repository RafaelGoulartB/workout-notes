import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/repositories/export_import_repository.dart';
import 'package:workout_notes/services/export_service.dart';

import 'support/test_db.dart';

class _FailingExportRepository extends ExportImportRepository {
  @override
  Future<Map<String, dynamic>> exportAllData() async =>
      throw StateError('export failed');
}

void main() {
  late Database database;
  late Directory temp;

  setUpAll(initSqfliteFfiForTests);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('backup_streaming_');
    database = await openTestDb();
  });

  tearDown(() async {
    await database.close();
    await temp.delete(recursive: true);
  });

  ExportService serviceWith(ExportImportRepository repository) =>
      ExportService(
        exportRepo: repository,
        temporaryDirectoryProvider: () async => temp,
      );

  test('exportBackupBytes goes through a temp file that is removed', () async {
    final service = serviceWith(
      ExportImportRepository(databaseProvider: () async => database),
    );

    final bytes = await service.exportBackupBytes();

    final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    expect(data['version'], ExportImportRepository.currentBackupVersion);
    expect(data['media_files'], isEmpty);
    expect(temp.listSync(), isEmpty);
  });

  test('saveJsonBackup hands the streamed bytes to the picker', () async {
    Uint8List? received;
    final service = ExportService(
      exportRepo: ExportImportRepository(
        databaseProvider: () async => database,
      ),
      temporaryDirectoryProvider: () async => temp,
      saveFile:
          ({required dialogTitle, required fileName, required bytes}) async {
            received = bytes;
            return '/saved/$fileName';
          },
    );

    final path = await service.saveJsonBackup(dialogTitle: 'Save');

    expect(path, startsWith('/saved/backup_'));
    expect(jsonDecode(utf8.decode(received!)), isA<Map<String, dynamic>>());
    expect(temp.listSync(), isEmpty);
  });

  test('a failed export leaves no temporary file behind', () async {
    final service = serviceWith(_FailingExportRepository());

    await expectLater(service.exportBackupBytes(), throwsStateError);

    expect(temp.listSync(), isEmpty);
  });

  test('the exported bytes restore through the byte decoder', () async {
    final repository = ExportImportRepository(
      databaseProvider: () async => database,
    );
    await database.insert('app_settings', {'key': 'a', 'value': 'b'});
    final service = serviceWith(repository);
    final bytes = await service.exportBackupBytes();
    await database.delete('app_settings');

    await service.restoreFromBytes(bytes);

    final rows = await database.query('app_settings', where: "key = 'a'");
    expect(rows.single['value'], 'b');
  });

  test('malformed UTF-8 is rejected before any data changes', () async {
    await database.insert('app_settings', {'key': 'a', 'value': 'b'});
    final service = serviceWith(
      ExportImportRepository(databaseProvider: () async => database),
    );

    await expectLater(
      service.restoreFromBytes(Uint8List.fromList([0x7B, 0xC3, 0x28, 0x7D])),
      throwsFormatException,
    );

    expect(await database.query('app_settings'), hasLength(1));
  });
}
