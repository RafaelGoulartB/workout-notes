import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/periodization_phase.dart';
import 'package:workout_notes/models/periodization_plan.dart';
import 'package:workout_notes/models/periodization_target.dart';
import 'package:workout_notes/repositories/body_measurement_repository.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';
import 'package:workout_notes/repositories/routine_repository.dart';
import 'package:workout_notes/repositories/settings_repository.dart';
import 'package:workout_notes/widgets/periodization/periodization_ui.dart';

import 'nutrition_goal_suggest_sheet.dart';

class PeriodizationPhaseFormScreen extends StatefulWidget {
  final PeriodizationPlan plan;
  final PeriodizationPhase? phase;

  const PeriodizationPhaseFormScreen({
    super.key,
    required this.plan,
    this.phase,
  });

  @override
  State<PeriodizationPhaseFormScreen> createState() =>
      _PeriodizationPhaseFormScreenState();
}

class _PeriodizationPhaseFormScreenState
    extends State<PeriodizationPhaseFormScreen> {
  final _repository = PeriodizationRepository();
  final _bodyRepository = BodyMeasurementRepository();
  final _settingsRepository = SettingsRepository();
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _intent;
  late final TextEditingController _type;
  final Map<String, TextEditingController> _targetControllers = {};
  late DateTime _startDate;
  late DateTime _endDate;
  int _color = 0xFF4F8EF7;
  bool _shiftFollowing = true;
  bool _saving = false;
  bool _loading = true;
  String? _routineId;
  String? _routineLinkId;
  PeriodizationTarget? _originalTarget;
  List<Map<String, dynamic>> _routines = const [];

  bool get _editing => widget.phase != null;

  @override
  void initState() {
    super.initState();
    final phase = widget.phase;
    _name = TextEditingController(text: phase?.name ?? '');
    _intent = TextEditingController(text: phase?.intent ?? '');
    _type = TextEditingController(text: phase?.templateKey ?? '');
    _startDate = phase?.startDate ?? _suggestedStart();
    _endDate = phase?.endDate ?? _startDate.add(const Duration(days: 27));
    _color = phase?.color ?? _color;
    for (final key in _targetKeys) {
      _targetControllers[key] = TextEditingController();
    }
    _load();
  }

  DateTime _suggestedStart() => DateTime.now().isBefore(widget.plan.startDate)
      ? widget.plan.startDate
      : DateTime.now().isAfter(widget.plan.endDate)
      ? widget.plan.startDate
      : DateTime.now();

  @override
  void dispose() {
    _name.dispose();
    _intent.dispose();
    _type.dispose();
    for (final controller in _targetControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      RoutineRepository().getRoutines(),
      if (_editing) _repository.getEffectiveTarget(widget.phase!.id),
      if (_editing) _repository.getRoutineLinks(widget.phase!.id),
    ]);
    if (!mounted) return;
    _routines = results[0] as List<Map<String, dynamic>>;
    if (_editing) {
      _originalTarget = results[1] as PeriodizationTarget?;
      _fillTarget(_originalTarget);
      final links = results[2] as List<Map<String, dynamic>>;
      if (links.isNotEmpty) {
        _routineId = links.first['routine_id'] as String?;
        _routineLinkId = links.first['id'] as String?;
      }
    }
    setState(() => _loading = false);
  }

  void _fillTarget(PeriodizationTarget? target) {
    if (target == null) return;
    final values = <String, num?>{
      'calories': target.calories,
      'protein': target.proteinG,
      'carbs': target.carbsG,
      'fat': target.fatG,
      'workouts': target.workoutsPerWeek,
      'minSets': target.minSetsPerWeek,
      'maxSets': target.maxSetsPerWeek,
      'minRpe': target.minRpe,
      'maxRpe': target.maxRpe,
      'weight': target.targetWeightKg,
      'change': target.weeklyWeightChangePercent,
      'sleep': target.sleepHours,
    };
    for (final entry in values.entries) {
      _targetControllers[entry.key]!.text = entry.value?.toString() ?? '';
    }
  }

  Future<void> _suggestNutritionTargets() async {
    await NutritionGoalSuggestSheet.show(
      context,
      bodyRepo: _bodyRepository,
      settingsRepo: _settingsRepository,
      onApply: (calories, protein, carbs, fat) {
        if (!mounted) return;
        setState(() {
          _targetControllers['calories']!.text = calories.toStringAsFixed(0);
          _targetControllers['protein']!.text = protein.toStringAsFixed(0);
          _targetControllers['carbs']!.text = carbs.toStringAsFixed(0);
          _targetControllers['fat']!.text = fat.toStringAsFixed(0);
        });
      },
    );
  }

  int _filledTargets(Iterable<String> keys) => keys
      .where((key) => _targetControllers[key]!.text.trim().isNotEmpty)
      .length;

  Future<void> _pickDate(bool start) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: start ? _startDate : _endDate,
      firstDate: widget.plan.startDate,
      lastDate: widget.plan.endDate.add(
        Duration(days: _editing && _shiftFollowing ? 3650 : 0),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (start) {
        final duration = _endDate.difference(_startDate);
        _startDate = picked;
        _endDate = picked.add(duration);
      } else {
        _endDate = picked;
      }
    });
  }

  PeriodizationTarget _buildTarget() => PeriodizationTarget(
    id: '',
    phaseId: widget.phase?.id ?? '',
    version: 0,
    validFrom: DateTime.now(),
    calories: _double('calories'),
    proteinG: _double('protein'),
    carbsG: _double('carbs'),
    fatG: _double('fat'),
    workoutsPerWeek: _int('workouts'),
    minSetsPerWeek: _int('minSets'),
    maxSetsPerWeek: _int('maxSets'),
    minRpe: _double('minRpe'),
    maxRpe: _double('maxRpe'),
    targetWeightKg: _double('weight'),
    weeklyWeightChangePercent: _double('change'),
    sleepHours: _double('sleep'),
    createdAt: DateTime.now(),
  );

  double? _double(String key) => double.tryParse(
    _targetControllers[key]!.text.trim().replaceAll(',', '.'),
  );
  int? _int(String key) => int.tryParse(_targetControllers[key]!.text.trim());

  bool _targetChanged(PeriodizationTarget target) {
    final old = _originalTarget;
    if (old == null) return !target.isEmpty;
    return target.nutritionJson.toString() != old.nutritionJson.toString() ||
        target.trainingJson.toString() != old.trainingJson.toString() ||
        target.bodyJson.toString() != old.bodyJson.toString() ||
        target.sleepJson.toString() != old.sleepJson.toString();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_endDate.isBefore(_startDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.periodizationOverlapError,
          ),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final target = _buildTarget();
      if (_editing) {
        final old = widget.phase!;
        final updated = PeriodizationPhase(
          id: old.id,
          planId: old.planId,
          name: _name.text.trim(),
          templateKey: _type.text.trim().isEmpty ? null : _type.text.trim(),
          color: _color,
          startDate: _startDate,
          endDate: _endDate,
          intent: _intent.text.trim().isEmpty ? null : _intent.text.trim(),
          orderIndex: old.orderIndex,
          createdAt: old.createdAt,
          updatedAt: DateTime.now(),
        );
        await _repository.updatePhaseWithTargetAndRoutine(
          updated,
          shiftFollowingPhases: _shiftFollowing,
          targetChanged: _targetChanged(target),
          target: target,
          routineId: _routineId,
          routineLinkId: _routineLinkId,
        );
      } else {
        await _repository.addPhase(
          planId: widget.plan.id,
          name: _name.text,
          startDate: _startDate,
          endDate: _endDate,
          color: _color,
          intent: _intent.text,
          templateKey: _type.text.trim().isEmpty ? null : _type.text.trim(),
          target: target.isEmpty ? null : target,
          routineId: _routineId,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      final loc = AppLocalizations.of(context)!;
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

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _editing ? loc.periodizationEditPhase : loc.periodizationNewPhase,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      bottomNavigationBar: _loading
          ? null
          : PeriodizationBottomBar(
              primary: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text(loc.commonSave),
              ),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  PeriodizationSurface(
                    accentColor: Color(_color),
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
                                color: Color(_color).withAlpha(35),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                Icons.flag_rounded,
                                color: Color(_color),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    loc.periodizationPhaseIdentity,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    loc.periodizationPhaseIdentityHelp,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        TextFormField(
                          controller: _name,
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
                          controller: _type,
                          decoration: InputDecoration(
                            labelText: loc.periodizationPhaseType,
                            hintText: loc.periodizationPhaseTypeHint,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _intent,
                          maxLines: 3,
                          decoration: InputDecoration(
                            labelText: loc.periodizationIntent,
                            hintText: loc.periodizationIntentHint,
                            alignLabelWithHint: true,
                          ),
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
                                date: _startDate,
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
                                date: _endDate,
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
                                loc.periodizationPhaseDuration(
                                  (_endDate.difference(_startDate).inDays + 1)
                                      .clamp(1, 9999),
                                ),
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
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  PeriodizationSurface(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          loc.periodizationColor,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 10,
                          children: _colors
                              .map(
                                (value) => Semantics(
                                  button: true,
                                  selected: _color == value,
                                  child: InkWell(
                                    onTap: () => setState(() => _color = value),
                                    borderRadius: BorderRadius.circular(24),
                                    child: CircleAvatar(
                                      radius: 22,
                                      backgroundColor: Color(value),
                                      child: _color == value
                                          ? const Icon(
                                              Icons.check,
                                              color: Colors.white,
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
                  if (_editing) ...[
                    const SizedBox(height: 10),
                    PeriodizationSurface(
                      padding: EdgeInsets.zero,
                      child: SwitchListTile(
                        value: _shiftFollowing,
                        onChanged: (value) =>
                            setState(() => _shiftFollowing = value),
                        secondary: const Icon(Icons.low_priority_rounded),
                        title: Text(loc.periodizationShiftFollowing),
                        subtitle: Text(loc.periodizationShiftFollowingHelp),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  PeriodizationSectionHeader(
                    title: loc.periodizationTargets,
                    subtitle: loc.periodizationOptionalTargets,
                    icon: Icons.track_changes_rounded,
                  ),
                  _AutomaticTargetsCard(onTap: _suggestNutritionTargets),
                  const SizedBox(height: 10),
                  _targetCard(
                    loc.periodizationNutritionTargets,
                    Icons.restaurant_outlined,
                    [
                      _field(
                        'calories',
                        loc.periodizationCaloriesPerDay,
                        unit: 'kcal',
                      ),
                      _field('protein', loc.periodizationProteinG, unit: 'g'),
                      _field('carbs', loc.periodizationCarbsG, unit: 'g'),
                      _field('fat', loc.periodizationFatG, unit: 'g'),
                    ],
                    keys: const ['calories', 'protein', 'carbs', 'fat'],
                    subtitle: loc.periodizationNutritionTargetsHelp,
                    actionLabel: loc.periodizationSuggestTargets,
                    onAction: _suggestNutritionTargets,
                    initiallyExpanded: true,
                  ),
                  _targetCard(
                    loc.periodizationTrainingTargets,
                    Icons.fitness_center,
                    [
                      _field(
                        'workouts',
                        loc.periodizationWorkoutsPerWeek,
                        integer: true,
                        unit: loc.periodizationPerWeekUnit,
                      ),
                      _field(
                        'minSets',
                        loc.periodizationMinSets,
                        integer: true,
                        unit: loc.periodizationPerWeekUnit,
                      ),
                      _field(
                        'maxSets',
                        loc.periodizationMaxSets,
                        integer: true,
                        unit: loc.periodizationPerWeekUnit,
                      ),
                      _field('minRpe', loc.periodizationMinRpe),
                      _field('maxRpe', loc.periodizationMaxRpe),
                    ],
                    keys: const [
                      'workouts',
                      'minSets',
                      'maxSets',
                      'minRpe',
                      'maxRpe',
                    ],
                    subtitle: loc.periodizationTrainingTargetsHelp,
                  ),
                  _targetCard(
                    loc.periodizationBodyTargets,
                    Icons.monitor_weight_outlined,
                    [
                      _field(
                        'weight',
                        loc.periodizationTargetWeight,
                        unit: 'kg',
                      ),
                      _field(
                        'change',
                        loc.periodizationWeeklyWeightChange,
                        signed: true,
                        unit: '%',
                      ),
                    ],
                    keys: const ['weight', 'change'],
                    subtitle: loc.periodizationBodyTargetsHelp,
                  ),
                  _targetCard(
                    loc.periodizationSleepTargets,
                    Icons.nightlight_outlined,
                    [_field('sleep', loc.periodizationSleepHours, unit: 'h')],
                    keys: const ['sleep'],
                    subtitle: loc.periodizationSleepTargetsHelp,
                  ),
                  const SizedBox(height: 8),
                  PeriodizationSectionHeader(
                    title: loc.periodizationLinkedRoutine,
                    icon: Icons.repeat_rounded,
                  ),
                  DropdownButtonFormField<String?>(
                    initialValue: _routineId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: loc.periodizationLinkedRoutine,
                      prefixIcon: const Icon(Icons.fitness_center_outlined),
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(
                          loc.periodizationNoRoutine,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      ..._routines.map(
                        (routine) => DropdownMenuItem<String?>(
                          value: routine['id'] as String,
                          child: Text(
                            routine['name'] as String,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) => setState(() => _routineId = value),
                  ),
                  if (_editing) ...[
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

  Widget _targetCard(
    String title,
    IconData icon,
    List<Widget> children, {
    required List<String> keys,
    required String subtitle,
    String? actionLabel,
    VoidCallback? onAction,
    bool initiallyExpanded = false,
  }) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final filled = _filledTargets(keys);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PeriodizationSurface(
        padding: EdgeInsets.zero,
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.fromLTRB(14, 5, 12, 5),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
          shape: const Border(),
          collapsedShape: const Border(),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withAlpha(125),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: theme.colorScheme.primary),
          ),
          title: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          subtitle: Text(
            filled == 0
                ? subtitle
                : loc.periodizationTargetsConfigured(filled, keys.length),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: filled == 0
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.primary,
              fontWeight: filled == 0 ? null : FontWeight.w700,
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
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth >= 560
                    ? (constraints.maxWidth - 10) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: 10,
                  runSpacing: 12,
                  children: children
                      .map((child) => SizedBox(width: width, child: child))
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    String key,
    String label, {
    bool integer = false,
    bool signed = false,
    String? unit,
  }) => TextField(
    controller: _targetControllers[key],
    onChanged: (_) => setState(() {}),
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

class _AutomaticTargetsCard extends StatelessWidget {
  final VoidCallback onTap;

  const _AutomaticTargetsCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              theme.colorScheme.primaryContainer,
              theme.colorScheme.tertiaryContainer.withAlpha(160),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withAlpha(175),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loc.periodizationAutomaticTargets,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        loc.periodizationAutomaticTargetsHelp,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer.withAlpha(
                            190,
                          ),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_rounded,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const _targetKeys = [
  'calories',
  'protein',
  'carbs',
  'fat',
  'workouts',
  'minSets',
  'maxSets',
  'minRpe',
  'maxRpe',
  'weight',
  'change',
  'sleep',
];

const _colors = <int>[
  0xFF4F8EF7,
  0xFFF5B942,
  0xFF9B6BE8,
  0xFF43B581,
  0xFFE85858,
  0xFF26A6A1,
];
