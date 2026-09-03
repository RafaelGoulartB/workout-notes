import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/services/backup_media_service.dart';

void main() {
  test('embeds and restores user-visible files with portable paths', () async {
    final source = await Directory.systemTemp.createTemp(
      'backup_media_source_',
    );
    final root = await Directory.systemTemp.createTemp('backup_media_restore_');
    addTearDown(() async {
      if (await source.exists()) await source.delete(recursive: true);
      if (await root.exists()) await root.delete(recursive: true);
    });

    final bodyPhoto = File('${source.path}/body.jpg');
    await bodyPhoto.writeAsBytes([1, 2, 3]);

    final data = <String, dynamic>{
      'version': 15,
      'body_measurements': [
        {
          'id': 'measurement-1',
          'photos_paths': jsonEncode([bodyPhoto.path]),
        },
      ],
    };
    final service = BackupMediaService(rootDirectoryProvider: () async => root);

    await service.addPortableMedia(data);

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

    await service.commitRestore(restoredDirectory);
    expect(await oldRestore.exists(), isFalse);
    expect(await restoredDirectory!.exists(), isTrue);
  });
}
