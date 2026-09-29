import 'package:flutter/material.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/models/run_gear.dart';
import 'package:workout_notes/repositories/run_insights_repository.dart';
import 'package:workout_notes/repositories/run_repository.dart';
import 'package:workout_notes/screens/run/run_detail_screen.dart';
import 'package:workout_notes/screens/run/run_gear_screen.dart';
import 'package:workout_notes/utils/run_fitness_analytics.dart';
import 'package:workout_notes/widgets/empty_state_placeholder.dart';
import 'package:workout_notes/widgets/run/insights/run_insights_fitness_sections.dart';
import 'package:workout_notes/widgets/run/insights/run_insights_year_sections.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';

/// Deeper running analysis: fitness estimate, race predictions, training load,
/// intensity mix, consistency and effort trends, then year views (calendar,
/// volume, elevation, review) and shoe mileage. Everything is computed once
/// per load from the full running history.
class RunInsightsScreen extends StatefulWidget {
  const RunInsightsScreen({super.key});

  @override
  State<RunInsightsScreen> createState() => _RunInsightsScreenState();
}

class _RunInsightsScreenState extends State<RunInsightsScreen> {
  final _runRepo = RunRepository();
  final _insightsRepo = RunInsightsRepository();

  bool _loading = true;
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
    final monday = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1 + 7 * 11));
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

    final years = RunFitnessAnalytics.availableYears(rows, now: now);
    setState(() {
      _today = now;
      _activities = rows;
      _estimate = estimate;
      _evolution = RunFitnessAnalytics.vdotByMonth(rows, now: now);
      _load = RunFitnessAnalytics.trainingLoad(rows, now: now, zones: zones);
      _intensity = zones == null
          ? null
          : RunFitnessAnalytics.intensityDistribution(
              rows,
              zones: zones,
              splits: splits,
              now: now,
            );
      _consistency = RunFitnessAnalytics.consistency(rows, now: now);
      _effort = RunFitnessAnalytics.weeklyEffort(rows, now: now);
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
    _daily = RunFitnessAnalytics.dailyDistance(rows, year: year);
    _months = RunFitnessAnalytics.monthlyTotals(
      rows,
      now: year == _today.year ? _today : DateTime(year, 12, 31),
    );
    _thisYearCumulative = RunFitnessAnalytics.cumulativeMonthly(
      rows,
      year,
      now: _today,
    );
    _lastYearCumulative = RunFitnessAnalytics.cumulativeMonthly(
      rows,
      year - 1,
      now: _today,
    );
    _review = RunFitnessAnalytics.yearReview(rows, year);
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

    return Scaffold(
      appBar: AppBar(title: Text(loc.runInsightsTitle)),
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
                padding: RunUi.screenPadding.copyWith(top: 0, bottom: 40),
                children: _sections(loc),
              ),
            ),
    );
  }

  List<Widget> _sections(AppLocalizations loc) {
    final estimate = _estimate;
    final load = _load;
    final consistency = _consistency;
    final review = _review;

    return [
      RunFitnessSection(estimate: estimate, evolution: _evolution),
      if (estimate != null) RunPredictorSection(estimate: estimate),
      if (load != null) RunLoadSection(load: load),
      RunIntensitySection(distribution: _intensity, zones: estimate?.zones),
      if (consistency != null) RunConsistencySection(consistency: consistency),
      RunEffortSection(weeks: _effort),
      RunYearSelector(
        years: _years,
        selected: _year,
        onChanged: (year) => setState(() => _computeYear(year)),
      ),
      const SizedBox(height: 12),
      RunHeatmapSection(year: _year, daily: _daily, today: _today),
      RunVolumeSection(
        year: _year,
        months: _months,
        thisYear: _thisYearCumulative,
        lastYear: _lastYearCumulative,
        today: _today,
      ),
      if (review != null) ...[
        RunElevationSection(
          year: _year,
          elevation: review.elevation,
          onOpenRun: _openRun,
        ),
        RunYearReviewSection(review: review, onOpenRun: _openRun),
      ],
      RunShoesSection(shoes: _shoes, onOpen: _openShoes),
    ];
  }
}
