import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/repositories/export_import_repository.dart';
import 'package:workout_notes/services/backup_exception.dart';
import 'package:workout_notes/services/backup_media_service.dart';
import 'package:workout_notes/services/export_service.dart';
import 'support/test_db.dart';

void main() {
  late Database database;
  late Directory sandbox;
  late Directory backupsDirectory;
  late Directory mediaRoot;
  late ExportService service;

  setUpAll(initSqfliteFfiForTests);

  setUp(() async {
    SharedPreferences.setMockInitialValues({'accent_color': 42});
    sandbox = await Directory.systemTemp.createTemp('backup_roundtrip_');
    backupsDirectory = await Directory('${sandbox.path}/backups').create();
    mediaRoot = Directory('${sandbox.path}/media');
    database = await openTestDb();
    service = ExportService(
      exportRepo: ExportImportRepository(
        databaseProvider: () async => database,
      ),
      backupMedia: BackupMediaService(
        rootDirectoryProvider: () async => mediaRoot,
      ),
      backupsDirectoryProvider: () async => backupsDirectory,
    );
  });

  tearDown(() async {
    await database.close();
    await sandbox.delete(recursive: true);
  });

  // The last photo is bigger than the inline-decode threshold so the restore
  // exercises the background-isolate path as well.
  final photos = <String, Uint8List>{
    'a.jpg': Uint8List.fromList([1, 2, 3, 4, 5]),
    'b.png': Uint8List.fromList(List.generate(300, (i) => i % 256)),
    'c.jpg': Uint8List.fromList(
      List.generate(400 * 1024, (i) => (i * 7) % 256),
    ),
  };

  Future<Map<String, String>> seed() async {
    final paths = <String, String>{};
    final dir = await Directory('${sandbox.path}/photos').create();
    for (final entry in photos.entries) {
      final file = File('${dir.path}/${entry.key}');
      await file.writeAsBytes(entry.value);
      paths[entry.key] = file.path;
    }
    await database.insert('workouts', _workout('w1'));
    await database.insert('workouts', _workout('w2'));
    await database.insert('body_measurements', {
      'id': 'm1',
      'type': 'weight',
      'value': 80.5,
      'date': '2026-01-01',
      'created_at': '2026-01-01T08:00:00.000',
      'photos_paths': jsonEncode([paths['a.jpg'], paths['b.png']]),
    });
    await database.insert('body_measurements', {
      'id': 'm2',
      'type': 'weight',
      'value': 79.0,
      'date': '2026-01-02',
      'created_at': '2026-01-02T08:00:00.000',
      'photos_paths': jsonEncode([paths['c.jpg']]),
    });
    await database.insert('app_settings', {'key': 'k', 'value': 'v'});
    return paths;
  }

  Future<void> wipe() async {
    await database.delete('workouts');
    await database.delete('body_measurements');
    await database.delete('app_settings');
    final photoDir = Directory('${sandbox.path}/photos');
    if (await photoDir.exists()) await photoDir.delete(recursive: true);
    SharedPreferences.setMockInitialValues({'accent_color': 7});
  }

  Future<void> expectRestoredMedia() async {
    expect((await database.query('workouts')).length, 2);
    final rows = await database.query('body_measurements', orderBy: 'id');
    expect(rows.map((r) => r['value']), [80.5, 79.0]);
    final m1 = (jsonDecode(rows[0]['photos_paths'] as String) as List)
        .cast<String>();
    final m2 = (jsonDecode(rows[1]['photos_paths'] as String) as List)
        .cast<String>();
    expect(m1, hasLength(2));
    expect(m2, hasLength(1));
    expect(await File(m1[0]).readAsBytes(), photos['a.jpg']);
    expect(await File(m1[1]).readAsBytes(), photos['b.png']);
    expect(await File(m2[0]).readAsBytes(), photos['c.jpg']);
    for (final path in [...m1, ...m2]) {
      expect(path, startsWith(mediaRoot.path));
    }
    expect((await SharedPreferences.getInstance()).getInt('accent_color'), 42);
  }

  test('exports compact JSON with one media manifest', () async {
    await seed();

    final bytes = await service.exportBackupBytes();
    final text = utf8.decode(bytes);
    final data = jsonDecode(text) as Map<String, dynamic>;

    expect(text, isNot(contains('\n')));
    expect(data['media_count'], 3);
    expect(data['media_files'], hasLength(3));
    expect((data['media_files'] as List).map((e) => e['size_bytes']), [
      5,
      300,
      400 * 1024,
    ]);
    expect(RegExp('"media_files"').allMatches(text), hasLength(1));
    expect(data['record_counts']['workouts'], 2);
  });

  test('round-trips through a backup file keeping counts and photos', () async {
    await seed();

    final path = await service.exportToJson();
    expect(path, endsWith('.json'));
    expect(backupsDirectory.listSync().map((e) => e.path), [
      path,
    ], reason: 'no temporary file is left behind');

    await wipe();
    final count = await service.restoreFromFile(path);

    expect(count, greaterThan(0));
    await expectRestoredMedia();
    expect(
      await database.query('app_settings', where: 'key = ?', whereArgs: ['k']),
      [
        {'key': 'k', 'value': 'v'},
      ],
    );
  });

  test('round-trips through bytes and a legacy indented backup', () async {
    await seed();
    final bytes = await service.exportBackupBytes();
    final legacy = const JsonEncoder.withIndent(
      '  ',
    ).convert(jsonDecode(utf8.decode(bytes)));

    await wipe();
    await service.restoreFromBytes(bytes);
    await expectRestoredMedia();

    await wipe();
    await service.restoreFromJsonString(legacy);
    await expectRestoredMedia();
  });

  test(
    'a missing photo reference leaves files, database and prefs alone',
    () async {
      await seed();
      final data =
          jsonDecode(utf8.decode(await service.exportBackupBytes()))
              as Map<String, dynamic>;
      // Valid manifest (count matches), but one row points to a photo that is
      // not embedded.
      (data['body_measurements'] as List)[0]['photos_paths'] = jsonEncode([
        'backup-media://media_0',
        'backup-media://media_99',
      ]);
      (data['preferences'] as Map)['accent_color'] = 999;

      await expectLater(
        service.restoreFromBytes(
          Uint8List.fromList(utf8.encode(jsonEncode(data))),
        ),
        throwsA(
          isA<BackupFormatException>().having(
            (e) => e.code,
            'code',
            BackupErrorCode.mediaReferenceMissing,
          ),
        ),
      );

      expect(mediaRoot.existsSync() ? mediaRoot.listSync() : const [], isEmpty);
      expect((await database.query('workouts')).length, 2);
      expect((await database.query('body_measurements')).length, 2);
      expect(
        (await SharedPreferences.getInstance()).getInt('accent_color'),
        42,
      );
    },
  );

  test('reports a missing backup file with a code the UI localizes', () async {
    await expectLater(
      service.restoreFromFile('${sandbox.path}/nope.json'),
      throwsA(
        isA<BackupFormatException>().having(
          (e) => e.code,
          'code',
          BackupErrorCode.fileNotFound,
        ),
      ),
    );
  });

  test('reports incompatible versions with a code and both versions', () async {
    final backup = jsonEncode({'version': 999});

    await expectLater(
      service.restoreFromJsonString(backup),
      throwsA(
        isA<BackupFormatException>()
            .having((e) => e.code, 'code', BackupErrorCode.incompatibleVersion)
            .having((e) => e.args, 'args', [
              999,
              ExportImportRepository.currentBackupVersion,
            ]),
      ),
    );
  });
}

Map<String, Object?> _workout(String id) => {
  'id': id,
  'date': '2026-01-01',
  'created_at': '2026-01-01T08:00:00.000',
};
