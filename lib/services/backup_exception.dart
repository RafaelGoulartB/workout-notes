import 'package:workout_notes/l10n/app_localizations.dart';

/// Backup problems the user can act on. The UI maps each code to a localized
/// message through [describeBackupError]; [FormatException.message] keeps an
/// English text for logs and tests.
enum BackupErrorCode {
  fileNotFound,
  invalidFormat,
  missingVersion,
  incompatibleVersion,
  mediaTooLarge,
  mediaReferenceMissing,
}

class BackupFormatException extends FormatException {
  const BackupFormatException(this.code, super.message, {this.args = const []});

  final BackupErrorCode code;

  /// Values interpolated into the localized message (path, versions, ...).
  final List<Object> args;
}

/// Localized, user-facing text for any error raised while exporting or
/// restoring a backup. Unknown errors fall back to their own description.
String describeBackupError(AppLocalizations loc, Object error) {
  if (error is! BackupFormatException) return error.toString();
  return switch (error.code) {
    BackupErrorCode.fileNotFound => loc.backupErrorFileNotFound(
      '${error.args.first}',
    ),
    BackupErrorCode.invalidFormat => loc.backupErrorInvalidFormat,
    BackupErrorCode.missingVersion => loc.backupErrorMissingVersion,
    BackupErrorCode.incompatibleVersion => loc.backupErrorIncompatibleVersion(
      '${error.args[0]}',
      '${error.args[1]}',
    ),
    BackupErrorCode.mediaTooLarge => loc.backupErrorMediaTooLarge,
    BackupErrorCode.mediaReferenceMissing =>
      loc.backupErrorMediaReferenceMissing,
  };
}
