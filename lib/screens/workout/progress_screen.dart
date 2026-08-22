import 'package:flutter/material.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/goal.dart';
import 'package:workout_notes/repositories/analytics_repository.dart';
import 'package:workout_notes/repositories/body_measurement_repository.dart';
import 'package:workout_notes/repositories/exercise_repository.dart';
import 'package:workout_notes/widgets/goals/goals_section.dart';
import 'package:workout_notes/widgets/progress/body_section_charts.dart';
import 'package:workout_notes/widgets/progress/duration_recovery_charts.dart';
import 'package:workout_notes/widgets/progress/exercise_detail_sheet.dart';
import 'package:workout_notes/widgets/progress/exercise_detail_view.dart';
import 'package:workout_notes/widgets/progress/frequency_charts.dart';
import 'package:workout_notes/widgets/progress/monthly_report_card.dart';
import 'package:workout_notes/widgets/progress/performance_section.dart';
import 'package:workout_notes/widgets/progress/progress_chart_shell.dart';
import 'package:workout_notes/widgets/progress/volume_charts.dart';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen>
    with SingleTickerProviderStateMixin {
  static const _tabCount = 4;

  final _analytics = AnalyticsRepository();
  final _exerciseRepo = ExerciseRepository();
  final _bodyRepo = BodyMeasurementRepository();

  late final TabController _tabController;

  bool _isLoading = true;

  Map<String, dynamic>? _monthReport;
  Map<String, dynamic>? _monthComparison;

  bool _isLoadingFrequency = false;
  bool _isLoadingTraining = false;
  bool _isLoadingPerformance = false;
  bool _isLoadingWellness = false;
  bool _loadedFrequency = false;
  bool _loadedTraining = false;
  bool _loadedPerformance = false;
  bool _loadedWellness = false;

  Map<String, int> _heatmapData = {};
  List<Map<String, dynamic>> _workoutDates = [];
  List<Map<String, dynamic>> _allExercises = [];
  List<Map<String, dynamic>> _durationTrend = [];
  List<Map<String, dynamic>> _densityData = [];
  List<Map<String, dynamic>> _feelingTrend = [];
  List<Map<String, dynamic>> _feelingVsVolume = [];
  List<Map<String, dynamic>> _bodyData = [];
  List<Map<String, dynamic>> _bodySummary = [];
  List<Map<String, dynamic>> _bodyComposition = [];

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
        _loadTraining();
      case 2:
        _loadWellness();
      case 3:
        _loadPerformance();
    }
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final now = DateTime.now();

    try {
      final previousMonth = DateTime(now.year, now.month - 1, 1);
      final results = await Future.wait([
        _analytics.getMonthlyReport(now.year, now.month),
        _analytics.getMonthlyReport(previousMonth.year, previousMonth.month),
      ]);

      if (!mounted) return;

      final currentReport = results[0];
      _monthReport = currentReport;
      final previousReport = results[1];
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

  Future<void> _loadTraining() async {
    if (_loadedTraining || _isLoadingTraining) return;
    setState(() => _isLoadingTraining = true);
    try {
      final results = await Future.wait([
        _analytics.getDurationTrend(),
        _analytics.getWorkoutDensity(),
      ]);
      if (!mounted) return;
      _durationTrend = results[0];
      _densityData = results[1];
      _loadedTraining = true;
      setState(() => _isLoadingTraining = false);
    } catch (_) {
      if (mounted) setState(() => _isLoadingTraining = false);
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

  Future<void> _loadWellness() async {
    if (_loadedWellness || _isLoadingWellness) return;
    setState(() => _isLoadingWellness = true);
    try {
      final results = await Future.wait([
        _analytics.getFeelingTrend(),
        _analytics.getFeelingVsVolume(),
        _analytics.getBodyWeightWithVolume(),
        _bodyRepo.getBodyMeasurementsSummary(),
        _bodyRepo.getBodyCompositionTrend(),
      ]);
      if (!mounted) return;
      _feelingTrend = results[0];
      _feelingVsVolume = results[1];
      _bodyData = results[2];
      _bodySummary = results[3];
      _bodyComposition = results[4];
      _loadedWellness = true;
      setState(() => _isLoadingWellness = false);
    } catch (_) {
      if (mounted) setState(() => _isLoadingWellness = false);
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
                  isScrollable: false,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                  tabs: [
                    Tab(text: loc.progressTabFrequency),
                    Tab(text: loc.progressTabTraining),
                    Tab(text: loc.progressTabWellness),
                    Tab(text: loc.progressTabExercises),
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
          _buildTabScroll(child: _buildTrainingContent(theme)),
          _buildTabScroll(child: _buildWellnessContent(theme)),
          _buildTabScroll(child: _buildPerformanceContent(theme)),
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

  Widget _buildGoalsHeader(ThemeData theme) {
    final loc = AppLocalizations.of(context)!;
    return ProgressGroupLabel(
      title: loc.progressGoals,
      icon: Icons.flag_outlined,
      color: Colors.deepPurple,
    );
  }

  Widget _buildFrequencyContent(ThemeData theme) {
    if (_isLoadingFrequency || !_loadedFrequency) return _sectionLoading();
    return FrequencyCharts(
      heatmapData: _heatmapData,
      workoutDates: _workoutDates,
      year: DateTime.now().year,
    );
  }

  Widget _buildTrainingContent(ThemeData theme) {
    final loc = AppLocalizations.of(context)!;
    if (_isLoadingTraining || !_loadedTraining) return _sectionLoading();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ProgressGroupLabel(
          title: loc.progressGroupVolume,
          icon: Icons.pie_chart_outline,
          color: Colors.teal,
        ),
        VolumeCharts(analytics: _analytics),
        const SizedBox(height: 20),
        ProgressGroupLabel(
          title: loc.progressGroupEfficiency,
          icon: Icons.timer_outlined,
          color: Colors.purple,
        ),
        if (_durationTrend.isEmpty && _densityData.isEmpty)
          _emptyTab(theme, loc.progressNoChartData)
        else
          DurationRecoveryCharts(
            durationTrend: _durationTrend,
            densityData: _densityData,
            feelingTrend: const [],
            feelingVsVolume: const [],
          ),
      ],
    );
  }

  Widget _buildPerformanceContent(ThemeData theme) {
    if (_isLoadingPerformance || !_loadedPerformance) return _sectionLoading();
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

  Widget _buildWellnessContent(ThemeData theme) {
    final loc = AppLocalizations.of(context)!;
    if (_isLoadingWellness || !_loadedWellness) return _sectionLoading();

    final hasRecovery =
        _feelingTrend.isNotEmpty || _feelingVsVolume.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ProgressGroupLabel(
          title: loc.progressGroupRecovery,
          icon: Icons.favorite_outline,
          color: Colors.redAccent,
        ),
        if (!hasRecovery)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              loc.progressNoChartData,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          DurationRecoveryCharts(
            durationTrend: const [],
            densityData: const [],
            feelingTrend: _feelingTrend,
            feelingVsVolume: _feelingVsVolume,
          ),
        const SizedBox(height: 20),
        ProgressGroupLabel(
          title: loc.progressGroupBody,
          icon: Icons.monitor_weight_outlined,
          color: Colors.indigo,
        ),
        BodySectionCharts(
          bodySummary: _bodySummary,
          bodyComposition: _bodyComposition,
          bodyData: _bodyData,
        ),
      ],
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
