import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_session_goal.dart';
import 'package:workout_notes/models/run_split.dart';
import 'package:workout_notes/models/run_tracking_state.dart';
import 'package:workout_notes/models/run_voice_settings.dart';
import 'package:workout_notes/screens/run/run_detail_screen.dart';
import 'package:workout_notes/screens/run/run_voice_settings_screen.dart';
import 'package:workout_notes/services/run_interval_engine.dart';
import 'package:workout_notes/services/run_tracking_service.dart';
import 'package:workout_notes/services/run_voice_coach.dart';
import 'package:workout_notes/utils/run_formatters.dart';

class RunRecordScreen extends StatefulWidget {
  const RunRecordScreen({super.key});

  @override
  State<RunRecordScreen> createState() => _RunRecordScreenState();
}

class _RunRecordScreenState extends State<RunRecordScreen> {
  final _service = RunTrackingService.instance;
  final _mapController = MapController();
  final _coach = RunVoiceCoach();
  bool _busy = false;
  bool _sheetExpanded = false;
  bool _intervalsOn = false;
  RunSessionGoal _goal = const RunSessionGoal.defaults();

  @override
  void initState() {
    super.initState();
    _service.addListener(_onChanged);
    _coach.addListener(_onCoachChanged);
    _service.initialize();
    _prepareCoach();
  }

  Future<void> _prepareCoach() async {
    await _coach.prepare();
    if (!mounted) return;
    setState(() => _intervalsOn = _coach.intervalsOn);
  }

  @override
  void dispose() {
    _service.removeListener(_onChanged);
    _coach.removeListener(_onCoachChanged);
    _coach.endSession();
    super.dispose();
  }

