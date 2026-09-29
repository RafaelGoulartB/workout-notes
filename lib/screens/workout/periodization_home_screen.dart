import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/nutrition/daily_nutrition_summary.dart';
import 'package:workout_notes/models/nutrition/nutrition_goal.dart';
import 'package:workout_notes/models/periodization_phase.dart';
import 'package:workout_notes/models/periodization_plan.dart';
import 'package:workout_notes/models/periodization_routine_suggestion.dart';
import 'package:workout_notes/models/periodization_run_suggestion.dart';
import 'package:workout_notes/models/periodization_schedule.dart';
import 'package:workout_notes/periodization/phase_kind.dart';
import 'package:workout_notes/periodization/phase_seed.dart';
import 'package:workout_notes/periodization/week_progress.dart';
import 'package:workout_notes/repositories/body_measurement_repository.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';
import 'package:workout_notes/screens/run/run_record_screen.dart';
import 'package:workout_notes/services/effective_nutrition_goal_service.dart';
import 'package:workout_notes/utils/load_generation.dart';
import 'package:workout_notes/widgets/load_error_view.dart';
import 'package:workout_notes/widgets/ai/ai_coach_header_button.dart';
import 'package:workout_notes/widgets/periodization/body_measurements_teaser_card.dart';
import 'package:workout_notes/widgets/periodization/plan_overview.dart';
import 'package:workout_notes/widgets/periodization/planning_widgets.dart';
import 'package:workout_notes/widgets/run/run_plan_ui.dart';

import 'active_workout_screen.dart';
import 'body_tracker_screen.dart';
import 'periodization_checkin_flow.dart';
import 'periodization_phase_editor_screen.dart';
import 'periodization_phase_screen.dart';
import 'periodization_plan_editor_screen.dart';
import 'periodization_plan_screen.dart';
import 'periodization_plans_screen.dart';
import 'settings_screen.dart';

/// Progress tab: body weight, then the active plan — what today asks for,
/// how this week is going, and the plan's phases on a roadmap.
class PeriodizationHomeScreen extends StatefulWidget {
  const PeriodizationHomeScreen({super.key});

  @override
  State<PeriodizationHomeScreen> createState() =>
      _PeriodizationHomeScreenState();
}

class _PeriodizationHomeScreenState extends State<PeriodizationHomeScreen> {
  final _repository = PeriodizationRepository();
  final _bodyRepo = BodyMeasurementRepository();

  PlanOverviewData? _overview;
  PeriodizationPhase? _currentPhase;
  PeriodizationDayPlan? _today;
  EffectiveNutritionGoal? _goal;
  DailyNutritionSummary? _eaten;
  PeriodizationRoutineSuggestion? _routineSuggestion;
  PeriodizationRunSuggestion? _runSuggestion;
  WeekProgress? _week;
  bool _weekReviewed = false;
  List<PeriodizationPlan> _otherPlans = const [];

  double? _weightKg;
  String? _weightUnit;
  double? _weightDelta;
  String? _weightDate;
  final _generation = LoadGeneration();
  bool _loading = true;
  bool _hasLoaded = false;
  bool _loadFailed = false;

  DateTime get _day {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _generation.invalidate();
    super.dispose();
  }

  Future<void> _loadWeight() async {
    final rows = await _bodyRepo.getBodyMeasurements(type: 'weight', limit: 2);
    if (rows.isEmpty) {
      _weightKg = _weightUnit = _weightDelta = _weightDate = null;
      return;
    }
    final latest = rows.first;
    final value = (latest['value'] as num?)?.toDouble();
    _weightKg = value;
    _weightUnit = latest['unit'] as String? ?? 'kg';
    _weightDate = latest['date'] as String?;
    final previous = rows.length >= 2
        ? (rows[1]['value'] as num?)?.toDouble()
        : null;
    _weightDelta = value == null || previous == null ? null : value - previous;
  }

  /// Reloads the tab. Only the newest load applies its result, and a failed
  /// one keeps what is on screen (with a retry) instead of leaving the tab
  /// loading forever or looking like it has no plan.
  Future<void> _load() async {
    final token = _generation.begin();
    if (mounted && !_hasLoaded) setState(() => _loading = true);
    try {
      await _loadAll(token);
    } catch (_) {
      if (!mounted || !_generation.isCurrent(token)) return;
      setState(() {
        _loadFailed = true;
        _loading = false;
      });
    }
  }

