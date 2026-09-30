import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show DateUtils;
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/models/strength_workout_summary.dart';
import 'package:workout_notes/repositories/run_repository.dart';
import 'package:workout_notes/repositories/strength_repository.dart';
import 'package:workout_notes/repositories/workout_repository.dart';
import 'package:workout_notes/services/indoor_tracking_service.dart';
import 'package:workout_notes/services/run_today_service.dart';
import 'package:workout_notes/services/run_tracking_service.dart';
import 'package:workout_notes/services/strength_routine_day_inference.dart';
import 'package:workout_notes/services/strength_today_service.dart';
import 'package:workout_notes/utils/date_utils.dart';
import 'package:workout_notes/utils/load_generation.dart';
import 'package:workout_notes/utils/strength_week_analytics.dart';
import 'package:workout_notes/widgets/workout/workout_home_widgets.dart';

/// Everything one load of the hub reads.
class WorkoutHomeData {
  final List<Map<String, dynamic>> active;
  final WorkoutWeekOverview overview;
  final StrengthHomeSnapshot? strengthSnapshot;
  final RunHomeSnapshot? runSnapshot;
  final bool hasHistory;
  final List<WorkoutDayMark> weekDays;
  final List<StrengthWorkoutSummary> recentGym;
  final List<RunActivity> recentCardio;
  final Map<String, StrengthCategoryInfo> categories;
  final double strengthAverageSessions;

  const WorkoutHomeData({
    required this.active,
    required this.overview,
    required this.strengthSnapshot,
    required this.runSnapshot,
    required this.hasHistory,
    required this.weekDays,
    required this.recentGym,
    required this.recentCardio,
    required this.categories,
    required this.strengthAverageSessions,
  });
}

/// State and data loading of the Treino tab: this week across gym and
/// running, today's plan, recent sessions, and whether a run / indoor session is
/// being recorded. Only the newest load applies its result, and a failed one
/// keeps whatever is already on screen (with a retry), instead of passing for
/// an empty history.
class WorkoutHomeController extends ChangeNotifier {
  WorkoutHomeController({
    WorkoutRepository? workoutRepo,
    StrengthRepository? strengthRepo,
    StrengthTodayService? strengthToday,
    RunRepository? runRepo,
    RunTrackingService? runTracking,
    IndoorTrackingService? indoorTracking,
  }) : _workoutRepo = workoutRepo ?? DatabaseHelper.instance.workoutRepo,
       _strengthRepo = strengthRepo ?? DatabaseHelper.instance.strengthRepo,
       _strengthToday = strengthToday ?? StrengthTodayService(),
       _runRepo = runRepo ?? DatabaseHelper.instance.runRepo,
       runTracking = runTracking ?? RunTrackingService.instance,
       indoorTracking = indoorTracking ?? IndoorTrackingService.instance {
    _runActive = this.runTracking.state.isActive;
    _indoorActive = this.indoorTracking.state.isActive;
    this.runTracking.addListener(_onTrackingChanged);
    this.indoorTracking.addListener(_onTrackingChanged);
    this.runTracking.initialize().catchError((Object _) {});
  }

  final WorkoutRepository _workoutRepo;
  final StrengthRepository _strengthRepo;
  final StrengthTodayService _strengthToday;
  final RunRepository _runRepo;
  final RunTrackingService runTracking;
  final IndoorTrackingService indoorTracking;
  final _generation = LoadGeneration();
  bool _disposed = false;

  bool _isLoading = true;
  bool _hasLoaded = false;
  bool _loadFailed = false;
  List<Map<String, dynamic>> _activeWorkouts = [];

  // Whether a run / an indoor session is being recorded. The hub only rebuilds
  // when this flips; the banners follow the live tracking state themselves.
  bool _runActive = false;
  bool _indoorActive = false;

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

  bool get isLoading => _isLoading;
  bool get hasLoaded => _hasLoaded;
  bool get loadFailed => _loadFailed;
  List<Map<String, dynamic>> get activeWorkouts => _activeWorkouts;
  bool get runActive => _runActive;
  bool get indoorActive => _indoorActive;
  WorkoutWeekOverview get overview => _overview;
  StrengthHomeSnapshot? get strengthSnapshot => _strengthSnapshot;
  RunHomeSnapshot? get runSnapshot => _runSnapshot;
  List<WorkoutDayMark> get weekDays => _weekDays;
  List<StrengthWorkoutSummary> get recentGym => _recentGym;
  List<RunActivity> get recentCardio => _recentCardio;
  Map<String, StrengthCategoryInfo> get categories => _categories;
  double get strengthAverageSessions => _strengthAverageSessions;
  int get pendingReviewRefresh => _pendingReviewRefresh;

  bool get hasAnyHistory =>
      _hasHistory || _activeWorkouts.isNotEmpty || _runActive || _indoorActive;

