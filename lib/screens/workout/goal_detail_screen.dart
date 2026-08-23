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

/// Detail screen for a single goal: current period progress with pacing,
/// the workouts that fed it, and how previous periods ended.
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
      final (current, history) =
          await repo.getProgressWithHistory(_goal, historyCount: 6);
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
    final saved = await GoalFormSheet.show(
      context,
      widget.db.settingsRepo,
      existing: _goal,
    );
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

  String _buildDefaultTitle(AppLocalizations loc) {
    final metric = _metricLabel(loc);
    final period = _goal.period == GoalPeriod.weekly
        ? loc.goalPeriodWeekly
        : loc.goalPeriodMonthly;
    return '$metric · $period';
  }

  String _short(double value) =>
      GoalFormatters.formatValueShort(_goal.metric, value, isKm: _isKm);

  String _full(double value) =>
      GoalFormatters.formatValue(_goal.metric, value, isKm: _isKm);

  /// Consecutive completed periods, newest first, counting the current one
  /// only once it is already complete (an open period never breaks a streak).
  int get _streak {
    var streak = (_current?.isComplete ?? false) ? 1 : 0;
    for (final period in _history) {
      if (!period.wasCompleted) break;
      streak++;
    }
    return streak;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final color = _scopeColor(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _goal.title.isNotEmpty ? _goal.title : _buildDefaultTitle(loc),
        ),
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
                child: Text(
                  loc.goalDelete,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading || _current == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  _buildHero(theme, loc, color),
                  _sectionHeader(theme, loc.goalPaceTitle),
                  _buildPaceCard(theme, loc, color),
                  _sectionHeader(theme, loc.goalContributingWorkouts),
                  GoalContributingWorkouts(
                    workouts: _contributors,
                    goal: _goal,
                    isKm: _isKm,
                    onTapWorkout: _openWorkout,
                    showHeader: false,
                  ),
                  _sectionHeader(theme, loc.goalHistory),
                  _buildHistory(theme, loc, color),
                ],
              ),
            ),
    );
  }

  Widget _sectionHeader(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  // ===================== HERO =====================
  Widget _buildHero(ThemeData theme, AppLocalizations loc, Color color) {
    final current = _current!;
    final percent = current.percent;
    final isComplete = current.isComplete;
    final isPortuguese = Localizations.localeOf(context).languageCode == 'pt';
    final accent = isComplete ? const Color(0xFF43A047) : color;
    final totalDays =
        current.periodEnd.difference(current.periodStart).inDays + 1;
    final elapsed = current.daysElapsed.clamp(1, totalDays);
    final periodLabel = _goal.period == GoalPeriod.weekly
        ? loc.goalPeriodWeekly
        : loc.goalPeriodMonthly;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [accent.withAlpha(38), theme.colorScheme.surfaceContainerLow],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: accent.withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accent.withAlpha(40),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_metricIcon(), color: accent, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${_metricLabel(loc)} · $periodLabel · '
                  '${_goal.scope == GoalScope.aerobic ? loc.goalScopeAerobic : loc.goalScopeAnaerobic}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _StatusPill(
                label: !_goal.isActive
                    ? loc.goalPausedBadge
                    : isComplete
                        ? loc.goalStatusAchieved
                        : loc.goalStatusInProgress,
                color: !_goal.isActive
                    ? theme.colorScheme.onSurfaceVariant
                    : isComplete
                        ? const Color(0xFF43A047)
                        : color,
                icon: !_goal.isActive
                    ? Icons.pause_rounded
                    : isComplete
                        ? Icons.emoji_events_rounded
                        : Icons.schedule_rounded,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              GoalProgressRing(
                percent: percent,
                color: accent,
                size: 96,
                strokeWidth: 10,
                child: Text(
                  '${(percent * 100).clamp(0, 999).toInt()}%',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      loc.goalCurrentProgress,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${_full(current.currentValue)} / '
                        '${_full(current.targetValue)}',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _InfoRow(
                      icon: Icons.event_outlined,
                      text: GoalFormatters.periodRangeLabel(
                        _goal.period,
                        current.periodStart,
                        current.periodEnd,
                        isPortuguese: isPortuguese,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _InfoRow(
                      icon: Icons.hourglass_bottom_rounded,
                      text: '${loc.goalPeriodDayOfTotal(elapsed, totalDays)}'
                          ' · ${loc.goalDaysRemaining(current.daysRemaining)}',
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: percent.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: accent.withAlpha(30),
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
          if (!isComplete) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.bolt, size: 14, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _resolveMotivation(
                      loc,
                      GoalFormatters.motivation(percent),
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ===================== PACE =====================
  Widget _buildPaceCard(ThemeData theme, AppLocalizations loc, Color color) {
    final current = _current!;
    final isComplete = current.isComplete;
    final remaining =
        (current.targetValue - current.currentValue).clamp(0.0, double.infinity);
    final surplus =
        (current.currentValue - current.targetValue).clamp(0.0, double.infinity);
    final totalDays =
        current.periodEnd.difference(current.periodStart).inDays + 1;
    final elapsed = current.daysElapsed.clamp(1, totalDays);
    // Today still counts toward the goal, so it is part of the days left.
    final daysLeftInclusive = (totalDays - elapsed + 1).clamp(1, totalDays);
    final neededPerDay = remaining / daysLeftInclusive;
    final projection = current.currentValue / elapsed * totalDays;
    final onTrack = projection + 0.0001 >= current.targetValue;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: !isComplete
                  ? _PaceTile(
                      icon: Icons.flag_outlined,
                      label: loc.goalRemainingLabel,
                      value: _short(remaining),
                      color: color,
                    )
                  : surplus > 0
                      // Only worth a number when the period actually went
                      // past the target.
                      ? _PaceTile(
                          icon: Icons.emoji_events_outlined,
                          label: loc.goalSurplusLabel,
                          value: '+${_short(surplus)}',
                          color: const Color(0xFF43A047),
                        )
                      : _PaceTile(
                          icon: Icons.emoji_events_outlined,
                          label: loc.goalStatusAchieved,
                          value: '100%',
                          color: const Color(0xFF43A047),
                        ),
            ),
            _PaceDivider(theme: theme),
            Expanded(
              child: _goal.metric == GoalMetric.days
                  ? _PaceTile(
                      icon: Icons.today_outlined,
                      label: loc.goalDaysLeftLabel,
                      // Same count the header shows, so the two never disagree.
                      value: '${current.daysRemaining}',
                      color: theme.colorScheme.onSurface,
                    )
                  : _PaceTile(
                      icon: Icons.speed_outlined,
                      label: loc.goalPerDayLabel,
                      value: isComplete ? '—' : _short(neededPerDay),
                      color: theme.colorScheme.onSurface,
                    ),
            ),
            _PaceDivider(theme: theme),
            Expanded(
              child: _PaceTile(
                icon: onTrack
                    ? Icons.trending_up_rounded
                    : Icons.trending_down_rounded,
                label: loc.goalProjectionLabel,
                value: _short(projection),
                color: onTrack ? const Color(0xFF43A047) : Colors.orange,
              ),
            ),
          ],
        ),
      ),
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

  // ===================== HISTORY =====================
  Widget _buildHistory(ThemeData theme, AppLocalizations loc, Color color) {
    final isPortuguese = Localizations.localeOf(context).languageCode == 'pt';
    if (_history.isEmpty) {
      return Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side:
              BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          child: Column(
            children: [
              Icon(
                Icons.history,
                size: 36,
                color: theme.colorScheme.onSurfaceVariant.withAlpha(100),
              ),
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
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withAlpha(150),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final completedCount = _history.where((h) => h.wasCompleted).length;
    final rate = (completedCount * 100 / _history.length).round();
    final streak = _streak;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _StatusPill(
                        label: loc.goalAchievementRate(rate),
                        color: rate >= 50
                            ? const Color(0xFF43A047)
                            : theme.colorScheme.onSurfaceVariant,
                        icon: Icons.percent_rounded,
                      ),
                      if (streak > 0)
                        _StatusPill(
                          label: loc.goalStreakPeriods(streak),
                          color: Colors.deepOrange,
                          icon: Icons.local_fire_department_rounded,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (var i = 0; i < _history.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  color: theme.colorScheme.outlineVariant.withAlpha(60),
                ),
              _historyTile(theme, _history[i], color, isPortuguese),
            ],
          ],
        ),
      ),
    );
  }

  Widget _historyTile(
    ThemeData theme,
    GoalPeriodResult h,
    Color color,
    bool isPortuguese,
  ) {
    final isComplete = h.wasCompleted;
    final iconColor =
        isComplete ? const Color(0xFF43A047) : theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: iconColor.withAlpha(30),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isComplete ? Icons.check_rounded : Icons.close_rounded,
              size: 15,
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
                    _goal.period,
                    h.start,
                    h.end,
                    isPortuguese: isPortuguese,
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_full(h.value)} / ${_full(h.targetValue)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 64,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
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
            width: 38,
            child: Text(
              '${(h.percent * 100).clamp(0, 999).toInt()}%',
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: iconColor,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;

  const _StatusPill({
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 13, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 12,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}

class _PaceDivider extends StatelessWidget {
  final ThemeData theme;

  const _PaceDivider({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: theme.colorScheme.outlineVariant.withAlpha(80),
    );
  }
}

class _PaceTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _PaceTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            fontSize: 10.5,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