  Future<void> _loadAll(int token) async {
    await _loadWeight();
    final plan = await _repository.getActivePlan();
    if (plan == null) {
      final plans = await _repository.getPlans(includeArchived: false);
      if (!mounted || !_generation.isCurrent(token)) return;
      setState(() {
        _overview = null;
        _currentPhase = null;
        _today = null;
        _week = null;
        _otherPlans = plans;
        _hasLoaded = true;
        _loadFailed = false;
        _loading = false;
      });
      return;
    }
    final overview = await PlanOverviewData.load(_repository, plan);
    final day = _day;
    final current = overview.phaseOn(day);
    PeriodizationDayPlan? dayPlan;
    EffectiveNutritionGoal? goal;
    DailyNutritionSummary? eaten;
    PeriodizationRoutineSuggestion? routine;
    PeriodizationRunSuggestion? run;
    WeekProgress? week;
    var reviewed = false;
    if (current != null) {
      // Each card is informational: one failing query must not take the
      // whole tab down with it.
      final results = await Future.wait<Object?>([
        _safe(_repository.getDayPlan(day)),
        _safe(EffectiveNutritionGoalService.resolve(date: day)),
        _safe(
          NutritionRepository().getDailySummary(
            day.toIso8601String().substring(0, 10),
          ),
        ),
        _safe(_repository.getRoutineSuggestion(day)),
        _safe(_repository.getRunSuggestion(day)),
        _safe(WeekProgress.load(_repository, current, current.weekAt(day) - 1)),
        _safe(_repository.getCheckin(current.id, day)),
      ]);
      dayPlan = results[0] as PeriodizationDayPlan?;
      goal = results[1] as EffectiveNutritionGoal?;
      eaten = results[2] as DailyNutritionSummary?;
      routine = results[3] as PeriodizationRoutineSuggestion?;
      run = results[4] as PeriodizationRunSuggestion?;
      week = results[5] as WeekProgress?;
      reviewed = results[6] != null;
    }
    if (!mounted || !_generation.isCurrent(token)) return;
    setState(() {
      _overview = overview;
      _currentPhase = current;
      _today = dayPlan;
      _goal = goal;
      _eaten = eaten;
      _routineSuggestion = routine;
      _runSuggestion = run;
      _week = week;
      _weekReviewed = reviewed;
      _hasLoaded = true;
      _loadFailed = false;
      _loading = false;
    });
  }

  static Future<Object?> _safe<T>(Future<T> future) =>
      future.then<Object?>((value) => value).catchError((Object _) => null);

  // ---- navigation ----

