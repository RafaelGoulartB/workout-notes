import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_achievement.dart';
import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/repositories/run_repository.dart';
import 'package:workout_notes/screens/run/run_achievements_screen.dart';
import 'package:workout_notes/screens/run/run_detail_screen.dart';
import 'package:workout_notes/screens/run/run_gear_screen.dart';
import 'package:workout_notes/screens/run/run_history_screen.dart';
import 'package:workout_notes/screens/run/run_insights_screen.dart';
import 'package:workout_notes/screens/run/run_plan_detail_screen.dart';
import 'package:workout_notes/screens/run/run_plans_screen.dart';
import 'package:workout_notes/screens/run/run_record_screen.dart';
import 'package:workout_notes/screens/run/run_voice_settings_screen.dart';
import 'package:workout_notes/services/run_today_service.dart';
import 'package:workout_notes/utils/run_achievement_engine.dart';
import 'package:workout_notes/utils/run_fitness_analytics.dart';
import 'package:workout_notes/utils/run_progress_analytics.dart';
import 'package:workout_notes/widgets/run/home/run_home_fitness_card.dart';
import 'package:workout_notes/widgets/run/home/run_home_hero.dart';
import 'package:workout_notes/widgets/run/home/run_home_plan_card.dart';
import 'package:workout_notes/widgets/run/home/run_home_recent_runs.dart';
import 'package:workout_notes/widgets/run/home/run_home_records_section.dart';
import 'package:workout_notes/widgets/run/home/run_home_today_card.dart';
import 'package:workout_notes/widgets/run/home/run_home_trends_card.dart';
import 'package:workout_notes/widgets/run/home/run_home_week_card.dart';
import 'package:workout_notes/widgets/run/run_pending_review_banner.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';

enum _HomeMenu { plans, history, shoes, records, voice }

/// The running home: today's session, this week, the followed plan, the
/// selected period's numbers and charts, current fitness, records and recent
/// runs. Heavy analytics are computed once per load, never inside `build`.
class RunStatsScreen extends StatefulWidget {
  const RunStatsScreen({super.key});

  @override
  State<RunStatsScreen> createState() => _RunStatsScreenState();
}

class _RunStatsScreenState extends State<RunStatsScreen> {
  final _repo = RunRepository();
  final _todayService = RunTodayService();

