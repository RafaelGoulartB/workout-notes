import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_plan.dart';
import 'package:workout_notes/repositories/run_repository.dart';
import 'package:workout_notes/screens/run/plan_wizard/run_plan_wizard_time.dart';
import 'package:workout_notes/services/run_pace_calculator.dart';
import 'package:workout_notes/services/run_plan_composer.dart';
import 'package:workout_notes/services/run_plan_history.dart';
import 'package:workout_notes/services/run_plan_templates.dart';
import 'package:workout_notes/services/run_plan_text.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/widgets/run/run_plan_ui.dart';

/// Where the athlete can do hill-type strength work.
enum RunPlanWizardTerrain { hill, stairs, treadmill, flat }

/// Number of wizard steps: days, intent/volume, paces, preview.
const int kRunPlanWizardSteps = 4;

/// State and derived plan maths of [RunPlanCustomizeScreen]. Steps read from
/// it and call its mutators; every mutator notifies so the screen rebuilds.
class RunPlanWizardController extends ChangeNotifier {
  final RunPlanTemplate template;

  /// Clock for race-date maths (tests).
  final DateTime? todayOverride;

  final _runRepo = RunRepository();
  final currentCtl = TextEditingController();
  final goalCtl = TextEditingController();
  final weeklyKmCtl = TextEditingController();
  final nameCtl = TextEditingController();

  int step = 0;
  late int sessions;
  late int weeks;
  final Set<int> days = {};
  int? longRunDay;
  RunPlanIntent intent = RunPlanIntent.finish;
  RunPlanIntensity intensity = RunPlanIntensity.standard;
  RunPlanWizardTerrain terrain = RunPlanWizardTerrain.hill;
  bool includeStrength = true;
  bool includeTest = true;
  late double currentDistanceMeters;
  DateTime? raceDate;
  RunPlanHistoryInsights? history;
  int previewWeek = 0;
  RunPlanLanguage language = RunPlanLanguage.pt;

  bool _historyApplied = false;
  bool _nameSeeded = false;
  bool _touched = false;
  bool _advanced = false;
  bool _disposed = false;

  RunPlanWizardController({
    required this.template,
    RunPlanHistoryInsights? history,
    this.todayOverride,
  }) {
    // Templates cap what they allow (a run/walk progression tops out at four
    // days), so the default has to be a value the user can actually re-pick.
    final allowed = template.allowedSessionsPerWeek;
    final preferred = template.sessionsPerWeek.clamp(3, 5);
    sessions = allowed.contains(preferred) ? preferred : allowed.last;
    weeks = template.defaultSelectableWeeks;
    currentDistanceMeters = goalDistance ?? RunPaceCalculator.fiveKMeters;
    seedDefaultDays();
    if (pbOnly) {
      intent = RunPlanIntent.pb;
    } else if (isMaintain || _finishTemplates.contains(template.key)) {
      intent = RunPlanIntent.finish;
    } else if (template.style == RunPlanTemplateStyle.performance ||
        template.raceFinish) {
      intent = RunPlanIntent.pb;
    }
    this.history = history;
    if (history != null) {
      _applyHistory(history);
    } else {
      _loadHistory();
    }
  }

  static const _finishTemplates = {
    'return',
    'return_injury',
    'first_5k',
    'first_10k',
    'to_half',
    'first_half',
    'first_marathon',
  };

  static const standardDistances = [
    RunPaceCalculator.fiveKMeters,
    RunPaceCalculator.tenKMeters,
    RunPaceCalculator.halfMeters,
    RunPaceCalculator.marathonMeters,
  ];

  // ===================== TEMPLATE FLAGS =====================

  bool get isPt => language == RunPlanLanguage.pt;
  bool get isMaintain => template.maintainFitness;
  bool get isRunWalk => template.style == RunPlanTemplateStyle.runWalk;

  /// Race distance this template trains for, or null for base / maintenance.
  double? get goalDistance => switch (template.goalKind) {
    RunPlanGoalKind.fiveK => RunPaceCalculator.fiveKMeters,
    RunPlanGoalKind.tenK => RunPaceCalculator.tenKMeters,
    RunPlanGoalKind.half => RunPaceCalculator.halfMeters,
    RunPlanGoalKind.marathon => RunPaceCalculator.marathonMeters,
    _ => null,
  };

  /// The plan ends in a race, so a race date can align it.
  bool get hasRace =>
      goalDistance != null &&
      !isMaintain &&
      (template.raceFinish ||
          template.style == RunPlanTemplateStyle.performance);

  /// Templates whose whole point is a faster time — asking "finish or PB?"
  /// there is noise.
  bool get pbOnly => const {
    '5k',
    '5k_advanced',
    '10k',
    '10k_advanced',
    'half_pb',
    'marathon_pb',
    'race_sharpen',
  }.contains(template.key);

