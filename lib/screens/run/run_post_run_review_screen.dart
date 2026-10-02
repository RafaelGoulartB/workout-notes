import 'package:flutter/material.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/models/run_gear.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/models/run_review_draft.dart';
import 'package:workout_notes/models/run_track_point.dart';
import 'package:workout_notes/models/scheduled_run.dart';
import 'package:workout_notes/repositories/run_plan_repository.dart';
import 'package:workout_notes/repositories/run_repository.dart';
import 'package:workout_notes/screens/run/run_detail_screen.dart';
import 'package:workout_notes/screens/run/run_route_map_screen.dart';
import 'package:workout_notes/services/run_tracking_service.dart';
import 'package:workout_notes/utils/date_utils.dart';
import 'package:workout_notes/utils/run_completion_policy.dart';
import 'package:workout_notes/utils/run_elevation_analytics.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/utils/run_pace_analytics.dart';
import 'package:workout_notes/utils/run_review_insights.dart';
import 'package:workout_notes/widgets/run/run_detail_chart_card.dart';
import 'package:workout_notes/widgets/run/run_review_widgets.dart';
import 'package:workout_notes/widgets/run/run_route_map.dart';
import 'package:workout_notes/widgets/run/run_route_sketch.dart';
import 'package:workout_notes/widgets/run/run_splits_list.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// What to do when the runner leaves the review with back / gesture.
enum _LeaveChoice { save, discard, keepEditing }

class RunPostRunReviewScreen extends StatefulWidget {
  final RunReviewDraft draft;

  /// Draws OpenStreetMap tiles under the route; tests turn this off.
  final bool showMapTiles;

  const RunPostRunReviewScreen({
    super.key,
    required this.draft,
    this.showMapTiles = true,
  });

  @override
  State<RunPostRunReviewScreen> createState() => _RunPostRunReviewScreenState();
}

class _RunPostRunReviewScreenState extends State<RunPostRunReviewScreen> {
  final _runRepository = DatabaseHelper.instance.runRepo;
  final _planRepository = DatabaseHelper.instance.runPlanRepo;
  final _trackingService = RunTrackingService.instance;
  final _selectedDistance = ValueNotifier<double?>(null);
  late final TextEditingController _titleController;
  late final TextEditingController _notesController;
  late final TextEditingController _distanceController;
  late final List<Offset> _route;
  late final List<RunTrackPoint> _points;
  late final RunPaceAnalytics _analytics;
  late final RunElevationProfile _elevation;

  RunPlanWorkout? _planWorkout;
  ScheduledRun? _nextSession;
  RunGearUsage? _gear;
  RunReviewInsights _insights = RunReviewInsights.empty;
  double? _rpe;
  int? _feelingRating;
  bool _completePlannedWorkout = false;
  bool _loading = true;
  bool _saving = false;

  RunReviewDraft get _draft => widget.draft;
  bool get _hasPlannedWorkout => _draft.planWorkoutId != null;
  bool get _isTooShort => RunCompletionPolicy.isTooShort(_draft.activity);
  bool get _isStationaryBike => _draft.activity.isStationaryBike;

  /// Indoor sessions have no GPS: the runner types the distance in.
  bool get _needsManualDistance => _draft.activity.isIndoor;

  double get _reviewedDistanceMeters {
    if (!_needsManualDistance) return _draft.activity.distanceMeters;
    final kilometers = double.tryParse(
      _distanceController.text.trim().replaceAll(',', '.'),
    );
    return (kilometers ?? 0).clamp(0, 1000) * 1000;
  }

  /// Average pace over the reviewed distance (treadmill needs it computed:
  /// the recorder cannot know the distance).
  double? get _reviewedPace {
    final activity = _draft.activity;
    if (!_needsManualDistance && activity.avgPaceSecPerKm != null) {
      return activity.avgPaceSecPerKm;
    }
    return RunPaceAnalytics.paceSecPerKm(
      _reviewedDistanceMeters,
      activity.movingTimeSeconds > 0
          ? activity.movingTimeSeconds
          : activity.durationSeconds,
    );
  }

