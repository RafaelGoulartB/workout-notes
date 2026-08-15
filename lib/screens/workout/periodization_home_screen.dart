import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/periodization_phase.dart';
import 'package:workout_notes/models/periodization_plan.dart';
import 'package:workout_notes/models/periodization_target.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';
import 'package:workout_notes/widgets/periodization/periodization_ui.dart';

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
      if (!mounted) return;
      setState(() {
        _plan = null;
        _phases = const [];
        _currentPhase = null;
        _currentTarget = null;
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

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          loc.periodizationTitle,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: false,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: loc.periodizationCalendar,
            onPressed: _plan == null ? null : _openCalendar,
            icon: const Icon(Icons.calendar_month_outlined),
          ),
          IconButton(
            tooltip: loc.periodizationHistory,
            onPressed: _openPlans,
            icon: const Icon(Icons.folder_open_outlined),
          ),
        ],
      ),
      body: _loading
          ? const _HomeSkeleton()
          : _plan == null
          ? PeriodizationEmptyState(
              icon: Icons.route_outlined,
              title: loc.periodizationNoActiveTitle,
              subtitle: loc.periodizationNoActiveSubtitle,
              primaryLabel: loc.periodizationCreatePlan,
              onPrimary: _createPlan,
              secondaryLabel: loc.periodizationHistory,
              onSecondary: _openPlans,
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    sliver: SliverToBoxAdapter(
                      child: _PlanHero(
                        plan: _plan!,
                        phases: _phases,
                        onTap: _openPlans,
                      ).animate().fadeIn(duration: 260.ms).slideY(begin: -.025),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    sliver: SliverToBoxAdapter(
                      child: _QuickActions(
                        onCalendar: _openCalendar,
                        onPlans: _openPlans,
                        onCompare: _openComparison,
                      ).animate().fadeIn(delay: 80.ms, duration: 240.ms),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
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
                                  onTap: () => _openPhase(_currentPhase!),
                                  onCheckin: () async {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            PeriodizationCheckinScreen(
                                              phase: _currentPhase!,
                                            ),
                                      ),
                                    );
                                    await _load();
                                  },
                                )
                                .animate()
                                .fadeIn(delay: 120.ms)
                                .slideY(begin: .03),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
                    sliver: SliverToBoxAdapter(
                      child: PeriodizationSectionHeader(
                        title: loc.periodizationNextPhases,
                        icon: Icons.route_outlined,
                        actionLabel: loc.periodizationAddPhase,
                        onAction: _addPhase,
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverToBoxAdapter(
                      child: PeriodizationSurface(
                        child: PeriodizationPhaseTimeline(
                          phases: _phases,
                          referenceDate: DateTime.now(),
                          selectedPhaseId: _currentPhase?.id,
                          onPhaseTap: _openPhase,
                        ),
                      ),
                    ),
                  ),
                  if (_upcoming.isNotEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                      sliver: SliverList.separated(
                        itemCount: _upcoming.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final phase = _upcoming[index];
                          return _UpcomingPhaseCard(
                            phase: phase,
                            onTap: () => _openPhase(phase),
                          );
                        },
                      ),
                    ),
                  if (_upcoming.isEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      sliver: SliverToBoxAdapter(
                        child: Text(
                          loc.periodizationNoUpcoming,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 110)),
                ],
              ),
            ),
    );
  }

  List<PeriodizationPhase> get _upcoming {
    final today = DateTime.now();
    return _phases.where((phase) => phase.startDate.isAfter(today)).toList();
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
    final firstAccent = activePhase == null
        ? const Color(0xFFF0A33B)
        : Color(activePhase.color);
    final endDate = DateFormat.MMMd(Intl.defaultLocale).format(plan.endDate);

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
              color: const Color(0xFF1F272B),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withAlpha(10)),
            ),
            child: CustomPaint(
              painter: _PlanHeroBackgroundPainter(
                color: Theme.of(context).colorScheme.primary,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 16, 17),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.route_rounded,
                          size: 19,
                          color: Color(0xFF7DD3F0),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            loc.periodizationPlanOverview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: const Color(0xFFE6EAED),
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: Color(0xFFC7CDD0),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Text(
                            plan.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  color: const Color(0xFFF2F4F5),
                                  fontWeight: FontWeight.w900,
                                  height: 1.06,
                                  letterSpacing: -.4,
                                ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            '${(progress * 100).round()}%',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: const Color(0xFF7DD3F0),
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      loc.periodizationWeekOf(currentWeek, totalWeeks),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFFB9C0C4),
                      ),
                    ),
                    const SizedBox(height: 13),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 8,
                        color: const Color(0xFF7DD3F0),
                        backgroundColor: const Color(0xFF354047),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _PlanHeroMetric(
                          value: '${phases.length}',
                          label: loc.periodizationPhases,
                          accent: firstAccent,
                          fill: phases.isEmpty ? 0 : 1,
                        ),
                        const SizedBox(width: 14),
                        _PlanHeroMetric(
                          value: '$currentWeek/$totalWeeks',
                          label: loc.periodizationCurrentWeek,
                          accent: const Color(0xFF36B7AA),
                          fill: totalWeeks == 0 ? 0 : currentWeek / totalWeeks,
                        ),
                        const SizedBox(width: 14),
                        _PlanHeroMetric(
                          value: endDate,
                          label: loc.periodizationPlanEnd,
                          accent: const Color(0xFFB25FC7),
                          fill: progress,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlanHeroMetric extends StatelessWidget {
  final String value;
  final String label;
  final Color accent;
  final double fill;

  const _PlanHeroMetric({
    required this.value,
    required this.label,
    required this.accent,
    required this.fill,
  });

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
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: fill.clamp(0, 1),
            minHeight: 3,
            color: accent,
            backgroundColor: accent.withAlpha(28),
          ),
        ),
      ],
    ),
  );
}

class _PlanHeroBackgroundPainter extends CustomPainter {
  final Color color;

  const _PlanHeroBackgroundPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final faint = Paint()..color = color.withAlpha(9);
    final softer = Paint()..color = color.withAlpha(5);
    canvas.drawPath(
      Path()
        ..moveTo(size.width * .43, 0)
        ..lineTo(size.width * .66, 0)
        ..lineTo(size.width * .28, size.height)
        ..lineTo(size.width * .06, size.height)
        ..close(),
      faint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(size.width * .82, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width * .68, size.height)
        ..lineTo(size.width * .48, size.height)
        ..close(),
      softer,
    );
  }

  @override
  bool shouldRepaint(covariant _PlanHeroBackgroundPainter oldDelegate) =>
      oldDelegate.color != color;
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
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
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
    final theme = Theme.of(context);
    final now = DateTime.now();
    final color = Color(phase.color);
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
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: phase.progressAt(now),
              minHeight: 7,
              color: color,
              backgroundColor: color.withAlpha(26),
            ),
          ),
          if (targetItems.isNotEmpty) ...[
            const SizedBox(height: 14),
            SizedBox(
              height: 108,
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
          ],
          const SizedBox(height: 12),
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

class _UpcomingPhaseCard extends StatelessWidget {
  final PeriodizationPhase phase;
  final VoidCallback onTap;

  const _UpcomingPhaseCard({required this.phase, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = Color(phase.color);
    final range =
        '${DateFormat.MMMd(Intl.defaultLocale).format(phase.startDate)} – ${DateFormat.MMMd(Intl.defaultLocale).format(phase.endDate)}';
    return PeriodizationSurface(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      accentColor: color,
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 8,
            height: 48,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  phase.name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$range  ·  ${phase.totalWeeks} sem.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
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