  Future<void> _openBodyTracker() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BodyTrackerScreen()),
    );
    if (!mounted) return;
    await _loadWeight();
    if (mounted) setState(() {});
  }

  Future<void> _openAppSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AppSettingsScreen()),
    );
    if (mounted) await _load();
  }

  Future<void> _createPlan([
    PlanBlueprint blueprint = PlanBlueprint.recomposition,
  ]) async {
    final planId = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => PeriodizationPlanEditorScreen(blueprint: blueprint),
      ),
    );
    if (planId != null) await _load();
  }

  Future<void> _editPlan() async {
    final plan = _overview?.plan;
    if (plan == null) return;
    final saved = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => PeriodizationPlanEditorScreen(plan: plan),
      ),
    );
    if (saved != null) await _load();
  }

  Future<void> _openPlans() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PeriodizationPlansScreen()),
    );
    await _load();
  }

  Future<void> _openPlan(PeriodizationPlan plan) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PeriodizationPlanScreen(plan: plan)),
    );
    await _load();
  }

  Future<void> _finishPlan() async {
    final plan = _overview?.plan;
    if (plan == null) return;
    final loc = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(loc.planningFinishPlanTitle),
        content: Text(loc.planningFinishPlanBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(loc.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(loc.planningFinishPlan),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repository.setPlanStatus(plan.id, PeriodizationPlanStatus.completed);
    await _load();
  }

  Future<void> _openPhase(PeriodizationPhase phase) async {
    final plan = _overview?.plan;
    if (plan == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PeriodizationPhaseScreen(plan: plan, phase: phase),
      ),
    );
    await _load();
  }

  Future<void> _editPhase(PeriodizationPhase phase) async {
    final plan = _overview?.plan;
    if (plan == null) return;
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PeriodizationPhaseEditorScreen(plan: plan, phase: phase),
      ),
    );
    await _load();
  }

  Future<void> _addPhase() async {
    final overview = _overview;
    if (overview == null) return;
    final kind = await pickPhaseKind(context);
    if (kind == null || !mounted) return;
    final loc = AppLocalizations.of(context)!;
    final results = await Future.wait<Object?>([
      NutritionRepository().getActiveGoal(),
      _bodyRepo.getLatestWeightKg(),
    ]);
    final last = overview.phases.lastOrNull;
    final phase = await _repository.appendPhase(
      overview.plan.id,
      PhaseScheduleEntry(
        name: kind.label(loc),
        templateKey: kind.key,
        color: kind.color,
        weeks: 4,
        seedTarget: seedTargetForKind(
          kind,
          tdee: (results[0] as NutritionGoal?)?.tdee,
          weightKg: results[1] as double?,
          training: last == null ? null : overview.targets[last.id],
        ),
      ),
    );
    if (!mounted) return;
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PeriodizationPhaseEditorScreen(plan: overview.plan, phase: phase),
      ),
    );
    await _load();
  }

  Future<void> _startWorkout() async {
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

  Future<void> _startRun() async {
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

  Future<void> _review() async {
    final plan = _overview?.plan;
    final phase = _currentPhase;
    if (plan == null || phase == null) return;
    await PeriodizationCheckinFlow.run(
      context: context,
      plan: plan,
      phase: phase,
    );
    if (mounted) await _load();
  }

  // ---- build ----

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
            tooltip: loc.settingsTitle,
            onPressed: _openAppSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_loadFailed && !_hasLoaded)
          ? LoadErrorView(onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
                children: [
                  if (_loadFailed) LoadErrorBanner(onRetry: _load),
                  BodyMeasurementsTeaserCard(
                    weightKg: _weightKg,
                    unit: _weightUnit,
                    delta: _weightDelta,
                    date: _weightDate,
                    goodDirection: _goodWeightDirection,
                    onOpen: _openBodyTracker,
                  ),
                  ..._overview == null
                      ? _emptyState(loc)
                      : _planSections(loc, _overview!),
                ],
              ),
            ),
    );
  }

  /// Direction the current phase wants the scale to move, if any.
  int? get _goodWeightDirection {
    final phase = _currentPhase;
    final rate = phase == null
        ? null
        : _overview?.targets[phase.id]?.weeklyWeightChangePercent;
    if (rate == null || rate == 0) return null;
    return rate > 0 ? 1 : -1;
  }

  List<Widget> _planSections(AppLocalizations loc, PlanOverviewData data) {
    final day = _day;
    final current = _currentPhase;
    return [
      PlanningSectionLabel(loc.planningTitle, icon: Icons.route_outlined),
      PlanHeaderCard(
        key: const Key('planningHeader'),
        data: data,
        today: day,
        onPhaseTap: _openPhase,
        menu: PopupMenuButton<String>(
          key: const Key('planningPlanMenu'),
          onSelected: (value) => switch (value) {
            'edit' => _editPlan(),
            'plans' => _openPlans(),
            'new' => _createPlan(),
            'finish' => _finishPlan(),
            _ => null,
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'edit',
              child: ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(loc.planningEditPlan),
              ),
            ),
            PopupMenuItem(
              value: 'plans',
              child: ListTile(
                leading: const Icon(Icons.folder_open_outlined),
                title: Text(loc.planningMyPlans),
              ),
            ),
            PopupMenuItem(
              value: 'new',
              child: ListTile(
                leading: const Icon(Icons.add_rounded),
                title: Text(loc.planningNewPlan),
              ),
            ),
            PopupMenuItem(
              value: 'finish',
              child: ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: Text(loc.planningFinishPlan),
              ),
            ),
          ],
        ),
      ),
      if (current != null && _today != null) ...[
        PlanningSectionLabel(
          '${loc.planningToday} · ${DateFormat('EEE, d MMM', Intl.defaultLocale).format(day)}',
          icon: Icons.today_outlined,
        ),
        _TodayCard(
          phase: current,
          dayPlan: _today!,
          goal: _goal,
          eaten: _eaten,
          routine: _routineSuggestion,
          run: _runSuggestion,
          workoutDoneToday: _week?.doneWeekdays.contains(day.weekday) ?? false,
          onStartWorkout: _startWorkout,
          onStartRun: _startRun,
          onOpenPhase: () => _openPhase(current),
        ),
      ],
      if (current != null && _week != null) ...[
        PlanningSectionLabel(
          loc.planningThisWeek,
          icon: Icons.date_range_outlined,
        ),
        _ThisWeekCard(
          phase: current,
          week: _week!,
          today: day,
          reviewed: _weekReviewed,
          onReview: _review,
          onOpen: () => _openPhase(current),
          onSetUp: () => _editPhase(current),
        ),
      ],
      if (current == null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: PlanningCard(
            child: Text(
              day.isBefore(data.phases.firstOrNull?.startDate ?? day)
                  ? loc.planningNotStartedYet
                  : loc.planningNoPhaseToday,
            ),
          ),
        ),
      PlanningSectionLabel(
        loc.planningPhasesCount(data.phases.length),
        icon: Icons.view_timeline_outlined,
        actionLabel: loc.planningAddPhase,
        onAction: _addPhase,
      ),
      for (final phase in data.phases)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: PhaseSummaryCard(
            key: Key('phaseCard-${phase.id}'),
            phase: phase,
            target: data.targets[phase.id],
            data: data,
            today: day,
            onTap: () => _openPhase(phase),
          ),
        ),
    ];
  }

  List<Widget> _emptyState(AppLocalizations loc) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return [
      PlanningSectionLabel(loc.planningTitle, icon: Icons.route_outlined),
      PlanningCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.route_rounded, size: 36, color: scheme.primary),
            const SizedBox(height: 12),
            Text(
              loc.planningEmptyTitle,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              loc.planningEmptyBody,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            BlueprintGrid(onTap: _createPlan),
          ],
        ),
      ),
      if (_otherPlans.isNotEmpty) ...[
        PlanningSectionLabel(
          loc.planningMyPlans,
          icon: Icons.folder_open_outlined,
          actionLabel: loc.planningSeeAll,
          onAction: _openPlans,
        ),
        for (final plan in _otherPlans.take(3))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: PlanningCard(
              onTap: () => _openPlan(plan),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          plan.name,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '${planStatusLabel(loc, plan.status)} · '
                          '${planningDateRange(plan.startDate, plan.endDate)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
          ),
      ],
    ];
  }
}

