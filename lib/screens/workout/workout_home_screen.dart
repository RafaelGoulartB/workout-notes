import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/services/strength_routine_day_inference.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/l10n/exercise_locale_helper.dart';
import 'package:workout_notes/models/cardio_activity_type.dart';
import 'package:workout_notes/models/strength_workout_summary.dart';
import 'package:workout_notes/repositories/strength_repository.dart';
import 'package:workout_notes/screens/strength/strength_home_screen.dart';
import 'package:workout_notes/services/run_today_service.dart';
import 'package:workout_notes/services/run_tracking_service.dart';
import 'package:workout_notes/services/stationary_bike_tracking_service.dart';
import 'package:workout_notes/services/strength_today_service.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/utils/strength_week_analytics.dart';
import 'package:workout_notes/widgets/ai/ai_coach_header_button.dart';
import 'package:workout_notes/widgets/run/run_pending_review_banner.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';
import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/screens/run/run_detail_screen.dart';
import 'package:workout_notes/screens/workout/workout_detail_screen.dart';
import 'package:workout_notes/widgets/strength/home/strength_home_format.dart';
import 'package:workout_notes/widgets/strength/home/workout_home_widgets.dart';
import '../../repositories/workout_repository.dart';
import '../../repositories/run_repository.dart';
import '../../services/rest_timer_service.dart';
import 'active_workout_screen.dart';
import '../run/run_record_screen.dart';
import '../run/run_stats_screen.dart';
import 'calendar_screen.dart';
import 'settings_screen.dart';
import 'rest_timer_screen.dart';

/// The Treino tab: live banners, this week across gym and running, and the
/// two hub entries (Musculação and Corrida) with a start button each.
class WorkoutHomeScreen extends StatefulWidget {
  final ValueListenable<int>? selectedTab;

  const WorkoutHomeScreen({super.key, this.selectedTab});

  @override
  State<WorkoutHomeScreen> createState() => _WorkoutHomeScreenState();
}

class _WorkoutHomeScreenState extends State<WorkoutHomeScreen> {
  final _workoutRepo = WorkoutRepository();
  final _strengthRepo = StrengthRepository();
  final _strengthToday = StrengthTodayService();
  final _runRepo = RunRepository();
  final _timerService = RestTimerService.instance;
  final _runTrackingService = RunTrackingService.instance;
  final _bikeTrackingService = StationaryBikeTrackingService.instance;
  bool _isLoading = true;
  List<Map<String, dynamic>> _activeWorkouts = [];

  WorkoutWeekOverview _overview = WorkoutWeekOverview.empty;
  StrengthHomeSnapshot? _strengthSnapshot;
  RunHomeSnapshot? _runSnapshot;
  bool _hasHistory = false;
  List<WorkoutDayMark> _weekDays = const [];
  List<StrengthWorkoutSummary> _recentGym = const [];
  List<RunActivity> _recentCardio = const [];
  Map<String, StrengthCategoryInfo> _categories = const {};
  double _strengthAverageSessions = 0;

  // Bumped on every reload so the unsaved-run banner re-reads its list.
  int _pendingReviewRefresh = 0;

  // Elapsed time timer for active workout
  Timer? _elapsedTimer;

  @override
  void initState() {
    super.initState();
    widget.selectedTab?.addListener(_onTabSelectionChanged);
    _runTrackingService.addListener(_onRunTrackingChanged);
    _bikeTrackingService.addListener(_onRunTrackingChanged);
    _runTrackingService.initialize();
    _loadData();
  }

  @override
  void dispose() {
    widget.selectedTab?.removeListener(_onTabSelectionChanged);
    _runTrackingService.removeListener(_onRunTrackingChanged);
    _bikeTrackingService.removeListener(_onRunTrackingChanged);
    _elapsedTimer?.cancel();
    super.dispose();
  }

  void _onRunTrackingChanged() {
    if (mounted) setState(() {});
  }

  void _onTabSelectionChanged() {
    if (widget.selectedTab?.value == 0 && _activeWorkouts.isNotEmpty) {
      _startElapsedTimer();
    } else {
      _stopElapsedTimer();
    }
  }

