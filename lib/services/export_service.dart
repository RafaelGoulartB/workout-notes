import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../repositories/workout_repository.dart';
import '../repositories/export_import_repository.dart';

/// Information about a local backup file.
class BackupFileInfo {
  final String path;
  final String name;
  final DateTime createdAt;
  final int sizeBytes;

  BackupFileInfo({
    required this.path,
    required this.name,
    required this.createdAt,
    required this.sizeBytes,
  });

  /// Human-readable file size.
  String get sizeFormatted {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class ExportService {
  final _workoutRepo = WorkoutRepository();
  final _exportRepo = ExportImportRepository();

  // ===================================================================
  // Backups directory (public Downloads folder)
  // ===================================================================

  /// Folder name inside Downloads where backups are stored.
  static const _backupFolderName = 'WorkoutNotes';

  /// Returns the public backups directory.
  ///
  /// On Android this is `Downloads/WorkoutNotes/`, on other platforms it
  /// falls back to the app's documents directory.
  ///
  /// The path is shown to the user so they know where to place backup
  /// files for manual import.
  Future<Directory> getBackupsDirectory() async {
    // Try the public Downloads folder first (Android)
    final downloads = await getExternalStorageDirectories(
      type: StorageDirectory.downloads,
    );
    if (downloads != null && downloads.isNotEmpty) {
      final dir = Directory('${downloads.first.path}/$_backupFolderName');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    }

    // Fallback: app's documents directory (iOS, desktop)
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/backups');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Returns a human-readable description of where backups are stored.
  Future<String> getBackupsPathDescription() async {
    final dir = await getBackupsDirectory();
    return dir.path;
  }

  /// Lists all `.json` backup files, sorted newest first.
  Future<List<BackupFileInfo>> listLocalBackups() async {
    final dir = await getBackupsDirectory();
    final files = <BackupFileInfo>[];

    try {
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.json')) {
          final stat = await entity.stat();
          files.add(BackupFileInfo(
            path: entity.path,
            name: entity.uri.pathSegments.last,
            createdAt: stat.modified,
            sizeBytes: stat.size,
          ));
        }
      }
    } catch (_) {
      // Directory might not be accessible; return empty list
    }

    files.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return files;
  }

  // ===================================================================
  // JSON Backup – Export
  // ===================================================================

  /// Exports all data to a JSON file in the public backups directory.
  ///
  /// Returns the full file path of the saved backup.
  Future<String> exportToJson() async {
    final data = await _exportRepo.exportAllData();
    final json = const JsonEncoder.withIndent('  ').convert(data);
    final dir = await getBackupsDirectory();
    final dateStr = DateFormat('yyyy-MM-dd_HHmmss').format(DateTime.now());
    final file = File('${dir.path}/workout_notes_backup_$dateStr.json');
    await file.writeAsString(json);
    return file.path;
  }

  /// Saves the backup to the public directory AND shares it via the
  /// system share sheet.
  ///
  /// After this call the file is available both in the public backups
  /// directory (for later import) and via the share sheet (to transfer
  /// to other devices or cloud storage).
  Future<String> shareJsonBackup() async {
    final path = await exportToJson();

    // Share via system sheet (user can save to any location, email, etc.)
    final xfile = XFile(path, mimeType: 'application/json');
    await Share.shareXFiles([xfile], text: 'Workout Notes - Backup');
    return path;
  }

  // ===================================================================
  // JSON Backup – Import (full restore)
  // ===================================================================

  /// Reads a JSON backup file at [filePath] and performs a full restore.
  ///
  /// Throws if the file is missing, invalid, or incompatible.
  Future<int> restoreFromFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('Arquivo não encontrado: $filePath');
    }

    final content = await file.readAsString();
    final data = jsonDecode(content);

    if (data is! Map<String, dynamic>) {
      throw const FormatException(
        'Formato de backup inválido: esperado um objeto JSON',
      );
    }

    if (!data.containsKey('version')) {
      throw const FormatException(
        'Arquivo de backup inválido: campo version ausente',
      );
    }

    return _exportRepo.restoreFromBackup(data);
  }

  /// Deletes a local backup file.
  Future<void> deleteBackupFile(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  // ===================================================================
  // CSV Export
  // ===================================================================

  Future<String> exportToCsv({
    String? exerciseId,
    String? exerciseName,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final rows = await _exportRepo.exportWorkoutsCsvData(
      exerciseId: exerciseId,
      startDate: startDate,
      endDate: endDate,
    );

    final csvRows = <List<String>>[
      [
        'Data',
        'Exercício',
        'Categoria',
        'Peso',
        'Repetições',
        'Distância',
        'Tempo (s)',
        'Aquecimento',
        'RPE',
        'Nota',
        'Observação do Treino',
      ],
    ];

    for (final row in rows) {
      csvRows.add([
        (row['date'] as String?) ?? '',
        (row['exercise'] as String?) ?? '',
        (row['category'] as String?) ?? '',
        (row['weight'] as num?)?.toStringAsFixed(1) ?? '',
        (row['reps'] as int?)?.toString() ?? '',
        (row['distance'] as num?)?.toStringAsFixed(2) ?? '',
        (row['time_seconds'] as int?)?.toString() ?? '',
        (row['is_warmup'] as int?) == 1 ? 'Sim' : 'Não',
        (row['rpe'] as num?)?.toStringAsFixed(1) ?? '',
        (row['set_comment'] as String?) ?? '',
        (row['workout_comment'] as String?) ?? '',
      ]);
    }

    final csvData = const ListToCsvConverter().convert(csvRows);
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/workout_notes_export_${DateTime.now().millisecondsSinceEpoch}.csv',
    );
    await file.writeAsString(csvData);
    return file.path;
  }

  Future<void> shareCsvExport({
    String? exerciseId,
    String? exerciseName,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final path = await exportToCsv(
      exerciseId: exerciseId,
      exerciseName: exerciseName,
      startDate: startDate,
      endDate: endDate,
    );
    final file = XFile(path, mimeType: 'text/csv');
    await Share.shareXFiles([file], text: 'Workout Notes - Export');
  }

  // ===================================================================
  // Share workout summary (text)
  // ===================================================================

  Future<void> shareWorkoutSummary(String workoutId) async {
    final workout = await _workoutRepo.getWorkout(workoutId);
    if (workout == null) return;

    final exercises = await _workoutRepo.getWorkoutExercises(workoutId);
    final date = (workout['date'] as String?) ?? '';
    final comment = (workout['comment'] as String?) ?? '';

    var text = '🏋️ Treino - $date\n';
    if (comment.isNotEmpty) text += '📝 $comment\n';
    text += '\n';

    for (final ex in exercises) {
      final sets = await _workoutRepo.getExerciseSets(ex['id'] as String);
      final exName = (ex['exercise_name'] as String?) ?? '';
      text += '\n$exName\n';
      for (int i = 0; i < sets.length; i++) {
        final s = sets[i];
        final weight = (s['weight'] as num?)?.toStringAsFixed(1) ?? '-';
        final reps = (s['reps'] as int?)?.toString() ?? '-';
        final complete = (s['is_complete'] as int?) == 1 ? '✅' : '⬜';
        text += '   $complete $i: $weight kg × $reps\n';
      }
    }

    await Share.share(text);
  }
}
