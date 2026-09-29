import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/services/export_service.dart';

/// Where a backup being restored comes from.
sealed class BackupSource {
  const BackupSource();
}

/// A JSON file already on disk (for example one listed by
/// [BackupActions.listLocalBackups]).
class BackupFileSource extends BackupSource {
  const BackupFileSource(this.path);
  final String path;
}

/// Backup JSON pasted by the user.
class BackupJsonSource extends BackupSource {
  const BackupJsonSource(this.json);
  final String json;
}

/// Raw bytes of a file chosen through the system picker.
class BackupBytesSource extends BackupSource {
  const BackupBytesSource(this.bytes);
  final Uint8List bytes;
}

/// Result of [BackupActions.pickBackupFile]; [source] is `null` when the chosen
/// file could not be read at all.
class PickedBackup {
  const PickedBackup(this.source);
  final BackupSource? source;
}

/// UI-free backup operations behind the Data & privacy screen. Widgets own the
/// dialogs and snack bars; everything that touches [ExportService] or the file
/// picker lives here so it can run (and be tested) without a `BuildContext`.
class BackupActions {
  BackupActions({ExportService? exportService})
    : _service = exportService ?? ExportService();

  final ExportService _service;

  /// Shares the JSON backup and returns the file path that was written.
  Future<String> shareBackup() => _service.shareJsonBackup();

  /// Lets the user save the JSON backup; `null` when they cancel.
  Future<String?> saveBackup({required String dialogTitle}) =>
      _service.saveJsonBackup(dialogTitle: dialogTitle);

  Future<String> backupsPathDescription(AppLocalizations loc) =>
      _service.getBackupsPathDescription(loc);

  Future<List<BackupFileInfo>> listLocalBackups() =>
      _service.listLocalBackups();

  /// Restores [source] and returns the number of imported records.
  Future<int> restore(BackupSource source) => switch (source) {
    BackupFileSource(:final path) => _service.restoreFromFile(path),
    BackupJsonSource(:final json) => _service.restoreFromJsonString(json),
    BackupBytesSource(:final bytes) => _service.restoreFromBytes(bytes),
  };

  /// Opens the system picker for a `.json` file. Returns `null` when the user
  /// cancels, a [PickedBackup] with a `null` source when the provider exposed
  /// neither bytes nor a path, and rethrows picker failures.
  Future<PickedBackup?> pickBackupFile() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (file == null) return null;

    Uint8List? bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (_) {
      // Some native providers expose only a filesystem path.
    }
    if (bytes != null) return PickedBackup(BackupBytesSource(bytes));
    final path = file.path;
    if (path != null) return PickedBackup(BackupFileSource(path));
    return const PickedBackup(null);
  }
}
