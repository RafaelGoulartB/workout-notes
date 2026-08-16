import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/sleep_entry.dart';
import 'package:workout_notes/models/sleep_night_summary.dart';
import 'package:workout_notes/models/sleep_monitor_session.dart';
import 'package:workout_notes/repositories/sleep_repository.dart';
import 'package:workout_notes/repositories/sleep_monitor_repository.dart';
import 'package:workout_notes/services/sleep_monitor_service.dart';
import 'package:workout_notes/services/sleep_goal_service.dart';

import 'package:workout_notes/widgets/empty_state_placeholder.dart';
import 'package:workout_notes/widgets/ai/ai_coach_header_button.dart';
import 'package:workout_notes/widgets/sleep/sleep_duration_chart.dart';
import 'package:workout_notes/widgets/sleep/sleep_latest_card.dart';
import 'package:workout_notes/widgets/sleep/sleep_goal_metrics_card.dart';

import 'package:workout_notes/widgets/sleep/sleep_schedule_chart.dart';
import 'package:workout_notes/widgets/sleep/sleep_weekly_summary_card.dart';
import 'package:workout_notes/widgets/sleep/sleep_stage_card.dart';

import 'sleep_monitor_result_screen.dart';
import 'sleep_monitor_screen.dart';
import 'traditional_alarms_screen.dart';
import 'settings_screen.dart';

class SleepTrackerScreen extends StatefulWidget {
  const SleepTrackerScreen({super.key});

  @override
  State<SleepTrackerScreen> createState() => _SleepTrackerScreenState();
}

