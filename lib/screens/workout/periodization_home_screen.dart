import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/periodization_phase.dart';
import 'package:workout_notes/models/periodization_plan.dart';
import 'package:workout_notes/models/periodization_target.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';

import 'periodization_calendar_screen.dart';
import 'periodization_checkin_screen.dart';
import 'periodization_comparison_screen.dart';
import 'periodization_phase_detail_screen.dart';
import 'periodization_phase_form_screen.dart';
import 'periodization_plan_form_screen.dart';
import 'periodization_plans_screen.dart';

class PeriodizationHomeScreen extends StatefulWidget {
  const PeriodizationHomeScreen({super.key});

  @override
  State<PeriodizationHomeScreen> createState() =>
      _PeriodizationHomeScreenState();
}

class _PeriodizationHomeScreenState extends State<PeriodizationHomeScreen> {
  final _repository = PeriodizationRepository();
  PeriodizationPlan? _plan;
  List<PeriodizationPhase> _phases = const [];
  PeriodizationPhase? _currentPhase;
  PeriodizationTarget? _currentTarget;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final plan = await _repository.getActivePlan();
    if (plan == null) {
      if (mounted) {
        setState(() {
          _plan = null;
          _phases = const [];
          _currentPhase = null;
          _currentTarget = null;
          _loading = false;
        });
      }
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
    final target = current == null
        ? null
        : await _repository.getEffectiveTarget(current.id);
    if (!mounted) return;
    setState(() {
      _plan = plan;
      _phases = phases;
      _currentPhase = current;
      _currentTarget = target;
      _loading = false;
    });
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

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.periodizationTitle),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: loc.periodizationCalendar,
            onPressed: _plan == null
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PeriodizationCalendarScreen(plan: _plan!),
                    ),
                  ),
            icon: const Icon(Icons.calendar_month_outlined),
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              switch (value) {
                case 'plans':
                  await _openPlans();
                case 'compare':
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PeriodizationComparisonScreen(),
                    ),
                  );
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'plans',
                child: Text(loc.periodizationHistory),
              ),
              PopupMenuItem(
                value: 'compare',
                child: Text(loc.periodizationCompare),
              ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _plan == null
          ? _EmptyPlan(onCreate: _createPlan, onHistory: _openPlans)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                children: [
                  _PlanHero(
                    plan: _plan!,
                    phases: _phases,
                  ).animate().fadeIn(duration: 250.ms).slideY(begin: -.03),
                  const SizedBox(height: 18),
                  _sectionTitle(loc.periodizationNow),
                  const SizedBox(height: 8),
                  if (_currentPhase == null)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.pause_circle_outline),
                        title: Text(loc.periodizationNoPhaseToday),
                      ),
                    )
                  else
                    _CurrentPhaseCard(
                      phase: _currentPhase!,
                      target: _currentTarget,
                      onTap: () => _openPhase(_currentPhase!),
                      onCheckin: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PeriodizationCheckinScreen(
                              phase: _currentPhase!,
                            ),
                          ),
                        );
                        await _load();
                      },
                    ).animate().fadeIn(delay: 100.ms).slideY(begin: .04),
                  const SizedBox(height: 22),
                  _sectionTitle(loc.periodizationNextPhases),
                  const SizedBox(height: 6),
                  ..._upcoming.map(
                    (phase) => Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        onTap: () => _openPhase(phase),
                        leading: Container(
                          width: 7,
                          height: 42,
                          decoration: BoxDecoration(
                            color: Color(phase.color),
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                        title: Text(phase.name),
                        subtitle: Text(
                          '${DateFormat.MMMd(Intl.defaultLocale).format(phase.startDate)} – ${DateFormat.MMMd(Intl.defaultLocale).format(phase.endDate)} · ${phase.totalWeeks}w',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                      ),
                    ),
                  ),
                  if (_upcoming.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(loc.periodizationNoUpcoming),
                    ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _addPhase,
                    icon: const Icon(Icons.add),
                    label: Text(loc.periodizationAddPhase),
                  ),
                ],
              ),
            ),
    );
  }

  List<PeriodizationPhase> get _upcoming {
    final today = DateTime.now();
    return _phases.where((phase) => phase.startDate.isAfter(today)).toList();
  }

  Widget _sectionTitle(String text) => Text(
    text,
    style: Theme.of(context).textTheme.labelLarge?.copyWith(
      letterSpacing: 1,
      fontWeight: FontWeight.bold,
    ),
  );
}

