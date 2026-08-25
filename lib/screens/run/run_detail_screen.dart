import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_achievement.dart';
import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/models/run_track_point.dart';
import 'package:workout_notes/models/run_workout_step.dart';
import 'package:workout_notes/models/scheduled_run.dart';
import 'package:workout_notes/repositories/run_plan_repository.dart';
import 'package:workout_notes/repositories/run_repository.dart';
import 'package:workout_notes/screens/run/run_replay_screen.dart';
import 'package:workout_notes/widgets/run/run_plan_ui.dart';
import 'package:workout_notes/utils/run_achievement_engine.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/utils/run_pace_analytics.dart';
import 'package:workout_notes/utils/run_route_pace_style.dart';
import 'package:workout_notes/widgets/run/run_achievements_section.dart';
import 'package:workout_notes/widgets/run/run_pace_chart.dart';
import 'package:workout_notes/widgets/run/run_splits_list.dart';

class RunDetailScreen extends StatefulWidget {
  final String activityId;

  const RunDetailScreen({super.key, required this.activityId});

  @override
  State<RunDetailScreen> createState() => _RunDetailScreenState();
}

class _RunDetailScreenState extends State<RunDetailScreen> {
  final _repo = RunRepository();
  final _planRepo = RunPlanRepository();
  RunActivity? _activity;
  List<RunActivityStep> _planSteps = const [];
  List<RunTrackPoint> _points = [];
  List<RunAchievementPlacement> _medals = [];
  RunPaceAnalytics _analytics = const RunPaceAnalytics(
    samples: [],
    splits: [],
    avgPaceSecPerKm: null,
    bestSplitPaceSecPerKm: null,
  );
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final activity =
        await _repo.ensureEffortMetrics(widget.activityId) ??
        await _repo.getActivity(widget.activityId);
    final planSteps = await _planRepo.getActivitySteps(widget.activityId);
    final points = activity == null
        ? <RunTrackPoint>[]
        : await _repo.getTrackPoints(widget.activityId);
    final analytics = activity == null
        ? const RunPaceAnalytics(
            samples: [],
            splits: [],
            avgPaceSecPerKm: null,
            bestSplitPaceSecPerKm: null,
          )
        : RunPaceAnalytics.fromTrackPoints(
            points,
            activityAvgPaceSecPerKm: activity.avgPaceSecPerKm,
          );
    final all = await _repo.listActivities(limit: 500);
    final board = RunAchievementEngine.build(all);
    if (!mounted) return;
    setState(() {
      _activity = activity;
      _points = points;
      _planSteps = planSteps;
      _analytics = analytics;
      _medals = activity == null || !activity.isRun
          ? const []
          : board.forActivity(activity.id);
      _loading = false;
    });
  }

  Future<void> _edit() async {
    final activity = _activity;
    if (activity == null) return;
    final loc = AppLocalizations.of(context)!;
    final titleController = TextEditingController(
      text:
          activity.title ??
          (activity.isStationaryBike
              ? loc.stationaryBikeDetailDefaultTitle
              : loc.runDetailDefaultTitle),
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

    if (saved == true) {
      await _repo.updateActivityMeta(
        id: activity.id,
        title: titleController.text.trim(),
        notes: notesController.text.trim(),
      );
      titleController.dispose();
      notesController.dispose();
      await _load();
    } else {
      titleController.dispose();
      notesController.dispose();
    }
  }

  Future<void> _delete() async {
    final activity = _activity;
    if (activity == null) return;
    final loc = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          activity.isStationaryBike
              ? loc.stationaryBikeDeleteConfirm
              : loc.runDetailDeleteConfirm,
        ),
        content: Text(
          activity.isStationaryBike
              ? loc.stationaryBikeDeleteConfirmBody
              : loc.runDetailDeleteConfirmBody,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              activity.isStationaryBike
                  ? loc.stationaryBikeDelete
                  : loc.runDetailDelete,
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _repo.deleteActivity(widget.activityId);
    if (mounted) Navigator.pop(context, true);
  }

  /// Returns fit bounds only when the trail has a usable geographic span.
  /// Degenerate bounds (0–1 points or identical coords) make flutter_map
  /// compute Infinity/NaN zoom and crash TileLayer.
  LatLngBounds? _boundsFor(List<LatLng> points) {
    if (points.length < 2) return null;
    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    // ~1e-4 deg ≈ 11 m; anything smaller is GPS jitter / a single spot.
    if ((maxLat - minLat) < 1e-4 && (maxLng - minLng) < 1e-4) {
      return null;
    }
    return LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng));
  }

  /// One planned-vs-actual row. The pace delta is the number that matters on an
  /// interval session: did rep 5 hold the target of rep 1?
  Widget _planStepRow(
    ThemeData theme,
    AppLocalizations loc,
    RunActivityStep step,
  ) {
    final role = RunStepRole.fromString(step.role);
    final color = RunPlanUi.roleColor(theme.colorScheme, role);
    final planned = step.plannedValue == null
        ? '—'
        : step.plannedMetric == 'time'
        ? RunPlanUi.durationLabel(step.plannedValue!)
        : RunPlanUi.distanceLabel(step.plannedValue!.toDouble());
    final actual = step.plannedMetric == 'time'
        ? RunPlanUi.durationLabel(step.actualDurationSeconds ?? 0)
        : RunPlanUi.distanceLabel(step.actualDistanceMeters ?? 0);
    final delta = step.paceDeltaSecPerKm;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 30,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  role == RunStepRole.work
                      ? '${RunPlanUi.roleLabel(loc, role)} ${step.repIndex}'
                      : RunPlanUi.roleLabel(loc, role),
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${loc.runDetailPlanStepPlanned} $planned · '
                  '${loc.runDetailPlanStepActual} $actual',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                RunFormatters.paceWithUnit(step.actualPaceSecPerKm),
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (delta != null)
                Text(
                  // Negative delta means faster than planned.
                  '${delta <= 0 ? '−' : '+'}'
                  '${RunPlanUi.paceLabel(delta.abs())}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: delta <= 0
                        ? theme.colorScheme.primary
                        : theme.colorScheme.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openReplay() async {
    final activity = _activity;
    if (activity == null || _points.length < 2) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => RunReplayScreen(activity: activity, points: _points),
      ),
    );
  }

  Widget _buildMap(ThemeData theme, AppLocalizations loc, List<LatLng> trail) {
    final bounds = _boundsFor(trail);
    final averagePace =
        _analytics.avgPaceSecPerKm ?? _activity?.avgPaceSecPerKm;
    final segmentPaces = RunRoutePaceStyle.segmentPaces(
      _points,
      averagePaceSecPerKm: averagePace,
    );
    final center = trail.isNotEmpty
        ? trail[trail.length ~/ 2]
        : const LatLng(-23.5505, -46.6333);

    return Stack(
      fit: StackFit.expand,
      children: [
        FlutterMap(
          options: MapOptions(
            initialCenter: center,
            initialZoom: bounds == null ? 15 : 14,
            initialCameraFit: bounds == null
                ? null
                : CameraFit.bounds(
                    bounds: bounds,
                    padding: const EdgeInsets.all(28),
                    maxZoom: 17,
                    minZoom: 3,
                  ),
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.workoutnotes.workout_notes',
            ),
            if (trail.length >= 2)
              PolylineLayer(
                polylines: [
                  for (var index = 0; index < trail.length - 1; index++)
                    Polyline(
                      points: [trail[index], trail[index + 1]],
                      color: RunRoutePaceStyle.colorForPace(
                        paceSecPerKm: segmentPaces[index],
                        averagePaceSecPerKm: averagePace,
                      ),
                      strokeWidth: RunRoutePaceStyle.routeStrokeWidth,
                      strokeCap: StrokeCap.butt,
                    ),
                ],
              ),
            if (trail.length == 1)
              MarkerLayer(
                markers: [
                  Marker(
                    point: trail.first,
                    width: 18,
                    height: 18,
                    child: Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
        if (trail.length >= 2)
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
    );
  }

  Widget _sectionCard({required Widget child}) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }

  Widget _sectionTitle(String text) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    );
  }

  Widget _buildStationaryBikeHero(ThemeData theme, AppLocalizations loc) {
    return Container(
      height: 176,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.secondaryContainer,
            theme.colorScheme.surfaceContainerLow,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.pedal_bike_rounded,
            size: 62,
            color: theme.colorScheme.secondary,
          ),
          const SizedBox(height: 10),
          Text(
            loc.stationaryBikeIndoorHeadline,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            loc.cardioActivityStationaryBikeSubtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final activity = _activity;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(loc.runDetailTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (activity == null) {
      return Scaffold(
        appBar: AppBar(title: Text(loc.runDetailTitle)),
        body: Center(child: Text(loc.runHistoryEmptyTitle)),
      );
    }

    final trail = _points.map((p) => LatLng(p.lat, p.lng)).toList();
    final dateLabel = DateFormat.yMMMd(
      Localizations.localeOf(context).toString(),
    ).add_Hm().format(activity.startedAt.toLocal());
    final avgPace = _analytics.avgPaceSecPerKm ?? activity.avgPaceSecPerKm;
    final bestPace =
        _analytics.bestSplitPaceSecPerKm ?? activity.maxPaceSecPerKm;
    final averageSpeed = activity.averageSpeedKmh;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          activity.title?.isNotEmpty == true
              ? activity.title!
              : activity.isStationaryBike
              ? loc.stationaryBikeDetailUntitled
              : loc.runDetailUntitled,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: loc.runDetailEdit,
            onPressed: _edit,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: activity.isStationaryBike
                ? loc.stationaryBikeDelete
                : loc.runDetailDelete,
            onPressed: _delete,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          if (activity.isStationaryBike)
            _buildStationaryBikeHero(theme, loc)
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(height: 240, child: _buildMap(theme, loc, trail)),
            ),
          const SizedBox(height: 12),
          _sectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      dateLabel,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                if (activity.notes?.isNotEmpty == true) ...[
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.notes_rounded,
                        size: 17,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          activity.notes!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (activity.feelingRating != null || activity.rpe != null) ...[
                  const SizedBox(height: 12),
                  _RunFeedbackStrip(
                    feelingRating: activity.feelingRating,
                    rpe: activity.rpe,
                    feelingLabel: loc.runDetailFeeling,
                    rpeLabel: loc.runDetailRpe,
                  ),
                ],
                const SizedBox(height: 12),
                Divider(
                  height: 1,
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.55,
                  ),
                ),
                const SizedBox(height: 12),
                _MetricsGrid(
                  items: [
                    _MetricItem(
                      icon: Icons.route_outlined,
                      label: loc.runRecordDistance,
                      value: RunFormatters.distanceWithUnit(
                        activity.distanceMeters,
                      ),
                    ),
                    _MetricItem(
                      icon: Icons.speed_rounded,
                      label: activity.isStationaryBike
                          ? loc.stationaryBikeAverageSpeed
                          : loc.runDetailAvgPace,
                      value: activity.isStationaryBike
                          ? '${averageSpeed?.toStringAsFixed(1) ?? '--'} ${loc.stationaryBikeSpeedUnit}'
                          : RunFormatters.paceWithUnit(avgPace),
                    ),
                    _MetricItem(
                      icon: Icons.timer_outlined,
                      label: loc.runDetailMovingTime,
                      value: RunFormatters.duration(activity.movingTimeSeconds),
                    ),
                    _MetricItem(
                      icon: Icons.schedule_rounded,
                      label: loc.runDetailElapsedTime,
                      value: RunFormatters.duration(activity.durationSeconds),
                    ),
                    _MetricItem(
                      icon: Icons.local_fire_department_outlined,
                      label: loc.runDetailCalories,
                      value: '${activity.calories ?? 0} kcal',
                    ),
                    if (activity.isRun && bestPace != null)
                      _MetricItem(
                        icon: Icons.bolt_rounded,
                        label: loc.runDetailBestPace,
                        value: RunFormatters.paceWithUnit(bestPace),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (activity.isRun && _medals.isNotEmpty) ...[
            const SizedBox(height: 12),
            _sectionCard(
              child: RunActivityAchievementsBlock(placements: _medals),
            ),
          ],
          if (activity.isRun && _analytics.hasChart) ...[
            const SizedBox(height: 12),
            _sectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _sectionTitle(loc.runDetailPaceSection),
                  const SizedBox(height: 12),
                  RunPaceChart(
                    samples: _analytics.samples,
                    avgPaceSecPerKm: avgPace,
                    emptyLabel: loc.runDetailPaceChartEmpty,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _SummaryTile(
                          label: loc.runDetailAvgPace,
                          value: RunFormatters.paceWithUnit(avgPace),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _SummaryTile(
                          label: loc.runDetailBestPace,
                          value: RunFormatters.paceWithUnit(bestPace),
                          highlight: true,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          if (activity.isRun && _planSteps.isNotEmpty) ...[
            const SizedBox(height: 12),
            _sectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _sectionTitle(loc.runDetailPlanComparison),
                  const SizedBox(height: 8),
                  for (final step in _planSteps) _planStepRow(theme, loc, step),
                ],
              ),
            ),
          ],
          if (activity.isRun && _analytics.hasSplits) ...[
            const SizedBox(height: 12),
            _sectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _sectionTitle(loc.runDetailSplitsSection),
                  const SizedBox(height: 8),
                  RunSplitsList(splits: _analytics.splits),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RunFeedbackStrip extends StatelessWidget {
  final int? feelingRating;
  final double? rpe;
  final String feelingLabel;
  final String rpeLabel;

  const _RunFeedbackStrip({
    required this.feelingRating,
    required this.rpe,
    required this.feelingLabel,
    required this.rpeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rating = feelingRating?.clamp(1, 5);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.14),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            if (rating != null)
              Expanded(
                child: Semantics(
                  label: '$feelingLabel: $rating/5',
                  child: ExcludeSemantics(
                    child: _FeedbackValue(
                      label: feelingLabel,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var star = 1; star <= 5; star++)
                            Icon(
                              star <= rating
                                  ? Icons.star_rounded
                                  : Icons.star_border_rounded,
                              size: 17,
                              color: star <= rating
                                  ? Colors.amber.shade700
                                  : theme.colorScheme.outline,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (rating != null && rpe != null)
              VerticalDivider(
                width: 18,
                thickness: 1,
                color: theme.colorScheme.outlineVariant,
              ),
            if (rpe != null)
              Expanded(
                child: Semantics(
                  label: '$rpeLabel: ${rpe!.round()}/10',
                  child: ExcludeSemantics(
                    child: _FeedbackValue(
                      label: rpeLabel,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.monitor_heart_outlined,
                            size: 17,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '${rpe!.round()}/10',
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
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
}

class _FeedbackValue extends StatelessWidget {
  final String label;
  final Widget child;

  const _FeedbackValue({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

class _MetricItem {
  final IconData icon;
  final String label;
  final String value;

  const _MetricItem({
    required this.icon,
    required this.label,
    required this.value,
  });
}

class _MetricsGrid extends StatelessWidget {
  final List<_MetricItem> items;

  const _MetricsGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final colWidth = (constraints.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in items)
              SizedBox(
                width: colWidth,
                child: _StatChip(
                  icon: item.icon,
                  label: item.label,
                  value: item.value,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.55,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 17, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;

  const _SummaryTile({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = highlight
        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.55)
        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
