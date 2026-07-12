import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/l10n/exercise_locale_helper.dart';
import 'package:workout_notes/repositories/analytics_repository.dart';
import 'package:workout_notes/repositories/exercise_repository.dart';
import 'package:workout_notes/utils/progress_helpers.dart';
import 'package:workout_notes/widgets/progress/progress_stat_cards.dart';
import 'package:workout_notes/screens/workout/workout_detail_screen.dart';

/// Full-screen exercise detail view with chart type selector,
/// records, chart, and history table.
class ExerciseDetailView extends StatefulWidget {
  final Map<String, dynamic>? initialHistory;
  final String initialExerciseId;
  final AnalyticsRepository analytics;
  final ExerciseRepository exerciseRepo;

  const ExerciseDetailView({
    super.key,
    required this.initialHistory,
    required this.initialExerciseId,
    required this.analytics,
    required this.exerciseRepo,
  });

  @override
  State<ExerciseDetailView> createState() => _ExerciseDetailViewState();
}

class _ExerciseDetailViewState extends State<ExerciseDetailView> {
  Map<String, dynamic>? _history;
  int _chartType = 0;
  List<Map<String, dynamic>> _allExercises = [];

  @override
  void initState() {
    super.initState();
    _history = widget.initialHistory;
    _loadExercises();
  }

  Future<void> _loadExercises() async {
    final exercises = await widget.exerciseRepo.getExercises();
    if (!mounted) return;
    setState(() {
      _allExercises = exercises;
    });
  }

  Future<void> _loadHistory(String exerciseId) async {
    final data = await widget.analytics.getExerciseHistory(
      exerciseId,
      limit: 30,
    );
    if (!mounted) return;
    setState(() {
      _history = data;
    });
  }

  List<String> _chartTypes(AppLocalizations loc) => [
    loc.exerciseDetailChart1RM,
    loc.exerciseDetailChartMaxWeight,
    loc.exerciseDetailChartVolume,
    loc.exerciseDetailChartTotalReps,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;

    if (_history == null) {
      return Center(child: Text(loc.progressLoadError));
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: _buildExerciseSelector(theme, loc),
        ),
        const SizedBox(height: 4),
        _buildChartTypeSelector(theme, loc),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildRecords(theme),
                const SizedBox(height: 16),
                _buildChart(theme, loc),
                const SizedBox(height: 16),
                _buildHistorySection(theme, loc),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExerciseSelector(ThemeData theme, AppLocalizations loc) {
    final selectedEx = _allExercises.firstWhere(
      (e) => e['id'] == (_history?['exercise_id']),
      orElse: () => <String, dynamic>{},
    );

    return DropdownButtonFormField<String>(
      initialValue: selectedEx['id'] as String?,
      decoration: InputDecoration(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      isExpanded: true,
      items: _allExercises.map((ex) {
        return DropdownMenuItem(
          value: ex['id'] as String,
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: Color(ex['category_color'] as int? ?? 0xFF757575),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ExerciseLocaleHelper.exerciseName(loc, ex),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      }).toList(),
      onChanged: (id) {
        if (id != null) _loadHistory(id);
      },
    );
  }

  Widget _buildChartTypeSelector(ThemeData theme, AppLocalizations loc) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        height: 36,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: List.generate(_chartTypes(loc).length, (i) {
            final isSelected = _chartType == i;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(
                  _chartTypes(loc)[i],
                  style: TextStyle(fontSize: 12),
                ),
                selected: isSelected,
                onSelected: (_) => setState(() => _chartType = i),
              ),
            );
          }),
        ),
      ),
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

  Widget _buildChart(ThemeData theme, AppLocalizations loc) {
    final history = _history!['history'] as List? ?? [];

    String title;
    List<double> values;

    switch (_chartType) {
      case 0:
        title =
            '${loc.exerciseDetailChart1RM} ${loc.progressChartTitleProgress}';
        values = history
            .map((h) => (h['estimated_1rm'] as double?) ?? 0)
            .toList();
        break;
      case 1:
        title = loc.exerciseDetailChartMaxWeight;
        values = history.map((h) => (h['max_weight'] as double?) ?? 0).toList();
        break;
      case 2:
        title = loc.progressChartTitleVolumePerWorkout;
        values = history
            .map((h) => (h['total_volume'] as double?) ?? 0)
            .toList();
        break;
      case 3:
        title = loc.progressChartTitleRepsPerWorkout;
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
            color: theme.colorScheme.outlineVariant.withAlpha(80),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Icon(
                Icons.bar_chart_outlined,
                size: 48,
                color: theme.colorScheme.onSurfaceVariant.withAlpha(80),
              ),
              const SizedBox(height: 12),
              Text(
                loc.progressNoChartData,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
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
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  '${history.length} ${loc.progressWorkouts.toLowerCase()}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
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
                      color: theme.colorScheme.outlineVariant.withAlpha(60),
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
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 10,
                              ),
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
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 9,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: values
                          .asMap()
                          .entries
                          .map((e) => FlSpot(e.key.toDouble(), e.value))
                          .toList(),
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
                        color:
                            (_chartType == 0
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

  Widget _buildHistorySection(ThemeData theme, AppLocalizations loc) {
    final history = _history!['history'] as List? ?? [];
    if (history.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          loc.progressHistoryTitle,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
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
                child: Text(
                  loc.progressHistoryDate,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  loc.workoutDetailWeight,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  loc.commonVolume,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  loc.progressHistorySetsReps,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  loc.exerciseDetailChart1RM,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withAlpha(
                    60,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        date.length >= 10 ? date.substring(5) : date,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
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
                      child: Text(
                        '$sets×$reps',
                        style: theme.textTheme.bodySmall,
                      ),
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
