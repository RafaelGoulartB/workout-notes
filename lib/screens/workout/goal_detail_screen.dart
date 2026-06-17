import 'package:flutter/material.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/goal.dart';
import 'package:workout_notes/repositories/goal_repository.dart';
import 'package:workout_notes/screens/workout/workout_detail_screen.dart';
import 'package:workout_notes/widgets/goals/goal_contributing_workouts.dart';
import 'package:workout_notes/widgets/goals/goal_form_sheet.dart';
import 'package:workout_notes/widgets/goals/goal_formatters.dart';
import 'package:workout_notes/widgets/goals/goal_progress_ring.dart';

/// Detail screen for a single goal, showing current progress, history, and actions.
class GoalDetailScreen extends StatefulWidget {
  final Goal goal;
  final DatabaseHelper db;

  const GoalDetailScreen({super.key, required this.goal, required this.db});

  @override
  State<GoalDetailScreen> createState() => _GoalDetailScreenState();
}

class _GoalDetailScreenState extends State<GoalDetailScreen> {
  late Goal _goal;
  GoalProgress? _current;
  List<GoalPeriodResult> _history = [];
  List<ContributingWorkout> _contributors = [];
  bool _isLoading = true;
  bool _isKm = true;

  @override
  void initState() {
    super.initState();
    _goal = widget.goal;
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      _isKm = await widget.db.settingsRepo.getIsDistanceKm();
      final repo = GoalRepository();
      final (current, history) = await repo.getProgressWithHistory(_goal, historyCount: 6);
      final contributors = await repo.getContributingWorkouts(_goal);
      if (!mounted) return;
      setState(() {
        _current = current;
        _history = history;
        _contributors = contributors;
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openWorkout(String workoutId) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => WorkoutDetailScreen(workoutId: workoutId),
    ));
  }

