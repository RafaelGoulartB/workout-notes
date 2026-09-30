import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/l10n/exercise_locale_helper.dart';
import 'package:workout_notes/models/cardio_activity_type.dart';
import 'package:workout_notes/models/strength_workout_summary.dart';
import 'package:workout_notes/screens/run/run_detail_screen.dart';
import 'package:workout_notes/screens/run/run_record_screen.dart';
import 'package:workout_notes/screens/run/run_stats_screen.dart';
import 'package:workout_notes/screens/settings/settings_screen.dart';
import 'package:workout_notes/screens/strength/strength_home_screen.dart';
import 'package:workout_notes/screens/workout/active_workout_screen.dart';
import 'package:workout_notes/screens/workout/calendar_screen.dart';
import 'package:workout_notes/screens/workout/rest_timer_screen.dart';
import 'package:workout_notes/screens/workout/workout_detail_screen.dart';
import 'package:workout_notes/screens/workout/workout_home_controller.dart';
import 'package:workout_notes/services/rest_timer_service.dart';
import 'package:workout_notes/services/run_today_service.dart';
import 'package:workout_notes/services/strength_today_service.dart';
import 'package:workout_notes/utils/date_utils.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/utils/strength_week_analytics.dart';
import 'package:workout_notes/widgets/ai/ai_coach_header_button.dart';
import 'package:workout_notes/widgets/run/run_pending_review_banner.dart';
import 'package:workout_notes/widgets/strength/home/strength_home_format.dart';
import 'package:workout_notes/widgets/ui/load_error_view.dart';
import 'package:workout_notes/widgets/ui/ui.dart';
import 'package:workout_notes/widgets/workout/active_session_banner.dart';
import 'package:workout_notes/widgets/workout/workout_home_chrome.dart';
import 'package:workout_notes/widgets/workout/workout_home_widgets.dart';

/// The Treino tab: live banners, this week across gym and running, and the
/// two hub entries (Musculação and Corrida) with a start button each.
class WorkoutHomeScreen extends StatefulWidget {
  const WorkoutHomeScreen({super.key});

  @override
  State<WorkoutHomeScreen> createState() => _WorkoutHomeScreenState();
}

class _WorkoutHomeScreenState extends State<WorkoutHomeScreen> {
  final _controller = WorkoutHomeController();
  final _timerService = RestTimerService.instance;

