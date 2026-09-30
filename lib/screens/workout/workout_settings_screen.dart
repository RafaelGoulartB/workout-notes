import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/screens/workout/settings_preferences_controller.dart';
import 'package:workout_notes/widgets/settings/settings.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Workout preferences: units, rest timer, screen and notification options.
class WorkoutSettingsScreen extends StatefulWidget {
  const WorkoutSettingsScreen({super.key});

  @override
  State<WorkoutSettingsScreen> createState() => _WorkoutSettingsScreenState();
}

class _WorkoutSettingsScreenState extends State<WorkoutSettingsScreen> {
  final _controller = WorkoutPreferencesController();

  @override
  void initState() {
    super.initState();
    _controller.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: SettingsAppBar(title: loc.settingsWorkoutTitle),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          if (_controller.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          final settings = _controller.settings;
          final restTimerNotifications =
              settings['notification_rest_timer_enabled'] != 'false';
          final workoutTimerNotifications =
              settings['notification_workout_timer_enabled'] != 'false';
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              // ===== TREINO =====
              AppSectionHeader(loc.settingsSectionWorkout, padding: AppSectionHeader.compactPadding),
              SettingsCard(
                children: [
                  SettingsSwitchTile(
                    icon: Icons.straighten,
                    title: loc.settingsUnitSystem,
                    subtitle: settings['unit_system'] == 'kg'
                        ? loc.settingsUnitKgCm
                        : loc.settingsUnitLbsIn,
                    value: settings['unit_system'] == 'kg',
                    onChanged: (v) =>
                        _controller.update('unit_system', v ? 'kg' : 'lbs'),
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
                    currentValue: _controller.defaultRestSeconds,
                    displayValue: WorkoutPreferencesController.formatRestTime(
                      _controller.defaultRestSeconds,
                    ),
                    choices: WorkoutPreferencesController.restChoices,
                    formatChoice: WorkoutPreferencesController.formatRestTime,
                    sheetTitle: loc.settingsDefaultRest,
                    onChanged: (v) =>
                        _controller.update('default_rest_time', v.toString()),
                  ),
                  const SettingsCardDivider(),
                  SettingsSwitchTile(
                    icon: Icons.play_circle_outline,
                    title: loc.settingsAutoStartRest,
                    subtitle: loc.settingsAutoStartRestSubtitle,
                    value: settings['auto_start_rest_timer'] == 'true',
                    onChanged: (v) => _controller.update(
                      'auto_start_rest_timer',
                      v.toString(),
                    ),
                  ),
                  const SettingsCardDivider(),
                  SettingsSwitchTile(
                    icon: Icons.av_timer,
                    title: loc.settingsAutoStartWorkoutTimer,
                    subtitle: loc.settingsAutoStartWorkoutTimerSubtitle,
                    value: settings['auto_start_workout_timer'] == 'true',
                    onChanged: (v) => _controller.update(
                      'auto_start_workout_timer',
                      v.toString(),
                    ),
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
                    value: settings['keep_screen_on'] == 'true',
                    onChanged: (v) =>
                        _controller.update('keep_screen_on', v.toString()),
                  ),
                ],
              ),

              // ===== NOTIFICAÇÕES =====
              AppSectionHeader(loc.settingsSectionNotifications, padding: AppSectionHeader.compactPadding),
              SettingsCard(
                children: [
                  SettingsSwitchTile(
                    icon: Icons.notifications_outlined,
                    title: loc.settingsRestTimerNotif,
                    subtitle: loc.settingsRestTimerNotifSubtitle,
                    value: restTimerNotifications,
                    onChanged: (v) => _controller.updateNotificationPreference(
                      'notification_rest_timer_enabled',
                      v,
                    ),
                  ),
                  if (restTimerNotifications) ...[
                    const SettingsCardDivider(),
                    SettingsSwitchTile(
                      icon: Icons.volume_up_outlined,
                      title: loc.settingsSound,
                      subtitle: loc.settingsRestSoundSubtitle,
                      indent: true,
                      value:
                          settings['notification_rest_timer_sound'] != 'false',
                      onChanged: (v) => _controller.updateNotificationFlag(
                        'notification_rest_timer_sound',
                        v,
                      ),
                    ),
                    const SettingsCardDivider(),
                    SettingsSwitchTile(
                      icon: Icons.vibration,
                      title: loc.settingsVibration,
                      subtitle: loc.settingsRestVibrationSubtitle,
                      indent: true,
                      value:
                          settings['notification_rest_timer_vibration'] !=
                          'false',
                      onChanged: (v) => _controller.updateNotificationFlag(
                        'notification_rest_timer_vibration',
                        v,
                      ),
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
                    value: workoutTimerNotifications,
                    onChanged: (v) => _controller.updateNotificationPreference(
                      'notification_workout_timer_enabled',
                      v,
                    ),
                  ),
                  if (workoutTimerNotifications) ...[
                    const SettingsCardDivider(),
                    SettingsSwitchTile(
                      icon: Icons.volume_up_outlined,
                      title: loc.settingsSound,
                      subtitle: loc.settingsWorkoutSoundSubtitle,
                      indent: true,
                      value:
                          settings['notification_workout_timer_sound'] ==
                          'true',
                      onChanged: (v) => _controller.updateNotificationFlag(
                        'notification_workout_timer_sound',
                        v,
                      ),
                    ),
                    const SettingsCardDivider(),
                    SettingsSwitchTile(
                      icon: Icons.vibration,
                      title: loc.settingsVibration,
                      subtitle: loc.settingsWorkoutVibrationSubtitle,
                      indent: true,
                      value:
                          settings['notification_workout_timer_vibration'] ==
                          'true',
                      onChanged: (v) => _controller.updateNotificationFlag(
                        'notification_workout_timer_vibration',
                        v,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
