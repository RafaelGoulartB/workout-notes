import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/repositories/analytics_repository.dart';
import 'package:workout_notes/utils/progress_helpers.dart';
import 'package:workout_notes/widgets/progress/progress_stat_cards.dart';
import '../../screens/workout/workout_detail_screen.dart';

/// Modal bottom sheet showing exercise detail chart & history.
class ExerciseDetailSheet extends StatefulWidget {
  final String exerciseId;
  final String exerciseName;
  final AnalyticsRepository analytics;

  const ExerciseDetailSheet({
    super.key,
    required this.exerciseId,
    required this.exerciseName,
    required this.analytics,
  });

  @override
  State<ExerciseDetailSheet> createState() => _ExerciseDetailSheetState();
}

class _ExerciseDetailSheetState extends State<ExerciseDetailSheet> {
  Map<String, dynamic>? _history;
  bool _isLoading = true;
  int _chartType = 0;

  List<String> _chartTypes(AppLocalizations loc) => [
        loc.exerciseDetailChart1RM,
        loc.exerciseDetailChartMaxWeight,
        loc.exerciseDetailChartVolume,
        loc.exerciseDetailChartTotalReps,
      ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data =
        await widget.analytics.getExerciseHistory(widget.exerciseId, limit: 30);
    if (!mounted) return;
    setState(() {
      _history = data;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollController) {
        return Padding(
          padding: EdgeInsets.only(bottom: bottom),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withAlpha(80),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Title
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.exerciseName,
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              if (_isLoading)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_history == null)
                Expanded(
                  child: Center(
                    child: Text(AppLocalizations.of(context)!.progressLoadError),
                  ),
                )
              else
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    child: _buildDetailContent(theme, loc),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailContent(ThemeData theme, AppLocalizations loc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Chart type selector
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: List.generate(_chartTypes(loc).length, (i) {
              final isSelected = _chartType == i;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(_chartTypes(loc)[i],
                      style: TextStyle(fontSize: 12)),
                  selected: isSelected,
                  onSelected: (_) => setState(() => _chartType = i),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 12),

        // Records
        _buildRecords(theme),
        const SizedBox(height: 16),

        // Chart
        _buildChart(theme),
        const SizedBox(height: 16),

        // History
        _buildHistorySection(theme),
      ],
    );
  }

  Widget _buildRecords(ThemeData theme) {
    final bestWeight = (_history!['best_weight'] as double?) ?? 0;
    final bestVolume = (_history!['best_volume'] as double?) ?? 0;
    final best1RM = (_history!['best_1rm'] as double?) ?? 0;

    return Row(
      children: [
        Expanded(
          child: ProgressStatCard(
            label: AppLocalizations.of(context)!.exerciseDetailChartMaxWeight,
            value: bestWeight > 0 ? bestWeight.toStringAsFixed(1) : '--',
            icon: Icons.monitor_weight,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ProgressStatCard(
            label: AppLocalizations.of(context)!.commonVolume,
            value: bestVolume > 0 ? formatVolume(bestVolume) : '--',
            icon: Icons.auto_graph,
            color: theme.colorScheme.secondary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ProgressStatCard(
            label: AppLocalizations.of(context)!.exerciseDetailChart1RM,
            value: best1RM > 0 ? best1RM.toStringAsFixed(1) : '--',
            icon: Icons.emoji_events,
            color: Colors.amber,
          ),
        ),
      ],
    );
  }

  Widget _buildChart(ThemeData theme) {
    final history = _history!['history'] as List? ?? [];

    String title;
    List<double> values;

    switch (_chartType) {
      case 0:
        title =
            '${AppLocalizations.of(context)!.exerciseDetailChart1RM} ${AppLocalizations.of(context)!.progressChartTitleProgress}';
        values = history
            .map((h) => (h['estimated_1rm'] as double?) ?? 0)
            .toList();
        break;
      case 1:
        title = AppLocalizations.of(context)!.exerciseDetailChartMaxWeight;
        values = history
            .map((h) => (h['max_weight'] as double?) ?? 0)
            .toList();
        break;
      case 2:
        title =
            AppLocalizations.of(context)!.progressChartTitleVolumePerWorkout;
        values = history
            .map((h) => (h['total_volume'] as double?) ?? 0)
            .toList();
        break;
      case 3:
        title =
            AppLocalizations.of(context)!.progressChartTitleRepsPerWorkout;
        values = history
            .map((h) => (h['total_reps'] as int?)?.toDouble() ?? 0)
            .toList();
        break;
      default:
        return const SizedBox.shrink();
    }

    final maxVal = values.fold<double>(0, (a, b) => a > b ? a : b);
    final minVal = values.isNotEmpty
        ? values.fold<double>(values.first, (a, b) => a < b ? a : b)
        : 0;

    if (history.isEmpty || maxVal <= 0) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
              color: theme.colorScheme.outlineVariant.withAlpha(80)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Icon(Icons.bar_chart_outlined,
                  size: 48,
                  color: theme.colorScheme.onSurfaceVariant.withAlpha(80)),
              const SizedBox(height: 12),
              Text(
                AppLocalizations.of(context)!.progressNoChartData,
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    final range = maxVal - minVal;
    final interval = niceInterval(range);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                Text(
                  '${history.length} ${AppLocalizations.of(context)!.progressWorkouts.toLowerCase()}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 220,
              child: LineChart(
                LineChartData(
                  minY: minVal > 0 ? minVal * 0.9 : 0,
                  maxY: maxVal * 1.05,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: interval,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color:
                          theme.colorScheme.outlineVariant.withAlpha(60),
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 44,
                        interval: interval,
                        getTitlesWidget: (v, _) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Text(
                              _chartType == 3
                                  ? v.toInt().toString()
                                  : v.toStringAsFixed(1),
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(fontSize: 10),
                            ),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        interval: history.length > 15 ? 2 : 1,
                        getTitlesWidget: (v, _) {
                          final idx = v.toInt();
                          if (idx < 0 || idx >= history.length) {
                            return const SizedBox.shrink();
                          }
                          final date = history[idx]['date'] as String? ?? '';
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              date.length >= 10 ? date.substring(5) : date,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(fontSize: 9),
                            ),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: values.asMap().entries.map((e) =>
                          FlSpot(e.key.toDouble(), e.value)).toList(),
                      isCurved: true,
                      color: _chartType == 0
                          ? Colors.amber
                          : _chartType == 2
                              ? theme.colorScheme.secondary
                              : theme.colorScheme.primary,
                      barWidth: 3,
                      dotData: FlDotData(
                        show: history.length <= 30,
                        getDotPainter: (spot, percent, bar, index) =>
                            FlDotCirclePainter(
                          radius: 4,
                          color: _chartType == 0
                              ? Colors.amber
                              : _chartType == 2
                                  ? theme.colorScheme.secondary
                                  : theme.colorScheme.primary,
                        ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        color: (_chartType == 0
                                ? Colors.amber
                                : _chartType == 2
                                    ? theme.colorScheme.secondary
                                    : theme.colorScheme.primary)
                            .withAlpha(30),
                      ),
                    ),
                  ],
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (touchedSpots) =>
                          touchedSpots.map((spot) {
                        final idx = spot.spotIndex;
                        final date = idx < history.length
                            ? (history[idx]['date'] as String? ?? '')
                            : '';
                        return LineTooltipItem(
                          '$date\n${spot.y.toStringAsFixed(1)}',
                          TextStyle(
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistorySection(ThemeData theme) {
    final history = _history!['history'] as List? ?? [];
    if (history.isEmpty) return const SizedBox.shrink();

    final loc = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          loc.progressHistoryTitle,
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: Text(loc.progressHistoryDate,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ),
              Expanded(
                flex: 2,
                child: Text(loc.workoutDetailWeight,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ),
              Expanded(
                flex: 2,
                child: Text(loc.commonVolume,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ),
              Expanded(
                flex: 2,
                child: Text(loc.progressHistorySetsReps,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ),
              Expanded(
                flex: 2,
                child: Text(loc.exerciseDetailChart1RM,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
        ...history.reversed.map((h) {
          final date = h['date'] as String? ?? '';
          final maxW = (h['max_weight'] as double?) ?? 0;
          final vol = (h['total_volume'] as double?) ?? 0;
          final sets = (h['total_sets'] as int?) ?? 0;
          final reps = (h['total_reps'] as int?) ?? 0;
          final est1RM = (h['estimated_1rm'] as double?);
          final workoutId = h['workout_id'] as String?;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: InkWell(
              onTap: workoutId != null
                  ? () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              WorkoutDetailScreen(workoutId: workoutId),
                        ),
                      )
                  : null,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withAlpha(60),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        date.length >= 10 ? date.substring(5) : date,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        maxW > 0 ? maxW.toStringAsFixed(1) : '-',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        vol > 0 ? vol.toStringAsFixed(0) : '-',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text('$sets×$reps',
                          style: theme.textTheme.bodySmall),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        est1RM != null ? est1RM.toStringAsFixed(1) : '-',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Colors.amber[700],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}
