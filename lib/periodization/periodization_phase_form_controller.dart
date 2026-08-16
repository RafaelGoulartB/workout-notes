import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:workout_notes/models/periodization_phase.dart';
import 'package:workout_notes/models/periodization_plan.dart';
import 'package:workout_notes/models/periodization_target.dart';
import 'package:workout_notes/repositories/body_measurement_repository.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';
import 'package:workout_notes/repositories/routine_repository.dart';
import 'package:workout_notes/repositories/settings_repository.dart';
import 'package:workout_notes/utils/periodization_palette.dart';

import 'nutrition_target_input.dart';
import 'phase_draft_data.dart';
import 'week_override_resolver.dart';

/// Outcome of a [PeriodizationPhaseFormController.save] call; the widget maps
/// each to localized feedback + navigation.
enum PhaseFormSaveStatus { ok, overlap, macroConflict }

/// Pure (no `BuildContext`) state for the phase editor.
///
/// Owns every field controller, the dates/color, the weekly-override model
/// and persistence. Widgets (the standalone screen and potentially the plan
/// wizard) consume it via [ChangeNotifier] and never mutate state directly.
class PeriodizationPhaseFormController extends ChangeNotifier {
  PeriodizationPhaseFormController({
    required this.plan,
    this.phase,
    this.draftMode = false,
    this.draft,
    PeriodizationRepository? repository,
    BodyMeasurementRepository? bodyRepository,
    SettingsRepository? settingsRepository,
  }) : _repository = repository ?? PeriodizationRepository(),
       _bodyRepository = bodyRepository ?? BodyMeasurementRepository(),
       _settingsRepository = settingsRepository ?? SettingsRepository() {
    _seed();
  }

  final PeriodizationPlan plan;
  final PeriodizationPhase? phase;
  final bool draftMode;
  final PeriodizationPhaseDraftData? draft;

  final PeriodizationRepository _repository;
  final BodyMeasurementRepository _bodyRepository;
  final SettingsRepository _settingsRepository;

  final _resolver = const WeekOverrideResolver();

  final name = TextEditingController();
  final intent = TextEditingController();
  final type = TextEditingController();
  final Map<String, TextEditingController> targetControllers = {};

  late DateTime startDate;
  late DateTime endDate;
  int color = kDefaultPhaseColor;
  bool shiftFollowing = true;
  bool saving = false;
  bool loading = true;
  String? routineId;
  List<Map<String, dynamic>> routines = const [];
  double? latestWeight;
  List<PeriodizationTarget> history = const [];

  late List<DateTime> weekStarts;
  late List<PeriodizationTarget?> weekOverrides;
  int selectedWeek = 0;
  final Set<int> conflictWeeks = {};

  Timer? _targetDebounce;
  bool _disposed = false;

  bool get editing => phase != null;
  int get weeksCount => weekStarts.length;
  int get durationDays =>
      (endDate.difference(startDate).inDays + 1).clamp(1, 9999);

  PeriodizationTarget? get effective => effectiveTarget(selectedWeek);
  bool get weekLocked => lockedWeeks.contains(selectedWeek);
  bool get weekCustomized => weekOverrides[selectedWeek] != null;
  bool get showEditableFields =>
      !weekLocked && (selectedWeek == 0 || weekCustomized || effective == null);

  BodyMeasurementRepository get bodyRepository => _bodyRepository;
  SettingsRepository get settingsRepository => _settingsRepository;

