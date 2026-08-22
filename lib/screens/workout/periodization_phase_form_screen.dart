import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/periodization_phase.dart';
import 'package:workout_notes/models/periodization_plan.dart';
import 'package:workout_notes/models/periodization_target.dart';
import 'package:workout_notes/models/run_plan.dart';
import 'package:workout_notes/periodization/periodization_phase_form_controller.dart';
import 'package:workout_notes/periodization/phase_draft_data.dart';
import 'package:workout_notes/periodization/run_plan_week_resolver.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';
import 'package:workout_notes/utils/periodization_palette.dart';
import 'package:workout_notes/widgets/periodization/nutrition_target_fields.dart';
import 'package:workout_notes/widgets/periodization/periodization_ui.dart';
import 'package:workout_notes/widgets/periodization/phase_week_selector.dart';
import 'package:workout_notes/widgets/run/run_plan_ui.dart';
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

  /// Opens scrolled to the targets section. The planning home links here with
  /// a "set targets" call to action, which would otherwise land on the name
  /// field with the targets far below the fold.
  final bool focusTargets;

  const PeriodizationPhaseFormScreen({
    super.key,
    required this.plan,
    this.phase,
    this.draftMode = false,
    this.draft,
    this.controller,
    this.focusTargets = false,
  });

  @override
  State<PeriodizationPhaseFormScreen> createState() =>
      _PeriodizationPhaseFormScreenState();
}

