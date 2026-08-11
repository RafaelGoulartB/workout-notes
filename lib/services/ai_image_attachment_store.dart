import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'package:workout_notes/models/ai_image_attachment.dart';

const _uuid = Uuid();

class AiImageAttachmentException implements Exception {
  final String code;
  const AiImageAttachmentException(this.code);
}

/// Keeps image bytes out of SQLite and only creates data URLs for an active
/// multimodal request.
class AiImageAttachmentStore {
  static const maxImagesPerMessage = kMaxAiChatImages;
  static const maxBytesPerImage = kMaxAiChatImageBytes;
  final Future<Directory> Function()? rootDirectoryProvider;

  const AiImageAttachmentStore({this.rootDirectoryProvider});

  Future<List<AiImageAttachment>> saveAll(List<AiPendingImage> images) async {
    if (images.isEmpty) return const [];
    if (images.length > maxImagesPerMessage) {
      throw const AiImageAttachmentException('too_many_images');
    }
    final root = await _rootDirectory();
    final saved = <AiImageAttachment>[];
    try {
      for (final image in images) {
        if (image.bytes.length > maxBytesPerImage) {
          throw const AiImageAttachmentException('image_too_large');
        }
        if (!_supportedMimeTypes.contains(image.mimeType)) {
          throw const AiImageAttachmentException('unsupported_image');
        }
        final id = _uuid.v4();
        final file = File(
          p.join(root.path, '$id.${_extensionFor(image.mimeType)}'),
        );
        await file.writeAsBytes(image.bytes, flush: true);
        saved.add(
          AiImageAttachment(
            id: id,
            path: file.path,
            mimeType: image.mimeType,
            fileName: image.fileName,
            sizeBytes: image.bytes.length,
          ),
        );
      }
      return saved;
    } catch (_) {
      await deleteAll(saved);
      rethrow;
    }
  }

  Future<List<String>> readDataUrls(List<AiImageAttachment> attachments) async {
    final urls = <String>[];
    for (final attachment in attachments) {
      final file = File(attachment.path);
      if (!await file.exists()) {
        throw const AiImageAttachmentException('image_missing');
      }
      urls.add(
        'data:${attachment.mimeType};base64,${base64Encode(await file.readAsBytes())}',
      );
    }
    return urls;
  }

  Future<void> deleteAll(Iterable<AiImageAttachment> attachments) async {
    for (final attachment in attachments) {
      try {
        final file = File(attachment.path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  Future<void> deleteOrphans(Set<String> retainedPaths) async {
    final root = await _rootDirectory();
    await for (final entity in root.list(followLinks: false)) {
      if (entity is File && !retainedPaths.contains(entity.path)) {
        try {
          await entity.delete();
        } catch (_) {}
      }
    }
  }

  Future<Directory> _rootDirectory() async {
    if (rootDirectoryProvider != null) {
      final directory = await rootDirectoryProvider!();
      if (!await directory.exists()) await directory.create(recursive: true);
      return directory;
    }
    final support = await getApplicationSupportDirectory();
    final directory = Directory(p.join(support.path, 'ai_chat_images'));
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  static const _supportedMimeTypes = {
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/gif',
  };

  static String _extensionFor(String mimeType) => switch (mimeType) {
    'image/png' => 'png',
    'image/webp' => 'webp',
    'image/gif' => 'gif',
    _ => 'jpg',
  };
}