  void _onCoachChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
    final state = _service.state;
    if (state.lat != null && state.lng != null) {
      _mapController.move(LatLng(state.lat!, state.lng!), _mapController.camera.zoom);
    }
    _coach.onTrackingUpdate(state);
  }

  Future<void> _openVoiceSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RunVoiceSettingsScreen()),
    );
    await _coach.reloadSettings();
    if (!mounted) return;
    if (!_service.state.isActive) {
      setState(() => _intervalsOn = _coach.settings.intervalsEnabledByDefault);
    }
  }

  Future<void> _beginVoiceSession({bool debugSim = false}) async {
    await _coach.beginSession(
      intervalsOn: _intervalsOn,
      goal: _goal,
      bypassHeadphonesGate: debugSim,
    );
  }

  void _toggleIntervals(bool value) {
    setState(() => _intervalsOn = value);
    _coach.setIntervalsOn(value);
  }

  void _setGoal(RunSessionGoal goal) {
    setState(() => _goal = goal);
    _coach.setGoal(goal);
  }

  Future<void> _startDebugSimulation() async {
    setState(() => _busy = true);
    try {
      var startLat = -23.5505;
      var startLng = -46.6333;
      try {
        startLat = _mapController.camera.center.latitude;
        startLng = _mapController.camera.center.longitude;
      } catch (_) {
        // Map not ready yet — fall back to default coords.
      }
      final ok = await _service.startDebugSimulation(
        startLat: startLat,
        startLng: startLng,
      );
      if (ok) {
        await _beginVoiceSession(debugSim: true);
        await _coach.onTrackingUpdate(_service.state);
        if (mounted) {
          final loc = AppLocalizations.of(context)!;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(loc.runVoiceDebugSimHint)),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
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
      } else if (ok) {
        await _beginVoiceSession();
        await _coach.onTrackingUpdate(_service.state);
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
      await _coach.endSession();
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
      await _coach.endSession();
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
    final interval = _coach.intervalSnapshot;
    final goalSnap = _coach.goalSnapshotFor(state);

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
                  Material(
                    color: theme.colorScheme.surface.withValues(alpha: 0.92),
                    shape: const CircleBorder(),
                    child: IconButton(
                      icon: const Icon(Icons.record_voice_over_outlined),
                      tooltip: loc.runRecordVoiceSettings,
                      onPressed: _openVoiceSettings,
                    ),
                  ),
                  if (_service.isDebugSimulating)
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.tertiaryContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        loc.runRecordDebugSimulating,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onTertiaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  if (state.hasWeakGps ||
                      (state.isRecording &&
                          state.lat == null &&
                          !_service.isDebugSimulating))
                    Container(
                      margin: const EdgeInsets.only(left: 8),
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
          NotificationListener<DraggableScrollableNotification>(
            onNotification: (notification) {
              final expanded = notification.extent >= 0.55;
              if (expanded != _sheetExpanded && mounted) {
                setState(() => _sheetExpanded = expanded);
              }
              return false;
            },
            child: Builder(
              builder: (context) {
                final hasSplitSummary = state.splits.isNotEmpty;
                final showDebug = kDebugMode &&
                    !state.isActive &&
                    _service.canDebugSimulate;
                final collapsedSize = hasSplitSummary
                    ? 0.52
                    : (showDebug ? 0.46 : 0.42);
                return DraggableScrollableSheet(
                  key: ValueKey('run-sheet-$collapsedSize'),
                  initialChildSize: collapsedSize,
                  minChildSize: collapsedSize,
                  maxChildSize: 0.88,
                  snap: true,
                  snapSizes: [collapsedSize, 0.88],
                  builder: (context, scrollController) {
                    return _MetricsSheet(
                      scrollController: scrollController,
                      state: state,
                      busy: _busy,
                      expanded: _sheetExpanded,
                      showDebugSimulate: showDebug,
                      intervalsOn: _intervalsOn,
                      intervalSnapshot: interval,
                      goal: _goal,
                      goalSnapshot: goalSnap,
                      onIntervalsChanged:
                          state.isActive ? null : _toggleIntervals,
                      onGoalChanged: state.isActive ? null : _setGoal,
                      onStart: _ensurePermissionAndStart,
                      onDebugSimulate: _startDebugSimulation,
                      onPause: () => _service.pause(),
                      onResume: () => _service.resume(),
                      onFinish: _finish,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricsSheet extends StatelessWidget {
  final ScrollController scrollController;
  final RunTrackingState state;
  final bool busy;
  final bool expanded;
  final bool showDebugSimulate;
  final bool intervalsOn;
  final RunIntervalSnapshot intervalSnapshot;
  final RunSessionGoal goal;
  final RunGoalSnapshot goalSnapshot;
  final ValueChanged<bool>? onIntervalsChanged;
  final ValueChanged<RunSessionGoal>? onGoalChanged;
  final VoidCallback onStart;
  final VoidCallback onDebugSimulate;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onFinish;

  const _MetricsSheet({
    required this.scrollController,
    required this.state,
    required this.busy,
    required this.expanded,
    required this.showDebugSimulate,
    required this.intervalsOn,
    required this.intervalSnapshot,
    required this.goal,
    required this.goalSnapshot,
    required this.onIntervalsChanged,
    required this.onGoalChanged,
    required this.onStart,
    required this.onDebugSimulate,
    required this.onPause,
    required this.onResume,
    required this.onFinish,
  });

  RunSplit? get _lastCompleted {
    if (state.splits.isEmpty) return null;
    return state.splits.last;
  }

  RunSplit? get _bestCompleted {
    RunSplit? best;
    for (final split in state.splits) {
      final pace = split.paceSecPerKm;
      if (pace == null || !pace.isFinite) continue;
      if (best == null || pace < (best.paceSecPerKm ?? double.infinity)) {
        best = split;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final pace = state.currentPaceSecPerKm ??
        (state.distanceMeters > 0
            ? state.movingTimeSeconds / (state.distanceMeters / 1000.0)
            : null);
    final allSplits = state.displaySplits;
    final last = _lastCompleted;
    final best = _bestCompleted;

    final panel = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.97),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        10,
        20,
        16 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.35,
                ),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
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
          const SizedBox(height: 10),
          _RunPlanCard(
            goal: goal,
            goalSnapshot: goalSnapshot,
            intervalsOn: intervalsOn,
            intervalSnapshot: intervalSnapshot,
            active: state.isActive,
            onGoalChanged: onGoalChanged,
            onIntervalsChanged: onIntervalsChanged,
          ),
          const SizedBox(height: 12),
          if (busy)
            const Center(child: CircularProgressIndicator())
          else if (!state.isActive) ...[
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton(
                onPressed: onStart,
                child: Text(loc.runRecordStart),
              ),
            ),
            if (showDebugSimulate) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: onDebugSimulate,
                  icon: const Icon(Icons.bug_report_outlined),
                  label: Text(loc.runRecordDebugSimulate),
                ),
              ),
            ],
          ] else
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
          if (!expanded) ...[
            if (last != null || best != null) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _SplitSummaryCard(
                      title: loc.runRecordSplitLast,
                      split: last,
                      emptyLabel: '—',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SplitSummaryCard(
                      title: loc.runRecordSplitBest,
                      split: best,
                      emptyLabel: '—',
                      highlight: true,
                    ),
                  ),
                ],
              ),
              if (state.splits.length > 1) ...[
                const SizedBox(height: 8),
                Text(
                  loc.runRecordSplitsExpandHint,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ] else ...[
            const SizedBox(height: 24),
            Text(
              loc.runRecordSplitsTitle,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 8),
            if (allSplits.isEmpty)
              Text(
                loc.runRecordSplitsEmpty,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Expanded(flex: 2, child: SizedBox.shrink()),
                    Expanded(
                      child: Text(
                        loc.runRecordSplitTime,
                        textAlign: TextAlign.end,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        loc.runRecordSplitPace,
                        textAlign: TextAlign.end,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ...allSplits.map((split) => _SplitRow(split: split)),
            ],
          ],
        ],
      ),
    );

    // Fill the sheet viewport so DraggableScrollableSheet can drag, while
    // keeping the painted panel flush to the bottom (no gap under the modal).
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          controller: scrollController,
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [panel],
            ),
          ),
        );
      },
    );
  }
}

