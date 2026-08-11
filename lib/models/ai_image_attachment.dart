import 'dart:typed_data';

const int kMaxAiChatImages = 5;
const int kMaxAiChatImageBytes = 10 * 1024 * 1024;

class AiPendingImage {
  final Uint8List bytes;
  final String mimeType;
  final String fileName;

  const AiPendingImage({
    required this.bytes,
    required this.mimeType,
    required this.fileName,
  });
}

class AiImageAttachment {
  final String id;
  final String path;
  final String mimeType;
  final String fileName;
  final int sizeBytes;

  const AiImageAttachment({
    required this.id,
    required this.path,
    required this.mimeType,
    required this.fileName,
    required this.sizeBytes,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'path': path,
    'mime_type': mimeType,
    'file_name': fileName,
    'size_bytes': sizeBytes,
  };

  factory AiImageAttachment.fromJson(Map<String, dynamic> json) {
    return AiImageAttachment(
      id: json['id'] as String? ?? '',
      path: json['path'] as String? ?? '',
      mimeType: json['mime_type'] as String? ?? 'image/jpeg',
      fileName: json['file_name'] as String? ?? 'image.jpg',
      sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
    );
  }
}
