import 'package:flutter/widgets.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/models/nutrition/nutrition_goal.dart';
import 'package:workout_notes/models/periodization_phase.dart';
import 'package:workout_notes/models/periodization_plan.dart';
import 'package:workout_notes/models/periodization_schedule.dart';
import 'package:workout_notes/models/periodization_target.dart';
import 'package:workout_notes/models/run_plan.dart';
import 'package:workout_notes/periodization/phase_kind.dart';
import 'package:workout_notes/periodization/phase_week_plan.dart';
import 'package:workout_notes/periodization/run_plan_week_resolver.dart';
import 'package:workout_notes/repositories/body_measurement_repository.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';
import 'package:workout_notes/repositories/routine_repository.dart';
import 'package:workout_notes/repositories/run_plan_repository.dart';
import 'package:workout_notes/utils/app_number_format.dart';
import 'package:workout_notes/utils/date_utils.dart';

/// Per-week deviation from the phase targets: a label ("Deload", "Refeed")
/// and/or different calories for training and rest days.
class WeekAdjustment {
  final double? calories;
  final double? restCalories;
  final String? label;

  const WeekAdjustment({this.calories, this.restCalories, this.label});

  bool get isEmpty =>
      calories == null &&
      restCalories == null &&
      (label == null || label!.trim().isEmpty);

  /// Anything beyond a label changes the week's numbers.
  bool get changesTargets => calories != null || restCalories != null;
}

/// State of the phase editor: the phase-level targets ("base"), the week
/// adjustments on top of them, and saving.
///
/// Weeks before [editableFrom] already happened and are shown from history;
/// saving rewrites the targets from that week on, one per week, as
/// `base + adjustment`.
class PhaseEditorController extends ChangeNotifier {
  PhaseEditorController({
    required this.plan,
    required PeriodizationPhase phase,
    PeriodizationRepository? repository,
    DateTime? today,
  }) : _phase = phase,
       _repository = repository ?? DatabaseHelper.instance.periodizationRepo,
       _today = today ?? DateTime.now() {
    name.text = phase.name;
    intent.text = phase.intent ?? '';
    kind = PhaseKind.fromKey(phase.templateKey);
    color = phase.color;
    weeks = phase.totalWeeks;
  }

  final PeriodizationPlan plan;
  final PeriodizationRepository _repository;
  final DateTime _today;
  PeriodizationPhase _phase;
  PeriodizationPhase get phase => _phase;

  // ---- identity ----
  final name = TextEditingController();
  final intent = TextEditingController();
  late PhaseKind kind;
  late int color;
  late int weeks;

  // ---- nutrition (training day) ----
  final caloriesText = TextEditingController();
  final proteinText = TextEditingController();
  final fatText = TextEditingController();
  bool restEnabled = false;
  final restCaloriesText = TextEditingController();

  // ---- training ----
  List<String> routineIds = [];
  Set<int> strengthDays = {};
  int? minSets;
  int? maxSets;
  double? minRpe;
  double? maxRpe;

  // ---- running ----
  String? runPlanId;
  int runPlanStartWeek = 0;
  Set<int> runDays = {};
  final runKmText = TextEditingController();

  // ---- body & sleep ----
  double? weeklyWeightChangePercent;
  final targetWeightText = TextEditingController();
  double? sleepHours;

  // ---- context ----
  double? tdee;
  double? latestWeightKg;
  List<Map<String, dynamic>> routines = const [];
  Map<String, List<String>> routineDayNames = const {};
  List<RunPlan> runPlans = const [];
  List<PeriodizationPhase> planPhases = const [];

  // ---- weeks ----
  /// Stored effective target of each phase week (history + current plan).
  List<PeriodizationTarget?> storedWeeks = const [];

  /// First phase week that can still change. Weeks before it are history.
  int editableFrom = 0;
  final Map<int, WeekAdjustment> adjustments = {};

  /// Target the base was loaded from; carries fields the editor does not
  /// show (long run, quality sessions) so saving never drops them.
  PeriodizationTarget? _loadedBase;