class _RunPlanCard extends StatelessWidget {
  final RunSessionGoal goal;
  final RunGoalSnapshot goalSnapshot;
  final bool intervalsOn;
  final RunIntervalSnapshot intervalSnapshot;
  final bool active;
  final ValueChanged<RunSessionGoal>? onGoalChanged;
  final ValueChanged<bool>? onIntervalsChanged;

  const _RunPlanCard({
    required this.goal,
    required this.goalSnapshot,
    required this.intervalsOn,
    required this.intervalSnapshot,
    required this.active,
    required this.onGoalChanged,
    required this.onIntervalsChanged,
  });

  String _formatGoalValue(RunSessionGoal g) {
    if (g.metric == RunIntervalMetric.time) {
      return RunFormatters.duration(g.value);
    }
    if (g.value >= 1000 && g.value % 1000 == 0) {
      return '${g.value ~/ 1000} km';
    }
    if (g.value >= 1000) {
      return '${(g.value / 1000).toStringAsFixed(1)} km';
    }
    return '${g.value} m';
  }

  String _formatRemaining(RunGoalSnapshot snap) {
    if (snap.goal.metric == RunIntervalMetric.time) {
      return RunFormatters.duration(snap.remaining.round());
    }
    final m = snap.remaining;
    if (m >= 1000) return '${(m / 1000).toStringAsFixed(2)} km';
    return '${m.round()} m';
  }

  Future<void> _editGoal(BuildContext context) async {
    if (onGoalChanged == null) return;
    final loc = AppLocalizations.of(context)!;
    var draft = goal.enabled
        ? goal
        : goal.copyWith(enabled: true, value: goal.value > 0 ? goal.value : 5000);

    final result = await showDialog<RunSessionGoal>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 24,
              ),
              title: Text(loc.runRecordGoalPickTitle),
              content: SizedBox(
                width: MediaQuery.sizeOf(context).width,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SegmentedButton<RunIntervalMetric>(
                      segments: [
                        ButtonSegment(
                          value: RunIntervalMetric.distance,
                          label: Text(loc.runIntervalMetricDistance),
                        ),
                        ButtonSegment(
                          value: RunIntervalMetric.time,
                          label: Text(loc.runIntervalMetricTime),
                        ),
                      ],
                      selected: {draft.metric},
                      onSelectionChanged: (set) {
                        final metric = set.first;
                        setDialogState(() {
                          draft = draft.copyWith(
                            metric: metric,
                            value: metric == RunIntervalMetric.distance
                                ? 5000
                                : 1800,
                          );
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    if (draft.metric == RunIntervalMetric.distance)
                      DropdownButtonFormField<int>(
                        key: ValueKey('goal-dist-${draft.value}'),
                        initialValue: _nearestDistance(draft.value),
                        decoration: InputDecoration(
                          labelText: loc.runIntervalDistance,
                        ),
                        items: [
                          for (final m in const [
                            1000,
                            2000,
                            3000,
                            5000,
                            10000,
                            21097,
                          ])
                            DropdownMenuItem(
                              value: m,
                              child: Text(
                                m >= 1000
                                    ? (m % 1000 == 0
                                        ? '${m ~/ 1000} km'
                                        : '${(m / 1000).toStringAsFixed(1)} km')
                                    : '$m m',
                              ),
                            ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setDialogState(
                            () => draft = draft.copyWith(value: v),
                          );
                        },
                      )
                    else
                      DropdownButtonFormField<int>(
                        key: ValueKey('goal-time-${draft.value}'),
                        initialValue: _nearestTime(draft.value),
                        decoration: InputDecoration(
                          labelText: loc.runIntervalDuration,
                        ),
                        items: [
                          for (final s in const [
                            600,
                            900,
                            1200,
                            1800,
                            2700,
                            3600,
                          ])
                            DropdownMenuItem(
                              value: s,
                              child: Text(RunFormatters.duration(s)),
                            ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setDialogState(
                            () => draft = draft.copyWith(value: v),
                          );
                        },
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(
                    ctx,
                    draft.copyWith(enabled: false),
                  ),
                  child: Text(loc.runRecordGoalNone),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(
                    ctx,
                    draft.copyWith(enabled: true),
                  ),
                  child: Text(loc.commonSave),
                ),
              ],
            );
          },
        );
      },
    );
    if (result != null) onGoalChanged!(result);
  }

