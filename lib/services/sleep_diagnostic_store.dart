import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_notes/services/sleep_wake_engine.dart';
import 'package:workout_notes/services/sleep_stage_engine.dart';

/// Opt-in local aggregate archive. Runs after import, never in the capture loop.
class SleepDiagnosticStore {
  static const preferenceKey = 'sleep_diagnostics_enabled';
  static const maxFiles = 14;
  static const maxBytes = 20 * 1024 * 1024;
  static const maxFileBytes = 4 * 1024 * 1024;
  final Future<Directory> Function() directoryProvider;

  SleepDiagnosticStore({Future<Directory> Function()? directoryProvider})
    : directoryProvider = directoryProvider ?? _directory;

  static Future<Directory> _directory() async => Directory(
    '${(await getApplicationSupportDirectory()).path}/sleep_diagnostics',
  );

  Future<bool> isEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(preferenceKey) ?? false;

  Future<void> setEnabled(bool enabled) async {
    if (!await (await SharedPreferences.getInstance()).setBool(
      preferenceKey,
      enabled,
    )) {
      throw const FileSystemException('Could not save diagnostic preference');
    }
    if (!enabled) {
      for (final file in await _files()) {
        await file.delete();
      }
    }
  }

  Future<List<File>> _files() async {
    final directory = await directoryProvider();
    if (!await directory.exists()) return [];
    return (await directory.list(followLinks: false).toList())
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList();
  }

  Future<void> save(
    Map<String, dynamic> spool, {
    Map<String, dynamic>? resultSummary,
  }) async {
    if (!await isEnabled()) return;
    final session = spool['session'];
    if (session is! Map) return;
    final id = session['id'];
    if (id is! String || !RegExp(r'^[a-zA-Z0-9_-]{1,100}$').hasMatch(id)) {
      throw const FormatException('Invalid session identifier');
    }
    final bytes = utf8.encode(
      jsonEncode({
        'schema': 'sleep-aggregate-replay',
        'schema_version': 1,
        'engine_version':
            resultSummary?['stage_algorithm_version'] ??
            (session['algorithm_version'] == 'audio-features-v3'
                ? SleepWakeEngine.algorithmVersion
                : SleepStageEngine.algorithmVersion),
        'parameters': session['algorithm_version'] == 'audio-features-v3'
            ? SleepWakeEngine.parameters
            : SleepStageEngine.parameters,
        'result_summary': resultSummary,
        'session': session,
        'segments': spool['segments'] ?? [],
      }),
    );
    if (bytes.length > maxFileBytes) {
      throw const FormatException('Diagnostic too large');
    }
    final directory = await directoryProvider();
    await directory.create(recursive: true);
    final file = File('${directory.path}/$id.json');
    final temporary = File('${directory.path}/$id.tmp');
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
    await _prune();
  }

  Future<void> _prune() async {
    final files = <(File, FileStat)>[];
    for (final file in await _files()) {
      files.add((file, await file.stat()));
    }
    files.sort((a, b) => b.$2.modified.compareTo(a.$2.modified));
    var kept = 0;
    var bytes = 0;
    final cutoff = DateTime.now().subtract(const Duration(days: 14));
    for (final (file, stat) in files) {
      if (stat.modified.isBefore(cutoff) ||
          kept >= maxFiles ||
          bytes + stat.size > maxBytes) {
        await file.delete();
      } else {
        kept++;
        bytes += stat.size;
      }
    }
  }

  Future<File?> latest() async {
    await _prune();
    final files = await _files();
    final dated = <(File, DateTime)>[];
    for (final file in files) {
      dated.add((file, await file.lastModified()));
    }
    dated.sort((a, b) => b.$2.compareTo(a.$2));
    return dated.firstOrNull?.$1;
  }
}
