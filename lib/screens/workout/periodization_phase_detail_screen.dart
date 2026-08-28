import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/periodization_checkin.dart';
import 'package:workout_notes/models/periodization_metrics.dart';
import 'package:workout_notes/models/periodization_phase.dart';
import 'package:workout_notes/models/periodization_plan.dart';
import 'package:workout_notes/models/periodization_projection.dart';
import 'package:workout_notes/models/periodization_target.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';
import 'package:workout_notes/repositories/routine_repository.dart';
import 'package:workout_notes/widgets/periodization/periodization_ui.dart';

import 'periodization_checkin_flow.dart';
import 'periodization_checkin_screen.dart';
import 'periodization_phase_form_screen.dart';

class PeriodizationPhaseDetailScreen extends StatefulWidget {
  final PeriodizationPlan plan;
  final PeriodizationPhase phase;

  const PeriodizationPhaseDetailScreen({
    super.key,
    required this.plan,
    required this.phase,
  });

  @override
  State<PeriodizationPhaseDetailScreen> createState() =>
      _PeriodizationPhaseDetailScreenState();
}

class _PeriodizationPhaseDetailScreenState
    extends State<PeriodizationPhaseDetailScreen> {
  final _repository = PeriodizationRepository();
  late PeriodizationPhase _phase;
  PeriodizationTarget? _target;
  PeriodizationMetrics? _metrics;
  PeriodizationProjection? _projection;
  List<PeriodizationTarget> _targetHistory = const [];
  List<PeriodizationCheckin> _checkins = const [];

  /// Per-week routine schedule resolved from the target history:
  /// (routine name, week start, week end) entries ordered by date.
  List<({String routineName, DateTime startsOn, DateTime endsOn})>
  _routineSchedule = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _phase = widget.phase;
    _load();
  }

  Future<void> _load() async {
    final refreshed = await _repository.getPhase(_phase.id);
    if (refreshed == null) {
      if (mounted) Navigator.pop(context, true);
      return;
    }
    _phase = refreshed;
    final results = await Future.wait([
      _repository.getEffectiveTarget(_phase.id),
      _repository.getPhaseMetrics(_phase),
      _repository.getTargetHistory(_phase.id),
      _repository.getCheckins(_phase.id),
      RoutineRepository().getRoutines(),
    ]);
    final metrics = results[1] as PeriodizationMetrics;
    final projection = await _repository.getPhaseProjection(
      _phase,
      phaseMetrics: metrics,
    );
    if (!mounted) return;
    final history = results[2] as List<PeriodizationTarget>;
    final routineById = {
      for (final routine in results[4] as List<Map<String, dynamic>>)
        routine['id'] as String: routine['name'] as String,
    };
    setState(() {
      _target = results[0] as PeriodizationTarget?;
      _metrics = metrics;
      _targetHistory = history;
      _checkins = results[3] as List<PeriodizationCheckin>;
      _routineSchedule = _buildRoutineSchedule(history, routineById);
      _projection = projection;
      _loading = false;
    });
  }

  List<({String routineName, DateTime startsOn, DateTime endsOn})>
  _buildRoutineSchedule(
    List<PeriodizationTarget> history,
    Map<String, String> routineById,
  ) {
    final ordered = [...history]
      ..sort((a, b) => a.validFrom.compareTo(b.validFrom));
    final schedule =
        <({String routineName, DateTime startsOn, DateTime endsOn})>[];
    DateTime dayOnly(DateTime value) =>
        DateTime(value.year, value.month, value.day);
    for (var i = 0; i < ordered.length; i++) {
      final target = ordered[i];
      final startsOn = dayOnly(target.validFrom);
      final endsOn = i + 1 < ordered.length
          ? dayOnly(ordered[i + 1].validFrom).subtract(const Duration(days: 1))
          : dayOnly(_phase.endDate);
      for (final routineId in target.routineIds) {
        final routineName = routineById[routineId];
        if (routineName == null) continue;
        schedule.add((
          routineName: routineName,
          startsOn: startsOn,
          endsOn: endsOn,
        ));
      }
    }
    return schedule;
  }

  Future<void> _edit() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PeriodizationPhaseFormScreen(plan: widget.plan, phase: _phase),
      ),
    );
    if (changed == true) {
      setState(() => _loading = true);
      await _load();
    }
  }

  Future<void> _checkin() async {
    final changed = await PeriodizationCheckinFlow.run(
      context: context,
      plan: widget.plan,
      phase: _phase,
    );
    if (changed && mounted) await _load();
  }

  Future<void> _delete() async {
    final loc = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(loc.periodizationDeletePhaseTitle),
        content: Text(loc.commonActionCannotBeUndone),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(loc.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(loc.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repository.deletePhase(_phase.id);
    if (mounted) Navigator.pop(context, true);
  }

  void _showReport() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .82,
        maxChildSize: .95,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
          children: [
            Text(
              AppLocalizations.of(context)!.periodizationFinalReport,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(_phase.name),
            const SizedBox(height: 20),
            _MetricsGrid(metrics: _metrics!),
            const SizedBox(height: 20),
            _ReportNarrative(
              metrics: _metrics!,
              target: _target,
              checkins: _checkins,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final now = DateTime.now();
    final progress = _phase.progressAt(now);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _phase.name,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(onPressed: _edit, icon: const Icon(Icons.edit_outlined)),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'delete') _delete();
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'delete', child: Text(loc.commonDelete)),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Color(_phase.color).withAlpha(35),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Color(_phase.color).withAlpha(120),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${(_phase.templateKey ?? _phase.name).toUpperCase()} · ${loc.periodizationPhaseWeek(_phase.weekAt(now), _phase.totalWeeks)}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: Color(_phase.color),
                            fontWeight: FontWeight.w800,
                            letterSpacing: .8,
                          ),
                        ),
                        if (_phase.intent != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            _phase.intent!,
                            style: theme.textTheme.titleLarge,
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          '${DateFormat.yMMMd(Intl.defaultLocale).format(_phase.startDate)} – ${DateFormat.yMMMd(Intl.defaultLocale).format(_phase.endDate)}',
                        ),
                        const SizedBox(height: 16),
                        LinearProgressIndicator(
                          value: progress,
                          color: Color(_phase.color),
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${loc.periodizationPhaseProgress} · ${(progress * 100).round()}%',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _checkin,
                          icon: const Icon(Icons.fact_check_outlined),
                          label: Text(loc.periodizationWeeklyCheckin),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton.filledTonal(
                        onPressed: _edit,
                        tooltip: loc.periodizationEditPhase,
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  PeriodizationSectionHeader(
                    title: loc.periodizationPlannedActual,
                    icon: Icons.analytics_outlined,
                  ),
                  _TargetActualGrid(target: _target, metrics: _metrics!),
                  if (_projection?.hasAnyEstimate == true) ...[
                    const SizedBox(height: 22),
                    PeriodizationSectionHeader(
                      title: loc.periodizationProjections,
                      icon: Icons.auto_graph_rounded,
                    ),
                    _ProjectionCard(projection: _projection!, phase: _phase),
                  ],
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _showReport,
                    icon: const Icon(Icons.assessment_outlined),
                    label: Text(loc.periodizationFinalReport),
                  ),
                  const SizedBox(height: 22),
                  PeriodizationSectionHeader(
                    title: loc.periodizationRoutineSchedule,
                    icon: Icons.repeat_rounded,
                  ),
                  if (_routineSchedule.isEmpty)
                    PeriodizationSurface(
                      child: Row(
                        children: [
                          const Icon(Icons.link_off_rounded),
                          const SizedBox(width: 12),
                          Text(loc.periodizationNoRoutine),
                        ],
                      ),
                    )
                  else
                    ..._routineSchedule.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: PeriodizationSurface(
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.repeat),
                            title: Text(entry.routineName),
                            subtitle: Text(
                              '${DateFormat.MMMd(Intl.defaultLocale).format(entry.startsOn)}'
                              ' – '
                              '${DateFormat.MMMd(Intl.defaultLocale).format(entry.endsOn)}',
                            ),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  PeriodizationSectionHeader(
                    title: loc.periodizationCheckins,
                    icon: Icons.fact_check_outlined,
                  ),
                  if (_checkins.isEmpty)
                    PeriodizationSurface(
                      child: Row(
                        children: [
                          const Icon(Icons.event_note_outlined),
                          const SizedBox(width: 12),
                          Expanded(child: Text(loc.periodizationNoCheckins)),
                        ],
                      ),
                    ),
                  ..._checkins.map(
                    (checkin) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: PeriodizationSurface(
                        padding: EdgeInsets.zero,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Color(_phase.color).withAlpha(25),
                            foregroundColor: Color(_phase.color),
                            child: const Icon(Icons.fact_check_outlined),
                          ),
                          title: Text(
                            DateFormat.yMMMd(
                              Intl.defaultLocale,
                            ).format(checkin.weekStart),
                          ),
                          subtitle: Text(_decisionLabel(loc, checkin.decision)),
                          trailing: PeriodizationStatusPill(
                            label: '${checkin.energy}/5',
                            icon: Icons.bolt_rounded,
                            color: Color(_phase.color),
                          ),
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PeriodizationCheckinScreen(
                                  phase: _phase,
                                  weekStart: checkin.weekStart,
                                ),
                              ),
                            );
                            await _load();
                          },
                        ),
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _checkin,
                    icon: const Icon(Icons.add_task),
                    label: Text(loc.periodizationWeeklyCheckin),
                  ),
                  const SizedBox(height: 22),
                  PeriodizationSectionHeader(
                    title: loc.periodizationTargetHistory,
                    icon: Icons.history_rounded,
                  ),
                  ..._targetHistory.map(
                    (target) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: PeriodizationSurface(
                        padding: EdgeInsets.zero,
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Text('v${target.version}'),
                          ),
                          title: Text(
                            DateFormat.yMMMd(
                              Intl.defaultLocale,
                            ).format(target.validFrom),
                          ),
                          subtitle: Text(_targetSummary(target)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  String _decisionLabel(AppLocalizations loc, PeriodizationDecision decision) =>
      switch (decision) {
        PeriodizationDecision.adjust => loc.periodizationAdjust,
        PeriodizationDecision.endPhase => loc.periodizationEndPhase,
        _ => loc.periodizationMaintain,
      };

  String _targetSummary(PeriodizationTarget target) {
    final parts = <String>[];
    if (target.calories != null) parts.add('${target.calories!.round()} kcal');
    if (target.proteinG != null) parts.add('${target.proteinG!.round()}g P');
    if (target.workoutsPerWeek != null) {
      parts.add('${target.workoutsPerWeek}×/week');
    }
    if (target.targetWeightKg != null) parts.add('${target.targetWeightKg} kg');
    return parts.isEmpty ? '—' : parts.join(' · ');
  }
}

class _TargetActualGrid extends StatelessWidget {
  final PeriodizationTarget? target;
  final PeriodizationMetrics metrics;

  const _TargetActualGrid({required this.target, required this.metrics});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final phaseTarget = target;
    final actualWorkoutsPerWeek = metrics.elapsedDays == 0
        ? null
        : metrics.workoutCount / metrics.elapsedDays * 7;
    final items = [
      (
        Icons.local_fire_department_outlined,
        loc.periodizationCaloriesPerDay,
        phaseTarget?.calories == null
            ? '—'
            : '${phaseTarget!.calories!.round()} kcal',
        metrics.averageCalories == null
            ? '—'
            : '${metrics.averageCalories!.round()} kcal',
      ),
      (
        Icons.restaurant_outlined,
        loc.periodizationProteinG,
        phaseTarget?.proteinG == null
            ? '—'
            : '${phaseTarget!.proteinG!.round()} g',
        metrics.averageProteinG == null
            ? '—'
            : '${metrics.averageProteinG!.round()} g',
      ),
      (
        Icons.fitness_center,
        loc.periodizationWorkoutsPerWeek,
        phaseTarget?.workoutsPerWeek == null
            ? '—'
            : '${phaseTarget!.workoutsPerWeek}×',
        actualWorkoutsPerWeek == null
            ? '—'
            : '${actualWorkoutsPerWeek.toStringAsFixed(1)}×',
      ),
      (
        Icons.nightlight_outlined,
        loc.periodizationSleepHours,
        phaseTarget?.sleepHours == null
            ? '—'
            : '${phaseTarget!.sleepHours!.toStringAsFixed(1)} h',
        metrics.averageSleepHours == null
            ? '—'
            : '${metrics.averageSleepHours!.toStringAsFixed(1)} h',
      ),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.55,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return PeriodizationSurface(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(item.$1, size: 19),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                '${loc.periodizationTargetLabel}: ${item.$3}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                '${loc.periodizationActualLabel}: ${item.$4}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MetricsGrid extends StatelessWidget {
  final PeriodizationMetrics metrics;
  const _MetricsGrid({required this.metrics});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final items = [
      (
        loc.periodizationWorkouts,
        metrics.plannedWorkouts == null
            ? '${metrics.workoutCount}'
            : '${metrics.workoutCount}/${metrics.plannedWorkouts}',
      ),
      (
        loc.periodizationSets,
        metrics.plannedSetsMinimum == null
            ? '${metrics.completedSets}'
            : '${metrics.completedSets}/${metrics.plannedSetsMinimum}+',
      ),
      (
        loc.periodizationAverageCalories,
        metrics.averageCalories == null
            ? '—'
            : '${metrics.averageCalories!.round()}',
      ),
      (
        loc.periodizationNutritionAdherence,
        metrics.nutritionAdherencePercent == null
            ? '—'
            : '${metrics.nutritionAdherencePercent!.round()}%',
      ),
      (
        loc.periodizationCoverage,
        metrics.nutritionCoveragePercent == null
            ? '—'
            : '${metrics.nutritionCoveragePercent!.round()}%',
      ),
      (
        loc.periodizationSetAdherence,
        metrics.setAdherencePercent == null
            ? '—'
            : '${metrics.setAdherencePercent!.round()}%',
      ),
      (
        loc.periodizationRpeAdherence,
        metrics.rpeAdherencePercent == null
            ? '—'
            : '${metrics.rpeAdherencePercent!.round()}%',
      ),
      (
        loc.periodizationSleepAdherence,
        metrics.sleepAdherencePercent == null
            ? '—'
            : '${metrics.sleepAdherencePercent!.round()}%',
      ),
      (
        loc.periodizationWeightAdherence,
        metrics.weightAdherencePercent == null
            ? '—'
            : '${metrics.weightAdherencePercent!.round()}%',
      ),
      (
        loc.periodizationWeightChange,
        metrics.weightChangeKg == null
            ? '—'
            : '${metrics.weightChangeKg! >= 0 ? '+' : ''}${metrics.weightChangeKg!.toStringAsFixed(1)} kg',
      ),
      (
        loc.periodizationAverageSleep,
        metrics.averageSleepHours == null
            ? '—'
            : '${metrics.averageSleepHours!.toStringAsFixed(1)} h',
      ),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.9,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) => PeriodizationSurface(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              items[index].$2,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(
              items[index].$1,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectionCard extends StatelessWidget {
  final PeriodizationProjection projection;
  final PeriodizationPhase phase;

  const _ProjectionCard({required this.projection, required this.phase});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final color = Color(phase.color);
    final basis =
        projection.weightBasis ==
            PeriodizationWeightProjectionBasis.observedTrend
        ? loc.periodizationProjectionObservedTrend
        : loc.periodizationProjectionPlannedRate;
    final rate = projection.weeklyWeightRatePercent;
    final items = <Widget>[];

    if (projection.expectedEndWeightKg case final weight?) {
      items.add(
        _ProjectionRow(
          icon: Icons.monitor_weight_outlined,
          color: color,
          label: loc.periodizationExpectedEndWeight,
          value: '${weight.toStringAsFixed(1)} kg',
          detail: rate == null
              ? basis
              : loc.periodizationProjectionWeightBasis(
                  basis,
                  '${rate >= 0 ? '+' : ''}${rate.toStringAsFixed(2)}%',
                ),
        ),
      );
    }
    if (projection.plannedVolume case final volume?) {
      final count = projection.plannedSets ?? projection.plannedWorkouts;
      items.add(
        _ProjectionRow(
          icon: Icons.fitness_center_rounded,
          color: color,
          label: loc.periodizationPlannedVolume,
          value: '${_compact(volume)} kg',
          detail: count == null
              ? loc.periodizationProjectionCurrentAverage
              : projection.plannedSets != null
              ? loc.periodizationProjectionPlannedSets(count)
              : loc.periodizationProjectionPlannedWorkouts(count),
        ),
      );
    }
    if (projection.estimatedGoalDate case final date?) {
      items.add(
        _ProjectionRow(
          icon: Icons.flag_outlined,
          color: color,
          label: loc.periodizationEstimatedGoalDate,
          value: DateFormat.yMMMd(Intl.defaultLocale).format(date),
          detail: loc.periodizationProjectionGoalBasis(basis),
        ),
      );
    }

    return PeriodizationSurface(
      accentColor: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < items.length; index++) ...[
            if (index > 0) const Divider(height: 24),
            items[index],
          ],
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  loc.periodizationProjectionDisclaimer,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _compact(double value) {
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}k';
    return value.toStringAsFixed(0);
  }
}

class _ProjectionRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String detail;

  const _ProjectionRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color.withAlpha(24),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelMedium),
              Text(
                value,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                detail,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReportNarrative extends StatelessWidget {
  final PeriodizationMetrics metrics;
  final PeriodizationTarget? target;
  final List<PeriodizationCheckin> checkins;

  const _ReportNarrative({
    required this.metrics,
    required this.target,
    required this.checkins,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final averageEnergy = checkins.isEmpty
        ? null
        : checkins.map((item) => item.energy).reduce((a, b) => a + b) /
              checkins.length;
    final sentences = <String>[
      loc.periodizationReportTrainingNarrative(
        metrics.workoutCount,
        metrics.completedSets,
      ),
      if (metrics.nutritionDaysLogged > 0)
        loc.periodizationReportNutritionNarrative(
          metrics.nutritionDaysLogged,
          metrics.averageCalories?.round() ?? 0,
        ),
      if (metrics.weightChangeKg != null)
        loc.periodizationReportWeightNarrative(
          metrics.weightChangeKg!.toStringAsFixed(1),
        ),
      if (averageEnergy != null)
        loc.periodizationReportEnergyNarrative(
          averageEnergy.toStringAsFixed(1),
        ),
    ];
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: sentences
              .map(
                (text) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(text),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}
