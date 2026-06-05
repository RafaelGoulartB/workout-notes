import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../../database/database_helper.dart';
import '../../services/rest_timer_service.dart';
import 'active_workout_screen.dart';
import 'quick_add_screen.dart';
import 'calendar_screen.dart';
import 'exercise_library_screen.dart';
import 'routines_screen.dart';
import 'progress_screen.dart';
import 'body_tracker_screen.dart';
import 'settings_screen.dart';
import 'rest_timer_screen.dart';
import 'workout_detail_screen.dart';

class WorkoutHomeScreen extends StatefulWidget {
  const WorkoutHomeScreen({super.key});

  @override
  State<WorkoutHomeScreen> createState() => _WorkoutHomeScreenState();
}

class _WorkoutHomeScreenState extends State<WorkoutHomeScreen> {
  final _db = DatabaseHelper.instance;
  final _timerService = RestTimerService.instance;
  bool _isLoading = true;
  List<Map<String, dynamic>> _activeWorkouts = [];
  List<Map<String, dynamic>> _upcomingWorkouts = [];
  List<Map<String, dynamic>> _completedWorkouts = [];
  bool _showCompleted = true;
  bool _showUpcoming = true;

  // Stats for header card
  int _monthWorkouts = 0;
  double _monthVolume = 0;
  int _currentStreak = 0;

  @override
  void initState() {
    super.initState();
    _timerService.addListener(_onTimerTick);
    _loadData();
  }

  @override
  void dispose() {
    _timerService.removeListener(_onTimerTick);
    super.dispose();
  }

