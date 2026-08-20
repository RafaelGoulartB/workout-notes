import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_achievement.dart';
import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/repositories/run_repository.dart';
import 'package:workout_notes/screens/run/run_detail_screen.dart';
import 'package:workout_notes/screens/run/run_record_screen.dart';
import 'package:workout_notes/utils/run_achievement_engine.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/utils/run_progress_analytics.dart';
import 'package:workout_notes/widgets/empty_state_placeholder.dart';
import 'package:workout_notes/widgets/run/run_achievements_section.dart';
import 'package:workout_notes/widgets/run/run_medal_badge.dart';

class RunHistoryScreen extends StatefulWidget {
  const RunHistoryScreen({super.key});

  @override
  State<RunHistoryScreen> createState() => _RunHistoryScreenState();
}

class _RunHistoryScreenState extends State<RunHistoryScreen> {
  final _repo = RunRepository();
  List<RunActivity> _activities = [];
  RunAchievementBoard _board = RunAchievementBoard.empty;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await _repo.backfillMissingEfforts(limit: 40);
    final rows = await _repo.listActivities(limit: 100);
    if (!mounted) return;
    setState(() {
      _activities = rows;
      _board = RunAchievementEngine.build(rows);
      _loading = false;
    });
  }

  Future<void> _openRecord() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RunRecordScreen()),
    );
    if (mounted) _load();
  }

  Future<void> _openDetail(RunActivity activity) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RunDetailScreen(activityId: activity.id),
      ),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final analytics = RunProgressAnalytics.fromActivities(
      _activities,
      period: RunStatsPeriod.all,
    );
    final locale = Localizations.localeOf(context).toString();

    return Scaffold(
      appBar: AppBar(title: Text(loc.runHistoryTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openRecord,
        icon: const Icon(Icons.directions_run),
        label: Text(loc.runRecordStart),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _activities.isEmpty
          ? EmptyStatePlaceholder(
              icon: Icons.directions_run,
              title: loc.runHistoryEmptyTitle,
              subtitle: loc.runHistoryEmptySubtitle,
              actionLabel: loc.runHistoryEmptyCta,
              onAction: _openRecord,
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 104),
                children: [
                  _HistoryOverview(
                    analytics: analytics,
                    distanceLabel: loc.runRecordDistance,
                    runsLabel: loc.runStatsRunCount,
                    timeLabel: loc.runDetailMovingTime,
                  ),
                  const SizedBox(height: 28),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Text(
                          loc.runStatsRecentRuns,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      Text(
                        '${analytics.runCount}',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  for (var index = 0; index < _activities.length; index++) ...[
                    if (index == 0 ||
                        _monthKey(_activities[index - 1]) !=
                            _monthKey(_activities[index])) ...[
                      if (index > 0) const SizedBox(height: 20),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8, left: 2),
                        child: Text(
                          DateFormat.yMMMM(
                            locale,
                          ).format(_activities[index].startedAt.toLocal()),
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                    _RunHistoryCard(
                      activity: _activities[index],
                      medals: _board.forActivity(_activities[index].id),
                      locale: locale,
                      titleFallback: loc.runDetailUntitled,
                      paceLabel: loc.runDetailAvgPace,
                      distanceLabel: loc.runRecordDistance,
                      timeLabel: loc.runDetailMovingTime,
                      medalLabelFor: (kind) =>
                          runAchievementKindShortLabel(loc, kind),
                      onTap: () => _openDetail(_activities[index]),
                    ),
                    if (index < _activities.length - 1)
                      const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
    );
  }

  String _monthKey(RunActivity activity) {
    final date = activity.startedAt.toLocal();
    return '${date.year}-${date.month}';
  }
}

class _HistoryOverview extends StatelessWidget {
  final RunProgressAnalytics analytics;
  final String distanceLabel;
  final String runsLabel;
  final String timeLabel;

  const _HistoryOverview({
    required this.analytics,
    required this.distanceLabel,
    required this.runsLabel,
    required this.timeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colors.surfaceContainerHighest.withAlpha(200),
            colors.surfaceContainerLow,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights_outlined, color: colors.primary, size: 18),
              const SizedBox(width: 8),
              Text(
                AppLocalizations.of(context)!.runStatsOverview,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: _OverviewMetric(
                  value: RunFormatters.distanceWithUnit(
                    analytics.totalDistanceMeters,
                  ),
                  label: distanceLabel,
                  prominent: true,
                  foreground: colors.onSurface,
                  mutedForeground: colors.onSurfaceVariant,
                ),
              ),
              _OverviewDivider(color: colors.outlineVariant.withAlpha(80)),
              Expanded(
                child: _OverviewMetric(
                  value: '${analytics.runCount}',
                  label: runsLabel,
                  foreground: colors.onSurface,
                  mutedForeground: colors.onSurfaceVariant,
                ),
              ),
              _OverviewDivider(color: colors.outlineVariant.withAlpha(80)),
              Expanded(
                child: _OverviewMetric(
                  value: RunFormatters.duration(
                    analytics.totalMovingTimeSeconds,
                  ),
                  label: timeLabel,
                  foreground: colors.onSurface,
                  mutedForeground: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OverviewMetric extends StatelessWidget {
  final String value;
  final String label;
  final bool prominent;
  final Color foreground;
  final Color mutedForeground;

  const _OverviewMetric({
    required this.value,
    required this.label,
    required this.foreground,
    required this.mutedForeground,
    this.prominent = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style:
                (prominent
                        ? theme.textTheme.headlineMedium
                        : theme.textTheme.titleLarge)
                    ?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: mutedForeground,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _OverviewDivider extends StatelessWidget {
  final Color color;

  const _OverviewDivider({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: color,
    );
  }
}

class _RunHistoryCard extends StatelessWidget {
  final RunActivity activity;
  final List<RunAchievementPlacement> medals;
  final String locale;
  final String titleFallback;
  final String paceLabel;
  final String distanceLabel;
  final String timeLabel;
  final String Function(RunAchievementKind kind) medalLabelFor;
  final VoidCallback onTap;

  const _RunHistoryCard({
    required this.activity,
    required this.medals,
    required this.locale,
    required this.titleFallback,
    required this.paceLabel,
    required this.distanceLabel,
    required this.timeLabel,
    required this.medalLabelFor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final date = DateFormat(
      'EEE, d MMM · HH:mm',
      locale,
    ).format(activity.startedAt.toLocal());
    final title = activity.title?.isNotEmpty == true
        ? activity.title!
        : titleFallback;

    return Card(
      margin: EdgeInsets.zero,
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 13),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.directions_run_rounded,
                      color: colors.onPrimaryContainer,
                      size: 23,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          date,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (medals.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          RunMedalBadgeRow(
                            placements: medals,
                            labelFor: medalLabelFor,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _PaceBadge(
                    label: paceLabel,
                    value: RunFormatters.pace(activity.avgPaceSecPerKm),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Divider(
                height: 1,
                color: colors.outlineVariant.withValues(alpha: 0.45),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _RunMetric(
                      icon: Icons.straighten_rounded,
                      label: distanceLabel,
                      value: RunFormatters.distanceWithUnit(
                        activity.distanceMeters,
                      ),
                    ),
                  ),
                  Expanded(
                    child: _RunMetric(
                      icon: Icons.timer_outlined,
                      label: timeLabel,
                      value: RunFormatters.duration(activity.movingTimeSeconds),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colors.onSurfaceVariant,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaceBadge extends StatelessWidget {
  final String label;
  final String value;

  const _PaceBadge({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            '$value /km',
            style: theme.textTheme.titleSmall?.copyWith(
              color: colors.primary,
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _RunMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _RunMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Row(
      children: [
        Icon(icon, size: 17, color: colors.primary),
        const SizedBox(width: 7),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontSize: 10,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
