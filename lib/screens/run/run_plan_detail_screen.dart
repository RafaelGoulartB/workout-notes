import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_plan.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/models/scheduled_run.dart';
import 'package:workout_notes/repositories/run_plan_repository.dart';
import 'package:workout_notes/screens/run/run_plan_workout_editor_screen.dart';
import 'package:workout_notes/widgets/run/run_plan_ui.dart';

/// Plan detail: identity header, week picker and the training week laid out by
/// weekday. A running week is read by day ("longão no domingo"), so the week is
/// drawn as seven rows instead of an undifferentiated list of sessions.
class RunPlanDetailScreen extends StatefulWidget {
  final String planId;

  const RunPlanDetailScreen({super.key, required this.planId});

  @override
  State<RunPlanDetailScreen> createState() => _RunPlanDetailScreenState();
}

class _RunPlanDetailScreenState extends State<RunPlanDetailScreen> {
  static const _weekTileWidth = 58.0;

  final _repo = RunPlanRepository();
  final _weekStrip = ScrollController();
  RunPlan? _plan;
  Set<int> _scheduledWeeks = const {};
  RunPlanProgress _progress = const RunPlanProgress();
  Map<String, ScheduledRunStatus> _workoutStatuses = const {};

  /// Driven by a periodization phase: the phase owns the week mapping, so this
  /// screen reports it instead of offering its own activation.
  bool _linkedToPlanning = false;
  bool _loading = true;
  int _week = 0;

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
    final scheduled = await _repo.getScheduledWeeks(plan.id);
    final progress = await _repo.getPlanProgress(plan.id);
    final workoutStatuses = await _repo.getPlanWorkoutStatuses(plan.id);
    final linked = await _repo.isLinkedToPeriodization(plan.id);
    if (!mounted) return;
    setState(() {
      _plan = plan;
      _scheduledWeeks = scheduled;
      _progress = progress;
      _workoutStatuses = workoutStatuses;
      _linkedToPlanning = linked;
      _week = _week.clamp(0, plan.weeks - 1);
      _loading = false;
    });
  }

  /// Follows this plan from today, or stops following it. Only one plan is
  /// followed at a time, so this replaces any previous one.
  Future<void> _toggleFollow() async {
    final loc = AppLocalizations.of(context)!;
    final plan = _plan;
    if (plan == null) return;
    if (plan.isActivated) {
      await _repo.deactivatePlan(plan.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.runPlanDeactivatedMessage)));
    } else {
      final current = await _repo.getActivatedPlan(hydrate: false);
      if (!mounted) return;
      if (current != null && current.id != plan.id) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(loc.runPlanReplaceActiveTitle),
            content: Text(loc.runPlanReplaceActiveBody(current.name)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(loc.runPlanActivate),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
      }
      final created = await _repo.activatePlan(plan.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.runPlanActivatedMessage(created))),
      );
    }
    await _load();
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

  void _selectWeek(int week) {
    setState(() => _week = week);
    _revealWeek(week);
  }

  /// Keeps the selected tile on screen — a 16-week plan scrolls far enough that
  /// the selection would otherwise sit outside the viewport.
  void _revealWeek(int week) {
    if (!_weekStrip.hasClients) return;
    final viewport = _weekStrip.position.viewportDimension;
    final target =
        (week * _weekTileWidth) - (viewport / 2) + _weekTileWidth / 2;
    _weekStrip.animateTo(
      target.clamp(0.0, _weekStrip.position.maxScrollExtent),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _editHeader() async {
    final plan = _plan;
    if (plan == null) return;
    final loc = AppLocalizations.of(context)!;
    final nameCtl = TextEditingController(text: plan.name);
    final notesCtl = TextEditingController(text: plan.notes ?? '');
    final weeksCtl = TextEditingController(text: plan.weeks.toString());
    var goal = plan.goalKind;
    var raceDate = plan.raceDate;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  loc.runPlanEditTitle,
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameCtl,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: loc.runPlanName,
                    hintText: loc.runPlanNameHint,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<RunPlanGoalKind>(
                  initialValue: goal,
                  decoration: InputDecoration(
                    labelText: loc.runPlanGoalKind,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (final kind in RunPlanGoalKind.values)
                      DropdownMenuItem(
                        value: kind,
                        child: Text(RunPlanUi.goalLabel(loc, kind)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setSheetState(() => goal = value);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: weeksCtl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: loc.runPlanWeeks,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 4),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.flag_outlined),
                  title: Text(loc.runPlanRaceDate),
                  subtitle: Text(
                    raceDate == null
                        ? loc.runPlanRaceDateNone
                        : DateFormat(
                            'd MMM y',
                            Intl.defaultLocale,
                          ).format(raceDate!),
                  ),
                  trailing: raceDate == null
                      ? const Icon(Icons.event_outlined)
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => setSheetState(() => raceDate = null),
                        ),
                  onTap: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: raceDate ?? now,
                      firstDate: DateTime(now.year - 1),
                      lastDate: DateTime(now.year + 5),
                    );
                    if (picked != null) setSheetState(() => raceDate = picked);
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: notesCtl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: loc.runPlanNotes,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(loc.commonSave),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
    if (saved != true) return;

    final weeks = int.tryParse(weeksCtl.text.trim());
    // Shrinking the horizon drops sessions, so confirm before losing them.
    if (weeks != null && weeks < plan.weeks) {
      final dropped = plan.workouts
          .where((workout) => workout.weekIndex >= weeks)
          .length;
      if (dropped > 0 && mounted) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(loc.commonConfirmDelete),
            content: Text(loc.commonActionCannotBeUndone),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(loc.commonCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(loc.commonSave),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
      }
    }

    await _repo.updatePlan(
      plan.id,
      name: nameCtl.text.trim().isEmpty ? null : nameCtl.text.trim(),
      notes: notesCtl.text.trim(),
      goalKind: goal,
      raceDate: raceDate,
      weeks: weeks,
    );
    if (mounted) _load();
  }

  Future<void> _addSession({int? dayOfWeek}) async {
    final plan = _plan;
    if (plan == null) return;
    final loc = AppLocalizations.of(context)!;
    final created = await _repo.addWorkout(
      planId: plan.id,
      weekIndex: _week,
      name: loc.runWorkoutKindEasy,
      dayOfWeek: dayOfWeek,
    );
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RunPlanWorkoutEditorScreen(workoutId: created.id),
      ),
    );
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
    final target = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                loc.runPlanMoveWeekTitle,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (var week = 0; week < plan.weeks; week++)
                    if (week != workout.weekIndex)
                      ListTile(
                        title: Text(loc.runPlanWeekLabel(week + 1)),
                        subtitle: Text(
                          loc.runPlanWeekSummary(
                            RunPlanUi.kmValue(plan.weeklyDistanceMeters(week)),
                            plan.workoutsForWeek(week).length,
                          ),
                        ),
                        onTap: () => Navigator.pop(ctx, week),
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
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
    await _repo.updateWorkout(workout.id, dayOfWeek: dayOfWeek);
    if (!mounted) return;
    setState(() {
      final plan = _plan;
      if (plan == null) return;
      _plan = plan.copyWith(
        workouts: [
          for (final item in plan.workouts)
            if (item.id == workout.id)
              item.copyWith(dayOfWeek: dayOfWeek)
            else
              item,
        ],
      );
    });
  }

  Future<void> _copyWeek() async {
    final plan = _plan;
    if (plan == null || plan.weeks < 2) return;
    final loc = AppLocalizations.of(context)!;
    final selected = <int>{};
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  loc.runPlanCopyWeekTitle(_week + 1),
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (var i = 0; i < plan.weeks; i++)
                      if (i != _week)
                        CheckboxListTile(
                          value: selected.contains(i),
                          title: Text(loc.runPlanWeekLabel(i + 1)),
                          subtitle: Text(
                            loc.runPlanWeekSummary(
                              RunPlanUi.kmValue(plan.weeklyDistanceMeters(i)),
                              plan.workoutsForWeek(i).length,
                            ),
                          ),
                          onChanged: (checked) => setSheetState(() {
                            if (checked == true) {
                              selected.add(i);
                            } else {
                              selected.remove(i);
                            }
                          }),
                        ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: selected.isEmpty
                        ? null
                        : () => Navigator.pop(ctx, true),
                    child: Text(loc.runPlanCopyWeek),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true || selected.isEmpty) return;
    final applied = await _repo.copyWeek(
      plan.id,
      sourceWeek: _week,
      targetWeeks: selected,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final plan = _plan;

    if (_loading || plan == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

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
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            _buildHeaderCard(theme, loc, plan),
            const SizedBox(height: 16),
            if (plan.weeks > 1) ...[
              _buildWeekPicker(theme, loc, plan),
              const SizedBox(height: 16),
            ],
            _buildWeekHeader(theme, loc, plan),
            const SizedBox(height: 12),
            ..._buildWeekDays(theme, loc, plan),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard(ThemeData theme, AppLocalizations loc, RunPlan plan) {
    final scheme = theme.colorScheme;
    final countdown = _raceCountdown(plan.raceDate);
    // Deliberately not a card: for most plans this is one line of identity, and
    // a box around it only pushed the training week further down.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.flag_outlined, size: 16, color: scheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${RunPlanUi.goalLabel(loc, plan.goalKind)} · '
                  '${loc.runPlanWeeksValue(plan.weeks)}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (plan.raceDate != null) ...[
            const SizedBox(height: 6),
            Text(
              countdown == null
                  ? DateFormat(
                      'd MMM y',
                      Intl.defaultLocale,
                    ).format(plan.raceDate!)
                  : '${DateFormat('d MMM', Intl.defaultLocale).format(plan.raceDate!)}'
                        ' · ${loc.runPlanRaceCountdown(countdown)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (plan.notes != null && plan.notes!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              plan.notes!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 14),
          _FollowCard(
            plan: plan,
            progress: _progress,
            viaPlanning: _linkedToPlanning,
            onToggle: _linkedToPlanning ? null : _toggleFollow,
            onReset: _progress.hasProgress && !_linkedToPlanning
                ? _resetProgress
                : null,
          ),
        ],
      ),
    );
  }

  /// Horizontal week picker. Each tile carries that week's volume as a bar, so
  /// the ramp and the taper are visible while picking.
  Widget _buildWeekPicker(ThemeData theme, AppLocalizations loc, RunPlan plan) {
    final volumes = [
      for (var week = 0; week < plan.weeks; week++)
        plan.weeklyDistanceMeters(week),
    ];
    final peak = volumes.fold<double>(
      0,
      (max, value) => value > max ? value : max,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          loc.runPlanWeeklyVolumeTitle.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 96,
          child: ListView.builder(
            controller: _weekStrip,
            scrollDirection: Axis.horizontal,
            itemCount: plan.weeks,
            itemExtent: _weekTileWidth,
            itemBuilder: (context, week) => _WeekTile(
              week: week,
              volume: volumes[week],
              peak: peak,
              selected: week == _week,
              scheduled: _scheduledWeeks.contains(week),
              completed: plan
                  .workoutsForWeek(week)
                  .every(
                    (workout) =>
                        _workoutStatuses[workout.id] ==
                        ScheduledRunStatus.completed,
                  ),
              onTap: () => _selectWeek(week),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWeekHeader(ThemeData theme, AppLocalizations loc, RunPlan plan) {
    final sessions = plan.workoutsForWeek(_week);
    final longRun = plan.longRunForWeek(_week);
    final quality = plan.qualitySessionsForWeek(_week);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                loc.runPlanWeekLabel(_week + 1),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (_scheduledWeeks.contains(_week))
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: _Badge(
                  icon: Icons.event_available,
                  label: loc.runPlanWeekScheduled,
                ),
              ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz),
              onSelected: (value) => switch (value) {
                'copy' => _copyWeek(),
                'schedule' => _scheduleWeek(),
                _ => null,
              },
              itemBuilder: (ctx) => [
                if (plan.weeks > 1)
                  PopupMenuItem(
                    value: 'copy',
                    child: Text(loc.runPlanCopyWeek),
                  ),
                PopupMenuItem(
                  value: 'schedule',
                  child: Text(loc.runPlanScheduleWeek),
                ),
              ],
            ),
          ],
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _Badge(
              icon: Icons.straighten,
              label: loc.runPlanWeekSummary(
                RunPlanUi.kmValue(plan.weeklyDistanceMeters(_week)),
                sessions.length,
              ),
            ),
            if (longRun != null)
              _Badge(
                icon: Icons.timeline,
                label:
                    '${loc.runPlanLongRun} '
                    '${RunPlanUi.distanceLabel(longRun.plannedDistanceMeters)}',
              ),
            if (quality > 0)
              _Badge(
                icon: Icons.bolt,
                label: loc.runPlanQualityCount(quality),
                highlight: true,
              ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.tonalIcon(
            onPressed: sessions.isEmpty ? null : _scheduleWeek,
            icon: const Icon(Icons.event_available_outlined, size: 18),
            label: Text(loc.runPlanScheduleWeek),
          ),
        ),
      ],
    );
  }

  /// One row per weekday, so the week reads like a training week. Sessions with
  /// no fixed day are appended at the end under a neutral marker.
  List<Widget> _buildWeekDays(
    ThemeData theme,
    AppLocalizations loc,
    RunPlan plan,
  ) {
    final sessions = plan.workoutsForWeek(_week);
    if (sessions.isEmpty) return [_buildEmptyWeek(theme, loc)];

    final today = DateTime.now().weekday;
    final rows = <Widget>[];
    for (var day = 1; day <= 7; day++) {
      final ofDay = sessions
          .where((workout) => workout.dayOfWeek == day)
          .toList();
      rows.add(
        _DayRow(
          dayOfWeek: day,
          label: RunPlanUi.weekdayLabel(loc, day),
          isToday: day == today,
          sessions: ofDay,
          onAdd: () => _addSession(dayOfWeek: day),
          onOpen: _openSession,
          onDuplicate: _duplicateSession,
          onMove: plan.weeks > 1 ? _moveSession : null,
          onDelete: _deleteSession,
          onMoveToDay: _moveSessionToDay,
          statuses: _workoutStatuses,
        ),
      );
    }
    final floating = sessions
        .where((workout) => workout.dayOfWeek == null)
        .toList();
    if (floating.isNotEmpty) {
      rows.add(
        _DayRow(
          dayOfWeek: null,
          label: '—',
          isToday: false,
          sessions: floating,
          onOpen: _openSession,
          onDuplicate: _duplicateSession,
          onMove: plan.weeks > 1 ? _moveSession : null,
          onDelete: _deleteSession,
          onMoveToDay: _moveSessionToDay,
          statuses: _workoutStatuses,
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

  static int? _raceCountdown(DateTime? raceDate) {
    if (raceDate == null) return null;
    final now = DateTime.now();
    final days = DateTime(
      raceDate.year,
      raceDate.month,
      raceDate.day,
    ).difference(DateTime(now.year, now.month, now.day)).inDays;
    return days < 0 ? null : days;
  }
}

class _WeekTile extends StatelessWidget {
  final int week;
  final double volume;
  final double peak;
  final bool selected;
  final bool scheduled;
  final bool completed;
  final VoidCallback onTap;

  const _WeekTile({
    required this.week,
    required this.volume,
    required this.peak,
    required this.selected,
    required this.scheduled,
    required this.completed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Never a fixed bar height: the text around it grows with the system font
    // scale, and the bar is the part that can afford to shrink.
    final fill = peak <= 0 ? 0.04 : (volume / peak).clamp(0.04, 1.0);

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: selected
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest.withAlpha(70),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Column(
              children: [
                Text(
                  volume <= 0 ? '—' : RunPlanUi.kmValue(volume),
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? scheme.onPrimaryContainer
                        : scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: FractionallySizedBox(
                    alignment: Alignment.bottomCenter,
                    heightFactor: fill,
                    widthFactor: null,
                    child: Container(
                      width: 16,
                      decoration: BoxDecoration(
                        color: selected
                            ? scheme.primary
                            : scheme.primary.withAlpha(90),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${week + 1}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: selected
                            ? scheme.onPrimaryContainer
                            : scheme.onSurface,
                      ),
                    ),
                    if (completed) ...[
                      const SizedBox(width: 3),
                      Icon(
                        Icons.check_circle_rounded,
                        size: 12,
                        color: scheme.tertiary,
                      ),
                    ] else if (scheduled) ...[
                      const SizedBox(width: 3),
                      Icon(Icons.circle, size: 5, color: scheme.tertiary),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A weekday and whatever is planned on it — or an explicit rest marker, which
/// is information too: a week with four rest days is a light week.
class _DayRow extends StatelessWidget {
  final int? dayOfWeek;
  final String label;
  final bool isToday;
  final List<RunPlanWorkout> sessions;
  final VoidCallback? onAdd;
  final ValueChanged<RunPlanWorkout> onOpen;
  final ValueChanged<RunPlanWorkout> onDuplicate;
  final ValueChanged<RunPlanWorkout>? onMove;
  final ValueChanged<RunPlanWorkout> onDelete;
  final void Function(RunPlanWorkout workout, int dayOfWeek) onMoveToDay;
  final Map<String, ScheduledRunStatus> statuses;

  const _DayRow({
    required this.dayOfWeek,
    required this.label,
    required this.isToday,
    required this.sessions,
    required this.onOpen,
    required this.onDuplicate,
    required this.onDelete,
    required this.onMoveToDay,
    required this.statuses,
    this.onAdd,
    this.onMove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 38,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                label.replaceAll('.', '').toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: isToday ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          Expanded(
            child: DragTarget<RunPlanWorkout>(
              key: dayOfWeek == null
                  ? null
                  : ValueKey('run-plan-day-$dayOfWeek'),
              onWillAcceptWithDetails: (details) =>
                  dayOfWeek != null && details.data.dayOfWeek != dayOfWeek,
              onAcceptWithDetails: (details) {
                final targetDay = dayOfWeek;
                if (targetDay != null) {
                  onMoveToDay(details.data, targetDay);
                }
              },
              builder: (context, candidates, rejected) {
                final isTarget = candidates.isNotEmpty;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: isTarget ? const EdgeInsets.all(3) : EdgeInsets.zero,
                  decoration: BoxDecoration(
                    color: isTarget
                        ? scheme.primaryContainer.withAlpha(90)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    border: isTarget
                        ? Border.all(color: scheme.primary, width: 1.5)
                        : null,
                  ),
                  child: sessions.isEmpty
                      ? _RestRow(onAdd: onAdd)
                      : Column(
                          children: [
                            for (final session in sessions)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: LongPressDraggable<RunPlanWorkout>(
                                  data: session,
                                  hapticFeedbackOnStart: true,
                                  feedback: Material(
                                    color: Colors.transparent,
                                    elevation: 8,
                                    borderRadius: BorderRadius.circular(14),
                                    child: SizedBox(
                                      width:
                                          (MediaQuery.sizeOf(context).width -
                                                  96)
                                              .clamp(220.0, 360.0)
                                              .toDouble(),
                                      child: _SessionCard(
                                        workout: session,
                                        status: statuses[session.id],
                                        onTap: () {},
                                        onDuplicate: () {},
                                        onDelete: () {},
                                      ),
                                    ),
                                  ),
                                  childWhenDragging: Opacity(
                                    opacity: 0.25,
                                    child: _buildSessionCard(session),
                                  ),
                                  child: _buildSessionCard(session),
                                ),
                              ),
                          ],
                        ),
                );
              },
            ),
          ),
          if (isToday)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 12),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
            )
          else
            const SizedBox(width: 10),
        ],
      ),
    );
  }

  Widget _buildSessionCard(RunPlanWorkout session) => _SessionCard(
    key: ValueKey('run-plan-session-${session.id}'),
    workout: session,
    status: statuses[session.id],
    onTap: () => onOpen(session),
    onDuplicate: () => onDuplicate(session),
    onMove: onMove == null ? null : () => onMove!(session),
    onDelete: () => onDelete(session),
  );
}

class _RestRow extends StatelessWidget {
  final VoidCallback? onAdd;

  const _RestRow({this.onAdd});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    return InkWell(
      onTap: onAdd,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withAlpha(70),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                loc.runPlanRestDay,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withAlpha(150),
                ),
              ),
            ),
            if (onAdd != null)
              Icon(
                Icons.add,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant.withAlpha(150),
              ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool highlight;

  const _Badge({
    required this.icon,
    required this.label,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = highlight
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(24),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  final RunPlanWorkout workout;
  final ScheduledRunStatus? status;
  final VoidCallback onTap;
  final VoidCallback onDuplicate;
  final VoidCallback? onMove;
  final VoidCallback onDelete;

  const _SessionCard({
    super.key,
    required this.workout,
    required this.status,
    required this.onTap,
    required this.onDuplicate,
    required this.onDelete,
    this.onMove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final scheme = theme.colorScheme;
    final color = RunPlanUi.kindColor(scheme, workout.kind);
    final outline = RunPlanUi.stepsOutline(loc, workout);
    final estimate = RunPlanUi.estimatedTotalSeconds(workout);
    final completed = status == ScheduledRunStatus.completed;
    final skipped = status == ScheduledRunStatus.skipped;
    final statusColor = completed ? scheme.tertiary : scheme.onSurfaceVariant;

    return Material(
      color: completed
          ? scheme.tertiaryContainer.withAlpha(70)
          : scheme.surfaceContainerHighest.withAlpha(70),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: color.withAlpha(34),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      RunPlanUi.kindIcon(workout.kind),
                      color: color,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          workout.name,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            decoration: completed
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            RunPlanUi.kindLabel(loc, workout.kind),
                            RunPlanUi.sessionSummary(loc, workout),
                            if (estimate > 0)
                              '~${RunPlanUi.durationRoughLabel(estimate)}',
                          ].where((part) => part.isNotEmpty).join(' · '),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (completed || skipped)
                    Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: _Badge(
                        icon: completed
                            ? Icons.check_circle_rounded
                            : Icons.skip_next_rounded,
                        label: completed
                            ? loc.runPlanSessionCompleted
                            : loc.runPlanSessionSkipped,
                        highlight: completed,
                      ),
                    ),
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    padding: EdgeInsets.zero,
                    onSelected: (value) => switch (value) {
                      'duplicate' => onDuplicate(),
                      'move' => onMove?.call(),
                      'delete' => onDelete(),
                      _ => null,
                    },
                    itemBuilder: (ctx) => [
                      PopupMenuItem(
                        value: 'duplicate',
                        child: Text(loc.runPlanSessionDuplicate),
                      ),
                      if (onMove != null)
                        PopupMenuItem(
                          value: 'move',
                          child: Text(loc.runPlanSessionMove),
                        ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(loc.runWorkoutDelete),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: RunWorkoutProfileBar(workout: workout, height: 8),
              ),
              if (completed) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.verified_rounded, size: 14, color: statusColor),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        loc.runPlanSessionCompletedHint,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (outline.isNotEmpty) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    outline,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Follow state of the plan: whether it is driving "which run is due today",
/// how far along it is, and the action to start or stop following it.
///
/// [onToggle] is null when a periodization phase owns the plan's weeks — the
/// card then only reports that, since a second anchor would contradict it.
class _FollowCard extends StatelessWidget {
  final RunPlan plan;
  final RunPlanProgress progress;
  final bool viaPlanning;
  final VoidCallback? onToggle;
  final VoidCallback? onReset;

  const _FollowCard({
    required this.plan,
    required this.progress,
    required this.viaPlanning,
    required this.onToggle,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final following = plan.isActivated || viaPlanning;
    final complete = progress.isComplete;
    final week = plan.activeWeekIndexOn(DateTime.now());
    final accent = complete
        ? scheme.tertiary
        : following
        ? scheme.primary
        : scheme.onSurfaceVariant;

    final String status;
    if (complete) {
      status = loc.runPlanCompletedHelp;
    } else if (viaPlanning) {
      status = loc.runPlanActiveViaHelp;
    } else if (week != null) {
      status = loc.runPlanCurrentWeek(week + 1, plan.weeks);
    } else {
      status = loc.runPlanActivateHint;
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: complete
            ? scheme.tertiaryContainer.withAlpha(80)
            : following
            ? scheme.primary.withAlpha(16)
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: complete
              ? scheme.tertiary.withAlpha(100)
              : following
              ? scheme.primary.withAlpha(90)
              : scheme.outlineVariant.withAlpha(90),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                complete
                    ? Icons.workspace_premium_rounded
                    : viaPlanning
                    ? Icons.route_rounded
                    : (following
                          ? Icons.play_circle_outline
                          : Icons.flag_outlined),
                size: 18,
                color: accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                // The heading is the state; the button is the action. Saying
                // "Seguir este plano" in both read like a duplicate.
                child: Text(
                  viaPlanning
                      ? loc.runPlanActiveVia
                      : complete
                      ? loc.runPlanCompletedBadge
                      : (following
                            ? loc.runPlanActiveBadge
                            : progress.hasProgress
                            ? loc.runPlanPausedBadge
                            : loc.runPlanNotFollowing),
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
              ),
              if (onReset != null)
                TextButton.icon(
                  onPressed: onReset,
                  icon: const Icon(Icons.restart_alt_rounded, size: 17),
                  label: Text(loc.runPlanResetShort),
                ),
              if (onToggle != null && !complete)
                following
                    ? TextButton(
                        onPressed: onToggle,
                        child: Text(loc.runPlanUnfollowShort),
                      )
                    : FilledButton.tonalIcon(
                        onPressed: onToggle,
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: Text(loc.runPlanFollowShort),
                      ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            status,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (progress.totalSessions > 0) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: progress.fraction,
                      minHeight: 6,
                      color: scheme.primary,
                      backgroundColor: scheme.primary.withAlpha(30),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  loc.runPlanProgressValue(
                    progress.completedSessions,
                    progress.totalSessions,
                  ),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
