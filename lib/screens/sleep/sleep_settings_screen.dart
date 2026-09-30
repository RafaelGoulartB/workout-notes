import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/alarm_wake_settings.dart';
import 'package:workout_notes/services/alarm_wake_settings_service.dart';
import 'package:workout_notes/services/sleep_diagnostic_store.dart';
import 'package:workout_notes/services/sleep_goal_service.dart';
import 'package:workout_notes/services/sleep_mission_service.dart';
import 'package:workout_notes/services/sleep_monitor_service.dart';
import 'package:workout_notes/services/traditional_alarm_service.dart';
import 'package:workout_notes/widgets/settings/settings.dart';
import 'package:workout_notes/widgets/sleep/monitor/smart_wake_widgets.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

class SleepSettingsScreen extends StatefulWidget {
  const SleepSettingsScreen({super.key});

  @override
  State<SleepSettingsScreen> createState() => _SleepSettingsScreenState();
}

class _SleepSettingsScreenState extends State<SleepSettingsScreen> {
  final _missions = SleepMissionService();
  final _monitor = SleepMonitorService.instance;
  final _sleepGoalService = SleepGoalService();
  final _alarmService = TraditionalAlarmService.instance;
  bool _loading = true;
  bool _busy = false;
  int _goalMinutes = SleepGoalService.defaultGoalMinutes;
  int _globalMaxSnoozes = TraditionalAlarmService.defaultMaxSnoozes;
  bool _globalSnoozeEnabled = true;
  bool _diagnosticsEnabled = false;
  final _diagnostics = SleepDiagnosticStore();
  final _wakeService = AlarmWakeSettingsService();
  AlarmWakeSettings _wake = AlarmWakeSettings.defaults;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _missions.load();
    final goalMinutes = await _sleepGoalService.load();
    final globalMaxSnoozes = await _alarmService.getGlobalMaxSnoozes();
    final globalSnoozeEnabled = await _alarmService.getGlobalSnoozeEnabled();
    final diagnosticsEnabled = await _diagnostics.isEnabled();
    final wake = await _wakeService.load();
    if (mounted) {
      setState(() {
        _wake = wake;
        _goalMinutes = goalMinutes;
        _globalMaxSnoozes = globalMaxSnoozes;
        _globalSnoozeEnabled = globalSnoozeEnabled;
        _diagnosticsEnabled = diagnosticsEnabled;
        _loading = false;
      });
    }
  }

  Future<void> _setDiagnostics(bool enabled) async {
    try {
      await _diagnostics.setEnabled(enabled);
      if (mounted) setState(() => _diagnosticsEnabled = enabled);
    } catch (_) {
      if (mounted) _message(AppLocalizations.of(context)!.sleepDiagnosticError);
    }
  }

  Future<void> _exportDiagnostic() async {
    final loc = AppLocalizations.of(context)!;
    try {
      final file = await _diagnostics.latest();
      if (!mounted) return;
      if (file == null) {
        _message(loc.sleepDiagnosticMissing);
        return;
      }
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      await FilePicker.saveFile(
        dialogTitle: loc.sleepDiagnosticExport,
        fileName: 'sleep_diagnostic.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: bytes,
      );
    } catch (_) {
      if (mounted) _message(loc.sleepDiagnosticError);
    }
  }

  Future<void> _scan() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await _monitor.scanBarcodeForMission();
      if (!mounted) return;
      if (result == null) {
        final loc = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc.sleepMissionScanError),
            action: SnackBarAction(
              label: loc.sleepMissionOpenSettings,
              onPressed: _monitor.openCameraSettings,
            ),
          ),
        );
        return;
      }
      await _missions.saveScanResult(result);
      if (!mounted) return;
      _message(AppLocalizations.of(context)!.sleepMissionSaved);
    } catch (_) {
      if (mounted) {
        _message(AppLocalizations.of(context)!.sleepMissionScanError);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggle(bool enabled) async {
    if (enabled && !_missions.config.isConfigured) {
      await _scan();
      return;
    }
    await _missions.setEnabled(enabled);
  }

  Future<void> _configureGoal() async {
    final loc = AppLocalizations.of(context)!;
    final selected = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        var value = _goalMinutes.toDouble();
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(loc.sleepGoalDialogTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  loc.sleepGoalDialogDescription,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                Text(
                  _formatGoal(value.round(), loc),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Slider(
                  min: SleepGoalService.minimumGoalMinutes.toDouble(),
                  max: SleepGoalService.maximumGoalMinutes.toDouble(),
                  divisions:
                      (SleepGoalService.maximumGoalMinutes -
                          SleepGoalService.minimumGoalMinutes) ~/
                      SleepGoalService.stepMinutes,
                  value: value,
                  label: _formatGoal(value.round(), loc),
                  onChanged: (next) => setDialogState(() => value = next),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(loc.commonCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(
                  dialogContext,
                  SleepGoalService.normalize(value.round()),
                ),
                child: Text(loc.commonSave),
              ),
            ],
          ),
        );
      },
    );
    if (selected == null) return;
    await _sleepGoalService.save(selected);
    if (!mounted) return;
    setState(() => _goalMinutes = selected);
    _message(loc.sleepGoalSaved);
  }

  static String _formatGoal(int minutes, AppLocalizations loc) =>
      loc.sleepDurationValue(minutes ~/ 60, minutes % 60);

  Future<void> _configureGlobalMaxSnoozes() async {
    final loc = AppLocalizations.of(context)!;
    var value = _globalMaxSnoozes;
    final selected = await showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(loc.alarmMaxSnoozes),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(loc.sleepSettingsMaxSnoozesDialogBody),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: value,
                decoration: InputDecoration(
                  labelText: loc.sleepSettingsAllowedSnoozes,
                ),
                items: List.generate(
                  11,
                  (index) => DropdownMenuItem(
                    value: index,
                    child: Text(
                      index == 0
                          ? loc.alarmNoSnoozes
                          : loc.alarmSnoozeTimes(index),
                    ),
                  ),
                ),
                onChanged: (next) {
                  if (next != null) setDialogState(() => value = next);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(loc.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, value),
              child: Text(loc.commonSave),
            ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    await _alarmService.setGlobalMaxSnoozes(selected);
    if (mounted) setState(() => _globalMaxSnoozes = selected);
  }

  Future<void> _saveWake(AlarmWakeSettings value) async {
    setState(() => _wake = value);
    await _wakeService.save(value);
  }

  Future<void> _configureSmartWake() async {
    final selected = await showSmartWakeSheet(context, _wake);
    if (selected == null || !mounted) return;
    await _saveWake(selected);
  }

  Future<void> _configureRamp() async {
    final loc = AppLocalizations.of(context)!;
    final selected = await showDialog<int>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(loc.alarmRampTitle),
        children: [
          for (final seconds in AlarmWakeSettings.rampOptions)
            ListTile(
              key: Key('alarm-ramp-$seconds'),
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              title: Text(alarmRampLabel(loc, seconds)),
              trailing: seconds == _wake.rampSeconds
                  ? Icon(
                      Icons.check_rounded,
                      color: Theme.of(dialogContext).colorScheme.primary,
                    )
                  : null,
              onTap: () => Navigator.pop(dialogContext, seconds),
            ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    await _saveWake(_wake.copyWith(rampSeconds: selected));
  }

  Future<void> _setGlobalSnoozeEnabled(bool enabled) async {
    await _alarmService.setGlobalSnoozeEnabled(enabled);
    if (mounted) setState(() => _globalSnoozeEnabled = enabled);
  }

  Future<void> _remove() async {
    final loc = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: loc.sleepMissionRemove,
      message: loc.sleepMissionRemoveConfirm,
      confirmLabel: loc.sleepMissionRemove,
    );
    if (confirmed == true) {
      await _missions.clear();
      if (mounted) _message(loc.sleepMissionRemoved);
    }
  }

  void _message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: SettingsAppBar(title: loc.sleepSettingsTitle),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                AppSectionHeader(
                  loc.sleepSettingsGoalSection,
                  padding: AppSectionHeader.compactPadding,
                ),
                SettingsCard(
                  children: [
                    SettingsLinkTile(
                      icon: Icons.track_changes_rounded,
                      title: loc.sleepGoalTitle,
                      subtitle: loc.sleepGoalCurrent(
                        _formatGoal(_goalMinutes, loc),
                      ),
                      onTap: _configureGoal,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Text(
                        loc.sleepGoalBody,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                AppSectionHeader(
                  loc.sleepDiagnosticTitle,
                  padding: AppSectionHeader.compactPadding,
                ),
                SettingsCard(
                  children: [
                    SettingsSwitchTile(
                      icon: Icons.analytics_outlined,
                      title: loc.sleepDiagnosticTitle,
                      subtitle: loc.sleepDiagnosticBody,
                      value: _diagnosticsEnabled,
                      onChanged: _setDiagnostics,
                    ),
                    if (_diagnosticsEnabled)
                      SettingsLinkTile(
                        icon: Icons.file_download_outlined,
                        title: loc.sleepDiagnosticExport,
                        onTap: _exportDiagnostic,
                      ),
                  ],
                ),
                AppSectionHeader(
                  loc.sleepSettingsWakeSection,
                  padding: AppSectionHeader.compactPadding,
                ),
                SettingsCard(
                  children: [
                    SettingsLinkTile(
                      key: const Key('sleep-settings-smart-wake'),
                      icon: Icons.auto_awesome_rounded,
                      title: loc.sleepSmartWakeTitle,
                      subtitle: _wake.smartWindowEnabled
                          ? loc.sleepSettingsSmartWindowValue(
                              _wake.windowMinutes,
                              smartWakeSensitivityTitle(loc, _wake.sensitivity),
                            )
                          : loc.sleepSmartWakeWindowOff,
                      onTap: _configureSmartWake,
                    ),
                    const SettingsCardDivider(),
                    SettingsLinkTile(
                      key: const Key('sleep-settings-ramp'),
                      icon: Icons.volume_up_rounded,
                      title: loc.alarmRampTitle,
                      subtitle: _wake.rampSeconds == 0
                          ? loc.alarmRampOff
                          : loc.alarmRampValue(
                              alarmRampLabel(loc, _wake.rampSeconds),
                            ),
                      onTap: _configureRamp,
                    ),
                    const SettingsCardDivider(),
                    SettingsSwitchTile(
                      icon: Icons.campaign_outlined,
                      title: loc.alarmRampBoost,
                      subtitle: loc.alarmRampBoostBody,
                      value: _wake.boost,
                      onChanged: (value) =>
                          _saveWake(_wake.copyWith(boost: value)),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Text(
                        loc.sleepSettingsWakeBody,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                AppSectionHeader(
                  loc.sleepSettingsAlarmsSection,
                  padding: AppSectionHeader.compactPadding,
                ),
                SettingsCard(
                  children: [
                    SettingsSwitchTile(
                      icon: Icons.snooze_rounded,
                      title: loc.sleepSettingsSnoozeToggle,
                      subtitle: loc.sleepSettingsSnoozeToggleBody,
                      value: _globalSnoozeEnabled,
                      onChanged: _setGlobalSnoozeEnabled,
                    ),
                    const SettingsCardDivider(),
                    SettingsLinkTile(
                      icon: Icons.timer_outlined,
                      title: loc.alarmMaxSnoozes,
                      subtitle: _globalMaxSnoozes == 0
                          ? loc.alarmNoSnoozes
                          : loc.alarmSnoozeTimes(_globalMaxSnoozes),
                      onTap: _globalSnoozeEnabled
                          ? _configureGlobalMaxSnoozes
                          : null,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Text(
                        loc.sleepSettingsMaxSnoozesBody,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                AppSectionHeader(
                  loc.sleepSettingsMissionSection,
                  padding: AppSectionHeader.compactPadding,
                ),
                SettingsCard(
                  children: [
                    SettingsSwitchTile(
                      icon: Icons.bedtime_outlined,
                      title: loc.sleepMissionToggle,
                      subtitle: loc.sleepMissionToggleBody,
                      value: _missions.config.enabled,
                      onChanged: (v) {
                        if (_busy) return;
                        _toggle(v);
                      },
                    ),
                    if (_missions.config.isConfigured)
                      const SettingsCardDivider(),
                    if (_missions.config.isConfigured)
                      SettingsInfoTile(
                        icon: Icons.qr_code_2_rounded,
                        title: loc.sleepMissionConfigured(
                          _missions.config.format ??
                              loc.sleepMissionFormatUnknown,
                        ),
                        subtitle: _missions.config.registeredAt == null
                            ? null
                            : DateFormat.yMd(
                                Localizations.localeOf(context).toLanguageTag(),
                              ).format(
                                _missions.config.registeredAt!.toLocal(),
                              ),
                      )
                    else
                      SettingsInfoTile(
                        icon: Icons.qr_code_2_outlined,
                        iconColor: theme.colorScheme.onSurfaceVariant,
                        title: loc.sleepMissionNotConfigured,
                      ),
                    const SettingsCardDivider(),
                    SettingsLinkTile(
                      icon: _missions.config.isConfigured
                          ? Icons.swap_horiz_rounded
                          : Icons.camera_alt_outlined,
                      title: _missions.config.isConfigured
                          ? loc.sleepMissionReplace
                          : loc.sleepMissionScan,
                      onTap: _busy ? null : _scan,
                    ),
                    if (_missions.config.isConfigured) ...[
                      const SettingsCardDivider(),
                      SettingsLinkTile(
                        icon: Icons.delete_outline_rounded,
                        title: loc.sleepMissionRemove,
                        destructive: true,
                        onTap: _busy ? null : _remove,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.security_outlined,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            loc.sleepMonitorModeAlarmWithMissionBody,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
