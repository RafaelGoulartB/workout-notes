import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/ai_image_attachment.dart';
import 'package:workout_notes/services/ai_image_attachment_store.dart';

void main() {
  late Directory tempDirectory;
  late AiImageAttachmentStore store;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('ai-chat-images-');
    store = AiImageAttachmentStore(
      rootDirectoryProvider: () async => tempDirectory,
    );
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test(
    'persists images as files and materialises data URLs on demand',
    () async {
      final attachments = await store.saveAll([
        AiPendingImage(
          bytes: Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9]),
          mimeType: 'image/jpeg',
          fileName: 'photo.jpg',
        ),
      ]);

      expect(attachments, hasLength(1));
      expect(await File(attachments.single.path).exists(), isTrue);
      final urls = await store.readDataUrls(attachments);
      expect(urls.single, startsWith('data:image/jpeg;base64,'));

      await store.deleteAll(attachments);
      expect(await File(attachments.single.path).exists(), isFalse);
    },
  );

  test('rejects more than five images before writing files', () async {
    final image = AiPendingImage(
      bytes: Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9]),
      mimeType: 'image/jpeg',
      fileName: 'photo.jpg',
    );

    expect(
      () => store.saveAll(List.filled(6, image)),
      throwsA(
        isA<AiImageAttachmentException>().having(
          (error) => error.code,
          'code',
          'too_many_images',
        ),
      ),
    );
  });

  test('startup cleanup removes only unreferenced image files', () async {
    final image = AiPendingImage(
      bytes: Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9]),
      mimeType: 'image/jpeg',
      fileName: 'photo.jpg',
    );
    final attachments = await store.saveAll([image, image]);

    await store.deleteOrphans({attachments.first.path});

    expect(await File(attachments.first.path).exists(), isTrue);
    expect(await File(attachments.last.path).exists(), isFalse);
  });
}