  bool loading = true;
  bool saving = false;
  bool dirty = false;

  static const _resolver = RunPlanWeekResolver();

  // =====================================================================
  // Loading
  // =====================================================================

  Future<void> load({
    RoutineRepository? routineRepository,
    RunPlanRepository? runPlanRepository,
    NutritionRepository? nutritionRepository,
    BodyMeasurementRepository? bodyRepository,
  }) async {
    final routineRepo = routineRepository ?? DatabaseHelper.instance.routineRepo;
    final results = await Future.wait<Object?>([
      routineRepo.getRoutines(),
      routineRepo.getRoutineDayNames(),
      (runPlanRepository ?? DatabaseHelper.instance.runPlanRepo).listPlans(hydrate: true),
      (nutritionRepository ?? DatabaseHelper.instance.nutritionRepo).getActiveGoal(),
      (bodyRepository ?? DatabaseHelper.instance.bodyMeasurementRepo).getLatestWeightKg(),
      _repository.getWeeklyTargets(_phase),
      _repository.getPhases(_phase.planId),
    ]);
    routines = results[0] as List<Map<String, dynamic>>;
    routineDayNames = results[1] as Map<String, List<String>>;
    runPlans = results[2] as List<RunPlan>;
    tdee = (results[3] as NutritionGoal?)?.tdee;
    latestWeightKg = results[4] as double?;
    storedWeeks = results[5] as List<PeriodizationTarget?>;
    planPhases = results[6] as List<PeriodizationPhase>;

    final today = dayOf(_today);
    editableFrom = _phase.contains(today) ? _phase.weekAt(today) - 1 : 0;
    final base = editableFrom < storedWeeks.length
        ? storedWeeks[editableFrom]
        : null;
    _loadedBase = base;
    if (base == null || base.isEmpty) {
      _seedFromKind();
    } else {
      _applyBase(base);
    }
    for (var week = editableFrom; week < storedWeeks.length; week++) {
      final stored = storedWeeks[week];
      if (stored == null) continue;
      final adjustment = WeekAdjustment(
        calories: week > editableFrom && stored.calories != base?.calories
            ? stored.calories
            : null,
        restCalories:
            week > editableFrom && stored.restCalories != base?.restCalories
            ? stored.restCalories
            : null,
        label: stored.weekLabel,
      );
      if (!adjustment.isEmpty) adjustments[week] = adjustment;
    }
    loading = false;
    notifyListeners();
  }

  void _applyBase(PeriodizationTarget base) {
    caloriesText.text = _format(base.calories);
    proteinText.text = _format(base.proteinG);
    fatText.text = _format(base.fatG);
    restEnabled = base.hasRestDayNutrition;
    restCaloriesText.text = _format(base.restCalories);
    routineIds = [...base.routineIds];
    strengthDays = {...base.strengthDays};
    minSets = base.minSetsPerWeek;
    maxSets = base.maxSetsPerWeek;
    minRpe = base.minRpe;
    maxRpe = base.maxRpe;
    runPlanId = base.runPlanIds.firstOrNull;
    runPlanStartWeek = base.runPlanStartWeek ?? 0;
    runDays = {...base.runDays};
    runKmText.text = runPlanId == null && base.runWeeklyDistanceMeters != null
        ? _format(base.runWeeklyDistanceMeters! / 1000, decimals: 1)
        : '';
    weeklyWeightChangePercent = base.weeklyWeightChangePercent;
    targetWeightText.text = _format(base.targetWeightKg, decimals: 1);
    sleepHours = base.sleepHours;
  }

  /// A phase without targets starts from its kind's suggestion, so the
  /// editor never opens on a wall of empty fields.
  void _seedFromKind() {
    if (kind.calorieFactor != null && tdee != null) suggestNutrition();
    weeklyWeightChangePercent = kind.weeklyWeightChangePercent;
  }

  // =====================================================================
  // Derived values
  // =====================================================================

