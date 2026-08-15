import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/periodization_metrics.dart';
import 'package:workout_notes/models/periodization_plan.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';
import 'package:workout_notes/widgets/periodization/periodization_ui.dart';

class PeriodizationComparisonScreen extends StatefulWidget {
  const PeriodizationComparisonScreen({super.key});

  @override
  State<PeriodizationComparisonScreen> createState() =>
      _PeriodizationComparisonScreenState();
}

class _PeriodizationComparisonScreenState
    extends State<PeriodizationComparisonScreen> {
  final _repository = PeriodizationRepository();
  List<PeriodizationPlan> _plans = const [];
  PeriodizationPlan? _left;
  PeriodizationPlan? _right;
  _PlanStats? _leftStats;
  _PlanStats? _rightStats;
  bool _loading = true;
  bool _comparing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final plans = await _repository.getPlans();
    final eligible = plans
        .where(
          (plan) =>
              plan.status == PeriodizationPlanStatus.completed ||
              plan.status == PeriodizationPlanStatus.archived ||
              plan.status == PeriodizationPlanStatus.active,
        )
        .toList();
    if (!mounted) return;
    setState(() {
      _plans = eligible;
      if (eligible.length >= 2) {
        _left = eligible[0];
        _right = eligible[1];
      }
      _loading = false;
    });
    if (eligible.length >= 2) await _compare();
  }

  Future<_PlanStats> _stats(PeriodizationPlan plan) async {
    final phases = await _repository.getPhases(plan.id);
    final metrics = <PeriodizationMetrics>[];
    for (final phase in phases) {
      metrics.add(await _repository.getPhaseMetrics(phase));
    }
    return _PlanStats.fromMetrics(plan, metrics);
  }

  Future<void> _compare() async {
    if (_left == null || _right == null || _left!.id == _right!.id) return;
    setState(() => _comparing = true);
    final results = await Future.wait([_stats(_left!), _stats(_right!)]);
    if (!mounted) return;
    setState(() {
      _leftStats = results[0];
      _rightStats = results[1];
      _comparing = false;
    });
  }

  Future<void> _pickPlan({required bool left}) async {
    final currentOther = left ? _right : _left;
    final selected = await showModalBottomSheet<PeriodizationPlan>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) {
        final loc = AppLocalizations.of(context)!;
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
              child: Text(
                left ? loc.periodizationPlanA : loc.periodizationPlanB,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            ..._plans.map(
              (plan) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: PeriodizationSurface(
                  selected: plan.id == (left ? _left?.id : _right?.id),
                  onTap: plan.id == currentOther?.id
                      ? null
                      : () => Navigator.pop(context, plan),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.primaryContainer,
                        child: const Icon(Icons.route_outlined),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              plan.name,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            Text(
                              '${(plan.totalDays / 7).ceil()} sem.',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      if (plan.id == (left ? _left?.id : _right?.id))
                        Icon(
                          Icons.check_circle_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
    if (selected == null) return;
    setState(() {
      if (left) {
        _left = selected;
      } else {
        _right = selected;
      }
      _leftStats = null;
      _rightStats = null;
    });
    await _compare();
  }

  void _swap() {
    setState(() {
      final current = _left;
      _left = _right;
      _right = current;
      final stats = _leftStats;
      _leftStats = _rightStats;
      _rightStats = stats;
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          loc.periodizationCompare,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _plans.length < 2
          ? PeriodizationEmptyState(
              icon: Icons.compare_arrows_rounded,
              title: loc.periodizationCompare,
              subtitle: loc.periodizationNoCompletedPlans,
              primaryLabel: loc.periodizationHistory,
              onPrimary: () => Navigator.pop(context),
            )
          : CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            theme.colorScheme.primaryContainer.withAlpha(180),
                            theme.colorScheme.surfaceContainerLow,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withAlpha(20),
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: Icon(
                              Icons.insights_outlined,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Text(
                              loc.periodizationComparisonHint,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: PeriodizationSectionHeader(
                      title: loc.periodizationSelectPlans,
                      icon: Icons.swap_horiz_rounded,
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      children: [
                        _PlanPickerCard(
                          eyebrow: loc.periodizationPlanA,
                          plan: _left,
                          color: theme.colorScheme.primary,
                          onTap: () => _pickPlan(left: true),
                        ),
                        SizedBox(
                          height: 42,
                          child: Center(
                            child: IconButton.filledTonal(
                              tooltip: WidgetsLocalizations.of(
                                context,
                              ).reorderItemDown,
                              onPressed: _swap,
                              icon: const Icon(Icons.swap_vert_rounded),
                            ),
                          ),
                        ),
                        _PlanPickerCard(
                          eyebrow: loc.periodizationPlanB,
                          plan: _right,
                          color: theme.colorScheme.tertiary,
                          onTap: () => _pickPlan(left: false),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_comparing)
                  const SliverPadding(
                    padding: EdgeInsets.all(42),
                    sliver: SliverToBoxAdapter(
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  )
                else if (_leftStats != null && _rightStats != null) ...[
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 26, 16, 0),
                    sliver: SliverToBoxAdapter(
                      child: PeriodizationSectionHeader(
                        title: loc.periodizationPlanSummary,
                        icon: Icons.analytics_outlined,
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 36),
                    sliver: SliverToBoxAdapter(
                      child: _ComparisonResults(
                        left: _leftStats!,
                        right: _rightStats!,
                      ).animate().fadeIn(duration: 240.ms).slideY(begin: .025),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _PlanPickerCard extends StatelessWidget {
  final String eyebrow;
  final PeriodizationPlan? plan;
  final Color color;
  final VoidCallback onTap;

  const _PlanPickerCard({
    required this.eyebrow,
    required this.plan,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return PeriodizationSurface(
      accentColor: color,
      selected: true,
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withAlpha(25),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.route_outlined, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eyebrow.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  plan?.name ?? loc.periodizationChoosePlan,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (plan != null)
                  Text(
                    '${(plan!.totalDays / 7).ceil()} sem.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const Icon(Icons.expand_more_rounded),
        ],
      ),
    );
  }
}

class _ComparisonResults extends StatelessWidget {
  final _PlanStats left;
  final _PlanStats right;

  const _ComparisonResults({required this.left, required this.right});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final rows = <_ComparisonValue>[
      _ComparisonValue(
        icon: Icons.layers_outlined,
        label: loc.periodizationPhases,
        left: '${left.phaseCount}',
        right: '${right.phaseCount}',
      ),
      _ComparisonValue(
        icon: Icons.fitness_center_rounded,
        label: loc.periodizationWorkouts,
        left: '${left.workouts}',
        right: '${right.workouts}',
      ),
      _ComparisonValue(
        icon: Icons.format_list_numbered_rounded,
        label: loc.periodizationSets,
        left: '${left.sets}',
        right: '${right.sets}',
      ),
      _ComparisonValue(
        icon: Icons.monitor_weight_outlined,
        label: loc.commonVolume,
        left: _compact(left.volume),
        right: _compact(right.volume),
      ),
      _ComparisonValue(
        icon: Icons.local_fire_department_outlined,
        label: loc.periodizationAverageCalories,
        left: _number(left.averageCalories),
        right: _number(right.averageCalories),
      ),
      _ComparisonValue(
        icon: Icons.donut_large_rounded,
        label: loc.periodizationAdherence,
        left: _percent(left.nutritionAdherence),
        right: _percent(right.nutritionAdherence),
      ),
      _ComparisonValue(
        icon: Icons.scale_outlined,
        label: loc.periodizationWeightChange,
        left: _kg(left.weightChange),
        right: _kg(right.weightChange),
      ),
      _ComparisonValue(
        icon: Icons.bedtime_outlined,
        label: loc.periodizationAverageSleep,
        left: _hours(left.averageSleep),
        right: _hours(right.averageSleep),
      ),
    ];
    return PeriodizationSurface(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withAlpha(135),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(18),
              ),
            ),
            child: Row(
              children: [
                const SizedBox(width: 34),
                Expanded(
                  child: Text(
                    left.plan.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    right.plan.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.tertiary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (var index = 0; index < rows.length; index++) ...[
            if (index > 0)
              Divider(
                height: 1,
                color: theme.colorScheme.outlineVariant.withAlpha(80),
              ),
            _ComparisonRow(value: rows[index]),
          ],
        ],
      ),
    );
  }

  static String _number(double? value) =>
      value == null ? '—' : value.round().toString();
  static String _percent(double? value) =>
      value == null ? '—' : '${value.round()}%';
  static String _kg(double? value) => value == null
      ? '—'
      : '${value >= 0 ? '+' : ''}${value.toStringAsFixed(1)} kg';
  static String _hours(double? value) =>
      value == null ? '—' : '${value.toStringAsFixed(1)} h';
  static String _compact(double value) => value >= 1000
      ? '${(value / 1000).toStringAsFixed(1)}k'
      : value.round().toString();
}

class _ComparisonValue {
  final IconData icon;
  final String label;
  final String left;
  final String right;

  const _ComparisonValue({
    required this.icon,
    required this.label,
    required this.left,
    required this.right,
  });
}

class _ComparisonRow extends StatelessWidget {
  final _ComparisonValue value;

  const _ComparisonRow({required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          Tooltip(
            message: value.label,
            child: Icon(
              value.icon,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              children: [
                Text(
                  value.left,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.primary,
                  ),
                ),
                Text(
                  value.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              children: [
                Text(
                  value.right,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.tertiary,
                  ),
                ),
                Text(
                  value.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
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

class _PlanStats {
  final PeriodizationPlan plan;
  final int phaseCount;
  final int workouts;
  final int sets;
  final double volume;
  final double? averageCalories;
  final double? nutritionAdherence;
  final double? weightChange;
  final double? averageSleep;

  const _PlanStats({
    required this.plan,
    required this.phaseCount,
    required this.workouts,
    required this.sets,
    required this.volume,
    this.averageCalories,
    this.nutritionAdherence,
    this.weightChange,
    this.averageSleep,
  });

  factory _PlanStats.fromMetrics(
    PeriodizationPlan plan,
    List<PeriodizationMetrics> metrics,
  ) {
    final nutritionDays = metrics.fold<int>(
      0,
      (sum, item) => sum + item.nutritionDaysLogged,
    );
    final sleepDays = metrics.fold<int>(
      0,
      (sum, item) => sum + item.sleepDaysLogged,
    );
    final adherence = metrics
        .where((item) => item.nutritionAdherencePercent != null)
        .toList();
    final weights = metrics
        .where((item) => item.weightChangeKg != null)
        .toList();
    return _PlanStats(
      plan: plan,
      phaseCount: metrics.length,
      workouts: metrics.fold(0, (sum, item) => sum + item.workoutCount),
      sets: metrics.fold(0, (sum, item) => sum + item.completedSets),
      volume: metrics.fold(0, (sum, item) => sum + item.volume),
      averageCalories: nutritionDays == 0
          ? null
          : metrics.fold<double>(
                  0,
                  (sum, item) =>
                      sum +
                      (item.averageCalories ?? 0) * item.nutritionDaysLogged,
                ) /
                nutritionDays,
      nutritionAdherence: adherence.isEmpty
          ? null
          : adherence.fold<double>(
                  0,
                  (sum, item) => sum + item.nutritionAdherencePercent!,
                ) /
                adherence.length,
      weightChange: weights.isEmpty
          ? null
          : weights.fold<double>(0, (sum, item) => sum + item.weightChangeKg!),
      averageSleep: sleepDays == 0
          ? null
          : metrics.fold<double>(
                  0,
                  (sum, item) =>
                      sum +
                      (item.averageSleepHours ?? 0) * item.sleepDaysLogged,
                ) /
                sleepDays,
    );
  }
}
