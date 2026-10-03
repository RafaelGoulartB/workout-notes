import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_notes/main.dart';
import 'package:workout_notes/services/ai_memory_service.dart';
import 'package:workout_notes/services/medication_reminder_service.dart';
import 'package:workout_notes/services/traditional_alarm_service.dart';
import 'package:workout_notes/state/ai_chat_service.dart';
import 'package:workout_notes/state/sections_notifier.dart';
import 'package:workout_notes/utils/app_locale.dart';

/// Brings everything that lives outside SQLite's tables back in line after the
/// user's data was replaced wholesale (a backup restore) or wiped ("delete all
/// history").
///
/// Native alarms and reminder slots, in-memory service state and the settings
/// notifiers all cache data that changed underneath them. Every step is best
/// effort and independent: a failure is logged and never stops the others or
/// turns an already committed restore into an error.
class AppDataCoordinator {
  AppDataCoordinator({
    Future<void> Function()? syncAlarms,
    Future<void> Function()? syncMedications,
    Future<void> Function()? resetAi,
    Future<void> Function()? refreshAppearance,
  }) : _syncAlarms = syncAlarms ?? _defaultSyncAlarms,
       _syncMedications = syncMedications ?? _defaultSyncMedications,
       _resetAi = resetAi ?? _defaultResetAi,
       _refreshAppearance = refreshAppearance ?? _defaultRefreshAppearance;

  static final AppDataCoordinator instance = AppDataCoordinator();

  final Future<void> Function() _syncAlarms;
  final Future<void> Function() _syncMedications;
  final Future<void> Function() _resetAi;
  final Future<void> Function() _refreshAppearance;

  /// Call after the database content (and, for a restore, the portable
  /// preferences) were replaced. [settingsReplaced] also re-applies theme,
  /// accent colour, language and section visibility from the preferences.
  Future<void> afterDataReplaced({required bool settingsReplaced}) async {
    await _guard('alarms', _syncAlarms);
    await _guard('medications', _syncMedications);
    await _guard('ai', _resetAi);
    if (settingsReplaced) await _guard('appearance', _refreshAppearance);
  }

  static Future<void> _guard(String name, Future<void> Function() step) async {
    try {
      await step();
    } catch (error) {
      debugPrint('Post-restore step "$name" failed: $error');
    }
  }

  static Future<void> _defaultSyncAlarms() async {
    final alarms = TraditionalAlarmService.instance;
    await alarms.reconcile(resync: true);
    await alarms.refresh();
  }

  static Future<void> _defaultSyncMedications() async {
    final medications = MedicationReminderService.instance;
    await medications.reconcile();
    await medications.refresh();
  }

  static Future<void> _defaultResetAi() async {
    AiChatService.instance.reset();
    AiMemoryService.instance.invalidateCache();
    await WorkoutNotesApp.aiSettings.load();
  }

  static Future<void> _defaultRefreshAppearance() async {
    final prefs = await SharedPreferences.getInstance();
    final accent = prefs.getInt('accent_color');
    WorkoutNotesApp.themeNotifier
      ..setSeedColor(accent == null ? AccentColors.defaultColor : Color(accent))
      ..setThemeMode(switch (prefs.getString('theme_mode')) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      });
    await WorkoutNotesApp.sections.setPlanEnabled(
      prefs.getBool(kPrefsPlanSectionEnabled) ?? true,
    );
    final language = AppLocale.languageCode(prefs.getString('app_locale'));
    await AppLocale.apply(language);
    WorkoutNotesApp.localeNotifier.setLocale(AppLocale.flutterLocale(language));
  }
}