  /// Seed the editor from an existing phase or a wizard draft.
  void _seed() {
    final phase = this.phase;
    final seed = draft;
    name.text = phase?.name ?? seed?.name ?? '';
    intent.text = phase?.intent ?? seed?.intent ?? '';
    type.text = phase?.templateKey ?? seed?.templateKey ?? '';
    startDate = phase?.startDate ?? seed?.startDate ?? _suggestedStart();
    endDate =
        phase?.endDate ?? seed?.endDate ?? startDate.add(const Duration(days: 27));
    color = phase?.color ?? seed?.color ?? color;
    weekStarts = _resolver.computeWeekStarts(startDate, endDate);
    weekOverrides = List<PeriodizationTarget?>.filled(
      weekStarts.length,
      null,
    );
    for (final key in kPhaseTargetKeys) {
      targetControllers[key] = TextEditingController();
    }
    if (draftMode && seed != null) {
      weekOverrides = _resolver.prefillOverridesFromDraft(
        weekStarts: weekStarts,
        weeklyTargets: seed.weeklyTargets,
      );
    }
  }

  DateTime _suggestedStart() => DateTime.now().isBefore(plan.startDate)
      ? plan.startDate
      : DateTime.now().isAfter(plan.endDate)
      ? plan.startDate
      : DateTime.now();

  Future<void> load() async {
    final weightFuture = _bodyRepository.getLatestWeightKg();
    final results = await Future.wait([
      RoutineRepository().getRoutines(),
      if (editing) _repository.getTargetHistory(phase!.id),
    ]);
    if (_disposed) return;
    routines = results[0] as List<Map<String, dynamic>>;
    if (editing) {
      history = results[1] as List<PeriodizationTarget>;
      weekOverrides = _resolver.reconstructOverrides(
        weekStarts: weekStarts,
        history: history,
      );
      final editableFrom = editableFromIndex;
      selectedWeek = (editableFrom < weekStarts.length
              ? editableFrom
              : weekStarts.length - 1)
          .clamp(0, weekStarts.length - 1);
    }
    latestWeight = await weightFuture;
    if (_disposed) return;
    loadIntoControllers(effective);
    loading = false;
    notifyListeners();
  }

  // =====================================================================
  // Week model helpers
  // =====================================================================

  PeriodizationTarget? effectiveTarget(int index) =>
      _resolver.effectiveTarget(weekOverrides, index);

  PeriodizationTarget? targetForDate(
    List<PeriodizationTarget> targets,
    DateTime date,
  ) => _resolver.targetForDate(targets, date);

  PeriodizationTarget copyOf(PeriodizationTarget source, DateTime validFrom) =>
      _resolver.copyOf(source, validFrom);

  bool targetsEquivalent(PeriodizationTarget? a, PeriodizationTarget? b) =>
      _resolver.targetsEquivalent(a, b);

  DateTime weekEnd(int index) =>
      _resolver.weekEnd(weekStarts, index, endDate);

  Set<int> get lockedWeeks {
    if (!editing) return const {};
    final today = _resolver.dayOnly(DateTime.now());
    return {
      for (var i = 0; i < weekStarts.length; i++)
        if (weekEnd(i).isBefore(today)) i,
    };
  }

  int get editableFromIndex {
    if (!editing) return 0;
    final today = _resolver.dayOnly(DateTime.now());
    for (var i = 0; i < weekStarts.length; i++) {
      if (!weekEnd(i).isBefore(today)) return i;
    }
    return weekStarts.length;
  }

  int? get currentWeekIndex {
    final today = _resolver.dayOnly(DateTime.now());
    for (var i = 0; i < weekStarts.length; i++) {
      if (!weekStarts[i].isAfter(today) && !weekEnd(i).isBefore(today)) {
        return i;
      }
    }
    return null;
  }

  // =====================================================================
  // Week editing (commit-on-switch model)
  // =====================================================================

  void selectWeek(int index) {
    if (index == selectedWeek) return;
    _targetDebounce?.cancel();
    commitSelectedWeek();
    selectedWeek = index;
    loadIntoControllers(effective);
    notifyListeners();
  }

  void commitSelectedWeek() {
    if (weekStarts.isEmpty || lockedWeeks.contains(selectedWeek)) return;
    weekOverrides[selectedWeek] = buildTargetForWeek(selectedWeek);
    updateConflict(selectedWeek);
  }

