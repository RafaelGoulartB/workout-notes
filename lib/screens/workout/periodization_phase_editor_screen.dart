import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/periodization_phase.dart';
import 'package:workout_notes/models/periodization_plan.dart';
import 'package:workout_notes/models/periodization_target.dart';
import 'package:workout_notes/periodization/phase_editor_controller.dart';
import 'package:workout_notes/periodization/phase_kind.dart';
import 'package:workout_notes/periodization/phase_week_plan.dart';
import 'package:workout_notes/periodization/run_plan_week_resolver.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';
import 'package:workout_notes/utils/periodization_palette.dart';
import 'package:workout_notes/widgets/periodization/planning_widgets.dart';
import 'package:workout_notes/widgets/run/run_plan_ui.dart';

/// Everything a phase plans, on one screen: what it is and how long it
/// lasts, its template week, nutrition (training vs rest days), training,
/// running, body and sleep targets, and per-week adjustments.
class PeriodizationPhaseEditorScreen extends StatefulWidget {
  final PeriodizationPlan plan;
  final PeriodizationPhase phase;

  /// Injected by tests; the screen builds its own otherwise.
  final PhaseEditorController? controller;

  const PeriodizationPhaseEditorScreen({
    super.key,
    required this.plan,
    required this.phase,
    this.controller,
  });

  @override
  State<PeriodizationPhaseEditorScreen> createState() =>
      _PeriodizationPhaseEditorScreenState();
}

class _PeriodizationPhaseEditorScreenState
    extends State<PeriodizationPhaseEditorScreen> {
  late final PhaseEditorController _controller =
      widget.controller ??
      PhaseEditorController(plan: widget.plan, phase: widget.phase);

  @override
  void initState() {
    super.initState();
    _controller.load();
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final loc = AppLocalizations.of(context)!;
    if (_controller.name.text.trim().isEmpty) {
      _snack(loc.planningNameRequired);
      return;
    }
    try {
      await _controller.save();
      if (!mounted) return;
      Navigator.pop(context, true);
    } on PeriodizationValidationException catch (error) {
      if (!mounted) return;
      _snack(planningErrorMessage(loc, error.code));
    }
  }

  void _snack(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Future<bool> _confirmDiscard() async {
    if (!_controller.dirty) return true;
    final loc = AppLocalizations.of(context)!;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(loc.planningDiscardTitle),
        content: Text(loc.planningDiscardBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(loc.planningKeepEditing),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(loc.planningDiscard),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => PopScope(
        canPop: !_controller.dirty,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final navigator = Navigator.of(context);
          if (await _confirmDiscard()) navigator.pop(false);
        },
        child: Scaffold(
          appBar: AppBar(title: Text(loc.planningEditPhase)),
          body: _controller.loading
              ? const Center(child: CircularProgressIndicator())
              : GestureDetector(
                  onTap: () => FocusScope.of(context).unfocus(),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      _IdentityCard(controller: _controller),
                      PlanningSectionLabel(
                        loc.planningTemplateWeek,
                        icon: Icons.view_week_outlined,
                      ),
                      _TemplateWeekCard(controller: _controller),
                      PlanningSectionLabel(
                        loc.planningNutrition,
                        icon: Icons.restaurant_outlined,
                      ),
                      _NutritionCard(controller: _controller, onSnack: _snack),
                      PlanningSectionLabel(
                        loc.planningTraining,
                        icon: Icons.fitness_center_outlined,
                      ),
                      _TrainingCard(controller: _controller),
                      PlanningSectionLabel(
                        loc.planningRunning,
                        icon: Icons.directions_run_outlined,
                      ),
                      _RunningCard(controller: _controller),
                      PlanningSectionLabel(
                        loc.planningBodyAndSleep,
                        icon: Icons.monitor_weight_outlined,
                      ),
                      _BodySleepCard(controller: _controller),
                      PlanningSectionLabel(
                        loc.planningWeeks,
                        icon: Icons.calendar_view_week_outlined,
                      ),
                      _WeeksCard(controller: _controller),
                    ],
                  ),
                ),
          bottomNavigationBar: _controller.loading
              ? null
              : SafeArea(
                  minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: FilledButton.icon(
                    key: const Key('phaseEditorSave'),
                    onPressed: _controller.saving ? null : _save,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    icon: _controller.saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_rounded),
                    label: Text(loc.planningSave),
                  ),
                ),
        ),
      ),
    );
  }
}