  double? get calories => _parse(caloriesText.text);
  double? get proteinG => _parse(proteinText.text);
  double? get fatG => _parse(fatText.text);
  double? get restCalories =>
      restEnabled ? _parse(restCaloriesText.text) : null;
  double? get carbsG =>
      remainingCarbsG(calories: calories, proteinG: proteinG, fatG: fatG);
  double? get restCarbsG =>
      remainingCarbsG(calories: restCalories, proteinG: proteinG, fatG: fatG);

  /// Protein and fat alone exceed the calories.
  bool get macroConflict {
    final kcal = calories;
    if (kcal == null) return false;
    return (proteinG ?? 0) * 4 + (fatG ?? 0) * 9 > kcal;
  }

  RunPlan? get runPlan => runPlanId == null
      ? null
      : runPlans.where((plan) => plan.id == runPlanId).firstOrNull;

  int get totalWeeks => weeks;

  bool isLocked(int week) => week < editableFrom;

  DateTime weekStart(int week) =>
      addDays(_phase.startDate, 7 * week);

  /// Plan week that phase week [week] maps onto, or null without a plan.
  int? runPlanWeekFor(int week) {
    final plan = runPlan;
    if (plan == null) return null;
    return _resolver.planWeekFor(
      phaseWeek: week,
      planWeeks: plan.weeks,
      startWeek: runPlanStartWeek,
    );
  }

  /// The phase-level target as currently edited.
  PeriodizationTarget buildBase() {
    final weight = latestWeightKg;
    final plan = runPlan;
    final km = _parse(runKmText.text);
    final loaded = _loadedBase;
    return PeriodizationTarget(
      id: '',
      phaseId: _phase.id,
      version: 0,
      validFrom: _phase.startDate,
      calories: calories,
      proteinG: proteinG,
      fatG: fatG,
      carbsG: carbsG,
      proteinGPerKg: weight != null && proteinG != null
          ? double.parse((proteinG! / weight).toStringAsFixed(2))
          : null,
      fatGPerKg: weight != null && fatG != null
          ? double.parse((fatG! / weight).toStringAsFixed(2))
          : null,
      weightKgUsed: weight != null && (proteinG != null || fatG != null)
          ? weight
          : null,
      restCalories: restCalories,
      restProteinG: restCalories == null ? null : proteinG,
      restFatG: restCalories == null ? null : fatG,
      restCarbsG: restCalories == null ? null : restCarbsG,
      routineIds: routineIds,
      strengthDays: strengthDays.toList(),
      workoutsPerWeek: strengthDays.isEmpty ? null : strengthDays.length,
      minSetsPerWeek: minSets,
      maxSetsPerWeek: maxSets,
      minRpe: minRpe,
      maxRpe: maxRpe,
      runPlanIds: plan == null ? const [] : [plan.id],
      runPlanStartWeek: plan == null || runPlanStartWeek == 0
          ? null
          : runPlanStartWeek,
      runDays: plan == null ? runDays.toList() : const [],
      runSessionsPerWeek: plan == null && runDays.isNotEmpty
          ? runDays.length
          : null,
      runWeeklyDistanceMeters: plan == null && km != null ? km * 1000 : null,
      longRunDistanceMeters: loaded?.longRunDistanceMeters,
      qualitySessionsPerWeek: plan == null
          ? loaded?.qualitySessionsPerWeek
          : null,
      targetWeightKg: _parse(targetWeightText.text),
      weeklyWeightChangePercent: weeklyWeightChangePercent,
      sleepHours: sleepHours,
      createdAt: DateTime.now(),
    );
  }

