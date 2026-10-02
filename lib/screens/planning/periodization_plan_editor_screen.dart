import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/nutrition/nutrition_goal.dart';
import 'package:workout_notes/models/periodization_phase.dart';
import 'package:workout_notes/models/periodization_plan.dart';
import 'package:workout_notes/models/periodization_schedule.dart';
import 'package:workout_notes/models/periodization_target.dart';
import 'package:workout_notes/periodization/phase_kind.dart';
import 'package:workout_notes/periodization/phase_seed.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';
import 'package:workout_notes/utils/date_utils.dart';
import 'package:workout_notes/widgets/periodization/plan_overview.dart';
import 'package:workout_notes/widgets/periodization/planning_widgets.dart';
import 'package:workout_notes/widgets/ui/guarded_load.dart';
import 'package:workout_notes/widgets/ui/load_error_view.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Creates or re-plans a plan: its name, the Monday it starts and the
/// ordered list of phases, each lasting a number of weeks. Phases are laid
/// back to back, so dates follow from the order and the lengths.
///
/// Pops with the plan id when something was saved.
class PeriodizationPlanEditorScreen extends StatefulWidget {
  /// Plan to edit; null creates a new one.
  final PeriodizationPlan? plan;

  /// Shape to start a new plan from.
  final PlanBlueprint blueprint;

  const PeriodizationPlanEditorScreen({
    super.key,
    this.plan,
    this.blueprint = PlanBlueprint.recomposition,
  });

  @override
  State<PeriodizationPlanEditorScreen> createState() =>
      _PeriodizationPlanEditorScreenState();
}

class _EditablePhase {
  final Key key = UniqueKey();
  PhaseScheduleEntry entry;
  final PhaseKind kind;

  _EditablePhase(this.entry, this.kind);
}

class _PeriodizationPlanEditorScreenState extends State<PeriodizationPlanEditorScreen> with GuardedLoad {
  final _repository = DatabaseHelper.instance.periodizationRepo;
  final _name = TextEditingController();
  late DateTime _start;
  final List<_EditablePhase> _phases = [];
  List<PeriodizationPhase> _originalPhases = const [];
  PlanBlueprint? _blueprint;
  bool _activate = true;
  bool _hasActivePlan = false;
  bool _saving = false;
  double? _tdee;
  double? _weightKg;

  /// Training setup new phases start from (the last phase's), so adding a
  /// phase never loses the routine and weekdays already planned.
  PeriodizationTarget? _trainingSeed;

  bool get _creating => widget.plan == null;

  @override
  void initState() {
    super.initState();
    _start = _nextMonday(DateTime.now());
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  static DateTime _nextMonday(DateTime date) {
    final day = dayOf(date);
    if (day.weekday == DateTime.monday) return day;
    return addDays(day, 8 - day.weekday);
  }

  Future<void> _load() => guardedLoad(() async {
    _phases.clear();
    final results = await Future.wait<Object?>([
      DatabaseHelper.instance.nutritionRepo.getActiveGoal(),
      DatabaseHelper.instance.bodyMeasurementRepo.getLatestWeightKg(),
      _repository.getActivePlan(),
    ]);
    _tdee = (results[0] as NutritionGoal?)?.tdee;
    _weightKg = results[1] as double?;
    final active = results[2] as PeriodizationPlan?;
    _hasActivePlan = active != null && active.id != widget.plan?.id;
    _activate = !_hasActivePlan;
    final plan = widget.plan;
    if (plan != null) {
      _name.text = plan.name;
      final phases = await _repository.getPhases(plan.id);
      _originalPhases = phases;
      if (phases.isNotEmpty) _start = phases.first.startDate;
      for (final phase in phases) {
        _phases.add(
          _EditablePhase(
            PhaseScheduleEntry(
              id: phase.id,
              name: phase.name,
              templateKey: phase.templateKey ?? PhaseKind.custom.key,
              color: phase.color,
              intent: phase.intent,
              weeks: phase.totalWeeks,
            ),
            PhaseKind.fromKey(phase.templateKey),
          ),
        );
      }
      if (phases.isNotEmpty) {
        _trainingSeed = await _repository.getEffectiveTarget(
          phases.last.id,
          date: phases.last.endDate,
        );
      }
    }
    if (!mounted) return;
    if (_creating) _applyBlueprint(widget.blueprint);
    setState(() => isLoading = false);
  });

  void _applyBlueprint(PlanBlueprint blueprint) {
    final loc = AppLocalizations.of(context)!;
    _blueprint = blueprint;
    _name.text = '${blueprint.label(loc)} ${_start.year}';
    _phases
      ..clear()
      ..addAll(
        blueprint.phases.map(
          (phase) => _EditablePhase(
            _newEntry(phase.kind, phase.nameFor(loc), phase.weeks),
            phase.kind,
          ),
        ),
      );
  }

  PhaseScheduleEntry _newEntry(PhaseKind kind, String name, int weeks) =>
      PhaseScheduleEntry(
        name: name,
        templateKey: kind.key,
        color: kind.color,
        weeks: weeks,
        seedTarget: _seedTarget(kind),
      );

  PeriodizationTarget? _seedTarget(PhaseKind kind) => seedTargetForKind(
    kind,
    tdee: _tdee,
    weightKg: _weightKg,
    training: _trainingSeed,
  );

  Future<void> _pickStart() async {
    final loc = AppLocalizations.of(context)!;
    final initial = _start;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: loc.planningStartMonday,
      selectableDayPredicate: (day) =>
          day.weekday == DateTime.monday || DateUtils.isSameDay(day, initial),
    );
    if (picked != null && mounted) setState(() => _start = picked);
  }

