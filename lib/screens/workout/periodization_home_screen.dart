import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/periodization_metrics.dart';
import 'package:workout_notes/models/periodization_phase.dart';
import 'package:workout_notes/models/periodization_plan.dart';
import 'package:workout_notes/models/periodization_routine_suggestion.dart';
import 'package:workout_notes/models/periodization_run_suggestion.dart';
import 'package:workout_notes/models/periodization_target.dart';
import 'package:workout_notes/navigation/ai_coach_navigation.dart';
import 'package:workout_notes/repositories/body_measurement_repository.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';
import 'package:workout_notes/repositories/run_plan_repository.dart';
import 'package:workout_notes/widgets/ai/ai_coach_header_button.dart';
import 'package:workout_notes/widgets/periodization/body_measurements_teaser_card.dart';
import 'package:workout_notes/screens/run/run_record_screen.dart';
import 'package:workout_notes/widgets/periodization/periodization_ui.dart';
import 'package:workout_notes/widgets/run/run_plan_ui.dart';

import 'body_tracker_screen.dart';
import 'periodization_calendar_screen.dart';
import 'active_workout_screen.dart';
import 'periodization_checkin_flow.dart';
import 'periodization_comparison_screen.dart';
import 'periodization_phase_detail_screen.dart';
import 'periodization_phase_form_screen.dart';
import 'periodization_plan_form_screen.dart';
import 'periodization_plans_screen.dart';
import 'settings_screen.dart';

class PeriodizationHomeScreen extends StatefulWidget {
  const PeriodizationHomeScreen({super.key});

  @override
  State<PeriodizationHomeScreen> createState() =>
      _PeriodizationHomeScreenState();
}

class _PeriodizationHomeScreenState extends State<PeriodizationHomeScreen> {
  final _repository = PeriodizationRepository();
  final _bodyRepo = BodyMeasurementRepository();
  PeriodizationPlan? _plan;
  List<PeriodizationPhase> _phases = const [];
  PeriodizationPhase? _currentPhase;
  PeriodizationTarget? _currentTarget;
  PeriodizationRoutineSuggestion? _routineSuggestion;
  PeriodizationRunSuggestion? _runSuggestion;
  bool _weekCheckinDone = false;

  /// Planned vs actual for the current week, across workouts, runs, nutrition
  /// and sleep. The numbers already existed for the phase report; this is the
  /// first place they answer "how is THIS week going".
  PeriodizationMetrics? _weekMetrics;
  double? _weightKg;
  String? _weightUnit;
  double? _weightDelta;
  String? _weightDate;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _loadWeightTeaser() async {
    final rows = await _bodyRepo.getBodyMeasurements(type: 'weight', limit: 2);
    if (rows.isEmpty) {
      _weightKg = null;
      _weightUnit = null;
      _weightDelta = null;
      _weightDate = null;
      return;
    }
    final latest = rows.first;
    final value = (latest['value'] as num?)?.toDouble();
    _weightKg = value;
    _weightUnit = latest['unit'] as String? ?? 'kg';
    _weightDate = latest['date'] as String?;
    if (rows.length >= 2 && value != null) {
      final previous = (rows[1]['value'] as num?)?.toDouble();
      _weightDelta = previous == null ? null : value - previous;
    } else {
      _weightDelta = null;
    }
  }

  Future<void> _load() async {
    final planFuture = _repository.getActivePlan();
    final weightFuture = _bodyRepo.getBodyMeasurements(
      type: 'weight',
      limit: 2,
    );
    final plan = await planFuture;
    final weightRows = await weightFuture;

    if (weightRows.isEmpty) {
      _weightKg = null;
      _weightUnit = null;
      _weightDelta = null;
      _weightDate = null;
    } else {
      final latest = weightRows.first;
      final value = (latest['value'] as num?)?.toDouble();
      _weightKg = value;
      _weightUnit = latest['unit'] as String? ?? 'kg';
      _weightDate = latest['date'] as String?;
      if (weightRows.length >= 2 && value != null) {
        final previous = (weightRows[1]['value'] as num?)?.toDouble();
        _weightDelta = previous == null ? null : value - previous;
      } else {
        _weightDelta = null;
      }
    }

    if (plan == null) {
      if (!mounted) return;
      setState(() {
        _plan = null;
        _phases = const [];
        _currentPhase = null;
        _currentTarget = null;
        _routineSuggestion = null;
        _runSuggestion = null;
        _weekCheckinDone = false;
        _weekMetrics = null;
        _loading = false;
      });
      return;
    }
    final phases = await _repository.getPhases(plan.id);
    PeriodizationPhase? current;
    for (final phase in phases) {
      if (phase.contains(DateTime.now())) {
        current = phase;
        break;
      }
    }
    final currentResults = current == null
        ? const <Object?>[null, null, null, null, null]
        : await Future.wait<Object?>([
            _repository.getEffectiveTarget(current.id),
            _repository.getRoutineSuggestion(DateTime.now()),
            _repository.getRunSuggestion(DateTime.now()),
            _repository.getCheckin(current.id, DateTime.now()),
            // The weekly card is informational, so a failure here must not
            // take the whole screen down with it.
            _repository
                .getWeekMetrics(current, DateTime.now())
                .then<Object?>((value) => value)
                .catchError((Object _) => null),
          ]);
    if (!mounted) return;
    setState(() {
      _plan = plan;
      _phases = phases;
      _currentPhase = current;
      _currentTarget = currentResults[0] as PeriodizationTarget?;
      _routineSuggestion = currentResults[1] as PeriodizationRoutineSuggestion?;
      _runSuggestion = currentResults[2] as PeriodizationRunSuggestion?;
      _weekCheckinDone = currentResults[3] != null;
      _weekMetrics = currentResults[4] as PeriodizationMetrics?;
      _loading = false;
    });
  }

