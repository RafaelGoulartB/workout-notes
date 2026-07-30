import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/sleep_entry.dart';
import 'package:workout_notes/repositories/sleep_repository.dart';

Future<void> showSleepEntrySheet(
  BuildContext context, {
  required SleepRepository repository,
  SleepEntry? existing,
  required VoidCallback onSaved,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheetContext) => _SleepEntrySheet(
      repository: repository,
      existing: existing,
      onSaved: onSaved,
    ),
  );
}

class _SleepEntrySheet extends StatefulWidget {
  final SleepRepository repository;
  final SleepEntry? existing;
  final VoidCallback onSaved;

  const _SleepEntrySheet({
    required this.repository,
    required this.existing,
    required this.onSaved,
  });

  @override
  State<_SleepEntrySheet> createState() => _SleepEntrySheetState();
}

class _SleepEntrySheetState extends State<_SleepEntrySheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _hoursController;
  late final TextEditingController _minutesController;
  late final TextEditingController _actualHoursController;
  late final TextEditingController _actualMinutesController;
  late final TextEditingController _commentController;

  late DateTime _date;
  TimeOfDay? _bedtime;
  TimeOfDay? _wakeTime;
  bool _isSaving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final entry = widget.existing;
    _date = entry?.date ?? DateTime.now();
    _hoursController = TextEditingController(
      text: entry == null ? '' : '${entry.sleepMinutes ~/ 60}',
    );
    _minutesController = TextEditingController(
      text: entry == null ? '' : '${entry.sleepMinutes % 60}',
    );
    _actualHoursController = TextEditingController(
      text: entry?.actualSleepMinutes == null
          ? ''
          : '${entry!.actualSleepMinutes! ~/ 60}',
    );
    _actualMinutesController = TextEditingController(
      text: entry?.actualSleepMinutes == null
          ? ''
          : '${entry!.actualSleepMinutes! % 60}',
    );
    _commentController = TextEditingController(text: entry?.comment ?? '');
    _bedtime = _timeFromMinutes(entry?.bedtimeMinutes);
    _wakeTime = _timeFromMinutes(entry?.wakeTimeMinutes);
  }

  @override
  void dispose() {
    _hoursController.dispose();
    _minutesController.dispose();
    _actualHoursController.dispose();
    _actualMinutesController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isEditing ? loc.sleepEditTitle : loc.sleepAddTitle,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 18),
              _DateField(
                date: _date,
                label: loc.sleepDate,
                onChanged: (value) => setState(() => _date = value),
              ),
              const SizedBox(height: 18),
              Text(
                loc.sleepDuration,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              _DurationFields(
                hoursController: _hoursController,
                minutesController: _minutesController,
                hoursLabel: loc.sleepHours,
                minutesLabel: loc.sleepMinutes,
              ),
              const SizedBox(height: 18),
              Text(
                '${loc.sleepActualDuration} (${loc.commonOptional})',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                loc.sleepActualDurationHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              _DurationFields(
                hoursController: _actualHoursController,
                minutesController: _actualMinutesController,
                hoursLabel: loc.sleepHours,
                minutesLabel: loc.sleepMinutes,
                optional: true,
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _TimeField(
                      label: loc.sleepBedtime,
                      value: _bedtime,
                      onChanged: (value) => setState(() => _bedtime = value),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _TimeField(
                      label: loc.sleepWakeTime,
                      value: _wakeTime,
                      onChanged: (value) => setState(() => _wakeTime = value),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _commentController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: loc.sleepComment,
                  alignLabelWithHint: true,
                  prefixIcon: const Icon(Icons.notes_outlined),
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: _isSaving ? null : _save,
                  icon: _isSaving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text(loc.sleepSave),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final loc = AppLocalizations.of(context)!;
    final sleepMinutes = _parseDuration(
      _hoursController.text,
      _minutesController.text,
    );
    final actualTextIsEmpty =
        _actualHoursController.text.trim().isEmpty &&
        _actualMinutesController.text.trim().isEmpty;
    final actualMinutes = actualTextIsEmpty
        ? null
        : _parseDuration(
            _actualHoursController.text,
            _actualMinutesController.text,
          );

    if (sleepMinutes == null || sleepMinutes <= 0 || sleepMinutes > 1440) {
      _showError(loc.sleepInvalidDuration);
      return;
    }
    if (!actualTextIsEmpty &&
        (actualMinutes == null ||
            actualMinutes <= 0 ||
            actualMinutes > sleepMinutes)) {
      _showError(loc.sleepInvalidActual);
      return;
    }

    setState(() => _isSaving = true);
    try {
      await widget.repository.save(
        SleepEntry(
          id: widget.existing?.id ?? const Uuid().v4(),
          date: DateTime(_date.year, _date.month, _date.day),
          sleepMinutes: sleepMinutes,
          actualSleepMinutes: actualMinutes,
          bedtimeMinutes: _minutesFromTime(_bedtime),
          wakeTimeMinutes: _minutesFromTime(_wakeTime),
          comment: _commentController.text.trim().isEmpty
              ? null
              : _commentController.text.trim(),
          source: widget.existing == null
              ? 'manual'
              : widget.existing!.source == 'manual'
              ? 'manual'
              : 'hybrid',
          timeInBedMinutes: widget.existing?.timeInBedMinutes,
          estimatedSleepMinutes: widget.existing?.estimatedSleepMinutes,
          createdAt: widget.existing?.createdAt ?? DateTime.now(),
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onSaved();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.sleepSaved)));
    } catch (error) {
      if (mounted) _showError(error.toString());
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  static int? _parseDuration(String hours, String minutes) {
    final h = int.tryParse(hours.trim().isEmpty ? '0' : hours.trim());
    final m = int.tryParse(minutes.trim().isEmpty ? '0' : minutes.trim());
    if (h == null || m == null || h < 0 || m < 0 || m > 59) return null;
    return h * 60 + m;
  }

  static TimeOfDay? _timeFromMinutes(int? minutes) {
    if (minutes == null) return null;
    return TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
  }

  static int? _minutesFromTime(TimeOfDay? value) =>
      value == null ? null : value.hour * 60 + value.minute;
}

class _DurationFields extends StatelessWidget {
  final TextEditingController hoursController;
  final TextEditingController minutesController;
  final String hoursLabel;
  final String minutesLabel;
  final bool optional;

  const _DurationFields({
    required this.hoursController,
    required this.minutesController,
    required this.hoursLabel,
    required this.minutesLabel,
    this.optional = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: hoursController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: hoursLabel,
              hintText: optional ? '—' : '0',
              suffixText: 'h',
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextFormField(
            controller: minutesController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: minutesLabel,
              hintText: optional ? '—' : '0',
              suffixText: 'min',
            ),
          ),
        ),
      ],
    );
  }
}

class _DateField extends StatelessWidget {
  final DateTime date;
  final String label;
  final ValueChanged<DateTime> onChanged;

  const _DateField({
    required this.date,
    required this.label,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime(2020),
          lastDate: DateTime.now(),
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.calendar_today_outlined),
        ),
        child: Text(
          DateFormat.yMMMMd(Intl.defaultLocale).format(date),
          style: theme.textTheme.bodyLarge,
        ),
      ),
    );
  }
}

class _TimeField extends StatelessWidget {
  final String label;
  final TimeOfDay? value;
  final ValueChanged<TimeOfDay?> onChanged;

  const _TimeField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: value ?? TimeOfDay.now(),
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.schedule_outlined),
        ),
        child: Text(
          value?.format(context) ??
              AppLocalizations.of(context)!.sleepNotInformed,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
