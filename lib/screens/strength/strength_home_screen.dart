import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:workout_notes/services/strength_routine_day_inference.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/goal.dart';
import 'package:workout_notes/models/strength_workout_summary.dart';
import 'package:workout_notes/navigation/ai_coach_navigation.dart';
import 'package:workout_notes/repositories/strength_records_repository.dart';
import 'package:workout_notes/repositories/strength_repository.dart';
import 'package:workout_notes/repositories/workout_repository.dart';
import 'package:workout_notes/screens/strength/strength_history_screen.dart';
import 'package:workout_notes/screens/strength/strength_insights_screen.dart';
import 'package:workout_notes/screens/strength/strength_records_screen.dart';
import 'package:workout_notes/screens/workout/active_workout_screen.dart';
import 'package:workout_notes/screens/workout/calendar_screen.dart';
import 'package:workout_notes/screens/workout/exercise_library_screen.dart';
import 'package:workout_notes/screens/workout/future_workout_planner_screen.dart';
import 'package:workout_notes/screens/workout/routines_screen.dart';
import 'package:workout_notes/screens/workout/workout_detail_screen.dart';
import 'package:workout_notes/services/strength_today_service.dart';
import 'package:workout_notes/utils/run_progress_analytics.dart';
import 'package:workout_notes/utils/strength_week_analytics.dart';
import 'package:workout_notes/widgets/goals/goals_section.dart';
import 'package:workout_notes/widgets/run/home/run_home_hero.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';
import 'package:workout_notes/widgets/strength/home/strength_home_active_banner.dart';
import 'package:workout_notes/widgets/strength/home/strength_home_empty.dart';
import 'package:workout_notes/widgets/strength/home/strength_home_hero.dart';
import 'package:workout_notes/widgets/strength/home/strength_home_muscles_card.dart';
import 'package:workout_notes/widgets/strength/home/strength_home_recent_workouts.dart';
import 'package:workout_notes/widgets/strength/home/strength_home_records_section.dart';
import 'package:workout_notes/widgets/strength/home/strength_home_today_card.dart';
import 'package:workout_notes/widgets/strength/home/strength_home_trends_card.dart';
import 'package:workout_notes/widgets/strength/home/strength_home_week_card.dart';

enum _HomeMenu { routines, exercises, history, records, calendar }

/// The gym hub: today's routine day, this week, muscles worked, the selected
/// period's numbers and charts, recent records, goals and recent workouts.
/// Analytics are computed once per load, never inside `build`.
class StrengthHomeScreen extends StatefulWidget {
  const StrengthHomeScreen({super.key});

  @override
  State<StrengthHomeScreen> createState() => _StrengthHomeScreenState();
}

class _StrengthHomeScreenState extends State<StrengthHomeScreen> {
  final _repo = StrengthRepository();
  final _recordsRepo = StrengthRecordsRepository();
  final _workoutRepo = WorkoutRepository();
  final _todayService = StrengthTodayService();