  Future<void> _openBodyTracker() async {
    await Navigator.push(
      context,
      AiCoachNavigation.route(
        kind: AiCoachRouteKind.normalWithFab,
        builder: (_) => const BodyTrackerScreen(),
      ),
    );
    if (mounted) {
      await _loadWeightTeaser();
      setState(() {});
    }
  }

  Future<void> _createPlan() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const PeriodizationPlanFormScreen()),
    );
    if (changed == true) await _load();
  }

  Future<void> _openPlans() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PeriodizationPlansScreen()),
    );
    await _load();
  }

  Future<void> _openAppSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AppSettingsScreen()),
    );
    if (mounted) await _load();
  }

  Future<void> _openComparison() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PeriodizationComparisonScreen()),
    );
  }

  Future<void> _addPhase() async {
    final plan = _plan;
    if (plan == null) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PeriodizationPhaseFormScreen(plan: plan),
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _openPhase(PeriodizationPhase phase) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PeriodizationPhaseDetailScreen(plan: _plan!, phase: phase),
      ),
    );
    await _load();
  }

  /// Straight to the phase editor, where the targets live. The "no targets"
  /// call to action on the current-phase card lands here instead of the phase
  /// detail screen, which would only show empty "Meta: —" rows.
  Future<void> _editPhase(PeriodizationPhase phase) async {
    final plan = _plan;
    if (plan == null) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PeriodizationPhaseFormScreen(
          plan: plan,
          phase: phase,
          focusTargets: true,
        ),
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _startSuggestedWorkout() async {
    final suggestion = _routineSuggestion;
    if (suggestion == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ActiveWorkoutScreen(
          routineId: suggestion.routineId,
          routineDayId: suggestion.routineDayId,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _startSuggestedRun() async {
    final suggestion = _runSuggestion;
    if (suggestion == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RunRecordScreen(
          planWorkout: suggestion.workout,
          scheduledRun: suggestion.scheduled,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _runCheckin() async {
    final plan = _plan;
    final phase = _currentPhase;
    if (plan == null || phase == null) return;
    await PeriodizationCheckinFlow.run(
      context: context,
      plan: plan,
      phase: phase,
    );
    if (mounted) await _load();
  }

  /// Puts every remaining week of the phase's running plan on the calendar.
  /// Without this the plan only ever surfaced as "today's suggestion".
  Future<void> _scheduleRuns() async {
    final phase = _currentPhase;
    if (phase == null) return;
    final loc = AppLocalizations.of(context)!;
    final result = await _repository.scheduleRunPlanForPhase(phase);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(loc.periodizationRunScheduleDone(result.created)),
        // Filling weeks of calendar in one tap deserves a way back.
        action: result.isEmpty
            ? null
            : SnackBarAction(
                label: loc.commonUndo,
                onPressed: () async {
                  await RunPlanRepository().deleteScheduledRuns(
                    result.createdIds,
                  );
                  if (mounted) await _load();
                },
              ),
      ),
    );
    await _load();
  }

  void _openCalendar() {
    final plan = _plan;
    if (plan == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PeriodizationCalendarScreen(plan: plan),
      ),
    );
  }


  List<Widget> _planningSlivers(AppLocalizations loc, ThemeData theme) {
    if (_plan == null) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: PeriodizationEmptyState(
            icon: Icons.route_outlined,
            title: loc.periodizationNoActiveTitle,
            subtitle: loc.periodizationNoActiveSubtitle,
            primaryLabel: loc.periodizationCreatePlan,
            onPrimary: _createPlan,
            secondaryLabel: loc.periodizationHistory,
            onSecondary: _openPlans,
          ),
        ),
      ];
    }
    final now = DateTime.now();
    // Phases can be planned across a new year (a 33-week cycle usually is);
    // month/day alone would then be ambiguous in the timeline.
    final spansYears = _phases.isNotEmpty &&
        _phases.first.startDate.year != _phases.last.endDate.year;
    final phaseWeeks = _phases.fold<int>(
      0,
      (sum, phase) => sum + phase.totalWeeks,
    );
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        sliver: SliverToBoxAdapter(
          child: _PlanHero(
            plan: _plan!,
            phases: _phases,
            onTap: _openPlans,
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        sliver: SliverToBoxAdapter(
          child: _QuickActions(
            onCalendar: _openCalendar,
            onPlans: _openPlans,
            onCompare: _openComparison,
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
        sliver: SliverToBoxAdapter(
          child: PeriodizationSectionHeader(
            title: loc.periodizationNow,
            icon: Icons.my_location_rounded,
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverToBoxAdapter(
          child: _currentPhase == null
              ? PeriodizationSurface(
                  onTap: _openPlans,
                  child: Row(
                    children: [
                      Icon(
                        Icons.event_busy_outlined,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          loc.periodizationNoPhaseToday,
                          style: theme.textTheme.bodyLarge,
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                )
              : _CurrentPhaseCard(
                  phase: _currentPhase!,
                  target: _currentTarget,
                  routineSuggestion: _routineSuggestion,
                  runSuggestion: _runSuggestion,
                  onStartRun: _startSuggestedRun,
                  onTap: () => _openPhase(_currentPhase!),
                  onStartWorkout: _startSuggestedWorkout,
                  onCheckin: _runCheckin,
                  onEditTargets: () => _editPhase(_currentPhase!),
                  checkinDone: _weekCheckinDone,
                  onScheduleRuns: _scheduleRuns,
                  hasRunPlan: _currentTarget?.runPlanIds.isNotEmpty ?? false,
                ),
        ),
      ),
      if (_currentPhase != null && _weekMetrics != null) ...[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
          sliver: SliverToBoxAdapter(
            child: PeriodizationSectionHeader(
              title: loc.periodizationThisWeek,
              icon: Icons.insights_rounded,
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverToBoxAdapter(
            child: _WeekAdherenceCard(
              metrics: _weekMetrics!,
              accent: Color(_currentPhase!.color),
              onTap: () => _openPhase(_currentPhase!),
            ),
          ),
        ),
      ],
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
        sliver: SliverToBoxAdapter(
          child: PeriodizationSectionHeader(
            title: loc.periodizationPhasesSection,
            subtitle: _phases.isEmpty
                ? null
                : '${loc.periodizationPhaseCount(_phases.length)}'
                      '  ·  ${loc.periodizationDurationWeeks(phaseWeeks)}',
            icon: Icons.route_outlined,
            actionLabel: loc.periodizationAddPhase,
            onAction: _addPhase,
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverToBoxAdapter(
          child: _phases.isEmpty
              ? _NoPhasesCard(onAdd: _addPhase)
              : PeriodizationSurface(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: _VerticalPhaseTimeline(
                    phases: _phases,
                    referenceDate: now,
                    showYear: spansYears,
                    onPhaseTap: _openPhase,
                  ),
                ),
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 110)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          loc.trackingTitle,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: false,
        automaticallyImplyLeading: false,
        actions: [
          const AiCoachHeaderButton(),
          IconButton(
            tooltip: loc.periodizationCalendar,
            onPressed: _plan == null ? null : _openCalendar,
            icon: const Icon(Icons.calendar_month_outlined),
          ),
          IconButton(
            tooltip: loc.settingsTitle,
            onPressed: _openAppSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: _loading
          ? const _HomeSkeleton()
          : RefreshIndicator(
              onRefresh: _load,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    sliver: SliverToBoxAdapter(
                      child: BodyMeasurementsTeaserCard(
                        weightKg: _weightKg,
                        unit: _weightUnit,
                        delta: _weightDelta,
                        date: _weightDate,
                        onOpen: _openBodyTracker,
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                    sliver: SliverToBoxAdapter(
                      child: PeriodizationSectionHeader(
                        title: loc.periodizationTitle,
                        icon: Icons.route_outlined,
                      ),
                    ),
                  ),
                  ..._planningSlivers(loc, theme),
                ],
              ),
            ),
    );
  }
}

class _PlanHero extends StatelessWidget {
  final PeriodizationPlan plan;
  final List<PeriodizationPhase> phases;
  final VoidCallback onTap;

  const _PlanHero({
    required this.plan,
    required this.phases,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final now = DateTime.now();
    final totalWeeks = (plan.totalDays / 7).ceil();
    final currentWeek = now.isBefore(plan.startDate)
        ? 0
        : (now.difference(plan.startDate).inDays ~/ 7 + 1).clamp(1, totalWeeks);
    final progress = plan.progressAt(now);
    PeriodizationPhase? activePhase;
    for (final phase in phases) {
      if (phase.contains(now)) {
        activePhase = phase;
        break;
      }
    }
    final accent = activePhase == null
        ? const Color(0xFF7DD3F0)
        : Color(activePhase.color);
    final endDate = DateFormat.yMMMd(Intl.defaultLocale).format(plan.endDate);
    final activeIndex = activePhase == null
        ? 0
        : phases.indexOf(activePhase) + 1;
    // Days left counts today in, so a plan ending today reads "1 dia".
    final daysLeft = plan.endDate.difference(DateTime(now.year, now.month, now.day)).inDays + 1;
    final String remainingValue;
    if (daysLeft <= 0) {
      remainingValue = '—';
    } else if (daysLeft > 14) {
      remainingValue = loc.periodizationWeeksLeft((daysLeft / 7).ceil());
    } else {
      remainingValue = loc.periodizationDaysLeft(daysLeft);
    }
    final String statusLine;
    if (now.isBefore(plan.startDate)) {
      statusLine = loc.periodizationPlanNotStarted(
        DateFormat.yMMMd(Intl.defaultLocale).format(plan.startDate),
      );
    } else if (daysLeft <= 0) {
      statusLine = loc.periodizationPlanFinished;
    } else {
      statusLine = loc.periodizationWeekOf(currentWeek, totalWeeks);
    }

    return Semantics(
      button: true,
      label:
          '${loc.periodizationPlanOverview}: ${plan.name}, ${(progress * 100).round()}%',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.surfaceContainerHighest.withAlpha(200),
                  theme.colorScheme.surfaceContainerLow,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          loc.periodizationActivePlan,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: accent,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.3,
                              ),
                        ),
                      ),
                      Text(
                        '${(progress * 100).round()}%',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: const Color(0xFFE6EAED),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: Color(0xFF9BA3A8),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    plan.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: const Color(0xFFF2F4F5),
                      fontWeight: FontWeight.w900,
                      height: 1.15,
                      letterSpacing: -.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    statusLine,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFFB9C0C4),
                    ),
                  ),
                  const SizedBox(height: 14),
                  // One segment per phase, in the phase colour: the plan's
                  // shape is readable at a glance, which a single-colour bar
                  // never showed.
                  _PhaseSegmentBar(
                    phases: phases,
                    referenceDate: now,
                    fallbackColor: accent,
                    progress: progress,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _PlanHeroMetric(
                        value: phases.isEmpty
                            ? '—'
                            : '$activeIndex/${phases.length}',
                        label: loc.periodizationPhases,
                      ),
                      _PlanHeroMetric(
                        value: remainingValue,
                        label: loc.periodizationRemaining,
                      ),
                      _PlanHeroMetric(
                        value: endDate,
                        label: loc.periodizationPlanEnd,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Segmented plan bar: one slice per phase sized by its duration, dimmed
/// ahead of today and saturated behind it, so the fill doubles as progress.
class _PhaseSegmentBar extends StatelessWidget {
  final List<PeriodizationPhase> phases;
  final DateTime referenceDate;
  final Color fallbackColor;
  final double progress;

  const _PhaseSegmentBar({
    required this.phases,
    required this.referenceDate,
    required this.fallbackColor,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    if (phases.isEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: LinearProgressIndicator(
          value: progress,
          minHeight: 9,
          color: fallbackColor,
          backgroundColor: const Color(0xFF354047),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: SizedBox(
        height: 9,
        child: Row(
          // Without stretch the ColoredBox slices collapse to zero height.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < phases.length; index++)
              Expanded(
                flex: phases[index].totalDays,
                child: Padding(
                  padding: EdgeInsets.only(
                    right: index == phases.length - 1 ? 0 : 2,
                  ),
                  child: _PhaseSegment(
                    phase: phases[index],
                    referenceDate: referenceDate,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PhaseSegment extends StatelessWidget {
  final PeriodizationPhase phase;
  final DateTime referenceDate;

  const _PhaseSegment({required this.phase, required this.referenceDate});

  @override
  Widget build(BuildContext context) {
    final color = Color(phase.color);
    final fill = phase.progressAt(referenceDate);
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: color.withAlpha(60)),
        if (fill > 0)
          FractionallySizedBox(
            widthFactor: fill,
            alignment: Alignment.centerLeft,
            child: ColoredBox(color: color),
          ),
      ],
    );
  }
}

class _PlanHeroMetric extends StatelessWidget {
  final String value;
  final String label;

  const _PlanHeroMetric({required this.value, required this.label});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: const Color(0xFFE4E8EA),
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: const Color(0xFFB3BABE)),
        ),
      ],
    ),
  );
}

/// Shown in place of the timeline when the plan has no phases yet — the
/// timeline itself would render as an empty bordered box.
class _NoPhasesCard extends StatelessWidget {
  final VoidCallback onAdd;

  const _NoPhasesCard({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return PeriodizationSurface(
      onTap: onAdd,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withAlpha(26),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.route_outlined,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loc.periodizationNoPhasesTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  loc.periodizationNoPhasesHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.add_rounded, color: theme.colorScheme.primary),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  final VoidCallback onCalendar;
  final VoidCallback onPlans;
  final VoidCallback onCompare;

  const _QuickActions({
    required this.onCalendar,
    required this.onPlans,
    required this.onCompare,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Row(
      children: [
        Expanded(
          child: _QuickAction(
            icon: Icons.calendar_month_outlined,
            label: loc.periodizationCalendar,
            onTap: onCalendar,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _QuickAction(
            icon: Icons.folder_open_outlined,
            label: loc.periodizationHistory,
            onTap: onPlans,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _QuickAction(
            icon: Icons.compare_arrows_rounded,
            label: loc.periodizationCompare,
            onTap: onCompare,
          ),
        ),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Column(
            children: [
              Icon(icon, size: 21, color: theme.colorScheme.primary),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CurrentPhaseCard extends StatelessWidget {
  final PeriodizationPhase phase;
  final PeriodizationTarget? target;
  final PeriodizationRoutineSuggestion? routineSuggestion;
  final PeriodizationRunSuggestion? runSuggestion;
  final VoidCallback onStartRun;
  final VoidCallback onTap;
  final VoidCallback onStartWorkout;
  final VoidCallback onCheckin;
  final VoidCallback onEditTargets;

  /// Whether this week already has a saved review. Without it the button
  /// looked identical whether or not the weekly ritual had been done.
  final bool checkinDone;

  /// Materialises the phase's running plan across its weeks.
  final VoidCallback onScheduleRuns;

  /// Whether this phase links a running plan at all.
  final bool hasRunPlan;

  const _CurrentPhaseCard({
    required this.phase,
    required this.target,
    required this.routineSuggestion,
    required this.runSuggestion,
    required this.onStartRun,
    required this.onTap,
    required this.onStartWorkout,
    required this.onCheckin,
    required this.onEditTargets,
    required this.checkinDone,
    required this.onScheduleRuns,
    required this.hasRunPlan,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final now = DateTime.now();
    final color = Color(phase.color);
    // Inclusive of today: the last day of a phase reads "Termina hoje".
    final daysLeft = phase.endDate
        .difference(DateTime(now.year, now.month, now.day))
        .inDays
        .clamp(0, 100000);
    final targetItems = <Widget>[];
    if (target?.calories != null) {
      targetItems.add(
        PeriodizationMetricTile(
          label: loc.periodizationCaloriesPerDay,
          value: '${target!.calories!.round()}',
          icon: Icons.local_fire_department_outlined,
          color: color,
        ),
      );
    }
    if (target?.proteinG != null) {
      targetItems.add(
        PeriodizationMetricTile(
          label: loc.periodizationProteinG,
          value: '${target!.proteinG!.round()} g',
          icon: Icons.restaurant_outlined,
          color: color,
        ),
      );
    }
    if (target?.workoutsPerWeek != null) {
      targetItems.add(
        PeriodizationMetricTile(
          label: loc.periodizationWorkoutsPerWeek,
          value: '${target!.workoutsPerWeek}×',
          icon: Icons.fitness_center_rounded,
          color: color,
        ),
      );
    }

    return PeriodizationSurface(
      accentColor: color,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withAlpha(28),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(Icons.trending_up_rounded, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loc.periodizationPhaseWeek(
                        phase.weekAt(now),
                        phase.totalWeeks,
                      ),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      phase.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (phase.intent != null)
                      Text(
                        phase.intent!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: phase.progressAt(now),
              minHeight: 7,
              color: color,
              backgroundColor: color.withAlpha(26),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${DateFormat.MMMd(Intl.defaultLocale).format(phase.startDate)}'
                  ' – '
                  '${DateFormat.MMMd(Intl.defaultLocale).format(phase.endDate)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                loc.periodizationPhaseEndsIn(daysLeft),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          if (targetItems.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 96,
              child: Row(
                children: [
                  for (
                    var index = 0;
                    index < targetItems.take(3).length;
                    index++
                  ) ...[
                    if (index > 0) const SizedBox(width: 8),
                    Expanded(child: targetItems[index]),
                  ],
                ],
              ),
            ),
          ] else if (target == null || target!.isEmpty) ...[
            // A phase with no targets at all makes the weekly review
            // meaningless, and nothing else on this screen said so. A phase
            // that only links a running plan is not "empty".
            const SizedBox(height: 12),
            _MissingTargetsRow(color: color, onTap: onEditTargets),
          ],
          if (routineSuggestion case final suggestion?) ...[
            const SizedBox(height: 12),
            DecoratedBox(
              decoration: BoxDecoration(
                color: color.withAlpha(18),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.event_available_outlined, color: color),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            suggestion.routineName,
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            loc.periodizationNextRoutineDay(
                              suggestion.routineDayName,
                              suggestion.routineDayIndex + 1,
                              suggestion.routineDayCount,
                            ),
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: onStartWorkout,
                      tooltip: loc.periodizationStartPhaseWorkout,
                      icon: const Icon(Icons.play_arrow_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (runSuggestion case final suggestion?) ...[
            const SizedBox(height: 12),
            DecoratedBox(
              decoration: BoxDecoration(
                color: color.withAlpha(18),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(
                      RunPlanUi.kindIcon(suggestion.workout.kind),
                      color: color,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            suggestion.workout.name,
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            '${RunPlanUi.kindLabel(loc, suggestion.workout.kind)}'
                            ' · '
                            '${RunPlanUi.sessionSummary(loc, suggestion.workout)}',
                            style: theme.textTheme.bodySmall,
                          ),
                          if (suggestion.workout.hasSteps) ...[
                            const SizedBox(height: 6),
                            RunWorkoutProfileBar(
                              workout: suggestion.workout,
                              height: 6,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (suggestion.isCompleted)
                      Icon(Icons.check_circle_outline, color: color)
                    else
                      IconButton(
                        onPressed: onStartRun,
                        tooltip: loc.runWorkoutStartSession,
                        icon: const Icon(Icons.play_arrow_rounded),
                      ),
                  ],
                ),
              ),
            ),
          ],
          // Reachable whenever the phase links a plan, not only on days the
          // plan happens to schedule a run.
          if (hasRunPlan) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onScheduleRuns,
              style: OutlinedButton.styleFrom(
                foregroundColor: color,
                side: BorderSide(color: color.withAlpha(110)),
              ),
              icon: const Icon(Icons.event_repeat_outlined, size: 19),
              label: Text(loc.periodizationRunScheduleAction),
            ),
          ],
          const SizedBox(height: 12),
          if (checkinDone)
            OutlinedButton.icon(
              onPressed: onCheckin,
              style: OutlinedButton.styleFrom(
                foregroundColor: color,
                side: BorderSide(color: color.withAlpha(120)),
              ),
              icon: const Icon(Icons.check_circle_outline, size: 20),
              label: Text(loc.periodizationCheckinDoneThisWeek),
            )
          else
            FilledButton.tonalIcon(
              onPressed: onCheckin,
              icon: const Icon(Icons.fact_check_outlined),
              label: Text(loc.periodizationWeeklyCheckin),
            ),
        ],
      ),
    );
  }
}

class _MissingTargetsRow extends StatelessWidget {
  final Color color;
  final VoidCallback onTap;

  const _MissingTargetsRow({required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Material(
      color: color.withAlpha(18),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            children: [
              Icon(Icons.flag_outlined, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loc.periodizationTargetsMissingTitle,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      loc.periodizationTargetsMissingHint,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Text(
                loc.periodizationTargetsDefine,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VerticalPhaseTimeline extends StatelessWidget {
  final List<PeriodizationPhase> phases;
  final DateTime referenceDate;
  final ValueChanged<PeriodizationPhase> onPhaseTap;

  /// Plans crossing a new year need the year in the date range, or
  /// "18 de nov. – 9 de mar." reads as a phase going backwards in time.
  final bool showYear;

  const _VerticalPhaseTimeline({
    required this.phases,
    required this.referenceDate,
    required this.onPhaseTap,
    this.showYear = false,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Column(
      children: List.generate(phases.length, (index) {
        final phase = phases[index];
        final color = Color(phase.color);
        final isCurrent = phase.contains(referenceDate);
        final isPast = phase.endDate.isBefore(referenceDate);
        final isFirst = index == 0;
        final isLast = index == phases.length - 1;

        final phaseProgress = isCurrent
            ? phase.progressAt(referenceDate)
            : (isPast ? 1.0 : 0.0);

        final shortDate = DateFormat.MMMd(Intl.defaultLocale);
        final longDate = DateFormat.yMMMd(Intl.defaultLocale);
        // The year goes on the end date only. A phase always runs forward, so
        // "18 de nov. – 9 de mar. de 2027" is unambiguous, and repeating the
        // year on both ends made the line long enough to be truncated.
        final range =
            '${shortDate.format(phase.startDate)}'
            ' – '
            '${(showYear ? longDate : shortDate).format(phase.endDate)}';
        final weeksLabel = loc.periodizationDurationWeeks(phase.totalWeeks);
        final detail = phase.intent?.trim().isNotEmpty == true
            ? '$weeksLabel  ·  ${phase.intent!.trim()}'
            : weeksLabel;
        final String? status;
        if (isPast) {
          status = loc.periodizationPhaseDone;
        } else if (!isCurrent) {
          status = loc.periodizationPhaseStartsIn(
            (phase.startDate.difference(referenceDate).inDays / 7).ceil().clamp(
              0,
              100000,
            ),
          );
        } else {
          status = null;
        }

        return Semantics(
          button: true,
          selected: isCurrent,
          label: '${phase.name}, $range',
          child: InkWell(
            onTap: () => onPhaseTap(phase),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              // The rail has to span the row's real height, or the connecting
              // line stops short and the timeline reads as broken segments.
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 44,
                      child: _TimelineRail(
                        isFirst: isFirst,
                        isLast: isLast,
                        isPast: isPast,
                        isCurrent: isCurrent,
                        color: color,
                        outlineColor: theme.colorScheme.outlineVariant,
                        nodeProgress: phaseProgress,
                        surface: theme.colorScheme.surface,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          0,
                          isFirst ? 8 : 12,
                          4,
                          isLast ? 4 : 12,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    phase.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: isCurrent
                                          ? FontWeight.w800
                                          : FontWeight.w700,
                                      color: isCurrent
                                          ? color
                                          : (isPast
                                              ? theme.colorScheme.onSurface
                                                  .withAlpha(190)
                                              : theme.colorScheme.onSurface),
                                    ),
                                  ),
                                ),
                                if (isCurrent) ...[
                                  _NowBadge(
                                    label: loc.periodizationNow,
                                    color: color,
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                Icon(
                                  Icons.chevron_right_rounded,
                                  size: 19,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            // The countdown leads the date line instead of
                            // sharing the title row, where the longest phase
                            // names were being ellipsized at large font scales.
                            Text.rich(
                              TextSpan(
                                children: [
                                  if (status != null) ...[
                                    TextSpan(
                                      text: status,
                                      style: TextStyle(
                                        color: isPast
                                            ? color.withAlpha(210)
                                            : theme.colorScheme.onSurface
                                                  .withAlpha(210),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const TextSpan(text: '  ·  '),
                                  ],
                                  TextSpan(text: range),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              detail,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant
                                    .withAlpha(190),
                              ),
                            ),
                            if (isCurrent && phaseProgress > 0) ...[
                              const SizedBox(height: 10),
                              _PhaseProgressBar(
                                progress: phaseProgress,
                                color: color,
                                backgroundColor:
                                    theme.colorScheme.surfaceContainerHighest,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _TimelineRail extends StatelessWidget {
  final bool isFirst;
  final bool isLast;
  final bool isPast;
  final bool isCurrent;
  final Color color;
  final Color outlineColor;
  final Color surface;
  final double nodeProgress;

  const _TimelineRail({
    required this.isFirst,
    required this.isLast,
    required this.isPast,
    required this.isCurrent,
    required this.color,
    required this.outlineColor,
    required this.surface,
    required this.nodeProgress,
  });

  static const double _nodeTop = 14;
  static const double _railX = 21;
  static const double _railWidth = 2;

  double get _nodeSize =>
      isCurrent ? 28 : (isPast ? 16 : 12);

  @override
  Widget build(BuildContext context) {
    final upperColor =
        isPast || isCurrent ? color.withAlpha(150) : outlineColor;
    final lowerColor = isPast ? color.withAlpha(150) : outlineColor;
    final bottomStart = _nodeTop + _nodeSize;
    // No fixed height: the parent row stretches this to its full height so
    // the line reaches the next node without a gap.
    return SizedBox(
      width: 44,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          if (!isFirst)
            Positioned(
              top: 0,
              height: _nodeTop,
              left: _railX,
              width: _railWidth,
              child: ColoredBox(color: upperColor),
            ),
          if (!isLast)
            Positioned(
              top: bottomStart,
              bottom: 0,
              left: _railX,
              width: _railWidth,
              child: ColoredBox(color: lowerColor),
            ),
          Positioned(
            top: _nodeTop,
            child: _TimelineNode(
              isCurrent: isCurrent,
              isPast: isPast,
              color: color,
              progress: nodeProgress,
              surface: surface,
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineNode extends StatelessWidget {
  final bool isCurrent;
  final bool isPast;
  final Color color;
  final Color surface;
  final double progress;

  const _TimelineNode({
    required this.isCurrent,
    required this.isPast,
    required this.color,
    required this.surface,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    if (isCurrent) {
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: progress.clamp(0, 1)),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        builder: (context, value, _) => SizedBox(
          width: 28,
          height: 28,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  value: value,
                  strokeWidth: 2.4,
                  backgroundColor: color.withAlpha(45),
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withAlpha(120),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (isPast) {
      return Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.check_rounded,
          size: 10,
          color: Colors.white,
        ),
      );
    }
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: surface,
        shape: BoxShape.circle,
        border: Border.all(color: color.withAlpha(150), width: 1.6),
      ),
    );
  }
}

class _NowBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _NowBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(36),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w900,
          letterSpacing: .8,
          fontSize: 10,
          height: 1.0,
        ),
      ),
    );
  }
}

class _PhaseProgressBar extends StatelessWidget {
  final double progress;
  final Color color;
  final Color backgroundColor;

  const _PhaseProgressBar({
    required this.progress,
    required this.color,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: progress.clamp(0, 1)),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) => ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: LinearProgressIndicator(
          value: value,
          minHeight: 4,
          color: color,
          backgroundColor: backgroundColor,
        ),
      ),
    );
  }
}

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              height: 190,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(22),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: List.generate(
                3,
                (index) => Expanded(
                  child: Container(
                    height: 72,
                    margin: EdgeInsets.only(left: index == 0 ? 0 : 8),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 40),
            Container(
              height: 260,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ],
        )
        .animate(onPlay: (controller) => controller.repeat(reverse: true))
        .fade(begin: .45, end: .85, duration: 900.ms);
  }
}

/// Planned vs actual for the running week, one row per target that exists.
///
/// Rows with no target are omitted rather than shown as "— / —": a phase that
/// only tracks nutrition should not be nagged about running volume.
class _WeekAdherenceCard extends StatelessWidget {
  final PeriodizationMetrics metrics;
  final Color accent;
  final VoidCallback onTap;

  const _WeekAdherenceCard({
    required this.metrics,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final rows = <Widget>[];

    void add({
      required IconData icon,
      required String label,
      required double done,
      required double planned,
      required String doneText,
      required String plannedText,
    }) {
      rows.add(
        _AdherenceRow(
          icon: icon,
          label: label,
          value: loc.periodizationAdherenceOf(doneText, plannedText),
          fraction: planned <= 0 ? 0 : (done / planned).clamp(0.0, 1.0),
          accent: accent,
        ),
      );
    }

    if (metrics.plannedWorkouts != null && metrics.plannedWorkouts! > 0) {
      add(
        icon: Icons.fitness_center_rounded,
        label: loc.periodizationAdherenceWorkouts,
        done: metrics.workoutCount.toDouble(),
        planned: metrics.plannedWorkouts!.toDouble(),
        doneText: '${metrics.workoutCount}',
        plannedText: '${metrics.plannedWorkouts}',
      );
    }
    if (metrics.plannedRunSessions != null &&
        metrics.plannedRunSessions! > 0) {
      add(
        icon: Icons.directions_run_rounded,
        label: loc.periodizationAdherenceRuns,
        done: metrics.runCount.toDouble(),
        planned: metrics.plannedRunSessions!.toDouble(),
        doneText: '${metrics.runCount}',
        plannedText: '${metrics.plannedRunSessions}',
      );
    }
    if (metrics.plannedRunDistanceMeters != null &&
        metrics.plannedRunDistanceMeters! > 0) {
      add(
        icon: Icons.route_outlined,
        label: loc.periodizationAdherenceVolume,
        done: metrics.runDistanceMeters,
        planned: metrics.plannedRunDistanceMeters!,
        doneText: '${RunPlanUi.kmValue(metrics.runDistanceMeters)} km',
        plannedText:
            '${RunPlanUi.kmValue(metrics.plannedRunDistanceMeters!)} km',
      );
    }
    if (metrics.averageCalories != null &&
        metrics.nutritionAdherencePercent != null) {
      rows.add(
        _AdherenceRow(
          icon: Icons.local_fire_department_outlined,
          label: loc.periodizationAdherenceCalories,
          value: '${metrics.averageCalories!.round()}',
          fraction: (metrics.nutritionAdherencePercent! / 100).clamp(0.0, 1.0),
          accent: accent,
        ),
      );
    }
    if (metrics.averageSleepHours != null &&
        metrics.sleepAdherencePercent != null) {
      rows.add(
        _AdherenceRow(
          icon: Icons.nightlight_outlined,
          label: loc.periodizationAdherenceSleep,
          value: '${metrics.averageSleepHours!.toStringAsFixed(1)} h',
          fraction: (metrics.sleepAdherencePercent! / 100).clamp(0.0, 1.0),
          accent: accent,
        ),
      );
    }

    return PeriodizationSurface(
      onTap: onTap,
      child: rows.isEmpty
          ? Row(
              children: [
                Icon(
                  Icons.insights_outlined,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    loc.periodizationAdherenceEmpty,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var index = 0; index < rows.length; index++) ...[
                  if (index > 0) const SizedBox(height: 12),
                  rows[index],
                ],
              ],
            ),
    );
  }
}

class _AdherenceRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final double fraction;
  final Color accent;

  const _AdherenceRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.fraction,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 17, color: accent),
        const SizedBox(width: 10),
        SizedBox(
          width: 78,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              color: accent,
              backgroundColor: accent.withAlpha(30),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          value,
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}
