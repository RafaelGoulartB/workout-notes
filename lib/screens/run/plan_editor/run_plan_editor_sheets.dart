import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/models/run_voice_settings.dart';
import 'package:workout_notes/models/run_workout_step.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/widgets/run/run_plan_ui.dart';

/// Distance stays plain metres; time also accepts `2:00`.
int? runPlanReadMetric(String raw, RunIntervalMetric metric) {
  if (metric == RunIntervalMetric.time) return RunPlanUi.parseSeconds(raw);
  final metres = int.tryParse(raw.trim());
  return metres == null || metres <= 0 ? null : metres;
}

// ===================== DRAFTS =====================

/// What the session sheet hands back on save.
class RunPlanSessionDraft {
  final String? name;
  final RunWorkoutKind kind;
  final int? dayOfWeek;
  final String notes;
  final double? targetDistanceMeters;
  final int? targetDurationSeconds;
  final double? targetPaceSecPerKm;

  const RunPlanSessionDraft({
    required this.name,
    required this.kind,
    required this.dayOfWeek,
    required this.notes,
    required this.targetDistanceMeters,
    required this.targetDurationSeconds,
    required this.targetPaceSecPerKm,
  });
}

/// What the step sheet hands back on save.
class RunPlanStepDraft {
  final RunStepRole role;
  final RunIntervalMetric metric;
  final int value;
  final int repeatCount;
  final double? paceMin;
  final double? paceMax;

  const RunPlanStepDraft({
    required this.role,
    required this.metric,
    required this.value,
    required this.repeatCount,
    this.paceMin,
    this.paceMax,
  });
}

/// What the interval-block sheet hands back on save: an effort leg, an
/// optional recovery leg and how many times they repeat.
class RunPlanIntervalDraft {
  final int repeats;
  final RunIntervalMetric effortMetric;
  final int effort;
  final RunIntervalMetric recoveryMetric;
  final int? recovery;
  final double? pace;

  const RunPlanIntervalDraft({
    required this.repeats,
    required this.effortMetric,
    required this.effort,
    required this.recoveryMetric,
    required this.recovery,
    required this.pace,
  });
}

// ===================== ENTRY POINTS =====================

Future<RunPlanSessionDraft?> showRunPlanSessionSheet(
  BuildContext context,
  RunPlanWorkout workout,
) => showModalBottomSheet<RunPlanSessionDraft>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _SessionSheet(workout: workout),
);

Future<RunPlanStepDraft?> showRunPlanStepSheet(
  BuildContext context, {
  RunWorkoutStep? step,
}) => showModalBottomSheet<RunPlanStepDraft>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _StepSheet(step: step),
);

Future<RunPlanIntervalDraft?> showRunPlanIntervalBlockSheet(
  BuildContext context,
) => showModalBottomSheet<RunPlanIntervalDraft>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => const _IntervalBlockSheet(),
);

// ===================== SHARED FRAME =====================