  PeriodizationTarget buildTargetForWeek(int index) {
    final previous = effectiveTarget(index);
    final validFrom = weekStarts[index];
    final input = NutritionTargetInput.fromControllers(targetControllers);
    final breakdown = input.resolve();
    double? calories;
    double? proteinG;
    double? carbsG;
    double? fatG;
    double? proteinGPerKg;
    double? fatGPerKg;
    double? weightKgUsed;
    if (breakdown != null) {
      calories = breakdown.calories;
      proteinG = breakdown.proteinG;
      fatG = breakdown.fatG;
      carbsG = breakdown.carbsG;
      proteinGPerKg = input.proteinPerKg;
      fatGPerKg = input.fatPerKg;
      weightKgUsed = input.refWeight;
    } else {
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
      phaseId: phase?.id ?? '',
      version: 0,
      validFrom: validFrom,
      calories: calories,
      proteinG: proteinG,
      carbsG: carbsG,
      fatG: fatG,
      proteinGPerKg: proteinGPerKg,
      fatGPerKg: fatGPerKg,
      weightKgUsed: weightKgUsed,
      workoutsPerWeek: intValue('workouts'),
      minSetsPerWeek: intValue('minSets'),
      maxSetsPerWeek: intValue('maxSets'),
      minRpe: doubleValue('minRpe'),
      maxRpe: doubleValue('maxRpe'),
      routineId: routineId,
      targetWeightKg: doubleValue('weight'),
      weeklyWeightChangePercent: doubleValue('change'),
      sleepHours: doubleValue('sleep'),
      createdAt: DateTime.now(),
    );
  }

  void updateConflict(int index) {
    final breakdown = NutritionTargetInput.fromControllers(
      targetControllers,
    ).resolve();
    if (breakdown != null) {
      breakdown.energyConflict
          ? conflictWeeks.add(index)
          : conflictWeeks.remove(index);
    } else {
      conflictWeeks.remove(index);
    }
  }

  /// Commits the selected week on a 300ms quiet period so typing does not
  /// rewrite the override (and trigger a rebuild) on every keystroke.
  void onTargetChanged() {
    if (lockedWeeks.contains(selectedWeek)) return;
    _targetDebounce?.cancel();
    _targetDebounce = Timer(const Duration(milliseconds: 300), () {
      if (_disposed) return;
      commitSelectedWeek();
      notifyListeners();
    });
  }

  void customizeSelectedWeek() {
    _targetDebounce?.cancel();
    commitSelectedWeek();
    if (weekOverrides[selectedWeek] == null) {
      final effective = effectiveTarget(selectedWeek);
      weekOverrides[selectedWeek] = effective == null
          ? buildTargetForWeek(selectedWeek)
          : copyOf(effective, weekStarts[selectedWeek]);
    }
    notifyListeners();
  }

  void useInheritance() {
    _targetDebounce?.cancel();
    weekOverrides[selectedWeek] = null;
    conflictWeeks.remove(selectedWeek);
    loadIntoControllers(effective);
    notifyListeners();
  }

  void applyToFollowingWeeks() {
    _targetDebounce?.cancel();
    commitSelectedWeek();
    final source = effectiveTarget(selectedWeek);
    for (var j = selectedWeek + 1; j < weekStarts.length; j++) {
      final current = effectiveTarget(j);
      if (!targetsEquivalent(current, source)) {
        weekOverrides[j] = source == null ? null : copyOf(source, weekStarts[j]);
        conflictWeeks.remove(j);
      }
    }
    notifyListeners();
  }

