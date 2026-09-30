import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/main.dart';
import 'package:workout_notes/repositories/settings_repository.dart';
import 'package:workout_notes/services/notification_service.dart';

/// `app_settings` backed preferences of the workout settings screen (units,
/// rest timer, notifications). The raw string map is exposed so tiles can
/// read the same keys the rest of the app persists.
class WorkoutPreferencesController extends ChangeNotifier {
  WorkoutPreferencesController({SettingsRepository? repository})
    : _repo = repository ?? DatabaseHelper.instance.settingsRepo;

  final SettingsRepository _repo;

  /// Rest-time choices (seconds) offered by the default-rest picker.
  static const restChoices = [30, 45, 60, 90, 120, 180];

  Map<String, String> _settings = {};
  bool _isLoading = true;
  bool _disposed = false;

  bool get isLoading => _isLoading;
  Map<String, String> get settings => _settings;

  int get defaultRestSeconds =>
      int.tryParse(_settings['default_rest_time'] ?? '90') ?? 90;

  Future<void> load() async {
    _settings = await _repo.getAllSettings();
    _isLoading = false;
    _notify();
  }

  Future<void> update(String key, String value) async {
    await _repo.setSetting(key, value);
    if (_disposed) return;
    _settings[key] = value;
    notifyListeners();
  }

  Future<void> updateNotificationPreference(String key, bool enabled) async {
    if (enabled) {
      await NotificationService.instance.requestPermission();
    }
    await update(key, enabled.toString());
    await NotificationService.instance.loadSettings();
  }

  /// Persists a notification sound/vibration flag and reloads the service.
  Future<void> updateNotificationFlag(String key, bool value) async {
    await update(key, value.toString());
    await NotificationService.instance.loadSettings();
  }

  /// Compact, locale-agnostic rest-time label: "30s", "1min", "1min 30s".
  static String formatRestTime(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return secs == 0 ? '${mins}min' : '${mins}min ${secs}s';
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Theme, accent colour and language changes of the general settings screen.
/// Persists to `shared_preferences` (read at app start) and pushes the change
/// to the app-wide notifiers.
class AppearanceController extends ChangeNotifier {
  AppearanceController({SettingsRepository? repository})
    : _repo = repository ?? DatabaseHelper.instance.settingsRepo,
      _accentIndex = AccentColors.indexOf(
        WorkoutNotesApp.themeNotifier.seedColor,
      ),
      _themeMode = WorkoutNotesApp.themeNotifier.themeMode;

  final SettingsRepository _repo;
  int _accentIndex;
  ThemeMode _themeMode;
  bool _disposed = false;

  int get accentIndex => _accentIndex;
  ThemeMode get themeMode => _themeMode;

  Future<void> changeAccentColor(int index) async {
    final color = AccentColors.options[index];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('accent_color', color.toARGB32());
    if (_disposed) return;
    _accentIndex = index;
    notifyListeners();
    WorkoutNotesApp.themeNotifier.setSeedColor(color);
  }

  /// Stored value for [mode] in both `shared_preferences` and `app_settings`.
  static String themeModeValue(ThemeMode mode) => switch (mode) {
    ThemeMode.light => 'light',
    ThemeMode.dark => 'dark',
    ThemeMode.system => 'system',
  };

  Future<void> changeThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    final value = themeModeValue(mode);
    await prefs.setString('theme_mode', value);
    await _repo.setSetting('theme_mode', value);
    if (_disposed) return;
    _themeMode = mode;
    notifyListeners();
    WorkoutNotesApp.themeNotifier.setThemeMode(mode);
  }

  Future<void> changeLocale(Locale newLocale) async {
    final prefs = await SharedPreferences.getInstance();
    final localeStr = newLocale.languageCode == 'pt' ? 'pt' : 'en';
    await prefs.setString('app_locale', localeStr);

    // Update date formatting
    await initializeDateFormatting(localeStr == 'pt' ? 'pt_BR' : 'en', null);
    Intl.defaultLocale = localeStr == 'pt' ? 'pt_BR' : 'en_US';

    WorkoutNotesApp.localeNotifier.setLocale(newLocale);
    await NotificationService.instance.loadSettings();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
