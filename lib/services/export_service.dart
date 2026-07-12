import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../l10n/app_localizations.dart';
import '../l10n/l10n_exercises.dart';
import '../repositories/workout_repository.dart';
import '../repositories/export_import_repository.dart';

typedef SaveFileCallback =
    Future<String?> Function({
      required String dialogTitle,
      required String fileName,
      required Uint8List bytes,
    });

typedef ShareFileCallback = Future<void> Function(XFile file, String text);

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
  final ExportImportRepository _exportRepo;
  final SaveFileCallback _saveFile;
  final ShareFileCallback _shareFile;
  final Future<Directory> Function()? backupsDirectoryProvider;

  ExportService({
    ExportImportRepository? exportRepo,
    SaveFileCallback? saveFile,
    ShareFileCallback? shareFile,
    this.backupsDirectoryProvider,
  }) : _exportRepo = exportRepo ?? ExportImportRepository(),
       _saveFile = saveFile ?? _saveFileWithPicker,
       _shareFile = shareFile ?? _shareFileWithSheet;

  static const _backupFolderName = 'WorkoutNotes';

  // ===================================================================
  // Backups directory
  // ===================================================================

  /// Returns the directory for saving/reading backup files.
  ///
  /// On Android, tries the public Downloads folder first so the user
  /// can easily find the files. Falls back to the app's documents
  /// directory if Downloads is not accessible (Android 11+ scoped
  /// storage).
  Future<Directory> getBackupsDirectory() async {
    final provider = backupsDirectoryProvider;
    if (provider != null) {
      return provider();
    }

    // Try public Downloads (Android 10-)
    try {
      final dirs = await getExternalStorageDirectories(
        type: StorageDirectory.downloads,
      );
      if (dirs != null && dirs.isNotEmpty) {
        final dir = Directory('${dirs.first.path}/$_backupFolderName');
        if (!await dir.exists()) await dir.create(recursive: true);
        return dir;
      }
    } catch (_) {}

    // Fallback: app's documents
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/$_backupFolderName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Human-readable path description to show the user.
  Future<String> getBackupsPathDescription() async {
    try {
      return (await getBackupsDirectory()).path;
    } catch (_) {
      return '(indisponível)';
    }
  }

  /// Lists `.json` files from the backups directory, newest first.
  Future<List<BackupFileInfo>> listLocalBackups() async {
    try {
      final dir = await getBackupsDirectory();
      final files = <BackupFileInfo>[];
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.json')) {
          final stat = await entity.stat();
          files.add(
            BackupFileInfo(
              path: entity.path,
              name: entity.uri.pathSegments.last,
              createdAt: stat.modified,
              sizeBytes: stat.size,
            ),
          );
        }
      }
      files.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return files;
    } catch (_) {
      return [];
    }
  }

  // ===================================================================
  // JSON Backup – Export
  // ===================================================================

  /// Generates the current backup format as UTF-8 JSON bytes.
  Future<Uint8List> exportBackupBytes() async {
    final data = await _exportRepo.exportAllData();
    final json = const JsonEncoder.withIndent('  ').convert(data);
    return Uint8List.fromList(utf8.encode(json));
  }

  /// Exports all data to JSON and returns the file path.
  Future<String> exportToJson() async {
    final bytes = await exportBackupBytes();
    final dir = await getBackupsDirectory();
    final dateStr = DateFormat('yyyy-MM-dd_HHmmss').format(DateTime.now());
    final file = File('${dir.path}/workout_notes_backup_$dateStr.json');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  /// Saves backup and opens share sheet. The file is also kept
  /// locally in the backups directory.
  Future<String> shareJsonBackup() async {
    final path = await exportToJson();
    final xfile = XFile(path, mimeType: 'application/json');
    await _shareFile(xfile, 'Workout Notes - Backup');
    return path;
  }

  /// Opens the native save dialog with the backup bytes.
  ///
  /// Returns the selected path, or `null` when the user cancels.
  Future<String?> saveJsonBackup({required String dialogTitle}) async {
    final bytes = await exportBackupBytes();
    final dateStr = DateFormat('yyyy-MM-dd_HHmmss').format(DateTime.now());
    return _saveFile(
      dialogTitle: dialogTitle,
      fileName: 'backup_$dateStr.json',
      bytes: bytes,
    );
  }

  static Future<String?> _saveFileWithPicker({
    required String dialogTitle,
    required String fileName,
    required Uint8List bytes,
  }) {
    return FilePicker.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: bytes,
    );
  }

  static Future<void> _shareFileWithSheet(XFile file, String text) async {
    await Share.shareXFiles([file], text: text);
  }

  // ===================================================================
  // JSON Backup – Import (restore)
  // ===================================================================

  /// Restores all data from a JSON backup file.
  Future<int> restoreFromFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('Arquivo não encontrado: $filePath');
    }
    final content = await file.readAsString();
    return _restoreFromJsonString(content);
  }

  /// Restores all data from a raw JSON string (pasted by the user).
  Future<int> restoreFromJsonString(String jsonString) async {
    return _restoreFromJsonString(jsonString);
  }

  /// Restores all data from the bytes returned by a file picker.
  Future<int> restoreFromBytes(Uint8List bytes) async {
    return _restoreFromJsonString(utf8.decode(bytes, allowMalformed: false));
  }

  Future<int> _restoreFromJsonString(String content) async {
    final data = jsonDecode(content);
    if (data is! Map<String, dynamic>) {
      throw const FormatException(
        'Formato inválido: esperado um objeto JSON com os dados do backup.',
      );
    }
    if (!data.containsKey('version')) {
      throw const FormatException(
        'Arquivo de backup inválido: campo version ausente.',
      );
    }
    final version = data['version'];
    if (version != ExportImportRepository.currentBackupVersion) {
      throw FormatException(
        'Versão de backup incompatível: $version. '
        'Versão esperada: ${ExportImportRepository.currentBackupVersion}.',
      );
    }
    return _exportRepo.restoreFromBackup(data);
  }

  /// Deletes a backup file.
  Future<void> deleteBackupFile(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
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
  // Share workout summary
  // ===================================================================

  Future<void> shareWorkoutSummary(
    String workoutId,
    AppLocalizations loc,
  ) async {
    final workout = await _workoutRepo.getWorkout(workoutId);
    if (workout == null) return;
    final exercises = await _workoutRepo.getWorkoutExercises(workoutId);
    final date = (workout['date'] as String?) ?? '';
    final comment = (workout['comment'] as String?) ?? '';
    var text = loc.exportServiceWorkoutSummary(date);
    if (comment.isNotEmpty) text += loc.exportServiceWorkoutNote(comment);
    text += '\n';
    for (final ex in exercises) {
      final sets = await _workoutRepo.getExerciseSets(ex['id'] as String);
      final exName = _localizedExerciseName(loc, ex);
      text += '\n$exName\n';
      for (int i = 0; i < sets.length; i++) {
        final s = sets[i];
        final weight = (s['weight'] as num?)?.toStringAsFixed(1) ?? '-';
        final reps = (s['reps'] as int?)?.toString() ?? '-';
        final complete = (s['is_complete'] as int?) == 1 ? '✅' : '⬜';
        text += '   $complete $i: $weight ${loc.workoutDetailKg} × $reps\n';
      }
    }
    await Share.share(text);
  }

  /// Returns the localized exercise name using the locale key, falling back
  /// to the database-stored name if no translation exists.
  String _localizedExerciseName(AppLocalizations loc, Map<String, dynamic> ex) {
    final localeKey = ex['exercise_locale_key'] as String?;
    if (localeKey != null) {
      final translated = ExerciseLocalization.exerciseName(
        localeKey,
        loc.localeName,
      );
      if (translated != null && translated.isNotEmpty) return translated;
    }
    return (ex['exercise_name'] as String?) ?? '';
  }
}
