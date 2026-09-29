import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_plan.dart';
import 'package:workout_notes/models/run_plan_ledger.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/models/scheduled_run.dart';
import 'package:workout_notes/repositories/run_plan_repository.dart';
import 'package:workout_notes/screens/run/plan_detail/run_plan_detail_sheets.dart';
import 'package:workout_notes/screens/run/plans/run_plan_activation.dart';
import 'package:workout_notes/screens/run/plans/run_plan_creation_flow.dart';
import 'package:workout_notes/screens/run/run_detail_screen.dart';
import 'package:workout_notes/screens/run/run_plan_customize_screen.dart';
import 'package:workout_notes/screens/run/run_plan_workout_editor_screen.dart';
import 'package:workout_notes/screens/workout/active_workout_screen.dart';
import 'package:workout_notes/services/run_plan_adaptation.dart';
import 'package:workout_notes/services/run_plan_coach.dart';
import 'package:workout_notes/services/run_plan_draft.dart';
import 'package:workout_notes/services/run_plan_templates.dart';
import 'package:workout_notes/services/run_plan_week_view.dart';
import 'package:workout_notes/services/run_strength_planner.dart';
import 'package:workout_notes/services/run_week_balance.dart';
import 'package:workout_notes/services/runner_strength_routine.dart';
import 'package:workout_notes/widgets/run/plan_detail/run_plan_adaptation_card.dart';
import 'package:workout_notes/widgets/run/plan_detail/run_plan_day_row.dart';
import 'package:workout_notes/widgets/run/plan_detail/run_plan_identity.dart';
import 'package:workout_notes/widgets/run/plan_detail/run_plan_session_card.dart';
import 'package:workout_notes/widgets/run/plan_detail/run_plan_status_card.dart';
import 'package:workout_notes/widgets/run/plan_detail/run_plan_strength_chip.dart';
import 'package:workout_notes/widgets/run/plan_detail/run_plan_week_header.dart';
import 'package:workout_notes/widgets/run/plan_detail/run_plan_week_strip.dart';
import 'package:workout_notes/widgets/run/run_balance_dialog.dart';
import 'package:workout_notes/widgets/run/run_plan_ui.dart';

/// Plan detail: identity header, status, week picker and the training week
/// laid out by weekday. A running week is read by day ("longão no domingo"),
/// so the week is drawn as seven rows instead of an undifferentiated list.
class RunPlanDetailScreen extends StatefulWidget {
  final String planId;

  /// Clock override for tests.
  final DateTime? today;

  const RunPlanDetailScreen({super.key, required this.planId, this.today});

  @override
  State<RunPlanDetailScreen> createState() => _RunPlanDetailScreenState();
}

class _RunPlanDetailScreenState extends State<RunPlanDetailScreen> {
  final _repo = RunPlanRepository();
  final _weekStrip = ScrollController();
  RunPlan? _plan;
  Set<int> _scheduledWeeks = const {};
  RunPlanProgress _progress = const RunPlanProgress();
  Map<String, RunPlanLedgerEntry> _ledger = const {};

  /// Driven by a periodization phase: the phase owns the week mapping, so this
  /// screen reports it instead of offering its own activation.
  bool _linkedToPlanning = false;
  bool _loading = true;
  int _week = 0;

  /// This week's suggestion from the weekly review, if any.
  RunPlanAdaptationProposal? _proposal;
  List<RunPlanAdaptationRecord> _adaptations = const [];
  Set<DateTime> _strengthDone = const {};
  bool _applying = false;

