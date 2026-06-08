import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import '../../repositories/workout_repository.dart';
import '../../repositories/routine_repository.dart';
import 'workout_detail_screen.dart';
import 'future_workout_planner_screen.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final _workoutRepo = WorkoutRepository();
  final _routineRepo = RoutineRepository();
  DateTime _selectedDate = DateTime.now();
  int _currentMonth = DateTime.now().month;
  int _currentYear = DateTime.now().year;
  Map<String, List<Map<String, dynamic>>> _workoutsByDate = {};
  Map<String, List<Map<String, dynamic>>> _categoriesByDate = {};
  List<Map<String, dynamic>> _selectedDayWorkouts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMonth();
  }

  Future<void> _loadMonth() async {
    setState(() => _isLoading = true);
    final workouts = await _workoutRepo.getWorkoutsByMonth(_currentYear, _currentMonth);
    
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final w in workouts) {
      final date = w['date'] as String? ?? '';
      grouped.putIfAbsent(date, () => []).add(w);
    }

    final categories = await _workoutRepo.getWorkoutCategoriesByDate(_currentYear, _currentMonth);

    _selectedDayWorkouts = grouped[_selectedDate.toIso8601String().substring(0, 10)] ?? [];

    if (mounted) {
      setState(() {
        _workoutsByDate = grouped;
        _categoriesByDate = categories;
        _isLoading = false;
      });
    }
  }

  void _previousMonth() {
    setState(() {
      if (_currentMonth == 1) {
        _currentMonth = 12;
        _currentYear--;
      } else {
        _currentMonth--;
      }
    });
    _loadMonth();
  }

  void _nextMonth() {
    setState(() {
      if (_currentMonth == 12) {
        _currentMonth = 1;
        _currentYear++;
      } else {
        _currentMonth++;
      }
    });
    _loadMonth();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateLocale = Localizations.localeOf(context).toString().startsWith('pt') ? 'pt_BR' : 'en_US';
    final monthName = DateFormat('MMMM yyyy', dateLocale).format(DateTime(_currentYear, _currentMonth));

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.calendarTitle),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Month selector
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(icon: const Icon(Icons.chevron_left), onPressed: _previousMonth),
                      Text(monthName[0].toUpperCase() + monthName.substring(1), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      IconButton(icon: const Icon(Icons.chevron_right), onPressed: _nextMonth),
                    ],
                  ),
                ),

                // Weekday headers
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                        AppLocalizations.of(context)!.calendarSun,
                        AppLocalizations.of(context)!.calendarMon,
                        AppLocalizations.of(context)!.calendarTue,
                        AppLocalizations.of(context)!.calendarWed,
                        AppLocalizations.of(context)!.calendarThu,
                        AppLocalizations.of(context)!.calendarFri,
                        AppLocalizations.of(context)!.calendarSat,
                      ].map((d) => Expanded(
                              child: Center(
                                child: Text(d, style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600, color: theme.colorScheme.onSurfaceVariant)),
                              ),
                            ))
                        .toList(),
                  ),
                ),

                // Calendar grid
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: _buildCalendarGrid(theme),
                ),

                const Divider(height: 1),

                // Selected day workouts
                Expanded(
                  child: _selectedDayWorkouts.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.fitness_center_outlined, size: 48, color: theme.colorScheme.onSurfaceVariant.withAlpha(80)),
                                const SizedBox(height: 16),
                                Text(
                                  AppLocalizations.of(context)!.calendarNoWorkouts(DateFormat('d/M').format(_selectedDate)),
                                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                ),
                                const SizedBox(height: 16),
                                FilledButton.icon(
                                  onPressed: _createWorkoutForSelectedDate,
                                  icon: const Icon(Icons.add, size: 18),
                                  label: Text(AppLocalizations.of(context)!.calendarCreateWorkout),
                                ),
                                const SizedBox(height: 8),
                                OutlinedButton.icon(
                                  onPressed: _importFromRoutine,
                                  icon: const Icon(Icons.repeat, size: 18),
                                  label: Text(AppLocalizations.of(context)!.activeWorkoutImportRoutine),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _selectedDayWorkouts.length,
                          itemBuilder: (ctx, i) {
                            final w = _selectedDayWorkouts[i];
                            final duration = (w['duration_seconds'] as int?) ?? 0;
                            final durStr = duration > 0 ? '${duration ~/ 60}min' : AppLocalizations.of(context)!.calendarInProgress;
                            return Card(
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
                              ),
                              child: ListTile(
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(Icons.fitness_center, color: theme.colorScheme.onPrimaryContainer, size: 20),
                                ),
                                title: Text(w['start_time'] != null
                                    ? DateFormat('HH:mm').format(DateTime.parse(w['start_time'] as String))
                                    : AppLocalizations.of(context)!.calendarNoTime),
                                subtitle: Text(durStr),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () async {
                                  final today = DateTime.now().toIso8601String().substring(0, 10);
                                  final workoutDate = w['date'] as String? ?? '';
                                  final isFuture = workoutDate.compareTo(today) > 0;
                                  Widget target;
                                  if (isFuture) {
                                    target = FutureWorkoutPlannerScreen(workoutId: w['id'] as String);
                                  } else {
                                    target = WorkoutDetailScreen(workoutId: w['id'] as String);
                                  }
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => target),
                                  );
                                  if (result == true) _loadMonth();
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildCalendarGrid(ThemeData theme) {
    final firstDay = DateTime(_currentYear, _currentMonth, 1);
    final lastDay = DateTime(_currentYear, _currentMonth + 1, 0);
    final firstWeekday = firstDay.weekday % 7; // Sunday = 0
    final daysInMonth = lastDay.day;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final selectedStr = _selectedDate.toIso8601String().substring(0, 10);

    final cells = <Widget>[];

    // Empty cells before first day
    for (int i = 0; i < firstWeekday; i++) {
      cells.add(const SizedBox.shrink());
    }

    // Day cells
    for (int day = 1; day <= daysInMonth; day++) {
      final dateStr = '$_currentYear-${_currentMonth.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
      final cats = _categoriesByDate[dateStr] ?? [];
      final hasWorkout = cats.isNotEmpty;
      final isToday = dateStr == today;
      final isSelected = dateStr == selectedStr;

      cells.add(
        GestureDetector(
          onTap: () {
            setState(() {
              _selectedDate = DateTime(_currentYear, _currentMonth, day);
              _selectedDayWorkouts = _workoutsByDate[dateStr] ?? [];
            });
          },
          child: Container(
            margin: const EdgeInsets.all(1),
            decoration: BoxDecoration(
              color: isSelected ? theme.colorScheme.primaryContainer : null,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$day',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                    color: isSelected
                        ? theme.colorScheme.onPrimaryContainer
                        : isToday
                            ? theme.colorScheme.primary
                            : null,
                  ),
                ),
                if (hasWorkout)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: _buildCategoryDots(cats),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.0,
      children: cells,
    );
  }

  /// Builds up to 4 small colored dots representing exercise categories.
  /// If more than 4 categories, shows 3 dots + a "+N" indicator.
  Widget _buildCategoryDots(List<Map<String, dynamic>> categories) {
    final maxDots = 4;
    final displayCats = categories.take(maxDots).toList();
    final overflow = categories.length - maxDots;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ...displayCats.map((cat) {
          final color = Color(cat['color'] as int? ?? 0xFF757575);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
          );
        }),
        if (overflow > 0)
          Padding(
            padding: const EdgeInsets.only(left: 1),
            child: Text(
              '+$overflow',
              style: TextStyle(
                fontSize: 6,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _createWorkoutForSelectedDate() async {
    await _workoutRepo.createWorkout(date: _selectedDate);
    _loadMonth();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.calendarWorkoutCreated), behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> _importFromRoutine() async {
    final ctx = context;
    final scaffoldMessenger = ScaffoldMessenger.of(ctx);
    final loc = AppLocalizations.of(ctx)!;
    final routines = await _routineRepo.getRoutines();
    if (routines.isEmpty) {
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text(loc.activeWorkoutNoRoutineFound), behavior: SnackBarBehavior.floating),
        );
      }
      return;
    }

    final theme = Theme.of(ctx);
    final routineId = await showModalBottomSheet<String>(
      context: ctx,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(
              color: theme.colorScheme.onSurfaceVariant.withAlpha(80),
              borderRadius: BorderRadius.circular(2),
            ))),
            const SizedBox(height: 16),
            Text(loc.activeWorkoutSelectRoutine, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            SizedBox(
              height: 300,
              child: ListView.separated(
                itemCount: routines.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  final routine = routines[i];
                  return ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.repeat, color: theme.colorScheme.onSecondaryContainer, size: 20),
                    ),
                    title: Text(routine['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pop(ctx, routine['id'] as String),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (routineId == null || !mounted) return;

    final days = await _routineRepo.getRoutineDays(routineId);
    if (days.isEmpty) {
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text(loc.activeWorkoutNoRoutineDays), behavior: SnackBarBehavior.floating),
        );
      }
      return;
    }

    final routineName = routines.firstWhere((r) => r['id'] == routineId)['name'] as String;
    final dayId = await showModalBottomSheet<String>(
      context: ctx,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(
              color: theme.colorScheme.onSurfaceVariant.withAlpha(80),
              borderRadius: BorderRadius.circular(2),
            ))),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: Text(loc.activeWorkoutBack),
                ),
              ],
            ),
            Text(routineName, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(loc.activeWorkoutSelectDay, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            SizedBox(
              height: 300,
              child: ListView.separated(
                itemCount: days.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  final day = days[i];
                  return ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.today, color: theme.colorScheme.onPrimaryContainer, size: 20),
                    ),
                    title: Text(day['name'] as String? ?? 'Dia ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    trailing: const Icon(Icons.download),
                    onTap: () => Navigator.pop(ctx, day['id'] as String),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (dayId == null || !mounted) return;

    // Create workout and import
    final newWorkoutId = await _workoutRepo.createWorkout(date: _selectedDate);
    await _workoutRepo.importRoutineDayToWorkout(newWorkoutId, dayId);
    _loadMonth();
    if (mounted) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(loc.activeWorkoutRoutineImported), behavior: SnackBarBehavior.floating),
      );
    }
  }
}
