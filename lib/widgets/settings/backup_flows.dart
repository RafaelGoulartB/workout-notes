import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/services/backup_actions.dart';
import 'package:workout_notes/services/backup_exception.dart';
import 'package:workout_notes/services/export_service.dart';
import 'package:workout_notes/widgets/settings/settings.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Thin UI glue over [BackupActions]: the sheets, dialogs and snack bars of
/// the JSON backup export and import flows. Every step re-checks
/// `context.mounted` after awaiting, like the screen it was extracted from.
class BackupFlows {
  BackupFlows(this.context, {BackupActions? actions})
    : actions = actions ?? BackupActions();

  final BuildContext context;
  final BackupActions actions;

  AppLocalizations get _loc => AppLocalizations.of(context)!;

  void _snack(
    String message, {
    Duration? duration,
    SnackBarBehavior behavior = SnackBarBehavior.floating,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: behavior,
        duration: duration ?? const Duration(milliseconds: 4000),
      ),
    );
  }

  // ===================== EXPORT =====================
  Future<void> exportBackup() async {
    final loc = _loc;
    if (!context.mounted) return;

    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SettingsSheetTitle(
                icon: Icons.download_outlined,
                title: loc.settingsExportOptionsTitle,
              ),
              const Divider(height: 1, thickness: 1),
              SettingsOptionTile(
                icon: Icons.share_outlined,
                title: loc.settingsExportShareOption,
                subtitle: loc.settingsExportShareSubtitle,
                onTap: () => Navigator.pop(ctx, 'share'),
              ),
              SettingsOptionTile(
                icon: Icons.save_alt_outlined,
                title: loc.settingsExportSaveOption,
                subtitle: loc.settingsExportSaveSubtitle,
                onTap: () => Navigator.pop(ctx, 'save'),
              ),
            ],
          ),
        );
      },
    );

    if (choice == null || !context.mounted) return;
    if (choice == 'share') {
      await _shareBackup();
    } else if (choice == 'save') {
      await _saveBackup();
    }
  }

  Future<void> _shareBackup() async {
    final loc = _loc;
    try {
      final savedPath = await actions.shareBackup();
      if (context.mounted) {
        _snack(
          '${loc.settingsExportSuccess}\n$savedPath',
          duration: const Duration(seconds: 6),
        );
      }
    } catch (e) {
      if (context.mounted) {
        _snack(loc.settingsExportError(describeBackupError(loc, e)));
      }
    }
  }

  Future<void> _saveBackup() async {
    final loc = _loc;
    try {
      final savedPath = await actions.saveBackup(
        dialogTitle: loc.settingsExportSaveDialogTitle,
      );
      if (savedPath == null || !context.mounted) return;
      _snack(
        loc.settingsExportSaveSuccess(savedPath),
        duration: const Duration(seconds: 6),
      );
    } catch (e) {
      if (context.mounted) {
        _snack(loc.settingsExportSaveError(describeBackupError(loc, e)));
      }
    }
  }

  // ===================== IMPORT =====================
  Future<void> importBackup() async {
    final loc = _loc;

    // Get path description to show user
    final backupsPath = await actions.backupsPathDescription(loc);
    if (!context.mounted) return;

    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SettingsSheetTitle(
                icon: Icons.restore_outlined,
                title: loc.settingsImportBackup,
              ),
              const Divider(height: 1, thickness: 1),
              SettingsOptionTile(
                icon: Icons.folder_open_outlined,
                title: loc.settingsImportLocalOption,
                subtitle: backupsPath,
                onTap: () => Navigator.pop(ctx, 'local'),
              ),
              SettingsOptionTile(
                icon: Icons.content_paste_go,
                title: loc.settingsImportPasteOption,
                subtitle: loc.settingsImportPasteSubtitle,
                onTap: () => Navigator.pop(ctx, 'paste'),
              ),
              SettingsOptionTile(
                icon: Icons.attach_file,
                title: loc.settingsImportPickFileOption,
                subtitle: loc.settingsImportPickFileSubtitle,
                onTap: () => Navigator.pop(ctx, 'device'),
              ),
            ],
          ),
        );
      },
    );

    if (choice == null || !context.mounted) return;

    if (choice == 'local') {
      await _pickFromLocal(backupsPath);
    } else if (choice == 'paste') {
      await _pasteFromClipboard();
    } else if (choice == 'device') {
      await _pickFromDevice();
    }
  }

  /// Confirms the destructive restore, runs it and reports the outcome.
  Future<void> _confirmAndRestore(BackupSource source) async {
    final loc = _loc;
    if (!context.mounted) return;
    final confirmed = await showConfirmDialog(
      context,
      title: loc.settingsImportBackup,
      message: loc.settingsImportWarning,
      confirmLabel: loc.settingsImport,
      destructive: true,
      icon: Icons.warning_amber_rounded,
    );

    if (confirmed != true || !context.mounted) return;

    try {
      final count = await actions.restore(source);
      if (!context.mounted) return;
      _snack(
        loc.settingsImportSuccess(count),
        duration: const Duration(seconds: 5),
      );
    } catch (e) {
      if (!context.mounted) return;
      _snack(loc.settingsImportError(describeBackupError(loc, e)));
    }
  }

  // ----- Option A: pick from local backups -----
  Future<void> _pickFromLocal(String backupsPath) async {
    final loc = _loc;
    final localBackups = await actions.listLocalBackups();

    if (localBackups.isEmpty) {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(loc.settingsImportBackup),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.folder_open,
                size: 48,
                color: Theme.of(ctx).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(loc.settingsNoBackupFile),
              const SizedBox(height: 8),
              Text(
                backupsPath,
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(loc.settingsAboutOk),
            ),
          ],
        ),
      );
      return;
    }

    if (!context.mounted) return;
    final selectedPath = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => _LocalBackupsSheet(
        title: loc.settingsImportBackup,
        backupsPath: backupsPath,
        backups: localBackups,
      ),
    );

    if (selectedPath == null || !context.mounted) return;
    await _confirmAndRestore(BackupFileSource(selectedPath));
  }

  // ----- Option B: paste JSON text -----
  Future<void> _pasteFromClipboard() async {
    final loc = _loc;
    final controller = TextEditingController();
    if (!context.mounted) return;
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.content_paste_go,
              color: Theme.of(ctx).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(loc.settingsImportPasteTitle),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: controller,
            maxLines: 12,
            minLines: 6,
            decoration: InputDecoration(
              hintText: loc.settingsImportPasteHint,
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.all(12),
              filled: true,
            ),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(loc.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(loc.settingsImport),
          ),
        ],
      ),
    );

    if (text == null || text.trim().isEmpty || !context.mounted) return;
    await _confirmAndRestore(BackupJsonSource(text.trim()));
  }

  // ----- Option C: pick a JSON file through Android's native picker -----
  Future<void> _pickFromDevice() async {
    final loc = _loc;
    PickedBackup? picked;
    try {
      picked = await actions.pickBackupFile();
    } catch (e) {
      if (!context.mounted) return;
      _snack(loc.settingsImportPickerError(e.toString()));
      return;
    }

    if (picked == null || !context.mounted) return;

    final source = picked.source;
    if (source != null) {
      await _confirmAndRestore(source);
      return;
    }
    _snack(loc.settingsImportPickerError(loc.settingsNoBackupFile));
  }
}

class _LocalBackupsSheet extends StatelessWidget {
  const _LocalBackupsSheet({
    required this.title,
    required this.backupsPath,
    required this.backups,
  });

  final String title;
  final String backupsPath;
  final List<BackupFileInfo> backups;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SettingsSheetTitle(icon: Icons.restore_outlined, title: title),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              backupsPath,
              style: t.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: t.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const Divider(height: 1, thickness: 1),
          SizedBox(
            height: (backups.length * 64.0).clamp(64, 320),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: backups.length,
              itemBuilder: (ctx, i) {
                final b = backups[i];
                final dateStr = DateFormat(
                  'dd/MM/yyyy HH:mm',
                ).format(b.createdAt);
                return InkWell(
                  onTap: () => Navigator.pop(ctx, b.path),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: t.colorScheme.primaryContainer.withAlpha(
                              120,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.description_outlined,
                            size: 20,
                            color: t.colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                dateStr,
                                style: t.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                b.sizeFormatted,
                                style: t.textTheme.bodySmall?.copyWith(
                                  color: t.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          color: t.colorScheme.onSurfaceVariant,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