  /// Hill sessions can appear in this template.
  bool get canHaveHills =>
      template.style == RunPlanTemplateStyle.performance || isMaintain;

  /// Performance plans long enough for a checkpoint get the mid-plan test.
  bool get offersTest =>
      template.style == RunPlanTemplateStyle.performance &&
      template.weeks >= 8 &&
      !isMaintain;

  DateTime get today => todayOverride ?? DateTime.now();

  // ===================== DIRTY TRACKING =====================

  /// True once the athlete changed an answer or moved past the first step —
  /// closing the wizard then throws work away and asks first.
  bool get hasChanges => _touched || _advanced || step > 0;

  /// Marks an edit made outside the mutators (text fields).
  void markChanged() {
    _touched = true;
    notifyListeners();
  }

  void _change(VoidCallback apply) {
    apply();
    _touched = true;
    notifyListeners();
  }

  // ===================== NAVIGATION =====================

  void next() {
    if (step >= kRunPlanWizardSteps - 1) return;
    step++;
    _advanced = true;
    notifyListeners();
  }

  void back() {
    if (step == 0) return;
    step--;
    notifyListeners();
  }

  void goToStep(int value) {
    step = value;
    notifyListeners();
  }

  // ===================== HISTORY =====================

  Future<void> _loadHistory() async {
    try {
      final activities = await _runRepo.listActivities(limit: 80);
      if (_disposed) return;
      final insights = RunPlanHistoryInsights.from(
        activities,
        goalDistanceMeters: goalDistance ?? RunPaceCalculator.fiveKMeters,
      );
      history = insights;
      _applyHistory(insights);
      notifyListeners();
    } catch (_) {
      // Missing plugin / empty DB — the athlete still types the numbers.
    }
  }

  void _applyHistory(RunPlanHistoryInsights insights) {
    if (_historyApplied) return;
    _historyApplied = true;
    if (weeklyKmCtl.text.trim().isEmpty && insights.medianWeeklyKm != null) {
      weeklyKmCtl.text = _kmText(insights.medianWeeklyKm!);
    }
    final suggested = insights.suggestedRace;
    if (suggested != null && currentCtl.text.trim().isEmpty) {
      // A GPS effort is rarely an exact race distance. Show the equivalent
      // time at the standard distance whose chip is selected — "5 km in
      // 28:30" for a 5.7 km run would misstate the athlete's fitness.
      final distance = standardDistances.reduce(
        (a, b) =>
            (a - suggested.distanceMeters).abs() <
                (b - suggested.distanceMeters).abs()
            ? a
            : b,
      );
      final seconds = (suggested.distanceMeters - distance).abs() < 1
          ? suggested.timeSeconds
          : (RunPaceCalculator.racePaceFor(
                      RunPaceCalculator.vdotFor(
                        distanceMeters: suggested.distanceMeters,
                        timeSeconds: suggested.timeSeconds,
                      ),
                      distance,
                    ) *
                    distance /
                    1000)
                .round();
      currentDistanceMeters = distance;
      currentCtl.text = RunFormatters.duration(seconds);
    }
  }

  static String _kmText(double km) {
    final rounded = (km * 10).round() / 10;
    return RunFormatters.decimal(
      rounded,
      rounded == rounded.roundToDouble() ? 0 : 1,
    );
  }

  // ===================== MUTATORS =====================

  void seedDefaultDays() {
    days
      ..clear()
      ..addAll(_defaultDaysFor(sessions));
    if (longRunDay != null && !days.contains(longRunDay)) longRunDay = null;
  }

  static List<int> _defaultDaysFor(int sessions) => switch (sessions) {
    3 => const [2, 5, 7],
    5 => const [2, 4, 5, 6, 7],
    _ => const [2, 4, 5, 7],
  };

  void setSessions(int value) => _change(() {
    sessions = value;
    seedDefaultDays();
  });

  void setWeeks(int value) => _change(() => weeks = value);

  /// Adds/removes [day]; false when the week is already full (the caller says
  /// what to do instead of silently swapping a day picked earlier).
  bool toggleDay(int day, bool selected) {
    if (selected && days.length >= sessions) return false;
    _change(() {
      if (selected) {
        days.add(day);
      } else {
        days.remove(day);
        if (longRunDay == day) longRunDay = null;
      }
    });
    return true;
  }

  void setLongRunDay(int? day) => _change(() => longRunDay = day);
  void setRaceDate(DateTime? date) => _change(() => raceDate = date);
  void setIntent(RunPlanIntent value) => _change(() => intent = value);
  void setIntensity(RunPlanIntensity value) => _change(() => intensity = value);
  void setTerrain(RunPlanWizardTerrain value) => _change(() => terrain = value);
  void setIncludeStrength(bool value) => _change(() => includeStrength = value);
  void setIncludeTest(bool value) => _change(() => includeTest = value);
  void setCurrentDistance(double meters) =>
      _change(() => currentDistanceMeters = meters);
  void setPreviewWeek(int value) {
    previewWeek = value;
    notifyListeners();
  }

