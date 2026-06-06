import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import '../../repositories/settings_repository.dart';
import '../../repositories/export_import_repository.dart';
import '../../database/test_seed_data.dart';
import '../../services/export_service.dart';
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

  @override
  void initState() {
    super.initState();
    _selectedAccentIndex = AccentColors.indexOf(
      WorkoutNotesApp.themeNotifier.seedColor,
    );
    _selectedThemeMode = WorkoutNotesApp.themeNotifier.themeMode;
    _load();
  }

  Future<void> _load() async {
    _settings = await _settingsRepo.getAllSettings();
    setState(() => _isLoading = false);
  }

  Future<void> _update(String key, String value) async {
    await _settingsRepo.setSetting(key, value);
    _settings[key] = value;
    setState(() {});
  }

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

  Widget _buildThemeModeOption({
    required ThemeData theme,
    required IconData icon,
    required String label,
    required String subtitle,
    required ThemeMode mode,
  }) {
    final isSelected = _selectedThemeMode == mode;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _changeThemeMode(mode),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isSelected
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerHighest.withAlpha(120),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 20,
                color: isSelected
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, size: 20, color: theme.colorScheme.primary)
            else
              Icon(Icons.circle_outlined, size: 20, color: theme.colorScheme.outlineVariant),
          ],
        ),
      ),
    );
  }

  Future<void> _exportBackup() async {
    final exportService = ExportService();
    try {
      await exportService.shareJsonBackup();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.settingsExportSuccess), behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.settingsExportError(e.toString())), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  Future<void> _generateTestData() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.settingsGenerateTitle),
        content: Text(AppLocalizations.of(context)!.settingsGenerateContent),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppLocalizations.of(context)!.commonCancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(AppLocalizations.of(context)!.settingsGenerate)),
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
          SnackBar(content: Text(AppLocalizations.of(context)!.commonError(e.toString())), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  Future<void> _deleteAllHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.settingsDeleteHistoryTitle),
        content: Text(AppLocalizations.of(context)!.settingsDeleteHistoryContent),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppLocalizations.of(context)!.commonCancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppLocalizations.of(context)!.settingsDeleteEverything, style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ExportImportRepository().deleteAllWorkoutData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.settingsDeleteHistorySuccess), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.settingsTitle),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Theme (Color & Mode)
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Global title
                        Row(
                          children: [
                            Icon(Icons.palette_outlined, size: 18, color: theme.colorScheme.primary),
                            const SizedBox(width: 8),
                            Text(AppLocalizations.of(context)!.settingsAppearance, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 16),
                        // Theme Mode section
                        Row(
                          children: [
                            Icon(Icons.dark_mode, size: 18, color: theme.colorScheme.primary),
                            const SizedBox(width: 8),
                            Text(AppLocalizations.of(context)!.settingsThemeMode, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildThemeModeOption(
                          theme: theme,
                          icon: Icons.brightness_auto,
                          label: AppLocalizations.of(context)!.settingsSystem,
                          subtitle: AppLocalizations.of(context)!.settingsSystemSubtitle,
                          mode: ThemeMode.system,
                        ),
                        const Divider(height: 1, indent: 0, endIndent: 0),
                        _buildThemeModeOption(
                          theme: theme,
                          icon: Icons.light_mode,
                          label: AppLocalizations.of(context)!.settingsLight,
                          subtitle: AppLocalizations.of(context)!.settingsLightSubtitle,
                          mode: ThemeMode.light,
                        ),
                        const Divider(height: 1, indent: 0, endIndent: 0),
                        _buildThemeModeOption(
                          theme: theme,
                          icon: Icons.dark_mode,
                          label: AppLocalizations.of(context)!.settingsDark,
                          subtitle: AppLocalizations.of(context)!.settingsDarkSubtitle,
                          mode: ThemeMode.dark,
                        ),
                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 16),
                        // Accent Color section
                        Row(
                          children: [
                            Icon(Icons.palette, size: 18, color: theme.colorScheme.primary),
                            const SizedBox(width: 8),
                            Text(AppLocalizations.of(context)!.settingsThemeColor, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: List.generate(AccentColors.options.length, (i) {
                            final isSelected = _selectedAccentIndex == i;
                            final color = AccentColors.options[i];
                            return GestureDetector(
                              onTap: () => _changeAccentColor(i),
                              child: Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(12),
                                  border: isSelected
                                      ? Border.all(color: theme.colorScheme.onSurface, width: 2.5)
                                      : Border.all(color: color.withAlpha(120), width: 1),
                                  boxShadow: isSelected
                                      ? [BoxShadow(color: color.withAlpha(100), blurRadius: 8, spreadRadius: 1)]
                                      : null,
                                ),
                                child: isSelected
                                    ? const Icon(Icons.check, color: Colors.white, size: 20)
                                    : null,
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _accentColorLabel(_selectedAccentIndex),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Unit system
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Row(
                          children: [
                            Icon(Icons.straighten, size: 18, color: theme.colorScheme.primary),
                            const SizedBox(width: 8),
                            Text(AppLocalizations.of(context)!.settingsUnits, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      SwitchListTile(
                        title: Text(AppLocalizations.of(context)!.settingsUnitSystem),
                        subtitle: Text(_settings['unit_system'] == 'kg' ? AppLocalizations.of(context)!.settingsUnitKgCm : AppLocalizations.of(context)!.settingsUnitLbsIn),
                        value: _settings['unit_system'] == 'kg',
                        onChanged: (v) => _update('unit_system', v ? 'kg' : 'lbs'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Rest timer defaults
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Row(
                          children: [
                            Icon(Icons.timer, size: 18, color: theme.colorScheme.primary),
                            const SizedBox(width: 8),
                            Text(AppLocalizations.of(context)!.settingsTimer, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      ListTile(
                        title: Text(AppLocalizations.of(context)!.settingsDefaultRest),
                        subtitle: Text('${_settings['default_rest_time'] ?? '90'} ${AppLocalizations.of(context)!.settingsSeconds}'),
                        trailing: SizedBox(
                          width: 100,
                          child: DropdownButtonFormField<int>(
                            initialValue: int.tryParse(_settings['default_rest_time'] ?? '90') ?? 90,
                            items: const [30, 45, 60, 90, 120, 180].map((s) => DropdownMenuItem(
                              value: s, child: Text(s >= 60 ? '${s ~/ 60}min' : '${s}s'),
                            )).toList(),
                            onChanged: (v) => _update('default_rest_time', v.toString()),
                            decoration: const InputDecoration(border: InputBorder.none, isDense: true),
                          ),
                        ),
                      ),
                      SwitchListTile(
                        title: Text(AppLocalizations.of(context)!.settingsAutoStartRest),
                        subtitle: Text(AppLocalizations.of(context)!.settingsAutoStartRestSubtitle),
                        value: _settings['auto_start_rest_timer'] == 'true',
                        onChanged: (v) => _update('auto_start_rest_timer', v.toString()),
                      ),
                      SwitchListTile(
                        title: Text(AppLocalizations.of(context)!.settingsAutoStartWorkoutTimer),
                        subtitle: Text(AppLocalizations.of(context)!.settingsAutoStartWorkoutTimerSubtitle),
                        value: _settings['auto_start_workout_timer'] == 'true',
                        onChanged: (v) => _update('auto_start_workout_timer', v.toString()),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Notifications
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Row(
                          children: [
                            Icon(Icons.notifications, size: 18, color: theme.colorScheme.primary),
                            const SizedBox(width: 8),
                            Text(AppLocalizations.of(context)!.settingsNotifications, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),

                      // ── Rest Timer Notification ──
                      SwitchListTile(
                        title: Text(AppLocalizations.of(context)!.settingsRestTimerNotif),
                        subtitle: Text(AppLocalizations.of(context)!.settingsRestTimerNotifSubtitle),
                        value: _settings['notification_rest_timer_enabled'] != 'false',
                        onChanged: (v) {
                          _update('notification_rest_timer_enabled', v.toString());
                          NotificationService.instance.loadSettings();
                        },
                      ),
                      if (_settings['notification_rest_timer_enabled'] != 'false') ...[
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.only(left: 16),
                          child: Row(
                            children: [
                              Icon(Icons.notifications_active, size: 16, color: theme.colorScheme.onSurfaceVariant.withAlpha(120)),
                              const SizedBox(width: 8),
                              Text(AppLocalizations.of(context)!.settingsAlertOptions, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                        SwitchListTile(
                          title: Text(AppLocalizations.of(context)!.settingsSound),
                          subtitle: Text(AppLocalizations.of(context)!.settingsRestSoundSubtitle),
                          value: _settings['notification_rest_timer_sound'] != 'false',
                          onChanged: (v) {
                            _update('notification_rest_timer_sound', v.toString());
                            NotificationService.instance.loadSettings();
                          },
                        ),
                        SwitchListTile(
                          title: Text(AppLocalizations.of(context)!.settingsVibration),
                          subtitle: Text(AppLocalizations.of(context)!.settingsRestVibrationSubtitle),
                          value: _settings['notification_rest_timer_vibration'] != 'false',
                          onChanged: (v) {
                            _update('notification_rest_timer_vibration', v.toString());
                            NotificationService.instance.loadSettings();
                          },
                        ),
                      ],
                      const Divider(height: 1, indent: 16, endIndent: 16),

                      // ── Workout Timer Notification ──
                      SwitchListTile(
                        title: Text(AppLocalizations.of(context)!.settingsWorkoutTimerNotif),
                        subtitle: Text(AppLocalizations.of(context)!.settingsWorkoutTimerNotifSubtitle),
                        value: _settings['notification_workout_timer_enabled'] != 'false',
                        onChanged: (v) {
                          _update('notification_workout_timer_enabled', v.toString());
                          NotificationService.instance.loadSettings();
                        },
                      ),
                      if (_settings['notification_workout_timer_enabled'] != 'false') ...[
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.only(left: 16),
                          child: Row(
                            children: [
                              Icon(Icons.notifications_active, size: 16, color: theme.colorScheme.onSurfaceVariant.withAlpha(120)),
                              const SizedBox(width: 8),
                              Text(AppLocalizations.of(context)!.settingsAlertOptions, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                        SwitchListTile(
                          title: Text(AppLocalizations.of(context)!.settingsSound),
                          subtitle: Text(AppLocalizations.of(context)!.settingsWorkoutSoundSubtitle),
                          value: _settings['notification_workout_timer_sound'] == 'true',
                          onChanged: (v) {
                            _update('notification_workout_timer_sound', v.toString());
                            NotificationService.instance.loadSettings();
                          },
                        ),
                        SwitchListTile(
                          title: Text(AppLocalizations.of(context)!.settingsVibration),
                          subtitle: Text(AppLocalizations.of(context)!.settingsWorkoutVibrationSubtitle),
                          value: _settings['notification_workout_timer_vibration'] == 'true',
                          onChanged: (v) {
                            _update('notification_workout_timer_vibration', v.toString());
                            NotificationService.instance.loadSettings();
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Display
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Row(
                          children: [
                            Icon(Icons.visibility, size: 18, color: theme.colorScheme.primary),
                            const SizedBox(width: 8),
                            Text(AppLocalizations.of(context)!.settingsDisplay, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      SwitchListTile(
                        title: Text(AppLocalizations.of(context)!.settingsKeepScreenOn),
                        subtitle: Text(AppLocalizations.of(context)!.settingsKeepScreenOnSubtitle),
                        value: _settings['keep_screen_on'] == 'true',
                        onChanged: (v) => _update('keep_screen_on', v.toString()),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Language
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.language, size: 18, color: theme.colorScheme.primary),
                            const SizedBox(width: 8),
                            Text(AppLocalizations.of(context)!.settingsLanguage, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _buildLanguageOption(
                          theme: theme,
                          label: AppLocalizations.of(context)!.settingsPortuguese,
                          subtitle: AppLocalizations.of(context)!.settingsPortuguese,
                          icon: Icons.flag,
                          locale: const Locale('pt', 'BR'),
                        ),
                        const Divider(height: 1, indent: 0, endIndent: 0),
                        _buildLanguageOption(
                          theme: theme,
                          label: AppLocalizations.of(context)!.settingsEnglish,
                          subtitle: AppLocalizations.of(context)!.settingsEnglish,
                          icon: Icons.language,
                          locale: const Locale('en'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Data management
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Row(
                          children: [
                            Icon(Icons.storage, size: 18, color: theme.colorScheme.primary),
                            const SizedBox(width: 8),
                            Text(AppLocalizations.of(context)!.settingsData, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      ListTile(
                        leading: Icon(Icons.download, color: theme.colorScheme.primary),
                        title: Text(AppLocalizations.of(context)!.settingsExportBackup),
                        subtitle: Text(AppLocalizations.of(context)!.settingsExportBackupSubtitle),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _exportBackup(),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      ListTile(
                        leading: Icon(Icons.bug_report, color: theme.colorScheme.secondary),
                        title: Text(AppLocalizations.of(context)!.settingsGenerateTestData),
                        subtitle: Text(AppLocalizations.of(context)!.settingsGenerateTestDataSubtitle),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _generateTestData(),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      ListTile(
                        leading: Icon(Icons.info_outline, color: theme.colorScheme.onSurfaceVariant),
                        title: Text(AppLocalizations.of(context)!.settingsAbout),
                        subtitle: Text(AppLocalizations.of(context)!.settingsAboutSubtitle),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Danger zone
                Center(
                  child: TextButton.icon(
                    onPressed: _deleteAllHistory,
                    icon: const Icon(Icons.delete_forever, color: Colors.red),
                    label: Text(AppLocalizations.of(context)!.settingsDeleteAllHistory, style: TextStyle(color: Colors.red)),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
    );
  }

  String _accentColorLabel(int index) {
    switch (index) {
      case 0: return AppLocalizations.of(context)!.accentColorRed;
      case 1: return AppLocalizations.of(context)!.accentColorDarkOrange;
      case 2: return AppLocalizations.of(context)!.accentColorOrange;
      case 3: return AppLocalizations.of(context)!.accentColorAmber;
      case 4: return AppLocalizations.of(context)!.accentColorDeepPurple;
      case 5: return AppLocalizations.of(context)!.accentColorDarkBlue;
      case 6: return AppLocalizations.of(context)!.accentColorGraphite;
      case 7: return AppLocalizations.of(context)!.accentColorForestGreen;
      default: return '';
    }
  }

  Widget _buildLanguageOption({
    required ThemeData theme,
    required String label,
    required String subtitle,
    required IconData icon,
    required Locale locale,
  }) {
    final isSelected = Localizations.localeOf(context).languageCode == locale.languageCode;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _changeLocale(locale),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isSelected
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerHighest.withAlpha(120),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 20,
                color: isSelected
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, size: 20, color: theme.colorScheme.primary)
            else
              Icon(Icons.circle_outlined, size: 20, color: theme.colorScheme.outlineVariant),
          ],
        ),
      ),
    );
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
}