  void loadIntoControllers(PeriodizationTarget? target) {
    final weight = target?.weightKgUsed ?? latestWeight;
    final values = <String, String?>{
      'calories': target?.calories?.round().toString(),
      'proteinPerKg': formatRatio(
        target?.proteinGPerKg ?? deriveRatio(target?.proteinG, weight),
      ),
      'fatPerKg': formatRatio(
        target?.fatGPerKg ?? deriveRatio(target?.fatG, weight),
      ),
      'refWeight': formatRatio(weight),
      'workouts': target?.workoutsPerWeek?.toString(),
      'minSets': target?.minSetsPerWeek?.toString(),
      'maxSets': target?.maxSetsPerWeek?.toString(),
      'minRpe': formatRatio(target?.minRpe),
      'maxRpe': formatRatio(target?.maxRpe),
      'weight': formatRatio(target?.targetWeightKg),
      'change': formatRatio(target?.weeklyWeightChangePercent),
      'sleep': formatRatio(target?.sleepHours),
    };
    for (final entry in values.entries) {
      targetControllers[entry.key]!.text = entry.value ?? '';
    }
    routineId = target?.routineId;
  }

  double? deriveRatio(double? grams, double? weight) {
    if (grams == null || weight == null || weight <= 0) return null;
    return grams / weight;
  }

  String formatRatio(double? value) {
    if (value == null || !value.isFinite) return '';
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
  }

  /// Applies a suggestion sheet result to the nutrition controllers and
  /// re-commits the selected week.
  void applyNutritionSuggestion(
    double calories,
    double protein,
    double carbs,
    double fat, {
    double? proteinPerKg,
    double? fatPerKg,
  }) {
    targetControllers['calories']!.text = calories.round().toString();
    final weight = latestWeight;
    targetControllers['proteinPerKg']!.text = formatRatio(
      proteinPerKg ?? deriveRatio(protein, weight),
    );
    targetControllers['fatPerKg']!.text = formatRatio(
      fatPerKg ?? deriveRatio(fat, weight),
    );
    if (weight != null) {
      targetControllers['refWeight']!.text = formatRatio(weight);
    }
    commitSelectedWeek();
    notifyListeners();
  }

  // =====================================================================
  // Dates / duration
  // =====================================================================

  DateTime get lastAllowedEnd => plan.endDate.add(
    Duration(days: editing && shiftFollowing ? 3650 : 0),
  );

  void setStartDate(DateTime picked) {
    final duration = endDate.difference(startDate);
    startDate = picked;
    endDate = picked.add(duration);
    rebuildWeeks();
  }

  void setEndDate(DateTime picked) {
    endDate = picked;
    rebuildWeeks();
  }

  void setWeeks(int weeks) {
    var end = startDate.add(Duration(days: weeks * 7 - 1));
    final lastAllowed = lastAllowedEnd;
    if (end.isAfter(lastAllowed)) end = lastAllowed;
    endDate = end;
    rebuildWeeks();
  }

  void rebuildWeeks() {
    final newStarts = _resolver.computeWeekStarts(startDate, endDate);
    final newOverrides = List<PeriodizationTarget?>.filled(
      newStarts.length,
      null,
    );
    for (var i = 0; i < newStarts.length && i < weekOverrides.length; i++) {
      newOverrides[i] = weekOverrides[i];
    }
    weekStarts = newStarts;
    weekOverrides = newOverrides;
    selectedWeek = selectedWeek.clamp(0, weekStarts.length - 1);
    conflictWeeks.removeWhere((index) => index >= weekStarts.length);
    loadIntoControllers(effective);
    notifyListeners();
  }

  // =====================================================================
  // Save
  // =====================================================================

  bool weeklyDiffersFromStored(List<PeriodizationTarget> weeks, int from) {
    if (history.isEmpty) return weeks.any((target) => !target.isEmpty);
    for (var k = 0; k < weeks.length; k++) {
      final stored = targetForDate(history, weekStarts[from + k]);
      if (!targetsEquivalent(weeks[k], stored)) return true;
    }
    return false;
  }