  @override
  void initState() {
    super.initState();
    final activity = _draft.activity;
    _titleController = TextEditingController(text: activity.title ?? '');
    _notesController = TextEditingController(text: activity.notes ?? '');
    _distanceController = TextEditingController(
      text: activity.distanceMeters > 0
          ? RunFormatters.decimal(activity.distanceMeters / 1000, 2)
          : '',
    );
    _distanceController.addListener(_onDistanceChanged);
    _rpe = activity.rpe;
    _feelingRating = activity.feelingRating;
    _completePlannedWorkout = _hasPlannedWorkout && !_isTooShort;
    _route = RunRouteSketch.parse(activity.polylineSummary);
    _points = activity.isRun ? _draft.trackPoints : const [];
    final profile = RunTrackProfile.fromPoints(_points);
    _analytics = RunPaceAnalytics.fromTrackPoints(
      _points,
      activityAvgPaceSecPerKm: activity.avgPaceSecPerKm,
      profile: profile,
    );
    _elevation = RunElevationProfile.fromTrackPoints(_points, profile: profile);
    _loadContext();
  }

  @override
  void dispose() {
    _selectedDistance.dispose();
    _titleController.dispose();
    _notesController.dispose();
    _distanceController
      ..removeListener(_onDistanceChanged)
      ..dispose();
    super.dispose();
  }

  void _onDistanceChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadContext() async {
    try {
      await _readContext();
    } catch (error, stack) {
      // The review stays usable without its plan context and history.
      debugPrint('Run review context failed: $error\n$stack');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _readContext() async {
    final activity = _draft.activity;
    final scheduledId = _draft.scheduledRunId;
    final workoutId = _draft.planWorkoutId;

    // The plan context and the run history are independent reads, so they
    // run together (SQLite still serialises the statements).
    final scheduledFuture = scheduledId == null
        ? Future<ScheduledRun?>.value(null)
        : _planRepository.getScheduledRun(scheduledId);
    final workoutFuture = scheduledFuture.then((scheduled) async {
      final fromSchedule = scheduled?.workout;
      if (fromSchedule != null || workoutId == null) return fromSchedule;
      return _planRepository.getWorkout(workoutId);
    });
    final historyFuture = _isStationaryBike
        ? Future.value((RunReviewInsights.empty, null, null))
        : _loadHistory(activity, scheduledId);

    final RunPlanWorkout? workout = await workoutFuture;
    final (insights, next, gear) = await historyFuture;
    if (!mounted) return;
    setState(() {
      _planWorkout = workout;
      _insights = insights;
      _nextSession = next;
      _gear = gear;
      if (_titleController.text.trim().isEmpty && workout != null) {
        _titleController.text = workout.name;
      }
      _loading = false;
    });
  }

  Future<(RunReviewInsights, ScheduledRun?, RunGearUsage?)> _loadHistory(
    RunActivity activity,
    String? scheduledId,
  ) async {
    // The week and the month of the run, with a day of slack; the pure
    // function does the exact filtering.
    final since = addDays(RunReviewInsights.weekStart(activity.startedAt), -40);
    final (ranking, recent, next, gear) = await (
      activity.isRun
          ? _runRepository.listActivitiesForRanking()
          : Future.value(const <RunActivity>[]),
      _runRepository.listActivities(
        limit: null,
        activityType: null,
        activityTypes: RunRepository.runningTypes,
        startedFrom: since,
      ),
      _nextPlannedSession(exclude: scheduledId),
      _defaultGearUsage(),
    ).wait;
    final insights = RunReviewInsights.compute(
      draft: activity,
      ranking: ranking,
      recent: recent,
    );
    return (insights, next, gear);
  }

  Future<RunGearUsage?> _defaultGearUsage() async {
    final gearRepo = DatabaseHelper.instance.runGearRepo;
    final defaultGear = await gearRepo.getDefaultGear();
    return defaultGear == null ? null : gearRepo.getUsage(defaultGear.id);
  }

  /// The next session of the followed plan, if any (light: one date range).
  Future<ScheduledRun?> _nextPlannedSession({String? exclude}) async {
    final plan = await _planRepository.getActivatedPlan(hydrate: false);
    if (plan == null) return null;
    final now = DateTime.now();
    final today = dayOf(now);
    final upcoming = await _planRepository.getScheduledRuns(
      today,
      addDays(today, 28),
    );
    for (final run in upcoming) {
      if (run.id != exclude &&
          run.isPlanned &&
          run.runPlanId == plan.id &&
          run.runActivityId == null) {
        return run;
      }
    }
    return null;
  }

  Future<void> _openMap() async {
    if (_points.length < 2) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => RunRouteMapScreen(
          title: '',
          points: _points,
          averagePaceSecPerKm: _reviewedPace,
          showMapTiles: widget.showMapTiles,
        ),
      ),
    );
  }

  // ------------------------------------------------------------ save / leave

