import 'package:flutter/material.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_achievement.dart';
import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/models/run_gear.dart';
import 'package:workout_notes/models/run_lap.dart';
import 'package:workout_notes/models/run_split.dart';
import 'package:workout_notes/models/run_track_point.dart';
import 'package:workout_notes/models/scheduled_run.dart';
import 'package:workout_notes/repositories/run_plan_repository.dart';
import 'package:workout_notes/repositories/run_repository.dart';
import 'package:workout_notes/screens/run/run_replay_screen.dart';
import 'package:workout_notes/screens/run/run_route_map_screen.dart';
import 'package:workout_notes/services/run_export_service.dart';
import 'package:workout_notes/utils/run_achievement_engine.dart';
import 'package:workout_notes/utils/run_elevation_analytics.dart';
import 'package:workout_notes/utils/run_pace_analytics.dart';
import 'package:workout_notes/widgets/run/run_achievements_section.dart';
import 'package:workout_notes/widgets/run/run_activity_step_row.dart';
import 'package:workout_notes/widgets/run/run_detail_chart_card.dart';
import 'package:workout_notes/widgets/run/run_detail_widgets.dart';
import 'package:workout_notes/widgets/run/run_gear_picker.dart';
import 'package:workout_notes/widgets/run/run_gear_row.dart';
import 'package:workout_notes/widgets/run/run_route_map.dart';
import 'package:workout_notes/widgets/run/run_share_card.dart';
import 'package:workout_notes/widgets/run/run_splits_list.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

enum _MenuAction { exportGpx, delete }

class RunDetailScreen extends StatefulWidget {
  final String activityId;

  /// Draws OpenStreetMap tiles under the route; tests turn this off.
  final bool showMapTiles;

  const RunDetailScreen({
    super.key,
    required this.activityId,
    this.showMapTiles = true,
  });

  @override
  State<RunDetailScreen> createState() => _RunDetailScreenState();
}

class _RunDetailScreenState extends State<RunDetailScreen> {
  final _repo = RunRepository();
  final _planRepo = RunPlanRepository();
  final _exportService = RunExportService();

  /// Distance highlighted by the charts, followed by the map marker.
  final _selectedDistance = ValueNotifier<double?>(null);

  RunActivity? _activity;
  List<RunActivityStep> _planSteps = const [];
  List<RunTrackPoint> _points = const [];
  List<RunLap> _laps = const [];
  List<RunAchievementPlacement> _medals = const [];
  RunGearUsage? _gear;
  RunPaceAnalytics _analytics = const RunPaceAnalytics(
    samples: [],
    splits: [],
    avgPaceSecPerKm: null,
    bestSplitPaceSecPerKm: null,
  );
  RunElevationProfile _elevation = RunElevationProfile.empty;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _selectedDistance.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final activity =
        await _repo.ensureEffortMetrics(widget.activityId) ??
        await _repo.getActivity(widget.activityId);
    if (activity == null) {
      if (!mounted) return;
      setState(() {
        _activity = null;
        _loading = false;
      });
      return;
    }

    final gearRepo = DatabaseHelper.instance.runGearRepo;
    final results = await Future.wait<Object?>([
      _planRepo.getActivitySteps(widget.activityId),
      _repo.getTrackPoints(widget.activityId),
      _repo.getSplits(widget.activityId),
      gearRepo.getLaps(widget.activityId),
      activity.gearId == null
          ? Future<RunGearUsage?>.value(null)
          : gearRepo.getUsage(activity.gearId!),
    ]);
    final planSteps = results[0] as List<RunActivityStep>;
    final points = results[1] as List<RunTrackPoint>;
    final storedSplits = results[2] as List<RunSplit>;
    final laps = results[3] as List<RunLap>;
    final gear = results[4] as RunGearUsage?;

    final profile = RunTrackProfile.fromPoints(points);
    final derived = RunPaceAnalytics.fromTrackPoints(
      points,
      activityAvgPaceSecPerKm: activity.avgPaceSecPerKm,
      profile: profile,
    );
    final analytics = storedSplits.isEmpty
        ? derived
        : RunPaceAnalytics(
            samples: derived.samples,
            splits: storedSplits,
            avgPaceSecPerKm: derived.avgPaceSecPerKm,
            bestSplitPaceSecPerKm:
                activity.bestSplitPaceSecPerKm ?? derived.bestSplitPaceSecPerKm,
          );

