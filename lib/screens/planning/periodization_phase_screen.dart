import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/periodization_checkin.dart';
import 'package:workout_notes/models/periodization_phase.dart';
import 'package:workout_notes/models/periodization_plan.dart';
import 'package:workout_notes/models/periodization_schedule.dart';
import 'package:workout_notes/models/periodization_target.dart';
import 'package:workout_notes/periodization/phase_kind.dart';
import 'package:workout_notes/periodization/week_progress.dart';
import 'package:workout_notes/widgets/periodization/planning_widgets.dart';

import 'periodization_checkin_flow.dart';
import 'periodization_phase_editor_screen.dart';
import 'package:workout_notes/utils/date_utils.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// A phase at a glance: what it plans (targets and template week) and how
/// each of its weeks went (planned vs done, weekly review).
class PeriodizationPhaseScreen extends StatefulWidget {
  final PeriodizationPlan plan;
  final PeriodizationPhase phase;

  const PeriodizationPhaseScreen({
    super.key,
    required this.plan,
    required this.phase,
  });

  @override
  State<PeriodizationPhaseScreen> createState() =>
      _PeriodizationPhaseScreenState();
}

class _PeriodizationPhaseScreenState extends State<PeriodizationPhaseScreen> {
  final _repository = DatabaseHelper.instance.periodizationRepo;
  late PeriodizationPhase _phase = widget.phase;
  late PeriodizationPlan _plan = widget.plan;
  List<PeriodizationPhase> _planPhases = const [];
  List<PeriodizationTarget?> _weeks = const [];
  final Map<int, WeekProgress> _progress = {};
  Map<String, PeriodizationCheckin> _checkins = const {};
  Map<String, String> _routineNames = const {};
  Map<String, List<String>> _routineDays = const {};
  int _selected = 0;
  bool _loading = true;
  bool _changed = false;

  DateTime get _today {
    final now = DateTime.now();
    return dayOf(now);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final phase = await _repository.getPhase(widget.phase.id);
    if (phase == null) {
      if (mounted) Navigator.pop(context, true);
      return;
    }
    final routineRepo = DatabaseHelper.instance.routineRepo;
    final results = await Future.wait<Object?>([
      _repository.getWeeklyTargets(phase),
      _repository.getCheckins(phase.id),
      routineRepo.getRoutines(),
      routineRepo.getRoutineDayNames(),
      _repository.getPlan(phase.planId),
      _repository.getPhases(phase.planId),
    ]);
    final currentWeek = phase.contains(_today)
        ? phase.weekAt(_today) - 1
        : phase.endDate.isBefore(_today)
        ? phase.totalWeeks - 1
        : 0;
    // Weeks that already started get their numbers up front so the strip
    // can show how each went; later weeks load when opened.
    final started = [
      for (var week = 0; week < phase.totalWeeks; week++)
        if (!phase.startDate.add(Duration(days: 7 * week)).isAfter(_today))
          week,
    ];
    final progress = await Future.wait([
      for (final week in {...started, currentWeek})
        WeekProgress.load(_repository, phase, week),
    ]);
    if (!mounted) return;
    setState(() {
      _phase = phase;
      _plan = results[4] as PeriodizationPlan? ?? _plan;
      _planPhases = results[5] as List<PeriodizationPhase>;
      _weeks = results[0] as List<PeriodizationTarget?>;
      _checkins = {
        for (final checkin in results[1] as List<PeriodizationCheckin>)
          _key(checkin.weekStart): checkin,
      };
      _routineNames = {
        for (final row in results[2] as List<Map<String, dynamic>>)
          row['id'] as String: row['name'] as String? ?? '',
      };
      _routineDays = results[3] as Map<String, List<String>>;
      _progress
        ..clear()
        ..addEntries(progress.map((item) => MapEntry(item.weekIndex, item)));
      if (_loading) _selected = currentWeek;
      _loading = false;
    });
  }

  Future<void> _select(int week) async {
    setState(() => _selected = week);
    if (_progress.containsKey(week)) return;
    final progress = await WeekProgress.load(_repository, _phase, week);
    if (!mounted) return;
    setState(() => _progress[week] = progress);
  }

