import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:life_notes/l10n/app_localizations.dart';
import '../../database/database_helper.dart';
import '../../services/export_service.dart';
import 'active_workout_screen.dart';

class WorkoutDetailScreen extends StatefulWidget {
  final String workoutId;
  const WorkoutDetailScreen({super.key, required this.workoutId});

  @override
  State<WorkoutDetailScreen> createState() => _WorkoutDetailScreenState();
}

class _WorkoutDetailScreenState extends State<WorkoutDetailScreen> {
  final _db = DatabaseHelper.instance;
  Map<String, dynamic>? _workout;
  List<_ExerciseWithSets> _exercises = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _workout = await _db.getWorkout(widget.workoutId);
    if (_workout == null) {
      if (mounted) Navigator.pop(context);
      return;
    }

    final entries = await _db.getWorkoutExercises(widget.workoutId);
    final exercises = <_ExerciseWithSets>[];
    for (final entry in entries) {
      final sets = await _db.getExerciseSets(entry['id'] as String);
      exercises.add(_ExerciseWithSets(
        name: entry['exercise_name'] as String? ?? '',
        categoryName: entry['category_name'] as String? ?? '',
        categoryColor: Color(entry['category_color'] as int? ?? 0xFF757575),
        sets: sets,
      ));
    }

    setState(() {
      _exercises = exercises;
      _isLoading = false;
    });
  }

  int get _totalSets => _exercises.fold<int>(0, (sum, e) => sum + e.sets.length);
  double get _totalVolume {
    double v = 0;
    for (final e in _exercises) {
      for (final s in e.sets) {
        final weight = (s['weight'] as num?)?.toDouble() ?? 0;
        final reps = (s['reps'] as int?) ?? 0;
        if ((s['is_warmup'] as int?) != 1) v += weight * reps;
      }
    }
    return v;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_workout != null
            ? DateFormat("d 'de' MMMM", 'pt_BR').format(DateTime.parse(_workout!['date'] as String))
            : AppLocalizations.of(context)!.workoutDetailContinue),
        centerTitle: true,
        actions: [
          PopupMenuButton(
            itemBuilder: (ctx) => [
              PopupMenuItem(value: 'continue', child: Row(
                children: [Icon(Icons.play_arrow, size: 18, color: Colors.green), SizedBox(width: 8), Text(AppLocalizations.of(context)!.workoutDetailContinue, style: TextStyle(color: Colors.green))],
              )),
              PopupMenuItem(value: 'edit_date', child: Row(
                children: [Icon(Icons.calendar_today, size: 18), SizedBox(width: 8), Text(AppLocalizations.of(context)!.workoutDetailEditDate)],
              )),
              PopupMenuItem(value: 'delete', child: Row(
                children: [Icon(Icons.delete_outline, size: 18, color: Colors.red), SizedBox(width: 8), Text(AppLocalizations.of(context)!.workoutDetailDelete, style: TextStyle(color: Colors.red))],
              )),
            ],
            onSelected: (v) {
              if (v == 'continue') _continueWorkout();
              if (v == 'edit_date') _editDate();
              if (v == 'delete') _deleteWorkout();
            },
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: () => ExportService().shareWorkoutSummary(widget.workoutId),
            tooltip: AppLocalizations.of(context)!.workoutDetailShare,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: CustomScrollView(
                slivers: [
                  // Header
                  SliverToBoxAdapter(child: _buildHeader(theme)),

                  // Exercises
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _buildExerciseCard(_exercises[index], theme),
                      childCount: _exercises.length,
                    ),
                  ),

                  // Actions
                  SliverToBoxAdapter(child: _buildActions(theme)),
                  const SliverToBoxAdapter(child: SizedBox(height: 40)),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    if (_workout == null) return const SizedBox.shrink();
    final date = DateFormat('EEEE, d \'de\' MMMM \'de\' yyyy', 'pt_BR').format(
      DateTime.parse(_workout!['date'] as String));
    final start = _workout!['start_time'] as String?;
    final end = _workout!['end_time'] as String?;
    final duration = (_workout!['duration_seconds'] as int?) ?? 0;
    final feeling = (_workout!['feeling_rating'] as int?) ?? 0;
    final comment = _workout!['comment'] as String?;

    final isActive = end == null;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(date[0].toUpperCase() + date.substring(1), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Row(
                children: [
                  _InfoChip(icon: Icons.schedule, label: isActive ? AppLocalizations.of(context)!.workoutHomeOngoing : '${duration ~/ 60}min ${duration % 60}s'),
                  const SizedBox(width: 8),
                  _InfoChip(icon: Icons.repeat, label: '$_totalSets sets'),
                  const SizedBox(width: 8),
                  if (_totalVolume > 0)
                    _InfoChip(icon: Icons.monitor_weight, label: '${_totalVolume.toStringAsFixed(0)} kg'),
                ],
              ),
              if (feeling > 0) ...[
                const SizedBox(height: 8),
                Row(
                  children: List.generate(5, (i) => Icon(
                    i < feeling ? Icons.star : Icons.star_border,
                    size: 18, color: Colors.amber,
                  )),
                ),
              ],
              if (comment != null && comment.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(comment, style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant, fontStyle: FontStyle.italic)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExerciseCard(_ExerciseWithSets exercise, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(width: 4, height: 24, decoration: BoxDecoration(
                    color: exercise.categoryColor, borderRadius: BorderRadius.circular(2),
                  )),
                  const SizedBox(width: 10),
                  Text(exercise.name, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  Text(exercise.categoryName, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
              const SizedBox(height: 8),
              if (exercise.sets.isEmpty)
                Text(AppLocalizations.of(context)!.workoutDetailNoSets, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant))
              else ...[
                Row(
                  children: [
                    const SizedBox(width: 34),
                    Expanded(flex: 2, child: Text('#', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600))),
                    Expanded(flex: 3, child: Text(AppLocalizations.of(context)!.workoutDetailWeight, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600))),
                    Expanded(flex: 3, child: Text(AppLocalizations.of(context)!.commonReps, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600))),
                    Expanded(flex: 3, child: Text('RPE', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600))),
                  ],
                ),
                const Divider(height: 4),
                ...exercise.sets.asMap().entries.map((entry) {
                  final i = entry.key;
                  final s = entry.value;
                  final isWarmup = (s['is_warmup'] as int?) == 1;
                  final isComplete = (s['is_complete'] as int?) == 1;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Container(width: 24, height: 24, decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isComplete ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest,
                        ), child: isComplete
                            ? Icon(Icons.check, size: 14, color: theme.colorScheme.onPrimary)
                            : null),
                        const SizedBox(width: 10),
                        Expanded(flex: 2, child: Text(isWarmup ? 'W' : '${i + 1}',
                            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: isWarmup ? Colors.orange : null))),
                        Expanded(flex: 3, child: Text((s['weight'] as num?)?.toStringAsFixed(1) ?? '-', style: theme.textTheme.bodyMedium)),
                        Expanded(flex: 3, child: Text((s['reps'] as int?)?.toString() ?? '-', style: theme.textTheme.bodyMedium)),
                        Expanded(flex: 3, child: Text((s['rpe'] as num?)?.toStringAsFixed(1) ?? '-', style: theme.textTheme.bodyMedium)),
                      ],
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActions(ThemeData theme) {
    final isActive = (_workout?['end_time'] as String?) == null;
    if (!isActive) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        children: [
          FilledButton.icon(
            onPressed: () async {
              final result = await Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => ActiveWorkoutScreen(workoutId: widget.workoutId),
                ),
              );
              if (result == true) _load();
            },
            icon: const Icon(Icons.play_arrow),
            label: Text(AppLocalizations.of(context)!.workoutDetailContinue),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => _deleteWorkout(),
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            label: Text(AppLocalizations.of(context)!.workoutDetailDelete, style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _editDate() async {
    final currentDate = DateTime.parse(_workout!['date'] as String);
    final newDate = await showDatePicker(
      context: context,
      initialDate: currentDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: 'Selecione a nova data',
    );
    if (newDate != null && mounted) {
      await DatabaseHelper.instance.updateWorkoutDate(widget.workoutId, newDate);
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.workoutDetailDateChanged), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  Future<void> _continueWorkout() async {
    await DatabaseHelper.instance.resetWorkoutToInProgress(widget.workoutId);
    if (mounted) {
      final result = await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ActiveWorkoutScreen(workoutId: widget.workoutId),
        ),
      );
      if (mounted) Navigator.pop(context, result ?? true);
    }
  }

  Future<void> _deleteWorkout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.workoutDetailDeleteConfirm),
        content: Text(AppLocalizations.of(context)!.commonActionCannotBeUndone),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppLocalizations.of(context)!.commonCancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppLocalizations.of(context)!.commonDelete, style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _db.deleteWorkout(widget.workoutId);
      if (mounted) Navigator.pop(context, true);
    }
  }
}

class _ExerciseWithSets {
  final String name;
  final String categoryName;
  final Color categoryColor;
  final List<Map<String, dynamic>> sets;
  _ExerciseWithSets({
    required this.name, required this.categoryName,
    required this.categoryColor, required this.sets,
  });
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