  /// Target of phase week [week]: stored history for locked weeks,
  /// `base + adjustment` otherwise.
  PeriodizationTarget? targetForWeek(int week, {PeriodizationTarget? base}) {
    if (isLocked(week)) {
      return week < storedWeeks.length ? storedWeeks[week] : null;
    }
    final phaseBase = base ?? buildBase();
    final adjustment = adjustments[week];
    final kcal = adjustment?.calories ?? phaseBase.calories;
    final rest = restEnabled
        ? adjustment?.restCalories ?? phaseBase.restCalories
        : null;
    final plan = runPlan;
    final planWeek = runPlanWeekFor(week);
    return phaseBase.copyWith(
      calories: kcal,
      carbsG: remainingCarbsG(
        calories: kcal,
        proteinG: phaseBase.proteinG,
        fatG: phaseBase.fatG,
      ),
      restCalories: rest,
      restCarbsG: rest == null
          ? null
          : remainingCarbsG(
              calories: rest,
              proteinG: phaseBase.proteinG,
              fatG: phaseBase.fatG,
            ),
      weekLabel: adjustment?.label?.trim().isEmpty ?? true
          ? null
          : adjustment!.label!.trim(),
      // With a linked plan the week's running volume is the plan week's, so
      // adherence compares against what the plan actually asks for.
      runSessionsPerWeek: plan != null && planWeek != null
          ? plan.workoutsForWeek(planWeek).length
          : null,
      runWeeklyDistanceMeters: plan != null && planWeek != null
          ? plan.weeklyDistanceMeters(planWeek)
          : null,
    );
  }

  /// Template week of phase week [week].
  List<PlannedWeekday> weekPlan(int week) => PhaseWeekPlan.build(
    target: targetForWeek(week),
    runPlan: isLocked(week) ? null : runPlan,
    runPlanWeek: isLocked(week) ? null : runPlanWeekFor(week),
  );

  /// Routine day names in rotation order across the linked routines.
  List<String> get strengthSequence => [
    for (final id in routineIds) ...?routineDayNames[id],
  ];

  String? routineName(String id) =>
      routines.where((row) => row['id'] == id).firstOrNull?['name'] as String?;

  /// The week containing today, or null when today is outside the phase.
  int? get currentWeek {
    final today = dayOf(_today);
    return _phase.contains(today) ? _phase.weekAt(today) - 1 : null;
  }

  // =====================================================================
  // Mutations
  // =====================================================================

  void touch() {
    dirty = true;
    notifyListeners();
  }

  /// Switches the phase kind. A name still equal to the previous kind's
  /// label ([labelOf] localizes it) follows the new kind.
  void setKind(PhaseKind value, {String Function(PhaseKind kind)? labelOf}) {
    if (labelOf != null && name.text.trim() == labelOf(kind)) {
      name.text = labelOf(value);
    }
    kind = value;
    if (value != PhaseKind.custom) color = value.color;
    touch();
  }

  void setWeeks(int value) {
    weeks = value.clamp(1, 104);
    adjustments.removeWhere((week, _) => week >= weeks);
    touch();
  }

  void setColor(int value) {
    color = value;
    touch();
  }

  void setRestEnabled(bool value) {
    restEnabled = value;
    if (value && _parse(restCaloriesText.text) == null) {
      final kcal = calories;
      if (kcal != null) {
        restCaloriesText.text = _format(((kcal * 0.85) / 10).round() * 10.0);
      }
    }
    touch();
  }

  /// Fills calories, protein and fat from the phase kind, TDEE and weight.
  /// Returns false when there is no TDEE to start from.
  bool suggestNutrition() {
    final expenditure = tdee;
    if (expenditure == null) return false;
    final factor = kind.calorieFactor ?? 1.0;
    final kcal = ((expenditure * factor) / 10).round() * 10.0;
    caloriesText.text = _format(kcal);
    final weight = latestWeightKg;
    if (weight != null) {
      proteinText.text = _format(
        (weight * (kind.proteinPerKg ?? 1.8)).roundToDouble(),
      );
      fatText.text = _format((weight * (kind.fatPerKg ?? 1.0)).roundToDouble());
    }
    if (restEnabled) {
      restCaloriesText.text = _format(((kcal * 0.85) / 10).round() * 10.0);
    }
    dirty = true;
    notifyListeners();
    return true;
  }

  void setRoutineIds(List<String> ids) {
    routineIds = ids;
    touch();
  }