  List<StrengthWorkoutSummary> _finished = const [];
  StrengthHomeSnapshot? _snapshot;
  StrengthWeekAnalytics? _analytics;
  List<StrengthMuscleLoad> _muscles = const [];
  Map<String, StrengthCategoryInfo> _categories = const {};
  List<StrengthRecordEvent> _records = const [];
  List<Map<String, dynamic>> _active = const [];
  bool _loading = true;
  RunStatsPeriod _period = RunStatsPeriod.weeks12;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = _analytics == null);
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final monday = StrengthWeekAnalytics.mondayOf(today);
      // Name older workouts after the routine day they trained (one-off).
      await StrengthRoutineDayInference.runOnce();
      final finished = await _repo.loadFinishedWorkouts();
      final results = await Future.wait<Object>([
        _todayService.load(now: now, finished: finished),
        _repo.loadMuscleLoad(from: monday, to: today),
        _repo.loadCategories(),
        _recordsRepo.recentRecords(limit: 12),
        _workoutRepo.getActiveWorkouts(),
      ]);
      if (!mounted) return;
      setState(() {
        _finished = finished;
        _snapshot = results[0] as StrengthHomeSnapshot;
        _muscles = results[1] as List<StrengthMuscleLoad>;
        _categories = results[2] as Map<String, StrengthCategoryInfo>;
        _records = results[3] as List<StrengthRecordEvent>;
        _active = results[4] as List<Map<String, dynamic>>;
        _analytics = StrengthWeekAnalytics.fromWorkouts(
          finished,
          period: _period,
          now: now,
        );
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setPeriod(RunStatsPeriod period) {
    setState(() {
      _period = period;
      _analytics = StrengthWeekAnalytics.fromWorkouts(
        _finished,
        period: period,
      );
    });
  }

  Future<void> _push(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    if (mounted) _reload();
  }

  Future<void> _openWorkoutScreen({
    String? workoutId,
    String? routineId,
    String? routineDayId,
  }) async {
    await Navigator.push(
      context,
      AiCoachNavigation.route(
        kind: AiCoachRouteKind.activeWorkout,
        builder: (_) => ActiveWorkoutScreen(
          workoutId: workoutId,
          routineId: routineId,
          routineDayId: routineDayId,
        ),
      ),
    );
    if (mounted) _reload();
  }

  /// Resumes the unfinished workout of today when there is one; starting a
  /// second session on top of it would split the day in two.
  Future<void> _startDay(StrengthRoutineDayInfo day) {
    if (_active.isNotEmpty) return _continueActive();
    return _openWorkoutScreen(
      routineId: day.routineId,
      routineDayId: day.routineDayId,
    );
  }

  Future<void> _startBlank() {
    if (_active.isNotEmpty) return _continueActive();
    return _openWorkoutScreen();
  }

  Future<void> _continueActive() =>
      _openWorkoutScreen(workoutId: _active.first['id'] as String?);

  /// The FAB: today's suggested day, else the next one, else a blank workout.
  Future<void> _train() {
    final day = _snapshot?.today.startDay;
    return day == null ? _startBlank() : _startDay(day);
  }

  Future<void> _editWeeklyGoal() async {
    final edit = await showStrengthWeeklyGoalDialog(
      context,
      current: _snapshot?.userWeeklyGoalSessions,
    );
    if (edit == null) return;
    await _todayService.setWeeklyGoalSessions(edit.sessions);
    if (mounted) _reload();
  }

  void _onMenu(_HomeMenu item) {
    switch (item) {
      case _HomeMenu.routines:
        _push(const RoutinesScreen());
      case _HomeMenu.exercises:
        _push(const ExerciseLibraryScreen());
      case _HomeMenu.history:
        _push(const StrengthHistoryScreen());
      case _HomeMenu.records:
        _push(const StrengthRecordsScreen());
      case _HomeMenu.calendar:
        _push(const CalendarScreen());
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
        title: Text(loc.strengthHomeTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.insights_outlined),
            tooltip: loc.strengthHomeMenuInsights,
            onPressed: () => _push(const StrengthInsightsScreen()),
          ),
          PopupMenuButton<_HomeMenu>(
            tooltip: loc.strengthHomeMenuMore,
            onSelected: _onMenu,
            itemBuilder: (_) => [
              _menuItem(
                _HomeMenu.routines,
                Icons.view_list_outlined,
                loc.routinesTitle,
              ),
              _menuItem(
                _HomeMenu.exercises,
                Icons.fitness_center,
                loc.exerciseLibraryTitle,
              ),
              _menuItem(
                _HomeMenu.history,
                Icons.history,
                loc.strengthHomeMenuHistory,
              ),
              _menuItem(
                _HomeMenu.records,
                Icons.emoji_events_outlined,
                loc.strengthHomeMenuRecords,
              ),
              _menuItem(
                _HomeMenu.calendar,
                Icons.calendar_month_outlined,
                loc.strengthHomeMenuCalendar,
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('strength-home-fab'),
        onPressed: _train,
        icon: const Icon(Icons.fitness_center),
        label: Text(loc.strengthHomeTrain),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: RunUi.screenPadding,
                children: [_buildContent(loc)],
              ),
            ),
    );
  }

  Widget _buildContent(AppLocalizations loc) {
    final snapshot = _snapshot;
    final analytics = _analytics;
    final hasWorkouts = _finished.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (snapshot != null)
          StrengthTodayCard(
            info: snapshot.today,
            onStartDay: _startDay,
            onBlankWorkout: _startBlank,
            onOpenRoutines: () => _push(const RoutinesScreen()),
            onOpenWorkout: (id) => _push(WorkoutDetailScreen(workoutId: id)),
          ).animate().fadeIn(duration: 300.ms),
        // The unfinished workout sits right under today's card.
        if (_active.isNotEmpty) ...[
          if (snapshot != null) const SizedBox(height: 12),
          StrengthActiveBanner(
            workout: _active.first,
            onTap: _continueActive,
          ).animate().fadeIn(duration: 300.ms),
        ],
        if (!hasWorkouts) ...[
          const SizedBox(height: 22),
          StrengthHomeEmpty(
            onStartWorkout: _startBlank,
            onCreateRoutine: () => _push(const RoutinesScreen()),
          ),
          ..._buildUpcoming(loc, snapshot),
        ] else if (analytics != null)
          ..._buildWithWorkouts(loc, analytics, snapshot),
      ],
    );
  }

  List<Widget> _buildUpcoming(
    AppLocalizations loc,
    StrengthHomeSnapshot? snapshot,
  ) {
    final upcoming = snapshot?.upcoming ?? const [];
    if (upcoming.isEmpty) return const [];
    return [
      RunSectionHeader(loc.strengthHomeUpcomingTitle),
      StrengthUpcomingWorkouts(
        workouts: upcoming,
        onOpen: (id) => _push(FutureWorkoutPlannerScreen(workoutId: id)),
      ),
    ];
  }

  List<Widget> _buildWithWorkouts(
    AppLocalizations loc,
    StrengthWeekAnalytics analytics,
    StrengthHomeSnapshot? snapshot,
  ) {
    final recent = _finished.take(5).toList();

    return [
      RunSectionHeader(loc.runStatsSectionThisWeek),
      StrengthWeekCard(
        analytics: analytics,
        snapshot: snapshot,
        categories: _categories,
        onEditGoal: _editWeeklyGoal,
      ),
      RunSectionHeader(loc.strengthHomeMusclesTitle),
      StrengthMusclesCard(
        muscles: _muscles,
        onTap: () => _push(const StrengthInsightsScreen()),
      ),
      RunSectionHeader(loc.runStatsOverview),
      RunPeriodChips(selected: _period, onChanged: _setPeriod),
      const SizedBox(height: 14),
      StrengthPeriodHero(analytics: analytics),
      RunSectionHeader(loc.runStatsSectionTrends),
      StrengthTrendsCard(analytics: analytics),
      RunSectionHeader(
        loc.strengthHomeRecordsTitle,
        trailing: RunHeaderAction(
          label: loc.strengthHomeSeeAll,
          onPressed: () => _push(const StrengthRecordsScreen()),
        ),
      ),
      StrengthRecentRecords(
        records: _records,
        onOpen: () => _push(const StrengthRecordsScreen()),
      ),
      RunSectionHeader(loc.progressGoals),
      GoalsSection(
        db: DatabaseHelper.instance,
        settingsRepo: DatabaseHelper.instance.settingsRepo,
        allowedScopes: const [GoalScope.anaerobic],
      ),
      ..._buildUpcoming(loc, snapshot),
      RunSectionHeader(
        loc.strengthHomeRecentTitle,
        trailing: RunHeaderAction(
          label: loc.strengthHomeSeeAll,
          onPressed: () => _push(const StrengthHistoryScreen()),
        ),
      ),
      StrengthRecentWorkouts(
        workouts: recent,
        categories: _categories,
        onOpen: (id) => _push(WorkoutDetailScreen(workoutId: id)),
      ),
    ];
  }
}