// =========================================================================
// Today
// =========================================================================

class _TodayCard extends StatelessWidget {
  final PeriodizationPhase phase;
  final PeriodizationDayPlan dayPlan;
  final EffectiveNutritionGoal? goal;
  final DailyNutritionSummary? eaten;
  final PeriodizationRoutineSuggestion? routine;
  final PeriodizationRunSuggestion? run;
  final bool workoutDoneToday;
  final VoidCallback onStartWorkout;
  final VoidCallback onStartRun;
  final VoidCallback onOpenPhase;

  const _TodayCard({
    required this.phase,
    required this.dayPlan,
    required this.goal,
    required this.eaten,
    required this.routine,
    required this.run,
    required this.workoutDoneToday,
    required this.onStartWorkout,
    required this.onStartRun,
    required this.onOpenPhase,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = Color(phase.color);
    final day = dayPlan.day;
    final training = dayPlan.trainingDay;
    final kcalGoal = goal?.fromPlan ?? false ? goal?.goal?.calories : null;
    final proteinGoal = goal?.fromPlan ?? false ? goal?.goal?.proteinG : null;
    final kcalEaten = eaten?.consumed.calories ?? 0;
    final proteinEaten = eaten?.consumed.proteinG ?? 0;
    final strengthToday = day.strength || (training == null && routine != null);
    final sleep = dayPlan.target?.sleepHours;

    final rows = <Widget>[
      if (kcalGoal != null)
        _TodayRow(
          icon: Icons.local_fire_department_outlined,
          color: color,
          title: loc.planningTodayKcal(
            planningKcal(kcalEaten),
            planningKcal(kcalGoal),
          ),
          subtitle: proteinGoal == null
              ? null
              : loc.planningTodayProtein(
                  proteinEaten.round(),
                  proteinGoal.round(),
                ),
          progress: kcalGoal <= 0 ? null : kcalEaten / kcalGoal,
        ),
      if (strengthToday && routine != null)
        _TodayRow(
          icon: Icons.fitness_center_rounded,
          color: color,
          title: routine!.routineDayName.isEmpty
              ? routine!.routineName
              : routine!.routineDayName,
          subtitle: routine!.routineDayName.isEmpty
              ? null
              : '${routine!.routineName} · ${loc.planningRoutineDayOf(routine!.routineDayIndex + 1, routine!.routineDayCount)}',
          done: workoutDoneToday && day.strength,
          onStart: onStartWorkout,
          startKey: const Key('todayStartWorkout'),
        )
      else if (day.strength)
        _TodayRow(
          icon: Icons.fitness_center_rounded,
          color: color,
          title: loc.planningStrengthDay,
          subtitle: loc.planningNoRoutineLinked,
          done: workoutDoneToday,
        ),
      if (run != null)
        _TodayRow(
          icon: RunPlanUi.kindIcon(run!.workout.kind),
          color: color,
          title: run!.workout.name,
          subtitle: [
            RunPlanUi.kindLabel(loc, run!.workout.kind),
            if (run!.workout.plannedDistanceMeters > 0)
              RunPlanUi.distanceLabel(run!.workout.plannedDistanceMeters),
          ].join(' · '),
          done: run!.isCompleted,
          onStart: run!.isCompleted ? null : onStartRun,
          startKey: const Key('todayStartRun'),
        )
      else if (day.run && day.runs.isEmpty)
        _TodayRow(
          icon: Icons.directions_run_rounded,
          color: color,
          title: loc.planningRunDay,
        ),
      if (training == false)
        _TodayRow(
          icon: Icons.self_improvement_rounded,
          color: color,
          title: loc.planningRestDay,
          subtitle: loc.planningRestDayBody,
        ),
      if (sleep != null)
        _TodayRow(
          icon: Icons.bedtime_outlined,
          color: color,
          title: loc.planningSleepTonight(
            sleep.toStringAsFixed(sleep % 1 == 0 ? 0 : 1).replaceAll('.', ','),
          ),
        ),
    ];

    return PlanningCard(
      key: const Key('planningToday'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onOpenPhase,
            borderRadius: BorderRadius.circular(12),
            child: Row(
              children: [
                PhaseAvatar.of(phase, size: 36),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        phase.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        loc.planningWeekOf(
                          dayPlan.weekNumber,
                          dayPlan.totalWeeks,
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (training != null)
                  PlanningPill(
                    icon: training
                        ? Icons.bolt_rounded
                        : Icons.self_improvement_rounded,
                    label: training
                        ? loc.planningTrainingDayShort
                        : loc.planningRestDayShort,
                    color: training ? color : scheme.tertiary,
                  ),
                if (dayPlan.target?.weekLabel case final label?
                    when label.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  PlanningPill(
                    icon: Icons.label_outline_rounded,
                    label: label,
                    color: color,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                loc.planningTodayNothing,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            )
          else
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              rows[i],
            ],
        ],
      ),
    );
  }
}

class _TodayRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final double? progress;
  final bool done;
  final VoidCallback? onStart;
  final Key? startKey;

  const _TodayRow({
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
    this.progress,
    this.done = false,
    this.onStart,
    this.startKey,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withAlpha(done ? 220 : 36),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              done ? Icons.check_rounded : icon,
              size: 20,
              color: done ? scheme.surface : color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    decoration: done ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                if (progress != null) ...[
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: progress!.clamp(0, 1).toDouble(),
                      minHeight: 5,
                      color: progress! > 1.05 ? scheme.error : color,
                      backgroundColor: color.withAlpha(36),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onStart != null && !done)
            IconButton.filledTonal(
              key: startKey,
              onPressed: onStart,
              icon: const Icon(Icons.play_arrow_rounded),
            ),
        ],
      ),
    );
  }
}

