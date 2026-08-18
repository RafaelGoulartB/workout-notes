import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/periodization_phase.dart';
import 'package:workout_notes/models/periodization_plan.dart';
import 'package:workout_notes/models/periodization_target.dart';
import 'package:workout_notes/periodization/periodization_phase_form_controller.dart';
import 'package:workout_notes/periodization/phase_draft_data.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';
import 'package:workout_notes/utils/periodization_palette.dart';
import 'package:workout_notes/widgets/periodization/nutrition_target_fields.dart';
import 'package:workout_notes/widgets/periodization/periodization_ui.dart';
import 'package:workout_notes/widgets/periodization/phase_week_selector.dart';
import 'package:workout_notes/widgets/periodization/week_copy_sheet.dart';

import 'nutrition_goal_suggest_sheet.dart';

class PeriodizationPhaseFormScreen extends StatefulWidget {
  final PeriodizationPlan plan;
  final PeriodizationPhase? phase;

  /// When true the editor never touches the database: "Save" pops with a
  /// [PeriodizationPhaseDraftData] result for the plan wizard to apply.
  final bool draftMode;
  final PeriodizationPhaseDraftData? draft;

  /// Optional externally-owned controller (e.g. from the plan wizard). When
  /// provided the screen uses it as-is and never disposes it; the caller is
  /// responsible for [PeriodizationPhaseFormController.load] and dispose.
  final PeriodizationPhaseFormController? controller;

  const PeriodizationPhaseFormScreen({
    super.key,
    required this.plan,
    this.phase,
    this.draftMode = false,
    this.draft,
    this.controller,
  });

  @override
  State<PeriodizationPhaseFormScreen> createState() =>
      _PeriodizationPhaseFormScreenState();
}