  void _onTrackingChanged() {
    final run = runTracking.state.isActive;
    final indoor = indoorTracking.state.isActive;
    if (_disposed || (run == _runActive && indoor == _indoorActive)) return;
    _runActive = run;
    _indoorActive = indoor;
    notifyListeners();
  }

  Future<T?> _safe<T>(Future<T> future) async {
    try {
      return await future;
    } catch (_) {
      return null;
    }
  }

  /// Reloads the hub.
  Future<void> load() async {
    if (_disposed) return;
    final token = _generation.begin();
    _pendingReviewRefresh++;
    if (!_hasLoaded) _isLoading = true;
    notifyListeners();
    try {
      final data = await _fetchData();
      if (_disposed || !_generation.isCurrent(token)) return;
      _activeWorkouts = data.active;
      _overview = data.overview;
      _strengthSnapshot = data.strengthSnapshot;
      _runSnapshot = data.runSnapshot;
      _weekDays = data.weekDays;
      _recentGym = data.recentGym;
      _recentCardio = data.recentCardio;
      _strengthAverageSessions = data.strengthAverageSessions;
      _categories = data.categories;
      _hasHistory = data.hasHistory;
      _hasLoaded = true;
      _loadFailed = false;
      _isLoading = false;
      notifyListeners();
    } catch (_) {
      if (_disposed || !_generation.isCurrent(token)) return;
      _loadFailed = true;
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<WorkoutHomeData> _fetchData() async {
    final now = DateTime.now();
    // Links old workouts to their routine day; the strength snapshot reads
    // that link, so it goes first.
    await StrengthRoutineDayInference.runOnce();
    final today = dayOf(now);
    final monday = mondayOf(today);
    // A year of history is enough for a week streak and keeps the reads
    // cheap; older weeks never change the number shown.
    final since = monday.subtract(const Duration(days: 7 * 52));

    // The rest is independent, so the awaits no longer chain (SQLite still
    // serialises the statements). Only this week's runs are read in full —
    // the plan card needs them; the year is read as light stamps.
    final weekRuns = _runRepo
        .listActivities(limit: null, activityType: null, startedFrom: monday)
        .then((all) => all.where((a) => a.isRunning).toList());
    final (
      active,
      stamps,
      cardio,
      recentCardio,
      strengthSnapshot,
      runSnapshot,
      recentGym,
      categories,
    ) = await (
      _workoutRepo.getActiveWorkouts(),
      _strengthRepo.loadWorkoutStamps(from: since),
      _runRepo.listCardioStamps(startedFrom: since),
      _runRepo.listRecentCardio(limit: 3, startedFrom: since),
      _safe(_strengthToday.load(now: now)),
      weekRuns.then((runs) => _safe(RunTodayService().load(activities: runs))),
      _safe(_strengthRepo.loadFinishedWorkouts(limit: 3)),
      _safe(_strengthRepo.loadCategories()),
    ).wait;

    // Monday–Sunday marks: what was done and what the plans expect.
    final plannedStrengthDays =
        strengthSnapshot?.plannedStrengthDays ?? const <int>[];
    final weekDays = [
      for (var i = 0; i < 7; i++)
        () {
          final date = monday.add(Duration(days: i));
          return WorkoutDayMark(
            date: date,
            strengthDone: stamps.any((g) => DateUtils.isSameDay(g.date, date)),
            // Sub-minute sessions are aborted starts, not runs.
            runDone: cardio.any(
              (a) =>
                  a.isRunning &&
                  a.countsAsSession &&
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
            date: dayOf(a.startedAt.toLocal()),
            durationSeconds: a.movingTimeSeconds > 0
                ? a.movingTimeSeconds
                : a.durationSeconds,
            runDistanceMeters: a.isRunning ? a.distanceMeters : 0,
          ),
      ],
      now: now,
    );

    return WorkoutHomeData(
      active: active,
      overview: overview,
      strengthSnapshot: strengthSnapshot,
      runSnapshot: runSnapshot,
      hasHistory: stamps.isNotEmpty || cardio.isNotEmpty,
      weekDays: weekDays,
      recentGym: recentGym ?? const <StrengthWorkoutSummary>[],
      recentCardio: recentCardio,
      categories: categories ?? const <String, StrengthCategoryInfo>{},
      strengthAverageSessions: averageWeeklySessions(stamps, monday),
    );
  }

  /// Sessions per week over the last 12 calendar weeks (this one
  /// included) — the same default period the gym hub averages over, so both
  /// screens show the same goal.
  @visibleForTesting
  static double averageWeeklySessions(
    List<StrengthWorkoutStamp> stamps,
    DateTime monday,
  ) {
    const weeks = 12;
    final from = monday.subtract(const Duration(days: 7 * (weeks - 1)));
    return stamps.where((s) => !s.date.isBefore(from)).length / weeks;
  }

  @override
  void dispose() {
    _disposed = true;
    _generation.invalidate();
    runTracking.removeListener(_onTrackingChanged);
    indoorTracking.removeListener(_onTrackingChanged);
    super.dispose();
  }
}