  /// Validates and persists (or, in draft mode, just snapshots the result).
  /// The widget must call its `Form` validation before this.
  Future<PhaseFormSaveStatus> save() async {
    _targetDebounce?.cancel();
    if (endDate.isBefore(startDate)) return PhaseFormSaveStatus.overlap;
    commitSelectedWeek();
    final locked = lockedWeeks;
    final editableFrom = editableFromIndex;
    if (conflictWeeks.any(
      (index) => index >= editableFrom && !locked.contains(index),
    )) {
      return PhaseFormSaveStatus.macroConflict;
    }
    if (draftMode) return PhaseFormSaveStatus.ok;
    saving = true;
    notifyListeners();
    try {
      var targetChanged = false;
      List<PeriodizationTarget>? weeklyTargets;
      DateTime? weeklyReplaceFrom;
      if (editableFrom < weekStarts.length) {
        final weeks = [
          for (var i = editableFrom; i < weekStarts.length; i++)
            effectiveTarget(i) ?? emptyTarget(weekStarts[i]),
        ];
        if (!editing) {
          weeklyTargets = weeks.any((target) => !target.isEmpty)
              ? weeks
              : null;
        } else if (weeklyDiffersFromStored(weeks, editableFrom)) {
          targetChanged = true;
          weeklyTargets = weeks;
          weeklyReplaceFrom = weekStarts[editableFrom];
        }
      }
      if (editing) {
        final old = phase!;
        final updated = PeriodizationPhase(
          id: old.id,
          planId: old.planId,
          name: name.text.trim(),
          templateKey: type.text.trim().isEmpty ? null : type.text.trim(),
          color: color,
          startDate: startDate,
          endDate: endDate,
          intent: intent.text.trim().isEmpty ? null : intent.text.trim(),
          orderIndex: old.orderIndex,
          createdAt: old.createdAt,
          updatedAt: DateTime.now(),
        );
        await _repository.updatePhaseWithTargets(
          updated,
          shiftFollowingPhases: shiftFollowing,
          targetChanged: targetChanged,
          weeklyTargets: targetChanged ? weeklyTargets : null,
          weeklyReplaceFrom: targetChanged ? weeklyReplaceFrom : null,
        );
      } else {
        await _repository.addPhase(
          planId: plan.id,
          name: name.text,
          startDate: startDate,
          endDate: endDate,
          color: color,
          intent: intent.text,
          templateKey: type.text.trim().isEmpty ? null : type.text.trim(),
          weeklyTargets: weeklyTargets,
        );
      }
      return PhaseFormSaveStatus.ok;
    } finally {
      saving = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Snapshot returned to the wizard in draft mode.
  PeriodizationPhaseDraftData get draftData => PeriodizationPhaseDraftData(
    name: name.text.trim(),
    intent: intent.text.trim().isEmpty ? null : intent.text.trim(),
    templateKey: type.text.trim().isEmpty ? null : type.text.trim(),
    color: color,
    startDate: startDate,
    endDate: endDate,
    weeklyTargets: [
      for (var i = 0; i < weekStarts.length; i++)
        effectiveTarget(i) ?? emptyTarget(weekStarts[i]),
    ],
  );

  PeriodizationTarget emptyTarget(DateTime validFrom) => PeriodizationTarget(
    id: '',
    phaseId: phase?.id ?? '',
    version: 0,
    validFrom: validFrom,
    createdAt: DateTime.now(),
  );

  // =====================================================================
  // Build helpers
  // =====================================================================

  int filledTargets(Iterable<String> keys) => keys
      .where((key) => targetControllers[key]!.text.trim().isNotEmpty)
      .length;

  double? doubleValue(String key) => double.tryParse(
    targetControllers[key]!.text.trim().replaceAll(',', '.'),
  );
  int? intValue(String key) => int.tryParse(targetControllers[key]!.text.trim());

  void setShiftFollowing(bool value) {
    shiftFollowing = value;
    notifyListeners();
  }

  void setColor(int value) {
    color = value;
    notifyListeners();
  }

  void setRoutine(String? value) {
    _targetDebounce?.cancel();
    routineId = value;
    commitSelectedWeek();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _targetDebounce?.cancel();
    name.dispose();
    intent.dispose();
    type.dispose();
    for (final controller in targetControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }
}

const kPhaseTargetKeys = [
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