/// Keyboard-aware scrollable body with a title and a save button.
class _SheetFrame extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final VoidCallback onSave;

  const _SheetFrame({
    required this.title,
    required this.children,
    required this.onSave,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 16),
            ...children,
            const SizedBox(height: 16),
            FilledButton(onPressed: onSave, child: Text(loc.commonSave)),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ===================== SESSION =====================

class _SessionSheet extends StatefulWidget {
  final RunPlanWorkout workout;

  const _SessionSheet({required this.workout});

  @override
  State<_SessionSheet> createState() => _SessionSheetState();
}

class _SessionSheetState extends State<_SessionSheet> {
  late final TextEditingController _name;
  late final TextEditingController _notes;
  late final TextEditingController _distance;
  late final TextEditingController _duration;
  late final TextEditingController _pace;
  late RunWorkoutKind _kind;
  late int? _dayOfWeek;

  @override
  void initState() {
    super.initState();
    final workout = widget.workout;
    _name = TextEditingController(text: workout.name);
    _notes = TextEditingController(text: workout.notes ?? '');
    _distance = TextEditingController(
      text: workout.targetDistanceMeters == null
          ? ''
          : RunFormatters.decimal(workout.targetDistanceMeters! / 1000),
    );
    _duration = TextEditingController(
      text: workout.targetDurationSeconds == null
          ? ''
          : (workout.targetDurationSeconds! ~/ 60).toString(),
    );
    _pace = TextEditingController(
      text: workout.targetPaceSecPerKm == null
          ? ''
          : RunPlanUi.paceLabel(workout.targetPaceSecPerKm),
    );
    _kind = workout.kind;
    _dayOfWeek = workout.dayOfWeek;
  }

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    _distance.dispose();
    _duration.dispose();
    _pace.dispose();
    super.dispose();
  }

  void _save() {
    final km = double.tryParse(_distance.text.trim().replaceAll(',', '.'));
    final minutes = int.tryParse(_duration.text.trim());
    final name = _name.text.trim();
    Navigator.pop(
      context,
      RunPlanSessionDraft(
        name: name.isEmpty ? null : name,
        kind: _kind,
        dayOfWeek: _dayOfWeek,
        notes: _notes.text.trim(),
        targetDistanceMeters: km == null || km <= 0 ? null : km * 1000,
        targetDurationSeconds: minutes == null || minutes <= 0
            ? null
            : minutes * 60,
        targetPaceSecPerKm: RunPlanUi.parsePace(_pace.text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return _SheetFrame(
      title: loc.runWorkoutEditTitle,
      onSave: _save,
      children: [
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: loc.runWorkoutName,
            hintText: loc.runWorkoutNameHint,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<RunWorkoutKind>(
          initialValue: _kind,
          decoration: InputDecoration(
            labelText: loc.runWorkoutKindLabel,
            border: const OutlineInputBorder(),
          ),
          items: [
            for (final value in RunWorkoutKind.values)
              DropdownMenuItem(
                value: value,
                child: Row(
                  children: [
                    Icon(
                      RunPlanUi.kindIcon(value),
                      size: 16,
                      color: RunPlanUi.kindColor(scheme, value),
                    ),
                    const SizedBox(width: 8),
                    Text(RunPlanUi.kindLabel(loc, value)),
                  ],
                ),
              ),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _kind = value);
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int?>(
          initialValue: _dayOfWeek,
          decoration: InputDecoration(
            labelText: loc.runWorkoutDayOfWeek,
            border: const OutlineInputBorder(),
          ),
          items: [
            DropdownMenuItem(value: null, child: Text(loc.runWorkoutDayAny)),
            for (var day = 1; day <= 7; day++)
              DropdownMenuItem(
                value: day,
                child: Text(RunPlanUi.weekdayLabel(loc, day)),
              ),
          ],
          onChanged: (value) => setState(() => _dayOfWeek = value),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _distance,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: loc.runWorkoutTargetDistance,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _duration,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: loc.runWorkoutTargetDuration,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pace,
          decoration: InputDecoration(
            labelText: loc.runWorkoutTargetPace,
            hintText: '4:35',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _notes,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: loc.runPlanNotes,
            border: const OutlineInputBorder(),
          ),
        ),
      ],
    );
  }
}

// ===================== STEP =====================

class _StepSheet extends StatefulWidget {
  final RunWorkoutStep? step;

  const _StepSheet({this.step});

  @override
  State<_StepSheet> createState() => _StepSheetState();
}

class _StepSheetState extends State<_StepSheet> {
  late final TextEditingController _value;
  late final TextEditingController _repeats;
  late final TextEditingController _paceFrom;
  late final TextEditingController _paceTo;
  late RunStepRole _role;
  late RunIntervalMetric _metric;

  @override
  void initState() {
    super.initState();
    final step = widget.step;
    _value = TextEditingController(
      text: step == null
          ? ''
          : step.metric == RunIntervalMetric.time
          ? RunPlanUi.secondsInput(step.value)
          : step.value.toString(),
    );
    _repeats = TextEditingController(text: (step?.repeatCount ?? 1).toString());
    _paceFrom = TextEditingController(
      text: step?.targetPaceMinSecPerKm == null
          ? ''
          : RunPlanUi.paceLabel(step!.targetPaceMinSecPerKm),
    );
    _paceTo = TextEditingController(
      text: step?.targetPaceMaxSecPerKm == null
          ? ''
          : RunPlanUi.paceLabel(step!.targetPaceMaxSecPerKm),
    );
    _role = step?.role ?? RunStepRole.work;
    _metric = step?.metric ?? RunIntervalMetric.distance;
  }

  @override
  void dispose() {
    _value.dispose();
    _repeats.dispose();
    _paceFrom.dispose();
    _paceTo.dispose();
    super.dispose();
  }

  void _save() {
    final value = runPlanReadMetric(_value.text, _metric);
    if (value == null) return;
    Navigator.pop(
      context,
      RunPlanStepDraft(
        role: _role,
        metric: _metric,
        value: value,
        repeatCount: (int.tryParse(_repeats.text.trim()) ?? 1).clamp(1, 99),
        paceMin: RunPlanUi.parsePace(_paceFrom.text),
        paceMax: RunPlanUi.parsePace(_paceTo.text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final step = widget.step;
    return _SheetFrame(
      title: step == null ? loc.runWorkoutAddStep : loc.runWorkoutStepEdit,
      onSave: _save,
      children: [
        // Roles are five short words — chips beat a dropdown here.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final value in RunStepRole.values)
              ChoiceChip(
                selected: _role == value,
                label: Text(RunPlanUi.roleLabel(loc, value)),
                onSelected: (_) => setState(() => _role = value),
              ),
          ],
        ),
        const SizedBox(height: 16),
        _MetricValueRow(
          controller: _value,
          metric: _metric,
          onMetricChanged: (value) => setState(() => _metric = value),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _repeats,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: loc.runWorkoutStepRepeats,
            helperText: step?.repeatGroup == null
                ? null
                : loc.runWorkoutStepRepeatHint,
            helperMaxLines: 2,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          loc.runWorkoutStepPaceRange,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _paceFrom,
                decoration: InputDecoration(
                  labelText: loc.runWorkoutStepPaceFrom,
                  hintText: '3:50',
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _paceTo,
                decoration: InputDecoration(
                  labelText: loc.runWorkoutStepPaceTo,
                  hintText: '4:05',
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ===================== INTERVAL BLOCK =====================

class _IntervalBlockSheet extends StatefulWidget {
  const _IntervalBlockSheet();

  @override
  State<_IntervalBlockSheet> createState() => _IntervalBlockSheetState();
}

class _IntervalBlockSheetState extends State<_IntervalBlockSheet> {
  final _repeats = TextEditingController(text: '6');
  final _effort = TextEditingController(text: '800');
  final _recovery = TextEditingController(text: '2:00');
  final _pace = TextEditingController();
  var _effortMetric = RunIntervalMetric.distance;
  var _recoveryMetric = RunIntervalMetric.time;

  @override
  void dispose() {
    _repeats.dispose();
    _effort.dispose();
    _recovery.dispose();
    _pace.dispose();
    super.dispose();
  }

  void _save() {
    final effort = runPlanReadMetric(_effort.text, _effortMetric);
    // Without an effort leg there is no block to add.
    if (effort == null) {
      Navigator.pop(context);
      return;
    }
    Navigator.pop(
      context,
      RunPlanIntervalDraft(
        repeats: (int.tryParse(_repeats.text.trim()) ?? 1).clamp(1, 99),
        effortMetric: _effortMetric,
        effort: effort,
        recoveryMetric: _recoveryMetric,
        recovery: runPlanReadMetric(_recovery.text, _recoveryMetric),
        pace: RunPlanUi.parsePace(_pace.text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return _SheetFrame(
      title: loc.runWorkoutIntervalBlockTitle,
      subtitle: loc.runWorkoutIntervalBlockHint,
      onSave: _save,
      children: [
        TextField(
          controller: _repeats,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: loc.runWorkoutStepRepeats,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        _MetricValueRow(
          label: loc.runWorkoutStepRoleWork,
          controller: _effort,
          metric: _effortMetric,
          onMetricChanged: (value) => setState(() => _effortMetric = value),
        ),
        const SizedBox(height: 12),
        _MetricValueRow(
          label: loc.runWorkoutStepRoleRecovery,
          controller: _recovery,
          metric: _recoveryMetric,
          onMetricChanged: (value) => setState(() => _recoveryMetric = value),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pace,
          decoration: InputDecoration(
            labelText: loc.runWorkoutStepPaceRange,
            hintText: '3:50',
            border: const OutlineInputBorder(),
          ),
        ),
      ],
    );
  }
}

/// Value field plus a distance/time toggle — the same control the step sheet
/// and the interval-block sheet need.
class _MetricValueRow extends StatelessWidget {
  /// Prefix for the field label ("Tiro", "Recuperação"). Null in the step sheet,
  /// where the role is already picked right above the field.
  final String? label;
  final TextEditingController controller;
  final RunIntervalMetric metric;
  final ValueChanged<RunIntervalMetric> onMetricChanged;

  const _MetricValueRow({
    required this.controller,
    required this.metric,
    required this.onMetricChanged,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final isTime = metric == RunIntervalMetric.time;
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: isTime ? TextInputType.text : TextInputType.number,
            decoration: InputDecoration(
              labelText: [
                if (label != null) label,
                isTime ? loc.runWorkoutStepTime : loc.runWorkoutStepDistance,
              ].join(' · '),
              hintText: isTime ? '2:00' : '800',
              suffixText: isTime ? null : 'm',
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SegmentedButton<RunIntervalMetric>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: RunIntervalMetric.distance,
              icon: const Icon(Icons.straighten, size: 16),
              tooltip: loc.runWorkoutStepMetricDistance,
            ),
            ButtonSegment(
              value: RunIntervalMetric.time,
              icon: const Icon(Icons.timer_outlined, size: 16),
              tooltip: loc.runWorkoutStepMetricTime,
            ),
          ],
          selected: {metric},
          onSelectionChanged: (selection) => onMetricChanged(selection.first),
        ),
      ],
    );
  }
}
