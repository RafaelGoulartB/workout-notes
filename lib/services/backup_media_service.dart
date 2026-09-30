import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:workout_notes/services/backup_exception.dart';

/// A photo that will be embedded in the backup. Only metadata is held here;
/// the bytes are read and encoded one file at a time by
/// [BackupMediaService.encodeMediaEntry].
class PortableMediaSource {
  const PortableMediaSource({
    required this.id,
    required this.fileName,
    required this.path,
    required this.sizeBytes,
  });

  final String id;
  final String fileName;
  final String path;
  final int sizeBytes;
}

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

  /// Encoded payloads smaller than this are decoded on the calling isolate;
  /// spawning an isolate would cost more than the work itself.
  static const _inlineDecodeChars = 256 * 1024;

  final Future<Directory> Function()? rootDirectoryProvider;

  /// Replaces photo paths in `data['body_measurements']` with logical URIs and
  /// returns the files to embed. Sets `media_count` and clears any
  /// `media_files`; the caller appends the entries produced by
  /// [encodeMediaEntry] to the serialized backup one at a time, so the encoded
  /// images never coexist in memory.
  Future<List<PortableMediaSource>> collectPortableMedia(
    Map<String, dynamic> data,
  ) async {
    final media = <PortableMediaSource>[];
    var totalBytes = 0;

    Future<String?> addFile(String path) async {
      final file = File(path);
      if (!await file.exists()) return null;
      final size = await file.length();
      if (size > _maxFileBytes || totalBytes + size > _maxTotalBytes) {
        throw const BackupFormatException(
          BackupErrorCode.mediaTooLarge,
          'Backup media exceeds the supported size limit.',
        );
      }
      final id = 'media_${media.length}';
      media.add(
        PortableMediaSource(
          id: id,
          fileName: _safeFileName(p.basename(path), id),
          path: path,
          sizeBytes: size,
        ),
      );
      totalBytes += size;
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

    data.remove('media_files');
    data['media_count'] = media.length;
    return media;
  }

  /// Reads [source] and returns its `media_files` JSON entry as UTF-8 bytes.
  /// The read and the base64 encoding run off the UI isolate.
  Future<Uint8List> encodeMediaEntry(PortableMediaSource source) {
    return compute<(String, String, String), Uint8List>(_encodeMediaEntry, (
      source.id,
      source.fileName,
      source.path,
    ));
  }

  /// Writes embedded files and replaces logical URIs in [data].
  ///
  /// Everything is validated before the first byte is written: the manifest,
  /// the encoded sizes (before any base64 decoding) and every photo reference.
  /// Files are then decoded and written one at a time, dropping each encoded
  /// payload from [data] once it is on disk. Any failure removes the restore
  /// directory again.
  ///
  /// Returns the newly-created restore directory, which the caller must pass
  /// to [commitRestore] after the database succeeds or [discardRestore] after
  /// a failure.
  Future<Directory?> materializeForRestore(Map<String, dynamic> data) async {
    final requirePortable =
        data['version'] is int && (data['version'] as int) >= 15;
    final entries = _validateManifest(data);

    // Reference errors must surface before anything touches the disk.
    _restoredMeasurementRows(data, {
      for (final entry in entries) '$_uriPrefix${entry.id}': entry.id,
    }, requirePortableReferences: requirePortable);

    Directory? restoreDirectory;
    try {
      final paths = <String, String>{};
      if (entries.isNotEmpty) {
        final root = await _rootDirectory();
        restoreDirectory = Directory(
          p.join(root.path, 'restore_${const Uuid().v4()}'),
        );
        await restoreDirectory.create(recursive: true);
        var fileIndex = 0;
        for (final entry in entries) {
          final path = p.join(
            restoreDirectory.path,
            'media_${fileIndex++}_${entry.fileName}',
          );
          final encoded = entry.row['data_base64'] as String;
          final job = (encoded, entry.sizeBytes, path);
          if (encoded.length < _inlineDecodeChars) {
            _decodeAndWriteMedia(job);
          } else {
            await compute<(String, int, String), void>(
              _decodeAndWriteMedia,
              job,
            );
          }
          // The bytes are on disk; release the encoded copy.
          entry.row.remove('data_base64');
          paths['$_uriPrefix${entry.id}'] = path;
        }
      }
      data['body_measurements'] = _restoredMeasurementRows(
        data,
        paths,
        requirePortableReferences: requirePortable,
      );
      return restoreDirectory;
    } catch (_) {
      await discardRestore(restoreDirectory);
      rethrow;
    }
  }

  /// Checks the manifest structure and every size limit using only the encoded
  /// length, so an oversized or inconsistent payload is rejected before it is
  /// ever decoded.
  static List<_ManifestEntry> _validateManifest(Map<String, dynamic> data) {
    final rawMedia = data['media_files'];
    if (rawMedia != null && rawMedia is! List) {
      throw const FormatException('Invalid backup media collection.');
    }
    final mediaRows = rawMedia is List ? rawMedia : const [];
    final version = data['version'];
    if (version is int &&
        version >= 15 &&
        (data['media_count'] is! int ||
            data['media_count'] != mediaRows.length)) {
      throw const FormatException('Backup media collection is incomplete.');
    }

    final entries = <_ManifestEntry>[];
    final ids = <String>{};
    var totalBytes = 0;
    for (final raw in mediaRows) {
      if (raw is! Map) {
        throw const FormatException('Invalid backup media entry.');
      }
      // Decoded JSON maps are mutable; keep the original so the payload can be
      // released once it is written.
      final row = raw is Map<String, dynamic>
          ? raw
          : Map<String, dynamic>.from(raw);
      final id = row['id'];
      final encoded = row['data_base64'];
      final expectedSize = row['size_bytes'];
      if (id is! String ||
          id.isEmpty ||
          !ids.add(id) ||
          encoded is! String ||
          expectedSize is! int) {
        throw const FormatException('Invalid backup media entry.');
      }
      // Base64 expands 3 bytes into 4 characters, minus up to 2 of padding.
      final maxDecoded = encoded.length * 3 ~/ 4;
      if (maxDecoded - 2 > _maxFileBytes || expectedSize > _maxFileBytes) {
        throw const BackupFormatException(
          BackupErrorCode.mediaTooLarge,
          'Backup media is too large.',
        );
      }
      if (expectedSize < 0 ||
          expectedSize > maxDecoded ||
          expectedSize < maxDecoded - 2) {
        throw const FormatException('Invalid backup media size.');
      }
      totalBytes += expectedSize;
      if (totalBytes > _maxTotalBytes) {
        throw const BackupFormatException(
          BackupErrorCode.mediaTooLarge,
          'Backup media is too large.',
        );
      }
      entries.add(
        _ManifestEntry(
          id: id,
          fileName: _safeFileName(
            row['file_name'] is String ? row['file_name'] as String : id,
            id,
          ),
          sizeBytes: expectedSize,
          row: row,
        ),
      );
    }
    return entries;
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

  /// Returns the measurement rows with their photo references resolved through
  /// [paths]. Leaves [data] untouched; the caller decides when to adopt the
  /// result.
  static List<Map<String, dynamic>> _restoredMeasurementRows(
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
            throw const BackupFormatException(
              BackupErrorCode.mediaReferenceMissing,
              'Backup media reference is missing.',
            );
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
    return measurements;
  }

  static List<Map<String, dynamic>> _mutableRows(dynamic raw) {
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map(Map<String, dynamic>.from)
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

class _ManifestEntry {
  const _ManifestEntry({
    required this.id,
    required this.fileName,
    required this.sizeBytes,
    required this.row,
  });

  final String id;
  final String fileName;
  final int sizeBytes;
  final Map<String, dynamic> row;
}

Uint8List _encodeMediaEntry((String, String, String) job) {
  final (id, fileName, path) = job;
  final bytes = File(path).readAsBytesSync();
  if (bytes.length > BackupMediaService._maxFileBytes) {
    throw const BackupFormatException(
      BackupErrorCode.mediaTooLarge,
      'Backup media exceeds the supported size limit.',
    );
  }
  final out = BytesBuilder(copy: false)
    ..add(
      utf8.encode(
        '{"id":${jsonEncode(id)},"file_name":${jsonEncode(fileName)},'
        '"size_bytes":${bytes.length},"data_base64":"',
      ),
    )
    // Base64 is plain ASCII, so its code units are already valid UTF-8.
    ..add(base64Encode(bytes).codeUnits)
    ..add(const [0x22, 0x7D]); // "}
  return out.takeBytes();
}

void _decodeAndWriteMedia((String, int, String) job) {
  final (encoded, expectedSize, path) = job;
  final List<int> bytes;
  try {
    bytes = base64Decode(encoded);
  } on FormatException {
    throw const FormatException('Invalid encoded backup media.');
  }
  if (bytes.length != expectedSize) {
    throw const FormatException('Invalid backup media size.');
  }
  File(path).writeAsBytesSync(bytes, flush: true);
}
