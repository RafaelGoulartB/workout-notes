import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/services/backup_exception.dart';
import 'package:workout_notes/services/backup_media_service.dart';

void main() {
  late Directory source;
  late Directory root;
  late BackupMediaService service;

  setUp(() async {
    source = await Directory.systemTemp.createTemp('backup_media_source_');
    root = await Directory.systemTemp.createTemp('backup_media_restore_');
    service = BackupMediaService(rootDirectoryProvider: () async => root);
  });

  tearDown(() async {
    if (await source.exists()) await source.delete(recursive: true);
    if (await root.exists()) await root.delete(recursive: true);
  });

  /// Builds a backup map the way ExportService does: URIs in the rows and one
  /// encoded entry per photo, parsed back from the serialized bytes.
  Future<Map<String, dynamic>> exportedData(List<String> photoPaths) async {
    final data = <String, dynamic>{
      'version': 15,
      'body_measurements': [
        {'id': 'measurement-1', 'photos_paths': jsonEncode(photoPaths)},
      ],
    };
    final media = await service.collectPortableMedia(data);
    final entries = <Map<String, dynamic>>[];
    for (final item in media) {
      entries.add(
        jsonDecode(utf8.decode(await service.encodeMediaEntry(item)))
            as Map<String, dynamic>,
      );
    }
    data['media_files'] = entries;
    return data;
  }

  Future<List<String>> rootEntries() async =>
      (await root.list().toList()).map((e) => e.path).toList();

  test('embeds and restores user-visible files with portable paths', () async {
    final bodyPhoto = File('${source.path}/body.jpg');
    await bodyPhoto.writeAsBytes([1, 2, 3]);

    final data = await exportedData([bodyPhoto.path]);

    expect(data['media_count'], 1);
    expect(data['media_files'], everyElement(isNot(contains('path'))));
    expect(
      data['body_measurements'].first['photos_paths'],
      contains('backup-media://'),
    );

    await source.delete(recursive: true);
    final oldRestore = Directory('${root.path}/restore_old');
    await oldRestore.create();

    final restoredDirectory = await service.materializeForRestore(data);
    final bodyPaths =
        (jsonDecode(data['body_measurements'].first['photos_paths'] as String)
                as List)
            .cast<String>();
    expect(await File(bodyPaths.single).readAsBytes(), [1, 2, 3]);
    // The encoded payload is released once the file is on disk.
    expect(data['media_files'], everyElement(isNot(contains('data_base64'))));

    await service.commitRestore(restoredDirectory);
    expect(await oldRestore.exists(), isFalse);
    expect(await restoredDirectory!.exists(), isTrue);
  });

  test('a missing photo reference fails before writing any file', () async {
    final photo = File('${source.path}/body.jpg');
    await photo.writeAsBytes([1, 2, 3]);
    final data = await exportedData([photo.path]);
    // Valid manifest, but a measurement points at a photo that is not in it.
    data['body_measurements'] = [
      ...data['body_measurements'] as List,
      {
        'id': 'measurement-2',
        'photos_paths': jsonEncode(['backup-media://media_9']),
      },
    ];

    await expectLater(
      service.materializeForRestore(data),
      throwsA(
        isA<BackupFormatException>().having(
          (e) => e.code,
          'code',
          BackupErrorCode.mediaReferenceMissing,
        ),
      ),
    );

    expect(await rootEntries(), isEmpty);
    // The payload was not consumed and the rows still hold logical URIs.
    expect(
      (data['media_files'] as List).single,
      containsPair('data_base64', isNotEmpty),
    );
    expect(
      data['body_measurements'].first['photos_paths'],
      contains('backup-media://'),
    );
  });

  test(
    'a failing write removes the partially created restore directory',
    () async {
      final first = File('${source.path}/a.jpg')..writeAsBytesSync([1, 2, 3]);
      final second = File('${source.path}/b.jpg')..writeAsBytesSync([4, 5, 6]);
      final data = await exportedData([first.path, second.path]);
      // Valid by size and shape but not decodable: fails on the second file,
      // after the first one was already written.
      (data['media_files'] as List)[1]['data_base64'] = '!!!!';

      await expectLater(
        service.materializeForRestore(data),
        throwsA(isA<FormatException>()),
      );

      expect(await rootEntries(), isEmpty);
    },
  );

  test('rejects oversized encoded media before decoding it', () async {
    final data = <String, dynamic>{
      'version': 15,
      'media_count': 1,
      'media_files': [
        {
          'id': 'media_0',
          'file_name': 'huge.jpg',
          'size_bytes': 60 * 1024 * 1024,
          // Not valid base64: reaching the decoder would raise a different
          // error, proving the size gate ran first.
          'data_base64': '!' * (61 * 1024 * 1024),
        },
      ],
      'body_measurements': <Map<String, dynamic>>[],
    };

    await expectLater(
      service.materializeForRestore(data),
      throwsA(
        isA<BackupFormatException>().having(
          (e) => e.code,
          'code',
          BackupErrorCode.mediaTooLarge,
        ),
      ),
    );
    expect(await rootEntries(), isEmpty);
  });

  test('rejects a declared size that disagrees with the payload', () async {
    final photo = File('${source.path}/body.jpg')..writeAsBytesSync([1, 2, 3]);
    final data = await exportedData([photo.path]);
    (data['media_files'] as List).single['size_bytes'] = 4000;

    await expectLater(
      service.materializeForRestore(data),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          'Invalid backup media size.',
        ),
      ),
    );
    expect(await rootEntries(), isEmpty);
  });
}