    var medals = const <RunAchievementPlacement>[];
    if (activity.isRun) {
      final ranking = await _repo.listActivitiesForRanking();
      medals = RunAchievementEngine.build(ranking).forActivity(activity.id);
    }
    if (!mounted) return;
    setState(() {
      _activity = activity;
      _points = points;
      _planSteps = planSteps;
      _laps = laps;
      _gear = gear;
      _analytics = analytics;
      _elevation = activity.isRun
          ? RunElevationProfile.fromTrackPoints(points, profile: profile)
          : RunElevationProfile.empty;
      _medals = medals;
      _loading = false;
    });
  }

  // ---------------------------------------------------------------- actions

  Future<void> _edit() async {
    final activity = _activity;
    if (activity == null) return;
    final loc = AppLocalizations.of(context)!;
    final titleController = TextEditingController(
      text: activity.title ?? runDefaultTitle(loc, activity),
    );
    final notesController = TextEditingController(text: activity.notes ?? '');

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.viewInsetsOf(ctx).bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                loc.runDetailEdit,
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: titleController,
                decoration: InputDecoration(labelText: loc.runDetailTitleLabel),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesController,
                decoration: InputDecoration(labelText: loc.runDetailNotes),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(loc.runDetailSave),
              ),
            ],
          ),
        );
      },
    );

    final title = titleController.text.trim();
    final notes = notesController.text.trim();
    titleController.dispose();
    notesController.dispose();
    if (saved != true || !mounted) return;
    await _repo.updateActivityMeta(id: activity.id, title: title, notes: notes);
    await _load();
  }

  Future<void> _delete() async {
    final activity = _activity;
    if (activity == null) return;
    final loc = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: activity.isStationaryBike
              ? loc.stationaryBikeDeleteConfirm
              : loc.runDetailDeleteConfirm,
      message: activity.isStationaryBike
              ? loc.stationaryBikeDeleteConfirmBody
              : loc.runDetailDeleteConfirmBody,
      confirmLabel: activity.isStationaryBike
                  ? loc.stationaryBikeDelete
                  : loc.runDetailDelete,
      cancelLabel: MaterialLocalizations.of(context).cancelButtonLabel,
    );
    if (confirmed != true || !mounted) return;
    await _repo.deleteActivity(widget.activityId);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _share() async {
    final activity = _activity;
    if (activity == null) return;
    await showRunShareSheet(
      context,
      activity: activity,
      medals: _medals,
      exportService: _exportService,
    );
  }

  Future<void> _exportGpx() async {
    final activity = _activity;
    if (activity == null || _points.length < 2) return;
    final loc = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _exportService.shareGpx(activity: activity, points: _points);
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(loc.runDetailExportError)));
    }
  }

  Future<void> _pickGear() async {
    final activity = _activity;
    if (activity == null) return;
    final choice = await showRunGearPicker(
      context,
      selectedGearId: activity.gearId,
    );
    if (choice == null || !mounted) return;
    await DatabaseHelper.instance.runGearRepo.setActivityGear(
      activity.id,
      choice.gear?.id,
    );
    await _load();
  }

  Future<void> _openReplay() async {
    final activity = _activity;
    if (activity == null || _points.length < 2) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => RunReplayScreen(
          activity: activity,
          points: _points,
          showMapTiles: widget.showMapTiles,
        ),
      ),
    );
  }

  Future<void> _openMap() async {
    final activity = _activity;
    if (activity == null || _points.length < 2) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => RunRouteMapScreen(
          title: activity.title ?? '',
          points: _points,
          averagePaceSecPerKm: _avgPace,
          showMapTiles: widget.showMapTiles,
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ build

  double? get _avgPace {
    final activity = _activity;
    if (activity == null) return null;
    return _analytics.avgPaceSecPerKm ??
        activity.avgPaceSecPerKm ??
        (activity.isRunning
            ? RunPaceAnalytics.paceSecPerKm(
                activity.distanceMeters,
                activity.movingTimeSeconds,
              )
            : null);
  }

  Widget _buildMap(RunActivity activity, AppLocalizations loc) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppUi.cardRadius),
      child: SizedBox(
        height: 260,
        child: Stack(
          fit: StackFit.expand,
          children: [
            RunRouteMap(
              points: _points,
              averagePaceSecPerKm: _avgPace,
              selectedDistance: _selectedDistance,
              showMapTiles: widget.showMapTiles,
              onTap: _openMap,
            ),
            Positioned(
              right: 10,
              top: 10,
              child: Semantics(
                button: true,
                label: loc.runDetailMapFullscreen,
                child: Material(
                  color: theme.colorScheme.surface.withValues(alpha: 0.9),
                  shape: const CircleBorder(),
                  child: InkWell(
                    key: const ValueKey('run-detail-fullscreen-button'),
                    customBorder: const CircleBorder(),
                    onTap: _openMap,
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.fullscreen_rounded, size: 22),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 12,
              bottom: 12,
              child: Semantics(
                button: true,
                label: loc.runReplayPlay,
                child: Material(
                  color: theme.colorScheme.primary.withValues(alpha: 0.92),
                  shape: const CircleBorder(),
                  elevation: 6,
                  child: InkWell(
                    key: const ValueKey('run-detail-replay-button'),
                    customBorder: const CircleBorder(),
                    onTap: _openReplay,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Icon(
                        Icons.play_arrow_rounded,
                        size: 26,
                        color: theme.colorScheme.onPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final activity = _activity;

    if (_loading && activity == null) {
      return Scaffold(
        appBar: AppBar(title: Text(loc.runDetailTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (activity == null) {
      return Scaffold(
        appBar: AppBar(title: Text(loc.runDetailTitle)),
        body: Center(child: Text(loc.runDetailNotFound)),
      );
    }

    final hasRoute = activity.isRun && _points.length >= 2;
    final avgPace = _avgPace;
    // Stored summary first so the numbers agree with the history list.
    final gain = activity.elevationGainMeters;
    final loss = activity.elevationLossMeters;
    final efforts = activity.isRun
        ? RunBestEffort.fromActivity(activity)
        : const <RunBestEffort>[];

    return Scaffold(
      // The hero card below carries the run's name and date, so the bar only
      // holds actions (a long "Run details" title was truncated anyway).
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: loc.runDetailEdit,
            onPressed: _edit,
          ),
          IconButton(
            icon: const Icon(Icons.ios_share_rounded),
            tooltip: loc.runShareAction,
            onPressed: _share,
          ),
          PopupMenuButton<_MenuAction>(
            tooltip: loc.runDetailMoreActions,
            onSelected: (action) => switch (action) {
              _MenuAction.exportGpx => _exportGpx(),
              _MenuAction.delete => _delete(),
            },
            itemBuilder: (context) => [
              if (hasRoute)
                PopupMenuItem(
                  value: _MenuAction.exportGpx,
                  child: Text(loc.runDetailExportGpx),
                ),
              PopupMenuItem(
                value: _MenuAction.delete,
                child: Text(
                  activity.isStationaryBike
                      ? loc.stationaryBikeDelete
                      : loc.runDetailDelete,
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          if (activity.isIndoor)
            RunIndoorBanner(activity: activity)
          else if (hasRoute)
            _buildMap(activity, loc),
          if (activity.isIndoor || hasRoute) const SizedBox(height: 12),
          RunDetailHero(
            activity: activity,
            avgPaceSecPerKm: avgPace,
            fastestKmPaceSecPerKm: _analytics.bestSplitPaceSecPerKm,
            elevationGainMeters:
                gain ?? (_elevation.hasData ? _elevation.gainMeters : null),
            elevationLossMeters: gain != null
                ? loss
                : (_elevation.hasData ? _elevation.lossMeters : null),
          ),
          if (activity.isRunning) ...[
            const SizedBox(height: 12),
            RunGearRow(usage: _gear, onTap: _pickGear),
          ],
          if (activity.isRun && _medals.isNotEmpty) ...[
            const SizedBox(height: 12),
            AppSectionCard(
              child: RunActivityAchievementsBlock(placements: _medals),
            ),
          ],
          if (activity.isRun && (_analytics.hasChart || _elevation.hasData))
            RunDetailChartCard(
              analytics: _analytics,
              avgPaceSecPerKm: avgPace,
              elevation: _elevation,
              gainMeters: gain,
              lossMeters: loss,
              selectedDistance: hasRoute ? _selectedDistance : null,
            ),
          if (activity.isRunning && _planSteps.isNotEmpty) ...[
            AppSectionHeader(
              AppLocalizations.of(context)!.runDetailPlanComparison,
            ),
            AppSectionCard(
              child: AppDividedList(
                children: [
                  for (final step in _planSteps) RunActivityStepRow(step: step),
                ],
              ),
            ),
          ],
          if (activity.isRun && _analytics.hasSplits) ...[
            AppSectionHeader(loc.runDetailSplitsSection),
            AppSectionCard(
              child: RunSplitsList(
                splits: _analytics.splits,
                averagePaceSecPerKm: avgPace,
                elevationGainByKm: _elevation.gainByKm,
              ),
            ),
          ],
          if (_laps.isNotEmpty) ...[
            AppSectionHeader(loc.runDetailLapsSection),
            AppSectionCard(child: RunLapsList(laps: _laps)),
          ],
          if (efforts.isNotEmpty) ...[
            AppSectionHeader(loc.runDetailEffortsSection),
            RunBestEffortsCard(efforts: efforts, medals: _medals),
          ],
        ],
      ),
    );
  }
}
