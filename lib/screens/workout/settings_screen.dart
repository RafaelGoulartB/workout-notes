import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import '../../repositories/settings_repository.dart';
import '../../repositories/export_import_repository.dart';
import '../../services/export_service.dart';
import '../../database/test_seed_data.dart';
import '../../services/notification_service.dart';
import '../../main.dart';

class WorkoutSettingsScreen extends StatefulWidget {
  const WorkoutSettingsScreen({super.key});

  @override
  State<WorkoutSettingsScreen> createState() => _WorkoutSettingsScreenState();
}

class _WorkoutSettingsScreenState extends State<WorkoutSettingsScreen> {
  final _settingsRepo = SettingsRepository();
  Map<String, String> _settings = {};
  bool _isLoading = true;
  int _selectedAccentIndex = AccentColors.indexOf(AccentColors.defaultColor);
  ThemeMode _selectedThemeMode = ThemeMode.system;

  // Easter egg: tap "Sobre" 10x em 15s para revelar o botão de dados de teste
  int _aboutTapCount = 0;
  DateTime? _aboutFirstTapTime;
  bool _showTestData = false;

  // Rest-time choices shown as chips in the timer card. The values are
  // seconds; the label is formatted at render time.
  static const _restChoices = [30, 45, 60, 90, 120, 180];

  @override
  void initState() {
    super.initState();
    _selectedAccentIndex = AccentColors.indexOf(
      WorkoutNotesApp.themeNotifier.seedColor,
    );
    _selectedThemeMode = WorkoutNotesApp.themeNotifier.themeMode;
    _load();
  }

  // ===================== DATA =====================
  Future<void> _load() async {
    _settings = await _settingsRepo.getAllSettings();
    setState(() => _isLoading = false);
  }

  Future<void> _update(String key, String value) async {
    await _settingsRepo.setSetting(key, value);
    _settings[key] = value;
    setState(() {});
  }

  // ===================== ACTIONS =====================
  Future<void> _changeAccentColor(int index) async {
    final color = AccentColors.options[index];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('accent_color', color.toARGB32());
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
  }

