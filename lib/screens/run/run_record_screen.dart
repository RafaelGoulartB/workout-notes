import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_tracking_state.dart';
import 'package:workout_notes/screens/run/run_detail_screen.dart';
import 'package:workout_notes/services/run_tracking_service.dart';
import 'package:workout_notes/utils/run_formatters.dart';

class RunRecordScreen extends StatefulWidget {
  const RunRecordScreen({super.key});

  @override
  State<RunRecordScreen> createState() => _RunRecordScreenState();
}

class _RunRecordScreenState extends State<RunRecordScreen> {
  final _service = RunTrackingService.instance;
  final _mapController = MapController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onChanged);
    _service.initialize();
  }

  @override
  void dispose() {
    _service.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
    final state = _service.state;
    if (state.lat != null && state.lng != null) {
      _mapController.move(LatLng(state.lat!, state.lng!), _mapController.camera.zoom);
    }
  }

  Future<void> _ensurePermissionAndStart() async {
    final loc = AppLocalizations.of(context)!;
    if (!_service.isSupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.runRecordUnsupported)),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final ok = await _service.start();
      if (!ok && mounted) {
        final msg = _service.state.errorMessage ?? loc.runRecordPermissionNeeded;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish() async {
    final loc = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.runRecordFinishConfirm),
        content: Text(loc.runRecordFinishConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(loc.runRecordFinish),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final activity = await _service.stop();
      if (!mounted) return;
      if (activity != null) {
        await Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => RunDetailScreen(activityId: activity.id),
          ),
        );
      } else {
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _discard() async {
    final loc = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.runRecordDiscardConfirm),
        content: Text(loc.runRecordDiscardConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(loc.runRecordDiscard),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _service.discard();
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final state = _service.state;
    final center = state.lat != null && state.lng != null
        ? LatLng(state.lat!, state.lng!)
        : const LatLng(-23.5505, -46.6333);
    final trail = state.trail
        .map((p) => LatLng(p.lat, p.lng))
        .toList(growable: false);

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: 16,
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
                      strokeWidth: 5,
                    ),
                  ],
                ),
              if (state.lat != null && state.lng != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(state.lat!, state.lng!),
                      width: 22,
                      height: 22,
                      child: Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Material(
                    color: theme.colorScheme.surface.withValues(alpha: 0.92),
                    shape: const CircleBorder(),
                    child: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: state.isActive
                          ? _discard
                          : () => Navigator.pop(context),
                    ),
                  ),
                  const Spacer(),
                  if (state.hasWeakGps ||
                      (state.isRecording && state.lat == null))
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        state.lat == null
                            ? loc.runRecordWaitingGps
                            : loc.runRecordWeakGps,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _MetricsPanel(
              state: state,
              busy: _busy,
              onStart: _ensurePermissionAndStart,
              onPause: () => _service.pause(),
              onResume: () => _service.resume(),
              onFinish: _finish,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricsPanel extends StatelessWidget {
  final RunTrackingState state;
  final bool busy;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onFinish;

  const _MetricsPanel({
    required this.state,
    required this.busy,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onFinish,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final pace = state.currentPaceSecPerKm ??
        (state.distanceMeters > 0
            ? state.movingTimeSeconds / (state.distanceMeters / 1000.0)
            : null);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.96),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!state.locationGranted && state.supported) ...[
              Text(
                loc.runRecordPermissionNeeded,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  child: _Metric(
                    label: loc.runRecordTime,
                    value: RunFormatters.duration(state.durationSeconds),
                  ),
                ),
                Expanded(
                  child: _Metric(
                    label: loc.runRecordDistance,
                    value: RunFormatters.distanceKm(state.distanceMeters),
                    unit: 'km',
                  ),
                ),
                Expanded(
                  child: _Metric(
                    label: loc.runRecordPace,
                    value: RunFormatters.pace(pace),
                    unit: loc.runRecordPaceUnit,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (busy)
              const CircularProgressIndicator()
            else if (!state.isActive)
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: onStart,
                  child: Text(loc.runRecordStart),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: state.isPaused ? onResume : onPause,
                      child: Text(
                        state.isPaused
                            ? loc.runRecordResume
                            : loc.runRecordPause,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: onFinish,
                      child: Text(loc.runRecordFinish),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;

  const _Metric({required this.label, required this.value, this.unit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            letterSpacing: 1.1,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (unit != null)
          Text(
            unit!,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}
