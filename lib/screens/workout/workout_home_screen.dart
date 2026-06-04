import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../../database/database_helper.dart';
import 'active_workout_screen.dart';
import 'quick_add_screen.dart';
import 'calendar_screen.dart';
import 'exercise_library_screen.dart';
import 'routines_screen.dart';
import 'progress_screen.dart';
import 'body_tracker_screen.dart';
import 'settings_screen.dart';
import 'export_screen.dart';
import 'rest_timer_screen.dart';
import 'workout_detail_screen.dart';

class WorkoutHomeScreen extends StatefulWidget {
  const WorkoutHomeScreen({super.key});

  @override
  State<WorkoutHomeScreen> createState() => _WorkoutHomeScreenState();
}

class _WorkoutHomeScreenState extends State<WorkoutHomeScreen> {
  final _db = DatabaseHelper.instance;
  bool _isLoading = true;
  List<Map<String, dynamic>> _activeWorkouts = [];
  List<Map<String, dynamic>> _completedWorkouts = [];
  List<Map<String, dynamic>> _routines = [];
  bool _showCompleted = true;
  bool _showUpcoming = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final allWorkouts = await _db.getWorkouts(limit: 50);
      _routines = await _db.getRoutines();

      final active = <Map<String, dynamic>>[];
      final completed = <Map<String, dynamic>>[];
      for (final w in allWorkouts) {
        if ((w['end_time'] as String?) == null) {
          active.add(w);
        } else {
          completed.add(w);
        }
      }

      if (mounted) {
        setState(() {
          _activeWorkouts = active;
          _completedWorkouts = completed;
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

  void _continueActiveWorkout(String id) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ActiveWorkoutScreen(workoutId: id)),
    );
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateFormat('EEEE, d \'de\' MMMM', 'pt_BR').format(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Treino'),
        centerTitle: true,
        actions: [
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
                  SliverToBoxAdapter(child: _buildHeader(theme, today)),
                  SliverToBoxAdapter(child: _buildQuickActions(theme)),
                  SliverToBoxAdapter(child: _buildNavGrid(theme)),
                  // Active workout section (always visible, non-collapsible)
                  SliverToBoxAdapter(child: _buildActiveSection(theme)),
                  // Upcoming / Routines section (collapsible)
                  if (_routines.isNotEmpty)
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

  Widget _buildHeader(ThemeData theme, String todayStr) {
    final todayFormatted = todayStr[0].toUpperCase() + todayStr.substring(1);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('🏋️', style: theme.textTheme.displaySmall),
          const SizedBox(height: 4),
          Text('Hora de Treinar!', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(todayFormatted, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideX(begin: -0.05);
  }

  Widget _buildQuickActions(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(16),
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
    ).animate().fadeIn(duration: 400.ms).slideX(begin: -0.05);
  }

  Widget _buildNavGrid(ThemeData theme) {
    final items = [
      _NavItemData(Icons.fitness_center, 'Exercícios', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ExerciseLibraryScreen()))),
      _NavItemData(Icons.repeat, 'Rotinas', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RoutinesScreen()))),
      _NavItemData(Icons.bar_chart, 'Progresso', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProgressScreen()))),
      _NavItemData(Icons.monitor_weight_outlined, 'Medidas', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BodyTrackerScreen()))),
      _NavItemData(Icons.download, 'Exportar', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ExportScreen()))),
      _NavItemData(Icons.timer_outlined, 'Timer', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RestTimerScreen()))),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Text('Navegação', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              ),
              const Divider(),
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
      ),
    ).animate().fadeIn(duration: 500.ms);
  }

  // === EM ANDAMENTO (non-collapsible) ===
  Widget _buildActiveSection(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
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
              Text('Em Andamento', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
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
                Text('Próximos Treinos', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                Icon(
                  _showUpcoming ? Icons.expand_less : Icons.expand_more,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
          if (_showUpcoming) ...[
            const SizedBox(height: 8),
            ...(_routines.map((r) => _buildRoutineCard(r, theme))),
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
                Text('Treinos Concluídos', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
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

  Widget _buildRoutineCard(Map<String, dynamic> routine, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RoutinesScreen()),
            );
            if (result == true) _loadData();
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.repeat, color: theme.colorScheme.onSecondaryContainer, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(routine['name'] as String? ?? '', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                ),
                Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant, size: 20),
              ],
            ),
          ),
        ),
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