  int _nearestDistance(int value) {
    const options = [1000, 2000, 3000, 5000, 10000, 21097];
    return options.reduce(
      (a, b) => (a - value).abs() <= (b - value).abs() ? a : b,
    );
  }

  int _nearestTime(int value) {
    const options = [600, 900, 1200, 1800, 2700, 3600];
    return options.reduce(
      (a, b) => (a - value).abs() <= (b - value).abs() ? a : b,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;

    String? intervalPhase;
    if (intervalsOn && active) {
      switch (intervalSnapshot.phase) {
        case RunIntervalPhase.work:
          intervalPhase = loc.runRecordIntervalWork(
            intervalSnapshot.workIndex,
            intervalSnapshot.totalWorks,
          );
        case RunIntervalPhase.rest:
          intervalPhase = loc.runRecordIntervalRest;
        case RunIntervalPhase.done:
          intervalPhase = loc.runRecordIntervalDone;
        case RunIntervalPhase.idle:
          intervalPhase = null;
      }
    }

    String goalSubtitle;
    if (!goal.enabled) {
      goalSubtitle = loc.runRecordGoalNone;
    } else if (goalSnapshot.completed) {
      goalSubtitle = loc.runRecordGoalDone;
    } else if (active) {
      goalSubtitle = loc.runRecordGoalRemaining(_formatRemaining(goalSnapshot));
    } else {
      goalSubtitle = _formatGoalValue(goal);
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            loc.runRecordPlanSection.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 0.8,
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: onGoalChanged == null ? null : () => _editGoal(context),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.flag_outlined,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          loc.runRecordGoal,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          goalSubtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: goal.enabled,
                    onChanged: onGoalChanged == null
                        ? null
                        : (v) {
                            if (v && !goal.enabled) {
                              _editGoal(context);
                            } else {
                              onGoalChanged!(goal.copyWith(enabled: v));
                            }
                          },
                  ),
                ],
              ),
            ),
          ),
          if (goal.enabled && active) ...[
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: goalSnapshot.progress.clamp(0.0, 1.0),
                minHeight: 5,
              ),
            ),
          ],
          Divider(
            height: 16,
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
          Row(
            children: [
              Icon(
                Icons.av_timer,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loc.runRecordIntervals,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (intervalPhase != null)
                      Text(
                        intervalPhase,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
              if (intervalSnapshot.isActive)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    intervalSnapshot.currentMetric ==
                            RunIntervalMetric.distance
                        ? '${intervalSnapshot.remaining.round()} m'
                        : RunFormatters.duration(
                            intervalSnapshot.remaining.round(),
                          ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              Switch.adaptive(
                value: intervalsOn,
                onChanged: onIntervalsChanged,
              ),
            ],
          ),
          if (intervalsOn && intervalSnapshot.isActive) ...[
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: intervalSnapshot.progress.clamp(0.0, 1.0),
                minHeight: 5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SplitSummaryCard extends StatelessWidget {
  final String title;
  final RunSplit? split;
  final String emptyLabel;
  final bool highlight;

  const _SplitSummaryCard({
    required this.title,
    required this.split,
    required this.emptyLabel,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final bg = highlight
        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.55)
        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 0.8,
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          if (split == null)
            Text(
              emptyLabel,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            )
          else ...[
            Text(
              loc.runRecordSplitKm(split!.km),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              RunFormatters.paceWithUnit(split!.paceSecPerKm),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              RunFormatters.duration(split!.durationSeconds),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SplitRow extends StatelessWidget {
  final RunSplit split;

  const _SplitRow({required this.split});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final label = split.isPartial
        ? loc.runRecordSplitPartial(split.km)
        : loc.runRecordSplitKm(split.km);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: split.isPartial ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              RunFormatters.duration(split.durationSeconds),
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            child: Text(
              RunFormatters.pace(split.paceSecPerKm),
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
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

