import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_plan.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/repositories/run_plan_repository.dart';
import 'package:workout_notes/repositories/run_repository.dart';
import 'package:workout_notes/services/run_pace_calculator.dart';
import 'package:workout_notes/services/run_plan_composer.dart';
import 'package:workout_notes/services/run_plan_history.dart';
import 'package:workout_notes/services/run_plan_templates.dart';
import 'package:workout_notes/services/run_plan_text.dart';
import 'package:workout_notes/services/run_strength_planner.dart';
import 'package:workout_notes/services/runner_strength_routine.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/widgets/run/run_plan_ui.dart';
import 'package:workout_notes/widgets/run/run_plan_volume_sparkline.dart';

/// Where the athlete can do hill-type strength work.
enum _Terrain { hill, stairs, treadmill, flat }

/// Coach-style wizard: days → intent/volume → paces → preview → create.
class RunPlanCustomizeScreen extends StatefulWidget {
  final RunPlanTemplate template;

  /// When set, skips loading GPS history (tests).
  final RunPlanHistoryInsights? history;

  /// Clock for race-date maths (tests).
  final DateTime? today;

  const RunPlanCustomizeScreen({
    super.key,
    required this.template,
    this.history,
    this.today,
  });

  @override
  State<RunPlanCustomizeScreen> createState() => _RunPlanCustomizeScreenState();
}

class _RunPlanCustomizeScreenState extends State<RunPlanCustomizeScreen> {
  final _repo = RunPlanRepository();
  final _runRepo = RunRepository();
  final _currentCtl = TextEditingController();
  final _goalCtl = TextEditingController();
  final _weeklyKmCtl = TextEditingController();

  int _step = 0;
  late int _sessions;
  late int _weeks;
  final Set<int> _days = {};
  int? _longRunDay;
  RunPlanIntent _intent = RunPlanIntent.finish;
  RunPlanIntensity _intensity = RunPlanIntensity.standard;
  _Terrain _terrain = _Terrain.hill;
  bool _includeStrength = true;
  bool _includeTest = true;
  late double _currentDistanceMeters;
  DateTime? _raceDate;
  bool _creating = false;
  RunPlanHistoryInsights? _history;
  bool _historyApplied = false;
  int _previewWeek = 0;

  RunPlanTemplate get _template => widget.template;
  bool get _isMaintain => _template.maintainFitness;
  bool get _isRunWalk => _template.style == RunPlanTemplateStyle.runWalk;

  /// Race distance this template trains for, or null for base / maintenance.
  double? get _goalDistance => _raceDistance(_template.goalKind);

  /// The plan ends in a race, so a race date can align it.
  bool get _hasRace =>
      _goalDistance != null &&
      !_isMaintain &&
      (_template.raceFinish ||
          _template.style == RunPlanTemplateStyle.performance);

  /// Templates whose whole point is a faster time — asking "finish or PB?"
  /// there is noise.
  bool get _pbOnly => const {
    '5k',
    '5k_advanced',
    '10k',
    '10k_advanced',
    'half_pb',
    'marathon_pb',
    'race_sharpen',
  }.contains(_template.key);

  /// Hill sessions can appear in this template.
  bool get _canHaveHills =>
      _template.style == RunPlanTemplateStyle.performance || _isMaintain;

