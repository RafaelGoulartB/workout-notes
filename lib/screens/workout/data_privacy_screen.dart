import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:workout_notes/dev_tools/test_data/test_data_generator.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/repositories/export_import_repository.dart';
import 'package:workout_notes/services/export_service.dart';
import 'package:workout_notes/widgets/settings/backup_flows.dart';
import 'package:workout_notes/widgets/settings/settings.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Data & privacy: CSV/JSON exports, backup restore, about and delete-all.
/// The developer test-data entry only exists in debug builds, behind a
/// hidden tap sequence on "About".
class DataPrivacyScreen extends StatefulWidget {
  const DataPrivacyScreen({super.key});

  @override
  State<DataPrivacyScreen> createState() => _DataPrivacyScreenState();
}

class _DataPrivacyScreenState extends State<DataPrivacyScreen> {
  // Easter egg: tap "Sobre" 10x em 15s para revelar o botão de dados de teste
  int _aboutTapCount = 0;
  DateTime? _aboutFirstTapTime;
  bool _showTestData = false;
  bool _isGeneratingTestData = false;

  Future<void> _exportNutritionCsv() async {
    final loc = AppLocalizations.of(context)!;
    if (!mounted) return;
    final service = ExportService();
    try {
      await service.shareNutritionCsv(loc: loc);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.exportNutritionSuccess)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.exportNutritionError(e.toString()))),
      );
    }
  }

  Future<void> _generateTestData() async {
    if (_isGeneratingTestData) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.settingsGenerateTitle),
        content: Text(AppLocalizations.of(context)!.settingsGenerateContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppLocalizations.of(context)!.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppLocalizations.of(context)!.settingsGenerate),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _isGeneratingTestData = true);
    var progressDialogOpen = true;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: [
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Text(
                    AppLocalizations.of(
                      dialogContext,
                    )!.settingsGeneratingTestData,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // Let Flutter paint the progress state before the many SQLite inserts.
    await WidgetsBinding.instance.endOfFrame;

    try {
      final generator = TestDataGenerator();
      final result = await generator.generate();
      if (mounted) {
        if (progressDialogOpen) {
          Navigator.of(context, rootNavigator: true).pop();
          progressDialogOpen = false;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.settingsGenerateSuccessDetailed(
                result.goals,
                result.meals,
                result.measurements,
                result.monitoredNights,
                result.nutritionDays,
                result.periodizationPlans,
                result.routines,
                result.runs,
                result.sleepNights,
                result.workouts,
              ),
            ),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('Failed to generate test data: $e\n$stackTrace');
      if (mounted) {
        if (progressDialogOpen) {
          Navigator.of(context, rootNavigator: true).pop();
          progressDialogOpen = false;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.commonError(e.toString()),
            ),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 8),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGeneratingTestData = false);
      }
    }
  }

  Future<void> _deleteAllHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.settingsDeleteHistoryTitle),
        content: Text(
          AppLocalizations.of(context)!.settingsDeleteHistoryContent,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppLocalizations.of(context)!.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              AppLocalizations.of(context)!.settingsDeleteEverything,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final repo = ExportImportRepository();
      await repo.deleteAllWorkoutData();
      await repo.deleteAllNutritionData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.settingsDeleteHistorySuccess,
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showAbout() {
    if (!kDebugMode) {
      _showAboutDialog();
      return;
    }
    final now = DateTime.now();

    // Reseta o contador se passaram mais de 15s desde o primeiro toque
    if (_aboutFirstTapTime == null ||
        now.difference(_aboutFirstTapTime!) > const Duration(seconds: 15)) {
      _aboutFirstTapTime = now;
      _aboutTapCount = 1;
    } else {
      _aboutTapCount++;
      if (_aboutTapCount >= 10 && !_showTestData) {
        _showTestData = true;
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.settingsDeveloperModeEnabled,
            ),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }

    _showAboutDialog();
  }

  void _showAboutDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.fitness_center,
              color: Theme.of(ctx).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(AppLocalizations.of(ctx)!.appTitle),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(ctx)!.settingsAboutDescription,
              style: Theme.of(ctx).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(ctx)!.settingsAboutSubtitle,
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(ctx)!.settingsAboutOk),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final backup = BackupFlows(context);

    return Scaffold(
      appBar: SettingsAppBar(title: loc.settingsDataPrivacyTitle),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // ===== EXPORTAÇÕES =====
          AppSectionHeader(loc.settingsSectionExports, padding: AppSectionHeader.compactPadding),
          SettingsCard(
            children: [
              SettingsLinkTile(
                icon: Icons.table_view_outlined,
                iconColor: theme.colorScheme.primary,
                title: loc.exportNutritionCsv,
                subtitle: loc.exportNutritionCsvSubtitle,
                onTap: _exportNutritionCsv,
              ),
            ],
          ),

          // ===== DADOS =====
          AppSectionHeader(loc.settingsSectionData, padding: AppSectionHeader.compactPadding),
          SettingsCard(
            children: [
              SettingsLinkTile(
                icon: Icons.download_outlined,
                iconColor: theme.colorScheme.primary,
                title: loc.settingsExportBackup,
                subtitle: loc.settingsExportIncludesNutrition,
                onTap: backup.exportBackup,
              ),
              const SettingsCardDivider(),
              SettingsLinkTile(
                icon: Icons.upload_outlined,
                iconColor: theme.colorScheme.primary,
                title: loc.settingsImportBackup,
                subtitle: loc.settingsImportBackupSubtitle,
                onTap: backup.importBackup,
              ),
              if (kDebugMode && _showTestData) ...[
                const SettingsCardDivider(),
                SettingsLinkTile(
                  icon: Icons.bug_report_outlined,
                  iconColor: theme.colorScheme.secondary,
                  title: loc.settingsGenerateTestData,
                  subtitle: loc.settingsGenerateTestDataSubtitle,
                  onTap: _isGeneratingTestData ? null : _generateTestData,
                ),
              ],
              const SettingsCardDivider(),
              SettingsLinkTile(
                icon: Icons.info_outline,
                iconColor: theme.colorScheme.onSurfaceVariant,
                title: loc.settingsAbout,
                subtitle: loc.settingsAboutSubtitle,
                onTap: _showAbout,
              ),
              const SettingsCardDivider(),
              SettingsLinkTile(
                icon: Icons.delete_outline,
                iconColor: Colors.red,
                title: loc.settingsDeleteAllHistory,
                subtitle: loc.settingsDeleteHistoryContent.split('\n').first,
                titleColor: Colors.red,
                onTap: _deleteAllHistory,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