  Future<void> _edit() async {
    final saved = await GoalFormSheet.show(context, widget.db.settingsRepo, existing: _goal);
    if (saved == null) return;
    await widget.db.goalRepo.update(saved);
    if (!mounted) return;
    setState(() => _goal = saved);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.goalSaved)),
    );
    await _load();
  }

  Future<void> _togglePause() async {
    final newActive = !_goal.isActive;
    await widget.db.goalRepo.toggleActive(_goal.id, newActive);
    if (!mounted) return;
    setState(() {
      _goal = _goal.copyWith(isActive: newActive);
    });
  }

  Future<void> _delete() async {
    final loc = AppLocalizations.of(context)!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.goalDeleteConfirm),
        content: Text(loc.goalDeleteMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(loc.commonCancel),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(foregroundColor: Colors.red),
            child: Text(loc.commonDelete),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await widget.db.goalRepo.delete(_goal.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(loc.goalDeleted)),
    );
    Navigator.of(context).pop();
  }

  Color _scopeColor(BuildContext context) {
    final theme = Theme.of(context);
    if (_goal.color != null) return Color(_goal.color!);
    return _goal.scope == GoalScope.aerobic
        ? const Color(0xFFE53935)
        : theme.colorScheme.primary;
  }

  IconData _metricIcon() {
    switch (_goal.metric) {
      case GoalMetric.volume:
        return Icons.auto_graph;
      case GoalMetric.days:
        return Icons.calendar_today;
      case GoalMetric.distance:
        return Icons.map;
      case GoalMetric.time:
        return Icons.timer;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final color = _scopeColor(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_goal.title.isNotEmpty
            ? _goal.title
            : _buildDefaultTitle(loc)),
        actions: [
          IconButton(
            icon: Icon(_goal.isActive ? Icons.pause : Icons.play_arrow),
            tooltip: _goal.isActive ? loc.goalPause : loc.goalResume,
            onPressed: _togglePause,
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'edit') _edit();
              if (value == 'delete') _delete();
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'edit', child: Text(loc.goalEditTitle)),
              PopupMenuItem(
                value: 'delete',
                child: Text(loc.goalDelete, style: const TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  _buildHeader(theme, loc, color),
                  const SizedBox(height: 16),
                  _buildCurrentCard(theme, loc, color),
                  const SizedBox(height: 12),
                  GoalContributingWorkouts(
                    workouts: _contributors,
                    goal: _goal,
                    isKm: _isKm,
                    onTapWorkout: _openWorkout,
                  ),
                  const SizedBox(height: 12),
                  _buildHistory(theme, loc, color),
                ],
              ),
            ),
    );
  }

  String _buildDefaultTitle(AppLocalizations loc) {
    final metric = _metricLabel(loc);
    final period = _goal.period == GoalPeriod.weekly
        ? loc.goalPeriodWeekly
        : loc.goalPeriodMonthly;
    return '$metric · $period';
  }

  String _metricLabel(AppLocalizations loc) {
    switch (_goal.metric) {
      case GoalMetric.volume:
        return loc.goalMetricVolume;
      case GoalMetric.days:
        return loc.goalMetricDays;
      case GoalMetric.distance:
        return loc.goalMetricDistance;
      case GoalMetric.time:
        return loc.goalMetricTime;
    }
  }

  Widget _buildHeader(ThemeData theme, AppLocalizations loc, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [color.withAlpha(40), theme.colorScheme.surface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withAlpha(40),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_metricIcon(), color: color, size: 28),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _metricLabel(loc),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                Text(
                  _goal.scope == GoalScope.aerobic
                      ? loc.goalScopeAerobic
                      : loc.goalScopeAnaerobic,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (!_goal.isActive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                loc.goalPausedBadge,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCurrentCard(ThemeData theme, AppLocalizations loc, Color color) {
    final current = _current!;
    final percent = current.percent;
    final isComplete = current.isComplete;
    final isPortuguese = Localizations.localeOf(context).languageCode == 'pt';

    String motivationKey = GoalFormatters.motivation(percent);
    String motivation = _resolveMotivation(loc, motivationKey);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withAlpha(80)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                GoalProgressRing(
                  percent: percent,
                  color: isComplete ? Colors.green : color,
                  size: 120,
                  strokeWidth: 12,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${(percent * 100).clamp(0, 999).toInt()}%',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isComplete ? Colors.green : color,
                        ),
                      ),
                      Text(
                        isComplete ? '✓' : '',
                        style: TextStyle(
                          fontSize: 20,
                          color: isComplete ? Colors.green : color,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        loc.goalCurrentProgress,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${GoalFormatters.formatValue(_goal.metric, current.currentValue, isKm: _isKm)} / ${GoalFormatters.formatValue(_goal.metric, current.targetValue, isKm: _isKm)}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _statRow(
                        theme,
                        Icons.calendar_today,
                        GoalFormatters.periodRangeLabel(
                            _goal.period, current.periodStart, current.periodEnd,
                            isPortuguese: isPortuguese),
                      ),
                      const SizedBox(height: 4),
                      _statRow(
                        theme,
                        Icons.hourglass_bottom,
                        isComplete
                            ? loc.goalCompleted
                            : loc.goalDaysRemaining(current.daysRemaining),
                      ),
                      const SizedBox(height: 4),
                      _statRow(
                        theme,
                        Icons.bolt,
                        motivation,
                        highlight: isComplete,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: percent.clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: color.withAlpha(25),
                valueColor: AlwaysStoppedAnimation<Color>(
                  isComplete ? Colors.green : color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statRow(ThemeData theme, IconData icon, String text, {bool highlight = false}) {
    return Row(
      children: [
        Icon(icon, size: 12, color: highlight ? Colors.green : theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11,
              color: highlight ? Colors.green : theme.colorScheme.onSurface,
              fontWeight: highlight ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }

  String _resolveMotivation(AppLocalizations loc, String key) {
    switch (key) {
      case 'goalMotivationDone':
        return loc.goalMotivationDone;
      case 'goalMotivationNear':
        return loc.goalMotivationNear;
      case 'goalMotivationMid':
        return loc.goalMotivationMid;
      default:
        return loc.goalMotivationEarly;
    }
  }

  Widget _buildHistory(ThemeData theme, AppLocalizations loc, Color color) {
    final isPortuguese = Localizations.localeOf(context).languageCode == 'pt';
    if (_history.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Icon(Icons.history,
                size: 40, color: theme.colorScheme.onSurfaceVariant.withAlpha(100)),
            const SizedBox(height: 8),
            Text(
              loc.goalNoHistory,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              loc.goalNoHistoryHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withAlpha(150),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final completedCount = _history.where((h) => h.wasCompleted).length;
    final rate = (completedCount * 100 / _history.length).round();

    return Card(
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
            Row(
              children: [
                Icon(Icons.history, size: 18, color: theme.colorScheme.onSurface),
                const SizedBox(width: 8),
                Text(
                  loc.goalHistory,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withAlpha(30),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    loc.goalAchievementRate(rate),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ..._history.map((h) => _historyTile(theme, loc, h, color, isPortuguese)),
          ],
        ),
      ),
    );
  }

  Widget _historyTile(ThemeData theme, AppLocalizations loc, GoalPeriodResult h,
      Color color, bool isPortuguese) {
    final isComplete = h.wasCompleted;
    final iconColor = isComplete ? Colors.green : theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: iconColor.withAlpha(30),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isComplete ? Icons.check : Icons.close,
              size: 16,
              color: iconColor,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  GoalFormatters.periodRangeLabel(
                      _goal.period, h.start, h.end,
                      isPortuguese: isPortuguese),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${GoalFormatters.formatValue(_goal.metric, h.value, isKm: _isKm)} / ${GoalFormatters.formatValue(_goal.metric, h.targetValue, isKm: _isKm)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 10,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: h.percent.clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: color.withAlpha(25),
                valueColor: AlwaysStoppedAnimation<Color>(iconColor),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 36,
            child: Text(
              '${(h.percent * 100).clamp(0, 999).toInt()}%',
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: iconColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
