import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/periodization_phase.dart';
import 'package:workout_notes/models/periodization_plan.dart';
import 'package:workout_notes/models/periodization_target.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';
import 'package:workout_notes/repositories/routine_repository.dart';

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
        await _repository.updatePhase(
          updated,
          shiftFollowingPhases: _shiftFollowing,
        );
        if (_targetChanged(target)) {
          await _repository.saveTargetVersion(old.id, target);
        }
        if (_routineId == null && _routineLinkId != null) {
          await _repository.deleteRoutineLink(_routineLinkId!);
        } else if (_routineId != null) {
          await _repository.saveRoutineLink(
            id: _routineLinkId,
            phaseId: old.id,
            routineId: _routineId!,
            startsOn: _startDate,
            endsOn: _endDate,
          );
        }
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
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _editing ? loc.periodizationEditPhase : loc.periodizationNewPhase,
        ),
        actions: [
          TextButton(
            onPressed: _saving || _loading ? null : _save,
            child: Text(loc.commonSave),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                children: [
                  TextFormField(
                    controller: _name,
                    decoration: InputDecoration(
                      labelText: loc.periodizationPhaseName,
                      border: const OutlineInputBorder(),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? loc.periodizationPhaseName
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _type,
                    decoration: InputDecoration(
                      labelText: loc.periodizationPhaseType,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _intent,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: loc.periodizationIntent,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _DateTile(
                          label: loc.periodizationStartDate,
                          date: _startDate,
                          onTap: () => _pickDate(true),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _DateTile(
                          label: loc.periodizationEndDate,
                          date: _endDate,
                          onTap: () => _pickDate(false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    loc.periodizationColor,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    children: _colors
                        .map(
                          (value) => InkWell(
                            onTap: () => setState(() => _color = value),
                            borderRadius: BorderRadius.circular(24),
                            child: CircleAvatar(
                              backgroundColor: Color(value),
                              child: _color == value
                                  ? const Icon(Icons.check, color: Colors.white)
                                  : null,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  if (_editing) ...[
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _shiftFollowing,
                      onChanged: (value) =>
                          setState(() => _shiftFollowing = value),
                      title: Text(loc.periodizationShiftFollowing),
                      subtitle: Text(loc.periodizationShiftFollowingHelp),
                    ),
                  ],
                  const SizedBox(height: 20),
                  _sectionTitle(
                    loc.periodizationNutritionTargets,
                    Icons.restaurant_outlined,
                  ),
                  _grid([
                    _field('calories', loc.periodizationCaloriesPerDay),
                    _field('protein', loc.periodizationProteinG),
                    _field('carbs', loc.periodizationCarbsG),
                    _field('fat', loc.periodizationFatG),
                  ]),
                  _sectionTitle(
                    loc.periodizationTrainingTargets,
                    Icons.fitness_center,
                  ),
                  _grid([
                    _field(
                      'workouts',
                      loc.periodizationWorkoutsPerWeek,
                      integer: true,
                    ),
                    _field('minSets', loc.periodizationMinSets, integer: true),
                    _field('maxSets', loc.periodizationMaxSets, integer: true),
                    _field('minRpe', loc.periodizationMinRpe),
                    _field('maxRpe', loc.periodizationMaxRpe),
                  ]),
                  _sectionTitle(
                    loc.periodizationBodyTargets,
                    Icons.monitor_weight_outlined,
                  ),
                  _grid([
                    _field('weight', loc.periodizationTargetWeight),
                    _field(
                      'change',
                      loc.periodizationWeeklyWeightChange,
                      signed: true,
                    ),
                  ]),
                  _sectionTitle(
                    loc.periodizationSleepTargets,
                    Icons.nightlight_outlined,
                  ),
                  _grid([_field('sleep', loc.periodizationSleepHours)]),
                  const SizedBox(height: 18),
                  DropdownButtonFormField<String?>(
                    initialValue: _routineId,
                    decoration: InputDecoration(
                      labelText: loc.periodizationLinkedRoutine,
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(loc.periodizationNoRoutine),
                      ),
                      ..._routines.map(
                        (routine) => DropdownMenuItem<String?>(
                          value: routine['id'] as String,
                          child: Text(routine['name'] as String),
                        ),
                      ),
                    ],
                    onChanged: (value) => setState(() => _routineId = value),
                  ),
                  if (_editing) ...[
                    const SizedBox(height: 12),
                    Text(
                      loc.periodizationVersionedTarget,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _sectionTitle(String text, IconData icon) => Padding(
    padding: const EdgeInsets.only(top: 22, bottom: 10),
    child: Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Text(text, style: Theme.of(context).textTheme.titleMedium),
      ],
    ),
  );

  Widget _grid(List<Widget> children) => GridView.count(
    crossAxisCount: 2,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    mainAxisSpacing: 10,
    crossAxisSpacing: 10,
    childAspectRatio: 2.3,
    children: children,
  );

  Widget _field(
    String key,
    String label, {
    bool integer = false,
    bool signed = false,
  }) => TextField(
    controller: _targetControllers[key],
    keyboardType: TextInputType.numberWithOptions(
      decimal: !integer,
      signed: signed,
    ),
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
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
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 5),
            Text(DateFormat.yMMMd(Intl.defaultLocale).format(date)),
          ],
        ),
      ),
    ),
  );
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
