import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../database/database_helper.dart';
import 'workout_detail_screen.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final _db = DatabaseHelper.instance;
  DateTime _selectedDate = DateTime.now();
  int _currentMonth = DateTime.now().month;
  int _currentYear = DateTime.now().year;
  Map<String, List<Map<String, dynamic>>> _workoutsByDate = {};
  List<Map<String, dynamic>> _selectedDayWorkouts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMonth();
  }

  Future<void> _loadMonth() async {
    setState(() => _isLoading = true);
    final workouts = await _db.getWorkoutsByMonth(_currentYear, _currentMonth);
    
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final w in workouts) {
      final date = w['date'] as String? ?? '';
      grouped.putIfAbsent(date, () => []).add(w);
    }

    _selectedDayWorkouts = grouped[_selectedDate.toIso8601String().substring(0, 10)] ?? [];

    if (mounted) {
      setState(() {
        _workoutsByDate = grouped;
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
    final monthName = DateFormat('MMMM yyyy', 'pt_BR').format(DateTime(_currentYear, _currentMonth));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Histórico'),
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
                    children: ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb']
                        .map((d) => Expanded(
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
                                  'Nenhum treino em ${DateFormat('d/M').format(_selectedDate)}',
                                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                ),
                                const SizedBox(height: 16),
                                FilledButton.icon(
                                  onPressed: _createWorkoutForSelectedDate,
                                  icon: const Icon(Icons.add, size: 18),
                                  label: const Text('Criar Treino'),
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
                            final durStr = duration > 0 ? '${duration ~/ 60}min' : 'Em andamento';
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
                                title: Text(DateFormat('HH:mm').format(DateTime.parse(w['start_time'] as String))),
                                subtitle: Text(durStr),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () async {
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => WorkoutDetailScreen(workoutId: w['id'] as String),
                                    ),
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
      final dateStr = '${_currentYear}-${_currentMonth.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
      final hasWorkout = _workoutsByDate.containsKey(dateStr);
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
            margin: const EdgeInsets.all(2),
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
                  Container(
                    width: 6, height: 6,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
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
      childAspectRatio: 1.1,
      children: cells,
    );
  }

  Future<void> _createWorkoutForSelectedDate() async {
    await _db.createWorkout(date: _selectedDate);
    _loadMonth();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Treino criado para este dia!'), behavior: SnackBarBehavior.floating),
      );
    }
  }
}
