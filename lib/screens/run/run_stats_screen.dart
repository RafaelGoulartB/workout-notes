import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_achievement.dart';
import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/repositories/run_repository.dart';
import 'package:workout_notes/screens/run/run_achievements_screen.dart';
import 'package:workout_notes/screens/run/run_detail_screen.dart';
import 'package:workout_notes/screens/run/run_history_screen.dart';
import 'package:workout_notes/screens/run/run_plans_screen.dart';
import 'package:workout_notes/screens/run/run_record_screen.dart';
import 'package:workout_notes/screens/run/run_voice_settings_screen.dart';
import 'package:workout_notes/utils/run_achievement_engine.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/utils/run_progress_analytics.dart';
import 'package:workout_notes/widgets/empty_state_placeholder.dart';
import 'package:workout_notes/widgets/run/run_achievements_section.dart';
import 'package:workout_notes/widgets/run/run_medal_badge.dart';
import 'package:workout_notes/widgets/run/run_progress_charts.dart';
import 'package:workout_notes/widgets/run/run_week_strip.dart';

/// Which trend chart the single chart card is showing.
enum _RunChartTab { volume, pace, frequency }

class RunStatsScreen extends StatefulWidget {
  const RunStatsScreen({super.key});

  @override
  State<RunStatsScreen> createState() => _RunStatsScreenState();
}

class _RunStatsScreenState extends State<RunStatsScreen> {
  final _repo = RunRepository();
  List<RunActivity> _activities = [];
  RunAchievementBoard _board = RunAchievementBoard.empty;
  bool _loading = true;
  RunStatsPeriod _period = RunStatsPeriod.weeks12;
  _RunChartTab _chartTab = _RunChartTab.volume;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await _repo.backfillMissingEfforts(limit: 60);
    final rows = await _repo.listActivities(limit: 500);
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