  @override
  void initState() {
    super.initState();
    _controller.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadData() => _controller.load();

  // ===================== ACTIONS =====================
  Future<void> _startWorkout() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ActiveWorkoutScreen(
          suggestedDay: _controller.strengthSnapshot?.today.startDay,
        ),
      ),
    );
    _loadData();
  }

  /// Starts today's suggested routine day (or a blank workout); resumes the
  /// unfinished workout of the day when there is one.
  Future<void> _trainStrength() async {
    if (_controller.activeWorkouts.isNotEmpty) {
      return _openActiveWorkout(_controller.activeWorkouts.first);
    }
    final day = _controller.strengthSnapshot?.today.startDay;
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
    if (!_controller.runTracking.state.isActive) {
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

  // ===================== BUILD =====================
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => _buildScreen(context),
    );
  }

  Widget _buildScreen(BuildContext context) {
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
      body: _controller.isLoading
          ? const WorkoutHomeLoadingSkeleton()
          : (_controller.loadFailed && !_controller.hasLoaded)
          ? LoadErrorView(onRetry: _loadData)
          : RefreshIndicator(
              onRefresh: _loadData,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  if (_controller.loadFailed)
                    SliverToBoxAdapter(
                      child: LoadErrorBanner(onRetry: _loadData),
                    ),
                  // The week hero leads; live sessions sit right below it.
                  if (_controller.hasAnyHistory)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      sliver: SliverToBoxAdapter(child: _buildWeekHero()),
                    ),
                  if (_controller.activeWorkouts.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _buildActiveBanner(
                        theme,
                        loc,
                        _controller.activeWorkouts.first,
                      ),
                    ),
                  if (_controller.runActive)
                    SliverToBoxAdapter(
                      child: _buildActiveRunBanner(theme, loc),
                    ),
                  SliverToBoxAdapter(
                    child: RunPendingReviewBanner(
                      refreshToken: _controller.pendingReviewRefresh,
                      onChanged: _loadData,
                    ),
                  ),
                  if (_controller.indoorActive)
                    SliverToBoxAdapter(
                      child: _buildActiveBikeBanner(theme, loc),
                    ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        if (!_controller.hasAnyHistory) ...[
                          _buildFirstTimeEmpty(theme, loc),
                          const SizedBox(height: 20),
                          _buildAreas(loc),
                        ] else ...[
                          AppSectionHeader(loc.workoutHomeTodayTitle),
                          _buildToday(loc),
                          AppSectionHeader(loc.workoutHomeAreasTitle),
                          _buildAreas(loc),
                          if (_recentItems(loc).isNotEmpty) ...[
                            AppSectionHeader(loc.workoutHomeRecentTitle),
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
    final strength = _controller.strengthSnapshot;
    final strengthGoal = StrengthWeekGoal.resolve(
      planSessions: strength?.planSessionsPerWeek,
      userSessions: strength?.userWeeklyGoalSessions,
      averageSessions: _controller.strengthAverageSessions,
    )?.sessions;
    final run = _controller.runSnapshot;
    final runGoal = run?.plan?.weekPlannedMeters ?? run?.userWeeklyGoalMeters;
    final now = DateTime.now();

    return FadeSlideIn(
      child: WorkoutWeekHero(
        strengthDone: _controller.overview.strengthSessions,
        strengthGoal: strengthGoal,
        runMeters: _controller.overview.runMeters,
        runGoalMeters: runGoal != null && runGoal > 0 ? runGoal : null,
        activeSeconds: _controller.overview.activeSeconds,
        streakWeeks: _controller.overview.streakWeeks,
        days: _controller.weekDays,
        today: dayOf(now),
        onOpenStrength: _openStrengthHub,
        onOpenRun: _openRunHub,
      ),
    );
  }

  String _dayName(StrengthRoutineDayInfo day) =>
      day.dayName.trim().isNotEmpty ? day.dayName : day.routineName;

  Widget _buildToday(AppLocalizations loc) {
    final colors = Theme.of(context).colorScheme;
    final strength = _controller.strengthSnapshot?.today;
    final run = _controller.runSnapshot?.today;
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
    return FadeSlideIn(
      delay: const Duration(milliseconds: 60),
      child: WorkoutTodayCard(
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
      ),
    );
  }

  Widget _buildAreas(AppLocalizations loc) {
    final colors = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context).toString();
    String? last(DateTime? date) => date == null
        ? null
        : loc.workoutHomeAreaStrengthLast(DateFormat.MMMd(locale).format(date));
    final lastGym = _controller.recentGym.isEmpty
        ? null
        : _controller.recentGym.first.date;
    final runs = _controller.recentCardio.where((a) => a.isRunning);
    final lastRun = runs.isEmpty ? null : runs.first.startedAt.toLocal();

    return FadeSlideIn(
      delay: const Duration(milliseconds: 120),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: WorkoutAreaTile(
                tileKey: const Key('workout-home-strength-hub'),
                icon: Icons.fitness_center,
                color: colors.primary,
                title: loc.workoutHomeHubStrengthTitle,
                line1: loc.workoutHomeHubStrengthWeek(
                  _controller.overview.strengthSessions,
                ),
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
                  RunFormatters.distanceWithUnit(
                    _controller.overview.runMeters,
                  ),
                ),
                line2: last(lastRun),
                onTap: _openRunHub,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The latest gym workouts and cardio sessions, newest first.
  List<WorkoutRecentItem> _recentItems(AppLocalizations loc) {
    final colors = Theme.of(context).colorScheme;
    final items = <(DateTime, WorkoutRecentItem)>[];
    for (final w in _controller.recentGym) {
      final category = w.dominantCategoryId == null
          ? null
          : _controller.categories[w.dominantCategoryId];
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
    for (final a in _controller.recentCardio) {
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
        if (_controller.categories[id] != null)
          ExerciseLocaleHelper.categoryName(
            loc,
            _controller.categories[id]!.row,
          ),
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
            ? WorkoutHomeTimerPill(
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

  // ===================== ACTIVE SESSION BANNERS =====================
  // The banners refresh their own subtitle (a clock, or the tracking service),
  // so the hub is not rebuilt for them.

  /// Pretty-prints the elapsed time of the active workout (e.g. "23 min",
  /// "1h 12min"). Returns null if it can't be computed.
  static String? _activeElapsed(Map<String, dynamic> workout) {
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

  Widget _buildActiveBanner(
    ThemeData theme,
    AppLocalizations loc,
    Map<String, dynamic> workout,
  ) {
    return ActiveSessionBanner(
      background: theme.colorScheme.primary,
      foreground: theme.colorScheme.onPrimary,
      title: loc.workoutHomeOngoing,
      tickEverySecond: true,
      subtitle: () {
        final elapsed = _activeElapsed(workout);
        return elapsed == null
            ? loc.workoutHomeActiveNotStarted
            : loc.workoutHomeActiveBannerSubtitle(elapsed);
      },
      onTap: () => _openActiveWorkout(workout),
      entranceDuration: const Duration(milliseconds: 350),
      entranceDelay: const Duration(milliseconds: 60),
      action: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
    );
  }

  Widget _buildActiveRunBanner(ThemeData theme, AppLocalizations loc) {
    return ActiveSessionBanner(
      background: theme.colorScheme.secondaryContainer,
      foreground: theme.colorScheme.onSecondaryContainer,
      title: loc.workoutHomeRunOngoing,
      refresh: _controller.runTracking,
      subtitle: () {
        final state = _controller.runTracking.state;
        final subtitle = loc.workoutHomeRunActiveSubtitle(
          RunFormatters.distanceWithUnit(state.distanceMeters),
          RunFormatters.duration(state.durationSeconds),
        );
        return state.isPaused
            ? '${loc.workoutHomeRunPaused} · $subtitle'
            : subtitle;
      },
      onTap: _startRun,
      action: FilledButton.tonalIcon(
        onPressed: _startRun,
        icon: const Icon(Icons.play_arrow_rounded, size: 18),
        label: Text(loc.workoutHomeActiveBannerAction),
      ),
    );
  }

  Widget _buildActiveBikeBanner(ThemeData theme, AppLocalizations loc) {
    return ActiveSessionBanner(
      background: theme.colorScheme.secondaryContainer,
      foreground: theme.colorScheme.onSecondaryContainer,
      title: loc.cardioActivityStationaryBike,
      refresh: _controller.indoorTracking,
      subtitle: () {
        final state = _controller.indoorTracking.state;
        final time = RunFormatters.duration(state.durationSeconds);
        return state.isPaused
            ? '${loc.workoutHomeRunPaused} · $time'
            : '$time · ${loc.cardioActivityStationaryBikeSubtitle}';
      },
      onTap: _openActiveBike,
      action: FilledButton.tonalIcon(
        onPressed: _openActiveBike,
        icon: const Icon(Icons.play_arrow_rounded, size: 18),
        label: Text(loc.workoutHomeActiveBannerAction),
      ),
    );
  }

  // ===================== FIRST-TIME EMPTY =====================
  Widget _buildFirstTimeEmpty(ThemeData theme, AppLocalizations loc) {
    return FadeSlideIn(
      delay: const Duration(milliseconds: 120),
      slideY: 0.05,
      child: Padding(
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
      ),
    );
  }
}

// ===================== SHARED WIDGETS =====================
