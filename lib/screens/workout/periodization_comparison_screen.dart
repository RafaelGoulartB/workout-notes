import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/periodization_metrics.dart';
import 'package:workout_notes/models/periodization_plan.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';

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

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(loc.periodizationCompare)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _plans.length < 2
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Text(
                  loc.periodizationNoCompletedPlans,
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 60),
              children: [
                Text(loc.periodizationSelectPlans),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _planPicker(
                        _left,
                        (plan) => setState(() => _left = plan),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('×'),
                    ),
                    Expanded(
                      child: _planPicker(
                        _right,
                        (plan) => setState(() => _right = plan),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _left?.id == _right?.id || _comparing
                      ? null
                      : _compare,
                  icon: const Icon(Icons.compare_arrows),
                  label: Text(loc.periodizationCompare),
                ),
                if (_comparing)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_leftStats != null && _rightStats != null) ...[
                  const SizedBox(height: 24),
                  Text(
                    loc.periodizationPlanSummary,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 10),
                  _ComparisonTable(left: _leftStats!, right: _rightStats!),
                ],
              ],
            ),
    );
  }

  Widget _planPicker(
    PeriodizationPlan? value,
    ValueChanged<PeriodizationPlan?> onChanged,
  ) => DropdownButtonFormField<PeriodizationPlan>(
    initialValue: value,
    isExpanded: true,
    decoration: const InputDecoration(border: OutlineInputBorder()),
    items: _plans
        .map(
          (plan) => DropdownMenuItem(
            value: plan,
            child: Text(plan.name, overflow: TextOverflow.ellipsis),
          ),
        )
        .toList(),
    onChanged: onChanged,
  );
}

class _ComparisonTable extends StatelessWidget {
  final _PlanStats left;
  final _PlanStats right;

  const _ComparisonTable({required this.left, required this.right});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final rows = <(String, String, String)>[
      ('Fases / Phases', '${left.phaseCount}', '${right.phaseCount}'),
      (loc.periodizationWorkouts, '${left.workouts}', '${right.workouts}'),
      (loc.periodizationSets, '${left.sets}', '${right.sets}'),
      (loc.commonVolume, _compact(left.volume), _compact(right.volume)),
      (
        loc.periodizationAverageCalories,
        _number(left.averageCalories),
        _number(right.averageCalories),
      ),
      (
        loc.periodizationAdherence,
        _percent(left.nutritionAdherence),
        _percent(right.nutritionAdherence),
      ),
      (
        loc.periodizationWeightChange,
        _kg(left.weightChange),
        _kg(right.weightChange),
      ),
      (
        loc.periodizationAverageSleep,
        _hours(left.averageSleep),
        _hours(right.averageSleep),
      ),
    ];
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(1.35),
          1: FlexColumnWidth(1),
          2: FlexColumnWidth(1),
        },
        border: TableBorder(
          horizontalInside: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        children: [
          TableRow(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
            ),
            children: [
              const SizedBox(height: 52),
              _cell(left.plan.name, bold: true),
              _cell(right.plan.name, bold: true),
            ],
          ),
          ...rows.map(
            (row) => TableRow(
              children: [
                _cell(row.$1),
                _cell(row.$2, emphasize: _wins(row.$2, row.$3)),
                _cell(row.$3, emphasize: _wins(row.$3, row.$2)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell(String text, {bool bold = false, bool emphasize = false}) =>
      Builder(
        builder: (context) => Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            text,
            textAlign: bold ? TextAlign.center : TextAlign.start,
            style: TextStyle(
              fontWeight: bold || emphasize ? FontWeight.bold : null,
              color: emphasize ? Theme.of(context).colorScheme.primary : null,
            ),
          ),
        ),
      );

  static bool _wins(String a, String b) {
    final left = double.tryParse(a.replaceAll(RegExp(r'[^0-9.-]'), ''));
    final right = double.tryParse(b.replaceAll(RegExp(r'[^0-9.-]'), ''));
    return left != null && right != null && left > right;
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