  // ===================== DERIVED =====================

  bool get daysValid => days.length == sessions;

  /// Current weekly volume, when the athlete filled it in.
  double? get currentWeeklyKm {
    final raw = weeklyKmCtl.text.trim().replaceAll(',', '.');
    if (raw.isEmpty) return null;
    final value = double.tryParse(raw);
    if (value == null || value < 0) return null;
    return value;
  }

  /// Seconds typed in [controller] for [distance]; null when empty.
  /// Returns -1 for text that is not a plausible time.
  static int? _typedSeconds(TextEditingController controller, double distance) {
    final raw = controller.text.trim();
    if (raw.isEmpty) return null;
    return parseRaceTime(raw, distance) ?? -1;
  }

  int? get currentSeconds => _typedSeconds(currentCtl, currentDistanceMeters);
  int? get goalSeconds {
    final distance = goalDistance;
    return distance == null ? null : _typedSeconds(goalCtl, distance);
  }

  RunPlanPaceCalibration? get currentCalibration {
    final seconds = currentSeconds;
    if (seconds == null || seconds < 0) return null;
    return RunPlanPaceCalibration(
      distanceMeters: currentDistanceMeters,
      timeSeconds: seconds,
    );
  }

  RunPlanPaceCalibration? get goalCalibration {
    final seconds = goalSeconds, distance = goalDistance;
    if (seconds == null || seconds < 0 || distance == null) return null;
    return RunPlanPaceCalibration(
      distanceMeters: distance,
      timeSeconds: seconds,
    );
  }

  bool get paceInputsValid =>
      (currentSeconds ?? 0) >= 0 && (goalSeconds ?? 0) >= 0;

  RunPlanBuildConfig get config {
    final current = currentCalibration;
    final goal = goalCalibration;
    return RunPlanBuildConfig(
      sessionsPerWeek: sessions,
      availableDays: (days.toList()..sort()),
      intent: intent,
      intensity: intensity,
      calibration: current ?? goal,
      paceSource: current != null
          ? RunPlanPaceSource.recent
          : RunPlanPaceSource.goal,
      goalCalibration: current != null ? goal : null,
      fitnessCalibration: current == null
          ? history?.suggestedRace?.calibration
          : null,
      raceDate: hasRace ? raceDate : null,
      startDate: today,
      currentWeeklyKm: currentWeeklyKm,
      includeHills: terrain != RunPlanWizardTerrain.flat,
      hillSurface: switch (terrain) {
        RunPlanWizardTerrain.stairs => RunPlanHillSurface.stairs,
        RunPlanWizardTerrain.treadmill => RunPlanHillSurface.treadmill,
        _ => RunPlanHillSurface.hill,
      },
      longRunDay: longRunDay != null && days.contains(longRunDay)
          ? longRunDay
          : null,
      weeks: template.selectableWeeks ? weeks : null,
      language: language,
      includeStrength: includeStrength,
      includeTest: includeTest,
    );
  }

  RunPlanOutline? get outline {
    if (!daysValid) return null;
    try {
      return RunPlanComposer.outline(template, config);
    } catch (_) {
      return null;
    }
  }

  bool canAdvance(RunPlanOutline? outline) => switch (step) {
    0 => daysValid,
    1 => true,
    2 => paceInputsValid,
    _ => daysValid && (outline?.readiness.canCreate ?? false),
  };

  // ===================== NAME =====================

  /// Fills the name with the template title once the locale is known.
  void seedName() {
    if (_nameSeeded) return;
    _nameSeeded = true;
    nameCtl.text = template.title(isPt);
  }

  /// Name typed by the athlete, or the template title when left blank.
  String get planName {
    final typed = nameCtl.text.trim();
    return typed.isEmpty ? template.title(isPt) : typed;
  }

  // ===================== LABELS =====================

  String distanceName(AppLocalizations loc, double meters) => switch (meters) {
    RunPaceCalculator.fiveKMeters => '5 km',
    RunPaceCalculator.tenKMeters => '10 km',
    RunPaceCalculator.halfMeters => loc.runPlanGoalHalf,
    RunPaceCalculator.marathonMeters => loc.runPlanGoalMarathon,
    _ => RunPlanUi.distanceLabel(meters),
  };

  @override
  void dispose() {
    _disposed = true;
    currentCtl.dispose();
    goalCtl.dispose();
    weeklyKmCtl.dispose();
    nameCtl.dispose();
    super.dispose();
  }
}
