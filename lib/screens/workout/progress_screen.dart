import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/l10n/exercise_locale_helper.dart';
import '../../database/database_helper.dart';
import 'workout_detail_screen.dart';
import '../../widgets/collapsible_section.dart';
import '../../widgets/workout_heatmap.dart';
import 'body_tracker_screen.dart';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  final _db = DatabaseHelper.instance;

  bool _isLoading = true;

  // === OVERVIEW DATA (loaded immediately) ===
  Map<String, dynamic>? _overviewStats;
  List<Map<String, dynamic>> _monthlyVolume = [];
  Map<String, dynamic>? _monthReport;
  Map<String, dynamic>? _monthComparison;

  // === LAZY LOADING FLAGS ===
  bool _isLoadingFrequency = false;
  bool _isLoadingVolume = false;
  bool _isLoadingPerformance = false;
  bool _isLoadingDuration = false;
  bool _isLoadingRecovery = false;
  bool _isLoadingBody = false;
  bool _loadedFrequency = false;
  bool _loadedVolume = false;
  bool _loadedPerformance = false;
  bool _loadedDuration = false;
  bool _loadedRecovery = false;
  bool _loadedBody = false;

  // === FREQUENCY DATA ===
  Map<String, int> _heatmapData = {};
  List<Map<String, dynamic>> _workoutDates = [];

  // === VOLUME DATA ===
  List<Map<String, dynamic>> _volumeByCategory = [];
  List<Map<String, dynamic>> _topExercises = [];
  List<Map<String, dynamic>> _energySystems = [];

  // === PERFORMANCE DATA ===
  List<Map<String, dynamic>> _allExercises = [];


  // === DURATION / DENSITY ===
  List<Map<String, dynamic>> _durationTrend = [];
  List<Map<String, dynamic>> _densityData = [];

  // === RECOVERY ===
  List<Map<String, dynamic>> _feelingTrend = [];
  List<Map<String, dynamic>> _feelingVsVolume = [];

  // === BODY ===
  List<Map<String, dynamic>> _bodyData = [];
  List<Map<String, dynamic>> _bodySummary = [];
  List<Map<String, dynamic>> _bodyComposition = [];

  // === EXERCISE DETAIL STATE ===
  Map<String, dynamic>? _selectedHistory;
  int _selectedChartType = 0;
  bool _showingOverview = true;

  List<String> _chartTypes(AppLocalizations loc) => [
    AppLocalizations.of(context)!.exerciseDetailChart1RM,
    AppLocalizations.of(context)!.exerciseDetailChartMaxWeight,
    AppLocalizations.of(context)!.exerciseDetailChartVolume,
    AppLocalizations.of(context)!.exerciseDetailChartTotalReps,
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {

    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final now = DateTime.now();

    try {
      // Load only immediately visible data
      final results = await Future.wait([
        _db.getWorkoutOverviewStats(),
        _db.getMonthlyVolume(),
        _db.getMonthlyReport(now.year, now.month),
        _db.getMonthComparison(now.year, now.month),
      ]);

      if (!mounted) return;

      _overviewStats = results[0] as Map<String, dynamic>;
      _monthlyVolume = results[1] as List<Map<String, dynamic>>;
      _monthReport = results[2] as Map<String, dynamic>;
      _monthComparison = results[3] as Map<String, dynamic>;

      setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ===================================================================
  // LAZY LOADING METHODS (called when sections are expanded)
  // ===================================================================

  Future<void> _loadFrequency() async {
    if (_loadedFrequency) return;
    setState(() => _isLoadingFrequency = true);
    final now = DateTime.now();
    try {
      final results = await Future.wait([
        _db.getYearlyHeatmapData(now.year),
        _db.getWorkoutDatesInRange(DateTime(now.year, 1, 1)),
      ]);
      if (!mounted) return;
      _heatmapData = results[0] as Map<String, int>;
      _workoutDates = results[1] as List<Map<String, dynamic>>;
      _loadedFrequency = true;
      setState(() => _isLoadingFrequency = false);
    } catch (_) {
      if (mounted) setState(() => _isLoadingFrequency = false);
    }
  }

  Future<void> _loadVolume() async {
    if (_loadedVolume) return;
    setState(() => _isLoadingVolume = true);
    try {
      final results = await Future.wait([
        _db.getVolumeByCategory(),
        _db.getTopExercisesByVolume(),
        _db.getEnergySystemDistribution(),
      ]);
      if (!mounted) return;
      _volumeByCategory = results[0];
      _topExercises = results[1];
      _energySystems = results[2];
      _loadedVolume = true;
      setState(() => _isLoadingVolume = false);
    } catch (_) {
      if (mounted) setState(() => _isLoadingVolume = false);
    }
  }

  Future<void> _loadPerformance() async {
    if (_loadedPerformance) return;
    setState(() => _isLoadingPerformance = true);
    try {
      // Only load the exercise list (lightweight) — no history or PRs
      _allExercises = await _db.getExercises();
      if (!mounted) return;
      _loadedPerformance = true;
      setState(() => _isLoadingPerformance = false);
    } catch (_) {
      if (mounted) setState(() => _isLoadingPerformance = false);
    }
  }

  Future<void> _loadDuration() async {
    if (_loadedDuration) return;
    setState(() => _isLoadingDuration = true);
    try {
      final results = await Future.wait([
        _db.getDurationTrend(),
        _db.getWorkoutDensity(),
      ]);
      if (!mounted) return;
      _durationTrend = results[0];
      _densityData = results[1];
      _loadedDuration = true;
      setState(() => _isLoadingDuration = false);
    } catch (_) {
      if (mounted) setState(() => _isLoadingDuration = false);
    }
  }

  Future<void> _loadRecovery() async {
    if (_loadedRecovery) return;
    setState(() => _isLoadingRecovery = true);
    try {
      final results = await Future.wait([
        _db.getFeelingTrend(),
        _db.getFeelingVsVolume(),
      ]);
      if (!mounted) return;
      _feelingTrend = results[0];
      _feelingVsVolume = results[1];
      _loadedRecovery = true;
      setState(() => _isLoadingRecovery = false);
    } catch (_) {
      if (mounted) setState(() => _isLoadingRecovery = false);
    }
  }

  Future<void> _loadBody() async {
    if (_loadedBody) return;
    setState(() => _isLoadingBody = true);
    try {
      final results = await Future.wait([
        _db.getBodyWeightWithVolume(),
        _db.getBodyMeasurementsSummary(),
        _db.getBodyCompositionTrend(),
      ]);
      if (!mounted) return;
      _bodyData = results[0];
      _bodySummary = results[1];
      _bodyComposition = results[2];
      _loadedBody = true;
      setState(() => _isLoadingBody = false);
    } catch (_) {
      if (mounted) setState(() => _isLoadingBody = false);
    }
  }

  Future<void> _loadHistory(String exerciseId) async {
    final data = await _db.getExerciseHistory(exerciseId, limit: 30);
    setState(() {
      _selectedHistory = data;
      _showingOverview = false;
    });
  }

  // =======================================================================
  // HELPERS
  // =======================================================================

  double _niceInterval(double range) {
    if (range <= 0) return 1;
    final rough = range / 5;
    double magnitude = 1;
    double temp = rough;
    while (temp >= 10) { temp /= 10; magnitude *= 10; }
    while (temp < 1) { temp *= 10; magnitude /= 10; }
    if (temp <= 1) temp = 1;
    else if (temp <= 2) temp = 2;
    else if (temp <= 5) temp = 5;
    else temp = 10;
    final result = temp * magnitude;
    return result < 0.5 ? 0.5 : result;
  }

  String _formatVolume(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.toStringAsFixed(0);
  }

  String _monthLabel(String isoMonth) {
    try {
      return DateFormat('MMM', Intl.defaultLocale).format(DateTime.parse(isoMonth));
    } catch (_) {
      return isoMonth.length >= 7 ? isoMonth.substring(5) : isoMonth;
    }
  }

  String _weekLabel(DateTime date, String prefix) {
    final week = DateFormat('w', Intl.defaultLocale).format(date);
    return '$prefix$week';
  }

  Widget _sectionLoading(ThemeData theme) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
      ),
    );
  }

  /// Shows a modal bottom sheet with full exercise history/charts.
  Future<void> _showExercisePopup(String exerciseId, String exerciseName, ThemeData theme) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ExerciseDetailSheet(
        exerciseId: exerciseId,
        exerciseName: exerciseName,
        db: _db,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_showingOverview ? AppLocalizations.of(context)!.progressTitle : (_selectedHistory?['exercise_name'] as String? ?? AppLocalizations.of(context)!.progressTitle)),
        centerTitle: true,
        leading: _showingOverview
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _showingOverview = true),
              ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _showingOverview
              ? _buildOverview(theme)
              : _buildExerciseDetail(theme),
    );
  }

  // =======================================================================
  // OVERVIEW
  // =======================================================================

  Widget _buildOverview(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Monthly report card
          _buildMonthlyReportCard(theme),
          const SizedBox(height: 12),

          // Enhanced stats row
          _buildStatsRow(theme),
          const SizedBox(height: 8),

          // Monthly volume chart (from existing)
          if (_monthlyVolume.isNotEmpty) ...[
            _buildMonthlyVolumeChart(theme),
            const SizedBox(height: 4),
          ],

          // === Collapsible Sections (lazy loaded on expand) ===
          _buildDivider(theme),
          CollapsibleSection(
            title: AppLocalizations.of(context)!.progressFrequency,
            icon: Icons.calendar_month,
            iconColor: Colors.blue,
            onExpanded: _loadFrequency,
            child: _buildFrequencyContent(theme),
          ),

          _buildDivider(theme),
          CollapsibleSection(
            title: AppLocalizations.of(context)!.progressVolumeGroups,
            icon: Icons.pie_chart,
            iconColor: Colors.teal,
            onExpanded: _loadVolume,
            child: _buildVolumeContent(theme),
          ),

          _buildDivider(theme),
          CollapsibleSection(
            title: AppLocalizations.of(context)!.progressExerciseHistory,
            icon: Icons.emoji_events,
            iconColor: Colors.amber,
            onExpanded: _loadPerformance,
            child: _buildPerformanceContent(theme),
          ),

          _buildDivider(theme),
          CollapsibleSection(
            title: AppLocalizations.of(context)!.progressDurationEfficiency,
            icon: Icons.timer,
            iconColor: Colors.purple,
            onExpanded: _loadDuration,
            child: _buildDurationContent(theme),
          ),

          _buildDivider(theme),
          CollapsibleSection(
            title: AppLocalizations.of(context)!.progressRecovery,
            icon: Icons.favorite,
            iconColor: Colors.red,
            onExpanded: _loadRecovery,
            child: _buildRecoveryContent(theme),
          ),

          _buildDivider(theme),
          CollapsibleSection(
            title: AppLocalizations.of(context)!.progressBodyMeasurements,
            icon: Icons.monitor_weight,
            iconColor: Colors.indigo,
            onExpanded: _loadBody,
            child: _buildBodyContent(theme),
          ),

          _buildDivider(theme),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildDivider(ThemeData theme) {
    return Divider(height: 1, color: theme.colorScheme.outlineVariant.withAlpha(60));
  }

  // ===================== MONTHLY REPORT =====================

  Widget _buildMonthlyReportCard(ThemeData theme) {
    final report = _monthReport;
    if (report == null) return const SizedBox.shrink();

    final wc = report['workout_count'] as int? ?? 0;
    final vol = (report['total_volume'] as double?) ?? 0;
    final sets = report['total_sets'] as int? ?? 0;
    final days = report['days_with_workouts'] as int? ?? 0;
    final avgFeeling = report['avg_feeling'] as double?;

    final comp = _monthComparison;
    final deltaW = comp?['delta_workouts'] as int? ?? 0;
    final deltaV = (comp?['delta_volume'] as double?) ?? 0;

    final now = DateTime.now();
    final monthName = DateFormat('MMMM', Intl.defaultLocale).format(now);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(100)),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [
              theme.colorScheme.primaryContainer.withAlpha(120),
              theme.colorScheme.surface,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_graph, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  AppLocalizations.of(context)!.progressMonthlyReport(monthName.toUpperCase()),
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _MiniStat(icon: Icons.fitness_center, label: AppLocalizations.of(context)!.progressWorkouts, value: '$wc',
                    color: theme.colorScheme.primary, delta: deltaW, theme: theme),
                const SizedBox(width: 8),
                _MiniStat(icon: Icons.auto_graph, label: AppLocalizations.of(context)!.commonVolume, value: _formatVolume(vol),
                    color: Colors.teal, delta: deltaV.toInt(), theme: theme),
                const SizedBox(width: 8),
                _MiniStat(icon: Icons.repeat, label: AppLocalizations.of(context)!.progressSets, value: '$sets',
                    color: theme.colorScheme.secondary, theme: theme),
                const SizedBox(width: 8),
                _MiniStat(icon: Icons.calendar_view_day, label: AppLocalizations.of(context)!.progressDays, value: '$days',
                    color: Colors.blue, theme: theme),
              ],
            ),
            if (avgFeeling != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.star, size: 14, color: Colors.amber),
                  const SizedBox(width: 4),
                  Text(
                    AppLocalizations.of(context)!.progressAverageFeeling(avgFeeling.toStringAsFixed(1)),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  if (deltaW != 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: deltaW > 0 ? Colors.green.withAlpha(25) : Colors.red.withAlpha(25),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            deltaW > 0 ? Icons.trending_up : Icons.trending_down,
                            size: 14,
                            color: deltaW > 0 ? Colors.green : Colors.red,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            AppLocalizations.of(context)!.progressVsLastMonth('${deltaW > 0 ? '+' : ''}$deltaW'),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: deltaW > 0 ? Colors.green : Colors.red,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ===================== STATS ROW =====================

  Widget _buildStatsRow(ThemeData theme) {
    final stats = _overviewStats;
    final totalWorkouts = (stats?['total_workouts'] as int?) ?? 0;
    final totalSets = (stats?['total_sets'] as int?) ?? 0;
    final totalVolume = (stats?['total_volume'] as int?) ?? 0;
    final streak = (stats?['current_streak'] as int?) ?? 0;

    return Row(
      children: [
        Expanded(child: _StatCard(
          label: AppLocalizations.of(context)!.progressWorkouts, value: '$totalWorkouts',
          icon: Icons.fitness_center, color: theme.colorScheme.primary,
        )),
        const SizedBox(width: 6),
        Expanded(child: _StatCard(
          label: AppLocalizations.of(context)!.progressSets, value: '$totalSets',
          icon: Icons.repeat, color: theme.colorScheme.secondary,
        )),
        const SizedBox(width: 6),
        Expanded(child: _StatCard(
          label: AppLocalizations.of(context)!.commonVolume, value: totalVolume >= 1000
              ? '${(totalVolume / 1000).toStringAsFixed(1)}k'
              : '$totalVolume',
          icon: Icons.auto_graph, color: Colors.teal,
        )),
        const SizedBox(width: 6),
        Expanded(child: _StatCard(
          label: AppLocalizations.of(context)!.progressStreak, value: '$streak ${streak == 1 ? AppLocalizations.of(context)!.workoutHomeDay : AppLocalizations.of(context)!.workoutHomeDays}',
          icon: Icons.local_fire_department, color: Colors.orange,
        )),
      ],
    );
  }

  // ===================== FREQUENCY CONTENT =====================

  Widget _buildFrequencyContent(ThemeData theme) {
    if (_isLoadingFrequency) return _sectionLoading(theme);
    if (!_loadedFrequency) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Heatmap
        Text(AppLocalizations.of(context)!.progressYearHeatmap, style: theme.textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w600, color: theme.colorScheme.onSurfaceVariant,
        )),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: WorkoutHeatmap(dailyData: _heatmapData, year: DateTime.now().year),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const Spacer(),
            _buildLegend(),
          ],
        ),
        const SizedBox(height: 16),

        // Weekly frequency chart
        if (_workoutDates.isNotEmpty) ...[
          Text(AppLocalizations.of(context)!.progressWeeklyFrequency,
              style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          _buildWeeklyFrequencyChart(theme),
          const SizedBox(height: 16),
        ],

        // Day of week + Time of day side by side
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildDayOfWeekChart(theme)),
            const SizedBox(width: 8),
            Expanded(child: _buildTimeOfDayChart(theme)),
          ],
        ),
      ],
    );
  }

  Widget _buildLegend() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _legendDot(Colors.green.shade200),
        _legendDot(Colors.green.shade400),
        _legendDot(Colors.green.shade600),
        _legendDot(Colors.green.shade800),
        const SizedBox(width: 4),
        Text('+ volume', style: TextStyle(fontSize: 9, color: Colors.grey)),
      ],
    );
  }

  Widget _legendDot(Color color) {
    return Container(
      width: 8, height: 8, margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(1)),
    );
  }

  Widget _buildWeeklyFrequencyChart(ThemeData theme) {
    final loc = AppLocalizations.of(context)!;
    final now = DateTime.now();
    final weeks = <_WeekBar>[];

    // Build last 12 weeks
    for (int i = 11; i >= 0; i--) {
      final weekStart = now.subtract(Duration(days: now.weekday - 1 + (i * 7)));
      final weekEnd = weekStart.add(const Duration(days: 6));
      final startStr = weekStart.toIso8601String().substring(0, 10);
      final endStr = weekEnd.toIso8601String().substring(0, 10);

      int count = 0;
      for (final wd in _workoutDates) {
        final d = wd['date'] as String? ?? '';
        if (d.compareTo(startStr) >= 0 && d.compareTo(endStr) <= 0) {
          count++;
        }
      }
      weeks.add(_WeekBar(_weekLabel(weekStart, AppLocalizations.of(context)!.progressWeekAbbreviation), count));
    }

    final maxCount = weeks.fold<int>(0, (a, b) => a > b.count ? a : b.count);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          height: 140,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxCount < 5 ? 5 : maxCount * 1.2,
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (g, gi, r, ri) {
                    final w = weeks[gi];
                    return BarTooltipItem(
                      '${w.label}: ${w.count} ${loc.progressWorkouts}',
                      TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 12),
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (v, _) {
                      final idx = v.toInt();
                      if (idx < 0 || idx >= weeks.length) return const SizedBox.shrink();
                      // Show every other label
                      if (weeks.length > 6 && idx % 2 != 0) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(weeks[idx].label,
                            style: theme.textTheme.bodySmall?.copyWith(fontSize: 8)),
                      );
                    },
                    reservedSize: 20,
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true, reservedSize: 20,
                    getTitlesWidget: (v, _) {
                      if (v == 0) return const SizedBox.shrink();
                      return Text('${v.toInt()}',
                          style: theme.textTheme.bodySmall?.copyWith(fontSize: 9));
                    },
                  ),
                ),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: false),
              gridData: FlGridData(
                show: true, drawVerticalLine: false,
                horizontalInterval: _niceInterval(maxCount > 0 ? maxCount / 4 : 1),
              ),
              barGroups: weeks.asMap().entries.map((e) => BarChartGroupData(
                x: e.key,
                barRods: [
                  BarChartRodData(
                    toY: e.value.count.toDouble(),
                    color: theme.colorScheme.primary,
                    width: 16,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4), topRight: Radius.circular(4),
                    ),
                  ),
                ],
              )).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDayOfWeekChart(ThemeData theme) {
    final dowCount = <int, int>{0: 0, 1: 0, 2: 0, 3: 0, 4: 0, 5: 0, 6: 0};
    for (final wd in _workoutDates) {
      final dow = wd['day_of_week'] as int? ?? 0;
      dowCount[dow] = (dowCount[dow] ?? 0) + 1;
    }

    final loc = AppLocalizations.of(context)!;
    final labels = [loc.calendarSun, loc.calendarMon, loc.calendarTue, loc.calendarWed, loc.calendarThu, loc.calendarFri, loc.calendarSat];
    final maxVal = dowCount.values.fold<int>(0, (a, b) => a > b ? a : b);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(loc.progressDayOfWeek, style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600, fontSize: 10)),
            const SizedBox(height: 6),
            SizedBox(
              height: 120,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxVal < 3 ? 3 : maxVal * 1.2,
                  barTouchData: BarTouchData(enabled: false),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true, reservedSize: 16,
                        getTitlesWidget: (v, _) {
                          final idx = v.toInt();
                          if (idx < 0 || idx >= 7) return const SizedBox.shrink();
                          return Text(labels[idx],
                              style: theme.textTheme.bodySmall?.copyWith(fontSize: 8));
                        },
                      ),
                    ),
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(show: false),
                  barGroups: List.generate(7, (i) => BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: (dowCount[i] ?? 0).toDouble(),
                        color: _dowColor(i, theme),
                        width: 10,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(3), topRight: Radius.circular(3),
                        ),
                      ),
                    ],
                  )),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _dowColor(int dow, ThemeData theme) {
    if (dow == 0 || dow == 6) return Colors.orange.withAlpha(180);
    return theme.colorScheme.primary;
  }

  Widget _buildTimeOfDayChart(ThemeData theme) {
    final periods = {'manhã': 0, 'tarde': 0, 'noite': 0, 'madrugada': 0};
    for (final wd in _workoutDates) {
      final startTime = wd['start_time'] as String?;
      if (startTime == null) continue;
      try {
        final hour = DateTime.parse(startTime).hour;
        if (hour < 6) periods['madrugada'] = periods['madrugada']! + 1;
        else if (hour < 12) periods['manhã'] = periods['manhã']! + 1;
        else if (hour < 18) periods['tarde'] = periods['tarde']! + 1;
        else periods['noite'] = periods['noite']! + 1;
      } catch (_) {}
    }

    final total = periods.values.fold<int>(0, (a, b) => a + b);
    if (total == 0) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              Text(AppLocalizations.of(context)!.progressTimeOfDay, style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600, fontSize: 10)),
              const SizedBox(height: 20),
              Icon(Icons.access_time, size: 24, color: theme.colorScheme.onSurfaceVariant.withAlpha(80)),
              Text(AppLocalizations.of(context)!.progressNoData, style: theme.textTheme.bodySmall?.copyWith(fontSize: 9)),
            ],
          ),
        ),
      );
    }

    final colors = [Colors.orange, Colors.amber, Colors.indigo, Colors.deepPurple];
    final labels = [AppLocalizations.of(context)!.progressMorning, AppLocalizations.of(context)!.progressAfternoon, AppLocalizations.of(context)!.progressEvening, AppLocalizations.of(context)!.progressDawn];
    final values = [periods['manhã']!, periods['tarde']!, periods['noite']!, periods['madrugada']!];

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppLocalizations.of(context)!.progressTimeOfDay, style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600, fontSize: 10)),
            const SizedBox(height: 6),
            SizedBox(
              height: 120,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 1,
                  centerSpaceRadius: 20,
                  sections: List.generate(4, (i) {
                    if (values[i] == 0) return PieChartSectionData(color: Colors.transparent, value: 0, showTitle: false);
                    return PieChartSectionData(
                      color: colors[i],
                      value: values[i].toDouble(),
                      title: '${(values[i] / total * 100).toStringAsFixed(0)}%',
                      titleStyle: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                      radius: 28,
                    );
                  }).where((s) => s.value > 0).toList(),
                ),
              ),
            ),
            const SizedBox(height: 4),
            ...List.generate(4, (i) {
              if (values[i] == 0) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Row(
                  children: [
                    Container(width: 6, height: 6, decoration: BoxDecoration(
                      color: colors[i], shape: BoxShape.circle,
                    )),
                    const SizedBox(width: 4),
                    Text('${labels[i]}: ${values[i]}', style: TextStyle(fontSize: 8)),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ===================== VOLUME CONTENT =====================

  Widget _buildVolumeContent(ThemeData theme) {
    if (_isLoadingVolume) return _sectionLoading(theme);
    if (!_loadedVolume) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Volume by category (pie) + Energy system (mini) side by side
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: _buildVolumeByCategoryPie(theme)),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: _buildEnergySystemMini(theme)),
          ],
        ),
        const SizedBox(height: 16),

        // Top exercises
        if (_topExercises.isNotEmpty) ...[
          Text(AppLocalizations.of(context)!.progressTopExercises,
              style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          _buildTopExercisesChart(theme),
        ],
      ],
    );
  }

  Widget _buildVolumeByCategoryPie(ThemeData theme) {
    if (_volumeByCategory.isEmpty) {
      return Card(
        elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(child: Text(AppLocalizations.of(context)!.progressNoData, style: theme.textTheme.bodySmall)),
        ),
      );
    }

    final total = _volumeByCategory.fold<double>(0, (a, b) => a + ((b['volume'] as num?)?.toDouble() ?? 0));

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppLocalizations.of(context)!.progressVolumeByGroup, style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600, fontSize: 10)),
            const SizedBox(height: 6),
            SizedBox(
              height: 150,
              child: Row(
                children: [
                  Expanded(
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 1,
                        centerSpaceRadius: 20,
                        sections: _volumeByCategory.asMap().entries.map((e) {
                          final vol = (e.value['volume'] as num?)?.toDouble() ?? 0;
                          final pct = total > 0 ? vol / total * 100 : 0.0;
                          return PieChartSectionData(
                            color: Color(e.value['color'] as int? ?? 0xFF757575),
                            value: vol,
                            title: pct >= 8 ? '${pct.toStringAsFixed(0)}%' : '',
                            titleStyle: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                            radius: pct >= 15 ? 32 : 26,
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _volumeByCategory.take(5).map((cat) {
                      final vol = (cat['volume'] as num?)?.toDouble() ?? 0;
                      final pct = total > 0 ? vol / total * 100 : 0.0;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(width: 8, height: 8, decoration: BoxDecoration(
                              color: Color(cat['color'] as int? ?? 0xFF757575),
                              borderRadius: BorderRadius.circular(2),
                            )),
                            const SizedBox(width: 4),
                            Text('${ExerciseLocaleHelper.categoryName(AppLocalizations.of(context)!, cat)} ${pct.toStringAsFixed(0)}%',
                                style: TextStyle(fontSize: 8)),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEnergySystemMini(ThemeData theme) {
    if (_energySystems.isEmpty) {
      return const SizedBox.shrink();
    }

    final total = _energySystems.fold<double>(0, (a, b) => a + ((b['volume'] as num?)?.toDouble() ?? 0));
    final colors = {'aerobic': Colors.green, 'anaerobic': Colors.red};
    final labels = {'aerobic': AppLocalizations.of(context)!.progressAerobic, 'anaerobic': AppLocalizations.of(context)!.progressAnaerobic};

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Text(AppLocalizations.of(context)!.progressEnergySystem, style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600, fontSize: 10)),
            const SizedBox(height: 8),
            SizedBox(
              height: 80,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 1,
                  centerSpaceRadius: 12,
                  sections: _energySystems.map((es) {
                    final system = es['energy_system'] as String? ?? 'anaerobic';
                    final vol = (es['volume'] as num?)?.toDouble() ?? 0;
                    final pct = total > 0 ? vol / total * 100 : 0.0;
                    return PieChartSectionData(
                      color: colors[system] ?? Colors.grey,
                      value: vol,
                      title: pct > 0 ? '${pct.toStringAsFixed(0)}%' : '',
                      titleStyle: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white),
                      radius: 28,
                    );
                  }).toList(),
                ),
              ),
            ),
            ..._energySystems.map((es) {
              final system = es['energy_system'] as String? ?? '';
              final vol = (es['volume'] as num?)?.toDouble() ?? 0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Row(
                  children: [
                    Container(width: 6, height: 6, decoration: BoxDecoration(
                      color: colors[system] ?? Colors.grey, shape: BoxShape.circle,
                    )),
                    const SizedBox(width: 4),
                    Text('${labels[system] ?? system}: ${_formatVolume(vol)}',
                        style: TextStyle(fontSize: 7)),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildTopExercisesChart(ThemeData theme) {
    final maxVol = _topExercises.fold<double>(0, (a, b) {
      final v = (b['volume'] as num?)?.toDouble() ?? 0;
      return a > v ? a : v;
    });

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: _topExercises.take(5).map((ex) {
            final vol = (ex['volume'] as num?)?.toDouble() ?? 0;
            final pct = maxVol > 0 ? vol / maxVol : 0.0;
            final catColor = Color(ex['category_color'] as int? ?? 0xFF757575);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 4, height: 28,
                    decoration: BoxDecoration(
                      color: catColor, borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 100,
                    child: Text(ExerciseLocaleHelper.exerciseName(AppLocalizations.of(context)!, ex),
                        style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: pct,
                        backgroundColor: theme.colorScheme.surfaceContainerHighest,
                        color: catColor,
                        minHeight: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 48,
                    child: Text(_formatVolume(vol),
                        style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
                        textAlign: TextAlign.right),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ===================== PERFORMANCE CONTENT =====================

  Widget _buildPerformanceContent(ThemeData theme) {
    if (_isLoadingPerformance) return _sectionLoading(theme);
    if (!_loadedPerformance) return const SizedBox.shrink();
    if (_allExercises.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(Icons.fitness_center_outlined, size: 32,
                  color: theme.colorScheme.onSurfaceVariant.withAlpha(80)),
              const SizedBox(height: 8),
              Text(AppLocalizations.of(context)!.progressNoExercises,
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      );
    }

    // Group exercises by category
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final ex in _allExercises) {
      final catName = ExerciseLocaleHelper.categoryName(AppLocalizations.of(context)!, ex);
      grouped.putIfAbsent(catName, () => []).add(ex);
    }
    final sortedKeys = grouped.keys.toList()..sort();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppLocalizations.of(context)!.progressTapForHistory,
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          ...sortedKeys.map((catName) {
            final exercises = grouped[catName]!;
            final catColor = Color(exercises.first['category_color'] as int? ?? 0xFF757575);
            return ExpansionTile(
              initiallyExpanded: false,
              tilePadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
              childrenPadding: EdgeInsets.zero,
              shape: const Border(),
              collapsedShape: const Border(),
              collapsedBackgroundColor: Colors.transparent,
              backgroundColor: Colors.transparent,
              iconColor: catColor,
              collapsedIconColor: catColor.withAlpha(150),
              title: Row(
                children: [
                  Container(
                    width: 4, height: 16,
                    decoration: BoxDecoration(
                      color: catColor, borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(catName,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: catColor,
                      )),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: catColor.withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('${exercises.length}',
                        style: TextStyle(fontSize: 10, color: catColor, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              children: exercises.map((ex) => _buildCategoryExerciseCard(ex, theme)).toList(),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildCategoryExerciseCard(Map<String, dynamic> ex, ThemeData theme) {
    final catColor = Color(ex['category_color'] as int? ?? 0xFF757575);
    final name = ExerciseLocaleHelper.exerciseName(AppLocalizations.of(context)!, ex);
    final type = ex['type'] as String? ?? 'weightReps';
    final icon = type == 'weightReps' ? Icons.fitness_center :
                type == 'cardio' ? Icons.directions_run :
                type == 'duration' ? Icons.timer : Icons.fitness_center;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 2),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _showExercisePopup(ex['id'] as String, name, theme),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: catColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: catColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(name,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
              ),
              Icon(Icons.chevron_right, size: 18, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }



  // ===================== DURATION CONTENT =====================

  Widget _buildDurationContent(ThemeData theme) {
    if (_isLoadingDuration) return _sectionLoading(theme);
    if (!_loadedDuration) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_durationTrend.isNotEmpty) ...[
          Text(AppLocalizations.of(context)!.progressDuration,
              style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          _buildDurationChart(theme),
          const SizedBox(height: 16),
        ],
        if (_densityData.isNotEmpty) ...[
          Text(AppLocalizations.of(context)!.progressDensity,
              style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          _buildDensityChart(theme),
        ],
      ],
    );
  }

  Widget _buildDurationChart(ThemeData theme) {
    final data = _durationTrend.reversed.toList();
    final values = data.map((d) => ((d['duration_seconds'] as int?) ?? 0) / 60.0).toList();
    final maxVal = values.fold<double>(0, (a, b) => a > b ? a : b);
    if (maxVal <= 0) return const SizedBox.shrink();

    final avg = values.fold<double>(0, (a, b) => a + b) / values.length;

    return Card(
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
                Text(AppLocalizations.of(context)!.progressAverage(avg.toStringAsFixed(0)),
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 11)),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 140,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: maxVal * 1.15,
                  gridData: FlGridData(show: true, drawVerticalLine: false,
                    horizontalInterval: _niceInterval(maxVal / 4),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true, reservedSize: 32,
                        getTitlesWidget: (v, _) => Text('${v.toInt()}min',
                            style: theme.textTheme.bodySmall?.copyWith(fontSize: 8)),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true, reservedSize: 20,
                        interval: data.length > 10 ? 2 : 1,
                        getTitlesWidget: (v, _) {
                          final idx = v.toInt();
                          if (idx < 0 || idx >= data.length) return const SizedBox.shrink();
                          final d = data[idx]['date'] as String? ?? '';
                          return Text(d.length >= 10 ? d.substring(5) : d,
                              style: theme.textTheme.bodySmall?.copyWith(fontSize: 7));
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: values.asMap().entries.map((e) =>
                        FlSpot(e.key.toDouble(), e.value)).toList(),
                      isCurved: true,
                      color: Colors.purple,
                      barWidth: 2.5,
                      dotData: FlDotData(show: values.length <= 20),
                      belowBarData: BarAreaData(show: true, color: Colors.purple.withAlpha(25)),
                    ),
                  ],
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (spots) => spots.map((s) {
                        final idx = s.spotIndex;
                        final d = idx < data.length ? (data[idx]['date'] as String? ?? '') : '';
                        return LineTooltipItem(
                          '$d\n${s.y.toStringAsFixed(0)}min',
                          TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold),
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

  Widget _buildDensityChart(ThemeData theme) {
    final data = _densityData.reversed.toList();
    final densities = data.map((d) {
      final vol = (d['volume'] as num?)?.toDouble() ?? 0;
      final dur = (d['duration_seconds'] as int?) ?? 1;
      return dur > 0 ? vol / dur : 0.0;
    }).toList();

    if (densities.isEmpty) return const SizedBox.shrink();
    final maxVal = densities.fold<double>(0, (a, b) => a > b ? a : b);
    final avg = densities.fold<double>(0, (a, b) => a + b) / densities.length;

    return Card(
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
                Text(AppLocalizations.of(context)!.progressDensityAverage(avg.toStringAsFixed(1)),
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 11)),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 120,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxVal * 1.2,
                  barTouchData: BarTouchData(enabled: false),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true, reservedSize: 32,
                        getTitlesWidget: (v, _) => Text('${v.toStringAsFixed(0)}',
                            style: theme.textTheme.bodySmall?.copyWith(fontSize: 8)),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true, reservedSize: 16,
                        interval: data.length > 10 ? 2 : 1,
                        getTitlesWidget: (v, _) {
                          final idx = v.toInt();
                          if (idx < 0 || idx >= data.length) return const SizedBox.shrink();
                          final d = data[idx]['date'] as String? ?? '';
                          return Text(d.length >= 10 ? d.substring(5) : d,
                              style: theme.textTheme.bodySmall?.copyWith(fontSize: 7));
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(show: true, drawVerticalLine: false,
                    horizontalInterval: _niceInterval(maxVal / 4),
                  ),
                  barGroups: densities.asMap().entries.map((e) => BarChartGroupData(
                    x: e.key,
                    barRods: [
                      BarChartRodData(
                        toY: e.value,
                        color: Colors.purple.shade300,
                        width: 10,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(3), topRight: Radius.circular(3),
                        ),
                      ),
                    ],
                  )).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===================== RECOVERY CONTENT =====================

  Widget _buildRecoveryContent(ThemeData theme) {
    if (_isLoadingRecovery) return _sectionLoading(theme);
    if (!_loadedRecovery) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_feelingTrend.isNotEmpty) ...[
          Text(AppLocalizations.of(context)!.progressRecoveryFeeling,
              style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          _buildFeelingChart(theme),
          const SizedBox(height: 16),
        ],
        if (_feelingVsVolume.isNotEmpty) ...[
          Text(AppLocalizations.of(context)!.progressRecoveryFeelingVsVolume,
              style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          _buildFeelingVsVolumeChart(theme),
        ],
      ],
    );
  }

  Widget _buildFeelingChart(ThemeData theme) {
    final data = _feelingTrend.reversed.toList();
    final values = data.map((d) => (d['feeling_rating'] as int?)?.toDouble() ?? 0).toList();

    if (values.isEmpty) return const SizedBox.shrink();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          height: 130,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: 5.5,
              minY: 0.5,
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (g, gi, r, ri) {
                    final d = data[gi];
                    final date = d['date'] as String? ?? '';
                    final feeling = d['feeling_rating'] as int? ?? 0;
                    return BarTooltipItem(
                      '$date\n${'★' * feeling}',
                      TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 12),
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true, reservedSize: 24,
                    getTitlesWidget: (v, _) {
                      if (v < 1) return const SizedBox.shrink();
                      return Text('${'★' * v.toInt()}',
                          style: TextStyle(fontSize: 9, color: Colors.amber));
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true, reservedSize: 16,
                    interval: data.length > 12 ? 2 : 1,
                    getTitlesWidget: (v, _) {
                      final idx = v.toInt();
                      if (idx < 0 || idx >= data.length) return const SizedBox.shrink();
                      final d = data[idx]['date'] as String? ?? '';
                      return Text(d.length >= 10 ? d.substring(5) : d,
                          style: theme.textTheme.bodySmall?.copyWith(fontSize: 7));
                    },
                  ),
                ),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: false),
              gridData: FlGridData(
                show: true, drawVerticalLine: false,
                horizontalInterval: 1,
              ),
              barGroups: values.asMap().entries.map((e) => BarChartGroupData(
                x: e.key,
                barRods: [
                  BarChartRodData(
                    toY: e.value,
                    color: e.value >= 4 ? Colors.green : e.value >= 3 ? Colors.amber : Colors.red.shade300,
                    width: 10,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(3), topRight: Radius.circular(3),
                    ),
                  ),
                ],
              )).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeelingVsVolumeChart(ThemeData theme) {
    final loc = AppLocalizations.of(context)!;
    final maxVol = _feelingVsVolume.fold<double>(0, (a, b) {
      final v = (b['avg_volume'] as num?)?.toDouble() ?? 0;
      return a > v ? a : v;
    });

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          height: 140,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxVol * 1.2,
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (g, gi, r, ri) {
                    final d = _feelingVsVolume[gi];
                    final feeling = d['feeling_rating'] as int? ?? 0;
                    final vol = (d['avg_volume'] as num?)?.toDouble() ?? 0;
                    final count = d['workout_count'] as int? ?? 0;
                    return BarTooltipItem(
                      '${'★' * feeling}\n${loc.commonVolume}: ${_formatVolume(vol)}\n$count ${loc.progressWorkouts}',
                      TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 11),
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true, reservedSize: 20,
                    getTitlesWidget: (v, _) {
                      final idx = v.toInt();
                      if (idx < 0 || idx >= _feelingVsVolume.length) return const SizedBox.shrink();
                      final feeling = _feelingVsVolume[idx]['feeling_rating'] as int? ?? 0;
                      return Text('${'★' * feeling}',
                          style: TextStyle(fontSize: 10, color: Colors.amber));
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true, reservedSize: 32,
                    getTitlesWidget: (v, _) => Text(_formatVolume(v),
                        style: theme.textTheme.bodySmall?.copyWith(fontSize: 8)),
                  ),
                ),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: false),
              gridData: FlGridData(
                show: true, drawVerticalLine: false,
                horizontalInterval: _niceInterval(maxVol / 4),
              ),
              barGroups: _feelingVsVolume.asMap().entries.map((e) {
                final vol = (e.value['avg_volume'] as num?)?.toDouble() ?? 0;
                return BarChartGroupData(
                  x: e.key,
                  barRods: [
                    BarChartRodData(
                      toY: vol,
                      color: Colors.red.shade300,
                      width: 24,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(4), topRight: Radius.circular(4),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  // ===================== BODY CONTENT =====================

  Widget _buildBodyContent(ThemeData theme) {
    if (_isLoadingBody) return _sectionLoading(theme);
    if (!_loadedBody) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // === Summary cards grid ===
        if (_bodySummary.isNotEmpty) ...[
          _buildBodySummaryGrid(theme),
          const SizedBox(height: 16),
        ],

        // === Body composition chart ===
        if (_bodyComposition.isNotEmpty && _bodyComposition.length >= 2) ...[
          Text(AppLocalizations.of(context)!.progressBodyComposition,
              style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          _buildBodyCompositionChart(theme),
          const SizedBox(height: 16),
        ],

        // === Weight vs Volume chart ===
        if (_bodyData.isNotEmpty) ...[
          Text(AppLocalizations.of(context)!.progressBodyWeightVsVolume,
              style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          _buildBodyWeightChart(theme),
        ],

        // === Body measurements link ===
        const SizedBox(height: 12),
        _buildBodyTrackerLink(theme),
      ],
    );
  }

  Widget _buildBodySummaryGrid(ThemeData theme) {
    final types = [
      {'id': 'weight', 'name': AppLocalizations.of(context)!.bodyTrackerWeight, 'unit': 'kg', 'color': Colors.indigo, 'icon': Icons.monitor_weight},
      {'id': 'bodyFat', 'name': AppLocalizations.of(context)!.bodyTrackerBodyFat, 'unit': '%', 'color': Colors.orange, 'icon': Icons.water_drop},
      {'id': 'waist', 'name': AppLocalizations.of(context)!.bodyTrackerWaist, 'unit': 'cm', 'color': Colors.teal, 'icon': Icons.straighten},
      {'id': 'chest', 'name': AppLocalizations.of(context)!.bodyTrackerChest, 'unit': 'cm', 'color': Colors.blue, 'icon': Icons.straighten},
      {'id': 'arm', 'name': AppLocalizations.of(context)!.bodyTrackerArm, 'unit': 'cm', 'color': Colors.purple, 'icon': Icons.straighten},
      {'id': 'hip', 'name': AppLocalizations.of(context)!.bodyTrackerHip, 'unit': 'cm', 'color': Colors.cyan, 'icon': Icons.straighten},
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 1.5,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: types.length,
      itemBuilder: (ctx, i) {
        final t = types[i];
        final typeId = t['id'] as String;
        final color = t['color'] as Color;
        final icon = t['icon'] as IconData;
        final unit = t['unit'] as String;

        // Find latest and previous values
        Map<String, dynamic>? latest;
        Map<String, dynamic>? previous;
        try {
          latest = _bodySummary.firstWhere((s) => s['type'] == typeId);
        } catch (_) {}

        // Find previous from bodyComposition (has prev_value)
        if (latest != null && _bodyComposition.isNotEmpty) {
          final latestDate = latest['date'] as String? ?? '';
          for (final bc in _bodyComposition) {
            final bcDate = bc['date'] as String? ?? '';
            if (bcDate.compareTo(latestDate) < 0) {
              previous = bc;
              break;
            }
          }
        }

        final currentValue = latest != null ? (latest['value'] as num?)?.toDouble() : null;
        final prevValue = previous != null ? (previous[typeId] as num?)?.toDouble() : null;

        double? delta;
        if (currentValue != null && prevValue != null && prevValue > 0) {
          delta = currentValue - prevValue;
        }

        return Card(
          elevation: 0,
          color: color.withAlpha(12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: color.withAlpha(40)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(height: 4),
                Text(
                  currentValue != null ? '${currentValue.toStringAsFixed(1)}' : '--',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: currentValue != null ? null : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  t['name'] as String,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 8, color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (delta != null && delta != 0)
                  Text(
                    '${delta > 0 ? '+' : ''}${delta.toStringAsFixed(1)}$unit',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                      color: _isPositiveForType(typeId) ? (delta > 0 ? Colors.green : Colors.red)
                          : (delta > 0 ? Colors.red : Colors.green),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// For weight/bodyFat: increase is bad (red), decrease is good (green)
  /// For measurements: increase can be good (muscle) or neutral
  bool _isPositiveForType(String typeId) {
    return typeId == 'weight' || typeId == 'bodyFat';
  }

  Widget _buildBodyCompositionChart(ThemeData theme) {
    final data = _bodyComposition;
    if (data.isEmpty) return const SizedBox.shrink();

    final bodyFats = data.map((d) => (d['body_fat'] as num?)?.toDouble()).where((v) => v != null && v > 0).toList();
    final waists = data.map((d) => (d['waist'] as num?)?.toDouble()).where((v) => v != null && v > 0).toList();
    final chests = data.map((d) => (d['chest'] as num?)?.toDouble()).where((v) => v != null && v > 0).toList();

    // Get data points where we have both weight and at least one measurement
    final validData = data.where((d) {
      final w = (d['weight'] as num?)?.toDouble() ?? 0;
      return w > 0;
    }).toList();

    if (validData.length < 2) return const SizedBox.shrink();

    final maxWeight = validData.map((d) => (d['weight'] as num?)?.toDouble() ?? 0).reduce((a, b) => a > b ? a : b);

    return Card(
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
            // Legend
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _legendDotWeight(Colors.indigo, AppLocalizations.of(context)!.bodyTrackerWeight),
                if (bodyFats.isNotEmpty)
                  _legendDotWeight(Colors.orange, AppLocalizations.of(context)!.bodyTrackerBodyFat),
                if (waists.isNotEmpty)
                  _legendDotWeight(Colors.teal, AppLocalizations.of(context)!.bodyTrackerWaist),
                if (chests.isNotEmpty)
                  _legendDotWeight(Colors.blue, AppLocalizations.of(context)!.bodyTrackerChest),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: maxWeight * 1.15,
                  gridData: FlGridData(
                    show: true, drawVerticalLine: false,
                    horizontalInterval: _niceInterval(maxWeight / 4),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true, reservedSize: 36,
                        getTitlesWidget: (v, _) => Text(
                          v > 100 ? '${(v / 1000).toStringAsFixed(0)}k' : v.toStringAsFixed(0),
                          style: theme.textTheme.bodySmall?.copyWith(fontSize: 8),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true, reservedSize: 20,
                        interval: validData.length > 8 ? 2 : 1,
                        getTitlesWidget: (v, _) {
                          final idx = v.toInt();
                          if (idx < 0 || idx >= validData.length) return const SizedBox.shrink();
                          final d = validData[idx]['date'] as String? ?? '';
                          return Text(d.length >= 10 ? d.substring(5) : d,
                              style: theme.textTheme.bodySmall?.copyWith(fontSize: 7));
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    // Weight
                    LineChartBarData(
                      spots: validData.asMap().entries.map((e) {
                        final w = (e.value['weight'] as num?)?.toDouble() ?? 0;
                        return FlSpot(e.key.toDouble(), w);
                      }).toList(),
                      isCurved: true,
                      color: Colors.indigo,
                      barWidth: 3,
                      dotData: FlDotData(show: true, getDotPainter: (s, p, b, i) =>
                        FlDotCirclePainter(radius: 4, color: Colors.indigo)),
                      belowBarData: BarAreaData(show: false),
                    ),
                    // Body fat
                    if (bodyFats.length >= 2)
                      LineChartBarData(
                        spots: validData.asMap().entries.map((e) {
                          final bf = (e.value['body_fat'] as num?)?.toDouble();
                          return FlSpot(e.key.toDouble(), bf ?? 0);
                        }).where((s) => s.y > 0).toList(),
                        isCurved: true,
                        color: Colors.orange,
                        barWidth: 2,
                        dashArray: [6, 3],
                        dotData: FlDotData(show: false),
                        belowBarData: BarAreaData(show: false),
                      ),
                    // Waist
                    if (waists.length >= 2)
                      LineChartBarData(
                        spots: validData.asMap().entries.map((e) {
                          final w = (e.value['waist'] as num?)?.toDouble();
                          return FlSpot(e.key.toDouble(), w ?? 0);
                        }).where((s) => s.y > 0).toList(),
                        isCurved: true,
                        color: Colors.teal,
                        barWidth: 2,
                        dashArray: [3, 3],
                        dotData: FlDotData(show: false),
                        belowBarData: BarAreaData(show: false),
                      ),
                  ],
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (spots) => spots.map((s) {
                        final idx = s.spotIndex;
                        final d = idx < validData.length ? (validData[idx]['date'] as String? ?? '') : '';
                        String label;
                        if (s.barIndex == 0) label = '${AppLocalizations.of(context)!.bodyTrackerWeight}: ${s.y.toStringAsFixed(1)}kg';
                        else if (s.barIndex == 1) label = '${AppLocalizations.of(context)!.bodyTrackerBodyFat}: ${s.y.toStringAsFixed(1)}%';
                        else label = '${AppLocalizations.of(context)!.bodyTrackerWaist}: ${s.y.toStringAsFixed(1)}cm';
                        return LineTooltipItem(
                          '$d\n$label',
                          TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 10),
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

  Widget _buildBodyWeightChart(ThemeData theme) {
    if (_bodyData.isEmpty) return const SizedBox.shrink();

    final loc = AppLocalizations.of(context)!;
    final weights = _bodyData.map((d) => (d['weight'] as num?)?.toDouble() ?? 0).toList();
    final volumes = _bodyData.map((d) => (d['volume'] as num?)?.toDouble() ?? 0).toList();
    final maxWeight = weights.fold<double>(0, (a, b) => a > b ? a : b);
    final maxVolume = volumes.fold<double>(0, (a, b) => a > b ? a : b);

    if (maxWeight <= 0) return const SizedBox.shrink();

    return Card(
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
                _legendDotWeight(Colors.indigo, AppLocalizations.of(context)!.progressBodyWeight),
                const SizedBox(width: 16),
                _legendDotWeight(Colors.teal, AppLocalizations.of(context)!.commonVolume),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 180,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: maxWeight > maxVolume ? maxWeight * 1.15 : maxVolume * 1.15,
                  gridData: FlGridData(
                    show: true, drawVerticalLine: false,
                    horizontalInterval: _niceInterval((maxWeight > maxVolume ? maxWeight : maxVolume) / 4),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true, reservedSize: 36,
                        getTitlesWidget: (v, _) => Text(v > 100 ? '${(v / 1000).toStringAsFixed(0)}k' : v.toStringAsFixed(0),
                            style: theme.textTheme.bodySmall?.copyWith(fontSize: 8)),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true, reservedSize: 20,
                        interval: _bodyData.length > 8 ? 2 : 1,
                        getTitlesWidget: (v, _) {
                          final idx = v.toInt();
                          if (idx < 0 || idx >= _bodyData.length) return const SizedBox.shrink();
                          final d = _bodyData[idx]['date'] as String? ?? '';
                          return Text(d.length >= 10 ? d.substring(5) : d,
                              style: theme.textTheme.bodySmall?.copyWith(fontSize: 7));
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    // Weight line
                    LineChartBarData(
                      spots: weights.asMap().entries.map((e) =>
                        FlSpot(e.key.toDouble(), e.value)).toList(),
                      isCurved: true,
                      color: Colors.indigo,
                      barWidth: 3,
                      dotData: FlDotData(show: true, getDotPainter: (s, p, b, i) =>
                        FlDotCirclePainter(radius: 4, color: Colors.indigo)),
                      belowBarData: BarAreaData(show: false),
                    ),
                    // Volume line
                    if (maxVolume > 0)
                      LineChartBarData(
                        spots: volumes.asMap().entries.map((e) =>
                          FlSpot(e.key.toDouble(), e.value)).toList(),
                        isCurved: true,
                        color: Colors.teal,
                        barWidth: 2,
                        dashArray: [6, 3],
                        dotData: FlDotData(show: true, getDotPainter: (s, p, b, i) =>
                          FlDotCirclePainter(radius: 3, color: Colors.teal)),
                        belowBarData: BarAreaData(show: false),
                      ),
                  ],
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (spots) => spots.map((s) {
                        final idx = s.spotIndex;
                        final d = idx < _bodyData.length ? (_bodyData[idx]['date'] as String? ?? '') : '';
                        final isWeight = s.barIndex == 0;
                        return LineTooltipItem(
                          '$d\n${isWeight ? '${loc.progressBodyWeight}: ${s.y.toStringAsFixed(1)}${loc.workoutDetailKg}' : '${loc.commonVolume}: ${_formatVolume(s.y)}'}',
                          TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 11),
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

  Widget _legendDotWeight(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(
          color: color, shape: BoxShape.circle,
        )),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 10)),
      ],
    );
  }

  Widget _buildBodyTrackerLink(ThemeData theme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => const BodyTrackerScreen(),
          ));
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.indigo.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.accessibility_new, size: 20, color: Colors.indigo),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.progressBodyMeasurements,
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      AppLocalizations.of(context)!.progressBodyMeasurementsSubtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  // ===================== MONTHLY VOLUME CHART (existing) =====================

  Widget _buildMonthlyVolumeChart(ThemeData theme) {
    final loc = AppLocalizations.of(context)!;
    final volumes = _monthlyVolume.map((m) => (m['volume'] as double?) ?? 0).toList();
    final maxVol = volumes.fold<double>(0, (a, b) => a > b ? a : b);
    if (maxVol <= 0) return const SizedBox.shrink();

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
            Text(loc.progressVolumeByMonth, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            SizedBox(
              height: 180,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxVol * 1.15,
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final m = _monthlyVolume[groupIndex];
                        final month = m['month'] as String? ?? '';
                        final vol = (m['volume'] as double?) ?? 0;
                        final wo = (m['workouts'] as int?) ?? 0;
                        return BarTooltipItem(
                          '${_monthLabel(month)}\n${_formatVolume(vol)}\n$wo ${loc.progressWorkouts}',
                          TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 12),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (v, _) {
                          final idx = v.toInt();
                          if (idx < 0 || idx >= _monthlyVolume.length) return const SizedBox.shrink();
                          final month = _monthlyVolume[idx]['month'] as String? ?? '';
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              month.length >= 7 ? month.substring(5, 7) : '',
                              style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
                            ),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 36,
                        getTitlesWidget: (v, _) {
                          if (v == 0) return const SizedBox.shrink();
                          return Text(
                            _formatVolume(v),
                            style: theme.textTheme.bodySmall?.copyWith(fontSize: 9),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: maxVol > 0 ? _niceInterval(maxVol / 4) : 1,
                  ),
                  barGroups: _monthlyVolume.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final vol = (entry.value['volume'] as double?) ?? 0;
                    return BarChartGroupData(
                      x: idx,
                      barRods: [
                        BarChartRodData(
                          toY: vol,
                          color: theme.colorScheme.primary,
                          width: 20,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(4),
                            topRight: Radius.circular(4),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =======================================================================
  // EXERCISE DETAIL VIEW (enhanced)
  // =======================================================================

  Widget _buildExerciseDetail(ThemeData theme) {
    if (_selectedHistory == null) return const SizedBox.shrink();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Expanded(child: _buildExerciseSelector(theme)),
            ],
          ),
        ),
        const SizedBox(height: 4),
        _buildChartTypeSelector(theme, AppLocalizations.of(context)!),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildRecords(theme),
                const SizedBox(height: 16),
                _buildChart(theme),
                const SizedBox(height: 16),
                _buildHistorySection(theme),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExerciseSelector(ThemeData theme) {
    final selectedEx = _allExercises.firstWhere(
      (e) => e['id'] == (_selectedHistory?['exercise_id']),
      orElse: () => <String, dynamic>{},
    );

    return DropdownButtonFormField<String>(
      value: selectedEx['id'] as String?,
      decoration: InputDecoration(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      isExpanded: true,
      items: _allExercises.map((ex) => DropdownMenuItem(
        value: ex['id'] as String,
        child: Row(
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(
              color: Color(ex['category_color'] as int? ?? 0xFF757575),
              shape: BoxShape.circle,
            )),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                ExerciseLocaleHelper.exerciseName(AppLocalizations.of(context)!, ex),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                ),
              ),
            ),
          ],
        ),
      )).toList(),
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
          children: List.generate(_chartTypes(AppLocalizations.of(context)!).length, (i) {
            final isSelected = _selectedChartType == i;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(_chartTypes(AppLocalizations.of(context)!)[i], style: TextStyle(fontSize: 12)),
                selected: isSelected,
                onSelected: (_) => setState(() => _selectedChartType = i),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildRecords(ThemeData theme) {
    final bestWeight = (_selectedHistory!['best_weight'] as double?) ?? 0;
    final bestVolume = (_selectedHistory!['best_volume'] as double?) ?? 0;
    final best1RM = (_selectedHistory!['best_1rm'] as double?) ?? 0;

    return Row(
      children: [
        Expanded(child: _StatCard(
          label: AppLocalizations.of(context)!.exerciseDetailChartMaxWeight, value: bestWeight > 0 ? '${bestWeight.toStringAsFixed(1)}' : '--',
          icon: Icons.monitor_weight, color: theme.colorScheme.primary,
        )),
        const SizedBox(width: 8),
        Expanded(child: _StatCard(
          label: AppLocalizations.of(context)!.commonVolume, value: bestVolume > 0 ? '${_formatVolume(bestVolume)}' : '--',
          icon: Icons.auto_graph, color: theme.colorScheme.secondary,
        )),
        const SizedBox(width: 8),
        Expanded(child: _StatCard(
          label: AppLocalizations.of(context)!.exerciseDetailChart1RM, value: best1RM > 0 ? '${best1RM.toStringAsFixed(1)}' : '--',
          icon: Icons.emoji_events, color: Colors.amber,
        )),
      ],
    );
  }

  Widget _buildChart(ThemeData theme) {
    final history = _selectedHistory!['history'] as List? ?? [];

    String title;
    List<double> values;

    switch (_selectedChartType) {
      case 0:
        title = '${AppLocalizations.of(context)!.exerciseDetailChart1RM} ${AppLocalizations.of(context)!.progressChartTitleProgress}';
        values = history.map((h) => (h['estimated_1rm'] as double?) ?? 0).toList();
        break;
      case 1:
        title = AppLocalizations.of(context)!.exerciseDetailChartMaxWeight;
        values = history.map((h) => (h['max_weight'] as double?) ?? 0).toList();
        break;
      case 2:
        title = AppLocalizations.of(context)!.progressChartTitleVolumePerWorkout;
        values = history.map((h) => (h['total_volume'] as double?) ?? 0).toList();
        break;
      case 3:
        title = AppLocalizations.of(context)!.progressChartTitleRepsPerWorkout;
        values = history.map((h) => (h['total_reps'] as int?)?.toDouble() ?? 0).toList();
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
          side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Icon(Icons.bar_chart_outlined, size: 48, color: theme.colorScheme.onSurfaceVariant.withAlpha(80)),
              const SizedBox(height: 12),
              Text(AppLocalizations.of(context)!.progressNoChartData,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      );
    }

    final range = maxVal - minVal;
    final interval = _niceInterval(range);

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
                Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('${history.length} ${AppLocalizations.of(context)!.progressWorkouts.toLowerCase()}', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
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
                              _selectedChartType == 3 ? '${v.toInt()}' : '${v.toStringAsFixed(1)}',
                              style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
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
                          if (idx < 0 || idx >= history.length) return const SizedBox.shrink();
                          final date = history[idx]['date'] as String? ?? '';
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              date.length >= 10 ? date.substring(5) : date,
                              style: theme.textTheme.bodySmall?.copyWith(fontSize: 9),
                            ),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: values.asMap().entries.map((e) =>
                        FlSpot(e.key.toDouble(), e.value)).toList(),
                      isCurved: true,
                      color: _selectedChartType == 0
                          ? Colors.amber
                          : _selectedChartType == 2
                              ? theme.colorScheme.secondary
                              : theme.colorScheme.primary,
                      barWidth: 3,
                      dotData: FlDotData(
                        show: history.length <= 30,
                        getDotPainter: (spot, percent, bar, index) =>
                            FlDotCirclePainter(
                              radius: 4,
                              color: _selectedChartType == 0
                                  ? Colors.amber
                                  : _selectedChartType == 2
                                      ? theme.colorScheme.secondary
                                      : theme.colorScheme.primary,
                            ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        color: (_selectedChartType == 0
                            ? Colors.amber
                            : _selectedChartType == 2
                                ? theme.colorScheme.secondary
                                : theme.colorScheme.primary).withAlpha(30),
                      ),
                    ),
                  ],
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (touchedSpots) => touchedSpots.map((spot) {
                        final idx = spot.spotIndex;
                        final date = idx < history.length
                            ? (history[idx]['date'] as String? ?? '')
                            : '';
                        return LineTooltipItem(
                          '$date\n${spot.y.toStringAsFixed(1)}',
                          TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold),
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
    final history = _selectedHistory!['history'] as List? ?? [];
    if (history.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(AppLocalizations.of(context)!.progressHistoryTitle, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(flex: 2, child: Text(AppLocalizations.of(context)!.progressHistoryDate, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold))),
              Expanded(flex: 2, child: Text(AppLocalizations.of(context)!.workoutDetailWeight, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold))),
              Expanded(flex: 2, child: Text(AppLocalizations.of(context)!.commonVolume, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold))),
              Expanded(flex: 2, child: Text(AppLocalizations.of(context)!.progressHistorySetsReps, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold))),
              Expanded(flex: 2, child: Text(AppLocalizations.of(context)!.exerciseDetailChart1RM, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold))),
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
                        builder: (_) => WorkoutDetailScreen(workoutId: workoutId),
                      ),
                    )
                  : null,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withAlpha(60),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(flex: 2, child: Text(date.length >= 10 ? date.substring(5) : date,
                        style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600))),
                    Expanded(flex: 2, child: Text(maxW > 0 ? '${maxW.toStringAsFixed(1)}' : '-',
                        style: theme.textTheme.bodySmall)),
                    Expanded(flex: 2, child: Text(vol > 0 ? '${vol.toStringAsFixed(0)}' : '-',
                        style: theme.textTheme.bodySmall)),
                    Expanded(flex: 2, child: Text('$sets×$reps',
                        style: theme.textTheme.bodySmall)),
                    Expanded(flex: 2, child: Text(est1RM != null ? '${est1RM.toStringAsFixed(1)}' : '-',
                        style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: Colors.amber[700]))),
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

// =======================================================================
// STATIC WIDGETS
// =======================================================================

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: color.withAlpha(15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(value, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, fontSize: 12)),
            Text(label, style: theme.textTheme.bodySmall?.copyWith(fontSize: 10, color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final ThemeData theme;
  final int? delta;

  const _MiniStat({
    required this.icon, required this.label, required this.value,
    required this.color, required this.theme, this.delta,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 3),
              Text(value, style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold, fontSize: 13,
              )),
            ],
          ),
          const SizedBox(height: 1),
          Text(label, style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 9, color: theme.colorScheme.onSurfaceVariant,
          )),
          if (delta != null && delta != 0)
            Text(
              '${delta! > 0 ? '+' : ''}$delta',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: delta! > 0 ? Colors.green : Colors.red,
              ),
            ),
        ],
      ),
    );
  }
}

class _WeekBar {
  final String label;
  final int count;
  _WeekBar(this.label, this.count);
}

// =======================================================================
// EXERCISE DETAIL BOTTOM SHEET (lazy loaded on tap)
// =======================================================================

class _ExerciseDetailSheet extends StatefulWidget {
  final String exerciseId;
  final String exerciseName;
  final DatabaseHelper db;

  const _ExerciseDetailSheet({
    required this.exerciseId,
    required this.exerciseName,
    required this.db,
  });

  @override
  State<_ExerciseDetailSheet> createState() => _ExerciseDetailSheetState();
}

class _ExerciseDetailSheetState extends State<_ExerciseDetailSheet> {
  Map<String, dynamic>? _history;
  bool _isLoading = true;
  int _chartType = 0;

  List<String> _chartTypes(AppLocalizations loc) => [
    AppLocalizations.of(context)!.exerciseDetailChart1RM,
    AppLocalizations.of(context)!.exerciseDetailChartMaxWeight,
    AppLocalizations.of(context)!.exerciseDetailChartVolume,
    AppLocalizations.of(context)!.exerciseDetailChartTotalReps,
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await widget.db.getExerciseHistory(widget.exerciseId, limit: 30);
    if (!mounted) return;
    setState(() {
      _history = data;
      _isLoading = false;
    });
  }

  String _formatVolume(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.toStringAsFixed(0);
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
                width: 40, height: 4,
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
                      child: Text(widget.exerciseName,
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
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
                  child: Center(child: Text(AppLocalizations.of(context)!.progressLoadError)),
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
                  label: Text(_chartTypes(loc)[i], style: TextStyle(fontSize: 12)),
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
        Expanded(child: _StatCard(
          label: AppLocalizations.of(context)!.exerciseDetailChartMaxWeight, value: bestWeight > 0 ? '${bestWeight.toStringAsFixed(1)}' : '--',
          icon: Icons.monitor_weight, color: theme.colorScheme.primary,
        )),
        const SizedBox(width: 8),
        Expanded(child: _StatCard(
          label: AppLocalizations.of(context)!.commonVolume, value: bestVolume > 0 ? '${_formatVolume(bestVolume)}' : '--',
          icon: Icons.auto_graph, color: theme.colorScheme.secondary,
        )),
        const SizedBox(width: 8),
        Expanded(child: _StatCard(
          label: AppLocalizations.of(context)!.exerciseDetailChart1RM, value: best1RM > 0 ? '${best1RM.toStringAsFixed(1)}' : '--',
          icon: Icons.emoji_events, color: Colors.amber,
        )),
      ],
    );
  }

  double _niceInterval(double range) {
    if (range <= 0) return 1;
    final rough = range / 5;
    double magnitude = 1;
    double temp = rough;
    while (temp >= 10) { temp /= 10; magnitude *= 10; }
    while (temp < 1) { temp *= 10; magnitude /= 10; }
    if (temp <= 1) temp = 1;
    else if (temp <= 2) temp = 2;
    else if (temp <= 5) temp = 5;
    else temp = 10;
    final result = temp * magnitude;
    return result < 0.5 ? 0.5 : result;
  }

  Widget _buildChart(ThemeData theme) {
    final history = _history!['history'] as List? ?? [];

    String title;
    List<double> values;

    switch (_chartType) {
      case 0:
        title = '${AppLocalizations.of(context)!.exerciseDetailChart1RM} ${AppLocalizations.of(context)!.progressChartTitleProgress}';
        values = history.map((h) => (h['estimated_1rm'] as double?) ?? 0).toList();
        break;
      case 1:
        title = AppLocalizations.of(context)!.exerciseDetailChartMaxWeight;
        values = history.map((h) => (h['max_weight'] as double?) ?? 0).toList();
        break;
      case 2:
        title = AppLocalizations.of(context)!.progressChartTitleVolumePerWorkout;
        values = history.map((h) => (h['total_volume'] as double?) ?? 0).toList();
        break;
      case 3:
        title = AppLocalizations.of(context)!.progressChartTitleRepsPerWorkout;
        values = history.map((h) => (h['total_reps'] as int?)?.toDouble() ?? 0).toList();
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
          side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Icon(Icons.bar_chart_outlined, size: 48, color: theme.colorScheme.onSurfaceVariant.withAlpha(80)),
              const SizedBox(height: 12),
              Text(AppLocalizations.of(context)!.progressNoChartData,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      );
    }

    final range = maxVal - minVal;
    final interval = _niceInterval(range);

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
                Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('${history.length} ${AppLocalizations.of(context)!.progressWorkouts.toLowerCase()}', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
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
                              _chartType == 3 ? '${v.toInt()}' : '${v.toStringAsFixed(1)}',
                              style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
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
                          if (idx < 0 || idx >= history.length) return const SizedBox.shrink();
                          final date = history[idx]['date'] as String? ?? '';
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              date.length >= 10 ? date.substring(5) : date,
                              style: theme.textTheme.bodySmall?.copyWith(fontSize: 9),
                            ),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
                                : theme.colorScheme.primary).withAlpha(30),
                      ),
                    ),
                  ],
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (touchedSpots) => touchedSpots.map((spot) {
                        final idx = spot.spotIndex;
                        final date = idx < history.length
                            ? (history[idx]['date'] as String? ?? '')
                            : '';
                        return LineTooltipItem(
                          '$date\n${spot.y.toStringAsFixed(1)}',
                          TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(AppLocalizations.of(context)!.progressHistoryTitle, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(flex: 2, child: Text(AppLocalizations.of(context)!.progressHistoryDate, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold))),
              Expanded(flex: 2, child: Text(AppLocalizations.of(context)!.workoutDetailWeight, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold))),
              Expanded(flex: 2, child: Text(AppLocalizations.of(context)!.commonVolume, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold))),
              Expanded(flex: 2, child: Text(AppLocalizations.of(context)!.progressHistorySetsReps, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold))),
              Expanded(flex: 2, child: Text(AppLocalizations.of(context)!.exerciseDetailChart1RM, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold))),
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
                        builder: (_) => WorkoutDetailScreen(workoutId: workoutId),
                      ),
                    )
                  : null,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withAlpha(60),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(flex: 2, child: Text(date.length >= 10 ? date.substring(5) : date,
                        style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600))),
                    Expanded(flex: 2, child: Text(maxW > 0 ? '${maxW.toStringAsFixed(1)}' : '-',
                        style: theme.textTheme.bodySmall)),
                    Expanded(flex: 2, child: Text(vol > 0 ? '${vol.toStringAsFixed(0)}' : '-',
                        style: theme.textTheme.bodySmall)),
                    Expanded(flex: 2, child: Text('$sets×$reps',
                        style: theme.textTheme.bodySmall)),
                    Expanded(flex: 2, child: Text(est1RM != null ? '${est1RM.toStringAsFixed(1)}' : '-',
                        style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: Colors.amber[700]))),
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
