import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/periodization_checkin.dart';
import 'package:workout_notes/models/periodization_metrics.dart';
import 'package:workout_notes/models/periodization_phase.dart';
import 'package:workout_notes/models/periodization_plan.dart';
import 'package:workout_notes/models/periodization_target.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';

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
  List<PeriodizationTarget> _targetHistory = const [];
  List<PeriodizationCheckin> _checkins = const [];
  List<Map<String, dynamic>> _routineLinks = const [];
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
      _repository.getRoutineLinks(_phase.id),
    ]);
    if (!mounted) return;
    setState(() {
      _target = results[0] as PeriodizationTarget?;
      _metrics = results[1] as PeriodizationMetrics;
      _targetHistory = results[2] as List<PeriodizationTarget>;
      _checkins = results[3] as List<PeriodizationCheckin>;
      _routineLinks = results[4] as List<Map<String, dynamic>>;
      _loading = false;
    });
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
    final result = await Navigator.push<PeriodizationDecision>(
      context,
      MaterialPageRoute(
        builder: (_) => PeriodizationCheckinScreen(phase: _phase),
      ),
    );
    if (result != null) await _load();
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
        title: Text(_phase.name),
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
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${loc.periodizationPhaseProgress} · ${(progress * 100).round()}%',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (_target != null) _TargetOverview(target: _target!),
                  const SizedBox(height: 22),
                  _SectionTitle(loc.periodizationPlannedActual),
                  const SizedBox(height: 10),
                  _MetricsGrid(metrics: _metrics!),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _showReport,
                    icon: const Icon(Icons.assessment_outlined),
                    label: Text(loc.periodizationFinalReport),
                  ),
                  const SizedBox(height: 22),
                  _SectionTitle(loc.periodizationRoutineSchedule),
                  if (_routineLinks.isEmpty)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.repeat),
                      title: Text(loc.periodizationNoRoutine),
                    )
                  else
                    ..._routineLinks.map(
                      (link) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.repeat),
                        title: Text(link['routine_name'] as String),
                        subtitle: Text(
                          '${link['starts_on']} – ${link['ends_on']}',
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  _SectionTitle(loc.periodizationCheckins),
                  ..._checkins.map(
                    (checkin) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.fact_check_outlined),
                      title: Text(
                        DateFormat.yMMMd(
                          Intl.defaultLocale,
                        ).format(checkin.weekStart),
                      ),
                      subtitle: Text(_decisionLabel(loc, checkin.decision)),
                      trailing: Text('${checkin.energy}/5'),
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
                  FilledButton.icon(
                    onPressed: _checkin,
                    icon: const Icon(Icons.add_task),
                    label: Text(loc.periodizationWeeklyCheckin),
                  ),
                  const SizedBox(height: 22),
                  _SectionTitle(loc.periodizationTargetHistory),
                  ..._targetHistory.map(
                    (target) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(child: Text('v${target.version}')),
                      title: Text(
                        DateFormat.yMMMd(
                          Intl.defaultLocale,
                        ).format(target.validFrom),
                      ),
                      subtitle: Text(_targetSummary(target)),
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

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.bold,
      letterSpacing: 1,
    ),
  );
}

class _TargetOverview extends StatelessWidget {
  final PeriodizationTarget target;
  const _TargetOverview({required this.target});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final items = <(IconData, String, String)>[];
    if (target.calories != null) {
      items.add((
        Icons.local_fire_department_outlined,
        '${target.calories!.round()}',
        loc.periodizationCaloriesPerDay,
      ));
    }
    if (target.proteinG != null) {
      items.add((
        Icons.restaurant_outlined,
        '${target.proteinG!.round()} g',
        loc.periodizationProteinG,
      ));
    }
    if (target.workoutsPerWeek != null) {
      items.add((
        Icons.fitness_center,
        '${target.workoutsPerWeek}×',
        loc.periodizationWorkoutsPerWeek,
      ));
    }
    if (target.sleepHours != null) {
      items.add((
        Icons.nightlight_outlined,
        '${target.sleepHours} h',
        loc.periodizationSleepHours,
      ));
    }
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: items
          .map(
            (item) => SizedBox(
              width: (MediaQuery.sizeOf(context).width - 42) / 2,
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(item.$1),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.$2,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              item.$3,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
          .toList(),
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
        loc.periodizationAdherence,
        metrics.nutritionAdherencePercent == null
            ? '—'
            : '${metrics.nutritionAdherencePercent!.round()}%',
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
      itemBuilder: (context, index) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
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
      ),
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
    final pt = Localizations.localeOf(context).languageCode == 'pt';
    final averageEnergy = checkins.isEmpty
        ? null
        : checkins.map((item) => item.energy).reduce((a, b) => a + b) /
              checkins.length;
    final sentences = <String>[
      pt
          ? '${metrics.workoutCount} treinos e ${metrics.completedSets} séries concluídas foram registrados no período.'
          : '${metrics.workoutCount} workouts and ${metrics.completedSets} completed sets were logged in the period.',
      if (metrics.nutritionDaysLogged > 0)
        pt
            ? 'A alimentação foi registrada em ${metrics.nutritionDaysLogged} dias, com média de ${metrics.averageCalories?.round() ?? 0} kcal.'
            : 'Nutrition was logged on ${metrics.nutritionDaysLogged} days, averaging ${metrics.averageCalories?.round() ?? 0} kcal.',
      if (metrics.weightChangeKg != null)
        pt
            ? 'A mudança de peso observada foi ${metrics.weightChangeKg!.toStringAsFixed(1)} kg.'
            : 'Observed weight change was ${metrics.weightChangeKg!.toStringAsFixed(1)} kg.',
      if (averageEnergy != null)
        pt
            ? 'Energia média nas revisões: ${averageEnergy.toStringAsFixed(1)}/5.'
            : 'Average energy in reviews: ${averageEnergy.toStringAsFixed(1)}/5.',
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