  Future<void> _addPhase() async {
    final kind = await pickPhaseKind(context);
    if (kind == null || !mounted) return;
    final loc = AppLocalizations.of(context)!;
    setState(() {
      _phases.add(_EditablePhase(_newEntry(kind, kind.label(loc), 4), kind));
      _blueprint = null;
    });
  }

  Future<void> _renamePhase(_EditablePhase phase) async {
    final loc = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: phase.entry.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(loc.planningRenamePhase),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: loc.planningPhaseNameHint),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(loc.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(loc.planningApply),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty || !mounted) return;
    setState(() => phase.entry = phase.entry.copyWith(name: name.trim()));
  }

  Future<void> _save() async {
    final loc = AppLocalizations.of(context)!;
    if (_name.text.trim().isEmpty) {
      showAppSnack(context, loc.planningNameRequired);
      return;
    }
    if (_phases.isEmpty) {
      showAppSnack(context, loc.planningPlanNeedsPhase);
      return;
    }
    final removed = _originalPhases
        .where((phase) => !_phases.any((item) => item.entry.id == phase.id))
        .toList();
    if (removed.isNotEmpty) {
      final confirmed = await showConfirmDialog(
        context,
        title: loc.planningRemovePhasesTitle,
        message: loc.planningRemovePhasesBody(
              removed.map((phase) => phase.name).join(', '),
            ),
        confirmLabel: loc.planningDelete,
        destructive: true,
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() => _saving = true);
    try {
      final entries = _phases.map((phase) => phase.entry).toList();
      String planId;
      if (_creating) {
        final plan = await _repository.createChainedPlan(
          name: _name.text,
          startDate: _start,
          phases: entries,
          activate: _activate,
        );
        planId = plan.id;
      } else {
        planId = widget.plan!.id;
        await _repository.replanPlan(
          planId: planId,
          name: _name.text,
          notes: widget.plan!.notes,
          startDate: _start,
          phases: entries,
        );
      }
      if (mounted) Navigator.pop(context, planId);
    } on PeriodizationValidationException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppSnack(context, planningErrorMessage(loc, error.code));
    }
  }

  /// Phases as they will be saved, for the roadmap preview.
  List<PeriodizationPhase> get _preview {
    final ranges = PeriodizationRepository.chainPhaseRanges(
      _start,
      _phases.map((phase) => phase.entry.weeks),
    );
    final now = DateTime.now();
    return [
      for (var i = 0; i < _phases.length; i++)
        PeriodizationPhase(
          id: '$i',
          planId: '',
          name: _phases[i].entry.name,
          templateKey: _phases[i].entry.templateKey,
          color: _phases[i].entry.color,
          startDate: ranges[i].start,
          endDate: ranges[i].end,
          orderIndex: i,
          createdAt: now,
          updatedAt: now,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final preview = isLoading ? const <PeriodizationPhase>[] : _preview;
    final totalWeeks = _phases.fold<int>(0, (sum, p) => sum + p.entry.weeks);
    final dateFormat = DateFormat('EEE, d MMM y', Intl.defaultLocale);
    return Scaffold(
      appBar: AppBar(
        title: Text(_creating ? loc.planningNewPlan : loc.planningEditPlan),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : loadFailed
          ? LoadErrorView(onRetry: _load)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (_creating) ...[
                  PlanningSectionLabel(
                    loc.planningStartFrom,
                    icon: Icons.auto_awesome_mosaic_outlined,
                  ),
                  BlueprintGrid(
                    selected: _blueprint,
                    onTap: (blueprint) =>
                        setState(() => _applyBlueprint(blueprint)),
                  ),
                ],
                PlanningSectionLabel(
                  loc.planningPlan,
                  icon: Icons.route_outlined,
                ),
                PlanningCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        key: const Key('planEditorName'),
                        controller: _name,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          labelText: loc.planningPlanName,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Material(
                        color: scheme.surfaceContainerHighest.withAlpha(90),
                        borderRadius: BorderRadius.circular(12),
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          leading: const Icon(Icons.event_outlined),
                          title: Text(loc.planningStartsOn),
                          subtitle: Text(dateFormat.format(_start)),
                          trailing: const Icon(Icons.edit_calendar_outlined),
                          onTap: _pickStart,
                        ),
                      ),
                      if (_creating && _hasActivePlan) ...[
                        const SizedBox(height: 4),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _activate,
                          onChanged: (value) =>
                              setState(() => _activate = value),
                          title: Text(loc.planningActivateNow),
                          subtitle: Text(loc.planningActivateReplaces),
                        ),
                      ],
                    ],
                  ),
                ),
                PlanningSectionLabel(
                  loc.planningPhasesCount(_phases.length),
                  icon: Icons.view_timeline_outlined,
                ),
                if (preview.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                    child: PlanRoadmap(phases: preview, today: DateTime.now()),
                  ),
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: _phases.length,
                  onReorderItem: (from, to) => setState(() {
                    _phases.insert(to, _phases.removeAt(from));
                    _blueprint = null;
                  }),
                  itemBuilder: (context, index) {
                    final phase = _phases[index];
                    return Padding(
                      key: phase.key,
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _PhaseTile(
                        index: index,
                        phase: phase,
                        range: preview.length > index ? preview[index] : null,
                        onRename: () => _renamePhase(phase),
                        onWeeks: (weeks) => setState(
                          () =>
                              phase.entry = phase.entry.copyWith(weeks: weeks),
                        ),
                        onRemove: _phases.length > 1
                            ? () => setState(() {
                                _phases.remove(phase);
                                _blueprint = null;
                              })
                            : null,
                      ),
                    );
                  },
                ),
                OutlinedButton.icon(
                  key: const Key('planEditorAddPhase'),
                  onPressed: _addPhase,
                  icon: const Icon(Icons.add_rounded),
                  label: Text(loc.planningAddPhase),
                ),
                const SizedBox(height: 16),
                if (preview.isNotEmpty)
                  Text(
                    loc.planningPlanSummary(
                      totalWeeks,
                      DateFormat(
                        'd MMM y',
                        Intl.defaultLocale,
                      ).format(preview.last.endDate),
                    ),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                if (_creating) ...[
                  const SizedBox(height: 8),
                  Text(
                    loc.planningCreateHint,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
      bottomNavigationBar: isLoading || loadFailed
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: FilledButton.icon(
                key: const Key('planEditorSave'),
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                icon: const Icon(Icons.check_rounded),
                label: Text(
                  _creating ? loc.planningCreatePlan : loc.planningSave,
                ),
              ),
            ),
    );
  }
}