class _PeriodizationPhaseFormScreenState
    extends State<PeriodizationPhaseFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _targetsKey = GlobalKey();
  late final PeriodizationPhaseFormController _controller;
  late final bool _ownsController;
  bool _targetsRevealed = false;

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

  /// The form body only exists once the controller finishes loading, so the
  /// reveal waits for the first frame that actually has the targets section.
  void _maybeRevealTargets() {
    if (!widget.focusTargets || _targetsRevealed || _controller.loading) return;
    _targetsRevealed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _targetsKey.currentContext;
      if (!mounted || target == null) return;
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        alignment: 0.05,
      );
    });
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(loc.periodizationOverlapError)));
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
          decoration: InputDecoration(suffixText: 'sem', helperText: '1 – 104'),
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

  Future<void> _pickRoutines() async {
    final loc = AppLocalizations.of(context)!;
    final selected = {..._controller.routineIds};
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  loc.periodizationLinkedRoutine,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(loc.periodizationLinkedRoutineWeeklyHelp),
                const SizedBox(height: 10),
                if (_controller.routines.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(loc.periodizationNoRoutine),
                  )
                else
                  ..._controller.routines.map((routine) {
                    final id = routine['id'] as String;
                    final days = _controller.routineDayNames[id] ?? const [];
                    return CheckboxListTile(
                      value: selected.contains(id),
                      title: Text(routine['name'] as String),
                      // A routine is only useful here through its days: the
                      // suggestion engine walks them in order, so the count
                      // is what decides how the week actually looks.
                      subtitle: Text(
                        loc.periodizationRoutineDays(days.length),
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (value) => setSheetState(() {
                        if (value == true) {
                          selected.add(id);
                        } else {
                          selected.remove(id);
                        }
                      }),
                    );
                  }),
                if (selected.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _RoutineSequencePreview(
                    days: [
                      for (final id in selected)
                        ...?_controller.routineDayNames[id],
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () => Navigator.pop(sheetContext, selected),
                  child: Text(loc.commonSave),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result != null && mounted) _controller.setRoutines(result);
  }

  Future<void> _pickRunPlans() async {
    final loc = AppLocalizations.of(context)!;
    final selected = {..._controller.runPlanIds};
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  loc.periodizationRunPlans,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(loc.periodizationRunPlansHelp),
                const SizedBox(height: 10),
                if (_controller.runPlans.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(loc.periodizationRunNoPlan),
                  )
                else
                  ..._controller.runPlans.map(
                    (plan) => CheckboxListTile(
                      value: selected.contains(plan.id),
                      title: Text(plan.name),
                      subtitle: Text(loc.runPlanWeeksValue(plan.weeks)),
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (value) => setSheetState(() {
                        if (value == true) {
                          selected.add(plan.id);
                        } else {
                          selected.remove(plan.id);
                        }
                      }),
                    ),
                  ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () => Navigator.pop(sheetContext, selected),
                  child: Text(loc.commonSave),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result != null && mounted) _controller.setRunPlans(result);
  }

  /// Sheet listing the plan's weeks so the phase can start on any of them.
  /// Each row carries that week's volume, which is how a runner recognises
  /// "the week I am on" without counting.
  Future<void> _pickAlignment(RunPlan plan) async {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final picked = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
              child: Text(
                loc.periodizationRunAlignPick,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text(
                loc.periodizationRunAlignHelp,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: plan.weeks,
                itemBuilder: (context, index) {
                  final volume = plan.weeklyDistanceMeters(index);
                  final sessions = plan.workoutsForWeek(index).length;
                  final selected = index == _controller.runPlanStartWeek;
                  return ListTile(
                    onTap: () => Navigator.pop(sheetContext, index),
                    selected: selected,
                    leading: Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                    ),
                    title: Text(loc.periodizationWeekChip(index + 1)),
                    subtitle: Text(
                      loc.runPlanWeekSummary(
                        RunPlanUi.kmValue(volume),
                        sessions,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null && mounted) _controller.setRunPlanStartWeek(picked);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final c = _controller;
    _maybeRevealTargets();
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
                  KeyedSubtree(
                    key: _targetsKey,
                    child: PeriodizationSectionHeader(
                      title: loc.periodizationTargets,
                      subtitle: loc.periodizationWeeklyTargetsHelp,
                      icon: Icons.track_changes_rounded,
                    ),
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
                            onCustomize:
                                !weekLocked &&
                                    c.selectedWeek > 0 &&
                                    !weekCustomized
                                ? c.customizeSelectedWeek
                                : null,
                            onUseInheritance:
                                !weekLocked &&
                                    c.selectedWeek > 0 &&
                                    weekCustomized
                                ? c.useInheritance
                                : null,
                            onCopy:
                                !weekLocked &&
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
                        color: theme.colorScheme.secondaryContainer.withAlpha(
                          80,
                        ),
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
                child: _field(
                  key,
                  label,
                  integer: integer,
                  signed: signed,
                  unit: unit,
                ),
              );
              return Wrap(
                spacing: 10,
                runSpacing: 12,
                children: [
                  field(
                    'workouts',
                    loc.periodizationWorkoutsPerWeek,
                    integer: true,
                    unit: loc.periodizationPerWeekUnit,
                  ),
                  field(
                    'minSets',
                    loc.periodizationMinSets,
                    integer: true,
                    unit: loc.periodizationPerWeekUnit,
                  ),
                  field(
                    'maxSets',
                    loc.periodizationMaxSets,
                    integer: true,
                    unit: loc.periodizationPerWeekUnit,
                  ),
                  field('minRpe', loc.periodizationMinRpe),
                  field('maxRpe', loc.periodizationMaxRpe),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          InkWell(
            onTap: weekLocked ? null : _pickRoutines,
            borderRadius: BorderRadius.circular(12),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: loc.periodizationLinkedRoutine,
                prefixIcon: const Icon(Icons.fitness_center_outlined),
                suffixIcon: const Icon(Icons.chevron_right_rounded),
              ),
              child: Text(
                c.routineIds.isEmpty
                    ? loc.periodizationNoRoutine
                    : c.routineIds
                          .map(
                            (id) => c.routines
                                .where((routine) => routine['id'] == id)
                                .map((routine) => routine['name'] as String)
                                .firstOrNull,
                          )
                          .whereType<String>()
                          .join(', '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
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
              field('change', loc.periodizationWeeklyWeightChange, unit: '%'),
            ],
          );
        },
      ),
    );
    final running = _targetTile(
      loc,
      theme,
      title: loc.periodizationRunSectionTitle,
      icon: Icons.directions_run,
      keys: const ['runSessions', 'runDistance', 'longRun', 'runQuality'],
      help: loc.periodizationRunSectionHelp,
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
                String? unit,
              }) => SizedBox(
                width: width,
                child: _field(key, label, integer: integer, unit: unit),
              );
              return Wrap(
                spacing: 10,
                runSpacing: 12,
                children: [
                  field(
                    'runSessions',
                    loc.periodizationRunSessionsPerWeek,
                    integer: true,
                    unit: loc.periodizationPerWeekUnit,
                  ),
                  field(
                    'runDistance',
                    loc.periodizationRunWeeklyDistance,
                    unit: 'km',
                  ),
                  field(
                    'longRun',
                    loc.periodizationRunLongRunDistance,
                    unit: 'km',
                  ),
                  field(
                    'runQuality',
                    loc.periodizationRunQualitySessions,
                    integer: true,
                    unit: loc.periodizationPerWeekUnit,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          InkWell(
            onTap: weekLocked ? null : _pickRunPlans,
            borderRadius: BorderRadius.circular(12),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: loc.periodizationRunPlans,
                prefixIcon: const Icon(Icons.route_outlined),
                suffixIcon: const Icon(Icons.chevron_right_rounded),
              ),
              child: Text(
                c.runPlanIds.isEmpty
                    ? loc.periodizationRunNoPlan
                    : c.runPlanIds
                          .map(
                            (id) => c.runPlans
                                .where((plan) => plan.id == id)
                                .map((plan) => plan.name)
                                .firstOrNull,
                          )
                          .whereType<String>()
                          .join(', '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (c.alignmentPlan case final alignmentPlan?) ...[
            const SizedBox(height: 12),
            _RunPlanAlignment(
              phaseWeeks: c.weeksCount,
              plan: alignmentPlan,
              startWeek: c.runPlanStartWeek,
              enabled: !weekLocked,
              onPick: () => _pickAlignment(alignmentPlan),
              onChange: c.setRunPlanStartWeek,
            ),
          ],
        ],
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
      running,
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
  }) => _TargetTile(
    title: title,
    icon: icon,
    subtitle: _targetCardSubtitle(help, keys),
    initiallyExpanded: initiallyExpanded,
    actionLabel: actionLabel,
    onAction: onAction,
    child: child,
  );

  Widget _readOnlyList(
    ThemeData theme,
    PeriodizationTarget? effective,
    bool weekLocked,
  ) {
    final loc = AppLocalizations.of(context)!;
    final c = _controller;
    final target = effective ?? c.emptyTarget(c.weekStarts[c.selectedWeek]);
    List<(String, String)> nutritionRows() => [
      if (target.calories != null)
        (loc.periodizationCaloriesPerDay, '${target.calories!.round()} kcal'),
      if (target.proteinG != null)
        (loc.nutritionProgressProtein, '${target.proteinG!.round()} g'),
      if (target.carbsG != null)
        (loc.periodizationCarbsRemainder, '${target.carbsG!.round()} g'),
      if (target.fatG != null)
        (loc.nutritionProgressFat, '${target.fatG!.round()} g'),
    ];
    List<(String, String)> trainingRows() => [
      if (target.routineIds.isNotEmpty)
        (
          loc.periodizationLinkedRoutine,
          target.routineIds
              .map(
                (id) => c.routines
                    .where((routine) => routine['id'] == id)
                    .map((routine) => routine['name'] as String)
                    .firstOrNull,
              )
              .whereType<String>()
              .join(', '),
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
    List<(String, String)> runningRows() => [
      if (target.runPlanIds.isNotEmpty)
        (
          loc.periodizationRunPlans,
          target.runPlanIds
              .map(
                (id) => c.runPlans
                    .where((plan) => plan.id == id)
                    .map((plan) => plan.name)
                    .firstOrNull,
              )
              .whereType<String>()
              .join(', '),
        ),
      if (target.runSessionsPerWeek != null)
        (
          loc.periodizationRunSessionsPerWeek,
          '${target.runSessionsPerWeek}${loc.periodizationPerWeekUnit}',
        ),
      if (target.runWeeklyDistanceMeters != null)
        (
          loc.periodizationRunWeeklyDistance,
          RunPlanUi.distanceLabel(target.runWeeklyDistanceMeters!),
        ),
      if (target.longRunDistanceMeters != null)
        (
          loc.periodizationRunLongRunDistance,
          RunPlanUi.distanceLabel(target.longRunDistanceMeters!),
        ),
      if (target.qualitySessionsPerWeek != null)
        (
          loc.periodizationRunQualitySessions,
          '${target.qualitySessionsPerWeek}${loc.periodizationPerWeekUnit}',
        ),
    ];
    List<(String, String)> bodyRows() => [
      if (target.targetWeightKg != null)
        (loc.periodizationTargetWeight, '${target.targetWeightKg} kg'),
      if (target.weeklyWeightChangePercent != null)
        (
          loc.periodizationWeeklyWeightChange,
          '${target.weeklyWeightChangePercent} %',
        ),
    ];
    List<(String, String)> sleepRows() => [
      if (target.sleepHours != null)
        (loc.periodizationSleepHours, '${target.sleepHours} h'),
    ];

    final sections = [
      (
        loc.periodizationNutritionTargets,
        Icons.restaurant_outlined,
        nutritionRows(),
      ),
      (loc.periodizationTrainingTargets, Icons.fitness_center, trainingRows()),
      (loc.periodizationRunSectionTitle, Icons.directions_run, runningRows()),
      (loc.periodizationBodyTargets, Icons.monitor_weight_outlined, bodyRows()),
      (loc.periodizationSleepTargets, Icons.nightlight_outlined, sleepRows()),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < sections.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            _readOnlySection(
              theme,
              sections[i].$1,
              sections[i].$2,
              sections[i].$3,
            ),
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

/// Custom collapsible section used by the phase target editor.
///
/// We render the header and body by hand to avoid the Material
/// [ListTile]/[ExpansionTile] internals, which reserve leading/title-gap
/// space that can push the body beyond the card width on small phones and
/// trigger a horizontal RenderFlex overflow while transitioning between
/// weeks.
class _TargetTile extends StatefulWidget {
  final String title;
  final IconData icon;
  final String subtitle;
  final bool initiallyExpanded;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget child;

  const _TargetTile({
    required this.title,
    required this.icon,
    required this.subtitle,
    required this.child,
    this.initiallyExpanded = false,
    this.actionLabel,
    this.onAction,
  });

  @override
  State<_TargetTile> createState() => _TargetTileState();
}

class _TargetTileState extends State<_TargetTile> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withAlpha(125),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    widget.icon,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedRotation(
                  duration: const Duration(milliseconds: 180),
                  turns: _expanded ? 0.5 : 0,
                  child: Icon(
                    Icons.expand_more_rounded,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeInOut,
          child: _expanded
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.actionLabel != null &&
                          widget.onAction != null) ...[
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: widget.onAction,
                            icon: const Icon(
                              Icons.auto_awesome_rounded,
                              size: 18,
                            ),
                            label: Text(widget.actionLabel!),
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      widget.child,
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
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

/// Shows and edits how the phase's weeks line up with the linked running
/// plan's weeks, plus what that alignment implies (exact fit, repeats, or a
/// tail of plan weeks the phase never reaches).
class _RunPlanAlignment extends StatelessWidget {
  final int phaseWeeks;
  final RunPlan plan;
  final int startWeek;
  final bool enabled;
  final VoidCallback onPick;
  final ValueChanged<int> onChange;

  const _RunPlanAlignment({
    required this.phaseWeeks,
    required this.plan,
    required this.startWeek,
    required this.enabled,
    required this.onPick,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    const resolver = RunPlanWeekResolver();
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final coverage = resolver.coverage(
      phaseWeeks: phaseWeeks,
      planWeeks: plan.weeks,
      startWeek: startWeek,
    );
    final String fit;
    switch (coverage) {
      case RunPlanCoverage.exact:
        fit = loc.periodizationRunAlignExact;
      case RunPlanCoverage.planRepeats:
        fit = loc.periodizationRunAlignRepeats(
          resolver.repeatsWithin(
            phaseWeeks: phaseWeeks,
            planWeeks: plan.weeks,
            startWeek: startWeek,
          ),
        );
      case RunPlanCoverage.planLonger:
        fit = loc.periodizationRunAlignLeftover(
          resolver.leftoverPlanWeeks(
            phaseWeeks: phaseWeeks,
            planWeeks: plan.weeks,
            startWeek: startWeek,
          ),
        );
      case RunPlanCoverage.empty:
        fit = '';
    }
    final lastPlanWeek = resolver.planWeekFor(
      phaseWeek: phaseWeeks - 1,
      planWeeks: plan.weeks,
      startWeek: startWeek,
    );
    final finishAligned = resolver.startWeekForFinish(
      phaseWeeks: phaseWeeks,
      planWeeks: plan.weeks,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withAlpha(90),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.link_rounded, size: 17, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  loc.periodizationRunAlignTitle,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton(
                onPressed: enabled ? onPick : null,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: Text(loc.periodizationWeekChip(startWeek + 1)),
              ),
            ],
          ),
          Text(
            loc.periodizationRunAlignValue(startWeek + 1),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          // The two ends of the mapping say more than any explanation: the
          // user reads where the phase starts in the plan and where it lands.
          Text(
            loc.periodizationRunAlignPreview(1, startWeek + 1),
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (phaseWeeks > 1 && lastPlanWeek != null)
            Text(
              loc.periodizationRunAlignPreview(phaseWeeks, lastPlanWeek + 1),
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          if (fit.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              fit,
              style: theme.textTheme.labelSmall?.copyWith(
                color: coverage == RunPlanCoverage.exact
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (enabled) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                if (startWeek != 0)
                  TextButton(
                    onPressed: () => onChange(0),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: Text(loc.periodizationRunAlignReset),
                  ),
                if (startWeek != finishAligned && finishAligned != 0)
                  TextButton(
                    onPressed: () => onChange(finishAligned),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: Text(loc.periodizationRunAlignFinish),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The training order the picked routines produce. The suggestion engine walks
/// every day of every selected routine in sequence and restarts at the end, so
/// showing the resulting chain is the only way to see what a multi-routine
/// selection actually schedules.
class _RoutineSequencePreview extends StatelessWidget {
  final List<String> days;

  const _RoutineSequencePreview({required this.days});

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const SizedBox.shrink();
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Long chains are unreadable in a sheet; the first few convey the shape.
    final shown = days.take(6).toList();
    final suffix = days.length > shown.length ? ' → …' : '';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withAlpha(90),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            loc.periodizationRoutineSequence('${shown.join(' → ')}$suffix'),
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            loc.periodizationRoutineSequenceHelp,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
