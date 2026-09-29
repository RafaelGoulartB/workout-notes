import 'package:flutter/material.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/models/run_gear.dart';
import 'package:workout_notes/repositories/run_repository.dart';
import 'package:workout_notes/screens/run/run_detail_screen.dart';
import 'package:workout_notes/screens/run/run_gear_screen.dart';
import 'package:workout_notes/utils/run_calendar_stats.dart';
import 'package:workout_notes/utils/run_fitness_analytics.dart';
import 'package:workout_notes/utils/run_training_load_analytics.dart';
import 'package:workout_notes/widgets/empty_state_placeholder.dart';
import 'package:workout_notes/widgets/run/insights/run_insights_fitness_sections.dart';
import 'package:workout_notes/widgets/run/insights/run_insights_year_sections.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';
import 'package:workout_notes/utils/date_utils.dart';

/// Which group of analysis cards is showing.
enum _InsightsTab { fitness, training, year }

/// Deeper running analysis in three tabs: current form (fitness estimate,
/// race predictions, training load), how you train (intensity mix,
/// consistency, effort) and the year (review, calendar, volume, shoes).
/// Everything is computed once per load from the full running history.
class RunInsightsScreen extends StatefulWidget {
  const RunInsightsScreen({super.key});

  @override
  State<RunInsightsScreen> createState() => _RunInsightsScreenState();
}

class _RunInsightsScreenState extends State<RunInsightsScreen> {
  final _runRepo = DatabaseHelper.instance.runRepo;
  final _insightsRepo = DatabaseHelper.instance.runInsightsRepo;

  bool _loading = true;
  _InsightsTab _tab = _InsightsTab.fitness;
  List<RunActivity> _activities = const [];
  RunFitnessEstimate? _estimate;
  List<RunVdotPoint> _evolution = const [];
  RunTrainingLoad? _load;
  RunIntensityDistribution? _intensity;
  RunConsistency? _consistency;
  List<RunWeeklyEffort> _effort = const [];
  List<RunGearUsage> _shoes = const [];
  List<int> _years = const [];
  late DateTime _today;

  int _year = DateTime.now().year;
  Map<DateTime, double> _daily = const {};
  List<RunMonthTotal> _months = const [];
  List<double?> _thisYearCumulative = const [];
  List<double?> _lastYearCumulative = const [];
  RunYearReview? _review;

  @override
  void initState() {
    super.initState();
    _today = DateTime.now();
    _year = _today.year;
    _loadAll();
  }

  Future<void> _loadAll() async {
    final now = DateTime.now();
    final rows = await _runRepo.listActivities(
      limit: null,
      activityTypes: RunRepository.runningTypes,
    );
    final estimate = RunFitnessAnalytics.estimate(rows, now: now);
    final zones = estimate?.zones;

    // Splits only matter for the intensity mix, which needs zones.
    final monday = addDays(mondayOf(now), -7 * 11);
    var splits = const <String, List<RunSplitSample>>{};
    if (zones != null) {
      try {
        splits = await _insightsRepo.splitsSince(monday);
      } catch (_) {
        // Older schemas: fall back to average pace per run.
      }
    }
    var shoes = const <RunGearUsage>[];
    try {
      shoes = await DatabaseHelper.instance.runGearRepo.listGearUsage(
        includeRetired: false,
      );
    } catch (_) {
      // No gear table yet.
    }
    if (!mounted) return;

    final years = RunCalendarStats.availableYears(rows, now: now);
    setState(() {
      _today = now;
      _activities = rows;
      _estimate = estimate;
      _evolution = RunFitnessAnalytics.vdotByMonth(rows, now: now);
      _load = RunTrainingLoadAnalytics.trainingLoad(rows, now: now, zones: zones);
      _intensity = zones == null
          ? null
          : RunTrainingLoadAnalytics.intensityDistribution(
              rows,
              zones: zones,
              splits: splits,
              now: now,
            );
      _consistency = RunCalendarStats.consistency(rows, now: now);
      _effort = RunTrainingLoadAnalytics.weeklyEffort(rows, now: now);
      _shoes = shoes;
      _years = years;
      if (!years.contains(_year)) _year = years.first;
      _computeYear(_year);
      _loading = false;
    });
  }

  void _computeYear(int year) {
    _year = year;
    final rows = _activities;
    _daily = RunCalendarStats.dailyDistance(rows, year: year);
    _months = RunCalendarStats.monthlyTotals(
      rows,
      now: year == _today.year ? _today : DateTime(year, 12, 31),
    );
    _thisYearCumulative = RunCalendarStats.cumulativeMonthly(
      rows,
      year,
      now: _today,
    );
    _lastYearCumulative = RunCalendarStats.cumulativeMonthly(
      rows,
      year - 1,
      now: _today,
    );
    _review = RunCalendarStats.yearReview(rows, year);
  }

  Future<void> _openRun(String id) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RunDetailScreen(activityId: id)),
    );
    if (mounted) _loadAll();
  }

  Future<void> _openShoes() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RunGearScreen()),
    );
    if (mounted) _loadAll();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final showTabs = !_loading && _activities.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.runInsightsTitle),
        bottom: showTabs
            ? PreferredSize(
                preferredSize: const Size.fromHeight(60),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: RunSegmentedTabs<_InsightsTab>(
                    values: _InsightsTab.values,
                    selected: _tab,
                    labelOf: (tab) => switch (tab) {
                      _InsightsTab.fitness => loc.runInsightsTabFitness,
                      _InsightsTab.training => loc.runInsightsTabTraining,
                      _InsightsTab.year => loc.runInsightsTabYear,
                    },
                    onChanged: (tab) => setState(() => _tab = tab),
                  ),
                ),
              )
            : null,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _activities.isEmpty
          ? EmptyStatePlaceholder(
              icon: Icons.insights_outlined,
              title: loc.runInsightsEmptyTitle,
              subtitle: loc.runInsightsEmptySubtitle,
            )
          : RefreshIndicator(
              onRefresh: _loadAll,
              child: ListView(
                key: PageStorageKey(_tab),
                padding: RunUi.screenPadding.copyWith(top: 8, bottom: 40),
                children: [
                  for (final (i, card) in _cards().indexed) ...[
                    if (i > 0) const SizedBox(height: 12),
                    card,
                  ],
                ],
              ),
            ),
    );
  }

  /// Cards of the selected tab: current form, how you train, the year.
  List<Widget> _cards() {
    final estimate = _estimate;
    final load = _load;
    final consistency = _consistency;
    final review = _review;

    return switch (_tab) {
      _InsightsTab.fitness => [
        RunFitnessSection(estimate: estimate, evolution: _evolution),
        if (estimate != null) RunPredictorSection(estimate: estimate),
        if (load != null) RunLoadSection(load: load),
      ],
      _InsightsTab.training => [
        RunIntensitySection(distribution: _intensity, zones: estimate?.zones),
        if (consistency != null)
          RunConsistencySection(consistency: consistency),
        RunEffortSection(weeks: _effort),
      ],
      _InsightsTab.year => [
        if (_years.length > 1)
          RunYearSelector(
            years: _years,
            selected: _year,
            onChanged: (year) => setState(() => _computeYear(year)),
          ),
        if (review != null)
          RunYearReviewSection(review: review, onOpenRun: _openRun),
        RunHeatmapSection(year: _year, daily: _daily, today: _today),
        RunVolumeSection(
          year: _year,
          months: _months,
          thisYear: _thisYearCumulative,
          lastYear: _lastYearCumulative,
          today: _today,
        ),
        RunShoesSection(shoes: _shoes, onOpen: _openShoes),
      ],
    };
  }
}
