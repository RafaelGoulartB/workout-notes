import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/repositories/run_repository.dart';
import 'package:workout_notes/screens/run/run_detail_screen.dart';
import 'package:workout_notes/screens/run/run_history_screen.dart';
import 'package:workout_notes/screens/run/run_record_screen.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/utils/run_progress_analytics.dart';
import 'package:workout_notes/widgets/empty_state_placeholder.dart';
import 'package:workout_notes/widgets/run/run_progress_charts.dart';

class RunStatsScreen extends StatefulWidget {
  const RunStatsScreen({super.key});

  @override
  State<RunStatsScreen> createState() => _RunStatsScreenState();
}

class _RunStatsScreenState extends State<RunStatsScreen> {
  final _repo = RunRepository();
  List<RunActivity> _activities = [];
  bool _loading = true;
  RunStatsPeriod _period = RunStatsPeriod.weeks12;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await _repo.listActivities(limit: 500);
    if (!mounted) return;
    setState(() {
      _activities = rows;
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

  Future<void> _openHistory() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RunHistoryScreen()),
    );
    if (mounted) _load();
  }

  Future<void> _openDetail(String activityId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RunDetailScreen(activityId: activityId),
      ),
    );
    if (mounted) _load();
  }

  Widget _sectionCard({required Widget child}) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }

  Widget _sectionTitle(String text) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
      ),
    );
  }

  String _periodLabel(AppLocalizations loc, RunStatsPeriod period) {
    return switch (period) {
      RunStatsPeriod.weeks4 => loc.runStatsPeriod4Weeks,
      RunStatsPeriod.weeks12 => loc.runStatsPeriod12Weeks,
      RunStatsPeriod.year => loc.runStatsPeriodYear,
      RunStatsPeriod.all => loc.runStatsPeriodAll,
    };
  }

  String _deltaLabel(AppLocalizations loc, double deltaMeters) {
    final abs = RunFormatters.distanceWithUnit(deltaMeters.abs());
    if (deltaMeters > 50) return loc.runStatsWeekUp(abs);
    if (deltaMeters < -50) return loc.runStatsWeekDown(abs);
    return loc.runStatsWeekFlat;
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final analytics = RunProgressAnalytics.fromActivities(
      _activities,
      period: _period,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.runStatsTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: loc.runHistoryTitle,
            onPressed: _openHistory,
          ),
        ],
      ),
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
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    children: [
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final period in RunStatsPeriod.values) ...[
                              if (period != RunStatsPeriod.values.first)
                                const SizedBox(width: 8),
                              ChoiceChip(
                                label: Text(_periodLabel(loc, period)),
                                selected: _period == period,
                                onSelected: (_) {
                                  setState(() => _period = period);
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _sectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              loc.runStatsOverview,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 14),
                            _MetricsGrid(
                              items: [
                                _MetricItem(
                                  label: loc.runRecordDistance,
                                  value: RunFormatters.distanceWithUnit(
                                    analytics.totalDistanceMeters,
                                  ),
                                ),
                                _MetricItem(
                                  label: loc.runStatsRunCount,
                                  value: '${analytics.runCount}',
                                ),
                                _MetricItem(
                                  label: loc.runDetailAvgPace,
                                  value: RunFormatters.paceWithUnit(
                                    analytics.avgPaceSecPerKm,
                                  ),
                                ),
                                _MetricItem(
                                  label: loc.runDetailMovingTime,
                                  value: RunFormatters.duration(
                                    analytics.totalMovingTimeSeconds,
                                  ),
                                ),
                                _MetricItem(
                                  label: loc.runDetailCalories,
                                  value: '${analytics.totalCalories} kcal',
                                ),
                                _MetricItem(
                                  label: loc.runStatsAvgPerWeek,
                                  value: analytics.avgRunsPerWeek
                                      .toStringAsFixed(1),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _sectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _sectionTitle(loc.runStatsThisWeek),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _SummaryTile(
                                    label: loc.runRecordDistance,
                                    value: RunFormatters.distanceWithUnit(
                                      analytics.thisWeekDistanceMeters,
                                    ),
                                    highlight: true,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _SummaryTile(
                                    label: loc.runStatsRunCount,
                                    value: '${analytics.thisWeekRunCount}',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _deltaLabel(
                                loc,
                                analytics.distanceDeltaVsLastWeek,
                              ),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _sectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _sectionTitle(loc.runStatsHighlights),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _SummaryTile(
                                    label: loc.runStatsLongestRun,
                                    value: analytics.longestRun == null
                                        ? '--'
                                        : RunFormatters.distanceWithUnit(
                                            analytics
                                                .longestRun!.distanceMeters,
                                          ),
                                    highlight: true,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _SummaryTile(
                                    label: loc.runStatsBestPace,
                                    value: RunFormatters.paceWithUnit(
                                      analytics.bestPaceSecPerKm,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (analytics.longestRun != null ||
                                analytics.fastestRun != null) ...[
                              const SizedBox(height: 8),
                              if (analytics.longestRun != null)
                                _HighlightLink(
                                  label: loc.runStatsViewLongest,
                                  subtitle: DateFormat.yMMMd(
                                    Localizations.localeOf(context)
                                        .toString(),
                                  ).format(
                                    analytics.longestRun!.startedAt.toLocal(),
                                  ),
                                  onTap: () => _openDetail(
                                    analytics.longestRun!.id,
                                  ),
                                ),
                              if (analytics.fastestRun != null &&
                                  analytics.fastestRun!.id !=
                                      analytics.longestRun?.id)
                                _HighlightLink(
                                  label: loc.runStatsViewFastest,
                                  subtitle: DateFormat.yMMMd(
                                    Localizations.localeOf(context)
                                        .toString(),
                                  ).format(
                                    analytics.fastestRun!.startedAt.toLocal(),
                                  ),
                                  onTap: () => _openDetail(
                                    analytics.fastestRun!.id,
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _sectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _sectionTitle(loc.runStatsWeeklyDistance),
                            const SizedBox(height: 12),
                            RunWeeklyDistanceChart(
                              buckets: analytics.weeklyBuckets,
                              emptyLabel: loc.runStatsChartEmpty,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _sectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _sectionTitle(loc.runStatsPaceTrend),
                            const SizedBox(height: 4),
                            Text(
                              loc.runStatsPaceTrendHint,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 12),
                            RunPaceTrendChart(
                              points: analytics.paceTrend,
                              emptyLabel: loc.runStatsPaceChartEmpty,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _sectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _sectionTitle(loc.runStatsWeeklyFrequency),
                            const SizedBox(height: 12),
                            RunWeeklyFrequencyChart(
                              buckets: analytics.weeklyBuckets,
                              emptyLabel: loc.runStatsChartEmpty,
                            ),
                          ],
                        ),
                      ),
                      if (analytics.activities.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _sectionCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: _sectionTitle(
                                      loc.runStatsRecentRuns,
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: _openHistory,
                                    child: Text(loc.runStatsSeeAll),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              for (final activity in analytics.activities
                                  .reversed
                                  .take(5)) ...[
                                _RecentRunTile(
                                  activity: activity,
                                  onTap: () => _openDetail(activity.id),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
    );
  }
}

class _HighlightLink extends StatelessWidget {
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _HighlightLink({
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(
        label,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _RecentRunTile extends StatelessWidget {
  final RunActivity activity;
  final VoidCallback onTap;

  const _RecentRunTile({required this.activity, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final date = DateFormat.MMMd(
      Localizations.localeOf(context).toString(),
    ).add_Hm().format(activity.startedAt.toLocal());

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Icon(
          Icons.directions_run,
          color: theme.colorScheme.onPrimaryContainer,
          size: 20,
        ),
      ),
      title: Text(
        activity.title?.isNotEmpty == true
            ? activity.title!
            : loc.runDetailUntitled,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '$date · ${RunFormatters.distanceWithUnit(activity.distanceMeters)}',
      ),
      trailing: Text(
        RunFormatters.pace(activity.avgPaceSecPerKm),
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      onTap: onTap,
    );
  }
}

class _MetricItem {
  final String label;
  final String value;

  const _MetricItem({required this.label, required this.value});
}

class _MetricsGrid extends StatelessWidget {
  final List<_MetricItem> items;

  const _MetricsGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final colWidth = (constraints.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in items)
              SizedBox(
                width: colWidth,
                child: _StatChip(label: item.label, value: item.value),
              ),
          ],
        );
      },
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;

  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;

  const _SummaryTile({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = highlight
        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.55)
        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