class _EmptyPlan extends StatelessWidget {
  final VoidCallback onCreate;
  final VoidCallback onHistory;

  const _EmptyPlan({required this.onCreate, required this.onHistory});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.view_timeline_outlined,
              size: 76,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 22),
            Text(
              loc.periodizationNoActiveTitle,
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              loc.periodizationNoActiveSubtitle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: Text(loc.periodizationCreatePlan),
            ),
            TextButton(
              onPressed: onHistory,
              child: Text(loc.periodizationHistory),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanHero extends StatelessWidget {
  final PeriodizationPlan plan;
  final List<PeriodizationPhase> phases;

  const _PlanHero({required this.plan, required this.phases});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final now = DateTime.now();
    final totalWeeks = (plan.totalDays / 7).ceil();
    final currentWeek = now.isBefore(plan.startDate)
        ? 0
        : (now.difference(plan.startDate).inDays ~/ 7 + 1).clamp(1, totalWeeks);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withAlpha(95),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withAlpha(80),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${loc.periodizationActivePlan} · ${plan.startDate.year}',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 5),
          Text(
            plan.name,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Row(
              children: phases.map((phase) {
                return Expanded(
                  flex: phase.totalDays,
                  child: Container(
                    height: 11,
                    margin: const EdgeInsets.only(right: 2),
                    color: Color(phase.color),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(loc.periodizationWeekOf(currentWeek, totalWeeks)),
              ),
              Text(
                '${(plan.progressAt(now) * 100).round()}%',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CurrentPhaseCard extends StatelessWidget {
  final PeriodizationPhase phase;
  final PeriodizationTarget? target;
  final VoidCallback onTap;
  final VoidCallback onCheckin;

  const _CurrentPhaseCard({
    required this.phase,
    required this.target,
    required this.onTap,
    required this.onCheckin,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final now = DateTime.now();
    final targetItems = <(String, String)>[];
    if (target?.calories != null) {
      targetItems.add((
        '${target!.calories!.round()}',
        loc.periodizationCaloriesPerDay,
      ));
    }
    if (target?.proteinG != null) {
      targetItems.add((
        '${target!.proteinG!.round()} g',
        loc.periodizationProteinG,
      ));
    }
    if (target?.workoutsPerWeek != null) {
      targetItems.add((
        '${target!.workoutsPerWeek}×',
        loc.periodizationWorkoutsPerWeek,
      ));
    }
    return Card(
      margin: EdgeInsets.zero,
      color: Color(phase.color).withAlpha(25),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Color(phase.color).withAlpha(95)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: Color(phase.color).withAlpha(60),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.trending_down, color: Color(phase.color)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${(phase.templateKey ?? phase.name).toUpperCase()} · ${loc.periodizationPhaseWeek(phase.weekAt(now), phase.totalWeeks)}',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        Text(
                          phase.intent ?? phase.name,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              if (targetItems.isNotEmpty) ...[
                const SizedBox(height: 16),
                Row(
                  children: targetItems
                      .take(3)
                      .map(
                        (item) => Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.$1,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                item.$2,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
              const SizedBox(height: 14),
              LinearProgressIndicator(
                value: phase.progressAt(now),
                color: Color(phase.color),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onCheckin,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: Text(loc.periodizationWeeklyCheckin),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