// =========================================================================
// Identity & duration
// =========================================================================

class _IdentityCard extends StatelessWidget {
  final PhaseEditorController controller;

  const _IdentityCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final start = controller.phase.startDate;
    final end = start.add(Duration(days: 7 * controller.weeks - 1));
    return PlanningCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PhaseAvatar(
                color: Color(controller.color),
                icon: controller.kind.icon,
                size: 48,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: controller.name,
                  onChanged: (_) => controller.touch(),
                  textCapitalization: TextCapitalization.sentences,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                  decoration: InputDecoration(
                    hintText: loc.planningPhaseNameHint,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final kind in PhaseKind.values)
                ChoiceChip(
                  avatar: Icon(
                    kind.icon,
                    size: 16,
                    color: controller.kind == kind
                        ? scheme.onSecondaryContainer
                        : Color(kind.color),
                  ),
                  label: Text(kind.label(loc)),
                  selected: controller.kind == kind,
                  showCheckmark: false,
                  onSelected: (_) => controller.setKind(
                    kind,
                    labelOf: (value) => value.label(loc),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            controller.kind.description(loc),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (controller.kind == PhaseKind.custom) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                for (final color in kPeriodizationColors)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => controller.setColor(color),
                      child: CircleAvatar(
                        radius: 14,
                        backgroundColor: Color(color),
                        child: controller.color == color
                            ? const Icon(
                                Icons.check,
                                size: 16,
                                color: Colors.white,
                              )
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const Divider(height: 28),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loc.planningDuration,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      planningDateRange(start, end),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              PlanningStepper(
                value: loc.planningWeeksShort(controller.weeks),
                onDecrement:
                    controller.weeks > 1 &&
                        controller.weeks > controller.editableFrom + 1
                    ? () => controller.setWeeks(controller.weeks - 1)
                    : null,
                onIncrement: controller.weeks < 104
                    ? () => controller.setWeeks(controller.weeks + 1)
                    : null,
              ),
            ],
          ),
          if (controller.weeks != controller.phase.totalWeeks)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                loc.planningDurationShiftHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.primary,
                ),
              ),
            ),
          const SizedBox(height: 20),
          TextField(
            controller: controller.intent,
            onChanged: (_) => controller.touch(),
            minLines: 1,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: loc.planningPhaseGoal,
              hintText: loc.planningPhaseGoalHint,
              prefixIcon: const Icon(Icons.flag_outlined),
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }
}

// =========================================================================
// Template week
// =========================================================================

class _TemplateWeekCard extends StatelessWidget {
  final PhaseEditorController controller;