class _PhaseTile extends StatelessWidget {
  final int index;
  final _EditablePhase phase;
  final PeriodizationPhase? range;
  final VoidCallback onRename;
  final ValueChanged<int> onWeeks;
  final VoidCallback? onRemove;

  const _PhaseTile({
    required this.index,
    required this.phase,
    required this.range,
    required this.onRename,
    required this.onWeeks,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final entry = phase.entry;
    return PlanningCard(
      padding: const EdgeInsets.fromLTRB(4, 10, 8, 10),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Icon(
                Icons.drag_indicator_rounded,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          PhaseAvatar(color: Color(entry.color), icon: phase.kind.icon),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              onTap: onRename,
              borderRadius: BorderRadius.circular(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (range != null)
                    Text(
                      planningDateRange(range!.startDate, range!.endDate),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
          PlanningStepper(
            value: loc.planningWeeksShort(entry.weeks),
            onDecrement: entry.weeks > 1
                ? () => onWeeks(entry.weeks - 1)
                : null,
            onIncrement: entry.weeks < 104
                ? () => onWeeks(entry.weeks + 1)
                : null,
          ),
          if (onRemove != null)
            IconButton(
              tooltip: loc.planningRemovePhase,
              onPressed: onRemove,
              icon: const Icon(Icons.close_rounded, size: 20),
            ),
        ],
      ),
    );
  }
}

/// Bottom sheet listing the phase kinds; returns the one picked.
Future<PhaseKind?> pickPhaseKind(BuildContext context) {
  final loc = AppLocalizations.of(context)!;
  return showModalBottomSheet<PhaseKind>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              loc.planningPickPhaseKind,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          for (final kind in PhaseKind.values)
            ListTile(
              leading: PhaseAvatar(color: Color(kind.color), icon: kind.icon),
              title: Text(kind.label(loc)),
              subtitle: Text(kind.description(loc)),
              onTap: () => Navigator.pop(context, kind),
            ),
        ],
      ),
    ),
  );
}
