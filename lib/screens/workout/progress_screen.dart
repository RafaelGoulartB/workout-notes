import 'package:flutter/material.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/goal.dart';
import 'package:workout_notes/repositories/analytics_repository.dart';
import 'package:workout_notes/repositories/body_measurement_repository.dart';
import 'package:workout_notes/repositories/exercise_repository.dart';
import 'package:workout_notes/utils/progress_helpers.dart';
import 'package:workout_notes/widgets/goals/goals_section.dart';
import 'package:workout_notes/widgets/progress/body_section_charts.dart';
import 'package:workout_notes/widgets/progress/duration_recovery_charts.dart';
import 'package:workout_notes/widgets/progress/exercise_detail_sheet.dart';
import 'package:workout_notes/widgets/progress/exercise_detail_view.dart';
import 'package:workout_notes/widgets/progress/frequency_charts.dart';
import 'package:workout_notes/widgets/progress/monthly_report_card.dart';
import 'package:workout_notes/widgets/progress/performance_section.dart';
import 'package:workout_notes/widgets/progress/progress_stat_cards.dart';
import 'package:workout_notes/widgets/progress/volume_charts.dart';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen>
    with SingleTickerProviderStateMixin {
  static const _tabCount = 6;

  final _analytics = AnalyticsRepository();
  final _exerciseRepo = ExerciseRepository();
  final _bodyRepo = BodyMeasurementRepository();

  late final TabController _tabController;

  bool _isLoading = true;

  // === OVERVIEW DATA (loaded immediately) ===
  Map<String, dynamic>? _overviewStats;
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
  bool _showingOverview = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabCount, vsync: this);
    _tabController.addListener(_onTabChanged);
    _load();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    _ensureTabLoaded(_tabController.index);
  }

  void _ensureTabLoaded(int index) {
    switch (index) {
      case 0:
        _loadFrequency();
      case 1:
        _loadVolume();
      case 2:
        _loadPerformance();
      case 3:
        _loadDuration();
      case 4:
        _loadRecovery();
      case 5:
        _loadBody();
    }
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final now = DateTime.now();

    try {
      final previousMonth = DateTime(now.year, now.month - 1, 1);
      final results = await Future.wait([
        _analytics.getWorkoutOverviewStats(),
        _analytics.getMonthlyReport(now.year, now.month),
        _analytics.getMonthlyReport(previousMonth.year, previousMonth.month),
      ]);

      if (!mounted) return;

      _overviewStats = results[0];
      final currentReport = results[1];
      _monthReport = currentReport;
      final previousReport = results[2];
      _monthComparison = {
        'current': currentReport,
        'previous': previousReport,
        'delta_workouts': (currentReport['workout_count'] as int) -
            (previousReport['workout_count'] as int),
        'delta_volume': (currentReport['total_volume'] as double) -
            (previousReport['total_volume'] as double),
        'delta_sets': (currentReport['total_sets'] as int) -
            (previousReport['total_sets'] as int),
      };

      setState(() => _isLoading = false);
      _ensureTabLoaded(_tabController.index);
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadFrequency() async {
    if (_loadedFrequency || _isLoadingFrequency) return;
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
    if (_loadedVolume || _isLoadingVolume) return;
    setState(() => _isLoadingVolume = true);
    try {
      _loadedVolume = true;
      if (mounted) setState(() => _isLoadingVolume = false);
    } catch (_) {
      if (mounted) setState(() => _isLoadingVolume = false);
    }
  }

  Future<void> _loadPerformance() async {
    if (_loadedPerformance || _isLoadingPerformance) return;
    setState(() => _isLoadingPerformance = true);
    try {
      final exercises = await _exerciseRepo.getExercises();
      if (!mounted) return;
      _allExercises = exercises
          .where((e) => (e['category_energy'] as String?) != 'aerobic')
          .toList();
      _loadedPerformance = true;
      setState(() => _isLoadingPerformance = false);
    } catch (_) {
      if (mounted) setState(() => _isLoadingPerformance = false);
    }
  }

  Future<void> _loadDuration() async {
    if (_loadedDuration || _isLoadingDuration) return;
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
    if (_loadedRecovery || _isLoadingRecovery) return;
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
    if (_loadedBody || _isLoadingBody) return;
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

  Widget _sectionLoading() {
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

  Widget _emptyTab(ThemeData theme, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Future<void> _showExercisePopup(
    String exerciseId,
    String exerciseName,
    ThemeData theme,
  ) async {
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
                onPressed: () => setState(() => _showingOverview = true),
              ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _showingOverview
          ? _buildOverview(theme)
          : _buildExerciseDetail(),
    );
  }

  Widget _buildOverview(ThemeData theme) {
    final loc = AppLocalizations.of(context)!;

    return NestedScrollView(
      headerSliverBuilder: (context, innerBoxIsScrolled) {
        return [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MonthlyReportCard(
                    report: _monthReport,
                    comparison: _monthComparison,
                  ),
                  const SizedBox(height: 12),
                  _buildStatsGrid(theme),
                  const SizedBox(height: 16),
                  _buildGoalsHeader(theme),
                  const SizedBox(height: 8),
                  GoalsSection(
                    db: DatabaseHelper.instance,
                    settingsRepo: DatabaseHelper.instance.settingsRepo,
                    allowedScopes: const [GoalScope.anaerobic],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          SliverOverlapAbsorber(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            sliver: SliverPersistentHeader(
              pinned: true,
              delegate: _ProgressTabBarDelegate(
                tabBar: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 14),
                  tabs: [
                    Tab(text: loc.progressTabFrequency),
                    Tab(text: loc.progressTabVolume),
                    Tab(text: loc.progressTabExercises),
                    Tab(text: loc.progressTabDuration),
                    Tab(text: loc.progressTabRecovery),
                    Tab(text: loc.progressTabBody),
                  ],
                ),
                backgroundColor: theme.scaffoldBackgroundColor,
                borderColor: theme.colorScheme.outlineVariant.withAlpha(80),
              ),
            ),
          ),
        ];
      },
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTabScroll(child: _buildFrequencyContent(theme)),
          _buildTabScroll(child: _buildVolumeContent(theme)),
          _buildTabScroll(child: _buildPerformanceContent(theme)),
          _buildTabScroll(child: _buildDurationContent(theme)),
          _buildTabScroll(child: _buildRecoveryContent(theme)),
          _buildTabScroll(child: _buildBodyContent(theme)),
        ],
      ),
    );
  }

  Widget _buildTabScroll({required Widget child}) {
    return Builder(
      builder: (context) {
        return CustomScrollView(
          slivers: [
            SliverOverlapInjector(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              sliver: SliverToBoxAdapter(child: child),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatsGrid(ThemeData theme) {
    final loc = AppLocalizations.of(context)!;
    final stats = _overviewStats;
    final totalWorkouts = (stats?['total_workouts'] as int?) ?? 0;
    final totalSets = (stats?['total_sets'] as int?) ?? 0;
    final totalVolume = (stats?['total_volume'] as num?)?.toDouble() ?? 0.0;
    final streak = (stats?['current_streak'] as int?) ?? 0;
    final dayLabel =
        streak == 1 ? loc.workoutHomeDay : loc.workoutHomeDays;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: ProgressStatCard(
                label: loc.progressWorkouts,
                value: '$totalWorkouts',
                icon: Icons.fitness_center,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ProgressStatCard(
                label: loc.progressSets,
                value: '$totalSets',
                icon: Icons.repeat,
                color: theme.colorScheme.secondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ProgressStatCard(
                label: loc.progressStreak,
                value: '$streak $dayLabel',
                icon: Icons.local_fire_department,
                color: Colors.orange,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ProgressStatCard(
                label: loc.commonVolume,
                value: formatVolume(totalVolume),
                icon: Icons.auto_graph,
                color: Colors.teal,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGoalsHeader(ThemeData theme) {
    final loc = AppLocalizations.of(context)!;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.deepPurple.withAlpha(25),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.flag, size: 18, color: Colors.deepPurple),
        ),
        const SizedBox(width: 10),
        Text(
          loc.progressGoals.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            loc.progressGoalsSubtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildFrequencyContent(ThemeData theme) {
    if (_isLoadingFrequency) return _sectionLoading();
    if (!_loadedFrequency) return _sectionLoading();
    return FrequencyCharts(
      heatmapData: _heatmapData,
      workoutDates: _workoutDates,
      year: DateTime.now().year,
    );
  }

  Widget _buildVolumeContent(ThemeData theme) {
    if (_isLoadingVolume) return _sectionLoading();
    if (!_loadedVolume) return _sectionLoading();
    return VolumeCharts(analytics: _analytics);
  }

  Widget _buildPerformanceContent(ThemeData theme) {
    if (_isLoadingPerformance) return _sectionLoading();
    if (!_loadedPerformance) return _sectionLoading();
    if (_allExercises.isEmpty) {
      return _emptyTab(
        theme,
        AppLocalizations.of(context)!.progressNoExercises,
      );
    }
    return PerformanceSection(
      allExercises: _allExercises,
      onExerciseTap: (id, name, _) => _showExercisePopup(id, name, theme),
    );
  }

  Widget _buildDurationContent(ThemeData theme) {
    if (_isLoadingDuration) return _sectionLoading();
    if (!_loadedDuration) return _sectionLoading();
    if (_durationTrend.isEmpty && _densityData.isEmpty) {
      return _emptyTab(
        theme,
        AppLocalizations.of(context)!.progressNoChartData,
      );
    }
    return DurationRecoveryCharts(
      durationTrend: _durationTrend,
      densityData: _densityData,
      feelingTrend: const [],
      feelingVsVolume: const [],
    );
  }

  Widget _buildRecoveryContent(ThemeData theme) {
    if (_isLoadingRecovery) return _sectionLoading();
    if (!_loadedRecovery) return _sectionLoading();
    if (_feelingTrend.isEmpty && _feelingVsVolume.isEmpty) {
      return _emptyTab(
        theme,
        AppLocalizations.of(context)!.progressNoChartData,
      );
    }
    return DurationRecoveryCharts(
      durationTrend: const [],
      densityData: const [],
      feelingTrend: _feelingTrend,
      feelingVsVolume: _feelingVsVolume,
    );
  }

  Widget _buildBodyContent(ThemeData theme) {
    if (_isLoadingBody) return _sectionLoading();
    if (!_loadedBody) return _sectionLoading();
    return BodySectionCharts(
      bodySummary: _bodySummary,
      bodyComposition: _bodyComposition,
      bodyData: _bodyData,
    );
  }

  Widget _buildExerciseDetail() {
    return ExerciseDetailView(
      initialHistory: _selectedHistory,
      initialExerciseId: _selectedHistory?['exercise_id'] as String? ?? '',
      analytics: _analytics,
      exerciseRepo: _exerciseRepo,
    );
  }
}

class _ProgressTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final Color backgroundColor;
  final Color borderColor;

  _ProgressTabBarDelegate({
    required this.tabBar,
    required this.backgroundColor,
    required this.borderColor,
  });

  @override
  double get minExtent => tabBar.preferredSize.height + 1;

  @override
  double get maxExtent => tabBar.preferredSize.height + 1;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Material(
      color: backgroundColor,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          tabBar,
          Divider(height: 1, thickness: 1, color: borderColor),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _ProgressTabBarDelegate oldDelegate) {
    return tabBar != oldDelegate.tabBar ||
        backgroundColor != oldDelegate.backgroundColor ||
        borderColor != oldDelegate.borderColor;
  }
}