  /// Starts a periodic timer that keeps the elapsed time on the active
  /// workout banner live. Cancels any previous timer first.
  void _startElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _activeWorkouts.isNotEmpty) {
        setState(() {});
      }
    });
  }

  /// Cancels the elapsed timer.
  void _stopElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
  }

  Future<T?> _safe<T>(Future<T> future) async {
    try {
      return await future;
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _pendingReviewRefresh++;
    });
    try {
      final now = DateTime.now();
      await StrengthRoutineDayInference.runOnce();
      final today = DateTime(now.year, now.month, now.day);
      final monday = StrengthWeekAnalytics.mondayOf(today);
      // A year of history is enough for a week streak and keeps the reads
      // cheap; older weeks never change the number shown.
      final since = monday.subtract(const Duration(days: 7 * 52));

      final active = await _workoutRepo.getActiveWorkouts();
      final stamps = await _strengthRepo.loadWorkoutStamps(from: since);
      final cardio = await _runRepo.listActivities(
        limit: null,
        activityType: null,
        startedFrom: since,
      );
      final runs = cardio.where((a) => a.isRunning).toList();
      final strengthSnapshot = await _safe(_strengthToday.load(now: now));
      final runSnapshot = await _safe(RunTodayService().load(activities: runs));
      final recentGym =
          await _safe(_strengthRepo.loadFinishedWorkouts(limit: 3)) ??
          const <StrengthWorkoutSummary>[];
      final categories =
          await _safe(_strengthRepo.loadCategories()) ??
          const <String, StrengthCategoryInfo>{};

      // Monday–Sunday marks: what was done and what the plans expect.
      final plannedStrengthDays =
          strengthSnapshot?.plannedStrengthDays ?? const <int>[];
      final weekDays = [
        for (var i = 0; i < 7; i++)
          () {
            final date = monday.add(Duration(days: i));
            return WorkoutDayMark(
              date: date,
              strengthDone: stamps.any(
                (g) => DateUtils.isSameDay(g.date, date),
              ),
              // Sub-minute sessions are aborted starts, not runs.
              runDone: runs.any(
                (a) =>
                    (a.durationSeconds >= 60 || a.distanceMeters >= 100) &&
                    DateUtils.isSameDay(a.startedAt.toLocal(), date),
              ),
              strengthPlanned: plannedStrengthDays.contains(date.weekday),
              runPlanned: (runSnapshot?.weekPlan ?? const []).any(
                (d) => DateUtils.isSameDay(d.date, date),
              ),
            );
          }(),
      ];

      final overview = WorkoutWeekOverview.compute(
        gym: stamps,
        cardio: [
          for (final a in cardio)
            WorkoutCardioStamp(
              date: _dateOnly(a.startedAt.toLocal()),
              durationSeconds: a.movingTimeSeconds > 0
                  ? a.movingTimeSeconds
                  : a.durationSeconds,
              runDistanceMeters: a.isRunning ? a.distanceMeters : 0,
            ),
        ],
        now: now,
      );

      if (!mounted) return;
      setState(() {
        _activeWorkouts = active;
        _overview = overview;
        _strengthSnapshot = strengthSnapshot;
        _runSnapshot = runSnapshot;
        _weekDays = weekDays;
        _recentGym = recentGym;
        // Sub-minute sessions are aborted starts, not activities to revisit.
        _recentCardio = cardio
            .where((a) => a.durationSeconds >= 60 || a.distanceMeters >= 100)
            .take(3)
            .toList();
        _strengthAverageSessions = _averageWeeklySessions(stamps, monday);
        _categories = categories;
        _hasHistory = stamps.isNotEmpty || cardio.isNotEmpty;
        _isLoading = false;
      });
      // Keep the elapsed time live when there is an active workout
      if (active.isNotEmpty && (widget.selectedTab?.value ?? 0) == 0) {
        _startElapsedTimer();
      } else {
        _stopElapsedTimer();
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Sessions per week over the last 12 calendar weeks (this one
  /// included) — the same default period the gym hub averages over, so both
  /// screens show the same goal.
  static double _averageWeeklySessions(
    List<StrengthWorkoutStamp> stamps,
    DateTime monday,
  ) {
    const weeks = 12;
    final from = monday.subtract(const Duration(days: 7 * (weeks - 1)));
    return stamps.where((s) => !s.date.isBefore(from)).length / weeks;
  }

  // ===================== ACTIONS =====================
  Future<void> _startWorkout() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ActiveWorkoutScreen(
          suggestedDay: _strengthSnapshot?.today.startDay,
        ),
      ),
    );
    _loadData();
  }

  /// Starts today's suggested routine day (or a blank workout); resumes the
  /// unfinished workout of the day when there is one.
  Future<void> _trainStrength() async {
    if (_activeWorkouts.isNotEmpty) {
      return _openActiveWorkout(_activeWorkouts.first);
    }
    final day = _strengthSnapshot?.today.startDay;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ActiveWorkoutScreen(
          routineId: day?.routineId,
          routineDayId: day?.routineDayId,
        ),
      ),
    );
    _loadData();
  }

  Future<void> _openStrengthHub() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const StrengthHomeScreen()),
    );
    _loadData();
  }

  Future<void> _openRunHub() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RunStatsScreen()),
    );
    _loadData();
  }

  Future<void> _openActiveWorkout(Map<String, dynamic> workout) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ActiveWorkoutScreen(workoutId: workout['id'] as String?),
      ),
    );
    _loadData();
  }

  Future<void> _startRun() async {
    // A session planned for today (followed plan or planning phase) is opened
    // ready to run; without one this is a plain free run.
    // Resuming a run that is already recording never swaps its session.
    RunPlannedSession? planned;
    if (!_runTrackingService.state.isActive) {
      try {
        final snapshot = await RunTodayService().load();
        if (snapshot.today.status == RunTodayStatus.planned) {
          planned = snapshot.today.session;
        }
      } catch (_) {
        planned = null;
      }
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RunRecordScreen(
          planWorkout: planned?.workout,
          scheduledRun: planned?.scheduled,
        ),
      ),
    );
    _loadData();
  }

  Future<void> _openActiveBike() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const RunRecordScreen(
          initialActivityType: CardioActivityType.stationaryBike,
        ),
      ),
    );
    _loadData();
  }

  // ===================== HELPERS =====================
  String _formatHeaderDate(AppLocalizations loc) {
    return DateFormat(
      'EEEE, d MMMM',
      Intl.defaultLocale,
    ).format(DateTime.now());
  }

  /// Pretty-prints the elapsed time of the active workout (e.g. "23 min",
  /// "1h 12min"). Returns null if it can't be computed.
  String? _activeElapsed(Map<String, dynamic> workout) {
    final startStr = workout['start_time'] as String?;
    if (startStr == null) return null;
    final start = DateTime.tryParse(startStr);
    if (start == null) return null;
    final elapsed = DateTime.now().difference(start);
    if (elapsed.isNegative) return null;
    final h = elapsed.inHours;
    final m = elapsed.inMinutes % 60;
    if (h > 0) return '${h}h ${m}min';
    if (m > 0) return '${m}min';
    return '${elapsed.inSeconds}s';
  }

  bool get _hasAnyHistory =>
      _hasHistory ||
      _activeWorkouts.isNotEmpty ||
      _runTrackingService.state.isActive ||
      _bikeTrackingService.state.isActive;

  // ===================== BUILD =====================
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _formatHeaderDate(loc),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        centerTitle: false,
        automaticallyImplyLeading: false,
        actions: _buildAppBarActions(theme, loc),
      ),
      body: _isLoading
          ? const _LoadingSkeleton()
          : RefreshIndicator(
              onRefresh: _loadData,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  // The week hero leads; live sessions sit right below it.
                  if (_hasAnyHistory)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      sliver: SliverToBoxAdapter(child: _buildWeekHero()),
                    ),
                  if (_activeWorkouts.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _buildActiveBanner(
                        theme,
                        loc,
                        _activeWorkouts.first,
                      ),
                    ),
                  if (_runTrackingService.state.isActive)
                    SliverToBoxAdapter(
                      child: _buildActiveRunBanner(theme, loc),
                    ),
                  SliverToBoxAdapter(
                    child: RunPendingReviewBanner(
                      refreshToken: _pendingReviewRefresh,
                      onChanged: _loadData,
                    ),
                  ),
                  if (_bikeTrackingService.state.isActive)
                    SliverToBoxAdapter(
                      child: _buildActiveBikeBanner(theme, loc),
                    ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        if (!_hasAnyHistory) ...[
                          _buildFirstTimeEmpty(theme, loc),
                          const SizedBox(height: 20),
                          _buildAreas(loc),
                        ] else ...[
                          RunSectionHeader(loc.workoutHomeTodayTitle),
                          _buildToday(loc),
                          RunSectionHeader(loc.workoutHomeAreasTitle),
                          _buildAreas(loc),
                          if (_recentItems(loc).isNotEmpty) ...[
                            RunSectionHeader(loc.workoutHomeRecentTitle),
                            WorkoutRecentList(items: _recentItems(loc)),
                          ],
                        ],
                      ]),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  // ===================== WEEK / TODAY / AREAS / RECENT =====================
  Widget _buildWeekHero() {
    final strength = _strengthSnapshot;
    final strengthGoal = StrengthWeekGoal.resolve(
      planSessions: strength?.planSessionsPerWeek,
      userSessions: strength?.userWeeklyGoalSessions,
      averageSessions: _strengthAverageSessions,
    )?.sessions;
    final run = _runSnapshot;
    final runGoal = run?.plan?.weekPlannedMeters ?? run?.userWeeklyGoalMeters;
    final now = DateTime.now();

    return WorkoutWeekHero(
      strengthDone: _overview.strengthSessions,
      strengthGoal: strengthGoal,
      runMeters: _overview.runMeters,
      runGoalMeters: runGoal != null && runGoal > 0 ? runGoal : null,
      activeSeconds: _overview.activeSeconds,
      streakWeeks: _overview.streakWeeks,
      days: _weekDays,
      today: DateTime(now.year, now.month, now.day),
      onOpenStrength: _openStrengthHub,
      onOpenRun: _openRunHub,
    ).animate().fadeIn(duration: 300.ms);
  }

  String _dayName(StrengthRoutineDayInfo day) =>
      day.dayName.trim().isNotEmpty ? day.dayName : day.routineName;

  Widget _buildToday(AppLocalizations loc) {
    final colors = Theme.of(context).colorScheme;
    final strength = _strengthSnapshot?.today;
    final run = _runSnapshot?.today;
    final items = <WorkoutTodayItem>[];

    if (strength?.status == StrengthTodayStatus.planned &&
        strength?.day != null) {
      final day = strength!.day!;
      final details = [
        loc.strengthHomeExercisesCount(day.exerciseCount),
        if (day.estimatedSeconds > 0)
          '~${RunFormatters.durationHoursMinutes(day.estimatedSeconds)}',
      ].join(' · ');
      items.add(
        WorkoutTodayItem(
          key: const Key('workout-home-train'),
          icon: Icons.fitness_center,
          color: colors.primary,
          title: _dayName(day),
          subtitle: loc.workoutHomeTodayStrengthSubtitle(details),
          startTooltip: loc.workoutHomeQuickStrength,
          onStart: _trainStrength,
          onOpen: _openStrengthHub,
        ),
      );
    } else if (strength?.status == StrengthTodayStatus.done) {
      final done = strength!.doneWorkout;
      items.add(
        WorkoutTodayItem(
          icon: Icons.fitness_center,
          color: colors.primary,
          title: done?.routineLabel ?? loc.workoutHomeRecentFree,
          subtitle: loc.workoutHomeTodayStrengthSubtitle(
            done == null
                ? loc.workoutHomeTodayDone
                : '${RunFormatters.durationHoursMinutes(done.durationSeconds)}'
                      ' · ${loc.strengthHomeSetsCount(done.workingSets)}',
          ),
          done: true,
          startTooltip: loc.workoutHomeQuickStrength,
          onStart: _trainStrength,
          onOpen: done == null
              ? _openStrengthHub
              : () => _openWorkoutDetail(done.id),
        ),
      );
    }

    if (run?.status == RunTodayStatus.planned && run?.session != null) {
      final workout = run!.session!.workout;
      final distance = workout.plannedDistanceMeters;
      final seconds = workout.plannedDurationSeconds;
      final details = [
        if (distance > 0) RunFormatters.distanceWithUnit(distance),
        if (seconds > 0) '~${RunFormatters.durationHoursMinutes(seconds)}',
      ].join(' · ');
      items.add(
        WorkoutTodayItem(
          key: const Key('workout-home-run'),
          icon: Icons.directions_run,
          color: colors.tertiary,
          title: workout.name,
          subtitle: details.isEmpty
              ? loc.workoutHomeTodayRunPlain
              : loc.workoutHomeTodayRunSubtitle(details),
          startTooltip: loc.workoutHomeQuickRun,
          onStart: _startRun,
          onOpen: _openRunHub,
        ),
      );
    } else if (run?.status == RunTodayStatus.done) {
      final done = run!.doneActivity;
      items.add(
        WorkoutTodayItem(
          icon: Icons.directions_run,
          color: colors.tertiary,
          title: done?.title?.trim().isNotEmpty == true
              ? done!.title!
              : loc.workoutHomeRecentRun,
          subtitle: done == null
              ? loc.workoutHomeTodayRunPlain
              : loc.workoutHomeTodayRunSubtitle(
                  RunFormatters.distanceWithUnit(done.distanceMeters),
                ),
          done: true,
          startTooltip: loc.workoutHomeQuickRun,
          onStart: _startRun,
          onOpen: done == null ? _openRunHub : () => _openRunDetail(done.id),
        ),
      );
    }

    final rest =
        strength?.status == StrengthTodayStatus.rest ||
        run?.status == RunTodayStatus.rest;
    final next = strength?.next;
    return WorkoutTodayCard(
      items: items,
      emptyIcon: rest
          ? Icons.self_improvement_rounded
          : Icons.wb_sunny_outlined,
      emptyTitle: rest
          ? loc.workoutHomeTodayRestTitle
          : loc.workoutHomeTodayFreeTitle,
      emptySubtitle: next != null
          ? loc.workoutHomeTodayNextStrength(_dayName(next))
          : loc.workoutHomeTodayFreeSubtitle,
      onQuickStrength: _trainStrength,
      onQuickRun: _startRun,
    ).animate().fadeIn(duration: 300.ms, delay: 60.ms);
  }

  Widget _buildAreas(AppLocalizations loc) {
    final colors = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context).toString();
    String? last(DateTime? date) => date == null
        ? null
        : loc.workoutHomeAreaStrengthLast(DateFormat.MMMd(locale).format(date));
    final lastGym = _recentGym.isEmpty ? null : _recentGym.first.date;
    final runs = _recentCardio.where((a) => a.isRunning);
    final lastRun = runs.isEmpty ? null : runs.first.startedAt.toLocal();

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: WorkoutAreaTile(
              tileKey: const Key('workout-home-strength-hub'),
              icon: Icons.fitness_center,
              color: colors.primary,
              title: loc.workoutHomeHubStrengthTitle,
              line1: loc.workoutHomeHubStrengthWeek(_overview.strengthSessions),
              line2: last(lastGym),
              onTap: _openStrengthHub,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: WorkoutAreaTile(
              tileKey: const Key('workout-home-run-hub'),
              icon: Icons.directions_run,
              color: colors.tertiary,
              title: loc.workoutHomeHubRunTitle,
              line1: loc.workoutHomeHubRunWeek(
                RunFormatters.distanceWithUnit(_overview.runMeters),
              ),
              line2: last(lastRun),
              onTap: _openRunHub,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms, delay: 120.ms);
  }

  /// The latest gym workouts and cardio sessions, newest first.
  List<WorkoutRecentItem> _recentItems(AppLocalizations loc) {
    final colors = Theme.of(context).colorScheme;
    final items = <(DateTime, WorkoutRecentItem)>[];
    for (final w in _recentGym) {
      final category = w.dominantCategoryId == null
          ? null
          : _categories[w.dominantCategoryId];
      items.add((
        w.startTime ?? w.date,
        WorkoutRecentItem(
          icon: Icons.fitness_center,
          color: category == null ? colors.primary : Color(category.color),
          title:
              w.routineLabel ??
              _muscleLabel(loc, w) ??
              loc.workoutHomeRecentFree,
          date: w.date,
          duration: w.durationSeconds > 0
              ? RunFormatters.durationHoursMinutes(w.durationSeconds)
              : null,
          value: StrengthHomeFormat.volume(w.volumeKg),
          valueCaption: loc.strengthHomeSetsCount(w.workingSets),
          onTap: () => _openWorkoutDetail(w.id),
        ),
      ));
    }
    for (final a in _recentCardio) {
      final started = a.startedAt.toLocal();
      final title = a.title?.trim().isNotEmpty == true
          ? a.title!
          : switch (a.activityType) {
              CardioActivityType.running => loc.workoutHomeRecentRun,
              CardioActivityType.treadmill => loc.workoutHomeRecentTreadmill,
              CardioActivityType.stationaryBike => loc.workoutHomeRecentBike,
            };
      items.add((
        started,
        WorkoutRecentItem(
          icon: a.isStationaryBike
              ? Icons.pedal_bike_rounded
              : Icons.directions_run,
          color: colors.tertiary,
          title: title,
          date: started,
          duration: RunFormatters.durationHoursMinutes(
            a.movingTimeSeconds > 0 ? a.movingTimeSeconds : a.durationSeconds,
          ),
          value: a.distanceMeters > 0
              ? RunFormatters.distanceWithUnit(a.distanceMeters)
              : RunFormatters.durationHoursMinutes(a.durationSeconds),
          valueCaption: a.isRunning && a.avgPaceSecPerKm != null
              ? RunFormatters.paceWithUnit(a.avgPaceSecPerKm)
              : null,
          onTap: () => _openRunDetail(a.id),
        ),
      ));
    }
    items.sort((a, b) => b.$1.compareTo(a.$1));
    return [for (final i in items.take(4)) i.$2];
  }

  /// "Costas · Bíceps" for a workout without a routine day.
  String? _muscleLabel(AppLocalizations loc, StrengthWorkoutSummary w) {
    final names = [
      for (final id in w.categoryIds.take(2))
        if (_categories[id] != null)
          ExerciseLocaleHelper.categoryName(loc, _categories[id]!.row),
    ];
    return names.isEmpty ? null : names.join(' · ');
  }

  Future<void> _openWorkoutDetail(String id) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => WorkoutDetailScreen(workoutId: id)),
    );
    _loadData();
  }

  Future<void> _openRunDetail(String id) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RunDetailScreen(activityId: id)),
    );
    _loadData();
  }

  // ===================== APP BAR =====================
  List<Widget> _buildAppBarActions(ThemeData theme, AppLocalizations loc) {
    return [
      const AiCoachHeaderButton(),
      ListenableBuilder(
        listenable: _timerService,
        builder: (context, _) => _timerService.isActive
            ? _TimerPill(
                remainingSeconds: _timerService.remainingSeconds,
                isRunning: _timerService.isRunning,
                isPaused: _timerService.isPaused,
                shortTime: _timerService.shortTime,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RestTimerScreen()),
                ),
              )
            : IconButton(
                icon: const Icon(Icons.calendar_month_outlined),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CalendarScreen()),
                ),
                tooltip: loc.workoutHomeHistoryTooltip,
              ),
      ),
      IconButton(
        icon: const Icon(Icons.settings_outlined),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AppSettingsScreen()),
        ),
        tooltip: loc.workoutHomeSettingsTooltip,
      ),
    ];
  }

  // ===================== ACTIVE WORKOUT BANNER =====================
  Widget _buildActiveBanner(
    ThemeData theme,
    AppLocalizations loc,
    Map<String, dynamic> workout,
  ) {
    final elapsed = _activeElapsed(workout);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Material(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openActiveWorkout(workout),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
            child: Row(
              children: [
                // Pulsing dot
                _PulsingDot(color: theme.colorScheme.onPrimary),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        loc.workoutHomeOngoing,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        elapsed == null
                            ? loc.workoutHomeActiveNotStarted
                            : loc.workoutHomeActiveBannerSubtitle(elapsed),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onPrimary.withAlpha(220),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onPrimary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.play_arrow_rounded,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        loc.workoutHomeActiveBannerAction,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate().fadeIn(duration: 350.ms, delay: 60.ms).slideY(begin: 0.05);
  }

  Widget _buildActiveRunBanner(ThemeData theme, AppLocalizations loc) {
    final state = _runTrackingService.state;
    final subtitle = loc.workoutHomeRunActiveSubtitle(
      RunFormatters.distanceWithUnit(state.distanceMeters),
      RunFormatters.duration(state.durationSeconds),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Material(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _startRun,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
            child: Row(
              children: [
                _PulsingDot(color: theme.colorScheme.onSecondaryContainer),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        loc.workoutHomeRunOngoing,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        state.isPaused
                            ? '${loc.workoutHomeRunPaused} · $subtitle'
                            : subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer
                              .withAlpha(220),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: _startRun,
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: Text(loc.workoutHomeActiveBannerAction),
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.05);
  }

  Widget _buildActiveBikeBanner(ThemeData theme, AppLocalizations loc) {
    final state = _bikeTrackingService.state;
    final time = RunFormatters.duration(state.durationSeconds);
    final subtitle = state.isPaused
        ? '${loc.workoutHomeRunPaused} · $time'
        : '$time · ${loc.cardioActivityStationaryBikeSubtitle}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Material(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _openActiveBike,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
            child: Row(
              children: [
                _PulsingDot(color: theme.colorScheme.onSecondaryContainer),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        loc.cardioActivityStationaryBike,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer
                              .withAlpha(220),
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: _openActiveBike,
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: Text(loc.workoutHomeActiveBannerAction),
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.05);
  }

  // ===================== FIRST-TIME EMPTY =====================
  Widget _buildFirstTimeEmpty(ThemeData theme, AppLocalizations loc) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withAlpha(120),
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withAlpha(30),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.fitness_center,
                size: 32,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              loc.workoutHomeEmptyTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              loc.workoutHomeEmptySubtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _startWorkout,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(loc.workoutHomeEmptyCta),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 300.ms, delay: 120.ms).slideY(begin: 0.05);
  }
}

// ===================== SHARED WIDGETS =====================

/// Loading skeleton — keeps the layout stable so the transition into real
/// content doesn't cause a jarring jump.
class _LoadingSkeleton extends StatelessWidget {
  const _LoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.surfaceContainerHighest;
    BoxDecoration box({double r = 8}) =>
        BoxDecoration(color: color, borderRadius: BorderRadius.circular(r));
    Widget line({required double h, double? w, double r = 8}) => Container(
      height: h,
      width: w,
      decoration: box(r: r),
    );
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        line(h: 24, w: 180),
        const SizedBox(height: 8),
        line(h: 14, w: 240),
        const SizedBox(height: 20),
        line(h: 90, r: 20),
        const SizedBox(height: 20),
        line(h: 12, w: 80),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: line(h: 90, r: 16)),
            const SizedBox(width: 12),
            Expanded(child: line(h: 90, r: 16)),
          ],
        ),
        const SizedBox(height: 20),
        line(h: 12, w: 60),
        const SizedBox(height: 12),
        line(h: 110, r: 16),
        const SizedBox(height: 20),
        line(h: 12, w: 100),
        const SizedBox(height: 12),
        line(h: 64, r: 12),
        const SizedBox(height: 8),
        line(h: 64, r: 12),
      ],
    );
  }
}

class _PulsingDot extends StatelessWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 16,
      height: 16,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .scale(
                begin: const Offset(0.6, 0.6),
                end: const Offset(1.0, 1.0),
                duration: 1.seconds,
              )
              .fadeOut(begin: 0.6, duration: 1.seconds),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ],
      ),
    );
  }
}

class _TimerPill extends StatelessWidget {
  final int remainingSeconds;
  final bool isRunning;
  final bool isPaused;
  final String shortTime;
  final VoidCallback onTap;

  const _TimerPill({
    required this.remainingSeconds,
    required this.isRunning,
    required this.isPaused,
    required this.shortTime,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUrgent = remainingSeconds <= 5 && isRunning;
    final bg = isUrgent
        ? Colors.red.withAlpha(40)
        : theme.colorScheme.primaryContainer;
    final fg = isUrgent ? Colors.red : theme.colorScheme.onPrimaryContainer;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isPaused ? Icons.pause : Icons.timer, size: 18, color: fg),
            const SizedBox(width: 4),
            Text(
              shortTime,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
