import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/periodization_checkin.dart';
import 'package:workout_notes/models/periodization_metrics.dart';
import 'package:workout_notes/models/periodization_phase.dart';
import 'package:workout_notes/models/periodization_target.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';
import 'package:workout_notes/widgets/periodization/periodization_ui.dart';

class PeriodizationCheckinScreen extends StatefulWidget {
  final PeriodizationPhase phase;
  final DateTime? weekStart;

  const PeriodizationCheckinScreen({
    super.key,
    required this.phase,
    this.weekStart,
  });

  @override
  State<PeriodizationCheckinScreen> createState() =>
      _PeriodizationCheckinScreenState();
}

class _PeriodizationCheckinScreenState
    extends State<PeriodizationCheckinScreen> {
  final _repository = PeriodizationRepository();
  final _notes = TextEditingController();
  late final DateTime _weekStart;
  PeriodizationMetrics? _metrics;
  PeriodizationTarget? _target;
  PeriodizationCheckin? _existing;
  int _energy = 3;
  int _hunger = 3;
  int _recovery = 3;
  String _performance = 'stable';
  PeriodizationDecision _decision = PeriodizationDecision.maintain;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final date = widget.weekStart ?? DateTime.now();
    final day = DateTime(date.year, date.month, date.day);
    _weekStart = day.subtract(Duration(days: day.weekday - DateTime.monday));
    _load();
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _repository.getWeekMetrics(widget.phase, _weekStart),
      _repository.getEffectiveTarget(widget.phase.id, date: _weekStart),
      _repository.getCheckin(widget.phase.id, _weekStart),
    ]);
    if (!mounted) return;
    _metrics = results[0] as PeriodizationMetrics;
    _target = results[1] as PeriodizationTarget?;
    _existing = results[2] as PeriodizationCheckin?;
    final existing = _existing;
    if (existing != null) {
      _energy = existing.energy;
      _hunger = existing.hunger;
      _recovery = existing.recovery;
      _performance = existing.performance;
      _decision = existing.decision;
      _notes.text = existing.notes ?? '';
    }
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final checkin = PeriodizationCheckin(
        id: _existing?.id ?? const Uuid().v4(),
        phaseId: widget.phase.id,
        weekStart: _weekStart,
        energy: _energy,
        hunger: _hunger,
        recovery: _recovery,
        performance: _performance,
        decision: _decision,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        metricsSnapshot: _metrics?.toSnapshot() ?? const {},
        targetsSnapshot: _target?.toSnapshot() ?? const {},
        createdAt: DateTime.now(),
      );
      await _repository.saveCheckin(checkin);
      if (mounted) Navigator.pop(context, _decision);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.periodizationSaveError('$error'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final end = _weekStart.add(const Duration(days: 6));
    return Scaffold(
      appBar: AppBar(
        title: Text(
          loc.periodizationWeekReview,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      bottomNavigationBar: _loading
          ? null
          : PeriodizationBottomBar(
              primary: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text(loc.periodizationSaveReview),
              ),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(widget.phase.color).withAlpha(45),
                        theme.colorScheme.surfaceContainerLow,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Color(widget.phase.color).withAlpha(55),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Color(widget.phase.color).withAlpha(30),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Icon(
                          Icons.fact_check_outlined,
                          color: Color(widget.phase.color),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.phase.name,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${DateFormat.MMMd(Intl.defaultLocale).format(_weekStart)} – ${DateFormat.MMMd(Intl.defaultLocale).format(end)}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                PeriodizationSectionHeader(
                  title: loc.periodizationAutomaticSummary,
                  icon: Icons.auto_graph_rounded,
                ),
                _SummaryCard(metrics: _metrics!, target: _target),
                const SizedBox(height: 18),
                PeriodizationSectionHeader(
                  title: loc.periodizationWeekReview,
                  icon: Icons.favorite_outline_rounded,
                ),
                PeriodizationSurface(
                  child: Column(
                    children: [
                      _RatingRow(
                        label: loc.periodizationEnergy,
                        icon: Icons.bolt_rounded,
                        value: _energy,
                        onChanged: (value) => setState(() => _energy = value),
                      ),
                      const Divider(height: 22),
                      _RatingRow(
                        label: loc.periodizationHunger,
                        icon: Icons.restaurant_rounded,
                        value: _hunger,
                        onChanged: (value) => setState(() => _hunger = value),
                      ),
                      const Divider(height: 22),
                      _RatingRow(
                        label: loc.periodizationRecovery,
                        icon: Icons.bedtime_outlined,
                        value: _recovery,
                        onChanged: (value) => setState(() => _recovery = value),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                PeriodizationSectionHeader(
                  title: loc.periodizationPerformance,
                  icon: Icons.trending_up_rounded,
                ),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: 'worse',
                        icon: const Icon(Icons.trending_down_rounded),
                        label: Text(loc.periodizationPerformanceWorse),
                      ),
                      ButtonSegment(
                        value: 'stable',
                        icon: const Icon(Icons.trending_flat_rounded),
                        label: Text(loc.periodizationPerformanceStable),
                      ),
                      ButtonSegment(
                        value: 'improved',
                        icon: const Icon(Icons.trending_up_rounded),
                        label: Text(loc.periodizationPerformanceImproved),
                      ),
                    ],
                    selected: {_performance},
                    showSelectedIcon: false,
                    onSelectionChanged: (value) =>
                        setState(() => _performance = value.first),
                  ),
                ),
                const SizedBox(height: 22),
                PeriodizationSectionHeader(
                  title: loc.periodizationDecision,
                  icon: Icons.alt_route_rounded,
                ),
                ...[
                  (
                    PeriodizationDecision.maintain,
                    loc.periodizationMaintain,
                    Icons.play_arrow_rounded,
                  ),
                  (
                    PeriodizationDecision.adjust,
                    loc.periodizationAdjust,
                    Icons.tune_rounded,
                  ),
                  (
                    PeriodizationDecision.endPhase,
                    loc.periodizationEndPhase,
                    Icons.flag_outlined,
                  ),
                ].map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: PeriodizationSurface(
                      selected: _decision == item.$1,
                      onTap: () => setState(() => _decision = item.$1),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            item.$3,
                            color: _decision == item.$1
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              item.$2,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Icon(
                            _decision == item.$1
                                ? Icons.check_circle_rounded
                                : Icons.circle_outlined,
                            color: _decision == item.$1
                                ? theme.colorScheme.primary
                                : theme.colorScheme.outline,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _notes,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: loc.periodizationReviewNotes,
                    alignLabelWithHint: true,
                    prefixIcon: const Padding(
                      padding: EdgeInsets.only(bottom: 72),
                      child: Icon(Icons.notes_rounded),
                    ),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final PeriodizationMetrics metrics;
  final PeriodizationTarget? target;

  const _SummaryCard({required this.metrics, required this.target});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return PeriodizationSurface(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: _Metric(
              value: metrics.weightChangeKg == null
                  ? '—'
                  : '${metrics.weightChangeKg! >= 0 ? '+' : ''}${metrics.weightChangeKg!.toStringAsFixed(1)} kg',
              label: loc.periodizationWeightChange,
            ),
          ),
          Expanded(
            child: _Metric(
              value: target?.workoutsPerWeek == null
                  ? '${metrics.workoutCount}'
                  : '${metrics.workoutCount}/${target!.workoutsPerWeek}',
              label: loc.periodizationWorkouts,
            ),
          ),
          Expanded(
            child: _Metric(
              value: metrics.nutritionAdherencePercent == null
                  ? '—'
                  : '${metrics.nutritionAdherencePercent!.round()}%',
              label: loc.periodizationAdherence,
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String value;
  final String label;

  const _Metric({required this.value, required this.label});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        value,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 3),
      Text(
        label,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelSmall,
      ),
    ],
  );
}

class _RatingRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final int value;
  final ValueChanged<int> onChanged;

  const _RatingRow({
    required this.label,
    required this.icon,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 19, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
            const Spacer(),
            Text('$value/5', style: theme.textTheme.labelMedium),
          ],
        ),
        const SizedBox(height: 9),
        Row(
          children: List.generate(5, (index) {
            final score = index + 1;
            final selected = score == value;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: index == 4 ? 0 : 7),
                child: Semantics(
                  button: true,
                  selected: selected,
                  label: '$label $score/5',
                  child: InkWell(
                    onTap: () => onChanged(score),
                    borderRadius: BorderRadius.circular(10),
                    child: Ink(
                      height: 38,
                      decoration: BoxDecoration(
                        color: selected
                            ? theme.colorScheme.primaryContainer
                            : theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                        border: selected
                            ? Border.all(color: theme.colorScheme.primary)
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          '$score',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: selected ? theme.colorScheme.primary : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}
