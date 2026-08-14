import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/periodization_checkin.dart';
import 'package:workout_notes/models/periodization_metrics.dart';
import 'package:workout_notes/models/periodization_phase.dart';
import 'package:workout_notes/models/periodization_target.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';

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
    final end = _weekStart.add(const Duration(days: 6));
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.periodizationWeekReview),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${DateFormat.MMMd(Intl.defaultLocale).format(_weekStart)} – ${DateFormat.MMMd(Intl.defaultLocale).format(end)}',
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              children: [
                Text(
                  loc.periodizationAutomaticSummary,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 8),
                _SummaryCard(metrics: _metrics!, target: _target),
                const SizedBox(height: 20),
                _RatingRow(
                  label: loc.periodizationEnergy,
                  value: _energy,
                  onChanged: (value) => setState(() => _energy = value),
                ),
                _RatingRow(
                  label: loc.periodizationHunger,
                  value: _hunger,
                  onChanged: (value) => setState(() => _hunger = value),
                ),
                _RatingRow(
                  label: loc.periodizationRecovery,
                  value: _recovery,
                  onChanged: (value) => setState(() => _recovery = value),
                ),
                const SizedBox(height: 12),
                Text(loc.periodizationPerformance),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: 'worse',
                      label: Text(loc.periodizationPerformanceWorse),
                    ),
                    ButtonSegment(
                      value: 'stable',
                      label: Text(loc.periodizationPerformanceStable),
                    ),
                    ButtonSegment(
                      value: 'improved',
                      label: Text(loc.periodizationPerformanceImproved),
                    ),
                  ],
                  selected: {_performance},
                  onSelectionChanged: (value) =>
                      setState(() => _performance = value.first),
                ),
                const SizedBox(height: 24),
                Text(
                  loc.periodizationDecision,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                RadioGroup<PeriodizationDecision>(
                  groupValue: _decision,
                  onChanged: (value) => setState(() => _decision = value!),
                  child: Column(
                    children: [
                      RadioListTile<PeriodizationDecision>(
                        value: PeriodizationDecision.maintain,
                        title: Text(loc.periodizationMaintain),
                      ),
                      RadioListTile<PeriodizationDecision>(
                        value: PeriodizationDecision.adjust,
                        title: Text(loc.periodizationAdjust),
                      ),
                      RadioListTile<PeriodizationDecision>(
                        value: PeriodizationDecision.endPhase,
                        title: Text(loc.periodizationEndPhase),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _notes,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: loc.periodizationReviewNotes,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text(loc.periodizationSaveReview),
                ),
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
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
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
  final int value;
  final ValueChanged<int> onChanged;

  const _RatingRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        ...List.generate(
          5,
          (index) => IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => onChanged(index + 1),
            icon: Icon(
              index < value ? Icons.circle : Icons.circle_outlined,
              size: 18,
            ),
          ),
        ),
      ],
    ),
  );
}
