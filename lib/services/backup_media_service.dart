import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Makes file references stored in SQLite portable across devices.
///
/// The JSON backup embeds body-measurement photos. AI chat images are omitted
/// together with the low-priority conversation history. Database paths are
/// replaced with logical URIs and rewritten to app-owned files on restore.
class BackupMediaService {
  BackupMediaService({this.rootDirectoryProvider});

  static const _uriPrefix = 'backup-media://';
  static const _maxFileBytes = 50 * 1024 * 1024;
  static const _maxTotalBytes = 500 * 1024 * 1024;

  final Future<Directory> Function()? rootDirectoryProvider;

  Future<void> addPortableMedia(Map<String, dynamic> data) async {
    final media = <Map<String, dynamic>>[];
    var totalBytes = 0;

    Future<String?> addFile(String path, {String? preferredName}) async {
      final file = File(path);
      if (!await file.exists()) return null;
      final size = await file.length();
      if (size > _maxFileBytes || totalBytes + size > _maxTotalBytes) {
        throw const FormatException(
          'Backup media exceeds the supported size limit.',
        );
      }
      final bytes = await file.readAsBytes();
      final id = 'media_${media.length}';
      final fileName = _safeFileName(preferredName ?? p.basename(path), id);
      media.add({
        'id': id,
        'file_name': fileName,
        'size_bytes': bytes.length,
        'data_base64': base64Encode(bytes),
      });
      totalBytes += bytes.length;
      return '$_uriPrefix$id';
    }

    final measurementRows = _mutableRows(data['body_measurements']);
    for (final row in measurementRows) {
      final portablePaths = <String>[];
      for (final path in _decodeStringList(row['photos_paths'])) {
        final uri = await addFile(path);
        if (uri != null) portablePaths.add(uri);
      }
      row['photos_paths'] = portablePaths.isEmpty
          ? null
          : jsonEncode(portablePaths);
    }
    data['body_measurements'] = measurementRows;

    data['media_files'] = media;
    data['media_count'] = media.length;
  }

  /// Writes embedded files and replaces logical URIs in [data].
  ///
  /// Returns the newly-created restore directory, which the caller must pass
  /// to [commitRestore] after the database succeeds or [discardRestore] after
  /// a failure.
  Future<Directory?> materializeForRestore(Map<String, dynamic> data) async {
    final rawMedia = data['media_files'];
    if (rawMedia != null && rawMedia is! List) {
      throw const FormatException('Invalid backup media collection.');
    }
    final mediaRows = rawMedia is List ? rawMedia : const [];
    if (data['version'] is int &&
        data['version'] >= 15 &&
        (data['media_count'] is! int ||
            data['media_count'] != mediaRows.length)) {
      throw const FormatException('Backup media collection is incomplete.');
    }

    final decoded = <String, ({String fileName, List<int> bytes})>{};
    var totalBytes = 0;
    for (final raw in mediaRows) {
      if (raw is! Map) {
        throw const FormatException('Invalid backup media entry.');
      }
      final row = Map<String, dynamic>.from(raw);
      final id = row['id'];
      final encoded = row['data_base64'];
      final expectedSize = row['size_bytes'];
      if (id is! String ||
          id.isEmpty ||
          decoded.containsKey(id) ||
          encoded is! String ||
          expectedSize is! int) {
        throw const FormatException('Invalid backup media entry.');
      }
      late final List<int> bytes;
      try {
        bytes = base64Decode(encoded);
      } on FormatException {
        throw const FormatException('Invalid encoded backup media.');
      }
      if (bytes.length != expectedSize || bytes.length > _maxFileBytes) {
        throw const FormatException('Invalid backup media size.');
      }
      totalBytes += bytes.length;
      if (totalBytes > _maxTotalBytes) {
        throw const FormatException('Backup media is too large.');
      }
      decoded[id] = (
        fileName: _safeFileName(
          row['file_name'] is String ? row['file_name'] as String : id,
          id,
        ),
        bytes: bytes,
      );
    }

    Directory? restoreDirectory;
    final paths = <String, String>{};
    if (decoded.isNotEmpty) {
      final root = await _rootDirectory();
      restoreDirectory = Directory(
        p.join(root.path, 'restore_${const Uuid().v4()}'),
      );
      await restoreDirectory.create(recursive: true);
      try {
        var fileIndex = 0;
        for (final entry in decoded.entries) {
          final file = File(
            p.join(
              restoreDirectory.path,
              'media_${fileIndex++}_${entry.value.fileName}',
            ),
          );
          await file.writeAsBytes(entry.value.bytes, flush: true);
          paths['$_uriPrefix${entry.key}'] = file.path;
        }
      } catch (_) {
        await discardRestore(restoreDirectory);
        rethrow;
      }
    }

    _rewriteMediaReferences(
      data,
      paths,
      requirePortableReferences:
          data['version'] is int && (data['version'] as int) >= 15,
    );
    return restoreDirectory;
  }

  Future<void> discardRestore(Directory? directory) async {
    if (directory == null) return;
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } catch (_) {}
  }

  /// Removes media directories left by previous successful restores. Files
  /// outside this service's app-owned root are never deleted.
  Future<void> commitRestore(Directory? retainedDirectory) async {
    if (retainedDirectory == null) return;
    try {
      final root = await _rootDirectory();
      await for (final entity in root.list(followLinks: false)) {
        if (entity is Directory && entity.path != retainedDirectory.path) {
          try {
            await entity.delete(recursive: true);
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  Future<Directory> _rootDirectory() async {
    final provider = rootDirectoryProvider;
    final root = provider != null
        ? await provider()
        : Directory(
            p.join(
              (await getApplicationSupportDirectory()).path,
              'backup_media',
            ),
          );
    if (!await root.exists()) await root.create(recursive: true);
    return root;
  }

  static void _rewriteMediaReferences(
    Map<String, dynamic> data,
    Map<String, String> paths, {
    required bool requirePortableReferences,
  }) {
    final measurements = _mutableRows(data['body_measurements']);
    for (final row in measurements) {
      final restoredPaths = <String>[];
      for (final rawPath in _decodeStringList(row['photos_paths'])) {
        final path = paths[rawPath];
        if (rawPath.startsWith(_uriPrefix)) {
          if (path == null) {
            throw const FormatException('Backup media reference is missing.');
          }
          restoredPaths.add(path);
        } else if (!requirePortableReferences && File(rawPath).existsSync()) {
          restoredPaths.add(rawPath);
        } else if (requirePortableReferences) {
          throw const FormatException('Invalid backup media reference.');
        }
      }
      row['photos_paths'] = restoredPaths.isEmpty
          ? null
          : jsonEncode(restoredPaths);
    }
    data['body_measurements'] = measurements;
  }

  static List<Map<String, dynamic>> _mutableRows(dynamic raw) {
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  static List<String> _decodeStringList(dynamic raw) {
    if (raw is! String || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded.whereType<String>().toList() : const [];
    } catch (_) {
      return const [];
    }
  }

  static String _safeFileName(String value, String fallback) {
    final base = p.basename(value).replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return base.isEmpty ? fallback : base;
  }
}
