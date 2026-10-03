import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/periodization/phase_editor_controller.dart';
import 'package:workout_notes/periodization/run_plan_week_resolver.dart';
import 'package:workout_notes/utils/app_number_format.dart';
import 'package:workout_notes/widgets/periodization/phase_editor/phase_editor_fields.dart';
import 'package:workout_notes/widgets/periodization/planning_widgets.dart';
import 'package:workout_notes/widgets/run/run_plan_ui.dart';

class PhaseTrainingCard extends StatelessWidget {
  final PhaseEditorController controller;

  const PhaseTrainingCard({super.key, required this.controller});

  Future<void> _pickRoutines(BuildContext context) async {
    final loc = AppLocalizations.of(context)!;
    final selected = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => PhaseRoutinePickerSheet(
        routines: controller.routines,
        dayNames: controller.routineDayNames,
        selected: controller.routineIds,
        title: loc.planningPickRoutine,
      ),
    );
    if (selected != null) controller.setRoutineIds(selected);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final names = controller.routineIds
        .map(controller.routineName)
        .whereType<String>()
        .toList();
    final sequence = controller.strengthSequence;
    return PlanningCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PhasePickerRow(
            key: const Key('phaseRoutinePicker'),
            icon: Icons.repeat_rounded,
            label: loc.planningRoutine,
            value: names.isEmpty ? loc.planningNone : names.join(' + '),
            onTap: () => _pickRoutines(context),
          ),
          if (sequence.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              sequence.join(' → '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            loc.planningStrengthDays,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          WeekdayPicker(
            key: const Key('phaseStrengthDays'),
            selected: controller.strengthDays,
            color: Color(controller.color),
            onChanged: controller.setStrengthDays,
          ),
          const SizedBox(height: 8),
          Text(
            controller.strengthDays.isEmpty
                ? loc.planningStrengthDaysHint
                : loc.planningWorkoutsPerWeek(controller.strengthDays.length),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 4),
              title: Text(
                loc.planningVolumeIntensity,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                _volumeSummary(loc),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              children: [
                PhaseRangeRow(
                  label: loc.planningSetsPerWeek,
                  min: controller.minSets?.toDouble(),
                  max: controller.maxSets?.toDouble(),
                  step: 2,
                  lowest: 0,
                  highest: 60,
                  start: 10,
                  format: (value) => value.round().toString(),
                  onChanged: (min, max) => controller.setTrainingVolume(
                    minSets: min?.round(),
                    maxSets: max?.round(),
                    minRpe: controller.minRpe,
                    maxRpe: controller.maxRpe,
                  ),
                ),
                const SizedBox(height: 8),
                PhaseRangeRow(
                  label: loc.planningRpe,
                  min: controller.minRpe,
                  max: controller.maxRpe,
                  step: 0.5,
                  lowest: 1,
                  highest: 10,
                  start: 7,
                  format: (value) =>
                      AppNumberFormat.decimal(value, value % 1 == 0 ? 0 : 1),
                  onChanged: (min, max) => controller.setTrainingVolume(
                    minSets: controller.minSets,
                    maxSets: controller.maxSets,
                    minRpe: min,
                    maxRpe: max,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _volumeSummary(AppLocalizations loc) {
    final parts = <String>[
      if (controller.minSets != null || controller.maxSets != null)
        '${controller.minSets ?? '—'}–${controller.maxSets ?? '—'} '
            '${loc.planningSetsShort}',
      if (controller.minRpe != null || controller.maxRpe != null)
        'RPE ${controller.minRpe?.toString() ?? '—'}–'
            '${controller.maxRpe?.toString() ?? '—'}',
    ];
    return parts.isEmpty ? loc.planningOptional : parts.join(' · ');
  }
}

/// "min – max" pair of steppers; a value can be cleared by stepping below
/// its lowest bound.
class PhaseRangeRow extends StatelessWidget {
  final String label;
  final double? min;
  final double? max;
  final double step;
  final double lowest;
  final double highest;
  final double start;
  final String Function(double value) format;
  final void Function(double? min, double? max) onChanged;

  const PhaseRangeRow({
    super.key,
    required this.label,
    required this.min,
    required this.max,
    required this.step,
    required this.lowest,
    required this.highest,
    required this.start,
    required this.format,
    required this.onChanged,
  });

  double? _down(double? value) {
    if (value == null) return null;
    final next = value - step;
    return next < lowest ? null : next;
  }

  double _up(double? value, {double? floor}) {
    final next = value == null ? (floor ?? start) : value + step;
    return next > highest ? highest : next;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodySmall),
        const SizedBox(height: 6),
        Row(
          children: [
            PlanningStepper(
              value: min == null ? '—' : format(min!),
              onDecrement: min == null
                  ? null
                  : () => onChanged(_down(min), max),
              onIncrement: () {
                final next = _up(min);
                onChanged(next, max != null && max! < next ? next : max);
              },
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('–'),
            ),
            PlanningStepper(
              value: max == null ? '—' : format(max!),
              onDecrement: max == null
                  ? null
                  : () {
                      final next = _down(max);
                      onChanged(
                        next != null && min != null && min! > next ? next : min,
                        next,
                      );
                    },
              onIncrement: () => onChanged(min, _up(max, floor: min)),
            ),
          ],
        ),
      ],
    );
  }
}

class PhaseRoutinePickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> routines;
  final Map<String, List<String>> dayNames;
  final List<String> selected;
  final String title;

  const PhaseRoutinePickerSheet({
    super.key,
    required this.routines,
    required this.dayNames,
    required this.selected,
    required this.title,
  });

  @override
  State<PhaseRoutinePickerSheet> createState() =>
      _PhaseRoutinePickerSheetState();
}

class _PhaseRoutinePickerSheetState extends State<PhaseRoutinePickerSheet> {
  late final List<String> _selected = [...widget.selected];

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(
                widget.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                loc.planningPickRoutineHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (widget.routines.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  loc.planningNoRoutines,
                  textAlign: TextAlign.center,
                ),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final routine in widget.routines)
                      CheckboxListTile(
                        value: _selected.contains(routine['id']),
                        onChanged: (checked) => setState(() {
                          final id = routine['id'] as String;
                          checked == true
                              ? _selected.add(id)
                              : _selected.remove(id);
                        }),
                        title: Text(routine['name'] as String? ?? ''),
                        subtitle: Text(
                          (widget.dayNames[routine['id']] ?? const []).join(
                            ' · ',
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: FilledButton(
                onPressed: () => Navigator.pop(context, _selected),
                child: Text(loc.planningDone),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PhaseRunningCard extends StatelessWidget {
  final PhaseEditorController controller;

  const PhaseRunningCard({super.key, required this.controller});

  Future<void> _pickPlan(BuildContext context) async {
    final loc = AppLocalizations.of(context)!;
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  loc.planningPickRunPlan,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              RadioGroup<String>(
                groupValue: controller.runPlanId ?? '',
                onChanged: (value) => Navigator.pop(context, value),
                child: Column(
                  children: [
                    RadioListTile<String>(
                      value: '',
                      title: Text(loc.planningNoRunPlan),
                      subtitle: Text(loc.planningNoRunPlanHint),
                    ),
                    for (final plan in controller.runPlans)
                      RadioListTile<String>(
                        value: plan.id,
                        title: Text(plan.name),
                        subtitle: Text(
                          '${RunPlanUi.goalLabel(loc, plan.goalKind)} · '
                          '${loc.planningWeeksShort(plan.weeks)}',
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;
    controller.setRunPlan(picked.isEmpty ? null : picked);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final plan = controller.runPlan;
    return PlanningCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PhasePickerRow(
            key: const Key('phaseRunPlanPicker'),
            icon: Icons.route_outlined,
            label: loc.planningRunPlan,
            value: plan?.name ?? loc.planningNoRunPlan,
            onTap: () => _pickPlan(context),
          ),
          const SizedBox(height: 14),
          if (plan != null) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    loc.planningRunPlanStartWeek,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                PlanningStepper(
                  value: '${controller.runPlanStartWeek + 1}/${plan.weeks}',
                  onDecrement: controller.runPlanStartWeek > 0
                      ? () => controller.setRunPlanStartWeek(
                          controller.runPlanStartWeek - 1,
                        )
                      : null,
                  onIncrement: controller.runPlanStartWeek < plan.weeks - 1
                      ? () => controller.setRunPlanStartWeek(
                          controller.runPlanStartWeek + 1,
                        )
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _coverage(loc, plan.weeks),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: controller.alignRunPlanFinish,
                icon: const Icon(Icons.sports_score_outlined, size: 18),
                label: Text(loc.planningAlignFinish),
              ),
            ),
          ] else ...[
            Text(
              loc.planningRunDays,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            WeekdayPicker(
              key: const Key('phaseRunDays'),
              selected: controller.runDays,
              color: Color(controller.color),
              hinted: controller.strengthDays,
              onChanged: controller.setRunDays,
            ),
            const SizedBox(height: 12),
            PhaseNumberField(
              controller: controller.runKmText,
              label: loc.planningWeeklyKm,
              suffix: 'km',
              decimal: true,
              onChanged: controller.touch,
            ),
          ],
        ],
      ),
    );
  }

  String _coverage(AppLocalizations loc, int planWeeks) {
    const resolver = RunPlanWeekResolver();
    final phaseWeeks = controller.weeks;
    final start = controller.runPlanStartWeek;
    return switch (resolver.coverage(
      phaseWeeks: phaseWeeks,
      planWeeks: planWeeks,
      startWeek: start,
    )) {
      RunPlanCoverage.exact ||
      RunPlanCoverage.empty => loc.planningRunCoverageExact,
      RunPlanCoverage.planLonger => loc.planningRunCoverageLonger(
        resolver.leftoverPlanWeeks(
          phaseWeeks: phaseWeeks,
          planWeeks: planWeeks,
          startWeek: start,
        ),
      ),
      RunPlanCoverage.planRepeats => loc.planningRunCoverageRepeats,
    };
  }
}

class PhaseBodySleepCard extends StatelessWidget {
  final PhaseEditorController controller;

  const PhaseBodySleepCard({super.key, required this.controller});

  static const _rates = [-1.0, -0.75, -0.5, -0.25, 0.0, 0.25, 0.5];

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final weight = controller.latestWeightKg;
    final rate = controller.weeklyWeightChangePercent;
    return PlanningCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            loc.planningWeightRate,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ChoiceChip(
                label: Text(loc.planningNone),
                selected: rate == null,
                onSelected: (_) => controller.setWeeklyWeightChange(null),
              ),
              for (final value in _rates)
                ChoiceChip(
                  label: Text(_percent(value)),
                  selected: rate == value,
                  onSelected: (_) => controller.setWeeklyWeightChange(value),
                ),
            ],
          ),
          if (rate != null && rate != 0 && weight != null) ...[
            const SizedBox(height: 6),
            Text(
              loc.planningWeightRateKg(
                AppNumberFormat.decimal((weight * rate / 100).abs(), 2),
                rate < 0 ? loc.planningLose : loc.planningGain,
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 14),
          PhaseNumberField(
            controller: controller.targetWeightText,
            label: loc.planningTargetWeight,
            suffix: 'kg',
            decimal: true,
            helper: weight == null
                ? null
                : loc.planningCurrentWeight(AppNumberFormat.decimal(weight, 1)),
            onChanged: controller.touch,
          ),
          const Divider(height: 28),
          Row(
            children: [
              Icon(Icons.bedtime_outlined, size: 20, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  loc.planningSleepPerNight,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              PlanningStepper(
                value: controller.sleepHours == null
                    ? '—'
                    : '${_hours(controller.sleepHours!)} h',
                onDecrement: controller.sleepHours == null
                    ? null
                    : () => controller.setSleepHours(
                        controller.sleepHours! <= 5
                            ? null
                            : controller.sleepHours! - 0.5,
                      ),
                onIncrement: () => controller.setSleepHours(
                  controller.sleepHours == null
                      ? 8
                      : (controller.sleepHours! + 0.5).clamp(5, 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _percent(double value) {
    if (value == 0) return '0%';
    final sign = value > 0
        ? '+'
        : value < 0
        ? '−'
        : '';
    final text = AppNumberFormat.decimal(
      value.abs(),
      value.abs() * 100 % 50 == 0 ? 1 : 2,
    );
    return '$sign$text%';
  }

  static String _hours(double value) =>
      AppNumberFormat.decimal(value, value % 1 == 0 ? 0 : 1);
}