  Future<void> _exportBackup() async {
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

  Future<void> _importBackup() async {
    final ctx = context;
    final loc = AppLocalizations.of(ctx)!;
    final scaffoldMessenger = ScaffoldMessenger.of(ctx);
    final service = ExportService();

    // Get path description to show user
    final backupsPath = await service.getBackupsPathDescription();

    // ----- Helper: show confirmation dialog + restore from file -----
    Future<void> confirmAndRestoreFromFile(String path) async {
      final confirmed = await showDialog<bool>(
        context: ctx,
        builder: (ctx) => AlertDialog(
          title: Text(loc.settingsImportBackup),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 48,
                  color: Theme.of(ctx).colorScheme.error),
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
        if (mounted) {
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text(loc.settingsImportSuccess(count)),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text(loc.settingsImportError(e.toString())),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }

    // ----- Helper: confirm + restore from pasted JSON string -----
    Future<void> confirmAndRestoreFromString(String jsonString) async {
      final confirmed = await showDialog<bool>(
        context: ctx,
        builder: (ctx) => AlertDialog(
          title: Text(loc.settingsImportBackup),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 48,
                  color: Theme.of(ctx).colorScheme.error),
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
        if (mounted) {
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text(loc.settingsImportSuccess(count)),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text(loc.settingsImportError(e.toString())),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }

    // ----- Option A: pick from local backups -----
    Future<void> pickFromLocal() async {
      final localBackups = await service.listLocalBackups();

      if (localBackups.isEmpty) {
        if (!mounted) return;
        await showDialog<void>(
          context: ctx,
          builder: (ctx) => AlertDialog(
            title: Text(loc.settingsImportBackup),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.folder_open,
                    size: 48,
                    color: Theme.of(ctx).colorScheme.primary),
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
        context: ctx,
        showDragHandle: true,
        builder: (ctx) {
          final t = Theme.of(ctx);
          return SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                  child: Row(
                    children: [
                      Icon(Icons.restore_outlined,
                          size: 18, color: t.colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          loc.settingsImportBackup,
                          style: t.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
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
                      final dateStr = DateFormat('dd/MM/yyyy HH:mm')
                          .format(b.createdAt);
                      return InkWell(
                        onTap: () => Navigator.pop(ctx, b.path),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
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
                                child: Icon(Icons.description_outlined,
                                    size: 20,
                                    color:
                                        t.colorScheme.onPrimaryContainer),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      dateStr,
                                      style: t.textTheme.bodyMedium
                                          ?.copyWith(
                                              fontWeight: FontWeight.w500),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      b.sizeFormatted,
                                      style: t.textTheme.bodySmall
                                          ?.copyWith(
                                        color: t
                                            .colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.chevron_right,
                                  color: t.colorScheme.onSurfaceVariant,
                                  size: 20),
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
      final text = await showDialog<String>(
        context: ctx,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.content_paste_go,
                  color: Theme.of(ctx).colorScheme.primary),
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
              onPressed: () =>
                  Navigator.pop(ctx, controller.text),
              child: Text(loc.settingsImport),
            ),
          ],
        ),
      );

      if (text == null || text.trim().isEmpty || !mounted) return;
      await confirmAndRestoreFromString(text.trim());
    }

    // ----- Main menu -----
    if (!mounted) return;
    final choice = await showModalBottomSheet<String>(
      context: ctx,
      showDragHandle: true,
      builder: (ctx) {
        final t = Theme.of(ctx);
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Row(
                  children: [
                    Icon(Icons.restore_outlined,
                        size: 18, color: t.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      loc.settingsImportBackup,
                      style: t.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, thickness: 1),
              _ImportOptionTile(
                icon: Icons.folder_open_outlined,
                title: 'Backups salvos no dispositivo',
                subtitle: backupsPath,
                onTap: () => Navigator.pop(ctx, 'local'),
              ),
              _ImportOptionTile(
                icon: Icons.content_paste_go,
                title: loc.settingsImportPasteOption,
                subtitle: loc.settingsImportPasteSubtitle,
                onTap: () => Navigator.pop(ctx, 'paste'),
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
    }
  }

  Future<void> _generateTestData() async {
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

    try {
      final generator = TestDataGenerator();
      final result = await generator.generate();
      if (mounted) {
        final wc = result['workouts'] as int;
        final rc = result['routines'] as int;
        final msg = '✅ $wc treinos e $rc rotinas gerados!';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(AppLocalizations.of(context)!.commonError(e.toString())),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _deleteAllHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.settingsDeleteHistoryTitle),
        content:
            Text(AppLocalizations.of(context)!.settingsDeleteHistoryContent),
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
      await ExportImportRepository().deleteAllWorkoutData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(AppLocalizations.of(context)!.settingsDeleteHistorySuccess),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showAbout() {
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

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.fitness_center,
                color: Theme.of(ctx).colorScheme.primary),
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

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.settingsTitle,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        centerTitle: false,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                // ===== APARÊNCIA =====
                _SectionHeader(text: loc.settingsSectionAppearance),
                _SettingsCard(
                  title: loc.settingsThemeMode,
                  icon: Icons.dark_mode_outlined,
                  children: [
                    _RadioOption(
                      icon: Icons.brightness_auto,
                      label: loc.settingsSystem,
                      subtitle: loc.settingsSystemSubtitle,
                      selected: _selectedThemeMode == ThemeMode.system,
                      onTap: () => _changeThemeMode(ThemeMode.system),
                    ),
                    const _CardDivider(),
                    _RadioOption(
                      icon: Icons.light_mode,
                      label: loc.settingsLight,
                      subtitle: loc.settingsLightSubtitle,
                      selected: _selectedThemeMode == ThemeMode.light,
                      onTap: () => _changeThemeMode(ThemeMode.light),
                    ),
                    const _CardDivider(),
                    _RadioOption(
                      icon: Icons.dark_mode,
                      label: loc.settingsDark,
                      subtitle: loc.settingsDarkSubtitle,
                      selected: _selectedThemeMode == ThemeMode.dark,
                      onTap: () => _changeThemeMode(ThemeMode.dark),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _SettingsCard(
                  title: loc.settingsThemeColor,
                  icon: Icons.palette_outlined,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: List.generate(AccentColors.options.length,
                            (i) {
                          final isSelected = _selectedAccentIndex == i;
                          final color = AccentColors.options[i];
                          return _ColorSwatch(
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
                              color: AccentColors.options[_selectedAccentIndex],
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
                _SettingsCard(
                  title: loc.settingsLanguage,
                  icon: Icons.language_outlined,
                  children: [
                    _RadioOption(
                      icon: Icons.translate,
                      label: loc.settingsPortuguese,
                      subtitle: loc.settingsLanguageSubtitle,
                      selected:
                          Localizations.localeOf(context).languageCode == 'pt',
                      onTap: () => _changeLocale(const Locale('pt', 'BR')),
                    ),
                    const _CardDivider(),
                    _RadioOption(
                      icon: Icons.translate,
                      label: loc.settingsEnglish,
                      subtitle: loc.settingsLanguageSubtitle,
                      selected:
                          Localizations.localeOf(context).languageCode == 'en',
                      onTap: () => _changeLocale(const Locale('en')),
                    ),
                  ],
                ),

                // ===== TREINO =====
                _SectionHeader(text: loc.settingsSectionWorkout),
                _SettingsCard(
                  children: [
                    _SwitchTile(
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
                _SettingsCard(
                  title: loc.settingsTimer,
                  icon: Icons.timer_outlined,
                  children: [
                    _ValuePickerTile(
                      icon: Icons.timer,
                      title: loc.settingsDefaultRest,
                      currentValue: int.tryParse(
                              _settings['default_rest_time'] ?? '90') ??
                          90,
                      displayValue: _formatRestTime(
                        int.tryParse(_settings['default_rest_time'] ?? '90') ??
                            90,
                      ),
                      choices: _restChoices,
                      formatChoice: _formatRestTime,
                      sheetTitle: loc.settingsDefaultRest,
                      onChanged: (v) =>
                          _update('default_rest_time', v.toString()),
                    ),
                    const _CardDivider(),
                    _SwitchTile(
                      icon: Icons.play_circle_outline,
                      title: loc.settingsAutoStartRest,
                      subtitle: loc.settingsAutoStartRestSubtitle,
                      value: _settings['auto_start_rest_timer'] == 'true',
                      onChanged: (v) =>
                          _update('auto_start_rest_timer', v.toString()),
                    ),
                    const _CardDivider(),
                    _SwitchTile(
                      icon: Icons.av_timer,
                      title: loc.settingsAutoStartWorkoutTimer,
                      subtitle:
                          loc.settingsAutoStartWorkoutTimerSubtitle,
                      value: _settings['auto_start_workout_timer'] == 'true',
                      onChanged: (v) =>
                          _update('auto_start_workout_timer', v.toString()),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _SettingsCard(
                  children: [
                    _SwitchTile(
                      icon: Icons.lightbulb_outline,
                      title: loc.settingsKeepScreenOn,
                      subtitle: loc.settingsKeepScreenOnSubtitle,
                      value: _settings['keep_screen_on'] == 'true',
                      onChanged: (v) => _update('keep_screen_on', v.toString()),
                    ),
                  ],
                ),

                // ===== NOTIFICAÇÕES =====
                _SectionHeader(text: loc.settingsSectionNotifications),
                _SettingsCard(
                  children: [
                    _SwitchTile(
                      icon: Icons.notifications_outlined,
                      title: loc.settingsRestTimerNotif,
                      subtitle: loc.settingsRestTimerNotifSubtitle,
                      value:
                          _settings['notification_rest_timer_enabled'] !=
                              'false',
                      onChanged: (v) {
                        _update('notification_rest_timer_enabled',
                            v.toString());
                        NotificationService.instance.loadSettings();
                      },
                    ),
                    if (_settings['notification_rest_timer_enabled'] !=
                        'false') ...[
                      const _CardDivider(),
                      _SwitchTile(
                        icon: Icons.volume_up_outlined,
                        title: loc.settingsSound,
                        subtitle: loc.settingsRestSoundSubtitle,
                        indent: true,
                        value: _settings['notification_rest_timer_sound'] !=
                            'false',
                        onChanged: (v) {
                          _update('notification_rest_timer_sound',
                              v.toString());
                          NotificationService.instance.loadSettings();
                        },
                      ),
                      const _CardDivider(),
                      _SwitchTile(
                        icon: Icons.vibration,
                        title: loc.settingsVibration,
                        subtitle: loc.settingsRestVibrationSubtitle,
                        indent: true,
                        value: _settings['notification_rest_timer_vibration'] !=
                            'false',
                        onChanged: (v) {
                          _update('notification_rest_timer_vibration',
                              v.toString());
                          NotificationService.instance.loadSettings();
                        },
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                _SettingsCard(
                  children: [
                    _SwitchTile(
                      icon: Icons.notifications_active_outlined,
                      title: loc.settingsWorkoutTimerNotif,
                      subtitle: loc.settingsWorkoutTimerNotifSubtitle,
                      value:
                          _settings['notification_workout_timer_enabled'] !=
                              'false',
                      onChanged: (v) {
                        _update('notification_workout_timer_enabled',
                            v.toString());
                        NotificationService.instance.loadSettings();
                      },
                    ),
                    if (_settings['notification_workout_timer_enabled'] !=
                        'false') ...[
                      const _CardDivider(),
                      _SwitchTile(
                        icon: Icons.volume_up_outlined,
                        title: loc.settingsSound,
                        subtitle: loc.settingsWorkoutSoundSubtitle,
                        indent: true,
                        value: _settings['notification_workout_timer_sound'] ==
                            'true',
                        onChanged: (v) {
                          _update('notification_workout_timer_sound',
                              v.toString());
                          NotificationService.instance.loadSettings();
                        },
                      ),
                      const _CardDivider(),
                      _SwitchTile(
                        icon: Icons.vibration,
                        title: loc.settingsVibration,
                        subtitle: loc.settingsWorkoutVibrationSubtitle,
                        indent: true,
                        value:
                            _settings['notification_workout_timer_vibration'] ==
                                'true',
                        onChanged: (v) {
                          _update('notification_workout_timer_vibration',
                              v.toString());
                          NotificationService.instance.loadSettings();
                        },
                      ),
                    ],
                  ],
                ),

                // ===== DADOS =====
                _SectionHeader(text: loc.settingsSectionData),
                _SettingsCard(
                  children: [
                    _LinkTile(
                      icon: Icons.download_outlined,
                      iconColor: theme.colorScheme.primary,
                      title: loc.settingsExportBackup,
                      subtitle: loc.settingsExportBackupSubtitle,
                      onTap: _exportBackup,
                    ),
                    const _CardDivider(),
                    _LinkTile(
                      icon: Icons.upload_outlined,
                      iconColor: theme.colorScheme.primary,
                      title: loc.settingsImportBackup,
                      subtitle: loc.settingsImportBackupSubtitle,
                      onTap: _importBackup,
                    ),
                    if (_showTestData) ...[
                      const _CardDivider(),
                      _LinkTile(
                        icon: Icons.bug_report_outlined,
                        iconColor: theme.colorScheme.secondary,
                        title: loc.settingsGenerateTestData,
                        subtitle: loc.settingsGenerateTestDataSubtitle,
                        onTap: _generateTestData,
                      ),
                    ],
                    const _CardDivider(),
                    _LinkTile(
                      icon: Icons.info_outline,
                      iconColor: theme.colorScheme.onSurfaceVariant,
                      title: loc.settingsAbout,
                      subtitle: loc.settingsAboutSubtitle,
                      onTap: _showAbout,
                    ),
                    const _CardDivider(),
                    _LinkTile(
                      icon: Icons.delete_outline,
                      iconColor: Colors.red,
                      title: loc.settingsDeleteAllHistory,
                      subtitle:
                          loc.settingsDeleteHistoryContent.split('\n').first,
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

// ===================== SHARED WIDGETS =====================

/// Section header (uppercase, tracked, muted). Consistent with the
/// home screen pattern.
class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Card container with optional title and rounded outline.
class _SettingsCard extends StatelessWidget {
  final String? title;
  final IconData? icon;
  final List<Widget> children;
  const _SettingsCard({this.title, this.icon, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side:
            BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    title!,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ...children,
        ],
      ),
    );
  }
}

/// Horizontal divider used between rows inside a [_SettingsCard].
class _CardDivider extends StatelessWidget {
  const _CardDivider();
  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: 56, // aligns under the title text, past the leading icon
      endIndent: 16,
      color: Theme.of(context).colorScheme.outlineVariant.withAlpha(60),
    );
  }
}

/// Radio-style row: leading icon, title + subtitle, check icon on the
/// right when selected. Tapping the whole row triggers [onTap].
class _RadioOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  const _RadioOption({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: selected
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerHighest.withAlpha(120),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 18,
                color: selected
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

/// Switch tile with leading icon, title + subtitle, switch on the right.
/// Tapping anywhere on the tile toggles the switch via [onChanged].
class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool indent;
  const _SwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.indent = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: EdgeInsets.fromLTRB(indent ? 32 : 16, 12, 12, 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

/// Tappable row that opens a deeper flow (or a dialog). Shows a chevron
/// at the trailing edge. Use [titleColor] for destructive tiles.
class _LinkTile extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? titleColor;
  const _LinkTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = titleColor ?? theme.colorScheme.onSurface;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: (iconColor ?? theme.colorScheme.primary).withAlpha(25),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 18,
                color: iconColor ?? theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w500, color: fg),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant, size: 20),
          ],
        ),
      ),
    );
  }
}

/// Single color swatch used in the accent color grid. The selected
/// swatch is highlighted with a thicker border and a white check.
class _ColorSwatch extends StatelessWidget {
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;
  const _ColorSwatch({
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: isSelected,
      label: color.toARGB32().toRadixString(16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(14),
              border: isSelected
                  ? Border.all(
                      color: theme.colorScheme.onSurface, width: 2.5)
                  : Border.all(color: color.withAlpha(120), width: 1),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: color.withAlpha(100),
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: isSelected
                ? const Icon(Icons.check, color: Colors.white, size: 22)
                : null,
          ),
        ),
      ),
    );
  }
}

/// Tappable row showing the current [displayValue] and a chevron. Tapping
/// opens a bottom sheet that lets the user pick from [choices]. The chosen
/// value is forwarded to [onChanged].
///
/// Use for "single value from a small set" settings like rest time, where
/// chips or inline rows would either wrap to multiple lines or take too
/// much vertical space.
class _ValuePickerTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final int currentValue;
  final String displayValue;
  final List<int> choices;
  final String Function(int) formatChoice;
  final String sheetTitle;
  final ValueChanged<int> onChanged;

  const _ValuePickerTile({
    required this.icon,
    required this.title,
    required this.currentValue,
    required this.displayValue,
    required this.choices,
    required this.formatChoice,
    required this.sheetTitle,
    required this.onChanged,
  });

  Future<void> _openSheet(BuildContext context) async {
    final theme = Theme.of(context);
    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Row(
                  children: [
                    Icon(icon, size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      sheetTitle,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, thickness: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: choices.length,
                  itemBuilder: (ctx, i) {
                    final value = choices[i];
                    final isSelected = value == currentValue;
                    return InkWell(
                      onTap: () => Navigator.pop(ctx, value),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 14),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                formatChoice(value),
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: isSelected
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurface,
                                ),
                              ),
                            ),
                            Icon(
                              isSelected
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                              color: isSelected
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.outlineVariant,
                              size: 22,
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
    if (selected != null) onChanged(selected);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => _openSheet(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon,
                  size: 18, color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              displayValue,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant, size: 20),
          ],
        ),
      ),
    );
  }
}

/// Tile used in the import source-picker bottom sheet.
class _ImportOptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ImportOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withAlpha(120),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon,
                  size: 22, color: theme.colorScheme.onPrimaryContainer),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant, size: 20),
          ],
        ),
      ),
    );
  }
}