  void _onTimerTick() {
    if (mounted) setState(() {});
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final now = DateTime.now();
      final tomorrow = DateTime(now.year, now.month, now.day + 1);
      final monthStart = DateTime(now.year, now.month, 1);

      final allWorkouts = await _db.getWorkouts(limit: 50);
      final futureWorkouts = await _db.getWorkouts(startDate: tomorrow, limit: 20);

      // Load stats
      final overview = await _db.getWorkoutOverviewStats();
      _currentStreak = (overview['current_streak'] as int?) ?? 0;

      // Calculate month stats
      final monthStr = monthStart.toIso8601String().substring(0, 7);
      double monthVol = 0;
      int monthCount = 0;
      for (final w in allWorkouts) {
        final wDate = w['date'] as String? ?? '';
        if (wDate.startsWith(monthStr)) {
          monthCount++;
          // Get volume for this workout
          final exercises = await _db.getWorkoutExercises(w['id'] as String);
          for (final ee in exercises) {
            final sets = await _db.getExerciseSets(ee['id'] as String);
            for (final s in sets) {
              if ((s['is_warmup'] as int? ?? 0) == 0) {
                monthVol += ((s['weight'] as num?)?.toDouble() ?? 0) * ((s['reps'] as int?) ?? 0);
              }
            }
          }
        }
      }
      _monthWorkouts = monthCount;
      _monthVolume = monthVol;

      final active = <Map<String, dynamic>>[];
      final completed = <Map<String, dynamic>>[];
      final todayStr = now.toIso8601String().substring(0, 10);
      for (final w in allWorkouts) {
        final wDate = w['date'] as String? ?? '';
        final isToday = wDate == todayStr;
        if ((w['end_time'] as String?) == null && isToday) {
          active.add(w);
        } else if ((w['end_time'] as String?) != null) {
          completed.add(w);
        }
      }

      if (mounted) {
        setState(() {
          _activeWorkouts = active;
          _upcomingWorkouts = futureWorkouts.take(5).toList();
          _completedWorkouts = completed.take(5).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _startWorkout() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ActiveWorkoutScreen()),
    );
    _loadData();
  }

  Future<void> _quickAdd() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const QuickAddScreen()),
    );
    _loadData();
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateFormat('EEEE, d \'de\' MMMM', 'pt_BR').format(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: null,
        centerTitle: false,
        automaticallyImplyLeading: false,
        actions: [
          if (_timerService.isActive)
            GestureDetector(
              onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const RestTimerScreen())),
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _timerService.remainingSeconds <= 5 && _timerService.isRunning
                      ? Colors.red.withAlpha(40)
                      : theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _timerService.isPaused ? Icons.pause : Icons.timer,
                      size: 18,
                      color: _timerService.remainingSeconds <= 5 && _timerService.isRunning
                          ? Colors.red
                          : theme.colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _timerService.shortTime,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: _timerService.remainingSeconds <= 5 && _timerService.isRunning
                            ? Colors.red
                            : theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.calendar_month_outlined),
              onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const CalendarScreen())),
              tooltip: 'Histórico',
            ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const WorkoutSettingsScreen())),
            tooltip: 'Configurações',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _buildHeaderStats(theme, today)),
                  SliverToBoxAdapter(child: _buildQuickActions(theme)),
                  SliverToBoxAdapter(child: _buildNavGrid(theme)),
                  // Active workout section (non-collapsible)
                  SliverToBoxAdapter(child: _buildActiveSection(theme)),
                  // Upcoming workouts section (collapsible)
                  if (_upcomingWorkouts.isNotEmpty)
                    SliverToBoxAdapter(child: _buildUpcomingSection(theme)),
                  // Completed workouts section (collapsible)
                  if (_completedWorkouts.isNotEmpty)
                    SliverToBoxAdapter(child: _buildCompletedSection(theme)),
                  const SliverToBoxAdapter(child: SizedBox(height: 100)),
                ],
              ),
            ),
    );
  }

  // ===================== HEADER STATS =====================
  Widget _buildHeaderStats(ThemeData theme, String todayStr) {
    final todayFormatted = todayStr[0].toUpperCase() + todayStr.substring(1);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            todayFormatted,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.surfaceContainerHighest.withAlpha(200),
                  theme.colorScheme.surfaceContainerLow,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  child: _StatItem(
                    label: 'Treinos no Mês',
                    value: '${_monthWorkouts}',
                    icon: Icons.fitness_center,
                    color: theme.colorScheme.primary,
                    theme: theme,
                  ),
                ),
                Container(
                  width: 1,
                  height: 48,
                  color: theme.colorScheme.outlineVariant.withAlpha(80),
                ),
                Expanded(
                  child: _StatItem(
                    label: 'Volume',
                    value: _formatVolume(_monthVolume),
                    icon: Icons.auto_graph,
                    color: theme.colorScheme.secondary,
                    theme: theme,
                  ),
                ),
                Container(
                  width: 1,
                  height: 48,
                  color: theme.colorScheme.outlineVariant.withAlpha(80),
                ),
                Expanded(
                  child: _StatItem(
                    label: 'Sequência',
                    value: '$_currentStreak ${_currentStreak == 1 ? 'dia' : 'dias'}',
                    icon: Icons.local_fire_department,
                    color: Colors.orange,
                    theme: theme,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.05);
  }

  String _formatVolume(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M kg';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k kg';
    return '${v.toStringAsFixed(0)} kg';
  }

  // ===================== QUICK ACTIONS =====================
  Widget _buildQuickActions(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: _ActionCard(
              icon: Icons.fitness_center,
              label: 'Novo Treino',
              subtitle: 'Começar agora',
              color: theme.colorScheme.primary,
              onTap: _startWorkout,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _ActionCard(
              icon: Icons.bolt,
              label: 'Quick Add',
              subtitle: 'Adicionar rápido',
              color: theme.colorScheme.secondary,
              onTap: _quickAdd,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.05);
  }

  // ===================== NAV GRID =====================
  Widget _buildNavGrid(ThemeData theme) {
    final items = [
      _NavItemData(Icons.fitness_center, 'Exercícios', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ExerciseLibraryScreen()))),
      _NavItemData(Icons.repeat, 'Rotinas', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RoutinesScreen()))),
      _NavItemData(Icons.bar_chart, 'Progresso', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProgressScreen()))),
      _NavItemData(Icons.monitor_weight_outlined, 'Medidas', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BodyTrackerScreen()))),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('NAVEGAÇÃO', style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: theme.colorScheme.onSurfaceVariant,
              )),
            ),
            const Divider(height: 1),
            ...items.map((item) => ListTile(
              leading: Icon(item.icon, color: theme.colorScheme.primary),
              title: Text(item.label, style: theme.textTheme.bodyMedium),
              trailing: Icon(Icons.chevron_right, size: 18, color: theme.colorScheme.onSurfaceVariant),
              onTap: item.onTap,
              dense: true,
              visualDensity: VisualDensity.compact,
            )),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 500.ms);
  }

  // === EM ANDAMENTO (non-collapsible) ===
  Widget _buildActiveSection(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.green.withAlpha(30),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(Icons.play_circle_fill, size: 18, color: Colors.green),
              ),
              const SizedBox(width: 8),
              Text('EM ANDAMENTO', style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: theme.colorScheme.onSurface,
              )),
            ],
          ),
          const SizedBox(height: 8),
          if (_activeWorkouts.isEmpty)
            _buildEmptyHint('Nenhum treino em andamento', Icons.play_circle_outline, theme)
          else
            ...(_activeWorkouts.map((w) => _buildWorkoutCard(w, theme, isActive: true))),
        ],
      ),
    );
  }

  // === PRÓXIMOS TREINOS (collapsible) ===
  Widget _buildUpcomingSection(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _showUpcoming = !_showUpcoming),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(Icons.schedule, size: 18, color: theme.colorScheme.onSecondaryContainer),
                ),
                const SizedBox(width: 8),
                Text('PRÓXIMOS TREINOS', style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: theme.colorScheme.onSurface,
                )),
                const Spacer(),
                Text('${_upcomingWorkouts.length}', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(width: 4),
                Icon(
                  _showUpcoming ? Icons.expand_less : Icons.expand_more,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
          if (_showUpcoming) ...[
            const SizedBox(height: 8),
            ...(_upcomingWorkouts.map((w) => _buildWorkoutCard(w, theme, isActive: false))),
          ],
        ],
      ),
    );
  }

  // === TREINOS CONCLUÍDOS (collapsible) ===
  Widget _buildCompletedSection(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _showCompleted = !_showCompleted),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(Icons.fitness_center, size: 18, color: theme.colorScheme.onPrimaryContainer),
                ),
                const SizedBox(width: 8),
                Text('TREINOS CONCLUÍDOS', style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: theme.colorScheme.onSurface,
                )),
                const Spacer(),
                Text('${_completedWorkouts.length}', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(width: 4),
                Icon(
                  _showCompleted ? Icons.expand_less : Icons.expand_more,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
          if (_showCompleted) ...[
            const SizedBox(height: 8),
            ...(_completedWorkouts.map((w) => _buildWorkoutCard(w, theme, isActive: false))),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyHint(String text, IconData icon, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant.withAlpha(120)),
          const SizedBox(width: 8),
          Text(text, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant.withAlpha(180))),
        ],
      ),
    );
  }

  Widget _buildWorkoutCard(Map<String, dynamic> workout, ThemeData theme, {required bool isActive}) {
    final date = (workout['date'] as String?) ?? '';
    final formatted = date.isNotEmpty
        ? DateFormat('d \'de\' MMMM yyyy', 'pt_BR').format(DateTime.parse(date))
        : '';
    final duration = (workout['duration_seconds'] as int?) ?? 0;
    final durStr = isActive
        ? 'Em andamento'
        : duration > 0
            ? '${duration ~/ 60}min ${duration % 60}s'
            : '--';
    final feeling = (workout['feeling_rating'] as int?) ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isActive
                ? Colors.green.withAlpha(100)
                : theme.colorScheme.outlineVariant.withAlpha(80),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => WorkoutDetailScreen(workoutId: workout['id'] as String),
              ),
            );
            _loadData();
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isActive ? Colors.green.withAlpha(25) : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isActive ? Icons.play_circle_fill : Icons.fitness_center,
                    color: isActive ? Colors.green : theme.colorScheme.onSurfaceVariant,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(formatted, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(durStr, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                if (feeling > 0)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(5, (i) => Icon(
                      i < feeling ? Icons.star : Icons.star_border,
                      size: 14,
                      color: Colors.amber,
                    )),
                  ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ===================== SHARED WIDGETS =====================

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final ThemeData theme;

  const _StatItem({
    required this.label, required this.value, required this.icon,
    required this.color, required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              value,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon, required this.label, required this.subtitle,
    required this.color, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withAlpha(25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(height: 16),
              Text(label, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItemData {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  _NavItemData(this.icon, this.label, this.onTap);
}