  Future<void> _edit() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PeriodizationPhaseEditorScreen(plan: _plan, phase: _phase),
      ),
    );
    if (saved == true) {
      _changed = true;
      await _load();
    }
  }

  Future<void> _review(DateTime weekStart) async {
    final changed = await PeriodizationCheckinFlow.run(
      context: context,
      plan: _plan,
      phase: _phase,
      weekStart: weekStart,
    );
    if (changed) {
      _changed = true;
      await _load();
    }
  }

  Future<void> _endThisWeek() async {
    final loc = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: loc.planningEndPhaseTitle,
      message: loc.planningEndPhaseBody,
      confirmLabel: loc.planningEndPhaseConfirm,
    );
    if (confirmed != true) return;
    await _repository.endPhaseThisWeek(_phase.id);
    _changed = true;
    await _load();
  }

  Future<void> _delete() async {
    final loc = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: loc.planningDeletePhaseTitle,
      message: loc.planningDeletePhaseBody(_phase.name),
      confirmLabel: loc.planningDelete,
    );
    if (confirmed != true) return;
    final remaining = _planPhases.where((p) => p.id != _phase.id).toList();
    await _repository.replanPlan(
      planId: _plan.id,
      name: _plan.name,
      notes: _plan.notes,
      startDate: _planPhases.first.startDate,
      phases: [
        for (final item in remaining)
          PhaseScheduleEntry(
            id: item.id,
            name: item.name,
            templateKey: item.templateKey ?? PhaseKind.custom.key,
            color: item.color,
            intent: item.intent,
            weeks: item.totalWeeks,
          ),
      ],
    );
    if (mounted) Navigator.pop(context, true);
  }

  static String _key(DateTime date) {
    return dateKey(mondayOf(date));
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_phase.name),
          actions: [
            IconButton(
              key: const Key('phaseScreenEdit'),
              tooltip: loc.planningEditPhase,
              onPressed: _loading ? null : _edit,
              icon: const Icon(Icons.edit_outlined),
            ),
            PopupMenuButton<String>(
              onSelected: (value) => switch (value) {
                'end' => _endThisWeek(),
                'delete' => _delete(),
                _ => null,
              },
              itemBuilder: (context) => [
                if (_phase.contains(_today) &&
                    _phase.weekAt(_today) < _phase.totalWeeks)
                  PopupMenuItem(
                    value: 'end',
                    child: Text(loc.planningEndPhaseMenu),
                  ),
                if (_planPhases.length > 1)
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(loc.planningDeletePhaseMenu),
                  ),
              ],
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  children: [
                    _Header(phase: _phase, today: _today),
                    PlanningSectionLabel(
                      loc.planningPhaseTargets,
                      icon: Icons.track_changes_outlined,
                      actionLabel: loc.planningEdit,
                      onAction: _edit,
                    ),
                    _TargetsCard(
                      target: _selectedTarget,
                      dayPlan: _progress[_selected]?.plan,
                      routineNames: _routineNames,
                      onEdit: _edit,
                    ),
                    PlanningSectionLabel(
                      loc.planningWeeks,
                      icon: Icons.calendar_view_week_outlined,
                    ),
                    _WeekStrip(
                      phase: _phase,
                      weeks: _weeks,
                      progress: _progress,
                      selected: _selected,
                      today: _today,
                      onSelect: _select,
                    ),
                    const SizedBox(height: 12),
                    _WeekDetail(
                      phase: _phase,
                      week: _selected,
                      target: _selectedTarget,
                      progress: _progress[_selected],
                      checkin:
                          _checkins[_key(
                            _phase.startDate.add(Duration(days: 7 * _selected)),
                          )],
                      today: _today,
                      strengthLabels: [
                        for (final id
                            in _selectedTarget?.routineIds ?? const <String>[])
                          ...?_routineDays[id],
                      ],
                      onReview: _review,
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  PeriodizationTarget? get _selectedTarget =>
      _selected < _weeks.length ? _weeks[_selected] : null;
}

class _Header extends StatelessWidget {
  final PeriodizationPhase phase;
  final DateTime today;

  const _Header({required this.phase, required this.today});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = Color(phase.color);
    final kind = PhaseKind.fromKey(phase.templateKey);
    final current = phase.contains(today);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PhaseAvatar.of(phase, size: 52),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      phaseStatusLabel(loc, phase, today).toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${kind.label(loc)} · '
                      '${loc.planningWeeksShort(phase.totalWeeks)}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      planningDateRange(phase.startDate, phase.endDate),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (current) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: phase.progressAt(today).toDouble(),
                minHeight: 6,
                color: color,
                backgroundColor: color.withAlpha(40),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              loc.planningDaysLeft(phase.endDate.difference(today).inDays),
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          if (phase.intent != null && phase.intent!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(phase.intent!, style: theme.textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}

/// Everything the phase asks for, grouped by area.
class _TargetsCard extends StatelessWidget {
  final PeriodizationTarget? target;
  final PeriodizationDayPlan? dayPlan;
  final Map<String, String> routineNames;
  final VoidCallback onEdit;

  const _TargetsCard({
    required this.target,
    required this.dayPlan,
    required this.routineNames,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final target = this.target;
    if (target == null || target.isEmpty) {
      return PlanningCard(
        onTap: onEdit,
        child: Row(
          children: [
            Icon(Icons.edit_note_rounded, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(child: Text(loc.planningNoTargetsYet)),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      );
    }
    final rows = <Widget>[
      if (target.calories != null)
        _TargetRow(
          icon: Icons.local_fire_department_outlined,
          title: target.hasRestDayNutrition
              ? loc.planningKcalTrainingRest(
                  planningKcal(target.calories),
                  planningKcal(target.restCalories),
                )
              : '${planningKcal(target.calories)} kcal',
          subtitle: _macros(loc, target),
        ),
      if (target.routineIds.isNotEmpty || target.strengthDays.isNotEmpty)
        _TargetRow(
          icon: Icons.fitness_center_rounded,
          title: [
            if (target.strengthDays.isNotEmpty)
              loc.planningWorkoutsPerWeek(target.strengthDays.length),
            ...target.routineIds.map((id) => routineNames[id]).nonNulls,
          ].join(' · '),
          subtitle: _volume(loc, target),
        ),
      if (dayPlan?.runPlan case final plan?)
        _TargetRow(
          icon: Icons.directions_run_rounded,
          title: plan.name,
          subtitle: dayPlan?.runPlanWeek == null
              ? null
              : loc.planningRunPlanWeek(dayPlan!.runPlanWeek! + 1, plan.weeks),
        )
      else if (target.runDays.isNotEmpty ||
          target.runWeeklyDistanceMeters != null)
        _TargetRow(
          icon: Icons.directions_run_rounded,
          title: [
            if (target.runDays.isNotEmpty)
              loc.planningRunsPerWeek(target.runDays.length),
            if (target.runWeeklyDistanceMeters != null)
              '${(target.runWeeklyDistanceMeters! / 1000).toStringAsFixed(0)} km',
          ].join(' · '),
        ),
      if (target.weeklyWeightChangePercent != null ||
          target.targetWeightKg != null)
        _TargetRow(
          icon: Icons.monitor_weight_outlined,
          title: [
            if (target.weeklyWeightChangePercent != null)
              loc.planningWeightRatePerWeek(
                _signed(target.weeklyWeightChangePercent!),
              ),
            if (target.targetWeightKg != null)
              loc.planningTargetWeightValue(
                target.targetWeightKg!.toStringAsFixed(1),
              ),
          ].join(' · '),
        ),
      if (target.sleepHours != null)
        _TargetRow(
          icon: Icons.bedtime_outlined,
          title: loc.planningSleepValue(
            target.sleepHours!
                .toStringAsFixed(target.sleepHours! % 1 == 0 ? 0 : 1)
                .replaceAll('.', ','),
          ),
        ),
    ];
    return PlanningCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            rows[i],
          ],
        ],
      ),
    );
  }

  static String _macros(AppLocalizations loc, PeriodizationTarget target) =>
      loc.planningMacrosLine(
        target.proteinG?.round().toString() ?? '—',
        target.carbsG?.round().toString() ?? '—',
        target.fatG?.round().toString() ?? '—',
      );

  static String? _volume(AppLocalizations loc, PeriodizationTarget target) {
    final parts = [
      if (target.minSetsPerWeek != null || target.maxSetsPerWeek != null)
        '${target.minSetsPerWeek ?? '—'}–${target.maxSetsPerWeek ?? '—'} '
            '${loc.planningSetsShort}',
      if (target.minRpe != null || target.maxRpe != null)
        'RPE ${target.minRpe ?? '—'}–${target.maxRpe ?? '—'}',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  static String _signed(double value) {
    final sign = value > 0
        ? '+'
        : value < 0
        ? '−'
        : '';
    return '$sign${value.abs().toString().replaceAll('.', ',')}%';
  }
}

class _TargetRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;

  const _TargetRow({required this.icon, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 20, color: scheme.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontal week picker; each tile shows how the week went (a bar filled
/// by adherence) or a hollow bar for weeks still ahead.
class _WeekStrip extends StatefulWidget {
  final PeriodizationPhase phase;
  final List<PeriodizationTarget?> weeks;
  final Map<int, WeekProgress> progress;
  final int selected;
  final DateTime today;
  final ValueChanged<int> onSelect;

  const _WeekStrip({
    required this.phase,
    required this.weeks,
    required this.progress,
    required this.selected,
    required this.today,
    required this.onSelect,
  });

  @override
  State<_WeekStrip> createState() => _WeekStripState();
}

class _WeekStripState extends State<_WeekStrip> {
  static const _tileWidth = 58.0;
  late final _scroll = ScrollController(
    initialScrollOffset: ((widget.selected - 2) * _tileWidth).clamp(
      0,
      double.infinity,
    ),
  );

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = Color(widget.phase.color);
    return SizedBox(
      height: 92,
      child: ListView.builder(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        itemCount: widget.phase.totalWeeks,
        itemExtent: _tileWidth,
        itemBuilder: (context, week) {
          final start = widget.phase.startDate.add(Duration(days: 7 * week));
          final started = !start.isAfter(widget.today);
          final current =
              widget.phase.contains(widget.today) &&
              widget.phase.weekAt(widget.today) - 1 == week;
          final score = widget.progress[week]?.score;
          final label = week < widget.weeks.length
              ? widget.weeks[week]?.weekLabel
              : null;
          final selected = week == widget.selected;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Material(
              color: selected
                  ? color.withAlpha(46)
                  : scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                key: Key('phaseWeekTile$week'),
                borderRadius: BorderRadius.circular(12),
                onTap: () => widget.onSelect(week),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected ? color : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
                  child: Column(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: FractionallySizedBox(
                            heightFactor: started
                                ? (score ?? 0).clamp(0.08, 1.0)
                                : 1,
                            child: Container(
                              width: 16,
                              decoration: BoxDecoration(
                                color: started
                                    ? color.withAlpha(score == null ? 60 : 220)
                                    : Colors.transparent,
                                border: started
                                    ? null
                                    : Border.all(color: color.withAlpha(90)),
                                borderRadius: BorderRadius.circular(5),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${week + 1}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: current ? color : null,
                        ),
                      ),
                      Container(
                        width: 5,
                        height: 5,
                        margin: const EdgeInsets.only(top: 2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: label != null && label.isNotEmpty
                              ? color
                              : current
                              ? scheme.onSurface
                              : Colors.transparent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _WeekDetail extends StatelessWidget {
  final PeriodizationPhase phase;
  final int week;
  final PeriodizationTarget? target;
  final WeekProgress? progress;
  final PeriodizationCheckin? checkin;
  final DateTime today;
  final List<String> strengthLabels;
  final ValueChanged<DateTime> onReview;

  const _WeekDetail({
    required this.phase,
    required this.week,
    required this.target,
    required this.progress,
    required this.checkin,
    required this.today,
    required this.strengthLabels,
    required this.onReview,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = Color(phase.color);
    final start = phase.startDate.add(Duration(days: 7 * week));
    final end = start.add(const Duration(days: 6));
    final started = !start.isAfter(today);
    final current = !today.isBefore(start) && !today.isAfter(end);
    final progress = this.progress;
    final label = target?.weekLabel;
    return PlanningCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  loc.planningWeekTitle(
                    week + 1,
                    planningDateRange(start, end),
                  ),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (label != null && label.isNotEmpty)
                PlanningPill(
                  icon: Icons.label_outline_rounded,
                  label: label,
                  color: color,
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (progress == null)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            TemplateWeekStrip(
              week: progress.week,
              accent: color,
              highlightWeekday: current ? today.weekday : null,
              doneWeekdays: progress.doneWeekdays,
              strengthLabels: strengthLabels,
            ),
            if (started) ...[
              const Divider(height: 28),
              _PlannedDone(progress: progress),
            ],
          ],
          if (started) ...[
            const SizedBox(height: 14),
            if (checkin != null) ...[
              _CheckinSummary(checkin: checkin!),
              const SizedBox(height: 8),
            ],
            SizedBox(
              width: double.infinity,
              child: checkin == null
                  ? FilledButton.tonalIcon(
                      key: const Key('phaseWeekReview'),
                      onPressed: () => onReview(start),
                      icon: const Icon(Icons.fact_check_outlined, size: 18),
                      label: Text(loc.planningWeeklyReview),
                    )
                  : OutlinedButton.icon(
                      onPressed: () => onReview(start),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: Text(loc.planningEditReview),
                    ),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                loc.planningWeekNotStarted,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Planned vs done rows for a week that already started.
class _PlannedDone extends StatelessWidget {
  final WeekProgress progress;

  const _PlannedDone({required this.progress});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final metrics = progress.metrics;
    final rows = <Widget>[
      if (progress.plannedStrength > 0 || progress.doneStrength > 0)
        PlannedDoneRow(
          icon: Icons.fitness_center_rounded,
          label: loc.planningStrengthSessions,
          done: '${progress.doneStrength}',
          planned: progress.plannedStrength > 0
              ? '${progress.plannedStrength}'
              : null,
          ratio: progress.plannedStrength == 0
              ? null
              : progress.doneStrength / progress.plannedStrength,
        ),
      if (progress.plannedRuns > 0 || progress.doneRuns > 0)
        PlannedDoneRow(
          icon: Icons.directions_run_rounded,
          label: loc.planningRuns,
          done: progress.plannedRunKm == null
              ? '${progress.doneRuns}'
              : '${progress.doneRuns} · '
                    '${progress.doneRunKm.toStringAsFixed(1).replaceAll('.', ',')} km',
          planned: progress.plannedRuns == 0
              ? null
              : progress.plannedRunKm == null
              ? '${progress.plannedRuns}'
              : '${progress.plannedRuns} · '
                    '${progress.plannedRunKm!.toStringAsFixed(1).replaceAll('.', ',')} km',
          ratio: progress.plannedRuns == 0
              ? null
              : progress.doneRuns / progress.plannedRuns,
        ),
      if (progress.targetCalories != null || progress.averageCalories != null)
        PlannedDoneRow(
          icon: Icons.local_fire_department_outlined,
          label: loc.planningAverageKcal,
          done: planningKcal(progress.averageCalories),
          planned: progress.targetCalories == null
              ? null
              : planningKcal(progress.targetCalories),
          ratio: metrics.nutritionAdherencePercent == null
              ? null
              : metrics.nutritionAdherencePercent! / 100,
        ),
      if (progress.target?.sleepHours != null ||
          metrics.averageSleepHours != null)
        PlannedDoneRow(
          icon: Icons.bedtime_outlined,
          label: loc.planningAverageSleep,
          done: metrics.averageSleepHours == null
              ? '—'
              : '${metrics.averageSleepHours!.toStringAsFixed(1).replaceAll('.', ',')} h',
          planned: progress.target?.sleepHours == null
              ? null
              : '${progress.target!.sleepHours!.toStringAsFixed(1).replaceAll('.', ',')} h',
          ratio: metrics.sleepAdherencePercent == null
              ? null
              : metrics.sleepAdherencePercent! / 100,
        ),
      if (metrics.weightChangeKg != null)
        PlannedDoneRow(
          icon: Icons.monitor_weight_outlined,
          label: loc.planningWeightChange,
          done:
              '${metrics.weightChangeKg! > 0 ? '+' : ''}'
              '${metrics.weightChangeKg!.toStringAsFixed(1).replaceAll('.', ',')} kg',
        ),
    ];
    if (rows.isEmpty) {
      return Text(
        loc.planningNothingLogged,
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    return Column(children: rows);
  }
}

/// "Label · done / planned" with a thin bar when there is a ratio.
class PlannedDoneRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String done;
  final String? planned;
  final double? ratio;

  const PlannedDoneRow({
    super.key,
    required this.icon,
    required this.label,
    required this.done,
    this.planned,
    this.ratio,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: done,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    if (planned != null)
                      TextSpan(
                        text: ' / $planned',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                  ],
                ),
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
          if (ratio != null) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 28),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: ratio!.clamp(0, 1).toDouble(),
                  minHeight: 4,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CheckinSummary extends StatelessWidget {
  final PeriodizationCheckin checkin;

  const _CheckinSummary({required this.checkin});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final decision = switch (checkin.decision) {
      PeriodizationDecision.maintain => loc.planningDecisionMaintain,
      PeriodizationDecision.adjust => loc.planningDecisionAdjust,
      PeriodizationDecision.endPhase => loc.planningDecisionEnd,
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(90),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.fact_check_rounded,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                loc.planningReviewDone,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(decision, style: theme.textTheme.labelMedium),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            loc.planningReviewScores(
              checkin.energy,
              checkin.hunger,
              checkin.recovery,
            ),
            style: theme.textTheme.bodySmall,
          ),
          if (checkin.notes != null && checkin.notes!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              checkin.notes!,
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