  const _TemplateWeekCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final week = controller.currentWeek ?? controller.editableFrom;
    final plan = controller.weekPlan(week.clamp(0, controller.weeks - 1));
    final average = PhaseWeekPlan.averageCalories(plan);
    final trainingDays = plan.where((day) => day.trainingDay).length;
    return PlanningCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TemplateWeekStrip(
            week: plan,
            accent: Color(controller.color),
            strengthLabels: controller.strengthSequence,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              _Legend(
                icon: Icons.fitness_center_rounded,
                label: loc.planningLegendStrength,
              ),
              _Legend(
                icon: Icons.directions_run_rounded,
                label: loc.planningLegendRun,
              ),
              _Legend(
                icon: Icons.remove_rounded,
                label: loc.planningLegendRest,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            trainingDays == 0
                ? loc.planningTemplateWeekEmpty
                : average == null
                ? loc.planningTrainingDaysCount(trainingDays)
                : loc.planningTemplateWeekSummary(
                    trainingDays,
                    planningKcal(average),
                  ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final IconData icon;
  final String label;

  const _Legend({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// =========================================================================
// Nutrition
// =========================================================================

class _NutritionCard extends StatelessWidget {
  final PhaseEditorController controller;
  final ValueChanged<String> onSnack;

  const _NutritionCard({required this.controller, required this.onSnack});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tdee = controller.tdee;
    final kcal = controller.calories;
    final weight = controller.latestWeightKg;
    String? perKg(double? grams) => grams == null || weight == null
        ? null
        : loc.planningGramsPerKg((grams / weight).toStringAsFixed(1));
    final tdeeHint = tdee == null || kcal == null
        ? null
        : loc.planningVsTdee(
            planningKcal(tdee),
            _signedPercent((kcal / tdee - 1) * 100),
          );
    return PlanningCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  controller.restEnabled
                      ? loc.planningTrainingDay
                      : loc.planningEveryDay,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  if (!controller.suggestNutrition()) {
                    onSnack(loc.planningSuggestNeedsTdee);
                  }
                },
                icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                label: Text(loc.planningSuggest),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _NumberField(
            key: const Key('phaseCalories'),
            controller: controller.caloriesText,
            label: loc.planningCaloriesPerDay,
            suffix: 'kcal',
            helper: tdeeHint,
            onChanged: controller.touch,
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _NumberField(
                  key: const Key('phaseProtein'),
                  controller: controller.proteinText,
                  label: loc.planningProtein,
                  suffix: 'g',
                  helper: perKg(controller.proteinG),
                  onChanged: controller.touch,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _NumberField(
                  key: const Key('phaseFat'),
                  controller: controller.fatText,
                  label: loc.planningFat,
                  suffix: 'g',
                  helper: perKg(controller.fatG),
                  onChanged: controller.touch,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _CarbsLine(carbs: controller.carbsG),
          if (controller.macroConflict) ...[
            const SizedBox(height: 8),
            _Warning(text: loc.planningMacroConflict),
          ],
          const Divider(height: 28),
          SwitchListTile(
            key: const Key('phaseRestToggle'),
            contentPadding: EdgeInsets.zero,
            value: controller.restEnabled,
            onChanged: controller.setRestEnabled,
            title: Text(
              loc.planningRestDayDifferent,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(loc.planningRestDayHint),
          ),
          if (controller.restEnabled) ...[
            const SizedBox(height: 4),
            _NumberField(
              key: const Key('phaseRestCalories'),
              controller: controller.restCaloriesText,
              label: loc.planningRestCalories,
              suffix: 'kcal',
              helper: kcal == null || controller.restCalories == null
                  ? null
                  : loc.planningRestDelta(
                      _signed(controller.restCalories! - kcal),
                    ),
              onChanged: controller.touch,
            ),
            const SizedBox(height: 10),
            _CarbsLine(carbs: controller.restCarbsG),
            if (controller.strengthDays.isEmpty &&
                controller.runPlan == null &&
                controller.runDays.isEmpty) ...[
              const SizedBox(height: 8),
              _Warning(text: loc.planningRestNeedsDays),
            ],
          ],
          if (tdee == null) ...[
            const SizedBox(height: 8),
            Text(
              loc.planningNoTdeeHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _signed(double value) =>
      '${value > 0
          ? '+'
          : value < 0
          ? '−'
          : ''}${value.abs().round()}';

  static String _signedPercent(double value) =>
      '${value > 0
          ? '+'
          : value < 0
          ? '−'
          : ''}${value.abs().round()}%';
}

class _CarbsLine extends StatelessWidget {
  final double? carbs;

  const _CarbsLine({required this.carbs});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(
          Icons.grain_rounded,
          size: 16,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            loc.planningCarbsRemaining(
              carbs == null ? '—' : '${carbs!.round()} g',
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _Warning extends StatelessWidget {
  final String text;

  const _Warning({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withAlpha(90),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? suffix;
  final String? helper;
  final VoidCallback onChanged;
  final bool decimal;

  const _NumberField({
    super.key,
    required this.controller,
    required this.label,
    required this.onChanged,
    this.suffix,
    this.helper,
    this.decimal = false,
  });

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    onChanged: (_) => onChanged(),
    keyboardType: TextInputType.numberWithOptions(decimal: decimal),
    inputFormatters: [
      FilteringTextInputFormatter.allow(
        RegExp(decimal ? r'[0-9.,]' : r'[0-9]'),
      ),
    ],
    decoration: InputDecoration(
      labelText: label,
      suffixText: suffix,
      helperText: helper,
      border: const OutlineInputBorder(),
      isDense: true,
    ),
  );
}

// =========================================================================
// Training
// =========================================================================

class _TrainingCard extends StatelessWidget {
  final PhaseEditorController controller;

  const _TrainingCard({required this.controller});

  Future<void> _pickRoutines(BuildContext context) async {
    final loc = AppLocalizations.of(context)!;
    final selected = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _RoutinePickerSheet(
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
          _PickerRow(
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
                _RangeRow(
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
                _RangeRow(
                  label: loc.planningRpe,
                  min: controller.minRpe,
                  max: controller.maxRpe,
                  step: 0.5,
                  lowest: 1,
                  highest: 10,
                  start: 7,
                  format: (value) => value
                      .toStringAsFixed(value % 1 == 0 ? 0 : 1)
                      .replaceAll('.', ','),
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
class _RangeRow extends StatelessWidget {
  final String label;
  final double? min;
  final double? max;
  final double step;
  final double lowest;
  final double highest;
  final double start;
  final String Function(double value) format;
  final void Function(double? min, double? max) onChanged;

  const _RangeRow({
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

class _PickerRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _PickerRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest.withAlpha(90),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            children: [
              Icon(icon, size: 20, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoutinePickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> routines;
  final Map<String, List<String>> dayNames;
  final List<String> selected;
  final String title;

  const _RoutinePickerSheet({
    required this.routines,
    required this.dayNames,
    required this.selected,
    required this.title,
  });

  @override
  State<_RoutinePickerSheet> createState() => _RoutinePickerSheetState();
}

class _RoutinePickerSheetState extends State<_RoutinePickerSheet> {
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

// =========================================================================
// Running
// =========================================================================

class _RunningCard extends StatelessWidget {
  final PhaseEditorController controller;

  const _RunningCard({required this.controller});

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
          _PickerRow(
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
            _NumberField(
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

// =========================================================================
// Body & sleep
// =========================================================================

class _BodySleepCard extends StatelessWidget {
  final PhaseEditorController controller;

  const _BodySleepCard({required this.controller});

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
                ((weight * rate / 100).abs()).toStringAsFixed(2),
                rate < 0 ? loc.planningLose : loc.planningGain,
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 14),
          _NumberField(
            controller: controller.targetWeightText,
            label: loc.planningTargetWeight,
            suffix: 'kg',
            decimal: true,
            helper: weight == null
                ? null
                : loc.planningCurrentWeight(weight.toStringAsFixed(1)),
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
    final text = value
        .abs()
        .toStringAsFixed(value.abs() * 100 % 50 == 0 ? 1 : 2)
        .replaceAll('.', ',');
    return '$sign$text%';
  }

  static String _hours(double value) =>
      value.toStringAsFixed(value % 1 == 0 ? 0 : 1).replaceAll('.', ',');
}

// =========================================================================
// Weeks
// =========================================================================

class _WeeksCard extends StatelessWidget {
  final PhaseEditorController controller;

  const _WeeksCard({required this.controller});

  Future<void> _openWeek(BuildContext context, int week) async {
    final result = await showModalBottomSheet<_WeekSheetResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _WeekSheet(controller: controller, week: week),
    );
    if (result == null) return;
    controller.setAdjustment(week, result.adjustment);
    if (result.applyToFollowing) controller.applyAdjustmentToFollowing(week);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final base = controller.buildBase();
    return PlanningCard(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: Text(
              loc.planningWeeksHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          for (var week = 0; week < controller.weeks; week++)
            _WeekRow(
              key: Key('phaseWeek$week'),
              week: week,
              controller: controller,
              base: base,
              onTap: controller.isLocked(week)
                  ? null
                  : () => _openWeek(context, week),
            ),
        ],
      ),
    );
  }
}

class _WeekRow extends StatelessWidget {
  final int week;
  final PhaseEditorController controller;
  final PeriodizationTarget base;
  final VoidCallback? onTap;

  const _WeekRow({
    super.key,
    required this.week,
    required this.controller,
    required this.base,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final target = controller.targetForWeek(week, base: base);
    final start = controller.weekStart(week);
    final locked = controller.isLocked(week);
    final current = controller.currentWeek == week;
    final adjusted = controller.adjustments[week]?.changesTargets ?? false;
    final label = locked
        ? target?.weekLabel
        : controller.adjustments[week]?.label;
    final kcal = target?.calories;
    final rest = target?.restCalories;
    final accent = Color(controller.color);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: current
                    ? accent
                    : locked
                    ? scheme.surfaceContainerHighest.withAlpha(90)
                    : accent.withAlpha(36),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${week + 1}',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: current
                      ? scheme.surface
                      : locked
                      ? scheme.onSurfaceVariant
                      : accent,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          planningDateRange(
                            start,
                            start.add(const Duration(days: 6)),
                          ),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (label != null && label.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        PlanningPill(
                          icon: Icons.label_outline_rounded,
                          label: label,
                          color: accent,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    kcal == null
                        ? loc.planningNoNutritionTarget
                        : rest == null
                        ? '${planningKcal(kcal)} kcal'
                        : loc.planningKcalTrainingRest(
                            planningKcal(kcal),
                            planningKcal(rest),
                          ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: adjusted ? accent : scheme.onSurfaceVariant,
                      fontWeight: adjusted ? FontWeight.w700 : null,
                    ),
                  ),
                ],
              ),
            ),
            if (locked)
              Icon(
                Icons.lock_outline_rounded,
                size: 18,
                color: scheme.onSurfaceVariant,
              )
            else if (current)
              Text(
                loc.planningThisWeek,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w800,
                ),
              )
            else
              Icon(
                adjusted ? Icons.tune_rounded : Icons.chevron_right_rounded,
                size: 20,
                color: adjusted ? accent : scheme.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }
}

class _WeekSheetResult {
  final WeekAdjustment adjustment;
  final bool applyToFollowing;

  const _WeekSheetResult(this.adjustment, {this.applyToFollowing = false});
}

class _WeekSheet extends StatefulWidget {
  final PhaseEditorController controller;
  final int week;

  const _WeekSheet({required this.controller, required this.week});

  @override
  State<_WeekSheet> createState() => _WeekSheetState();
}

class _WeekSheetState extends State<_WeekSheet> {
  late final WeekAdjustment? _initial =
      widget.controller.adjustments[widget.week];
  late final _label = TextEditingController(text: _initial?.label ?? '');
  late final _calories = TextEditingController(
    text: _initial?.calories?.round().toString() ?? '',
  );
  late final _rest = TextEditingController(
    text: _initial?.restCalories?.round().toString() ?? '',
  );
  bool _applyFollowing = false;

  @override
  void dispose() {
    _label.dispose();
    _calories.dispose();
    _rest.dispose();
    super.dispose();
  }

  double? _parse(String raw) {
    final value = double.tryParse(raw.trim());
    return value == null || value <= 0 ? null : value;
  }

  WeekAdjustment get _current => WeekAdjustment(
    label: _label.text.trim().isEmpty ? null : _label.text.trim(),
    calories: _parse(_calories.text),
    restCalories: widget.controller.restEnabled ? _parse(_rest.text) : null,
  );

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final controller = widget.controller;
    final start = controller.weekStart(widget.week);
    final base = controller.buildBase();
    final presets = [
      loc.planningWeekLabelDeload,
      loc.planningWeekLabelRefeed,
      loc.planningWeekLabelDietBreak,
      loc.planningWeekLabelTest,
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              loc.planningWeekTitle(
                widget.week + 1,
                planningDateRange(start, start.add(const Duration(days: 6))),
              ),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              loc.planningWeekSheetHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final preset in presets)
                  ChoiceChip(
                    label: Text(preset),
                    selected: _label.text.trim() == preset,
                    onSelected: (selected) =>
                        setState(() => _label.text = selected ? preset : ''),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _label,
              onChanged: (_) => setState(() {}),
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: loc.planningWeekLabel,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const Key('weekSheetCalories'),
              controller: _calories,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: controller.restEnabled
                    ? loc.planningTrainingDayCalories
                    : loc.planningCaloriesPerDay,
                hintText: planningKcal(base.calories),
                helperText: loc.planningWeekKcalHelper(
                  planningKcal(base.calories),
                ),
                suffixText: 'kcal',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (controller.restEnabled) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _rest,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: loc.planningRestCalories,
                  hintText: planningKcal(base.restCalories),
                  helperText: loc.planningWeekKcalHelper(
                    planningKcal(base.restCalories),
                  ),
                  suffixText: 'kcal',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
            if (widget.week < controller.weeks - 1)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _applyFollowing,
                onChanged: (value) =>
                    setState(() => _applyFollowing = value ?? false),
                title: Text(loc.planningApplyToFollowing),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (_initial != null)
                  TextButton(
                    onPressed: () => Navigator.pop(
                      context,
                      _WeekSheetResult(
                        const WeekAdjustment(),
                        applyToFollowing: _applyFollowing,
                      ),
                    ),
                    child: Text(loc.planningResetWeek),
                  ),
                const Spacer(),
                FilledButton(
                  key: const Key('weekSheetApply'),
                  onPressed: () => Navigator.pop(
                    context,
                    _WeekSheetResult(
                      _current,
                      applyToFollowing: _applyFollowing,
                    ),
                  ),
                  child: Text(loc.planningApply),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