  DateTime get _today => widget.today ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    // Templates cap what they allow (a run/walk progression tops out at four
    // days), so the default has to be a value the user can actually re-pick.
    final allowed = _template.allowedSessionsPerWeek;
    final preferred = _template.sessionsPerWeek.clamp(3, 5);
    _sessions = allowed.contains(preferred) ? preferred : allowed.last;
    _weeks = _template.defaultSelectableWeeks;
    _currentDistanceMeters = _goalDistance ?? RunPaceCalculator.fiveKMeters;
    _seedDefaultDays();
    if (_pbOnly) {
      _intent = RunPlanIntent.pb;
    } else if (_isMaintain ||
        const {
          'return',
          'return_injury',
          'first_5k',
          'first_10k',
          'to_half',
          'first_half',
          'first_marathon',
        }.contains(_template.key)) {
      _intent = RunPlanIntent.finish;
    } else if (_template.style == RunPlanTemplateStyle.performance ||
        _template.raceFinish) {
      _intent = RunPlanIntent.pb;
    }
    _history = widget.history;
    if (_history != null) {
      _applyHistory(_history!);
    } else {
      _loadHistory();
    }
  }

  Future<void> _loadHistory() async {
    try {
      final activities = await _runRepo.listActivities(limit: 80);
      if (!mounted) return;
      final insights = RunPlanHistoryInsights.from(
        activities,
        goalDistanceMeters: _goalDistance ?? RunPaceCalculator.fiveKMeters,
      );
      setState(() {
        _history = insights;
        _applyHistory(insights);
      });
    } catch (_) {
      // Missing plugin / empty DB — the athlete still types the numbers.
    }
  }

  void _applyHistory(RunPlanHistoryInsights insights) {
    if (_historyApplied) return;
    _historyApplied = true;
    if (_weeklyKmCtl.text.trim().isEmpty && insights.medianWeeklyKm != null) {
      _weeklyKmCtl.text = _formatKmValue(insights.medianWeeklyKm!);
    }
    final suggested = insights.suggestedRace;
    if (suggested != null && _currentCtl.text.trim().isEmpty) {
      // A GPS effort is rarely an exact race distance. Show the equivalent
      // time at the standard distance whose chip is selected — "5 km in
      // 28:30" for a 5.7 km run would misstate the athlete's fitness.
      final distance = _standardDistances.reduce(
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
      _currentDistanceMeters = distance;
      _currentCtl.text = _formatDuration(seconds);
    }
  }

  @override
  void dispose() {
    _currentCtl.dispose();
    _goalCtl.dispose();
    _weeklyKmCtl.dispose();
    super.dispose();
  }

  /// Current weekly volume, when the athlete filled it in.
  double? get _currentWeeklyKm {
    final raw = _weeklyKmCtl.text.trim().replaceAll(',', '.');
    if (raw.isEmpty) return null;
    final value = double.tryParse(raw);
    if (value == null || value < 0) return null;
    return value;
  }

  void _seedDefaultDays() {
    _days
      ..clear()
      ..addAll(_defaultDaysFor(_sessions));
    if (_longRunDay != null && !_days.contains(_longRunDay)) {
      _longRunDay = null;
    }
  }

  static List<int> _defaultDaysFor(int sessions) => switch (sessions) {
    3 => const [2, 5, 7],
    5 => const [2, 4, 5, 6, 7],
    _ => const [2, 4, 5, 7],
  };

  static const _standardDistances = [
    RunPaceCalculator.fiveKMeters,
    RunPaceCalculator.tenKMeters,
    RunPaceCalculator.halfMeters,
    RunPaceCalculator.marathonMeters,
  ];

  static String _distanceName(AppLocalizations loc, double meters) =>
      switch (meters) {
        RunPaceCalculator.fiveKMeters => '5 km',
        RunPaceCalculator.tenKMeters => '10 km',
        RunPaceCalculator.halfMeters => loc.runPlanGoalHalf,
        RunPaceCalculator.marathonMeters => loc.runPlanGoalMarathon,
        _ => RunPlanUi.distanceLabel(meters),
      };

  static double? _raceDistance(RunPlanGoalKind goal) => switch (goal) {
    RunPlanGoalKind.fiveK => RunPaceCalculator.fiveKMeters,
    RunPlanGoalKind.tenK => RunPaceCalculator.tenKMeters,
    RunPlanGoalKind.half => RunPaceCalculator.halfMeters,
    RunPlanGoalKind.marathon => RunPaceCalculator.marathonMeters,
    _ => null,
  };

  bool get _daysValid => _days.length == _sessions;

  /// Seconds typed in [controller] for [distance]; null when empty.
  /// Returns -1 for text that is not a plausible time.
  static int? _typedSeconds(TextEditingController controller, double distance) {
    final raw = controller.text.trim();
    if (raw.isEmpty) return null;
    return parseRaceTime(raw, distance) ?? -1;
  }

  int? get _currentSeconds =>
      _typedSeconds(_currentCtl, _currentDistanceMeters);
  int? get _goalSeconds {
    final distance = _goalDistance;
    return distance == null ? null : _typedSeconds(_goalCtl, distance);
  }

  RunPlanPaceCalibration? get _currentCalibration {
    final seconds = _currentSeconds;
    if (seconds == null || seconds < 0) return null;
    return RunPlanPaceCalibration(
      distanceMeters: _currentDistanceMeters,
      timeSeconds: seconds,
    );
  }

  RunPlanPaceCalibration? get _goalCalibration {
    final seconds = _goalSeconds, distance = _goalDistance;
    if (seconds == null || seconds < 0 || distance == null) return null;
    return RunPlanPaceCalibration(
      distanceMeters: distance,
      timeSeconds: seconds,
    );
  }

  bool get _paceInputsValid =>
      (_currentSeconds ?? 0) >= 0 && (_goalSeconds ?? 0) >= 0;

  RunPlanBuildConfig get _config {
    final current = _currentCalibration;
    final goal = _goalCalibration;
    return RunPlanBuildConfig(
      sessionsPerWeek: _sessions,
      availableDays: (_days.toList()..sort()),
      intent: _intent,
      intensity: _intensity,
      calibration: current ?? goal,
      paceSource: current != null
          ? RunPlanPaceSource.recent
          : RunPlanPaceSource.goal,
      goalCalibration: current != null ? goal : null,
      fitnessCalibration: current == null
          ? _history?.suggestedRace?.calibration
          : null,
      raceDate: _hasRace ? _raceDate : null,
      startDate: _today,
      currentWeeklyKm: _currentWeeklyKm,
      includeHills: _terrain != _Terrain.flat,
      hillSurface: switch (_terrain) {
        _Terrain.stairs => RunPlanHillSurface.stairs,
        _Terrain.treadmill => RunPlanHillSurface.treadmill,
        _ => RunPlanHillSurface.hill,
      },
      longRunDay: _longRunDay != null && _days.contains(_longRunDay)
          ? _longRunDay
          : null,
      weeks: _template.selectableWeeks ? _weeks : null,
      language: Localizations.localeOf(context).languageCode == 'pt'
          ? RunPlanLanguage.pt
          : RunPlanLanguage.en,
      includeStrength: _includeStrength,
      includeTest: _includeTest,
    );
  }

  /// Performance plans long enough for a checkpoint get the mid-plan test.
  bool get _offersTest =>
      _template.style == RunPlanTemplateStyle.performance &&
      _template.weeks >= 8 &&
      !_isMaintain;

  RunPlanOutline? get _outline {
    if (!_daysValid) return null;
    try {
      return RunPlanComposer.outline(_template, _config);
    } catch (_) {
      return null;
    }
  }

  static String _km(double value) => value.toStringAsFixed(0);

  static String _formatKmValue(double km) {
    final rounded = (km * 10).round() / 10;
    if (rounded == rounded.roundToDouble()) {
      return rounded.toStringAsFixed(0);
    }
    return rounded.toStringAsFixed(1);
  }

  String _date(DateTime date) =>
      MaterialLocalizations.of(context).formatMediumDate(date);

  /// Opens [template] in a fresh wizard; a plan created there closes this one.
  Future<void> _switchTo(RunPlanTemplate template) async {
    final plan = await Navigator.push<RunPlan>(
      context,
      MaterialPageRoute(
        builder: (_) => RunPlanCustomizeScreen(
          template: template,
          history: _history,
          today: widget.today,
        ),
      ),
    );
    if (plan != null && mounted) Navigator.pop(context, plan);
  }

  /// Coach warnings for the current step. Days step: only the schedule smell;
  /// preview step: everything, so the athlete sees it right before creating.
  Widget _buildWarnings(
    AppLocalizations loc,
    ThemeData theme,
    RunPlanOutline? outline, {
    required bool full,
  }) {
    final readiness = outline?.readiness;
    if (readiness == null) return const SizedBox.shrink();
    final isPt = Localizations.localeOf(context).languageCode == 'pt';
    final messages = <String>[];
    final actions = <(String, VoidCallback)>[];
    void action(String label, VoidCallback onTap) {
      if (actions.every((a) => a.$1 != label)) actions.add((label, onTap));
    }

    if (readiness.consecutiveDays) {
      messages.add(loc.runPlanCustomizeWarnConsecutiveDays);
    }
    if (full && readiness.raceTooSoon) {
      messages.add(
        loc.runPlanCustomizeWarnRaceTooSoon(
          readiness.weeksToRace ?? 0,
          readiness.minWeeks,
        ),
      );
      action(
        loc.runPlanCustomizeActionPickDate,
        () => setState(() => _step = 0),
      );
    }
    if (full && readiness.baselineZero) {
      messages.add(loc.runPlanCustomizeWarnZeroBaseline);
      action(
        loc.runPlanCustomizeActionStartRunning,
        () => _switchTo(RunPlanTemplates.runWalk),
      );
    }
    if (full && readiness.volumeGap) {
      messages.add(
        loc.runPlanCustomizeWarnVolumeGap(
          _km(readiness.startWeeklyKm),
          _km(readiness.currentWeeklyKm ?? 0),
        ),
      );
    }
    if (full && readiness.thinSessions) {
      messages.add(loc.runPlanCustomizeWarnThinSessions);
    }
    if (full && (readiness.volumeGap || readiness.thinSessions)) {
      if (_sessions > 3 && _template.allowedSessionsPerWeek.contains(3)) {
        action(
          loc.runPlanCustomizeActionThreeDays,
          () => setState(() {
            _sessions = 3;
            _seedDefaultDays();
          }),
        );
      }
      if (readiness.volumeGap && _intensity != RunPlanIntensity.conservative) {
        action(
          loc.runPlanCustomizeActionConservative,
          () => setState(() => _intensity = RunPlanIntensity.conservative),
        );
      }
    }
    if (full && readiness.timeCapDistanceGap) {
      messages.add(
        loc.runPlanCustomizeWarnTimeCapGap(
          _km(readiness.longRunCapKm),
          _km(readiness.requiredLongKm),
        ),
      );
    } else if (full && readiness.longRunShort) {
      messages.add(
        loc.runPlanCustomizeWarnLongRunShort(
          _km(readiness.peakLongKm),
          _km(readiness.requiredLongKm),
        ),
      );
    }
    if (full && (readiness.longRunShort || readiness.baselineZero)) {
      final shorter = RunPlanTemplates.shorterGoal(_template);
      if (shorter != null && shorter.key != RunPlanTemplates.runWalk.key) {
        action(
          loc.runPlanCustomizeActionTryPlan(shorter.title(isPt)),
          () => _switchTo(shorter),
        );
      }
    }
    if (full && readiness.needsHillAccess) {
      messages.add(loc.runPlanCustomizeWarnNeedsHills);
      final threshold = RunPlanTemplates.thresholdBlock;
      action(
        loc.runPlanCustomizeActionTryPlan(threshold.title(isPt)),
        () => _switchTo(threshold),
      );
    }
    if (messages.isEmpty) return const SizedBox.shrink();
    final scheme = theme.colorScheme;
    final blocking = full && !readiness.canCreate;
    final background = blocking
        ? scheme.errorContainer
        : scheme.tertiaryContainer;
    final foreground = blocking
        ? scheme.onErrorContainer
        : scheme.onTertiaryContainer;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        color: background,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: foreground),
                  const SizedBox(width: 8),
                  Text(
                    loc.runPlanCustomizeWarnTitle,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: foreground,
                    ),
                  ),
                ],
              ),
              for (final message in messages) ...[
                const SizedBox(height: 8),
                Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(color: foreground),
                ),
              ],
              if (blocking) ...[
                const SizedBox(height: 8),
                Text(
                  loc.runPlanCustomizeBlocked,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final (label, onTap) in actions)
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: foreground,
                          side: BorderSide(color: foreground),
                        ),
                        onPressed: onTap,
                        child: Text(label),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _create() async {
    final outline = _outline;
    if (_creating || !_daysValid || !(outline?.readiness.canCreate ?? false)) {
      return;
    }
    setState(() => _creating = true);
    try {
      final isPt = Localizations.localeOf(context).languageCode == 'pt';
      final plan = await RunPlanTemplates.create(
        _repo,
        _template,
        name: _template.title(isPt),
        config: _config,
      );
      if (_includeStrength) {
        try {
          await RunnerStrengthRoutine().ensure(pt: isPt);
        } catch (_) {
          // The plan stands on its own; strength can be set up later.
        }
      }
      if (!mounted) return;
      Navigator.pop(context, plan);
    } catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
      final loc = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.commonError(e.toString()))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isPt = Localizations.localeOf(context).languageCode == 'pt';
    final outline = _outline;
    final canNext = switch (_step) {
      0 => _daysValid,
      1 => true,
      2 => _paceInputsValid,
      _ => _daysValid && (outline?.readiness.canCreate ?? false),
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.runPlanCustomizeTitle),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _template.title(isPt),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  loc.runPlanCustomizeSubtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (var i = 0; i < 4; i++)
                      Expanded(
                        child: Container(
                          height: 4,
                          margin: EdgeInsets.only(right: i < 3 ? 6 : 0),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(2),
                            color: i <= _step
                                ? theme.colorScheme.primary
                                : theme.colorScheme.surfaceContainerHighest,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_step == 0) _buildDaysStep(loc, theme, outline),
                if (_step == 1) _buildIntentStep(loc, theme),
                if (_step == 2) _buildPaceStep(loc, theme, outline),
                if (_step == 3) _buildPreviewStep(loc, theme, outline),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  if (_step > 0)
                    TextButton(
                      onPressed: _creating
                          ? null
                          : () => setState(() => _step--),
                      child: Text(loc.runPlanCustomizeBack),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: !canNext || _creating
                        ? null
                        : () {
                            if (_step < 3) {
                              setState(() => _step++);
                            } else {
                              _create();
                            }
                          },
                    child: _creating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _step < 3
                                ? loc.runPlanCustomizeNext
                                : loc.runPlanCustomizeCreate,
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<String> _weekdayLabels(AppLocalizations loc) => [
    loc.runPlanCustomizeWeekdayMon,
    loc.runPlanCustomizeWeekdayTue,
    loc.runPlanCustomizeWeekdayWed,
    loc.runPlanCustomizeWeekdayThu,
    loc.runPlanCustomizeWeekdayFri,
    loc.runPlanCustomizeWeekdaySat,
    loc.runPlanCustomizeWeekdaySun,
  ];

  Widget _buildDaysStep(
    AppLocalizations loc,
    ThemeData theme,
    RunPlanOutline? outline,
  ) {
    final labels = _weekdayLabels(loc);
    final readiness = outline?.readiness;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    String? raceNote;
    if (_hasRace && _raceDate != null && readiness != null && outline != null) {
      final weeksToRace = readiness.weeksToRace;
      final plannedWeeks = outline.schedule.length;
      if (readiness.raceTooSoon) {
        raceNote = loc.runPlanCustomizeWarnRaceTooSoon(
          weeksToRace ?? 0,
          readiness.minWeeks,
        );
      } else if (weeksToRace != null && weeksToRace < _template.weeks) {
        raceNote = loc.runPlanCustomizeRaceCompressed(plannedWeeks);
      } else if (outline.startWeek != null) {
        raceNote = loc.runPlanCustomizeRaceStartsLater(
          plannedWeeks,
          _date(outline.startWeek!),
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(loc.runPlanCustomizeDaysTitle, style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          loc.runPlanCustomizeDaysHelp,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final n in _template.allowedSessionsPerWeek)
              ChoiceChip(
                label: Text(loc.runPlanCustomizeSessions(n)),
                selected: _sessions == n,
                onSelected: (_) => setState(() {
                  _sessions = n;
                  _seedDefaultDays();
                }),
              ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          loc.runPlanCustomizePickDays(_sessions),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var d = 1; d <= 7; d++)
              FilterChip(
                label: Text(labels[d - 1]),
                selected: _days.contains(d),
                onSelected: (selected) {
                  if (selected && _days.length >= _sessions) {
                    // Silently swapping a day the athlete picked earlier was
                    // confusing; say what to do instead.
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        SnackBar(
                          content: Text(
                            loc.runPlanCustomizeDaysFull(_sessions),
                          ),
                        ),
                      );
                    return;
                  }
                  setState(() {
                    if (selected) {
                      _days.add(d);
                    } else {
                      _days.remove(d);
                      if (_longRunDay == d) _longRunDay = null;
                    }
                  });
                },
              ),
          ],
        ),
        if (!_daysValid) ...[
          const SizedBox(height: 12),
          Text(
            loc.runPlanCustomizePickDays(_sessions),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        if (!_isRunWalk && _daysValid) ...[
          const SizedBox(height: 24),
          Text(
            loc.runPlanCustomizeLongRunDay,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: Text(loc.runPlanCustomizeLongRunAuto),
                selected: _longRunDay == null,
                onSelected: (_) => setState(() => _longRunDay = null),
              ),
              for (final d in (_days.toList()..sort()))
                ChoiceChip(
                  label: Text(labels[d - 1]),
                  selected: _longRunDay == d,
                  onSelected: (_) => setState(() => _longRunDay = d),
                ),
            ],
          ),
        ],
        if (_template.selectableWeeks) ...[
          const SizedBox(height: 24),
          Text(
            loc.runPlanCustomizeWeeksTitle,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Text(loc.runPlanCustomizeWeeksHelp, style: muted),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final n in _template.allowedWeeks)
                ChoiceChip(
                  label: Text(loc.runPlanWeeksValue(n)),
                  selected: _weeks == n,
                  onSelected: (_) => setState(() => _weeks = n),
                ),
            ],
          ),
        ],
        _buildWarnings(loc, theme, outline, full: false),
        if (_hasRace) ...[
          const SizedBox(height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(loc.runPlanCustomizeRaceDate),
            subtitle: Text(
              _raceDate == null ? loc.runPlanRaceDateNone : _date(_raceDate!),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_raceDate != null)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() => _raceDate = null),
                  ),
                IconButton(
                  icon: Icon(
                    _raceDate == null
                        ? Icons.event_outlined
                        : Icons.event_available,
                  ),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate:
                          _raceDate ??
                          _today.add(Duration(days: 7 * _template.weeks)),
                      firstDate: _today,
                      lastDate: _today.add(const Duration(days: 800)),
                    );
                    if (picked != null) setState(() => _raceDate = picked);
                  },
                ),
              ],
            ),
          ),
          if (raceNote != null)
            Text(
              raceNote,
              style: readiness!.raceTooSoon
                  ? theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    )
                  : muted,
            ),
        ],
      ],
    );
  }

  Widget _buildIntentStep(AppLocalizations loc, ThemeData theme) {
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _isMaintain
              ? loc.runPlanCustomizeMaintainTitle
              : loc.runPlanCustomizeIntentTitle,
          style: theme.textTheme.titleLarge,
        ),
        if (_isMaintain || !_pbOnly) ...[
          const SizedBox(height: 8),
          Text(
            _isMaintain
                ? loc.runPlanCustomizeMaintainHelp
                : loc.runPlanCustomizeIntentHelp,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (!_isMaintain && !_pbOnly && !_isRunWalk) ...[
          const SizedBox(height: 16),
          _OptionCard(
            selected: _intent == RunPlanIntent.finish,
            title: loc.runPlanCustomizeIntentFinish,
            subtitle: loc.runPlanCustomizeIntentFinishHint,
            onTap: () => setState(() => _intent = RunPlanIntent.finish),
          ),
          const SizedBox(height: 8),
          _OptionCard(
            selected: _intent == RunPlanIntent.pb,
            title: loc.runPlanCustomizeIntentPb,
            subtitle: loc.runPlanCustomizeIntentPbHint,
            onTap: () => setState(() => _intent = RunPlanIntent.pb),
          ),
        ],
        const SizedBox(height: 24),
        Text(loc.runPlanCustomizeIntensity, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final value in RunPlanIntensity.values)
              ChoiceChip(
                label: Text(switch (value) {
                  RunPlanIntensity.conservative =>
                    loc.runPlanCustomizeIntensityConservative,
                  RunPlanIntensity.standard =>
                    loc.runPlanCustomizeIntensityStandard,
                  RunPlanIntensity.aggressive =>
                    loc.runPlanCustomizeIntensityAggressive,
                }),
                selected: _intensity == value,
                onSelected: (_) => setState(() => _intensity = value),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(switch (_intensity) {
          RunPlanIntensity.conservative =>
            loc.runPlanCustomizeIntensityConservativeHint,
          RunPlanIntensity.standard =>
            loc.runPlanCustomizeIntensityStandardHint,
          RunPlanIntensity.aggressive =>
            loc.runPlanCustomizeIntensityAggressiveHint,
        }, style: muted),
        if (_canHaveHills) ...[
          const SizedBox(height: 24),
          Text(
            loc.runPlanCustomizeTerrainTitle,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final terrain in _Terrain.values)
                ChoiceChip(
                  avatar: Icon(switch (terrain) {
                    _Terrain.hill => Icons.landscape_outlined,
                    _Terrain.stairs => Icons.stairs_outlined,
                    _Terrain.treadmill => Icons.directions_run,
                    _Terrain.flat => Icons.horizontal_rule,
                  }, size: 18),
                  label: Text(switch (terrain) {
                    _Terrain.hill => loc.runPlanCustomizeTerrainHill,
                    _Terrain.stairs => loc.runPlanCustomizeTerrainStairs,
                    _Terrain.treadmill => loc.runPlanCustomizeTerrainTreadmill,
                    _Terrain.flat => loc.runPlanCustomizeTerrainFlat,
                  }),
                  selected: _terrain == terrain,
                  onSelected: (_) => setState(() => _terrain = terrain),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(switch (_terrain) {
            _Terrain.hill => loc.runPlanCustomizeTerrainHillHelp,
            _Terrain.stairs => loc.runPlanCustomizeTerrainStairsHelp,
            _Terrain.treadmill => loc.runPlanCustomizeTerrainTreadmillHelp,
            _Terrain.flat => loc.runPlanCustomizeTerrainFlatHelp,
          }, style: muted),
        ],
        const SizedBox(height: 16),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.fitness_center_rounded),
          title: Text(loc.runPlanCustomizeStrengthTitle),
          subtitle: Text(loc.runPlanCustomizeStrengthHelp),
          value: _includeStrength,
          onChanged: (value) => setState(() => _includeStrength = value),
        ),
        if (_offersTest)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.timer_outlined),
            title: Text(loc.runPlanCustomizeTestTitle),
            subtitle: Text(loc.runPlanCustomizeTestHelp),
            value: _includeTest,
            onChanged: (value) => setState(() => _includeTest = value),
          ),
        const SizedBox(height: 24),
        Text(
          loc.runPlanCustomizeBaselineTitle,
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Text(
          _isMaintain
              ? loc.runPlanCustomizeBaselineHelpMaintain
              : loc.runPlanCustomizeBaselineHelp,
          style: muted,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _weeklyKmCtl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: loc.runPlanCustomizeBaselineField,
            hintText: loc.runPlanCustomizeBaselineHint,
            suffixText: 'km',
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (_history?.medianWeeklyKm != null &&
            _history!.medianWeekCount > 0) ...[
          const SizedBox(height: 8),
          Text(
            loc.runPlanCustomizeBaselineFromHistory(_history!.medianWeekCount),
            style: muted,
          ),
        ],
      ],
    );
  }

  Widget _timeField(
    AppLocalizations loc,
    TextEditingController controller,
    int? seconds,
  ) => TextField(
    controller: controller,
    keyboardType: TextInputType.datetime,
    decoration: InputDecoration(
      labelText: loc.runPlanCustomizePaceTime,
      hintText: loc.runPlanCustomizePaceTimeHint,
      errorText: seconds != null && seconds < 0
          ? loc.runPlanCustomizeTimeInvalid
          : null,
      border: const OutlineInputBorder(),
    ),
    onChanged: (_) => setState(() {}),
  );

  Widget _buildPaceStep(
    AppLocalizations loc,
    ThemeData theme,
    RunPlanOutline? outline,
  ) {
    final distances = <(String, double)>[
      for (final meters in _standardDistances)
        (_distanceName(loc, meters), meters),
    ];
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final suggested = _history?.suggestedRace;
    final nearest = distances.reduce(
      (a, b) =>
          (a.$2 - _currentDistanceMeters).abs() <
              (b.$2 - _currentDistanceMeters).abs()
          ? a
          : b,
    );
    final goalDistance = _goalDistance;
    final ramp = outline?.paceRamp;
    final start = ramp?.pacesAt(0);
    final end = ramp?.targetPaces;
    final plannedWeeks = outline?.schedule.length ?? _template.weeks;
    final projected = goalDistance == null
        ? null
        : ramp?.projectedSeconds(goalDistance);
    final assessment =
        outline?.readiness.goalAssessment ?? RunPlanGoalAssessment.none;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(loc.runPlanCustomizePaceTitle, style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          loc.runPlanCustomizePaceHelp,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          loc.runPlanCustomizeCurrentTitle,
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(loc.runPlanCustomizeCurrentHelp, style: muted),
        if (suggested != null) ...[
          const SizedBox(height: 4),
          Text(
            loc.runPlanCustomizePaceFromRun(
              RunPlanUi.distanceLabel(suggested.distanceMeters),
              RunFormatters.duration(suggested.timeSeconds),
            ),
            style: muted,
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in distances)
              ChoiceChip(
                label: Text(entry.$1),
                selected: (nearest.$2 - entry.$2).abs() < 1,
                onSelected: (_) =>
                    setState(() => _currentDistanceMeters = entry.$2),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _timeField(loc, _currentCtl, _currentSeconds),
        if (goalDistance != null && !_isMaintain) ...[
          const SizedBox(height: 24),
          Text(
            loc.runPlanCustomizeGoalTitle(_distanceName(loc, goalDistance)),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(loc.runPlanCustomizeGoalHelp, style: muted),
          const SizedBox(height: 12),
          _timeField(loc, _goalCtl, _goalSeconds),
          if (_goalCalibration != null && _currentCalibration == null) ...[
            const SizedBox(height: 8),
            Text(loc.runPlanCustomizeGoalOnlyNote, style: muted),
          ],
        ],
        if (start != null) ...[
          const SizedBox(height: 20),
          Text(
            loc.runPlanCustomizePacePreview(
              RunPlanUi.paceLabel(start.easySecPerKm),
              RunPlanUi.paceLabel(start.tempoSecPerKm),
              RunPlanUi.paceLabel(start.intervalSecPerKm),
            ),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (end != null &&
              (end.tempoSecPerKm - start.tempoSecPerKm).abs() >= 1) ...[
            const SizedBox(height: 4),
            Text(
              loc.runPlanCustomizePaceEndPreview(
                RunPlanUi.paceLabel(end.tempoSecPerKm),
                RunPlanUi.paceLabel(end.intervalSecPerKm),
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (projected != null) ...[
            const SizedBox(height: 12),
            _GoalFeedback(
              assessment: assessment,
              message: switch (assessment) {
                RunPlanGoalAssessment.realistic =>
                  loc.runPlanCustomizeGoalRealistic(plannedWeeks),
                RunPlanGoalAssessment.ambitious =>
                  loc.runPlanCustomizeGoalAmbitious(
                    RunFormatters.duration(projected),
                  ),
                RunPlanGoalAssessment.unrealistic =>
                  loc.runPlanCustomizeGoalUnrealistic(
                    plannedWeeks,
                    RunFormatters.duration(projected),
                  ),
                RunPlanGoalAssessment.none => loc.runPlanCustomizeProjection(
                  RunFormatters.duration(projected),
                ),
              },
            ),
          ],
          const SizedBox(height: 8),
          Text(loc.runPlanCustomizePaceEstimateNote, style: muted),
        ],
      ],
    );
  }

  Widget _buildPreviewStep(
    AppLocalizations loc,
    ThemeData theme,
    RunPlanOutline? outline,
  ) {
    final total = outline?.schedule.length ?? 0;
    final weekIndex = total == 0 ? 0 : _previewWeek.clamp(0, total - 1);
    final week = [...?(total == 0 ? null : outline!.schedule[weekIndex])]
      ..sort((a, b) => a.dayOfWeek.compareTo(b.dayOfWeek));
    final weekOutline = total == 0 ? null : outline!.weeks[weekIndex];
    bool hasRace(int w) =>
        w >= 0 &&
        w < total &&
        outline!.schedule[w].any((s) => s.kind == RunWorkoutKind.race);
    final strengthDays = !_includeStrength || total == 0
        ? const <int>[]
        : RunStrengthPlanner.daysFor(
            [
              for (final s in week)
                (
                  day: s.dayOfWeek,
                  kind: s.kind,
                  km: (s.targetDistanceMeters ?? 0) / 1000,
                ),
            ],
            raceWeek: hasRace(weekIndex),
            weekBeforeRace: hasRace(weekIndex + 1),
          );
    final easyPace = outline?.paceRamp.pacesAt(weekIndex)?.easySecPerKm;
    final summary = <String>[
      if (outline != null && outline.peakWeeklyKm > 0)
        loc.runPlanCustomizePreviewPeak(_km(outline.peakWeeklyKm)),
      if (outline != null && outline.peakLongKm > 0)
        loc.runPlanCustomizePreviewLong(_km(outline.peakLongKm)),
      if (outline?.raceWeekNumber != null)
        loc.runPlanCustomizePreviewRaceWeek(outline!.raceWeekNumber!),
      if (outline?.startWeek != null)
        loc.runPlanCustomizeStartsOn(_date(outline!.startWeek!)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          loc.runPlanCustomizePreviewTitle,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          _isRunWalk
              ? loc.runPlanCustomizePreviewHelpRunWalk
              : _isMaintain
              ? loc.runPlanCustomizePreviewHelpMaintain
              : loc.runPlanCustomizePreviewHelp,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        _buildWarnings(loc, theme, outline, full: true),
        if (outline != null && outline.hasVolumeCurve) ...[
          const SizedBox(height: 16),
          RunPlanVolumeSparkline(
            weeks: outline.weeks,
            selected: weekIndex,
            onSelect: (i) => setState(() => _previewWeek = i),
          ),
        ],
        if (summary.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(summary.join(' · '), style: theme.textTheme.titleSmall),
        ],
        if (week.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: weekIndex > 0
                    ? () => setState(() => _previewWeek = weekIndex - 1)
                    : null,
              ),
              Expanded(
                child: Text(
                  [
                    loc.runPlanCustomizeWeekOf(weekIndex + 1, total),
                    if (weekOutline != null && !_isRunWalk)
                      RunPlanVolumeSparkline.phaseLabel(loc, weekOutline.phase),
                    if (weekOutline != null && weekOutline.weekKm >= 1)
                      '${_km(weekOutline.weekKm)} km',
                  ].join(' · '),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: weekIndex < total - 1
                    ? () => setState(() => _previewWeek = weekIndex + 1)
                    : null,
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        for (final session in week)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Icon(
                RunPlanUi.kindIcon(session.kind),
                color: RunPlanUi.kindColor(theme.colorScheme, session.kind),
              ),
              title: Text(session.name),
              subtitle: Text(
                [
                  RunPlanUi.weekdayLabel(loc, session.dayOfWeek),
                  RunPlanUi.kindLabel(loc, session.kind),
                  if (session.targetDistanceMeters != null)
                    RunPlanUi.distanceLabel(session.targetDistanceMeters!),
                  if (RunPlanComposer.estimateDurationSeconds(
                        session,
                        easySecPerKm: easyPace,
                      )
                      case final seconds?)
                    loc.runPlanCustomizeDuration((seconds / 60).round()),
                  if (session.targetPaceSecPerKm != null)
                    '${RunPlanUi.paceLabel(session.targetPaceSecPerKm)}/km',
                ].join(' · '),
              ),
            ),
          ),
        if (strengthDays.isNotEmpty)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Icon(
                Icons.fitness_center_rounded,
                color: theme.colorScheme.secondary,
              ),
              title: Text(
                loc.runPlanCustomizeStrengthDays(
                  strengthDays
                      .map((d) => RunPlanUi.weekdayLabel(loc, d))
                      .join(', '),
                ),
              ),
              subtitle: Text(loc.runPlanCustomizeStrengthHelp),
            ),
          ),
      ],
    );
  }
}

/// Colour-coded verdict on the goal time.
class _GoalFeedback extends StatelessWidget {
  final RunPlanGoalAssessment assessment;
  final String message;

  const _GoalFeedback({required this.assessment, required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground, icon) = switch (assessment) {
      RunPlanGoalAssessment.realistic => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
        Icons.check_circle_outline,
      ),
      RunPlanGoalAssessment.ambitious => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
        Icons.trending_up,
      ),
      RunPlanGoalAssessment.unrealistic => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        Icons.warning_amber_rounded,
      ),
      RunPlanGoalAssessment.none => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
        Icons.flag_outlined,
      ),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: foreground, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _OptionCard({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
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
  }
}

/// Parses a race time typed by a person, or null when it is not a plausible
/// time for [distanceMeters].
///
/// Accepts `h:mm:ss`, `mm:ss` and a bare number of minutes (`25` is a 25
/// minute 5K, never 25 seconds). A two-part entry that makes no sense as
/// minutes:seconds for a long race is read as hours:minutes (`1:55` for a
/// half marathon).
int? parseRaceTime(String raw, double distanceMeters) {
  final text = raw.trim().replaceAll('.', ':').replaceAll(',', ':');
  if (text.isEmpty) return null;
  bool plausible(int seconds) => RunPaceCalculator.isPlausibleRace(
    distanceMeters: distanceMeters,
    timeSeconds: seconds,
  );
  final parts = text.split(':');
  final numbers = parts.map(int.tryParse).toList();
  if (numbers.any((n) => n == null || n < 0)) return null;
  int? result;
  switch (numbers.length) {
    case 1:
      result = numbers[0]! * 60;
    case 2:
      final (a, b) = (numbers[0]!, numbers[1]!);
      if (b >= 60) return null;
      final asMinutes = a * 60 + b;
      final asHours = a * 3600 + b * 60;
      result = plausible(asMinutes) || !plausible(asHours)
          ? asMinutes
          : asHours;
    case 3:
      final (h, m, s) = (numbers[0]!, numbers[1]!, numbers[2]!);
      if (m >= 60 || s >= 60) return null;
      result = h * 3600 + m * 60 + s;
    default:
      return null;
  }
  return plausible(result) ? result : null;
}

String _formatDuration(int seconds) {
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final rest = seconds % 60;
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${rest.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:${rest.toString().padLeft(2, '0')}';
}