class _PeriodizationPhaseFormScreenState
    extends State<PeriodizationPhaseFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final PeriodizationPhaseFormController _controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller =
        widget.controller ??
        PeriodizationPhaseFormController(
          plan: widget.plan,
          phase: widget.phase,
          draftMode: widget.draftMode,
          draft: widget.draft,
        );
    _controller.addListener(_onControllerChanged);
    if (_ownsController) _controller.load();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final loc = AppLocalizations.of(context)!;
    try {
      final status = await _controller.save();
      if (!mounted) return;
      if (status == PhaseFormSaveStatus.overlap) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.periodizationOverlapError)),
        );
        return;
      }
      if (status == PhaseFormSaveStatus.macroConflict) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.nutritionSuggestMacroEnergyError)),
        );
        return;
      }
      Navigator.pop(
        context,
        widget.draftMode && _ownsController ? _controller.draftData : true,
      );
    } catch (error) {
      if (!mounted) return;
      final message =
          error is PeriodizationValidationException &&
              error.code == 'phase_overlap'
          ? loc.periodizationOverlapError
          : loc.periodizationSaveError('$error');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _pickDate(bool start) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: start ? _controller.startDate : _controller.endDate,
      firstDate: widget.plan.startDate,
      lastDate: _controller.lastAllowedEnd,
    );
    if (picked == null || !mounted) return;
    if (start) {
      _controller.setStartDate(picked);
    } else {
      _controller.setEndDate(picked);
    }
  }

  Future<void> _pickWeeks() async {
    final loc = AppLocalizations.of(context)!;
    final controller = TextEditingController(
      text: _controller.weeksCount.toString(),
    );
    final result = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(loc.periodizationPickWeeksTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onSubmitted: (value) {
            final parsed = int.tryParse(value.trim());
            if (parsed != null && parsed >= 1 && parsed <= 104) {
              Navigator.pop(context, parsed);
            }
          },
          decoration: InputDecoration(
            suffixText: 'sem',
            helperText: '1 – 104',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(loc.commonCancel),
          ),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(controller.text.trim());
              if (value != null && value >= 1 && value <= 104) {
                Navigator.pop(context, value);
              }
            },
            child: Text(loc.commonSave),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    _controller.setWeeks(result);
  }

  Future<void> _suggestNutritionTargets() async {
    await NutritionGoalSuggestSheet.show(
      context,
      bodyRepo: _controller.bodyRepository,
      settingsRepo: _controller.settingsRepository,
      onApply: (suggestion) {
        if (!mounted) return;
        _controller.applyNutritionSuggestion(
          suggestion.calories,
          suggestion.proteinG,
          suggestion.carbsG,
          suggestion.fatG,
        );
      },
    );
  }

  Future<void> _copyWeekTargets() async {
    final loc = AppLocalizations.of(context)!;
    final c = _controller;
    final targets = await WeekCopySheet.show(
      context,
      weekCount: c.weeksCount,
      selected: c.selectedWeek,
      firstWeekStart: c.weekStarts.first,
      phaseEnd: c.endDate,
      customizedWeeks: {
        for (var i = 0; i < c.weekOverrides.length; i++)
          if (c.weekOverrides[i] != null) i,
      },
      lockedWeeks: c.lockedWeeks,
      currentWeek: c.currentWeekIndex,
    );
    if (targets == null || targets.isEmpty || !mounted) return;
    final applied = c.applyToWeeks(targets);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(loc.periodizationWeekCopyApplied(applied))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final c = _controller;
    final locked = c.lockedWeeks;
    final effective = c.effective;
    final weekLocked = c.weekLocked;
    final weekCustomized = c.weekCustomized;
    final showEditableFields = c.showEditableFields;
    final weeksCount = c.weeksCount;
    final durationDays = c.durationDays;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.draftMode || c.editing
              ? loc.periodizationEditPhase
              : loc.periodizationNewPhase,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      bottomNavigationBar: c.loading
          ? null
          : PeriodizationBottomBar(
              primary: FilledButton.icon(
                onPressed: c.saving ? null : _save,
                icon: c.saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text(loc.commonSave),
              ),
            ),
      body: c.loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  PeriodizationSurface(
                    accentColor: Color(c.color),
                    selected: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: Color(c.color).withAlpha(35),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                Icons.flag_rounded,
                                color: Color(c.color),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                loc.periodizationPhaseIdentity,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          loc.periodizationPhaseIdentityHelp,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 18),
                        TextFormField(
                          controller: c.name,
                          decoration: InputDecoration(
                            labelText: loc.periodizationPhaseName,
                            hintText: loc.periodizationPhaseNameHint,
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? loc.periodizationPhaseName
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: c.type,
                          decoration: InputDecoration(
                            labelText: loc.periodizationPhaseType,
                            hintText: loc.periodizationPhaseTypeHint,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: c.intent,
                          maxLines: 3,
                          decoration: InputDecoration(
                            labelText: loc.periodizationIntent,
                            hintText: loc.periodizationIntentHint,
                            alignLabelWithHint: true,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          loc.periodizationColor,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: kPeriodizationColors
                              .map(
                                (value) => Semantics(
                                  button: true,
                                  selected: c.color == value,
                                  child: InkWell(
                                    onTap: () => c.setColor(value),
                                    borderRadius: BorderRadius.circular(24),
                                    child: Container(
                                      width: 38,
                                      height: 38,
                                      decoration: BoxDecoration(
                                        color: Color(value),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: c.color == value
                                              ? theme.colorScheme.onSurface
                                              : Colors.transparent,
                                          width: 2.5,
                                        ),
                                      ),
                                      child: c.color == value
                                          ? const Icon(
                                              Icons.check_rounded,
                                              color: Colors.white,
                                              size: 20,
                                            )
                                          : null,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  PeriodizationSectionHeader(
                    title: loc.periodizationPeriodAndIdentity,
                    subtitle: loc.periodizationPeriodHelp,
                    icon: Icons.date_range_outlined,
                  ),
                  PeriodizationSurface(
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _DateTile(
                                label: loc.periodizationStartDate,
                                date: c.startDate,
                                onTap: () => _pickDate(true),
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: Icon(Icons.arrow_forward_rounded),
                            ),
                            Expanded(
                              child: _DateTile(
                                label: loc.periodizationEndDate,
                                date: c.endDate,
                                onTap: () => _pickDate(false),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Icon(
                              Icons.timelapse_rounded,
                              size: 18,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${loc.periodizationDurationWeeks(weeksCount)}'
                                ' · '
                                '${loc.periodizationPhaseDuration(durationDays)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        InkWell(
                          onTap: _pickWeeks,
                          borderRadius: BorderRadius.circular(12),
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: loc.periodizationWeeks,
                              prefixIcon: const Icon(Icons.timelapse_rounded),
                              suffixIcon: const Icon(
                                Icons.chevron_right_rounded,
                              ),
                            ),
                            child: Text(
                              loc.periodizationDurationWeeks(weeksCount),
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (c.editing) ...[
                    const SizedBox(height: 10),
                    PeriodizationSurface(
                      padding: EdgeInsets.zero,
                      child: SwitchListTile(
                        value: c.shiftFollowing,
                        onChanged: c.setShiftFollowing,
                        secondary: const Icon(Icons.low_priority_rounded),
                        title: Text(loc.periodizationShiftFollowing),
                        subtitle: Text(loc.periodizationShiftFollowingHelp),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  PeriodizationSectionHeader(
                    title: loc.periodizationTargets,
                    subtitle: loc.periodizationWeeklyTargetsHelp,
                    icon: Icons.track_changes_rounded,
                  ),
                  PeriodizationSurface(
                    padding: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                          child: PhaseWeekSelector(
                            weekCount: weeksCount,
                            selected: c.selectedWeek,
                            firstWeekStart: c.weekStarts.first,
                            phaseEnd: c.endDate,
                            customizedWeeks: {
                              for (var i = 0; i < c.weekOverrides.length; i++)
                                if (c.weekOverrides[i] != null) i,
                            },
                            lockedWeeks: locked,
                            currentWeek: c.currentWeekIndex,
                            onSelect: c.selectWeek,
                            onCustomize: !weekLocked &&
                                    c.selectedWeek > 0 &&
                                    !weekCustomized
                                ? c.customizeSelectedWeek
                                : null,
                            onUseInheritance: !weekLocked &&
                                    c.selectedWeek > 0 &&
                                    weekCustomized
                                ? c.useInheritance
                                : null,
                            onCopy: !weekLocked &&
                                    weeksCount > 1 &&
                                    (c.selectedWeek == 0 || weekCustomized)
                                ? _copyWeekTargets
                                : null,
                          ),
                        ),
                        _targetsDivider(theme),
                        if (showEditableFields)
                          ..._editableSections(
                            loc,
                            c,
                            weekLocked,
                            _suggestNutritionTargets,
                          )
                        else
                          _readOnlyList(theme, effective, weekLocked),
                      ],
                    ),
                  ),
                  if (c.editing) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondaryContainer.withAlpha(80),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.history_rounded, size: 19),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              loc.periodizationVersionedTarget,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                ],
              ),
            ),
    );
  }

  String _targetCardSubtitle(String help, List<String> keys) {
    final loc = AppLocalizations.of(context)!;
    final filled = _controller.filledTargets(keys);
    return filled == 0
        ? help
        : loc.periodizationTargetsConfigured(filled, keys.length);
  }

  Widget _targetsDivider(ThemeData theme) => Divider(
    height: 1,
    thickness: 1,
    indent: 14,
    endIndent: 14,
    color: theme.colorScheme.outlineVariant.withAlpha(80),
  );

  List<Widget> _editableSections(
    AppLocalizations loc,
    PeriodizationPhaseFormController c,
    bool weekLocked,
    Future<void> Function() onSuggestNutrition,
  ) {
    final theme = Theme.of(context);
    final nutrition = _targetTile(
      loc,
      theme,
      title: loc.periodizationNutritionTargets,
      icon: Icons.restaurant_outlined,
      keys: const ['adjustment', 'proteinPerKg', 'fatPerKg', 'refWeight'],
      help: loc.periodizationNutritionTargetsHelp,
      initiallyExpanded: true,
      actionLabel: loc.periodizationSuggestTargets,
      onAction: () => onSuggestNutrition(),
      child: NutritionTargetFields(
        tdee: c.tdee,
        adjustment: c.targetControllers['adjustment']!,
        proteinPerKg: c.targetControllers['proteinPerKg']!,
        fatPerKg: c.targetControllers['fatPerKg']!,
        referenceWeight: c.targetControllers['refWeight']!,
        onChanged: c.onTargetChanged,
      ),
    );
    final training = _targetTile(
      loc,
      theme,
      title: loc.periodizationTrainingTargets,
      icon: Icons.fitness_center,
      keys: const ['workouts', 'minSets', 'maxSets', 'minRpe', 'maxRpe'],
      help: loc.periodizationTrainingTargetsHelp,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth >= 560
                  ? (constraints.maxWidth - 10) / 2
                  : constraints.maxWidth;
              Widget field(
                String key,
                String label, {
                bool integer = false,
                bool signed = false,
                String? unit,
              }) => SizedBox(
                width: width,
                child: _field(key, label,
                    integer: integer, signed: signed, unit: unit),
              );
              return Wrap(
                spacing: 10,
                runSpacing: 12,
                children: [
                  field('workouts', loc.periodizationWorkoutsPerWeek,
                      integer: true, unit: loc.periodizationPerWeekUnit),
                  field('minSets', loc.periodizationMinSets,
                      integer: true, unit: loc.periodizationPerWeekUnit),
                  field('maxSets', loc.periodizationMaxSets,
                      integer: true, unit: loc.periodizationPerWeekUnit),
                  field('minRpe', loc.periodizationMinRpe),
                  field('maxRpe', loc.periodizationMaxRpe),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String?>(
            initialValue: c.routineId,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: loc.periodizationLinkedRoutine,
              prefixIcon: const Icon(
                Icons.fitness_center_outlined,
              ),
              helperText: loc.periodizationLinkedRoutineWeeklyHelp,
            ),
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text(
                  loc.periodizationNoRoutine,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ...c.routines.map(
                (routine) => DropdownMenuItem<String?>(
                  value: routine['id'] as String,
                  child: Text(
                    routine['name'] as String,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            onChanged: weekLocked ? null : c.setRoutine,
          ),
        ],
      ),
    );
    final body = _targetTile(
      loc,
      theme,
      title: loc.periodizationBodyTargets,
      icon: Icons.monitor_weight_outlined,
      keys: const ['weight', 'change'],
      help: loc.periodizationBodyTargetsHelp,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth >= 560
              ? (constraints.maxWidth - 10) / 2
              : constraints.maxWidth;
          Widget field(String key, String label, {String? unit}) => SizedBox(
            width: width,
            child: _field(key, label, unit: unit),
          );
          return Wrap(
            spacing: 10,
            runSpacing: 12,
            children: [
              field('weight', loc.periodizationTargetWeight, unit: 'kg'),
              field(
                'change',
                loc.periodizationWeeklyWeightChange,
                unit: '%',
              ),
            ],
          );
        },
      ),
    );
    final sleep = _targetTile(
      loc,
      theme,
      title: loc.periodizationSleepTargets,
      icon: Icons.nightlight_outlined,
      keys: const ['sleep'],
      help: loc.periodizationSleepTargetsHelp,
      child: _field('sleep', loc.periodizationSleepHours, unit: 'h'),
    );

    return [
      nutrition,
      _targetsDivider(theme),
      training,
      _targetsDivider(theme),
      body,
      _targetsDivider(theme),
      sleep,
    ];
  }

  Widget _targetTile(
    AppLocalizations loc,
    ThemeData theme, {
    required String title,
    required IconData icon,
    required List<String> keys,
    required String help,
    required Widget child,
    bool initiallyExpanded = false,
    String? actionLabel,
    VoidCallback? onAction,
  }) => ExpansionTile(
    initiallyExpanded: initiallyExpanded,
    tilePadding: const EdgeInsets.fromLTRB(14, 5, 12, 5),
    childrenPadding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
    shape: const Border(),
    collapsedShape: const Border(),
    leading: Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withAlpha(125),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 16, color: theme.colorScheme.primary),
    ),
    title: Text(
      title,
      style: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w800,
      ),
    ),
    subtitle: Text(
      _targetCardSubtitle(help, keys),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    ),
    children: [
      if (actionLabel != null && onAction != null) ...[
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.auto_awesome_rounded, size: 18),
            label: Text(actionLabel),
          ),
        ),
        const SizedBox(height: 14),
      ],
      child,
    ],
  );

  Widget _readOnlyList(
    ThemeData theme,
    PeriodizationTarget? effective,
    bool weekLocked,
  ) {
    final loc = AppLocalizations.of(context)!;
    final c = _controller;
    final target =
        effective ?? c.emptyTarget(c.weekStarts[c.selectedWeek]);
    List<(String, String)> nutritionRows() => [
      if (target.calories != null) (loc.periodizationCaloriesPerDay, '${target.calories!.round()} kcal'),
      if (target.proteinG != null) (loc.nutritionProgressProtein, '${target.proteinG!.round()} g'),
      if (target.carbsG != null) (loc.periodizationCarbsRemainder, '${target.carbsG!.round()} g'),
      if (target.fatG != null) (loc.nutritionProgressFat, '${target.fatG!.round()} g'),
    ];
    List<(String, String)> trainingRows() => [
      if (target.routineId != null)
        (
          loc.periodizationLinkedRoutine,
          c.routines
                  .where((routine) => routine['id'] == target.routineId)
                  .map((routine) => routine['name'] as String)
                  .firstOrNull ??
              loc.periodizationNoRoutine,
        ),
      if (target.workoutsPerWeek != null)
        (
          loc.periodizationWorkoutsPerWeek,
          '${target.workoutsPerWeek}${loc.periodizationPerWeekUnit}',
        ),
      if (target.minSetsPerWeek != null || target.maxSetsPerWeek != null)
        (
          loc.periodizationMinSets,
          '${target.minSetsPerWeek ?? '-'}–${target.maxSetsPerWeek ?? '-'}',
        ),
      if (target.minRpe != null || target.maxRpe != null)
        (
          loc.periodizationMinRpe,
          '${target.minRpe ?? '-'}–${target.maxRpe ?? '-'}',
        ),
    ];
    List<(String, String)> bodyRows() => [
      if (target.targetWeightKg != null)
        (
          loc.periodizationTargetWeight,
          '${target.targetWeightKg} kg',
        ),
      if (target.weeklyWeightChangePercent != null)
        (
          loc.periodizationWeeklyWeightChange,
          '${target.weeklyWeightChangePercent} %',
        ),
    ];
    List<(String, String)> sleepRows() => [
      if (target.sleepHours != null)
        (
          loc.periodizationSleepHours,
          '${target.sleepHours} h',
        ),
    ];

    final sections = [
      (
        loc.periodizationNutritionTargets,
        Icons.restaurant_outlined,
        nutritionRows(),
      ),
      (
        loc.periodizationTrainingTargets,
        Icons.fitness_center,
        trainingRows(),
      ),
      (
        loc.periodizationBodyTargets,
        Icons.monitor_weight_outlined,
        bodyRows(),
      ),
      (loc.periodizationSleepTargets, Icons.nightlight_outlined, sleepRows()),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < sections.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            _readOnlySection(theme, sections[i].$1, sections[i].$2, sections[i].$3),
          ],
        ],
      ),
    );
  }

  Widget _readOnlySection(
    ThemeData theme,
    String title,
    IconData icon,
    List<(String, String)> values,
  ) {
    final loc = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withAlpha(125),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 17, color: theme.colorScheme.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        if (values.isEmpty) ...[
          const SizedBox(height: 6),
          Text(
            loc.periodizationOptionalTargets,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ] else ...[
          const SizedBox(height: 8),
          for (final entry in values)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.$1,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Text(
                    entry.$2,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget _field(
    String key,
    String label, {
    bool integer = false,
    bool signed = false,
    String? unit,
  }) => TextField(
    controller: _controller.targetControllers[key],
    onChanged: (_) => _controller.onTargetChanged(),
    keyboardType: TextInputType.numberWithOptions(
      decimal: !integer,
      signed: signed,
    ),
    decoration: InputDecoration(
      labelText: label,
      suffixText: unit,
      filled: true,
      fillColor: Theme.of(context).colorScheme.surfaceContainerLowest,
    ),
  );
}

class _DateTile extends StatelessWidget {
  final String label;
  final DateTime date;
  final VoidCallback onTap;

  const _DateTile({
    required this.label,
    required this.date,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Icon(
                Icons.calendar_today_outlined,
                size: 17,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  DateFormat.MMMd(Intl.defaultLocale).format(date),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
