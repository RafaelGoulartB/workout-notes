import 'dart:convert';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Service for handling body measurement photos.
class BodyPhotoService {
  static BodyPhotoService? _instance;
  BodyPhotoService._();
  static BodyPhotoService get instance => _instance ??= BodyPhotoService._();

  final _picker = ImagePicker();

  /// Picks an image from camera or gallery.
  Future<File?> pickImage({ImageSource source = ImageSource.camera}) async {
    final picked = await _picker.pickImage(
      source: source,
      maxWidth: 1200,
      maxHeight: 1600,
      imageQuality: 85,
    );
    if (picked == null) return null;

    // Copy to app's documents directory for persistence
    final appDir = await getApplicationDocumentsDirectory();
    final photosDir = Directory(p.join(appDir.path, 'body_photos'));
    if (!await photosDir.exists()) {
      await photosDir.create(recursive: true);
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final ext = p.extension(picked.path);
    final newPath = p.join(photosDir.path, 'body_$timestamp$ext');
    final savedFile = await File(picked.path).copy(newPath);

    return savedFile;
  }

  /// Picks multiple images from gallery.
  Future<List<File>> pickMultipleImages() async {
    final picked = await _picker.pickMultiImage(
      maxWidth: 1200,
      maxHeight: 1600,
      imageQuality: 85,
    );
    if (picked.isEmpty) return [];

    final appDir = await getApplicationDocumentsDirectory();
    final photosDir = Directory(p.join(appDir.path, 'body_photos'));
    if (!await photosDir.exists()) {
      await photosDir.create(recursive: true);
    }

    final List<File> savedFiles = [];
    for (final image in picked) {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final ext = p.extension(image.path);
      final newPath = p.join(photosDir.path, 'body_$timestamp$ext');
      savedFiles.add(await File(image.path).copy(newPath));
    }

    return savedFiles;
  }

  /// Returns a File for the given path if it exists.
  File? getPhoto(String path) {
    final file = File(path);
    return file.existsSync() ? file : null;
  }

  /// Deletes a photo file.
  Future<void> deletePhoto(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Deletes multiple photo files.
  Future<void> deletePhotos(List<String> paths) async {
    for (final path in paths) {
      await deletePhoto(path);
    }
  }

  /// Encodes a list of file paths to JSON string for database storage.
  static String? encodePaths(List<String> paths) {
    if (paths.isEmpty) return null;
    return jsonEncode(paths);
  }

  /// Decodes a JSON string from database to list of file paths.
  static List<String> decodePaths(String? json) {
    if (json == null || json.isEmpty) return [];
    try {
      final decoded = jsonDecode(json);
      if (decoded is List) {
        return decoded.cast<String>();
      }
    } catch (_) {}
    return [];
  }
}
