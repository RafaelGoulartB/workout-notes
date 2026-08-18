import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/periodization_phase.dart';
import 'package:workout_notes/models/periodization_plan.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';
import 'package:workout_notes/repositories/workout_repository.dart';

import 'periodization_phase_detail_screen.dart';
import 'future_workout_planner_screen.dart';

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
  final _workoutRepository = WorkoutRepository();
  late DateTime _month;
  DateTime _selectedDate = DateTime.now();
  List<PeriodizationPhase> _phases = const [];
  List<Map<String, dynamic>> _workouts = const [];
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
    final workouts = await _workoutRepository.getWorkouts(
      startDate: DateTime(_month.year, _month.month),
      endDate: DateTime(_month.year, _month.month + 1, 0),
    );
    if (mounted) {
      setState(() {
        _phases = phases;
        _workouts = workouts;
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
    _load();
  }

  Future<void> _planWorkout() async {
    final id = await _workoutRepository.createWorkout(date: _selectedDate);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FutureWorkoutPlannerScreen(workoutId: id),
      ),
    );
    await _load();
  }

  Map<String, dynamic>? _workoutAt(DateTime date) {
    final key = date.toIso8601String().substring(0, 10);
    for (final workout in _workouts) {
      if (workout['date'] == key) return workout;
    }
    return null;
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
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (selectedPhase == null)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 18),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.event_busy_outlined, size: 44),
                                const SizedBox(height: 10),
                                Text(loc.periodizationCalendarNoPhase),
                              ],
                            ),
                          ),
                        )
                      else
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
                      const SizedBox(height: 12),
                      if (_workoutAt(_selectedDate) case final workout?)
                        FilledButton.tonalIcon(
                          onPressed: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => FutureWorkoutPlannerScreen(
                                  workoutId: workout['id'] as String,
                                ),
                              ),
                            );
                            await _load();
                          },
                          icon: const Icon(Icons.edit_calendar_outlined),
                          label: Text(loc.periodizationOpenWorkout),
                        )
                      else
                        FilledButton.icon(
                          onPressed: _planWorkout,
                          icon: const Icon(Icons.add_task_rounded),
                          label: Text(loc.periodizationPlanWorkout),
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
        final workout = _workoutAt(date);
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
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$day',
                  style: TextStyle(
                    fontWeight: isToday ? FontWeight.bold : null,
                  ),
                ),
                if (workout != null)
                  Container(
                    width: 5,
                    height: 5,
                    margin: const EdgeInsets.only(top: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