  void setStrengthDays(Set<int> days) {
    strengthDays = days;
    touch();
  }

  void setRunPlan(String? id) {
    runPlanId = id;
    runPlanStartWeek = 0;
    touch();
  }

  void setRunPlanStartWeek(int value) {
    final plan = runPlan;
    if (plan == null) return;
    runPlanStartWeek = value.clamp(0, plan.weeks - 1);
    touch();
  }

  /// Start the plan so its last week lands on the phase's last week.
  void alignRunPlanFinish() {
    final plan = runPlan;
    if (plan == null) return;
    runPlanStartWeek = _resolver.startWeekForFinish(
      phaseWeeks: weeks,
      planWeeks: plan.weeks,
    );
    touch();
  }

  void setRunDays(Set<int> days) {
    runDays = days;
    touch();
  }

  void setWeeklyWeightChange(double? value) {
    weeklyWeightChangePercent = value;
    touch();
  }

  void setSleepHours(double? value) {
    sleepHours = value;
    touch();
  }

  void setTrainingVolume({
    int? minSets,
    int? maxSets,
    double? minRpe,
    double? maxRpe,
  }) {
    this.minSets = minSets;
    this.maxSets = maxSets;
    this.minRpe = minRpe;
    this.maxRpe = maxRpe;
    touch();
  }

  void setAdjustment(int week, WeekAdjustment adjustment) {
    if (isLocked(week)) return;
    if (adjustment.isEmpty) {
      adjustments.remove(week);
    } else {
      adjustments[week] = adjustment;
    }
    touch();
  }

  /// Copies week [week]'s adjustment onto every later editable week.
  void applyAdjustmentToFollowing(int week) {
    final source = adjustments[week];
    for (var other = week + 1; other < weeks; other++) {
      if (source == null || source.isEmpty) {
        adjustments.remove(other);
      } else {
        adjustments[other] = source;
      }
    }
    touch();
  }

  // =====================================================================
  // Saving
  // =====================================================================

  /// Persists the phase. When its length changed the plan is re-chained
  /// first so the following phases move with it.
  Future<void> save() async {
    saving = true;
    notifyListeners();
    try {
      final trimmedName = name.text.trim();
      if (weeks != _phase.totalWeeks) {
        final phases = await _repository.getPhases(_phase.planId);
        final current = await _repository.getPlan(_phase.planId) ?? plan;
        await _repository.replanPlan(
          planId: current.id,
          name: current.name,
          notes: current.notes,
          startDate: phases.first.startDate,
          phases: [
            for (final item in phases)
              PhaseScheduleEntry(
                id: item.id,
                name: item.id == _phase.id ? trimmedName : item.name,
                templateKey: item.templateKey ?? PhaseKind.custom.key,
                color: item.color,
                intent: item.intent,
                weeks: item.id == _phase.id ? weeks : item.totalWeeks,
              ),
          ],
        );
        _phase = await _repository.getPhase(_phase.id) ?? _phase;
      }
      final base = buildBase();
      final from = editableFrom.clamp(0, _phase.totalWeeks);
      await _repository.savePhaseSetup(
        _phase.id,
        name: trimmedName,
        templateKey: kind.key,
        color: color,
        intent: intent.text,
        fromWeek: from,
        weeks: [
          for (var week = from; week < _phase.totalWeeks; week++)
            targetForWeek(week, base: base)!,
        ],
      );
      dirty = false;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    for (final controller in [
      name,
      intent,
      caloriesText,
      proteinText,
      fatText,
      restCaloriesText,
      runKmText,
      targetWeightText,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  static double? _parse(String raw) {
    final value = double.tryParse(raw.trim().replaceAll(',', '.'));
    return value == null || !value.isFinite || value <= 0 ? null : value;
  }

  static String _format(double? value, {int decimals = 0}) {
    if (value == null) return '';
    if (decimals == 0 || value == value.roundToDouble()) {
      return value.round().toString();
    }
    return AppNumberFormat.decimal(value, decimals);
  }
}
