import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/widgets/settings/settings.dart';
import '../../repositories/settings_repository.dart';
import '../../repositories/export_import_repository.dart';
import '../../repositories/nutrition_repository.dart';
import '../../services/export_service.dart';
import '../../dev_tools/test_data/test_data_generator.dart';
import '../../services/notification_service.dart';
import '../../main.dart';
import '../../navigation/ai_coach_navigation.dart';
import 'ai_chat_screen.dart';
import 'ai_settings_screen.dart';
import 'nutrition_settings_screen.dart';
import 'plan_settings_screen.dart';
import 'sleep_settings_screen.dart';

enum _SettingsCategory { general, workout, ai, data }

/// Application-wide settings entry point. The same screen is opened from the
/// workout, sleep and nutrition tabs so global preferences never appear to
/// belong to one tracking area.
class AppSettingsScreen extends StatelessWidget {
  const AppSettingsScreen({super.key});

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: SettingsAppBar(title: loc.settingsTitle),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SettingsSectionHeader(text: loc.settingsAppPreferencesSection),
          SettingsCard(
            children: [
              SettingsLinkTile(
                icon: Icons.tune_rounded,
                iconColor: theme.colorScheme.primary,
                title: loc.settingsGeneralTitle,
                subtitle: loc.settingsGeneralSubtitle,
                onTap: () => _open(
                  context,
                  const _SettingsDetailScreen(
                    category: _SettingsCategory.general,
                  ),
                ),
              ),
            ],
          ),
          SettingsSectionHeader(text: loc.settingsBySectionTitle),
          SettingsCard(
            children: [
              SettingsLinkTile(
                icon: Icons.fitness_center_outlined,
                iconColor: theme.colorScheme.primary,
                title: loc.tabWorkout,
                subtitle: loc.settingsWorkoutSubtitle,
                onTap: () => _open(
                  context,
                  const _SettingsDetailScreen(
                    category: _SettingsCategory.workout,
                  ),
                ),
              ),
              const SettingsCardDivider(),
              SettingsLinkTile(
                icon: Icons.nightlight_outlined,
                iconColor: theme.colorScheme.primary,
                title: loc.tabSleep,
                subtitle: loc.settingsSleepSubtitle,
                onTap: () => _open(context, const SleepSettingsScreen()),
              ),
              const SettingsCardDivider(),
              SettingsLinkTile(
                icon: Icons.restaurant_outlined,
                iconColor: theme.colorScheme.primary,
                title: loc.tabNutrition,
                subtitle: loc.settingsNutritionSubtitle,
                onTap: () => _open(
                  context,
                  NutritionSettingsScreen(repository: NutritionRepository()),
                ),
              ),
              const SettingsCardDivider(),
              SettingsLinkTile(
                icon: Icons.view_timeline_outlined,
                iconColor: theme.colorScheme.primary,
                title: loc.tabPlan,
                subtitle: loc.settingsPlanSubtitle,
                onTap: () => _open(context, const PlanSettingsScreen()),
              ),
            ],
          ),
          SettingsSectionHeader(text: loc.settingsResourcesSection),
          SettingsCard(
            children: [
              SettingsLinkTile(
                icon: Icons.smart_toy_outlined,
                iconColor: theme.colorScheme.primary,
                title: loc.settingsAiTitle,
                subtitle: loc.settingsAiSubtitle,
                onTap: () => _open(
                  context,
                  const _SettingsDetailScreen(category: _SettingsCategory.ai),
                ),
              ),
              const SettingsCardDivider(),
              SettingsLinkTile(
                icon: Icons.shield_outlined,
                iconColor: theme.colorScheme.primary,
                title: loc.settingsDataPrivacyTitle,
                subtitle: loc.settingsDataPrivacySubtitle,
                onTap: () => _open(
                  context,
                  const _SettingsDetailScreen(category: _SettingsCategory.data),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Direct route kept for callers that specifically need workout preferences.
class WorkoutSettingsScreen extends StatelessWidget {
  const WorkoutSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const _SettingsDetailScreen(category: _SettingsCategory.workout);
}

class _SettingsDetailScreen extends StatefulWidget {
  final _SettingsCategory category;

  const _SettingsDetailScreen({required this.category});

  @override
  State<_SettingsDetailScreen> createState() => _SettingsDetailScreenState();
}

class _SettingsDetailScreenState extends State<_SettingsDetailScreen> {
  final _settingsRepo = SettingsRepository();
  Map<String, String> _settings = {};
  bool _isLoading = true;
  int _selectedAccentIndex = AccentColors.indexOf(AccentColors.defaultColor);
  ThemeMode _selectedThemeMode = ThemeMode.system;

  // Easter egg: tap "Sobre" 10x em 15s para revelar o botão de dados de teste
  int _aboutTapCount = 0;
  DateTime? _aboutFirstTapTime;
  bool _showTestData = false;
  bool _isGeneratingTestData = false;

  // Rest-time choices shown as chips in the timer card. The values are
  // seconds; the label is formatted at render time.
  static const _restChoices = [30, 45, 60, 90, 120, 180];

  @override
  void initState() {
    super.initState();
    WorkoutNotesApp.aiSettings.addListener(_onAiSettingsChanged);
    _selectedAccentIndex = AccentColors.indexOf(
      WorkoutNotesApp.themeNotifier.seedColor,
    );
    _selectedThemeMode = WorkoutNotesApp.themeNotifier.themeMode;
    _load();
  }

  @override
  void dispose() {
    WorkoutNotesApp.aiSettings.removeListener(_onAiSettingsChanged);
    super.dispose();
  }

  void _onAiSettingsChanged() {
    if (mounted) setState(() {});
  }

  // ===================== DATA =====================
  Future<void> _load() async {
    _settings = await _settingsRepo.getAllSettings();
    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  Future<void> _update(String key, String value) async {
    await _settingsRepo.setSetting(key, value);
    if (!mounted) return;
    _settings[key] = value;
    setState(() {});
  }

  Future<void> _updateNotificationPreference(String key, bool enabled) async {
    if (enabled) {
      await NotificationService.instance.requestPermission();
    }
    await _update(key, enabled.toString());
    await NotificationService.instance.loadSettings();
  }

  // ===================== ACTIONS =====================
  Future<void> _changeAccentColor(int index) async {
    final color = AccentColors.options[index];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('accent_color', color.toARGB32());
    if (!mounted) return;
    setState(() => _selectedAccentIndex = index);
    WorkoutNotesApp.themeNotifier.setSeedColor(color);
  }

  Future<void> _changeThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    String value;
    switch (mode) {
      case ThemeMode.light:
        value = 'light';
        break;
      case ThemeMode.dark:
        value = 'dark';
        break;
      default:
        value = 'system';
    }
    await prefs.setString('theme_mode', value);
    await _update('theme_mode', value);
    if (!mounted) return;
    setState(() => _selectedThemeMode = mode);
    WorkoutNotesApp.themeNotifier.setThemeMode(mode);
  }

  Future<void> _changeLocale(Locale newLocale) async {
    final prefs = await SharedPreferences.getInstance();
    final localeStr = newLocale.languageCode == 'pt' ? 'pt' : 'en';
    await prefs.setString('app_locale', localeStr);

    // Update date formatting
    await initializeDateFormatting(localeStr == 'pt' ? 'pt_BR' : 'en', null);
    Intl.defaultLocale = localeStr == 'pt' ? 'pt_BR' : 'en_US';

    WorkoutNotesApp.localeNotifier.setLocale(newLocale);
    await NotificationService.instance.loadSettings();
  }

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

  Future<void> _exportBackup() async {
    final loc = AppLocalizations.of(context)!;
    if (!mounted) return;

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

    if (choice == null || !mounted) return;
    if (choice == 'share') {
      await _shareBackup();
    } else if (choice == 'save') {
      await _saveBackup();
    }
  }

  Future<void> _shareBackup() async {
    final loc = AppLocalizations.of(context)!;
    final exportService = ExportService();
    try {
      final savedPath = await exportService.shareJsonBackup();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${loc.settingsExportSuccess}\n$savedPath'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc.settingsExportError(e.toString())),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _saveBackup() async {
    final loc = AppLocalizations.of(context)!;
    final exportService = ExportService();
    try {
      final savedPath = await exportService.saveJsonBackup(
        dialogTitle: loc.settingsExportSaveDialogTitle,
      );
      if (savedPath == null || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(loc.settingsExportSaveSuccess(savedPath)),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc.settingsExportSaveError(e.toString())),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _importBackup() async {
    final loc = AppLocalizations.of(context)!;
    final service = ExportService();

    // Get path description to show user
    final backupsPath = await service.getBackupsPathDescription();
    if (!mounted) return;

    // ----- Helper: show confirmation dialog + restore from file -----
    Future<void> confirmAndRestoreFromFile(String path) async {
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(loc.settingsImportBackup),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 48,
                color: Theme.of(ctx).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(loc.settingsImportWarning),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(loc.commonCancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
                foregroundColor: Theme.of(ctx).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(loc.settingsImport),
            ),
          ],
        ),
      );

      if (confirmed != true || !mounted) return;

      try {
        final count = await service.restoreFromFile(path);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc.settingsImportSuccess(count)),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc.settingsImportError(e.toString())),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }

    // ----- Helper: confirm + restore from pasted JSON string -----
    Future<void> confirmAndRestoreFromString(String jsonString) async {
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(loc.settingsImportBackup),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 48,
                color: Theme.of(ctx).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(loc.settingsImportWarning),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(loc.commonCancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
                foregroundColor: Theme.of(ctx).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(loc.settingsImport),
            ),
          ],
        ),
      );

      if (confirmed != true || !mounted) return;

      try {
        final count = await service.restoreFromJsonString(jsonString);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc.settingsImportSuccess(count)),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc.settingsImportError(e.toString())),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }

    // ----- Helper: confirm + restore from picked file bytes -----
    Future<void> confirmAndRestoreFromBytes(Uint8List bytes) async {
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(loc.settingsImportBackup),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 48,
                color: Theme.of(ctx).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(loc.settingsImportWarning),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(loc.commonCancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
                foregroundColor: Theme.of(ctx).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(loc.settingsImport),
            ),
          ],
        ),
      );

      if (confirmed != true || !mounted) return;

      try {
        final count = await service.restoreFromBytes(bytes);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc.settingsImportSuccess(count)),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc.settingsImportError(e.toString())),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }

    // ----- Option A: pick from local backups -----
    Future<void> pickFromLocal() async {
      final localBackups = await service.listLocalBackups();

      if (localBackups.isEmpty) {
        if (!mounted) return;
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

      if (!mounted) return;
      final selectedPath = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (ctx) {
          final t = Theme.of(ctx);
          return SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SettingsSheetTitle(
                  icon: Icons.restore_outlined,
                  title: loc.settingsImportBackup,
                ),
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
                  height: (localBackups.length * 64.0).clamp(64, 320),
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: localBackups.length,
                    itemBuilder: (ctx, i) {
                      final b = localBackups[i];
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
                                  color: t.colorScheme.primaryContainer
                                      .withAlpha(120),
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
        },
      );

      if (selectedPath == null || !mounted) return;
      await confirmAndRestoreFromFile(selectedPath);
    }

    // ----- Option B: paste JSON text -----
    Future<void> pasteFromClipboard() async {
      final controller = TextEditingController();
      if (!mounted) return;
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

      if (text == null || text.trim().isEmpty || !mounted) return;
      await confirmAndRestoreFromString(text.trim());
    }

    // ----- Option C: pick a JSON file through Android's native picker -----
    Future<void> pickFromDevice() async {
      FilePickerResult? result;
      try {
        result = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['json'],
          allowMultiple: false,
          withData: true,
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc.settingsImportPickerError(e.toString())),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      if (result == null || !mounted) return;

      final file = result.files.single;
      if (file.bytes != null) {
        await confirmAndRestoreFromBytes(file.bytes!);
      } else if (file.path != null) {
        await confirmAndRestoreFromFile(file.path!);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              loc.settingsImportPickerError(loc.settingsNoBackupFile),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }

    // ----- Main menu -----
    if (!mounted) return;
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

    if (choice == null || !mounted) return;

    if (choice == 'local') {
      await pickFromLocal();
    } else if (choice == 'paste') {
      await pasteFromClipboard();
    } else if (choice == 'device') {
      await pickFromDevice();
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

  void _openAiCoach() {
    final settings = WorkoutNotesApp.aiSettings;
    final loc = AppLocalizations.of(context)!;
    if (!settings.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(loc.aiCoachConfigureBeforeChat),
          duration: Duration(seconds: 2),
        ),
      );
      Navigator.of(context).push(
        AiCoachNavigation.route(
          kind: AiCoachRouteKind.aiFlow,
          builder: (_) => const AiSettingsScreen(),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      AiCoachNavigation.route(
        kind: AiCoachRouteKind.aiFlow,
        builder: (_) => const AiChatScreen(),
      ),
    );
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
            content: const Text('🔧 Modo desenvolvedor ativado!'),
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

  // ===================== HELPERS =====================
  String _accentColorLabel(int index, AppLocalizations loc) {
    switch (index) {
      case 0:
        return loc.accentColorRed;
      case 1:
        return loc.accentColorDarkOrange;
      case 2:
        return loc.accentColorOrange;
      case 3:
        return loc.accentColorAmber;
      case 4:
        return loc.accentColorDeepPurple;
      case 5:
        return loc.accentColorDarkBlue;
      case 6:
        return loc.accentColorGraphite;
      case 7:
        return loc.accentColorForestGreen;
      default:
        return '';
    }
  }

  /// Compact, locale-agnostic rest-time label: "30s", "1min", "1min 30s".
  String _formatRestTime(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return secs == 0 ? '${mins}min' : '${mins}min ${secs}s';
  }

  // ===================== BUILD =====================
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final pageTitle = switch (widget.category) {
      _SettingsCategory.general => loc.settingsGeneralTitle,
      _SettingsCategory.workout => loc.settingsWorkoutTitle,
      _SettingsCategory.ai => loc.settingsAiTitle,
      _SettingsCategory.data => loc.settingsDataPrivacyTitle,
    };

    return Scaffold(
      appBar: SettingsAppBar(title: pageTitle),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (widget.category == _SettingsCategory.general) ...[
                  // ===== APARÊNCIA =====
                  SettingsSectionHeader(text: loc.settingsSectionAppearance),
                  SettingsCard(
                    title: loc.settingsThemeMode,
                    icon: Icons.dark_mode_outlined,
                    children: [
                      SettingsRadioOption(
                        icon: Icons.brightness_auto,
                        label: loc.settingsSystem,
                        subtitle: loc.settingsSystemSubtitle,
                        selected: _selectedThemeMode == ThemeMode.system,
                        onTap: () => _changeThemeMode(ThemeMode.system),
                      ),
                      const SettingsCardDivider(),
                      SettingsRadioOption(
                        icon: Icons.light_mode,
                        label: loc.settingsLight,
                        subtitle: loc.settingsLightSubtitle,
                        selected: _selectedThemeMode == ThemeMode.light,
                        onTap: () => _changeThemeMode(ThemeMode.light),
                      ),
                      const SettingsCardDivider(),
                      SettingsRadioOption(
                        icon: Icons.dark_mode,
                        label: loc.settingsDark,
                        subtitle: loc.settingsDarkSubtitle,
                        selected: _selectedThemeMode == ThemeMode.dark,
                        onTap: () => _changeThemeMode(ThemeMode.dark),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SettingsCard(
                    title: loc.settingsThemeColor,
                    icon: Icons.palette_outlined,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: List.generate(AccentColors.options.length, (
                            i,
                          ) {
                            final isSelected = _selectedAccentIndex == i;
                            final color = AccentColors.options[i];
                            return SettingsColorSwatch(
                              color: color,
                              isSelected: isSelected,
                              onTap: () => _changeAccentColor(i),
                            );
                          }),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color:
                                    AccentColors.options[_selectedAccentIndex],
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _accentColorLabel(_selectedAccentIndex, loc),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SettingsCard(
                    title: loc.settingsLanguage,
                    icon: Icons.language_outlined,
                    children: [
                      SettingsRadioOption(
                        icon: Icons.translate,
                        label: loc.settingsPortuguese,
                        subtitle: loc.settingsLanguageSubtitle,
                        selected:
                            Localizations.localeOf(context).languageCode ==
                            'pt',
                        onTap: () => _changeLocale(const Locale('pt', 'BR')),
                      ),
                      const SettingsCardDivider(),
                      SettingsRadioOption(
                        icon: Icons.translate,
                        label: loc.settingsEnglish,
                        subtitle: loc.settingsLanguageSubtitle,
                        selected:
                            Localizations.localeOf(context).languageCode ==
                            'en',
                        onTap: () => _changeLocale(const Locale('en')),
                      ),
                    ],
                  ),
                ],

                if (widget.category == _SettingsCategory.workout) ...[
                  // ===== TREINO =====
                  SettingsSectionHeader(text: loc.settingsSectionWorkout),
                  SettingsCard(
                    children: [
                      SettingsSwitchTile(
                        icon: Icons.straighten,
                        title: loc.settingsUnitSystem,
                        subtitle: _settings['unit_system'] == 'kg'
                            ? loc.settingsUnitKgCm
                            : loc.settingsUnitLbsIn,
                        value: _settings['unit_system'] == 'kg',
                        onChanged: (v) =>
                            _update('unit_system', v ? 'kg' : 'lbs'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SettingsCard(
                    title: loc.settingsTimer,
                    icon: Icons.timer_outlined,
                    children: [
                      SettingsValuePickerTile(
                        icon: Icons.timer,
                        title: loc.settingsDefaultRest,
                        currentValue:
                            int.tryParse(
                              _settings['default_rest_time'] ?? '90',
                            ) ??
                            90,
                        displayValue: _formatRestTime(
                          int.tryParse(
                                _settings['default_rest_time'] ?? '90',
                              ) ??
                              90,
                        ),
                        choices: _restChoices,
                        formatChoice: _formatRestTime,
                        sheetTitle: loc.settingsDefaultRest,
                        onChanged: (v) =>
                            _update('default_rest_time', v.toString()),
                      ),
                      const SettingsCardDivider(),
                      SettingsSwitchTile(
                        icon: Icons.play_circle_outline,
                        title: loc.settingsAutoStartRest,
                        subtitle: loc.settingsAutoStartRestSubtitle,
                        value: _settings['auto_start_rest_timer'] == 'true',
                        onChanged: (v) =>
                            _update('auto_start_rest_timer', v.toString()),
                      ),
                      const SettingsCardDivider(),
                      SettingsSwitchTile(
                        icon: Icons.av_timer,
                        title: loc.settingsAutoStartWorkoutTimer,
                        subtitle: loc.settingsAutoStartWorkoutTimerSubtitle,
                        value: _settings['auto_start_workout_timer'] == 'true',
                        onChanged: (v) =>
                            _update('auto_start_workout_timer', v.toString()),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SettingsCard(
                    children: [
                      SettingsSwitchTile(
                        icon: Icons.lightbulb_outline,
                        title: loc.settingsKeepScreenOn,
                        subtitle: loc.settingsKeepScreenOnSubtitle,
                        value: _settings['keep_screen_on'] == 'true',
                        onChanged: (v) =>
                            _update('keep_screen_on', v.toString()),
                      ),
                    ],
                  ),

                  // ===== NOTIFICAÇÕES =====
                  SettingsSectionHeader(text: loc.settingsSectionNotifications),
                  SettingsCard(
                    children: [
                      SettingsSwitchTile(
                        icon: Icons.notifications_outlined,
                        title: loc.settingsRestTimerNotif,
                        subtitle: loc.settingsRestTimerNotifSubtitle,
                        value:
                            _settings['notification_rest_timer_enabled'] !=
                            'false',
                        onChanged: (v) => _updateNotificationPreference(
                          'notification_rest_timer_enabled',
                          v,
                        ),
                      ),
                      if (_settings['notification_rest_timer_enabled'] !=
                          'false') ...[
                        const SettingsCardDivider(),
                        SettingsSwitchTile(
                          icon: Icons.volume_up_outlined,
                          title: loc.settingsSound,
                          subtitle: loc.settingsRestSoundSubtitle,
                          indent: true,
                          value:
                              _settings['notification_rest_timer_sound'] !=
                              'false',
                          onChanged: (v) {
                            _update(
                              'notification_rest_timer_sound',
                              v.toString(),
                            );
                            NotificationService.instance.loadSettings();
                          },
                        ),
                        const SettingsCardDivider(),
                        SettingsSwitchTile(
                          icon: Icons.vibration,
                          title: loc.settingsVibration,
                          subtitle: loc.settingsRestVibrationSubtitle,
                          indent: true,
                          value:
                              _settings['notification_rest_timer_vibration'] !=
                              'false',
                          onChanged: (v) {
                            _update(
                              'notification_rest_timer_vibration',
                              v.toString(),
                            );
                            NotificationService.instance.loadSettings();
                          },
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  SettingsCard(
                    children: [
                      SettingsSwitchTile(
                        icon: Icons.notifications_active_outlined,
                        title: loc.settingsWorkoutTimerNotif,
                        subtitle: loc.settingsWorkoutTimerNotifSubtitle,
                        value:
                            _settings['notification_workout_timer_enabled'] !=
                            'false',
                        onChanged: (v) => _updateNotificationPreference(
                          'notification_workout_timer_enabled',
                          v,
                        ),
                      ),
                      if (_settings['notification_workout_timer_enabled'] !=
                          'false') ...[
                        const SettingsCardDivider(),
                        SettingsSwitchTile(
                          icon: Icons.volume_up_outlined,
                          title: loc.settingsSound,
                          subtitle: loc.settingsWorkoutSoundSubtitle,
                          indent: true,
                          value:
                              _settings['notification_workout_timer_sound'] ==
                              'true',
                          onChanged: (v) {
                            _update(
                              'notification_workout_timer_sound',
                              v.toString(),
                            );
                            NotificationService.instance.loadSettings();
                          },
                        ),
                        const SettingsCardDivider(),
                        SettingsSwitchTile(
                          icon: Icons.vibration,
                          title: loc.settingsVibration,
                          subtitle: loc.settingsWorkoutVibrationSubtitle,
                          indent: true,
                          value:
                              _settings['notification_workout_timer_vibration'] ==
                              'true',
                          onChanged: (v) {
                            _update(
                              'notification_workout_timer_vibration',
                              v.toString(),
                            );
                            NotificationService.instance.loadSettings();
                          },
                        ),
                      ],
                    ],
                  ),
                ],

                if (widget.category == _SettingsCategory.ai) ...[
                  // ===== INTELIGÊNCIA ARTIFICIAL =====
                  SettingsSectionHeader(text: loc.aiCoachSection),
                  SettingsCard(
                    children: [
                      SettingsLinkTile(
                        icon: Icons.smart_toy_rounded,
                        iconColor: theme.colorScheme.primary,
                        title: loc.aiCoachEntry,
                        subtitle: loc.aiCoachEntrySubtitle,
                        onTap: _openAiCoach,
                      ),
                      const SettingsCardDivider(),
                      SettingsLinkTile(
                        icon: Icons.tune_rounded,
                        iconColor: theme.colorScheme.onSurfaceVariant,
                        title: loc.aiCoachConfigureEntry,
                        subtitle: loc.aiCoachConfigureEntrySubtitle,
                        onTap: () {
                          Navigator.of(context).push(
                            AiCoachNavigation.route(
                              kind: AiCoachRouteKind.aiFlow,
                              builder: (_) => const AiSettingsScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],

                if (widget.category == _SettingsCategory.data) ...[
                  // ===== EXPORTAÇÕES =====
                  SettingsSectionHeader(text: loc.settingsSectionExports),
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
                  SettingsSectionHeader(text: loc.settingsSectionData),
                  SettingsCard(
                    children: [
                      SettingsLinkTile(
                        icon: Icons.download_outlined,
                        iconColor: theme.colorScheme.primary,
                        title: loc.settingsExportBackup,
                        subtitle: loc.settingsExportIncludesNutrition,
                        onTap: _exportBackup,
                      ),
                      const SettingsCardDivider(),
                      SettingsLinkTile(
                        icon: Icons.upload_outlined,
                        iconColor: theme.colorScheme.primary,
                        title: loc.settingsImportBackup,
                        subtitle: loc.settingsImportBackupSubtitle,
                        onTap: _importBackup,
                      ),
                      if (kDebugMode && _showTestData) ...[
                        const SettingsCardDivider(),
                        SettingsLinkTile(
                          icon: Icons.bug_report_outlined,
                          iconColor: theme.colorScheme.secondary,
                          title: loc.settingsGenerateTestData,
                          subtitle: loc.settingsGenerateTestDataSubtitle,
                          onTap: _isGeneratingTestData
                              ? null
                              : _generateTestData,
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
                        subtitle: loc.settingsDeleteHistoryContent
                            .split('\n')
                            .first,
                        titleColor: Colors.red,
                        onTap: _deleteAllHistory,
                      ),
                    ],
                  ),
                ],
              ],
            ),
    );
  }
}
