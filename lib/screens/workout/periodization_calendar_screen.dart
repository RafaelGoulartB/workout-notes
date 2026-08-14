import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/periodization_phase.dart';
import 'package:workout_notes/models/periodization_plan.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';

import 'periodization_phase_detail_screen.dart';

class PeriodizationCalendarScreen extends StatefulWidget {
  final PeriodizationPlan plan;

  const PeriodizationCalendarScreen({super.key, required this.plan});

  @override
  State<PeriodizationCalendarScreen> createState() =>
      _PeriodizationCalendarScreenState();
}

class _PeriodizationCalendarScreenState
    extends State<PeriodizationCalendarScreen> {
  final _repository = PeriodizationRepository();
  late DateTime _month;
  DateTime _selectedDate = DateTime.now();
  List<PeriodizationPhase> _phases = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final initial = widget.plan.contains(DateTime.now())
        ? DateTime.now()
        : widget.plan.startDate;
    _month = DateTime(initial.year, initial.month);
    _selectedDate = initial;
    _load();
  }

  Future<void> _load() async {
    final phases = await _repository.getPhases(widget.plan.id);
    if (mounted) {
      setState(() {
        _phases = phases;
        _loading = false;
      });
    }
  }

  PeriodizationPhase? _phaseAt(DateTime date) {
    for (final phase in _phases) {
      if (phase.contains(date)) return phase;
    }
    return null;
  }

  void _changeMonth(int delta) {
    final next = DateTime(_month.year, _month.month + delta);
    if (next.isBefore(
          DateTime(widget.plan.startDate.year, widget.plan.startDate.month),
        ) ||
        next.isAfter(
          DateTime(widget.plan.endDate.year, widget.plan.endDate.month),
        )) {
      return;
    }
    setState(() => _month = next);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final selectedPhase = _phaseAt(_selectedDate);
    return Scaffold(
      appBar: AppBar(title: Text(loc.periodizationCalendar)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => _changeMonth(-1),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Expanded(
                        child: Text(
                          DateFormat.yMMMM(Intl.defaultLocale).format(_month),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        onPressed: () => _changeMonth(1),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: List.generate(7, (index) {
                      final monday = DateTime(
                        2024,
                        1,
                        1,
                      ).add(Duration(days: index));
                      return Expanded(
                        child: Text(
                          DateFormat.E(
                            Intl.defaultLocale,
                          ).format(monday).substring(0, 1).toUpperCase(),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      );
                    }),
                  ),
                ),
                Padding(padding: const EdgeInsets.all(10), child: _buildGrid()),
                const Divider(height: 1),
                Expanded(
                  child: selectedPhase == null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.event_busy_outlined, size: 44),
                              const SizedBox(height: 10),
                              Text(loc.periodizationCalendarNoPhase),
                            ],
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            Card(
                              color: Color(selectedPhase.color).withAlpha(35),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Color(selectedPhase.color),
                                ),
                                title: Text(selectedPhase.name),
                                subtitle: Text(selectedPhase.intent ?? ''),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          PeriodizationPhaseDetailScreen(
                                            plan: widget.plan,
                                            phase: selectedPhase,
                                          ),
                                    ),
                                  );
                                  await _load();
                                },
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildGrid() {
    final first = DateTime(_month.year, _month.month, 1);
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final leading = first.weekday - 1;
    final count = ((leading + days + 6) ~/ 7) * 7;
    final today = DateTime.now();
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: 3,
        crossAxisSpacing: 3,
      ),
      itemCount: count,
      itemBuilder: (context, index) {
        final day = index - leading + 1;
        if (day < 1 || day > days) return const SizedBox.shrink();
        final date = DateTime(_month.year, _month.month, day);
        final phase = _phaseAt(date);
        final selected = _sameDay(date, _selectedDate);
        final isToday = _sameDay(date, today);
        return InkWell(
          onTap: () => setState(() => _selectedDate = date),
          borderRadius: BorderRadius.circular(9),
          child: Container(
            decoration: BoxDecoration(
              color: phase == null
                  ? null
                  : Color(phase.color).withAlpha(selected ? 110 : 45),
              borderRadius: BorderRadius.circular(9),
              border: selected
                  ? Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 2,
                    )
                  : isToday
                  ? Border.all(color: Theme.of(context).colorScheme.primary)
                  : null,
            ),
            alignment: Alignment.center,
            child: Text(
              '$day',
              style: TextStyle(fontWeight: isToday ? FontWeight.bold : null),
            ),
          ),
        );
      },
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
