import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/medication.dart';
import 'package:workout_notes/services/medication_reminder_service.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Escalation delays offered in the editor, in minutes.
const medicationEscalationChoices = [5, 10, 15, 20, 30, 45, 60, 90, 120];

String formatEscalation(int minutes) {
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '$hours h' : '$hours h $rest min';
}

List<String> _weekdayNames(AppLocalizations loc) => [
  loc.alarmWeekMon,
  loc.alarmWeekTue,
  loc.alarmWeekWed,
  loc.alarmWeekThu,
  loc.alarmWeekFri,
  loc.alarmWeekSat,
  loc.alarmWeekSun,
];

/// "Medications" tab of the alarms screen: today's doses (confirm from the
/// app too) and the list of medications with their reminder settings.
class MedicationRemindersTab extends StatefulWidget {
  const MedicationRemindersTab({super.key});

  @override
  State<MedicationRemindersTab> createState() => _MedicationRemindersTabState();
}

class _MedicationRemindersTabState extends State<MedicationRemindersTab> {
  final _service = MedicationReminderService.instance;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _service.addListener(_changed);
    _load();
  }

  @override
  void dispose() {
    _service.removeListener(_changed);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      await _service.reconcile();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _answer(
    MedicationDoseItem item,
    MedicationDoseStatus status,
  ) async {
    setState(() => _busy = true);
    try {
      await _service.answer(item, status);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _undo(MedicationDoseItem item) async {
    setState(() => _busy = true);
    try {
      await _service.undo(item);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggle(Medication medication, bool enabled) async {
    final loc = AppLocalizations.of(context)!;
    setState(() => _busy = true);
    try {
      if (enabled && !await _service.preparePermissions()) {
        _message(loc.alarmPermissionRequired);
        return;
      }
      await _service.setEnabled(medication, enabled);
    } catch (_) {
      _message(loc.medicationSaveError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(Medication medication) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final loc = AppLocalizations.of(context)!;
        return AlertDialog(
          title: Text(loc.medicationDeleteTitle),
          content: Text(loc.medicationDeleteBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(loc.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(loc.medicationDelete),
            ),
          ],
        );
      },
    );
    if (confirmed == true) await _service.delete(medication);
  }

  Future<void> _edit(Medication medication) => Navigator.push<bool>(
    context,
    MaterialPageRoute(
      builder: (_) => MedicationEditorScreen(medication: medication),
    ),
  );

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    if (_loading) return const Center(child: CircularProgressIndicator());
    final medications = _service.medications;
    if (medications.isEmpty) return const _EmptyMedications();
    final today = _service.todayItems();
    final taken = today
        .where((item) => item.state == MedicationDoseState.taken)
        .length;

    return RefreshIndicator(
      onRefresh: _service.reconcile,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
        children: [
          AppSectionHeader(
            loc.medicationToday,
            trailing: today.isEmpty
                ? null
                : Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(
                      loc.medicationTodayProgress(taken, today.length),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
          ),
          if (today.isEmpty)
            AppSectionCard(
              child: Text(
                loc.medicationNoDosesToday,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            AppSectionCard(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              child: AppDividedList(
                children: [
                  for (final item in today)
                    _DoseRow(
                      key: Key('medication-dose-${item.slotId}'),
                      item: item,
                      busy: _busy,
                      onTake: () => _answer(item, MedicationDoseStatus.taken),
                      onSkip: () => _answer(item, MedicationDoseStatus.skipped),
                      onUndo: () => _undo(item),
                    ),
                ],
              ),
            ),
          AppSectionHeader(loc.medicationList),
          for (final medication in medications) ...[
            _MedicationCard(
              medication: medication,
              busy: _busy,
              onTap: () => _edit(medication),
              onToggle: (enabled) => _toggle(medication, enabled),
              onDelete: () => _delete(medication),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _EmptyMedications extends StatelessWidget {
  const _EmptyMedications();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.medication_outlined,
              size: 56,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(loc.medicationEmptyTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(loc.medicationEmptyBody, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// One of today's doses: time, medication, state and the confirm actions.
class _DoseRow extends StatelessWidget {
  const _DoseRow({
    super.key,
    required this.item,
    required this.busy,
    required this.onTake,
    required this.onSkip,
    required this.onUndo,
  });

  final MedicationDoseItem item;
  final bool busy;
  final VoidCallback onTake;
  final VoidCallback onSkip;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final (stateLabel, stateColor) = switch (item.state) {
      MedicationDoseState.taken => (
        loc.medicationStateTakenAt(
          DateFormat.Hm().format(item.record!.recordedAt),
        ),
        colors.primary,
      ),
      MedicationDoseState.skipped => (
        loc.medicationStateSkipped,
        colors.onSurfaceVariant,
      ),
      MedicationDoseState.upcoming => (
        loc.medicationStateUpcoming,
        colors.onSurfaceVariant,
      ),
      MedicationDoseState.awaiting => (
        loc.medicationStateAwaiting,
        colors.tertiary,
      ),
      MedicationDoseState.ringing => (loc.medicationStateRinging, colors.error),
      MedicationDoseState.overdue => (
        loc.medicationStateOverdue,
        colors.tertiary,
      ),
    };
    final dosage = item.medication.dosage;
    final done = item.isAnswered;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 56,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: (done ? colors.primary : stateColor).withAlpha(28),
              borderRadius: BorderRadius.circular(AppUi.tileRadius),
            ),
            child: Column(
              children: [
                Icon(
                  item.state == MedicationDoseState.taken
                      ? Icons.check_circle_rounded
                      : item.state == MedicationDoseState.ringing
                      ? Icons.alarm_rounded
                      : Icons.medication_rounded,
                  size: 18,
                  color: done ? colors.primary : stateColor,
                ),
                const SizedBox(height: 2),
                Text(
                  item.time.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontFeatures: AppUi.tabular,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.medication.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    decoration: item.state == MedicationDoseState.skipped
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                Text(
                  [?dosage, stateLabel].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: dosage == null
                        ? stateColor
                        : colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (done)
            TextButton(
              onPressed: busy ? null : onUndo,
              child: Text(loc.medicationUndo),
            )
          else ...[
            FilledButton.tonal(
              onPressed: busy ? null : onTake,
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              child: Text(loc.medicationTake),
            ),
            PopupMenuButton<String>(
              enabled: !busy,
              onSelected: (_) => onSkip(),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'skip', child: Text(loc.medicationSkip)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MedicationCard extends StatelessWidget {
  const _MedicationCard({
    required this.medication,
    required this.busy,
    required this.onTap,
    required this.onToggle,
    required this.onDelete,
  });

  final Medication medication;
  final bool busy;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final active = medication.enabled;
    final days = medication.everyDay
        ? loc.alarmEveryDay
        : medication.weekdays.map((d) => _weekdayNames(loc)[d - 1]).join(', ');

    return AppSectionCard(
      onTap: busy ? null : onTap,
      padding: const EdgeInsets.fromLTRB(16, 14, 4, 14),
      child: Opacity(
        opacity: active ? 1 : 0.55,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppIconBadge(
              Icons.medication_rounded,
              color: active ? colors.primary : colors.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    medication.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (medication.dosage != null)
                    Text(
                      medication.dosage!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final time in medication.times)
                        AppPill(
                          icon: Icons.schedule_rounded,
                          label: time.label,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$days · ${loc.medicationEscalationChip(formatEscalation(medication.escalationMinutes))}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              children: [
                Switch(value: active, onChanged: busy ? null : onToggle),
                PopupMenuButton<String>(
                  enabled: !busy,
                  onSelected: (_) => onDelete(),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(loc.medicationDelete),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Create or edit a medication: name, dose, times, days and the delay before
/// the sound alarm.
class MedicationEditorScreen extends StatefulWidget {
  const MedicationEditorScreen({super.key, this.medication});

  final Medication? medication;

  @override
  State<MedicationEditorScreen> createState() => _MedicationEditorScreenState();
}

class _MedicationEditorScreenState extends State<MedicationEditorScreen> {
  final _service = MedicationReminderService.instance;
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _dosage;
  late final TextEditingController _notes;
  late List<MedicationTime> _times;
  late Set<int> _days;
  late int _escalation;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final medication = widget.medication;
    _name = TextEditingController(text: medication?.name ?? '');
    _dosage = TextEditingController(text: medication?.dosage ?? '');
    _notes = TextEditingController(text: medication?.notes ?? '');
    _times = [...?medication?.times];
    if (_times.isEmpty) _times = [const MedicationTime(8, 0)];
    _days = {...?medication?.weekdays};
    _escalation =
        medication?.escalationMinutes ?? Medication.defaultEscalationMinutes;
    if (!medicationEscalationChoices.contains(_escalation)) {
      _escalation = Medication.defaultEscalationMinutes;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _dosage.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _addTime() async {
    final loc = AppLocalizations.of(context)!;
    final last = _times.isEmpty ? const MedicationTime(8, 0) : _times.last;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: (last.hour + 12) % 24, minute: last.minute),
    );
    if (picked == null || !mounted) return;
    final time = MedicationTime(picked.hour, picked.minute);
    if (_times.contains(time)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.medicationTimeExists)));
      return;
    }
    setState(() => _times = [..._times, time]..sort());
  }

  Future<void> _changeTime(MedicationTime current) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
    );
    if (picked == null || !mounted) return;
    final time = MedicationTime(picked.hour, picked.minute);
    if (time != current && _times.contains(time)) return;
    setState(() {
      _times = [for (final value in _times) value == current ? time : value]
        ..sort();
    });
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    final loc = AppLocalizations.of(context)!;
    setState(() => _saving = true);
    try {
      if (!await _service.preparePermissions()) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(loc.alarmPermissionRequired)));
        }
        return;
      }
      final medication = widget.medication;
      if (medication == null) {
        await _service.create(
          name: _name.text,
          dosage: _dosage.text,
          notes: _notes.text,
          times: _times,
          weekdays: _days.toList(),
          escalationMinutes: _escalation,
        );
      } else {
        final dosage = _dosage.text.trim();
        final notes = _notes.text.trim();
        await _service.save(
          medication.copyWith(
            name: _name.text.trim(),
            dosage: dosage,
            clearDosage: dosage.isEmpty,
            notes: notes,
            clearNotes: notes.isEmpty,
            times: _times,
            weekdays: _days.toList()..sort(),
            escalationMinutes: _escalation,
          ),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(loc.medicationSaveError)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final names = _weekdayNames(loc);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.medication == null ? loc.medicationNew : loc.medicationEdit,
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(loc.medicationSave),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: loc.medicationName,
                hintText: loc.medicationNameHint,
                prefixIcon: const Icon(Icons.medication_rounded),
              ),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? loc.medicationNameRequired
                  : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _dosage,
              decoration: InputDecoration(
                labelText: loc.medicationDosage,
                hintText: loc.medicationDosageHint,
                prefixIcon: const Icon(Icons.science_outlined),
              ),
            ),
            AppSectionHeader(loc.medicationTimes),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final time in _times)
                  InputChip(
                    avatar: const Icon(Icons.schedule_rounded, size: 18),
                    label: Text(
                      time.label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontFeatures: AppUi.tabular,
                      ),
                    ),
                    onPressed: () => _changeTime(time),
                    onDeleted: _times.length > 1
                        ? () =>
                              setState(() => _times = [..._times]..remove(time))
                        : null,
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add_rounded, size: 18),
                  label: Text(loc.medicationAddTime),
                  onPressed: _addTime,
                ),
              ],
            ),
            AppSectionHeader(loc.medicationDays),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(7, (index) {
                final day = index + 1;
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
              loc.medicationDaysHelp,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            AppSectionHeader(loc.medicationEscalation),
            DropdownButtonFormField<int>(
              initialValue: _escalation,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.alarm_rounded),
              ),
              items: [
                for (final minutes in medicationEscalationChoices)
                  DropdownMenuItem(
                    value: minutes,
                    child: Text(formatEscalation(minutes)),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _escalation = value);
              },
            ),
            const SizedBox(height: 8),
            Text(
              loc.medicationEscalationHelp,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _notes,
              minLines: 1,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: loc.medicationNotes,
                prefixIcon: const Icon(Icons.notes_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