  DateTime get _today => RunPlanWeekView.day(widget.today ?? DateTime.now());

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _weekStrip.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final plan = await _repo.getPlan(widget.planId);
    if (!mounted) return;
    if (plan == null) {
      Navigator.pop(context);
      return;
    }
    // Independent reads run together (SQLite still serialises them).
    final (scheduled, progress, ledger, linked, adaptations) = await (
      _repo.getScheduledWeeks(plan.id),
      _repo.getPlanProgress(plan.id),
      _repo.getPlanLedger(plan.id),
      _repo.isLinkedToPeriodization(plan.id),
      _repo.listAdaptations(plan.id),
    ).wait;
    // The weekly review reads the run history; a failure there must not keep
    // the plan from opening.
    final proposalFuture = linked
        ? Future<RunPlanAdaptationProposal?>.value(null)
        : RunPlanCoach()
              .review(plan)
              .then<RunPlanAdaptationProposal?>((value) => value)
              .catchError((Object _) => null);
    final anchor = plan.activatedAt;
    final strengthFuture = anchor != null && _includesStrength(plan)
        ? () {
            final start = RunPlanWeekView.monday(anchor);
            return RunnerStrengthRoutine()
                .completedDays(
                  start,
                  start.add(Duration(days: 7 * plan.weeks)),
                )
                .catchError((Object _) => <DateTime>{});
          }()
        : Future<Set<DateTime>>.value(const {});
    final proposal = await proposalFuture;
    final strengthDone = await strengthFuture;
    if (!mounted) return;
    final firstLoad = _loading;
    setState(() {
      _plan = plan;
      _scheduledWeeks = scheduled;
      _progress = progress;
      _ledger = ledger;
      _linkedToPlanning = linked;
      _adaptations = adaptations;
      _proposal = proposal;
      _strengthDone = strengthDone;
      if (firstLoad) {
        // Open on the week being run, not week 1.
        _week = plan.activeWeekIndexOn(_today) ?? _week;
      }
      _week = _week.clamp(0, plan.weeks - 1);
      _loading = false;
    });
  }

  static bool _includesStrength(RunPlan plan) =>
      plan.config?['includeStrength'] == true;

  // --- plan level actions ----------------------------------------------------

  Future<void> _applyProposal() async {
    final plan = _plan, proposal = _proposal;
    if (plan == null || proposal == null || _applying) return;
    setState(() => _applying = true);
    final loc = AppLocalizations.of(context)!;
    try {
      await RunPlanCoach().apply(plan, proposal);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.runPlanAdaptApplied)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.commonError(e.toString()))));
    }
    if (mounted) setState(() => _applying = false);
    await _load();
  }

  Future<void> _dismissProposal() async {
    final plan = _plan, proposal = _proposal;
    if (plan == null || proposal == null) return;
    await RunPlanCoach().dismiss(plan, proposal);
    await _load();
  }

  /// Replaces this screen with the detail of a freshly created plan.
  void _replaceWith(RunPlan created) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => RunPlanDetailScreen(planId: created.id),
      ),
    );
  }

  /// Opens the wizard for [template]; a plan created there replaces this
  /// screen.
  Future<void> _startTemplate(RunPlanTemplate template) async {
    final created = await Navigator.push<RunPlan>(
      context,
      MaterialPageRoute(
        builder: (_) => RunPlanCustomizeScreen(template: template),
      ),
    );
    if (created == null || !mounted) return;
    _replaceWith(created);
  }

  /// "Choose next plan": the same template picker as the library.
  Future<void> _chooseNextPlan() async {
    final created = await startNewRunPlan(context, _repo);
    if (created == null || !mounted) return;
    _replaceWith(created);
  }

  Future<void> _closeFinishedPlan() async {
    final plan = _plan;
    if (plan == null) return;
    await _repo.deactivatePlan(plan.id);
    await _load();
  }

  Future<void> _startStrength(int sessionIndex) async {
    final isPt = Localizations.localeOf(context).languageCode == 'pt';
    final workoutId = await RunnerStrengthRoutine().startWorkout(
      pt: isPt,
      sessionIndex: sessionIndex,
    );
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ActiveWorkoutScreen(workoutId: workoutId),
      ),
    );
    if (mounted) _load();
  }

  /// Follows this plan from today, or stops following it. Only one plan is
  /// followed at a time, so this replaces any previous one.
  Future<void> _toggleFollow() async {
    final plan = _plan;
    if (plan == null) return;
    if (plan.isActivated) {
      await unfollowRunPlan(context, _repo, plan);
    } else if (!await followRunPlan(context, _repo, plan)) {
      return;
    }
    if (mounted) await _load();
  }

  Future<void> _resetProgress() async {
    final plan = _plan;
    if (plan == null) return;
    final loc = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.restart_alt_rounded),
        title: Text(loc.runPlanResetTitle),
        content: Text(loc.runPlanResetBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(loc.runPlanResetConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repo.resetPlanProgress(plan.id);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(loc.runPlanResetDone)));
    await _load();
  }

  Future<void> _editHeader() async {
    final plan = _plan;
    if (plan == null) return;
    final result = await showRunPlanEditSheet(context, plan);
    if (result == null) return;
    await _repo.updatePlan(
      plan.id,
      name: result.name,
      notes: result.notes,
      goalKind: result.goal,
      raceDate: result.raceDate,
      weeks: result.weeks,
    );
    if (mounted) _load();
  }

  // --- week ------------------------------------------------------------------

  void _selectWeek(int week) {
    setState(() => _week = week);
    _revealWeek(week);
  }

  /// Keeps the selected tile on screen: a 16-week plan scrolls far enough that
  /// the selection would otherwise sit outside the viewport.
  void _revealWeek(int week) {
    if (!_weekStrip.hasClients) return;
    final viewport = _weekStrip.position.viewportDimension;
    final target =
        (week * RunPlanWeekStrip.tileWidth) -
        (viewport / 2) +
        RunPlanWeekStrip.tileWidth / 2;
    _weekStrip.animateTo(
      target.clamp(0.0, _weekStrip.position.maxScrollExtent),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _copyWeek() async {
    final plan = _plan;
    if (plan == null || plan.weeks < 2) return;
    final loc = AppLocalizations.of(context)!;
    final targets = await showRunPlanCopyWeekSheet(
      context,
      plan,
      sourceWeek: _week,
    );
    if (targets == null || !mounted) return;
    final applied = await _repo.copyWeek(
      plan.id,
      sourceWeek: _week,
      targetWeeks: targets,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(loc.runPlanCopyWeekApplied(applied))),
    );
    _load();
  }

  Future<void> _scheduleWeek() async {
    final plan = _plan;
    if (plan == null) return;
    final loc = AppLocalizations.of(context)!;
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      helpText: loc.runPlanScheduleWeek,
      // The plan week starts on a Monday, so default to the coming Monday.
      initialDate: now.add(Duration(days: (8 - now.weekday) % 7)),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null || !mounted) return;
    final createdIds = await _repo.materializeWeek(
      planId: plan.id,
      weekIndex: _week,
      weekStart: picked,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(loc.runPlanScheduleWeekDone(createdIds.length))),
    );
    _load();
  }

  // --- sessions --------------------------------------------------------------

  /// Creates the session only to hand it to the editor and deletes it again
  /// when the editor is left without filling anything in, so backing out
  /// never leaves an "Easy" session behind.
  Future<void> _addSession({int? dayOfWeek}) async {
    final plan = _plan;
    if (plan == null) return;
    final defaultName = AppLocalizations.of(context)!.runWorkoutKindEasy;
    final created = await _repo.addWorkout(
      planId: plan.id,
      weekIndex: _week,
      name: defaultName,
      dayOfWeek: dayOfWeek,
    );
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RunPlanWorkoutEditorScreen(workoutId: created.id),
      ),
    );
    final current = await _repo.getWorkout(created.id);
    if (current != null &&
        RunPlanDraft.isUntouched(current, defaultName: defaultName)) {
      await _repo.deleteWorkout(created.id);
    }
    if (mounted) _load();
  }

  Future<void> _openSession(RunPlanWorkout workout) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RunPlanWorkoutEditorScreen(workoutId: workout.id),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _startSession(RunPlanSessionView view) async {
    await startRunPlanSession(context, _repo, view);
    if (mounted) _load();
  }

  Future<void> _openRun(RunPlanSessionView view) async {
    final id = view.ledger?.runActivityId;
    if (id == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RunDetailScreen(activityId: id)),
    );
    if (mounted) _load();
  }

  Future<void> _duplicateSession(RunPlanWorkout workout) async {
    final loc = AppLocalizations.of(context)!;
    await _repo.duplicateWorkout(workout.id);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(loc.runPlanSessionDuplicated)));
    _load();
  }

  Future<void> _deleteSession(RunPlanWorkout workout) async {
    final loc = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.runWorkoutDeleteConfirm(workout.name)),
        content: Text(loc.commonActionCannotBeUndone),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(loc.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repo.deleteWorkout(workout.id);
    if (mounted) _load();
  }

  Future<void> _moveSession(RunPlanWorkout workout) async {
    final plan = _plan;
    if (plan == null || plan.weeks < 2) return;
    final loc = AppLocalizations.of(context)!;
    final target = await showRunPlanMoveWeekSheet(
      context,
      plan,
      fromWeek: workout.weekIndex,
    );
    if (target == null) return;
    await _repo.updateWorkout(workout.id, weekIndex: target);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(loc.runPlanMoveWeekDone(target + 1))),
    );
    _load();
  }

  Future<void> _moveSessionToDay(RunPlanWorkout workout, int dayOfWeek) async {
    if (workout.dayOfWeek == dayOfWeek) return;
    final plan = _plan;
    if (plan == null) return;
    final loc = AppLocalizations.of(context)!;
    // Any Monday works: the check only needs weekdays as dates.
    final monday = DateTime(2024, 1, 1);
    DateTime dateOf(int day) => monday.add(Duration(days: day - 1));
    final week = [
      for (final w in plan.workoutsForWeek(workout.weekIndex))
        if (w.dayOfWeek != null)
          RunBalanceSession(
            id: w.id,
            date: dateOf(w.dayOfWeek!),
            kind: w.kind,
            km: w.plannedDistanceMeters / 1000,
            fixed:
                (_ledger[w.id]?.status ?? ScheduledRunStatus.planned) !=
                ScheduledRunStatus.planned,
          ),
    ];
    final byId = {for (final w in plan.workouts) w.id: w};
    final advice = workout.dayOfWeek == null
        ? const RunMoveAdvice()
        : RunWeekBalance.adviseMove(
            week: week,
            movingId: workout.id,
            to: dateOf(dayOfWeek),
          );
    var target = dayOfWeek;
    RunPlanWorkout? swap;
    if (!advice.ok) {
      final choice = await showBalanceDialog(
        context,
        advice: advice,
        nameOf: (id) => byId[id]?.name ?? '',
        dayLabel: (date) => RunPlanUi.weekdayLabel(loc, date.weekday),
      );
      if (choice == null || !mounted) return;
      switch (choice) {
        case BalanceChoice.swap:
          swap = byId[advice.swapWith!.id];
        case BalanceChoice.better:
          target = advice.betterDate!.weekday;
        case BalanceChoice.anyway:
          break;
      }
    }
    final from = workout.dayOfWeek;
    await _repo.moveWorkoutToDay(workout.id, target);
    if (swap != null && from != null) {
      await _repo.moveWorkoutToDay(swap.id, from);
    }
    if (!mounted) return;
    // Local update: a full reload would re-run the weekly review for a
    // change that cannot affect it.
    final swapped = swap;
    setState(() {
      final current = _plan;
      if (current == null) return;
      _plan = current.copyWith(
        workouts: [
          for (final item in current.workouts)
            if (item.id == workout.id)
              item.copyWith(dayOfWeek: target)
            else if (swapped != null && item.id == swapped.id)
              item.copyWith(dayOfWeek: from)
            else
              item,
        ],
      );
    });
  }

  // --- build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final plan = _plan;

    if (_loading || plan == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final today = _today;
    return Scaffold(
      appBar: AppBar(
        title: Text(plan.name),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: loc.runPlanEditTitle,
            icon: const Icon(Icons.edit_outlined),
            onPressed: _editHeader,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addSession,
        icon: const Icon(Icons.add),
        label: Text(loc.runPlanAddSession),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          // Bottom room so the extended FAB never covers the last row.
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
          children: [
            RunPlanIdentity(plan: plan, today: today),
            const SizedBox(height: 14),
            _buildStatus(plan, today),
            if (_adaptations.where((a) => a.applied).firstOrNull
                case final last?) ...[
              const SizedBox(height: 8),
              _buildAdaptationHistory(theme, loc, last),
            ],
            const SizedBox(height: 16),
            if (plan.weeks > 1) ...[
              _buildWeekStrip(plan, today),
              const SizedBox(height: 16),
            ],
            RunPlanWeekHeader(
              plan: plan,
              week: _week,
              weekStart: RunPlanWeekView.weekStart(plan, _week, today),
              isCurrent: plan.activeWeekIndexOn(today) == _week,
              scheduled: _scheduledWeeks.contains(_week),
              doneMeters: RunPlanWeekView.doneMeters(plan, _week, _ledger),
              onSchedule: _scheduleWeek,
              onCopy: plan.weeks > 1 ? _copyWeek : null,
            ),
            const SizedBox(height: 12),
            ..._buildWeekDays(theme, loc, plan, today),
          ],
        ),
      ),
    );
  }

  Widget _buildStatus(RunPlan plan, DateTime today) {
    final finished = plan.isFinishedOn(today) || _progress.isComplete;
    final next = _linkedToPlanning
        ? null
        : RunPlanWeekView.nextSession(plan, _ledger, today);
    final card = RunPlanStatusCard(
      plan: plan,
      progress: _progress,
      viaPlanning: _linkedToPlanning,
      today: today,
      next: next,
      onOpenNext: next == null
          ? null
          : () => _selectWeek(next.workout.weekIndex),
      onToggle: _linkedToPlanning ? null : _toggleFollow,
      onReset: (_progress.hasProgress || finished) && !_linkedToPlanning
          ? _resetProgress
          : null,
      onChooseNext: finished ? _chooseNextPlan : null,
      onClose: finished && plan.isActivated ? _closeFinishedPlan : null,
      nextTemplates: finished
          ? RunPlanTemplates.nextSteps(plan.templateKey, plan.goalKind)
          : const [],
      onStartTemplate: _startTemplate,
    );
    if (finished || _proposal == null) return card;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        card,
        const SizedBox(height: 12),
        RunPlanAdaptationCard(
          plan: plan,
          proposal: _proposal!,
          busy: _applying,
          onApply: _applyProposal,
          onKeep: _dismissProposal,
          onReturnPlan: () => _startTemplate(RunPlanTemplates.returnToRunning),
        ),
      ],
    );
  }

  Widget _buildAdaptationHistory(
    ThemeData theme,
    AppLocalizations loc,
    RunPlanAdaptationRecord last,
  ) {
    final scheme = theme.colorScheme;
    return Row(
      children: [
        Icon(Icons.tune_rounded, size: 14, color: scheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            loc.runPlanAdaptHistory(
              DateFormat('d MMM', Intl.defaultLocale).format(last.createdAt),
              _adaptationLabel(loc, last),
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  static String _adaptationLabel(
    AppLocalizations loc,
    RunPlanAdaptationRecord record,
  ) => switch (record.kind) {
    'hold' => loc.runPlanAdaptKindHold,
    'stepBack' => loc.runPlanAdaptKindStepBack,
    'rebuild' => loc.runPlanAdaptKindRebuild,
    _ => loc.runPlanAdaptKindPace,
  };

  Widget _buildWeekStrip(RunPlan plan, DateTime today) {
    final completed = <int>{
      for (var week = 0; week < plan.weeks; week++)
        if (plan.workoutsForWeek(week).isNotEmpty &&
            plan
                .workoutsForWeek(week)
                .every((w) => _ledger[w.id]?.isCompleted == true))
          week,
    };
    return RunPlanWeekStrip(
      plan: plan,
      controller: _weekStrip,
      selectedWeek: _week,
      currentWeek: plan.activeWeekIndexOn(today),
      scheduledWeeks: _scheduledWeeks,
      doneMeters: [
        for (var week = 0; week < plan.weeks; week++)
          RunPlanWeekView.doneMeters(plan, week, _ledger),
      ],
      completedWeeks: completed,
      onSelect: _selectWeek,
    );
  }

  Widget _sessionCard(
    RunPlanSessionView view, {
    required bool preview,
    required RunPlanSessionView? next,
    required bool canMove,
  }) {
    final isNext =
        next != null &&
        next.workout.id == view.workout.id &&
        next.date == view.date;
    return RunPlanSessionCard(
      key: preview ? null : ValueKey('run-plan-session-${view.workout.id}'),
      view: view,
      onTap: preview ? () {} : () => _openSession(view.workout),
      onEdit: preview ? () {} : () => _openSession(view.workout),
      onDuplicate: preview ? () {} : () => _duplicateSession(view.workout),
      onMove: canMove && !preview ? () => _moveSession(view.workout) : null,
      onDelete: preview ? () {} : () => _deleteSession(view.workout),
      onStart: isNext && !preview ? () => _startSession(view) : null,
      onOpenRun: view.ledger?.runActivityId == null || preview
          ? null
          : () => _openRun(view),
    );
  }

  /// One row per weekday, so the week reads like a training week. Sessions
  /// with no fixed day are appended at the end under a neutral marker.
  List<Widget> _buildWeekDays(
    ThemeData theme,
    AppLocalizations loc,
    RunPlan plan,
    DateTime today,
  ) {
    final views = RunPlanWeekView.sessionsForWeek(plan, _week, _ledger, today);
    if (views.isEmpty) return [_buildEmptyWeek(theme, loc)];

    final next = _linkedToPlanning
        ? null
        : RunPlanWeekView.nextSession(plan, _ledger, today);
    final strengthDays = _includesStrength(plan)
        ? RunStrengthPlanner.daysForPlanWeek(plan, _week)
        : const <int>[];
    final canMove = plan.weeks > 1;
    Widget cardFor(RunPlanSessionView view, {required bool preview}) =>
        _sessionCard(view, preview: preview, next: next, canMove: canMove);

    final rows = <Widget>[];
    for (var day = 1; day <= 7; day++) {
      final ofDay = [
        for (final view in views)
          if (view.workout.dayOfWeek == day) view,
      ];
      final strengthIndex = strengthDays.indexOf(day);
      final date = RunPlanWeekView.dateFor(plan, _week, day, today);
      rows.add(
        RunPlanDayRow(
          strength: strengthIndex < 0
              ? null
              : RunPlanStrengthChip(
                  label: strengthIndex.isEven
                      ? loc.runPlanStrengthA
                      : loc.runPlanStrengthB,
                  done: date != null && _strengthDone.contains(date),
                  onStart: () => _startStrength(strengthIndex),
                ),
          dayOfWeek: day,
          label: RunPlanUi.weekdayLabel(loc, day),
          date: date,
          isToday: date != null && date == today,
          sessions: ofDay,
          cardBuilder: cardFor,
          onAdd: () => _addSession(dayOfWeek: day),
          onMoveToDay: _moveSessionToDay,
        ),
      );
    }
    final floating = [
      for (final view in views)
        if (view.workout.dayOfWeek == null) view,
    ];
    if (floating.isNotEmpty) {
      rows.add(
        RunPlanDayRow(
          dayOfWeek: null,
          label: '—',
          date: null,
          isToday: false,
          sessions: floating,
          cardBuilder: cardFor,
          onMoveToDay: _moveSessionToDay,
        ),
      );
    }
    return rows;
  }

  Widget _buildEmptyWeek(ThemeData theme, AppLocalizations loc) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28),
    child: Column(
      children: [
        Icon(
          Icons.event_note_outlined,
          size: 48,
          color: theme.colorScheme.primary.withAlpha(70),
        ),
        const SizedBox(height: 12),
        Text(loc.runPlanWeekEmpty, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          loc.runPlanWeekEmptySubtitle,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _addSession,
          icon: const Icon(Icons.add, size: 18),
          label: Text(loc.runPlanAddSession),
        ),
      ],
    ),
  );
}