  Future<void> _openHistory() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RunHistoryScreen()),
    );
    if (mounted) _load();
  }

  Future<void> _openAchievements() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RunAchievementsScreen()),
    );
    if (mounted) _load();
  }

  Future<void> _openPlans() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RunPlansScreen()),
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

  Widget _sectionCard({required Widget child, EdgeInsets? padding}) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(16),
        child: child,
      ),
    );
  }

  Widget _sectionHeader(String text, {Widget? trailing}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 0, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          ?trailing,
        ],
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

  String? _periodRangeLabel(RunProgressAnalytics analytics) {
    final start = analytics.periodStart;
    if (start == null) return null;
    final locale = Localizations.localeOf(context).toString();
    final format = DateFormat.MMMd(locale);
    return '${format.format(start)} – ${format.format(analytics.now)}';
  }

  // ===================== PERIOD SELECTOR =====================
  Widget _buildPeriodSelector(AppLocalizations loc) {
    return Row(
      children: [
        for (final period in RunStatsPeriod.values) ...[
          if (period != RunStatsPeriod.values.first) const SizedBox(width: 8),
          Expanded(
            child: ChoiceChip(
              // The four periods share the row, so the label scales down
              // instead of being clipped on narrow screens.
              label: SizedBox(
                width: double.infinity,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(_periodLabel(loc, period), maxLines: 1),
                ),
              ),
              labelStyle: Theme.of(context).textTheme.labelMedium,
              labelPadding: EdgeInsets.zero,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
              showCheckmark: false,
              selected: _period == period,
              onSelected: (_) => setState(() => _period = period),
            ),
          ),
        ],
      ],
    );
  }

  // ===================== HERO =====================
  Widget _buildHero(AppLocalizations loc, RunProgressAnalytics analytics) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final divider = colors.outlineVariant.withAlpha(80);
    final ratio = analytics.distanceRatioVsPreviousPeriod;
    final paceDelta = analytics.paceDeltaVsPreviousPeriod;
    final range = _periodRangeLabel(analytics);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colors.surfaceContainerHighest.withAlpha(200),
            colors.surfaceContainerLow,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colors.primary.withAlpha(30),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.directions_run,
                  size: 18,
                  color: colors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loc.runStatsOverview,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (range != null)
                      Text(
                        range,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        RunFormatters.distanceKm(analytics.totalDistanceMeters),
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.0,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'km',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              if (ratio != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _TrendPill(
                    label:
                        '${ratio >= 0 ? '+' : '-'}'
                        '${(ratio.abs() * 100).round()}%',
                    icon: ratio >= 0
                        ? Icons.trending_up_rounded
                        : Icons.trending_down_rounded,
                    positive: ratio >= 0,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            analytics.hasPreviousPeriod
                ? loc.runStatsVsPrevious
                : loc.runStatsNoPrevious,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          Container(height: 1, color: divider),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _HeroMetric(
                  icon: Icons.timer_outlined,
                  color: colors.secondary,
                  label: loc.runRecordTime,
                  value: RunFormatters.duration(
                    analytics.totalMovingTimeSeconds,
                  ),
                ),
              ),
              _HeroDivider(color: divider),
              Expanded(
                child: _HeroMetric(
                  icon: Icons.speed_rounded,
                  color: colors.tertiary,
                  label: loc.runRecordPace,
                  value: RunFormatters.pace(analytics.avgPaceSecPerKm),
                  unit: loc.runRecordPaceUnit,
                ),
              ),
              _HeroDivider(color: divider),
              Expanded(
                child: _HeroMetric(
                  icon: Icons.flag_outlined,
                  color: colors.primary,
                  label: loc.runStatsRunCount,
                  value: '${analytics.runCount}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _HeroMetric(
                  icon: Icons.local_fire_department_outlined,
                  color: Colors.deepOrange,
                  label: loc.runDetailCalories,
                  value: '${analytics.totalCalories}',
                  unit: 'kcal',
                ),
              ),
              _HeroDivider(color: divider),
              Expanded(
                child: _HeroMetric(
                  icon: Icons.calendar_view_week_outlined,
                  color: colors.primary,
                  label: loc.runStatsAvgPerWeek,
                  value: analytics.avgRunsPerWeek.toStringAsFixed(1),
                ),
              ),
              _HeroDivider(color: divider),
              Expanded(
                child: _HeroMetric(
                  icon: Icons.straighten_rounded,
                  color: colors.secondary,
                  label: loc.runStatsAvgPerRun,
                  value: analytics.runCount == 0
                      ? '--'
                      : RunFormatters.distanceKm(
                          analytics.totalDistanceMeters / analytics.runCount,
                        ),
                  unit: analytics.runCount == 0 ? null : 'km',
                ),
              ),
            ],
          ),
          if (paceDelta != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  paceDelta.abs() < 3
                      ? Icons.trending_flat_rounded
                      : paceDelta < 0
                      ? Icons.trending_up_rounded
                      : Icons.trending_down_rounded,
                  size: 16,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    paceDelta.abs() < 3
                        ? loc.runStatsPaceStable
                        : paceDelta < 0
                        ? loc.runStatsPaceFaster(
                            '${paceDelta.abs().round()} s/km',
                          )
                        : loc.runStatsPaceSlower(
                            '${paceDelta.abs().round()} s/km',
                          ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
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

  // ===================== THIS WEEK =====================
  Widget _buildWeekCard(AppLocalizations loc, RunProgressAnalytics analytics) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final ratio = analytics.thisWeekVsAverageRatio;

    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          RunFormatters.distanceKm(
                            analytics.thisWeekDistanceMeters,
                          ),
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'km',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: colors.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      analytics.thisWeekRunCount == 0
                          ? loc.runStatsWeekNoRuns
                          : '${analytics.thisWeekRunCount} '
                                '${loc.runStatsRunCount.toLowerCase()}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (analytics.weekStreak > 0)
                _TrendPill(
                  label: loc.runStatsStreakWeeks(analytics.weekStreak),
                  icon: Icons.local_fire_department_rounded,
                  positive: true,
                ),
            ],
          ),
          const SizedBox(height: 16),
          RunWeekStrip(days: analytics.thisWeekDays, today: analytics.now),
          if (ratio != null) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: ratio.clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: colors.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(
                  ratio >= 1 ? colors.primary : colors.primary.withAlpha(180),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    loc.runStatsWeeklyAverageValue(
                      RunFormatters.distanceWithUnit(
                        analytics.avgWeeklyDistanceMeters,
                      ),
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  loc.runStatsVsWeeklyAverage((ratio * 100).round()),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ratio >= 1
                        ? colors.primary
                        : colors.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Text(
            _deltaLabel(loc, analytics.distanceDeltaVsLastWeek),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  // ===================== PERIOD HIGHLIGHTS =====================
  Widget _buildHighlights(
    AppLocalizations loc,
    RunProgressAnalytics analytics,
  ) {
    final locale = Localizations.localeOf(context).toString();
    final dateFormat = DateFormat.yMMMd(locale);
    final longest = analytics.longestRun;
    final fastest = analytics.fastestRun;
    final bestSplit = analytics.bestKmSplitSecPerKm;
    final theme = Theme.of(context);

    final rows = <Widget>[
      _HighlightRow(
        icon: Icons.straighten_rounded,
        label: loc.runStatsLongestRun,
        value: longest == null
            ? '--'
            : RunFormatters.distanceWithUnit(longest.distanceMeters),
        subtitle: longest == null
            ? null
            : dateFormat.format(longest.startedAt.toLocal()),
        onTap: longest == null ? null : () => _openDetail(longest.id),
      ),
      _HighlightRow(
        icon: Icons.bolt_rounded,
        label: loc.runStatsBestPace,
        value: RunFormatters.paceWithUnit(analytics.bestPaceSecPerKm),
        subtitle: fastest == null
            ? null
            : dateFormat.format(fastest.startedAt.toLocal()),
        onTap: fastest == null ? null : () => _openDetail(fastest.id),
      ),
      if (bestSplit != null)
        _HighlightRow(
          icon: Icons.timer_outlined,
          label: loc.runStatsBestKmSplit,
          value: RunFormatters.paceWithUnit(bestSplit),
        ),
    ];

    return _sectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                color: theme.colorScheme.outlineVariant.withAlpha(70),
              ),
            rows[i],
          ],
        ],
      ),
    );
  }

  // ===================== TRENDS =====================
  Widget _buildTrends(AppLocalizations loc, RunProgressAnalytics analytics) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final caption = switch (_chartTab) {
      _RunChartTab.volume => loc.runStatsChartAverageLegend(
        RunFormatters.distanceWithUnit(analytics.avgWeeklyDistanceMeters),
      ),
      _RunChartTab.pace => loc.runStatsPaceTrendHint,
      _RunChartTab.frequency => loc.runStatsChartAverageLegend(
        analytics.avgRunsPerWeek.toStringAsFixed(1),
      ),
    };

    final chart = switch (_chartTab) {
      _RunChartTab.volume => RunWeeklyDistanceChart(
        buckets: analytics.weeklyBuckets,
        emptyLabel: loc.runStatsChartEmpty,
        averageMeters: analytics.avgWeeklyDistanceMeters,
      ),
      _RunChartTab.pace => RunPaceTrendChart(
        points: analytics.paceTrend,
        emptyLabel: loc.runStatsPaceChartEmpty,
      ),
      _RunChartTab.frequency => RunWeeklyFrequencyChart(
        buckets: analytics.weeklyBuckets,
        emptyLabel: loc.runStatsChartEmpty,
      ),
    };

    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ChartTabBar(
            selected: _chartTab,
            labels: {
              _RunChartTab.volume: loc.runStatsChartTabVolume,
              _RunChartTab.pace: loc.runStatsChartTabPace,
              _RunChartTab.frequency: loc.runStatsChartTabFrequency,
            },
            onChanged: (tab) => setState(() => _chartTab = tab),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // Legend swatch for the dashed average line drawn on the
              // volume chart only.
              if (_chartTab == _RunChartTab.volume)
                Container(
                  width: 14,
                  height: 2,
                  margin: const EdgeInsets.only(right: 6),
                  color: colors.tertiary.withValues(alpha: 0.7),
                ),
              Expanded(
                child: Text(
                  caption,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          chart,
        ],
      ),
    );
  }

  // ===================== RECENT RUNS =====================
  Widget _buildRecentRuns(RunProgressAnalytics analytics) {
    final theme = Theme.of(context);
    final recent = analytics.activities.reversed.take(5).toList();

    return _sectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < recent.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                color: theme.colorScheme.outlineVariant.withAlpha(70),
              ),
            _RecentRunTile(
              activity: recent[i],
              medals: _board.forActivity(recent[i].id),
              onTap: () => _openDetail(recent[i].id),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final analytics = RunProgressAnalytics.fromActivities(
      _activities,
      period: _period,
    );

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.record_voice_over_outlined),
            tooltip: loc.runVoiceSettingsTitle,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const RunVoiceSettingsScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.route_outlined),
            tooltip: loc.runPlansTitle,
            onPressed: _openPlans,
          ),
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
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
                children: [
                  _buildPeriodSelector(loc),
                  const SizedBox(height: 14),
                  _buildHero(
                    loc,
                    analytics,
                  ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.04),
                  _sectionHeader(loc.runStatsSectionThisWeek),
                  _buildWeekCard(
                    loc,
                    analytics,
                  ).animate().fadeIn(duration: 300.ms, delay: 80.ms),
                  _sectionHeader(loc.runStatsSectionHighlights),
                  _buildHighlights(loc, analytics),
                  _sectionHeader(loc.runStatsSectionTrends),
                  _buildTrends(loc, analytics),
                  _sectionHeader(loc.runStatsSectionRecords),
                  Semantics(
                    button: true,
                    label: loc.runAchievementsOpenBoard,
                    child: InkWell(
                      onTap: _openAchievements,
                      borderRadius: BorderRadius.circular(16),
                      child: _sectionCard(
                        child: RunAchievementsSection(
                          board: _board,
                          onOpenActivity: (_) => _openAchievements(),
                          showTitle: false,
                        ),
                      ),
                    ),
                  ),
                  if (analytics.activities.isNotEmpty) ...[
                    _sectionHeader(
                      loc.runStatsSectionRecent,
                      trailing: TextButton(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        onPressed: _openHistory,
                        child: Text(loc.runStatsSeeAll),
                      ),
                    ),
                    _buildRecentRuns(analytics),
                  ],
                ],
              ),
            ),
    );
  }
}

