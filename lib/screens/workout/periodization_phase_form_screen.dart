import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/periodization_phase.dart';
import 'package:workout_notes/models/periodization_plan.dart';
import 'package:workout_notes/models/periodization_target.dart';
import 'package:workout_notes/repositories/body_measurement_repository.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';
import 'package:workout_notes/repositories/routine_repository.dart';
import 'package:workout_notes/repositories/settings_repository.dart';
import 'package:workout_notes/utils/macro_calculator.dart';
import 'package:workout_notes/widgets/periodization/nutrition_target_fields.dart';
import 'package:workout_notes/widgets/periodization/periodization_ui.dart';
import 'package:workout_notes/widgets/periodization/phase_week_selector.dart';

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
  List<Map<String, dynamic>> _routines = const [];
  double? _latestWeight;
  List<PeriodizationTarget> _history = const [];

  late List<DateTime> _weekStarts;
  late List<PeriodizationTarget?> _weekOverrides;
  int _selectedWeek = 0;
  final Set<int> _conflictWeeks = {};

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
    _weekStarts = _computeWeekStarts(_startDate, _endDate);
    _weekOverrides = List<PeriodizationTarget?>.filled(
      _weekStarts.length,
      null,
    );
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
    final weightFuture = _bodyRepository.getLatestWeightKg();
    final results = await Future.wait([
      RoutineRepository().getRoutines(),
      if (_editing) _repository.getTargetHistory(widget.phase!.id),
      if (_editing) _repository.getRoutineLinks(widget.phase!.id),
    ]);
    if (!mounted) return;
    _routines = results[0] as List<Map<String, dynamic>>;
    if (_editing) {
      _history = results[1] as List<PeriodizationTarget>;
      _reconstructOverrides();
      final links = results[2] as List<Map<String, dynamic>>;
      if (links.isNotEmpty) {
        _routineId = links.first['routine_id'] as String?;
        _routineLinkId = links.first['id'] as String?;
      }
      final editableFrom = _editableFromIndex();
      _selectedWeek = (editableFrom < _weekStarts.length
              ? editableFrom
              : _weekStarts.length - 1)
          .clamp(0, _weekStarts.length - 1);
    }
    _latestWeight = await weightFuture;
    if (!mounted) return;
    _loadIntoControllers(_effectiveTarget(_selectedWeek));
    setState(() => _loading = false);
  }

  // =====================================================================
  // Week model: `_weekOverrides[i]` holds week i's own target or null when
  // it inherits from the nearest previous override (week 0 is the base).
  // =====================================================================

  List<DateTime> _computeWeekStarts(DateTime start, DateTime end) {
    final days = end.difference(start).inDays + 1;
    final count = (days / 7).ceil().clamp(1, 200);
    return [
      for (var i = 0; i < count; i++)
        _day(start).add(Duration(days: 7 * i)),
    ];
  }

  DateTime _weekEnd(int index) {
    final nominal = _weekStarts[index].add(const Duration(days: 6));
    final last = index == _weekStarts.length - 1;
    return last && nominal.isAfter(_endDate) ? _endDate : nominal;
  }

  PeriodizationTarget? _effectiveTarget(int index) {
    for (var i = index; i >= 0; i--) {
      if (_weekOverrides[i] != null) return _weekOverrides[i];
    }
    return null;
  }

  void _reconstructOverrides() {
    for (var i = 0; i < _weekStarts.length; i++) {
      final effective = _targetForDate(_history, _weekStarts[i]);
      final previous = i == 0
          ? null
          : _targetForDate(_history, _weekStarts[i - 1]);
      if (effective != null && !_targetsEquivalent(effective, previous)) {
        _weekOverrides[i] = _copyOf(effective, _weekStarts[i]);
      }
    }
  }

  PeriodizationTarget? _targetForDate(
    List<PeriodizationTarget> targets,
    DateTime date,
  ) {
    final eligible =
        targets.where((target) => !target.validFrom.isAfter(date)).toList()
          ..sort((a, b) {
            final byDate = b.validFrom.compareTo(a.validFrom);
            return byDate == 0 ? b.version.compareTo(a.version) : byDate;
          });
    if (eligible.isNotEmpty) return eligible.first;
    if (targets.isEmpty) return null;
    final oldest = [...targets]..sort((a, b) => a.version.compareTo(b.version));
    return oldest.first;
  }

  PeriodizationTarget _copyOf(PeriodizationTarget source, DateTime validFrom) =>
      source.copyWith(id: '', version: 0, validFrom: validFrom);

  static bool _targetsEquivalent(
    PeriodizationTarget? a,
    PeriodizationTarget? b,
  ) {
    final emptyA = a == null || a.isEmpty;
    final emptyB = b == null || b.isEmpty;
    if (emptyA && emptyB) return true;
    if (a == null || b == null) return false;
    return a.nutritionJson.toString() == b.nutritionJson.toString() &&
        a.trainingJson.toString() == b.trainingJson.toString() &&
        a.bodyJson.toString() == b.bodyJson.toString() &&
        a.sleepJson.toString() == b.sleepJson.toString();
  }

  Set<int> _lockedWeeks() {
    if (!_editing) return const {};
    final today = _dayOnly(DateTime.now());
    return {
      for (var i = 0; i < _weekStarts.length; i++)
        if (_weekEnd(i).isBefore(today)) i,
    };
  }

  int _editableFromIndex() {
    if (!_editing) return 0;
    final today = _dayOnly(DateTime.now());
    for (var i = 0; i < _weekStarts.length; i++) {
      if (!_weekEnd(i).isBefore(today)) return i;
    }
    return _weekStarts.length;
  }

  int? _currentWeekIndex() {
    final today = _dayOnly(DateTime.now());
    for (var i = 0; i < _weekStarts.length; i++) {
      if (!_weekStarts[i].isAfter(today) && !_weekEnd(i).isBefore(today)) {
        return i;
      }
    }
    return null;
  }

  // =====================================================================
  // Week editing (commit-on-switch model)
  // =====================================================================

  void _selectWeek(int index) {
    if (index == _selectedWeek) return;
    _commitSelectedWeek();
    setState(() {
      _selectedWeek = index;
      _loadIntoControllers(_effectiveTarget(index));
    });
  }

  void _commitSelectedWeek() {
    if (_weekStarts.isEmpty || _lockedWeeks().contains(_selectedWeek)) return;
    final target = _buildTargetForWeek(_selectedWeek);
    _weekOverrides[_selectedWeek] = target;
    _updateConflict(_selectedWeek);
  }

  PeriodizationTarget _buildTargetForWeek(int index) {
    final previous = _effectiveTarget(index);
    final validFrom = _weekStarts[index];
    final hasNutritionInput = ['calories', 'proteinPerKg', 'fatPerKg', 'refWeight']
        .any((key) => _targetControllers[key]!.text.trim().isNotEmpty);
    double? calories;
    double? proteinG;
    double? carbsG;
    double? fatG;
    double? proteinGPerKg;
    double? fatGPerKg;
    double? weightKgUsed;
    final kcal = NutritionTargetFields.parseField(_targetControllers['calories']!);
    final protein = NutritionTargetFields.parseField(
      _targetControllers['proteinPerKg']!,
    );
    final fat = NutritionTargetFields.parseField(_targetControllers['fatPerKg']!);
    final weight = NutritionTargetFields.parseField(
      _targetControllers['refWeight']!,
    );
    if (hasNutritionInput && kcal != null && protein != null && fat != null && weight != null) {
      final breakdown = computeMacros(
        calories: kcal,
        proteinPerKg: protein,
        fatPerKg: fat,
        weightKg: weight,
      );
      calories = breakdown.calories;
      proteinG = breakdown.proteinG;
      fatG = breakdown.fatG;
      carbsG = breakdown.carbsG;
      proteinGPerKg = protein;
      fatGPerKg = fat;
      weightKgUsed = weight;
    } else {
      // Partial nutrition input keeps the previous values (legacy absolute
      // grams survive until the user completes the g/kg fields).
      calories = previous?.calories;
      proteinG = previous?.proteinG;
      carbsG = previous?.carbsG;
      fatG = previous?.fatG;
      proteinGPerKg = previous?.proteinGPerKg;
      fatGPerKg = previous?.fatGPerKg;
      weightKgUsed = previous?.weightKgUsed;
    }
    return PeriodizationTarget(
      id: '',
      phaseId: widget.phase?.id ?? '',
      version: 0,
      validFrom: validFrom,
      calories: calories,
      proteinG: proteinG,
      carbsG: carbsG,
      fatG: fatG,
      proteinGPerKg: proteinGPerKg,
      fatGPerKg: fatGPerKg,
      weightKgUsed: weightKgUsed,
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
  }

  void _updateConflict(int index) {
    final kcal = NutritionTargetFields.parseField(_targetControllers['calories']!);
    final protein = NutritionTargetFields.parseField(
      _targetControllers['proteinPerKg']!,
    );
    final fat = NutritionTargetFields.parseField(_targetControllers['fatPerKg']!);
    final weight = NutritionTargetFields.parseField(
      _targetControllers['refWeight']!,
    );
    final hasInput = ['calories', 'proteinPerKg', 'fatPerKg', 'refWeight']
        .any((key) => _targetControllers[key]!.text.trim().isNotEmpty);
    if (hasInput &&
        kcal != null &&
        protein != null &&
        fat != null &&
        weight != null) {
      final breakdown = computeMacros(
        calories: kcal,
        proteinPerKg: protein,
        fatPerKg: fat,
        weightKg: weight,
      );
      breakdown.energyConflict
          ? _conflictWeeks.add(index)
          : _conflictWeeks.remove(index);
    } else {
      _conflictWeeks.remove(index);
    }
  }

  void _onTargetChanged() {
    if (_lockedWeeks().contains(_selectedWeek)) return;
    setState(() => _commitSelectedWeek());
  }

  void _customizeSelectedWeek() {
    _commitSelectedWeek();
    if (_weekOverrides[_selectedWeek] == null) {
      final effective = _effectiveTarget(_selectedWeek);
      _weekOverrides[_selectedWeek] = effective == null
          ? _buildTargetForWeek(_selectedWeek)
          : _copyOf(effective, _weekStarts[_selectedWeek]);
    }
    setState(() {});
  }

  void _useInheritance() {
    setState(() {
      _weekOverrides[_selectedWeek] = null;
      _conflictWeeks.remove(_selectedWeek);
      _loadIntoControllers(_effectiveTarget(_selectedWeek));
    });
  }

  void _applyToFollowingWeeks() {
    _commitSelectedWeek();
    final source = _effectiveTarget(_selectedWeek);
    setState(() {
      for (var j = _selectedWeek + 1; j < _weekStarts.length; j++) {
        final current = _effectiveTarget(j);
        if (!_targetsEquivalent(current, source)) {
          _weekOverrides[j] = source == null
              ? null
              : _copyOf(source, _weekStarts[j]);
          _conflictWeeks.remove(j);
        }
      }
    });
  }

  void _loadIntoControllers(PeriodizationTarget? target) {
    final weight = target?.weightKgUsed ?? _latestWeight;
    final values = <String, String?>{
      'calories': target?.calories?.round().toString(),
      'proteinPerKg': _formatRatio(
        target?.proteinGPerKg ?? _deriveRatio(target?.proteinG, weight),
      ),
      'fatPerKg': _formatRatio(
        target?.fatGPerKg ?? _deriveRatio(target?.fatG, weight),
      ),
      'refWeight': _formatRatio(weight),
      'workouts': target?.workoutsPerWeek?.toString(),
      'minSets': target?.minSetsPerWeek?.toString(),
      'maxSets': target?.maxSetsPerWeek?.toString(),
      'minRpe': _formatRatio(target?.minRpe),
      'maxRpe': _formatRatio(target?.maxRpe),
      'weight': _formatRatio(target?.targetWeightKg),
      'change': _formatRatio(target?.weeklyWeightChangePercent),
      'sleep': _formatRatio(target?.sleepHours),
    };
    for (final entry in values.entries) {
      _targetControllers[entry.key]!.text = entry.value ?? '';
    }
  }

  double? _deriveRatio(double? grams, double? weight) {
    if (grams == null || weight == null || weight <= 0) return null;
    return grams / weight;
  }

  String _formatRatio(double? value) {
    if (value == null || !value.isFinite) return '';
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
  }

  Future<void> _suggestNutritionTargets() async {
    await NutritionGoalSuggestSheet.show(
      context,
      bodyRepo: _bodyRepository,
      settingsRepo: _settingsRepository,
      onApply: (
        calories,
        protein,
        carbs,
        fat, {
        double? proteinPerKg,
        double? fatPerKg,
      }) {
        if (!mounted) return;
        setState(() {
          _targetControllers['calories']!.text = calories.round().toString();
          final weight = _latestWeight;
          _targetControllers['proteinPerKg']!.text = _formatRatio(
            proteinPerKg ?? _deriveRatio(protein, weight),
          );
          _targetControllers['fatPerKg']!.text = _formatRatio(
            fatPerKg ?? _deriveRatio(fat, weight),
          );
          if (weight != null) {
            _targetControllers['refWeight']!.text = _formatRatio(weight);
          }
          _commitSelectedWeek();
        });
      },
    );
  }

  // =====================================================================
  // Dates / duration
  // =====================================================================

  DateTime _lastAllowedEnd() => widget.plan.endDate.add(
    Duration(days: _editing && _shiftFollowing ? 3650 : 0),
  );

  Future<void> _pickDate(bool start) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: start ? _startDate : _endDate,
      firstDate: widget.plan.startDate,
      lastDate: _lastAllowedEnd(),
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
      _rebuildWeeks();
    });
  }

  void _setWeeks(int weeks) {
    var end = _startDate.add(Duration(days: weeks * 7 - 1));
    final lastAllowed = _lastAllowedEnd();
    if (end.isAfter(lastAllowed)) end = lastAllowed;
    setState(() {
      _endDate = end;
      _rebuildWeeks();
    });
  }

  void _rebuildWeeks() {
    final newStarts = _computeWeekStarts(_startDate, _endDate);
    final newOverrides = List<PeriodizationTarget?>.filled(
      newStarts.length,
      null,
    );
    for (var i = 0; i < newStarts.length && i < _weekOverrides.length; i++) {
      newOverrides[i] = _weekOverrides[i];
    }
    _weekStarts = newStarts;
    _weekOverrides = newOverrides;
    _selectedWeek = _selectedWeek.clamp(0, _weekStarts.length - 1);
    _conflictWeeks.removeWhere((index) => index >= _weekStarts.length);
    _loadIntoControllers(_effectiveTarget(_selectedWeek));
  }

  Future<void> _askCustomWeeks() async {
    final controller = TextEditingController();
    final loc = AppLocalizations.of(context)!;
    final result = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(loc.periodizationCustomWeeks),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
    if (result != null) _setWeeks(result);
  }

  // =====================================================================
  // Save
  // =====================================================================

  bool _weeklyDiffersFromStored(List<PeriodizationTarget> weeks, int from) {
    if (_history.isEmpty) return weeks.any((target) => !target.isEmpty);
    for (var k = 0; k < weeks.length; k++) {
      final stored = _targetForDate(_history, _weekStarts[from + k]);
      if (!_targetsEquivalent(weeks[k], stored)) return true;
    }
    return false;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_endDate.isBefore(_startDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.periodizationOverlapError),
        ),
      );
      return;
    }
    _commitSelectedWeek();
    final locked = _lockedWeeks();
    final editableFrom = _editableFromIndex();
    if (_conflictWeeks.any(
      (index) => index >= editableFrom && !locked.contains(index),
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.nutritionSuggestMacroEnergyError,
          ),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      var targetChanged = false;
      List<PeriodizationTarget>? weeklyTargets;
      DateTime? weeklyReplaceFrom;
      if (editableFrom < _weekStarts.length) {
        final weeks = [
          for (var i = editableFrom; i < _weekStarts.length; i++)
            _effectiveTarget(i) ?? _emptyTarget(_weekStarts[i]),
        ];
        if (!_editing) {
          weeklyTargets = weeks.any((target) => !target.isEmpty)
              ? weeks
              : null;
        } else if (_weeklyDiffersFromStored(weeks, editableFrom)) {
          targetChanged = true;
          weeklyTargets = weeks;
          weeklyReplaceFrom = _weekStarts[editableFrom];
        }
      }
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
          targetChanged: targetChanged,
          weeklyTargets: targetChanged ? weeklyTargets : null,
          weeklyReplaceFrom: targetChanged ? weeklyReplaceFrom : null,
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
          weeklyTargets: weeklyTargets,
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

  PeriodizationTarget _emptyTarget(DateTime validFrom) => PeriodizationTarget(
    id: '',
    phaseId: widget.phase?.id ?? '',
    version: 0,
    validFrom: validFrom,
    createdAt: DateTime.now(),
  );

  // =====================================================================
  // Build
  // =====================================================================

  int _filledTargets(Iterable<String> keys) => keys
      .where((key) => _targetControllers[key]!.text.trim().isNotEmpty)
      .length;

  double? _double(String key) => double.tryParse(
    _targetControllers[key]!.text.trim().replaceAll(',', '.'),
  );
  int? _int(String key) => int.tryParse(_targetControllers[key]!.text.trim());

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final locked = _lockedWeeks();
    final effective = _effectiveTarget(_selectedWeek);
    final weekLocked = locked.contains(_selectedWeek);
    final weekCustomized = _weekOverrides[_selectedWeek] != null;
    final showEditableFields =
        !weekLocked && (_selectedWeek == 0 || weekCustomized || effective == null);
    final weeksCount = _weekStarts.length;
    final durationDays = (_endDate.difference(_startDate).inDays + 1).clamp(
      1,
      9999,
    );
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
                                      color:
                                          theme.colorScheme.onSurfaceVariant,
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
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final count in const [1, 2, 3, 4, 6, 8, 12])
                              ChoiceChip(
                                label: Text(loc.periodizationDurationWeeks(count)),
                                selected: weeksCount == count,
                                onSelected: (_) => _setWeeks(count),
                              ),
                            ChoiceChip(
                              avatar: const Icon(Icons.tune_rounded, size: 16),
                              label: Text('$weeksCount sem'),
                              selected: !const [1, 2, 3, 4, 6, 8, 12]
                                  .contains(weeksCount),
                              onSelected: (_) => _askCustomWeeks(),
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
                    subtitle: loc.periodizationWeeklyTargetsHelp,
                    icon: Icons.track_changes_rounded,
                  ),
                  _AutomaticTargetsCard(onTap: _suggestNutritionTargets),
                  const SizedBox(height: 10),
                  PeriodizationSurface(
                    child: PhaseWeekSelector(
                      weekCount: weeksCount,
                      selected: _selectedWeek,
                      firstWeekStart: _weekStarts.first,
                      phaseEnd: _endDate,
                      customizedWeeks: {
                        for (var i = 0; i < _weekOverrides.length; i++)
                          if (_weekOverrides[i] != null) i,
                      },
                      lockedWeeks: locked,
                      currentWeek: _currentWeekIndex(),
                      onSelect: _selectWeek,
                      onCustomize: !weekLocked &&
                              _selectedWeek > 0 &&
                              !weekCustomized
                          ? _customizeSelectedWeek
                          : null,
                      onUseInheritance: !weekLocked &&
                              _selectedWeek > 0 &&
                              weekCustomized
                          ? _useInheritance
                          : null,
                      onApplyToFollowing: !weekLocked &&
                              weeksCount > 1 &&
                              _selectedWeek < weeksCount - 1 &&
                              (_selectedWeek == 0 || weekCustomized)
                          ? _applyToFollowingWeeks
                          : null,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (showEditableFields) ...[
                    _targetCard(
                      loc.periodizationNutritionTargets,
                      Icons.restaurant_outlined,
                      subtitle: _targetCardSubtitle(
                        loc.periodizationNutritionTargetsHelp,
                        const ['calories', 'proteinPerKg', 'fatPerKg', 'refWeight'],
                      ),
                      actionLabel: loc.periodizationSuggestTargets,
                      onAction: _suggestNutritionTargets,
                      initiallyExpanded: true,
                      child: NutritionTargetFields(
                        calories: _targetControllers['calories']!,
                        proteinPerKg: _targetControllers['proteinPerKg']!,
                        fatPerKg: _targetControllers['fatPerKg']!,
                        referenceWeight: _targetControllers['refWeight']!,
                        onChanged: _onTargetChanged,
                      ),
                    ),
                    _targetCard(
                      loc.periodizationTrainingTargets,
                      Icons.fitness_center,
                      subtitle: _targetCardSubtitle(
                        loc.periodizationTrainingTargetsHelp,
                        const [
                          'workouts',
                          'minSets',
                          'maxSets',
                          'minRpe',
                          'maxRpe',
                        ],
                      ),
                      child: LayoutBuilder(
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
                    ),
                    _targetCard(
                      loc.periodizationBodyTargets,
                      Icons.monitor_weight_outlined,
                      subtitle: _targetCardSubtitle(
                        loc.periodizationBodyTargetsHelp,
                        const ['weight', 'change'],
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final width = constraints.maxWidth >= 560
                              ? (constraints.maxWidth - 10) / 2
                              : constraints.maxWidth;
                          Widget field(String key, String label,
                                  {String? unit}) =>
                              SizedBox(width: width, child: _field(key, label, unit: unit));
                          return Wrap(
                            spacing: 10,
                            runSpacing: 12,
                            children: [
                              field('weight', loc.periodizationTargetWeight, unit: 'kg'),
                              field('change', loc.periodizationWeeklyWeightChange,
                                  unit: '%'),
                            ],
                          );
                        },
                      ),
                    ),
                    _targetCard(
                      loc.periodizationSleepTargets,
                      Icons.nightlight_outlined,
                      subtitle: _targetCardSubtitle(
                        loc.periodizationSleepTargetsHelp,
                        const ['sleep'],
                      ),
                      child: _field('sleep', loc.periodizationSleepHours, unit: 'h'),
                    ),
                  ] else
                    _readOnlyCards(effective, weekLocked),
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
    final filled = _filledTargets(keys);
    return filled == 0
        ? help
        : loc.periodizationTargetsConfigured(filled, keys.length);
  }

  Widget _targetCard(
    String title,
    IconData icon, {
    required String subtitle,
    required Widget child,
    String? actionLabel,
    VoidCallback? onAction,
    bool initiallyExpanded = false,
  }) {
    final theme = Theme.of(context);
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
            subtitle,
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
        ),
      ),
    );
  }

  Widget _readOnlyCards(PeriodizationTarget? effective, bool weekLocked) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final target = effective ?? _emptyTarget(_weekStarts[_selectedWeek]);
    List<Widget> rows(List<(String, String)> values) => [
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
    ];
    final nutritionRows = <(String, String)>[
      if (target.calories != null) (loc.periodizationCaloriesPerDay, '${target.calories!.round()} kcal'),
      if (target.proteinG != null) (loc.nutritionProgressProtein, '${target.proteinG!.round()} g'),
      if (target.carbsG != null) (loc.periodizationCarbsRemainder, '${target.carbsG!.round()} g'),
      if (target.fatG != null) (loc.nutritionProgressFat, '${target.fatG!.round()} g'),
    ];
    final trainingRows = <(String, String)>[
      if (target.workoutsPerWeek != null)
        (loc.periodizationWorkoutsPerWeek, '${target.workoutsPerWeek}${loc.periodizationPerWeekUnit}'),
      if (target.minSetsPerWeek != null || target.maxSetsPerWeek != null)
        (loc.periodizationMinSets,
            '${target.minSetsPerWeek ?? '-'}–${target.maxSetsPerWeek ?? '-'}'),
      if (target.minRpe != null || target.maxRpe != null)
        (loc.periodizationMinRpe,
            '${target.minRpe ?? '-'}–${target.maxRpe ?? '-'}'),
    ];
    final bodyRows = <(String, String)>[
      if (target.targetWeightKg != null)
        (loc.periodizationTargetWeight, '${target.targetWeightKg} kg'),
      if (target.weeklyWeightChangePercent != null)
        (loc.periodizationWeeklyWeightChange, '${target.weeklyWeightChangePercent} %'),
    ];
    final sleepRows = <(String, String)>[
      if (target.sleepHours != null)
        (loc.periodizationSleepHours, '${target.sleepHours} h'),
    ];

    Widget card(String title, IconData icon, List<(String, String)> values) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: PeriodizationSurface(
            padding: const EdgeInsets.all(14),
            child: Column(
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
                    Icon(
                      Icons.lock_rounded,
                      size: 15,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
                if (values.isEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    loc.periodizationOptionalTargets,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 10),
                  ...rows(values),
                ],
              ],
            ),
          ),
        );

    return Column(
      children: [
        card(loc.periodizationNutritionTargets, Icons.restaurant_outlined, nutritionRows),
        card(loc.periodizationTrainingTargets, Icons.fitness_center, trainingRows),
        card(loc.periodizationBodyTargets, Icons.monitor_weight_outlined, bodyRows),
        card(loc.periodizationSleepTargets, Icons.nightlight_outlined, sleepRows),
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
    controller: _targetControllers[key],
    onChanged: (_) => _onTargetChanged(),
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
                          color: theme.colorScheme.onPrimaryContainer.withAlpha(190),
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
  'proteinPerKg',
  'fatPerKg',
  'refWeight',
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

DateTime _dayOnly(DateTime date) => DateTime(date.year, date.month, date.day);
DateTime _day(DateTime date) => DateTime(date.year, date.month, date.day);