  List<RunActivity> _activities = const [];
  RunAchievementBoard _board = RunAchievementBoard.empty;
  RunHomeSnapshot? _snapshot;
  RunFitnessEstimate? _fitness;
  RunTrainingLoad? _load;
  RunProgressAnalytics? _analytics;
  bool _loading = true;
  RunStatsPeriod _period = RunStatsPeriod.weeks12;
  int _bannerRefresh = 0;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = _analytics == null);
    await _repo.backfillMissingEfforts(limit: 60);
    await _repo.backfillSmoothedElevation();
    final rows = await _repo.listActivities(
      limit: null,
      activityTypes: RunRepository.runningTypes,
    );
    final snapshot = await _todayService.load(activities: rows);
    if (!mounted) return;
    final fitness = RunFitnessAnalytics.estimate(rows);
    setState(() {
      _activities = rows;
      _board = RunAchievementEngine.build(rows);
      _snapshot = snapshot;
      _fitness = fitness;
      _load = RunFitnessAnalytics.trainingLoad(rows, zones: fitness?.zones);
      _analytics = RunProgressAnalytics.fromActivities(rows, period: _period);
      _bannerRefresh++;
      _loading = false;
    });
  }

  void _setPeriod(RunStatsPeriod period) {
    setState(() {
      _period = period;
      _analytics = RunProgressAnalytics.fromActivities(
        _activities,
        period: period,
      );
    });
  }

  Future<void> _push(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    if (mounted) _reload();
  }

  Future<void> _startFreeRun() => _push(const RunRecordScreen());

  Future<void> _startSession(RunPlannedSession session) => _push(
    RunRecordScreen(
      planWorkout: session.workout,
      scheduledRun: session.scheduled,
    ),
  );

  Future<void> _editWeeklyGoal() async {
    final current = _snapshot?.userWeeklyGoalMeters;
    final edit = await showRunWeeklyGoalDialog(
      context,
      currentKm: current == null ? null : current / 1000,
    );
    if (edit == null) return;
    await _todayService.setWeeklyGoalKm(edit.km);
    if (mounted) _reload();
  }

  void _onMenu(_HomeMenu item) {
    switch (item) {
      case _HomeMenu.plans:
        _push(const RunPlansScreen());
      case _HomeMenu.history:
        _push(const RunHistoryScreen());
      case _HomeMenu.shoes:
        _push(const RunGearScreen());
      case _HomeMenu.records:
        _push(const RunAchievementsScreen());
      case _HomeMenu.voice:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const RunVoiceSettingsScreen()),
        );
    }
  }

  PopupMenuItem<_HomeMenu> _menuItem(
    _HomeMenu value,
    IconData icon,
    String label,
  ) => PopupMenuItem(
    value: value,
    child: Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Flexible(child: Text(label)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.runStatsTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.insights_outlined),
            tooltip: loc.runHomeMenuInsights,
            onPressed: () => _push(const RunInsightsScreen()),
          ),
          PopupMenuButton<_HomeMenu>(
            tooltip: loc.runHomeMenuMore,
            onSelected: _onMenu,
            itemBuilder: (_) => [
              _menuItem(
                _HomeMenu.plans,
                Icons.route_outlined,
                loc.runPlansTitle,
              ),
              _menuItem(_HomeMenu.history, Icons.history, loc.runHistoryTitle),
              _menuItem(
                _HomeMenu.shoes,
                Icons.directions_walk,
                loc.runGearTitle,
              ),
              _menuItem(
                _HomeMenu.records,
                Icons.emoji_events_outlined,
                loc.runHomeMenuRecords,
              ),
              _menuItem(
                _HomeMenu.voice,
                Icons.record_voice_over_outlined,
                loc.runVoiceSettingsTitle,
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _startFreeRun,
        icon: const Icon(Icons.directions_run),
        label: Text(loc.runRecordStart),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  RunPendingReviewBanner(
                    refreshToken: _bannerRefresh,
                    onChanged: _reload,
                  ),
                  Padding(
                    padding: RunUi.screenPadding,
                    child: _buildContent(loc),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildContent(AppLocalizations loc) {
    final snapshot = _snapshot;
    final analytics = _analytics;
    final load = _load;
    final hasRuns = _activities.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (snapshot != null)
          RunTodayCard(
            info: snapshot.today,
            onStartSession: () {
              final session = snapshot.today.session;
              if (session != null) _startSession(session);
            },
            onFreeRun: _startFreeRun,
            onOpenPlans: () => _push(const RunPlansScreen()),
            onOpenRun: (id) => _push(RunDetailScreen(activityId: id)),
          ).animate().fadeIn(duration: 300.ms),
        if (!hasRuns)
          ..._buildEmpty(loc, snapshot)
        else ...[
          if (analytics != null)
            ..._buildWithRuns(loc, analytics, snapshot, load),
        ],
      ],
    );
  }

  List<Widget> _buildEmpty(AppLocalizations loc, RunHomeSnapshot? snapshot) {
    final plan = snapshot?.plan;
    return [
      if (plan != null) ...[
        RunSectionHeader(loc.runHomePlanTitle),
        _planCard(plan, snapshot),
      ],
      const SizedBox(height: 22),
      RunSectionCard(
        child: Column(
          children: [
            const Icon(Icons.directions_run, size: 48),
            const SizedBox(height: 12),
            Text(
              loc.runHistoryEmptyTitle,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              loc.runHistoryEmptySubtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _startFreeRun,
              child: Text(loc.runHistoryEmptyCta),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _planCard(RunPlanContext plan, RunHomeSnapshot? snapshot) {
    return RunActivePlanCard(
      planContext: plan,
      next: snapshot?.nextSession,
      today: DateTime.now(),
      onOpenPlan: () => _push(RunPlanDetailScreen(planId: plan.plan.id)),
      onAllPlans: () => _push(const RunPlansScreen()),
    );
  }

  List<Widget> _buildWithRuns(
    AppLocalizations loc,
    RunProgressAnalytics analytics,
    RunHomeSnapshot? snapshot,
    RunTrainingLoad? load,
  ) {
    final plan = snapshot?.plan;
    final recent = _activities.take(5).toList();

    return [
      RunSectionHeader(loc.runStatsSectionThisWeek),
      RunWeekCard(
        analytics: analytics,
        snapshot: snapshot,
        onEditGoal: _editWeeklyGoal,
      ),
      if (plan != null) ...[
        RunSectionHeader(loc.runHomePlanTitle),
        _planCard(plan, snapshot),
      ],
      RunSectionHeader(loc.runStatsOverview),
      RunPeriodChips(selected: _period, onChanged: _setPeriod),
      const SizedBox(height: 14),
      RunPeriodHero(analytics: analytics),
      RunSectionHeader(loc.runStatsSectionTrends),
      RunTrendsCard(analytics: analytics),
      if (load != null) ...[
        RunSectionHeader(loc.runHomeFitnessTitle),
        RunFitnessCard(
          estimate: _fitness,
          load: load,
          onSeeAll: () => _push(const RunInsightsScreen()),
        ),
      ],
      RunSectionHeader(
        loc.runHomeRecordsTitle,
        trailing: RunHeaderAction(
          label: loc.runHomeRecordsSeeAll,
          onPressed: () => _push(const RunAchievementsScreen()),
        ),
      ),
      RunRecordsSection(
        analytics: analytics,
        board: _board,
        onOpenActivity: (id) => _push(RunDetailScreen(activityId: id)),
      ),
      RunSectionHeader(
        loc.runStatsSectionRecent,
        trailing: RunHeaderAction(
          label: loc.runStatsSeeAll,
          onPressed: () => _push(const RunHistoryScreen()),
        ),
      ),
      RunRecentRuns(
        activities: recent,
        board: _board,
        onOpen: (id) => _push(RunDetailScreen(activityId: id)),
      ),
    ];
  }
}
