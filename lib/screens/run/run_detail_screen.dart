import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/models/run_track_point.dart';
import 'package:workout_notes/repositories/run_repository.dart';
import 'package:workout_notes/utils/run_formatters.dart';

class RunDetailScreen extends StatefulWidget {
  final String activityId;

  const RunDetailScreen({super.key, required this.activityId});

  @override
  State<RunDetailScreen> createState() => _RunDetailScreenState();
}

class _RunDetailScreenState extends State<RunDetailScreen> {
  final _repo = RunRepository();
  RunActivity? _activity;
  List<RunTrackPoint> _points = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final activity = await _repo.getActivity(widget.activityId);
    final points = activity == null
        ? <RunTrackPoint>[]
        : await _repo.getTrackPoints(widget.activityId);
    if (!mounted) return;
    setState(() {
      _activity = activity;
      _points = points;
      _loading = false;
    });
  }

  Future<void> _edit() async {
    final activity = _activity;
    if (activity == null) return;
    final loc = AppLocalizations.of(context)!;
    final titleController = TextEditingController(
      text: activity.title ?? loc.runDetailDefaultTitle,
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
              Text(loc.runDetailEdit, style: Theme.of(ctx).textTheme.titleLarge),
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
    final loc = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.runDetailDeleteConfirm),
        content: Text(loc.runDetailDeleteConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(loc.runDetailDelete),
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

  Widget _buildMap(ThemeData theme, List<LatLng> trail) {
    final bounds = _boundsFor(trail);
    final center = trail.isNotEmpty
        ? trail[trail.length ~/ 2]
        : const LatLng(-23.5505, -46.6333);

    return FlutterMap(
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
              Polyline(
                points: trail,
                color: theme.colorScheme.primary,
                strokeWidth: 4,
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

    return Scaffold(
      appBar: AppBar(
        title: Text(activity.title?.isNotEmpty == true
            ? activity.title!
            : loc.runDetailUntitled),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: loc.runDetailEdit,
            onPressed: _edit,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: loc.runDetailDelete,
            onPressed: _delete,
          ),
        ],
      ),
      body: ListView(
        children: [
          SizedBox(
            height: 280,
            child: _buildMap(theme, trail),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Text(
              dateLabel,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatChip(
                  label: loc.runRecordDistance,
                  value: RunFormatters.distanceWithUnit(activity.distanceMeters),
                ),
                _StatChip(
                  label: loc.runDetailElapsedTime,
                  value: RunFormatters.duration(activity.durationSeconds),
                ),
                _StatChip(
                  label: loc.runDetailMovingTime,
                  value: RunFormatters.duration(activity.movingTimeSeconds),
                ),
                _StatChip(
                  label: loc.runDetailAvgPace,
                  value: RunFormatters.paceWithUnit(activity.avgPaceSecPerKm),
                ),
                _StatChip(
                  label: loc.runDetailCalories,
                  value: '${activity.calories ?? 0} kcal',
                ),
              ],
            ),
          ),
          if (activity.notes?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Text(activity.notes!, style: theme.textTheme.bodyLarge),
            )
          else
            const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;

  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: (MediaQuery.sizeOf(context).width - 40) / 2,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
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
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
