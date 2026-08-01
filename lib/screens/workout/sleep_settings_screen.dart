import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/services/sleep_mission_service.dart';
import 'package:workout_notes/services/sleep_monitor_service.dart';
import 'package:workout_notes/services/sleep_goal_service.dart';

class SleepSettingsScreen extends StatefulWidget {
  const SleepSettingsScreen({super.key});

  @override
  State<SleepSettingsScreen> createState() => _SleepSettingsScreenState();
}

class _SleepSettingsScreenState extends State<SleepSettingsScreen> {
  final _missions = SleepMissionService();
  final _monitor = SleepMonitorService.instance;
  final _sleepGoalService = SleepGoalService();
  bool _loading = true;
  bool _busy = false;
  int _goalMinutes = SleepGoalService.defaultGoalMinutes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _missions.load();
    final goalMinutes = await _sleepGoalService.load();
    if (mounted) {
      setState(() {
        _goalMinutes = goalMinutes;
        _loading = false;
      });
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
              onPressed: () {
                _monitor.openCameraSettings();
              },
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

  Future<void> _remove() async {
    final loc = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(loc.sleepMissionRemove),
        content: Text(loc.sleepMissionRemoveConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(loc.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(loc.sleepMissionRemove),
          ),
        ],
      ),
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
      appBar: AppBar(
        title: Text(
          loc.sleepSettingsTitle,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              children: [
                _SectionHeader(text: loc.sleepSettingsGoalSection),
                const SizedBox(height: 8),
                _SettingsCard(
                  children: [
                    _LinkTile(
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
                const SizedBox(height: 16),
                _SectionHeader(text: loc.sleepSettingsMissionSection),
                const SizedBox(height: 8),
                _SettingsCard(
                  children: [
                    SwitchListTile.adaptive(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                      value: _missions.config.enabled,
                      onChanged: _busy ? null : _toggle,
                      title: Text(loc.sleepMissionToggle),
                      subtitle: Text(loc.sleepMissionToggleBody),
                    ),
                    const Divider(height: 1),
                    _StatusRow(
                      icon: _missions.config.isConfigured
                          ? Icons.qr_code_2_rounded
                          : Icons.qr_code_2_outlined,
                      title: _missions.config.isConfigured
                          ? loc.sleepMissionConfigured(
                              _missions.config.format ??
                                  loc.sleepMissionFormatUnknown,
                            )
                          : loc.sleepMissionNotConfigured,
                      color: _missions.config.isConfigured
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                      subtitle: _missions.config.registeredAt == null
                          ? null
                          : DateFormat.yMd(
                              Localizations.localeOf(context).toLanguageTag(),
                            ).format(_missions.config.registeredAt!.toLocal()),
                    ),
                    _LinkTile(
                      icon: _missions.config.isConfigured
                          ? Icons.swap_horiz_rounded
                          : Icons.camera_alt_outlined,
                      title: _missions.config.isConfigured
                          ? loc.sleepMissionReplace
                          : loc.sleepMissionScan,
                      onTap: _busy ? null : _scan,
                    ),
                    if (_missions.config.isConfigured)
                      _LinkTile(
                        icon: Icons.delete_outline_rounded,
                        title: loc.sleepMissionRemove,
                        destructive: true,
                        onTap: _busy ? null : _remove,
                      ),
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        letterSpacing: 1.1,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Column(children: children),
  );
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.title,
    required this.color,
    this.subtitle,
  });
  final IconData icon;
  final String title;
  final Color color;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: color),
    title: Text(title),
    subtitle: subtitle == null ? null : Text(subtitle!),
  );
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.destructive = false,
    this.subtitle,
  });
  final IconData icon;
  final String title;
  final VoidCallback? onTap;
  final bool destructive;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? Theme.of(context).colorScheme.error : null;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title, style: color == null ? null : TextStyle(color: color)),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}
