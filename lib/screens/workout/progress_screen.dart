import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/repositories/analytics_repository.dart';
import 'package:workout_notes/repositories/exercise_repository.dart';
import 'package:workout_notes/repositories/body_measurement_repository.dart';
import 'package:workout_notes/utils/pace_calculator.dart';
import 'package:workout_notes/widgets/collapsible_section.dart';
import 'package:workout_notes/widgets/progress/monthly_report_card.dart';
import 'package:workout_notes/widgets/progress/monthly_volume_chart.dart';
import 'package:workout_notes/widgets/progress/progress_stat_cards.dart';
import 'package:workout_notes/widgets/progress/frequency_charts.dart';
import 'package:workout_notes/widgets/progress/volume_charts.dart';
import 'package:workout_notes/widgets/progress/performance_section.dart';
import 'package:workout_notes/widgets/progress/duration_recovery_charts.dart';
import 'package:workout_notes/widgets/progress/body_section_charts.dart';
import 'package:workout_notes/widgets/progress/exercise_detail_sheet.dart';
import 'package:workout_notes/widgets/progress/exercise_detail_view.dart';
import 'package:workout_notes/widgets/progress/cardio_charts.dart';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  final _analytics = AnalyticsRepository();
  final _exerciseRepo = ExerciseRepository();
  final _bodyRepo = BodyMeasurementRepository();

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
  bool _isLoadingCardio = false;
  bool _loadedFrequency = false;
  bool _loadedVolume = false;
  bool _loadedPerformance = false;
  bool _loadedDuration = false;
  bool _loadedRecovery = false;
  bool _loadedBody = false;
  bool _loadedCardio = false;

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

  // === CARDIO DATA ===
  List<Map<String, dynamic>> _cardioWeeklyData = [];
  List<Map<String, dynamic>> _cardioModalityData = [];
  List<Map<String, dynamic>> _paceTrendData = [];
  List<Map<String, dynamic>> _cardioPRs = [];
  Map<String, dynamic>? _monthlyCardioStats;
  String? _selectedPaceExerciseId;
  String? _selectedPaceExerciseName;
  int _exerciseFilter = 0; // 0=all, 1=strength, 2=cardio

  // === EXERCISE DETAIL STATE ===
  Map<String, dynamic>? _selectedHistory;
  bool _showingOverview = true;

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
      final results = await Future.wait([
        _analytics.getWorkoutOverviewStats(),
        _analytics.getMonthlyVolume(),
        _analytics.getMonthlyReport(now.year, now.month),
        _analytics.getMonthComparison(now.year, now.month),
        _analytics.getMonthlyCardioStats(now.year, now.month),
      ]);

      if (!mounted) return;

      _overviewStats = results[0] as Map<String, dynamic>;
      _monthlyVolume = results[1] as List<Map<String, dynamic>>;
      _monthReport = results[2] as Map<String, dynamic>;
      _monthComparison = results[3] as Map<String, dynamic>;
      _monthlyCardioStats = results[4] as Map<String, dynamic>;

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
        _analytics.getYearlyHeatmapData(now.year),
        _analytics.getWorkoutDatesInRange(DateTime(now.year, 1, 1)),
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
        _analytics.getVolumeByCategory(),
        _analytics.getTopExercisesByVolume(),
        _analytics.getEnergySystemDistribution(),
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
      _allExercises = await _exerciseRepo.getExercises();
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
        _analytics.getDurationTrend(),
        _analytics.getWorkoutDensity(),
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
        _analytics.getFeelingTrend(),
        _analytics.getFeelingVsVolume(),
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
        _analytics.getBodyWeightWithVolume(),
        _bodyRepo.getBodyMeasurementsSummary(),
        _bodyRepo.getBodyCompositionTrend(),
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

  Future<void> _loadCardio() async {
    if (_loadedCardio) return;
    setState(() => _isLoadingCardio = true);
    final now = DateTime.now();
    try {
      // Ensure exercises are loaded for the pace selector
      final futures = <Future>[
        _analytics.getCardioWeeklyDistance(),
        _analytics.getCardioDistanceByModality(),
        _analytics.getCardioPRs(),
        _analytics.getMonthlyCardioStats(now.year, now.month),
      ];
      if (!_loadedPerformance) {
        futures.add(_exerciseRepo.getExercises());
      }
      final results = await Future.wait(futures);
      if (!mounted) return;
      _cardioWeeklyData = results[0] as List<Map<String, dynamic>>;
      _cardioModalityData = results[1] as List<Map<String, dynamic>>;
      _cardioPRs = results[2] as List<Map<String, dynamic>>;
      _monthlyCardioStats = results[3] as Map<String, dynamic>;
      if (!_loadedPerformance && results.length > 4) {
        _allExercises = results[4] as List<Map<String, dynamic>>;
        _loadedPerformance = true;
      }
      _loadedCardio = true;
      setState(() => _isLoadingCardio = false);
    } catch (_) {
      if (mounted) setState(() => _isLoadingCardio = false);
    }
  }

  /// Loads pace trend for a specific cardio exercise.
  Future<void> _loadPaceForExercise(String exerciseId, String exerciseName) async {
    _selectedPaceExerciseId = exerciseId;
    _selectedPaceExerciseName = exerciseName;
    try {
      _paceTrendData = await _analytics.getPaceTrend(exerciseId);
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  // =======================================================================
  // HELPERS
  // =======================================================================


  Widget _sectionLoading(ThemeData theme) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  /// Shows a modal bottom sheet with full exercise history/charts.
  Future<void> _showExercisePopup(
      String exerciseId, String exerciseName, ThemeData theme) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => ExerciseDetailSheet(
        exerciseId: exerciseId,
        exerciseName: exerciseName,
        analytics: _analytics,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _showingOverview
              ? AppLocalizations.of(context)!.progressTitle
              : (_selectedHistory?['exercise_name'] as String? ??
                  AppLocalizations.of(context)!.progressTitle),
        ),
        centerTitle: true,
        leading: _showingOverview
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () =>
                    setState(() => _showingOverview = true),
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
          MonthlyReportCard(
            report: _monthReport,
            comparison: _monthComparison,
          ),
          const SizedBox(height: 12),

          // Enhanced stats row
          _buildStatsRow(theme),
          const SizedBox(height: 8),

          // Monthly volume chart
          if (_monthlyVolume.isNotEmpty) ...[
            MonthlyVolumeChart(data: _monthlyVolume),
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

          // ── Cardio Section ──
          _buildDivider(theme),
          CollapsibleSection(
            title: AppLocalizations.of(context)!.progressCardio,
            icon: Icons.directions_run,
            iconColor: const Color(0xFFE53935),
            onExpanded: _loadCardio,
            child: _buildCardioContent(theme),
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
    return Divider(
        height: 1,
        color: theme.colorScheme.outlineVariant.withAlpha(60));
  }

  // ===================== STATS ROW =====================

  Widget _buildStatsRow(ThemeData theme) {
    final stats = _overviewStats;
    final totalWorkouts = (stats?['total_workouts'] as int?) ?? 0;
    final totalSets = (stats?['total_sets'] as int?) ?? 0;
    final totalVolume = (stats?['total_volume'] as int?) ?? 0;
    final streak = (stats?['current_streak'] as int?) ?? 0;

    final cardioStats = _monthlyCardioStats;
    final cardioDist = (cardioStats?['total_distance'] as num?)?.toDouble() ?? 0;
    final cardioTime = (cardioStats?['total_time'] as int?) ?? 0;
    final cardioTimeMin = cardioTime ~/ 60;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: ProgressStatCard(
                label: AppLocalizations.of(context)!.progressWorkouts,
                value: '$totalWorkouts',
                icon: Icons.fitness_center,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: ProgressStatCard(
                label: AppLocalizations.of(context)!.progressSets,
                value: '$totalSets',
                icon: Icons.repeat,
                color: theme.colorScheme.secondary,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: ProgressStatCard(
                label: AppLocalizations.of(context)!.progressStreak,
                value: '$streak ${streak == 1 ? AppLocalizations.of(context)!.workoutHomeDay : AppLocalizations.of(context)!.workoutHomeDays}',
                icon: Icons.local_fire_department,
                color: Colors.orange,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: ProgressStatCard(
                label: AppLocalizations.of(context)!.commonVolume,
                value: totalVolume >= 1000
                    ? '${(totalVolume / 1000).toStringAsFixed(1)}k'
                    : '$totalVolume',
                icon: Icons.auto_graph,
                color: Colors.teal,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: ProgressStatCard(
                label: AppLocalizations.of(context)!.workoutHomeCardioDistance,
                value: PaceCalculator.formatDistance(cardioDist),
                icon: Icons.map,
                color: const Color(0xFFE53935),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: ProgressStatCard(
                label: AppLocalizations.of(context)!.workoutHomeCardioTime,
                value: cardioTimeMin >= 60
                    ? '${cardioTimeMin ~/ 60}h${cardioTimeMin % 60}'
                    : '${cardioTimeMin}min',
                icon: Icons.timer_outlined,
                color: Colors.deepOrange,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ===================== FREQUENCY CONTENT =====================

  Widget _buildFrequencyContent(ThemeData theme) {
    if (_isLoadingFrequency) return _sectionLoading(theme);
    if (!_loadedFrequency) return const SizedBox.shrink();
    return FrequencyCharts(
      heatmapData: _heatmapData,
      workoutDates: _workoutDates,
      year: DateTime.now().year,
    );
  }

  // ===================== CARDIO CONTENT =====================

  Widget _buildCardioContent(ThemeData theme) {
    final loc = AppLocalizations.of(context)!;
    if (_isLoadingCardio) return _sectionLoading(theme);
    if (!_loadedCardio) return const SizedBox.shrink();

    final cardioStats = _monthlyCardioStats;
    final totalDist = (cardioStats?['total_distance'] as num?)?.toDouble() ?? 0;
    final totalTime = (cardioStats?['total_time'] as int?) ?? 0;
    final cardioSessions = (cardioStats?['cardio_sessions'] as int?) ?? 0;
    double? avgPace;
    if (totalDist > 0 && totalTime > 0) {
      avgPace = totalTime / totalDist;
    }

    // Compute cardio exercises list for pace trend selector
    final cardioExercises = _allExercises
        .where((e) => (e['category_energy'] as String?) == 'aerobic')
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CardioHeader(
          totalDistance: totalDist,
          avgPaceSeconds: avgPace,
          totalTimeSeconds: totalTime,
          sessionCount: cardioSessions,
        ),
        const SizedBox(height: 12),

        if (_cardioWeeklyData.isNotEmpty) ...[
          WeeklyDistanceChart(data: _cardioWeeklyData),
          const SizedBox(height: 8),
        ],

        if (_cardioModalityData.isNotEmpty) ...[
          DistanceByModalityChart(data: _cardioModalityData),
          const SizedBox(height: 8),
        ],

        // Pace trend with exercise selector
        if (cardioExercises.isNotEmpty) ...[
          _buildPaceSelector(theme, loc, cardioExercises),
          const SizedBox(height: 8),
        ],

        PaceTrendChart(
          paceData: _paceTrendData,
          selectedExerciseName: _selectedPaceExerciseName,
        ),
        const SizedBox(height: 8),

        CardioPRsCard(prs: _cardioPRs),
      ],
    );
  }

  Widget _buildPaceSelector(ThemeData theme, AppLocalizations loc, List<Map<String, dynamic>> exercises) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.search, size: 16, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  hint: Text(loc.progressSelectExercise, style: theme.textTheme.bodySmall),
                  value: _selectedPaceExerciseId,
                  items: exercises.map((e) {
                    final id = e['id'] as String? ?? '';
                    final name = e['name'] as String? ?? '';
                    return DropdownMenuItem(value: id, child: Text(name, style: theme.textTheme.bodySmall));
                  }).toList(),
                  onChanged: (id) {
                    if (id != null) {
                      final ex = exercises.firstWhere((e) => e['id'] == id);
                      _loadPaceForExercise(id, ex['name'] as String? ?? '');
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===================== VOLUME CONTENT =====================

  Widget _buildVolumeContent(ThemeData theme) {
    if (_isLoadingVolume) return _sectionLoading(theme);
    if (!_loadedVolume) return const SizedBox.shrink();
    return VolumeCharts(
      volumeByCategory: _volumeByCategory,
      energySystems: _energySystems,
      topExercises: _topExercises,
    );
  }

  // ===================== PERFORMANCE CONTENT =====================

  Widget _buildPerformanceContent(ThemeData theme) {
    if (_isLoadingPerformance) return _sectionLoading(theme);
    if (!_loadedPerformance) return const SizedBox.shrink();
    final loc = AppLocalizations.of(context)!;

    // Filter based on selected tab
    List<Map<String, dynamic>> filtered;
    switch (_exerciseFilter) {
      case 1: // strength only
        filtered = _allExercises.where((e) => (e['category_energy'] as String?) != 'aerobic').toList();
        break;
      case 2: // cardio only
        filtered = _allExercises.where((e) => (e['category_energy'] as String?) == 'aerobic').toList();
        break;
      default:
        filtered = _allExercises;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Filter pills
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              _filterPill(loc.progressFilterAll, 0, theme),
              const SizedBox(width: 6),
              _filterPill(loc.progressFilterStrength, 1, theme),
              const SizedBox(width: 6),
              _filterPill(loc.progressFilterCardio, 2, theme),
            ],
          ),
        ),
        PerformanceSection(
          allExercises: filtered,
          onExerciseTap: (id, name, _) => _showExercisePopup(id, name, theme),
        ),
      ],
    );
  }

  Widget _filterPill(String label, int filterValue, ThemeData theme) {
    final isSelected = _exerciseFilter == filterValue;
    return GestureDetector(
      onTap: () => setState(() => _exerciseFilter = filterValue),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest.withAlpha(100),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? theme.colorScheme.primary : theme.colorScheme.outlineVariant.withAlpha(80),
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  // ===================== DURATION CONTENT =====================

  Widget _buildDurationContent(ThemeData theme) {
    if (_isLoadingDuration) return _sectionLoading(theme);
    if (!_loadedDuration) return const SizedBox.shrink();
    if (_durationTrend.isEmpty && _densityData.isEmpty) {
      return const SizedBox.shrink();
    }
    return DurationRecoveryCharts(
      durationTrend: _durationTrend,
      densityData: _densityData,
      feelingTrend: [],
      feelingVsVolume: [],
    );
  }

  // ===================== RECOVERY CONTENT =====================

  Widget _buildRecoveryContent(ThemeData theme) {
    if (_isLoadingRecovery) return _sectionLoading(theme);
    if (!_loadedRecovery) return const SizedBox.shrink();
    if (_feelingTrend.isEmpty && _feelingVsVolume.isEmpty) {
      return const SizedBox.shrink();
    }
    return DurationRecoveryCharts(
      durationTrend: [],
      densityData: [],
      feelingTrend: _feelingTrend,
      feelingVsVolume: _feelingVsVolume,
    );
  }

  // ===================== BODY CONTENT =====================

  Widget _buildBodyContent(ThemeData theme) {
    if (_isLoadingBody) return _sectionLoading(theme);
    if (!_loadedBody) return const SizedBox.shrink();
    return BodySectionCharts(
      bodySummary: _bodySummary,
      bodyComposition: _bodyComposition,
      bodyData: _bodyData,
    );
  }

  // =======================================================================
  // EXERCISE DETAIL VIEW
  // =======================================================================

  Widget _buildExerciseDetail(ThemeData theme) {
    return ExerciseDetailView(
      initialHistory: _selectedHistory,
      initialExerciseId: _selectedHistory?['exercise_id'] as String? ?? '',
      analytics: _analytics,
      exerciseRepo: _exerciseRepo,
    );
  }
}