// =========================================================================
// This week
// =========================================================================

class _ThisWeekCard extends StatelessWidget {
  final PeriodizationPhase phase;
  final WeekProgress week;
  final DateTime today;
  final bool reviewed;
  final VoidCallback onReview;
  final VoidCallback onOpen;
  final VoidCallback onSetUp;

  const _ThisWeekCard({
    required this.phase,
    required this.week,
    required this.today,
    required this.reviewed,
    required this.onReview,
    required this.onOpen,
    required this.onSetUp,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = Color(phase.color);
    final stats = <String>[
      if (week.plannedStrength > 0)
        loc.planningStatStrength(week.doneStrength, week.plannedStrength),
      if (week.plannedRuns > 0)
        loc.planningStatRuns(week.doneRuns, week.plannedRuns),
      if (week.averageCalories != null && week.targetCalories != null)
        loc.planningStatKcal(
          planningKcal(week.averageCalories),
          planningKcal(week.targetCalories),
        ),
    ];
    return PlanningCard(
      key: const Key('planningThisWeek'),
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TemplateWeekStrip(
            week: week.week,
            accent: color,
            highlightWeekday: today.weekday,
            doneWeekdays: week.doneWeekdays,
            showCalories: false,
          ),
          if (!week.week.any((day) => day.trainingDay)) ...[
            const SizedBox(height: 10),
            Text(
              loc.planningSetUpWeekHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onSetUp,
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: Text(loc.planningSetUpWeek),
              ),
            ),
          ],
          if (stats.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              stats.join('  ·  '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: reviewed
                ? OutlinedButton.icon(
                    onPressed: onReview,
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: Text(loc.planningReviewDone),
                  )
                : FilledButton.tonalIcon(
                    key: const Key('planningWeekReview'),
                    onPressed: onReview,
                    icon: const Icon(Icons.fact_check_outlined, size: 18),
                    label: Text(loc.planningWeeklyReview),
                  ),
          ),
        ],
      ),
    );
  }
}