/// Small coloured pill used for period-over-period deltas and streaks.
class _TrendPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool positive;

  const _TrendPill({
    required this.label,
    required this.icon,
    required this.positive,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final color = positive ? colors.primary : colors.error;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroDivider extends StatelessWidget {
  final Color color;

  const _HeroDivider({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 34,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: color,
    );
  }
}

class _HeroMetric extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String? unit;

  const _HeroMetric({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.unit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 4),
              Text(
                value,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: 2),
                Text(
                  unit!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

/// Segmented pill row that swaps the chart shown in the trends card.
class _ChartTabBar extends StatelessWidget {
  final _RunChartTab selected;
  final Map<_RunChartTab, String> labels;
  final ValueChanged<_RunChartTab> onChanged;

  const _ChartTabBar({
    required this.selected,
    required this.labels,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (final tab in _RunChartTab.values)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(9),
                onTap: () => onChanged(tab),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: tab == selected
                        ? colors.primary.withAlpha(45)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      labels[tab] ?? '',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: tab == selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: tab == selected
                            ? colors.primary
                            : colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Period highlight row: icon, label + date, value and an optional chevron.
class _HighlightRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? subtitle;
  final VoidCallback? onTap;

  const _HighlightRow({
    required this.icon,
    required this.label,
    required this.value,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colors.primary.withAlpha(25),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: colors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              value,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (onTap != null)
              Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant)
            else
              const SizedBox(width: 24),
          ],
        ),
      ),
    );
  }
}

class _RecentRunTile extends StatelessWidget {
  final RunActivity activity;
  final List<RunAchievementPlacement> medals;
  final VoidCallback onTap;

  const _RecentRunTile({
    required this.activity,
    required this.medals,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final date = DateFormat.MMMd(
      Localizations.localeOf(context).toString(),
    ).add_Hm().format(activity.startedAt.toLocal());

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.directions_run,
                size: 20,
                color: colors.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          activity.title?.isNotEmpty == true
                              ? activity.title!
                              : loc.runDetailUntitled,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (medals.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        RunMedalDot(tier: medals.first.tier, size: 14),
                      ],
                    ],
                  ),
                  Text(
                    date,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  RunFormatters.distanceWithUnit(activity.distanceMeters),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  RunFormatters.paceWithUnit(activity.avgPaceSecPerKm),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