  /// Returns true once the run is saved and the detail screen is showing.
  Future<bool> _save() async {
    if (_saving) return false;
    setState(() => _saving = true);
    final saved = await _trackingService.saveReviewedRun(
      draft: _draft,
      completePlannedWorkout:
          _hasPlannedWorkout && !_isTooShort && _completePlannedWorkout,
      title: _titleController.text,
      notes: _notesController.text,
      rpe: _rpe,
      feelingRating: _feelingRating,
      distanceMeters: _needsManualDistance ? _reviewedDistanceMeters : null,
    );
    if (!mounted) return false;
    if (saved == null) {
      setState(() => _saving = false);
      final loc = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isStationaryBike
                ? loc.stationaryBikeReviewSaveError
                : loc.runReviewSaveError,
          ),
        ),
      );
      return false;
    }
    final gearId = _gear?.gear.id;
    if (gearId != null && saved.isRunning) {
      await DatabaseHelper.instance.runGearRepo.setActivityGear(
        saved.id,
        gearId,
      );
      if (!mounted) return true;
    }
    await Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => RunDetailScreen(
          activityId: saved.id,
          showMapTiles: widget.showMapTiles,
        ),
      ),
    );
    return true;
  }

  Future<bool> _confirmDiscard() async {
    final loc = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: _isStationaryBike
          ? loc.stationaryBikeReviewDiscardTitle
          : loc.runReviewDiscardTitle,
      message: _isStationaryBike
          ? loc.stationaryBikeReviewDiscardBody
          : loc.runReviewDiscardBody,
      confirmLabel: loc.runReviewDiscard,
      destructive: true,
      cancelLabel: MaterialLocalizations.of(context).cancelButtonLabel,
    );
    return confirmed == true;
  }

  Future<void> _discardNow() async {
    setState(() => _saving = true);
    await _trackingService.discardReview(_draft);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _discard() async {
    if (await _confirmDiscard() && mounted) await _discardNow();
  }

  /// Back / gesture: the run is still only a pending draft, so ask before
  /// leaving instead of silently orphaning it.
  Future<void> _confirmLeave() async {
    if (_saving) return;
    final loc = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final choice = await showDialog<_LeaveChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(loc.runReviewLeaveTitle),
        content: Text(loc.runReviewLeaveBody),
        actionsOverflowButtonSpacing: 4,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _LeaveChoice.keepEditing),
            child: Text(loc.runReviewLeaveKeepEditing),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: colors.error),
            onPressed: () => Navigator.pop(context, _LeaveChoice.discard),
            child: Text(loc.runReviewDiscard),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _LeaveChoice.save),
            child: Text(loc.runReviewSave),
          ),
        ],
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case _LeaveChoice.save:
        await _save();
      case _LeaveChoice.discard:
        await _discardNow();
      case _LeaveChoice.keepEditing:
      case null:
        break;
    }
  }

  // ------------------------------------------------------------------ build

  String _titleHint(AppLocalizations loc) {
    if (_isStationaryBike) return loc.stationaryBikeReviewTitleHint;
    if (_draft.activity.isTreadmill) return loc.runReviewTreadmillTitleHint;
    return loc.runReviewTitleHint;
  }

  Widget _routeSection(AppLocalizations loc) {
    if (_points.length >= 2) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppUi.cardRadius),
        child: SizedBox(
          height: 220,
          child: RunRouteMap(
            points: _points,
            averagePaceSecPerKm: _reviewedPace,
            selectedDistance: _selectedDistance,
            showMapTiles: widget.showMapTiles,
            onTap: _openMap,
          ),
        ),
      );
    }
    return AppSectionCard(
      child: Center(
        child: RunRouteSketch(points: _route, width: 260, height: 170),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final activity = _draft.activity;
    final showRoute = _points.length >= 2 || RunRouteSketch.hasShape(_route);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _isStationaryBike
                ? loc.stationaryBikeReviewTitle
                : loc.runReviewTitle,
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            RunReviewHero(
              activity: activity,
              distanceMeters: _reviewedDistanceMeters,
              headline: _isStationaryBike
                  ? loc.stationaryBikeReviewHeroHeadline
                  : loc.runReviewHeroHeadline,
              paceSecPerKm: _reviewedPace,
              speedKmh: _isStationaryBike
                  ? _reviewedSpeedKmh(activity.movingTimeSeconds)
                  : null,
              speedUnit: _isStationaryBike ? loc.stationaryBikeSpeedUnit : null,
              elevationGainMeters: activity.isRun && _elevation.hasData
                  ? _elevation.gainMeters
                  : null,
              route: _route,
            ),
            if (_needsManualDistance) ...[
              AppSectionHeader(
                _isStationaryBike
                    ? loc.stationaryBikeReviewDistanceSection
                    : loc.runReviewTreadmillSection,
              ),
              RunIndoorDistanceField(
                controller: _distanceController,
                label: _isStationaryBike
                    ? loc.stationaryBikeReviewDistanceLabel
                    : loc.runReviewTreadmillDistanceLabel,
                hint: _isStationaryBike
                    ? loc.stationaryBikeReviewDistanceHint
                    : loc.runReviewTreadmillDistanceHint,
              ),
            ],
            if (showRoute) ...[
              AppSectionHeader(loc.runReviewRoute),
              _routeSection(loc),
            ],
            // Pace only: the elevation profile lives on the run detail.
            if (_analytics.hasChart)
              RunDetailChartCard(
                analytics: _analytics,
                avgPaceSecPerKm: _reviewedPace,
                elevation: RunElevationProfile.empty,
                selectedDistance: _points.length >= 2
                    ? _selectedDistance
                    : null,
              ),
            if (_hasPlannedWorkout && _planWorkout != null) ...[
              AppSectionHeader(loc.runReviewPlanComparison),
              RunReviewPlanCard(
                workout: _planWorkout!,
                activity: activity,
                stepResults: _draft.stepResults,
                isTooShort: _isTooShort,
                completePlanned: _completePlannedWorkout,
                onCompletePlannedChanged: (value) =>
                    setState(() => _completePlannedWorkout = value),
              ),
            ],
            if (_draft.splits.isNotEmpty) ...[
              AppSectionHeader(loc.runReviewSplits),
              AppSectionCard(
                child: RunSplitsList(
                  splits: _draft.splits,
                  averagePaceSecPerKm: activity.avgPaceSecPerKm,
                  elevationGainByKm: _elevation.gainByKm,
                ),
              ),
            ],
            AppSectionHeader(loc.runReviewEffortTitle),
            RunEffortSelector(
              rpe: _rpe,
              onChanged: (value) => setState(() => _rpe = value),
            ),
            AppSectionHeader(loc.runReviewFeelingTitle),
            RunFeelingSelector(
              rating: _feelingRating,
              onChanged: (value) => setState(() => _feelingRating = value),
            ),
            AppSectionHeader(loc.runReviewDetailsTitle),
            AppSectionCard(
              child: Column(
                children: [
                  TextField(
                    controller: _titleController,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: loc.runDetailTitleLabel,
                      hintText: _titleHint(loc),
                      prefixIcon: const Icon(Icons.edit_outlined, size: 20),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _notesController,
                    textCapitalization: TextCapitalization.sentences,
                    minLines: 3,
                    maxLines: 6,
                    decoration: InputDecoration(
                      labelText: loc.runDetailNotes,
                      hintText: _isStationaryBike
                          ? loc.stationaryBikeReviewNotesHint
                          : loc.runReviewNotesHint,
                      alignLabelWithHint: true,
                    ),
                  ),
                ],
              ),
            ),
            if (!_isStationaryBike) ...[
              AppSectionHeader(loc.runReviewMeaningTitle),
              RunReviewMeaningCard(
                loading: _loading,
                insights: _insights,
                nextSession: _nextSession,
                // Indoor distance is typed after the insights were computed.
                weekMeters:
                    _insights.weekMeters +
                    (_reviewedDistanceMeters - activity.distanceMeters),
              ),
            ],
          ],
        ),
        bottomNavigationBar: _ReviewActionBar(
          saving: _saving,
          onDiscard: _discard,
          onSave: _save,
        ),
      ),
    );
  }

  double? _reviewedSpeedKmh(int movingSeconds) {
    final meters = _reviewedDistanceMeters;
    if (meters <= 0 || movingSeconds <= 0) return null;
    return (meters / 1000) / (movingSeconds / 3600);
  }
}

class _ReviewActionBar extends StatelessWidget {
  final bool saving;
  final VoidCallback onDiscard;
  final VoidCallback onSave;

  const _ReviewActionBar({
    required this.saving,
    required this.onDiscard,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: AppUi.divider(theme.colorScheme)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: OutlinedButton(
                    onPressed: saving ? null : onDiscard,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                      side: BorderSide(
                        color: theme.colorScheme.error.withValues(alpha: 0.5),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      loc.runReviewDiscard,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.fade,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: saving ? null : onSave,
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_rounded),
                    label: Text(
                      loc.runReviewSave,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.fade,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