class _SleepTrackerScreenState extends State<SleepTrackerScreen> {
  final _repository = SleepRepository();
  final _monitorRepository = SleepMonitorRepository();
  final _monitorService = SleepMonitorService.instance;
  final _sleepGoalService = SleepGoalService();
  List<SleepEntry> _entries = const [];
  SleepDashboardStats? _stats;
  SleepNightSummary? _latestNight;
  Map<String, SleepNightSummary> _nightSummaries = const {};
  bool _isLoading = true;
  int _historyDisplayCount = 5;
  int _lastRecoveryCount = 0;
  late DateTime _weekEnd;
  bool _isChangingWeek = false;
  int _sleepGoalMinutes = SleepGoalService.defaultGoalMinutes;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _weekEnd = DateTime(now.year, now.month, now.day);
    _monitorService.addListener(_onMonitorChanged);
    _lastRecoveryCount = _monitorService.recoveredCount;
    _bootstrap();
    if (_lastRecoveryCount > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showRecoveryMessage(_lastRecoveryCount);
      });
    }
  }

  @override
  void dispose() {
    _monitorService.removeListener(_onMonitorChanged);
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _monitorService.initialize();
    if (mounted) await _load();
  }

  void _onMonitorChanged() {
    if (mounted) {
      setState(() {});
      if (_monitorService.recoveredCount > _lastRecoveryCount) {
        _lastRecoveryCount = _monitorService.recoveredCount;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showRecoveryMessage(_lastRecoveryCount);
        });
      }
      if (!_monitorService.isMonitoring &&
          (_monitorService.state.status == 'completed' ||
              _monitorService.state.status == 'interrupted')) {
        _load();
      }
    }
  }

  void _showRecoveryMessage(int count) {
    final loc = AppLocalizations.of(context);
    if (loc == null) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(loc.sleepMonitorRecovered(count))));
  }

  Future<void> _load() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      await _monitorRepository.repairSleepEntriesFromSessions();
      final entries = await _repository.getEntries(limit: 500);
      final stats = await _repository.getDashboardStats(
        referenceDate: _weekEnd,
      );
      final sleepGoalMinutes = await _sleepGoalService.load();
      final nightSummaries = await _monitorRepository.getNightSummaries(
        limit: 500,
      );
      final summariesByEntry = {
        for (final summary in nightSummaries) summary.entry.id: summary,
      };
      final latestNight = stats.latest == null
          ? null
          : summariesByEntry[stats.latest!.id];
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _stats = stats;
        _sleepGoalMinutes = sleepGoalMinutes;
        _latestNight = latestNight;
        _nightSummaries = summariesByEntry;
        _historyDisplayCount = 5;
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _formatHeaderDate(),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        centerTitle: false,
        automaticallyImplyLeading: false,
        actions: [
          const AiCoachHeaderButton(),
          IconButton(
            tooltip: 'Alarmes',
            icon: const Icon(Icons.alarm_rounded),
            onPressed: _openTraditionalAlarms,
          ),
          IconButton(
            tooltip: loc.settingsTitle,
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openAppSettings,
          ),
        ],
      ),
      floatingActionButton: _buildMonitorFab(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _entries.isEmpty
                  ? _buildEmptyState(loc)
                  : _buildContent(theme, loc),
            ),
    );
  }

  String _formatHeaderDate() =>
      DateFormat('EEEE, d MMMM', Intl.defaultLocale).format(DateTime.now());

  Widget _buildEmptyState(AppLocalizations loc) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      child: Column(
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * .5,
            child: EmptyStatePlaceholder(
              icon: Icons.nightlight_round,
              title: loc.sleepEmptyTitle,
              subtitle: loc.sleepEmptySubtitle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(ThemeData theme, AppLocalizations loc) {
    final stats = _stats!;
    final weeklyDays = _weeklyDays();
    final latest = stats.latest;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        if (latest != null) ...[
          SleepGoalMetricsCard(
            entry: latest,
            stats: stats,
            goalMinutes: _sleepGoalMinutes,
          ),
          const SizedBox(height: 16),
          SleepLatestCard(entry: latest, onTap: () => _showDetails(latest)),
          if (_latestNight?.session != null) ...[
            const SizedBox(height: 16),
            SleepStageCard(
              session: _latestNight!.session!,
              stages: _latestNight!.stages,
              compact: true,
            ),
          ],
          const SizedBox(height: 16),
        ],
        SleepWeeklySummaryCard(
          stats: stats,
          start: weeklyDays.first,
          end: weeklyDays.last,
        ),
        const SizedBox(height: 12),
        SleepScheduleChart(
          entries: _entries,
          days: weeklyDays,
          onPreviousWeek: _isChangingWeek ? null : () => _changeWeek(-1),
          onNextWeek: _isChangingWeek || !_canGoToNextWeek
              ? null
              : () => _changeWeek(1),
        ),
        const SizedBox(height: 12),
        SleepDurationChart(entries: _entries, days: weeklyDays),
        const SizedBox(height: 12),
        _SleepChartCard(
          title: loc.sleepTrendChart,
          icon: Icons.show_chart_rounded,
          child: _entries.length < 2
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 22),
                  child: Center(
                    child: Text(
                      loc.sleepNeedTwoEntries,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              : _buildTrendChart(theme, loc),
        ),
        const SizedBox(height: 18),
        _buildHistory(theme, loc),
      ],
    );
  }

  Widget? _buildMonitorFab() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return null;
    }
    final isActive = _monitorService.isMonitoring;
    final loc = AppLocalizations.of(context)!;
    final elapsed = _formatElapsed(_monitorService.state.elapsed);
    return FloatingActionButton.extended(
      heroTag: 'sleep-monitor-fab',
      onPressed: _openMonitor,
      icon: Icon(isActive ? Icons.open_in_new_rounded : Icons.nightlight_round),
      label: Text(
        isActive
            ? '${loc.sleepMonitorOpenActive} - $elapsed'
            : loc.sleepMonitorCta,
      ),
    );
  }

  static String _formatElapsed(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  Future<void> _openTraditionalAlarms() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TraditionalAlarmsScreen()),
    );
    if (mounted) await _load();
  }

  Future<void> _openAppSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AppSettingsScreen()),
    );
    if (mounted) await _load();
  }

  bool get _canGoToNextWeek {
    return _weekEnd.isBefore(_dateOnly(DateTime.now()));
  }

  Future<void> _changeWeek(int direction) async {
    if (_isChangingWeek) return;
    final today = _dateOnly(DateTime.now());
    final candidate = _weekEnd.add(Duration(days: direction * 7));
    if (candidate.isAfter(today)) return;

    setState(() => _isChangingWeek = true);
    try {
      final stats = await _repository.getDashboardStats(
        referenceDate: candidate,
      );
      if (!mounted) return;
      setState(() {
        _weekEnd = candidate;
        _stats = stats;
      });
    } finally {
      if (mounted) setState(() => _isChangingWeek = false);
    }
  }

  Widget _buildTrendChart(ThemeData theme, AppLocalizations loc) {
    final end = _dateOnly(DateTime.now());
    final start = end.subtract(const Duration(days: 29));
    final byDate = {
      for (final entry in _entries) _dateString(entry.date): entry,
    };
    final recordedSpots = <FlSpot>[];
    final actualSpots = <FlSpot>[];
    final deepSpots = <FlSpot>[];
    for (var index = 0; index < 30; index++) {
      final date = start.add(Duration(days: index));
      final entry = byDate[_dateString(date)];
      if (entry == null) continue;
      recordedSpots.add(FlSpot(index.toDouble(), entry.sleepMinutes / 60));
      if (entry.actualSleepMinutes != null) {
        actualSpots.add(
          FlSpot(index.toDouble(), entry.actualSleepMinutes! / 60),
        );
      }
      final stageSession = _nightSummaries[entry.id]?.session;
      if (stageSession?.deepSleepMinutes != null &&
          (stageSession?.stageConfidence ?? 0) >= 0.6) {
        deepSpots.add(
          FlSpot(index.toDouble(), stageSession!.deepSleepMinutes! / 60),
        );
      }
    }
    final maxValue = recordedSpots
        .map((spot) => spot.y)
        .fold<double>(8, math.max);

    return Column(
      children: [
        _ChartLegend(
          items: [
            (theme.colorScheme.primary, loc.sleepChartRecorded),
            (Colors.indigo, loc.sleepChartActual),
            if (deepSpots.isNotEmpty)
              (Colors.deepPurple, loc.sleepStageDeepEstimated),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 180,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: 29,
              minY: 0,
              maxY: maxValue + 1,
              gridData: FlGridData(show: true, drawVerticalLine: false),
              borderData: FlBorderData(show: false),
              lineTouchData: const LineTouchData(enabled: true),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    interval: 2,
                    getTitlesWidget: (value, meta) => Text(
                      '${value.toInt()}h',
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    interval: 7,
                    getTitlesWidget: (value, meta) {
                      final date = start.add(Duration(days: value.toInt()));
                      return SideTitleWidget(
                        meta: meta,
                        child: Text(
                          DateFormat('d/M').format(date),
                          style: const TextStyle(fontSize: 10),
                        ),
                      );
                    },
                  ),
                ),
              ),
              lineBarsData: [
                _lineData(recordedSpots, theme.colorScheme.primary),
                if (actualSpots.isNotEmpty)
                  _lineData(actualSpots, Colors.indigo),
                if (deepSpots.isNotEmpty)
                  _lineData(deepSpots, Colors.deepPurple),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHistory(ThemeData theme, AppLocalizations loc) {
    final visibleCount = math.min(_historyDisplayCount, _entries.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.history, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              '${loc.sleepHistory} · ${loc.sleepEntries(_entries.length)}',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ..._entries
            .take(visibleCount)
            .map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _SleepHistoryCard(
                  entry: entry,
                  summary: _nightSummaries[entry.id],
                  loc: loc,
                  onTap: () => _showDetails(entry),
                ),
              ),
            ),
        if (visibleCount < _entries.length)
          Center(
            child: TextButton.icon(
              onPressed: () => setState(() => _historyDisplayCount += 5),
              icon: const Icon(Icons.add),
              label: Text(
                _entries.length - visibleCount > 5
                    ? loc.sleepLoadMore(_entries.length - visibleCount)
                    : loc.sleepLoadMoreCount(_entries.length - visibleCount),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _openMonitor() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SleepMonitorScreen()),
    );
    _load();
  }

  Future<void> _showDetails(SleepEntry entry) async {
    final monitorSession = await _monitorRepository.getSessionForSleepEntry(
      entry.id,
    );
    if (!mounted) return;
    if (monitorSession != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              SleepMonitorResultScreen(sessionId: monitorSession.id),
        ),
      );
      await _load();
      return;
    }
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final mediaQuery = MediaQuery.of(sheetContext);
        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: mediaQuery.size.height * 0.9,
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                0,
                20,
                24 + mediaQuery.viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    loc.sleepDetails,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat.yMMMMd(Intl.defaultLocale).format(entry.date),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (entry.source != 'manual') ...[
                    const SizedBox(height: 10),
                    Chip(
                      avatar: const Icon(Icons.mic_none, size: 18),
                      label: Text(loc.sleepMonitorSource),
                    ),
                  ],
                  const SizedBox(height: 18),
                  _DetailRow(
                    Icons.bedtime_outlined,
                    loc.sleepDuration,
                    _formatMinutes(entry.sleepMinutes, loc),
                  ),
                  _DetailRow(
                    Icons.timelapse_outlined,
                    loc.sleepActualDuration,
                    entry.actualSleepMinutes == null
                        ? loc.sleepNoActual
                        : _formatMinutes(entry.actualSleepMinutes, loc),
                  ),
                  if (entry.bedtimeMinutes != null)
                    _DetailRow(
                      Icons.nightlight_outlined,
                      loc.sleepBedtime,
                      _formatTime(entry.bedtimeMinutes!),
                    ),
                  if (entry.wakeTimeMinutes != null)
                    _DetailRow(
                      Icons.wb_sunny_outlined,
                      loc.sleepWakeTime,
                      _formatTime(entry.wakeTimeMinutes!),
                    ),
                  if (entry.timeInBedMinutes != null)
                    _DetailRow(
                      Icons.bed_outlined,
                      loc.sleepMonitorTimeInBed,
                      '${entry.timeInBedMinutes} min',
                    ),
                  if (entry.comment != null && entry.comment!.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(entry.comment!),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          Navigator.pop(sheetContext);
                          await _deleteEntry(entry);
                        },
                        icon: const Icon(Icons.delete_outline),
                        label: Text(loc.sleepDelete),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _deleteEntry(SleepEntry entry) async {
    final loc = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(loc.sleepDelete),
        content: Text(loc.sleepDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(loc.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(loc.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repository.delete(entry.id);
    if (!mounted) return;
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.sleepDeleted)));
    }
  }

  static LineChartBarData _lineData(List<FlSpot> spots, Color color) =>
      LineChartBarData(
        spots: spots,
        isCurved: true,
        color: color,
        barWidth: 3,
        dotData: const FlDotData(show: true),
        belowBarData: BarAreaData(show: false),
      );

  static String _formatMinutes(int? minutes, AppLocalizations loc) {
    if (minutes == null) return '--';
    return loc.sleepDurationValue(minutes ~/ 60, minutes % 60);
  }

  static String _formatTime(int minutes) {
    final hour = minutes ~/ 60;
    final minute = minutes % 60;
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  List<DateTime> _weeklyDays() {
    return List.generate(
      7,
      (index) => _weekEnd.subtract(Duration(days: 6 - index)),
    );
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static String _dateString(DateTime value) =>
      _dateOnly(value).toIso8601String().substring(0, 10);
}

class _SleepChartCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _SleepChartCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _ChartLegend extends StatelessWidget {
  final List<(Color, String)> items;

  const _ChartLegend({required this.items});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 6,
      children: items
          .map(
            (item) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: item.$1,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(item.$2, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          )
          .toList(),
    );
  }
}

class _SleepHistoryCard extends StatelessWidget {
  final SleepEntry entry;
  final SleepNightSummary? summary;
  final AppLocalizations loc;
  final VoidCallback onTap;

  const _SleepHistoryCard({
    required this.entry,
    required this.summary,
    required this.loc,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 44,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withAlpha(18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Text(
                      DateFormat('dd').format(entry.date),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      DateFormat('MMM').format(entry.date),
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loc.sleepDurationValue(
                        entry.sleepMinutes ~/ 60,
                        entry.sleepMinutes % 60,
                      ),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      entry.actualSleepMinutes == null
                          ? loc.sleepNoActual
                          : '${loc.sleepActualDuration}: ${loc.sleepDurationValue(entry.actualSleepMinutes! ~/ 60, entry.actualSleepMinutes! % 60)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (entry.source != 'manual')
                      Text(
                        loc.sleepMonitorSource,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    if (summary?.hasStages ?? false) ...[
                      const SizedBox(height: 7),
                      _StageMiniComposition(session: summary!.session!),
                      const SizedBox(height: 4),
                      Text(
                        _stageTotals(summary!.session!, loc),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ] else if (summary?.session != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        loc.sleepStageUnavailable,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (entry.efficiency != null)
                Text(
                  '${entry.efficiency!.toStringAsFixed(0)}%',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: Colors.teal,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _StageMiniComposition extends StatelessWidget {
  final SleepMonitorSession session;

  const _StageMiniComposition({required this.session});

  @override
  Widget build(BuildContext context) {
    final awake = session.awakeMinutes ?? 0;
    final sleeping = session.sleepingMinutes ?? 0;
    final deep = session.deepSleepMinutes ?? 0;
    final unknown = session.unknownMinutes ?? 0;
    final total = awake + sleeping + deep + unknown;
    if (total <= 0) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: SizedBox(
        height: 6,
        child: Row(
          children: [
            if (awake > 0)
              Expanded(
                flex: awake,
                child: Container(color: Colors.orange),
              ),
            if (sleeping > 0)
              Expanded(
                flex: sleeping,
                child: Container(color: Colors.lightBlue),
              ),
            if (deep > 0)
              Expanded(
                flex: deep,
                child: Container(color: Colors.indigo),
              ),
            if (unknown > 0)
              Expanded(
                flex: unknown,
                child: Container(color: Colors.grey),
              ),
          ],
        ),
      ),
    );
  }
}

String _stageTotals(SleepMonitorSession session, AppLocalizations loc) {
  final sleeping = session.sleepingMinutes ?? 0;
  final deep = session.deepSleepMinutes ?? 0;
  return '${loc.sleepStageSleeping} ${_compactMinutes(sleeping)} \u00b7 ${loc.sleepStageDeepEstimated} ${_compactMinutes(deep)}';
}

String _compactMinutes(int minutes) =>
    minutes >= 60 ? '${minutes ~/ 60}h ${minutes % 60}min' : '${minutes}min';

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
