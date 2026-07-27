import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/sleep_entry.dart';
import 'package:workout_notes/models/sleep_monitor_segment.dart';
import 'package:workout_notes/repositories/sleep_repository.dart';
import 'package:workout_notes/repositories/sleep_monitor_repository.dart';
import 'package:workout_notes/services/sleep_monitor_service.dart';
import 'package:workout_notes/widgets/empty_state_placeholder.dart';

import 'sleep_entry_sheet.dart';
import 'sleep_monitor_result_screen.dart';
import 'sleep_monitor_screen.dart';

class SleepTrackerScreen extends StatefulWidget {
  const SleepTrackerScreen({super.key});

  @override
  State<SleepTrackerScreen> createState() => _SleepTrackerScreenState();
}

class _SleepTrackerScreenState extends State<SleepTrackerScreen> {
  final _repository = SleepRepository();
  final _monitorRepository = SleepMonitorRepository();
  final _monitorService = SleepMonitorService.instance;
  List<SleepEntry> _entries = const [];
  SleepDashboardStats? _stats;
  bool _isLoading = true;
  int _historyDisplayCount = 5;
  int _lastRecoveryCount = 0;

  @override
  void initState() {
    super.initState();
    _monitorService.addListener(_onMonitorChanged);
    _lastRecoveryCount = _monitorService.recoveredCount;
    _monitorService.initialize();
    if (_lastRecoveryCount > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showRecoveryMessage(_lastRecoveryCount);
      });
    }
    _load();
  }

  @override
  void dispose() {
    _monitorService.removeListener(_onMonitorChanged);
    super.dispose();
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
      final entries = await _repository.getEntries(limit: 500);
      final stats = await _repository.getDashboardStats();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _stats = stats;
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
      appBar: AppBar(title: Text(loc.sleepTitle), centerTitle: true),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _entries.isEmpty
                  ? _buildEmptyState(loc)
                  : _buildContent(theme, loc),
            ),
      floatingActionButton: _isLoading
          ? null
          : FloatingActionButton.extended(
              onPressed: _openAdd,
              icon: const Icon(Icons.add),
              label: Text(loc.sleepAdd),
            ),
    );
  }

  Widget _buildEmptyState(AppLocalizations loc) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        children: [
          if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) ...[
            _buildMonitorCta(loc),
            const SizedBox(height: 16),
          ],
          SizedBox(
            height: MediaQuery.sizeOf(context).height * .58,
            child: EmptyStatePlaceholder(
              icon: Icons.nightlight_round,
              title: loc.sleepEmptyTitle,
              subtitle: loc.sleepEmptySubtitle,
              actionLabel: loc.sleepAdd,
              onAction: _openAdd,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(ThemeData theme, AppLocalizations loc) {
    final stats = _stats!;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) ...[
          _buildMonitorCta(loc),
          const SizedBox(height: 12),
        ],
        _LatestSleepCard(
          entry: stats.latest,
          loc: loc,
        ).animate().fadeIn(duration: 350.ms),
        const SizedBox(height: 12),
        _buildMetricGrid(theme, stats, loc),
        const SizedBox(height: 16),
        _SleepChartCard(
          title: loc.sleepDailyChart,
          icon: Icons.bar_chart_rounded,
          child: _buildDailyChart(theme, loc),
        ),
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
        const SizedBox(height: 16),
        _buildHistory(theme, loc),
      ],
    );
  }

  Widget _buildMonitorCta(AppLocalizations loc) {
    final active = _monitorService.isMonitoring;
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: ListTile(
        leading: Icon(active ? Icons.graphic_eq : Icons.mic_none),
        title: Text(
          active ? loc.sleepMonitorRunning : loc.sleepMonitorCta,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          active ? loc.sleepMonitorOpenActive : loc.sleepMonitorCtaSubtitle,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: _openMonitor,
      ),
    );
  }

  Widget _buildMetricGrid(
    ThemeData theme,
    SleepDashboardStats stats,
    AppLocalizations loc,
  ) {
    final cards = [
      _MetricData(
        loc.sleepAverage7Days,
        _formatMinutes(stats.average7Days?.round(), loc),
        Icons.calendar_view_week_outlined,
        theme.colorScheme.primary,
      ),
      _MetricData(
        loc.sleepAverage30Days,
        _formatMinutes(stats.average30Days?.round(), loc),
        Icons.calendar_month_outlined,
        theme.colorScheme.secondary,
      ),
      _MetricData(
        loc.sleepActualAverage,
        _formatMinutes(stats.actualAverage30Days?.round(), loc),
        Icons.bedtime_outlined,
        Colors.indigo,
      ),
      _MetricData(
        loc.sleepConsistency,
        loc.sleepDaysRecorded(stats.recordedDays30Days, 30),
        Icons.event_available_outlined,
        Colors.green,
      ),
      _MetricData(
        loc.sleepEfficiency,
        stats.efficiency30Days == null
            ? '--'
            : '${stats.efficiency30Days!.toStringAsFixed(0)}%',
        Icons.speed_outlined,
        Colors.teal,
      ),
      _MetricData(
        loc.sleepMinimum,
        _formatMinutes(stats.minimum30Days, loc),
        Icons.arrow_downward_rounded,
        Colors.deepOrange,
      ),
      _MetricData(
        loc.sleepMaximum,
        _formatMinutes(stats.maximum30Days, loc),
        Icons.arrow_upward_rounded,
        Colors.purple,
      ),
    ];
    return GridView.builder(
      itemCount: cards.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.8,
      ),
      itemBuilder: (context, index) => _MetricCard(data: cards[index]),
    );
  }

  Widget _buildDailyChart(ThemeData theme, AppLocalizations loc) {
    final today = _dateOnly(DateTime.now());
    final byDate = {
      for (final entry in _entries) _dateString(entry.date): entry,
    };
    final days = List.generate(
      7,
      (index) => today.subtract(Duration(days: 6 - index)),
    );
    final groups = <BarChartGroupData>[];
    var maxHours = 0.0;
    for (var index = 0; index < days.length; index++) {
      final entry = byDate[_dateString(days[index])];
      final recorded = entry == null ? null : entry.sleepMinutes / 60;
      final actual = entry?.actualSleepMinutes == null
          ? null
          : entry!.actualSleepMinutes! / 60;
      maxHours = math.max(maxHours, math.max(recorded ?? 0, actual ?? 0));
      final rods = <BarChartRodData>[];
      if (recorded != null) {
        rods.add(_barRod(recorded, theme.colorScheme.primary));
      }
      if (actual != null) {
        rods.add(_barRod(actual, Colors.indigo));
      }
      groups.add(BarChartGroupData(x: index, barRods: rods));
    }

    return Column(
      children: [
        _ChartLegend(
          items: [
            (theme.colorScheme.primary, loc.sleepChartRecorded),
            (Colors.indigo, loc.sleepChartActual),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 210,
          child: BarChart(
            BarChartData(
              maxY: math.max(8, maxHours + 1),
              minY: 0,
              alignment: BarChartAlignment.spaceAround,
              barGroups: groups,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: 2,
              ),
              borderData: FlBorderData(show: false),
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
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index < 0 || index >= days.length) {
                        return const SizedBox();
                      }
                      return SideTitleWidget(
                        meta: meta,
                        child: Text(
                          DateFormat(
                            'E',
                            Intl.defaultLocale,
                          ).format(days[index]).substring(0, 1),
                          style: const TextStyle(fontSize: 11),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTrendChart(ThemeData theme, AppLocalizations loc) {
    final end = _dateOnly(DateTime.now());
    final start = end.subtract(const Duration(days: 29));
    final byDate = {
      for (final entry in _entries) _dateString(entry.date): entry,
    };
    final recordedSpots = <FlSpot>[];
    final actualSpots = <FlSpot>[];
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
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 220,
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

  Future<void> _openAdd() async {
    await showSleepEntrySheet(context, repository: _repository, onSaved: _load);
  }

  Future<void> _openMonitor() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SleepMonitorScreen()),
    );
    _load();
  }

  Future<void> _showDetails(SleepEntry entry) async {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final monitorSession = await _monitorRepository.getSessionForSleepEntry(
      entry.id,
    );
    final monitorSegments = monitorSession == null
        ? const <SleepMonitorSegment>[]
        : await _monitorRepository.getSegments(monitorSession.id);
    if (!mounted) return;
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
                  if (entry.source != 'manual' || monitorSession != null) ...[
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
                  if (monitorSession != null) ...[
                    _DetailRow(
                      Icons.volume_off_outlined,
                      loc.sleepMonitorQuietPeriod,
                      '${monitorSession.quietMinutes ?? 0} min',
                    ),
                    _DetailRow(
                      Icons.volume_up_outlined,
                      loc.sleepMonitorNoisyPeriod,
                      '${monitorSession.noisyMinutes ?? 0} min',
                    ),
                    const SizedBox(height: 8),
                    SleepMonitorTimeline(segments: monitorSegments),
                    const SizedBox(height: 8),
                  ],
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
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        onPressed: () async {
                          Navigator.pop(sheetContext);
                          await showSleepEntrySheet(
                            context,
                            repository: _repository,
                            existing: entry,
                            onSaved: _load,
                          );
                        },
                        icon: const Icon(Icons.edit_outlined),
                        label: Text(loc.sleepEdit),
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

  static BarChartRodData _barRod(double value, Color color) => BarChartRodData(
    toY: value,
    width: 9,
    color: color,
    borderRadius: BorderRadius.circular(3),
  );

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

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static String _dateString(DateTime value) =>
      _dateOnly(value).toIso8601String().substring(0, 10);
}

class _LatestSleepCard extends StatelessWidget {
  final SleepEntry? entry;
  final AppLocalizations loc;

  const _LatestSleepCard({required this.entry, required this.loc});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    return Card(
      color: color.withAlpha(18),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withAlpha(24),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.nightlight_round, color: color, size: 30),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(loc.sleepLatest, style: theme.textTheme.labelLarge),
                  const SizedBox(height: 4),
                  Text(
                    entry == null
                        ? '--'
                        : loc.sleepDurationValue(
                            entry!.sleepMinutes ~/ 60,
                            entry!.sleepMinutes % 60,
                          ),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (entry != null)
                    Text(
                      DateFormat.yMMMd(Intl.defaultLocale).format(entry!.date),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (entry?.actualSleepMinutes != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    loc.sleepActualDuration,
                    style: theme.textTheme.labelSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    loc.sleepDurationValue(
                      entry!.actualSleepMinutes! ~/ 60,
                      entry!.actualSleepMinutes! % 60,
                    ),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.indigo,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _MetricData {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _MetricData(this.label, this.value, this.icon, this.color);
}

class _MetricCard extends StatelessWidget {
  final _MetricData data;

  const _MetricCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(data.icon, color: data.color, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    data.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    data.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
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
  final AppLocalizations loc;
  final VoidCallback onTap;

  const _SleepHistoryCard({
    required this.entry,
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
