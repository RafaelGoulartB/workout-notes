import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';

import '../../models/traditional_alarm.dart';
import '../../services/traditional_alarm_service.dart';

class TraditionalAlarmsScreen extends StatefulWidget {
  const TraditionalAlarmsScreen({super.key});

  @override
  State<TraditionalAlarmsScreen> createState() =>
      _TraditionalAlarmsScreenState();
}

class _TraditionalAlarmsScreenState extends State<TraditionalAlarmsScreen>
    with WidgetsBindingObserver {
  final _service = TraditionalAlarmService.instance;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _service.addListener(_changed);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _service.removeListener(_changed);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _service.reconcile();
  }

  Future<void> _load() async {
    await _service.initialize();
    if (mounted) setState(() => _loading = false);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _edit([TraditionalAlarm? alarm]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => _AlarmEditorScreen(alarm: alarm)),
    );
    if (saved == true) await _service.refresh();
  }

  Future<void> _toggle(TraditionalAlarm alarm, bool enabled) async {
    setState(() => _busy = true);
    try {
      if (enabled && !await _service.preparePermissions()) {
        if (mounted) {
          _message(AppLocalizations.of(context)!.alarmPermissionRequired);
        }
        return;
      }
      await _service.setEnabled(alarm, enabled);
    } catch (_) {
      if (mounted) _message(AppLocalizations.of(context)!.alarmUpdateError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(TraditionalAlarm alarm) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final loc = AppLocalizations.of(context)!;
        return AlertDialog(
          title: Text(loc.alarmDeleteTitle),
          content: Text(loc.alarmDeleteBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(loc.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(loc.alarmDelete),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    await _service.delete(alarm);
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(loc.alarmTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : () => _edit(),
        icon: const Icon(Icons.add_alarm_rounded),
        label: Text(loc.alarmNew),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _service.alarms.isEmpty
          ? const _EmptyAlarms()
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: _service.alarms.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, index) {
                final alarm = _service.alarms[index];
                return _AlarmCard(
                  alarm: alarm,
                  disabled: _busy,
                  onTap: () => _edit(alarm),
                  onToggle: (enabled) => _toggle(alarm, enabled),
                  onDelete: () => _delete(alarm),
                );
              },
            ),
    );
  }
}

class _EmptyAlarms extends StatelessWidget {
  const _EmptyAlarms();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.alarm_off_rounded,
            size: 56,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context)!.alarmEmptyTitle,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context)!.alarmEmptyBody,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

class _AlarmCard extends StatelessWidget {
  const _AlarmCard({
    required this.alarm,
    required this.disabled,
    required this.onTap,
    required this.onToggle,
    required this.onDelete,
  });
  final TraditionalAlarm alarm;
  final bool disabled;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final color = alarm.enabled
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _time(context),
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _days(loc),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (alarm.enabled && alarm.nextTriggerAt != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        loc.alarmNext(
                          DateFormat(
                            'EEE, d MMM • HH:mm',
                            Intl.defaultLocale,
                          ).format(alarm.nextTriggerAt!.toLocal()),
                        ),
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ],
                    if (alarm.requiresMission || alarm.snoozeEnabled) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        children: [
                          if (alarm.requiresMission)
                            Chip(
                              avatar: Icon(
                                Icons.qr_code_scanner_rounded,
                                size: 18,
                              ),
                              label: Text(loc.alarmMission),
                            ),
                          if (alarm.snoozeEnabled)
                            Chip(
                              avatar: const Icon(
                                Icons.snooze_rounded,
                                size: 18,
                              ),
                              label: Text(
                                loc.alarmSnoozeChip(
                                  alarm.snoozeMinutes,
                                  alarm.maxSnoozes,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Column(
                children: [
                  Switch(
                    value: alarm.enabled,
                    onChanged: disabled ? null : onToggle,
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'delete') onDelete();
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(loc.alarmDelete),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _time(BuildContext context) =>
      MaterialLocalizations.of(context).formatTimeOfDay(
        TimeOfDay(hour: alarm.hour, minute: alarm.minute),
        alwaysUse24HourFormat: true,
      );
  String _days(AppLocalizations loc) {
    if (alarm.weekdays.isEmpty) return loc.alarmOneShot;
    if (alarm.weekdays.length == 7) return loc.alarmEveryDay;
    final names = [
      loc.alarmWeekMon,
      loc.alarmWeekTue,
      loc.alarmWeekWed,
      loc.alarmWeekThu,
      loc.alarmWeekFri,
      loc.alarmWeekSat,
      loc.alarmWeekSun,
    ];
    return alarm.weekdays.map((day) => names[day - 1]).join(', ');
  }
}

class _AlarmEditorScreen extends StatefulWidget {
  const _AlarmEditorScreen({this.alarm});
  final TraditionalAlarm? alarm;

  @override
  State<_AlarmEditorScreen> createState() => _AlarmEditorScreenState();
}

class _AlarmEditorScreenState extends State<_AlarmEditorScreen> {
  final _service = TraditionalAlarmService.instance;
  late TimeOfDay _time;
  late Set<int> _days;
  late bool _snoozeEnabled;
  late int _snoozeMinutes;
  late int _maxSnoozes;
  late bool _requiresMission;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final alarm = widget.alarm;
    _time = TimeOfDay(hour: alarm?.hour ?? 7, minute: alarm?.minute ?? 0);
    _days = {...?alarm?.weekdays};
    _snoozeEnabled = alarm?.snoozeEnabled ?? true;
    _snoozeMinutes = alarm?.snoozeMinutes ?? 5;
    _maxSnoozes =
        alarm?.maxSnoozes ?? TraditionalAlarmService.defaultMaxSnoozes;
    _requiresMission = alarm?.requiresMission ?? false;
    if (alarm == null) _loadGlobalDefault();
  }

  Future<void> _loadGlobalDefault() async {
    final maxSnoozes = await _service.getGlobalMaxSnoozes();
    final snoozeEnabled = await _service.getGlobalSnoozeEnabled();
    if (mounted) {
      setState(() {
        _maxSnoozes = maxSnoozes;
        _snoozeEnabled = snoozeEnabled;
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_requiresMission && !await _service.hasConfiguredMission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.alarmMissionNotConfigured,
            ),
          ),
        );
      }
      return;
    }
    setState(() => _saving = true);
    try {
      if (!await _service.preparePermissions()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context)!.alarmPermissionRequired,
              ),
            ),
          );
        }
        return;
      }
      if (widget.alarm == null) {
        await _service.create(
          hour: _time.hour,
          minute: _time.minute,
          weekdays: _days.toList(),
          snoozeEnabled: _snoozeEnabled,
          snoozeMinutes: _snoozeMinutes,
          maxSnoozes: _maxSnoozes,
          requiresMission: _requiresMission,
        );
      } else {
        await _service.save(
          widget.alarm!.copyWith(
            hour: _time.hour,
            minute: _time.minute,
            weekdays: _days.toList(),
            snoozeEnabled: _snoozeEnabled,
            snoozeMinutes: _snoozeMinutes,
            maxSnoozes: _maxSnoozes,
            requiresMission: _requiresMission,
          ),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.alarmSaveError)),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.alarm == null ? loc.alarmNew : loc.alarmEdit),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? loc.alarmSaving : loc.alarmSave),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          Center(
            child: TextButton(
              onPressed: _pickTime,
              child: Text(
                MaterialLocalizations.of(
                  context,
                ).formatTimeOfDay(_time, alwaysUse24HourFormat: true),
                style: Theme.of(
                  context,
                ).textTheme.displayLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(loc.alarmRepeat, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(7, (index) {
              final day = index + 1;
              final names = [
                loc.alarmWeekMon,
                loc.alarmWeekTue,
                loc.alarmWeekWed,
                loc.alarmWeekThu,
                loc.alarmWeekFri,
                loc.alarmWeekSat,
                loc.alarmWeekSun,
              ];
              return FilterChip(
                label: Text(names[index]),
                selected: _days.contains(day),
                onSelected: (selected) => setState(() {
                  selected ? _days.add(day) : _days.remove(day);
                }),
              );
            }),
          ),
          const SizedBox(height: 8),
          Text(
            _days.isEmpty ? loc.alarmOneShotHelp : loc.alarmDaysHelp,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 28),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _snoozeEnabled,
            onChanged: (value) => setState(() => _snoozeEnabled = value),
            title: Text(loc.alarmSnoozeEnable),
            subtitle: Text(loc.alarmSnoozeEnableBody),
          ),
          if (_snoozeEnabled)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(loc.alarmSnoozeInterval),
              trailing: DropdownButton<int>(
                value: _snoozeMinutes,
                items: const [5, 10, 15, 20, 30]
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text('$value min'),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _snoozeMinutes = value);
                },
              ),
            ),
          if (_snoozeEnabled)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(loc.alarmMaxSnoozes),
              trailing: DropdownButton<int>(
                value: _maxSnoozes,
                items: List.generate(
                  11,
                  (value) => DropdownMenuItem(
                    value: value,
                    child: Text(
                      value == 0
                          ? loc.alarmNoSnoozes
                          : loc.alarmSnoozeTimes(value),
                    ),
                  ),
                ),
                onChanged: (value) {
                  if (value != null) setState(() => _maxSnoozes = value);
                },
              ),
            ),
          const Divider(height: 36),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _requiresMission,
            onChanged: (value) => setState(() => _requiresMission = value),
            title: Text(loc.alarmRequireMission),
            subtitle: Text(loc.alarmRequireMissionBody),
          ),
        ],
      ),
    );
  }

  Future<void> _pickTime() async {
    final result = await showTimePicker(context: context, initialTime: _time);
    if (result != null && mounted) setState(() => _time = result);
  }
}
