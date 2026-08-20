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
                      icon: const Icon(Icons.settings_outlined),
                      tooltip: loc.runRecordSettings,
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
              final expanded = notification.extent >= 0.75;
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
                final hasIntervalStatus = state.isActive && _intervalsOn;
                final media = MediaQuery.of(context);
                final systemBottom = media.viewPadding.bottom;
                final bottomPad =
                    (systemBottom > 0 ? systemBottom : 16.0) + 16.0;
                // Sheet height tracks only the widgets that are on screen —
                // no reserved empty slots for hidden intervals/splits.
                var contentH = 23.0; // handle
                if (!state.locationGranted && state.supported) {
                  contentH += 68;
                }
                contentH += 72; // metrics
                contentH += 12;
                contentH += 22; // section label
                contentH += _goal.enabled && state.isActive ? 64.0 : 52.0;
                if (hasIntervalStatus) {
                  contentH += interval.isActive ? 64.0 : 52.0;
                }
                if (hasSplitSummary) {
                  contentH += 10 + 72;
                  if (state.splits.length > 1) contentH += 20;
                }
                contentH += 12 + 52; // gap + primary actions
                if (showDebug) contentH += 38;
                contentH += bottomPad;
                final collapsedSize =
                    (contentH / media.size.height).clamp(0.28, 0.72);
                return DraggableScrollableSheet(
                  key: ValueKey(
                    'run-sheet-${collapsedSize.toStringAsFixed(3)}-'
                    '${state.isActive}-$hasSplitSummary-$hasIntervalStatus',
                  ),
                  initialChildSize: collapsedSize,
                  minChildSize: collapsedSize,
                  maxChildSize: 0.90,
                  snap: true,
                  snapSizes: [collapsedSize, 0.90],
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

    final actionButtonStyle = FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(52),
      textStyle: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );
    final outlineActionStyle = OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(52),
      textStyle: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      side: BorderSide(
        color: theme.colorScheme.outline.withValues(alpha: 0.7),
        width: 1.5,
      ),
    );

    final systemBottom = MediaQuery.viewPaddingOf(context).bottom;
    final bottomPad = (systemBottom > 0 ? systemBottom : 16.0) + 16.0;

    final Widget actions;
    if (busy) {
      actions = const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (!state.isActive) {
      actions = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: onStart,
            style: actionButtonStyle,
            icon: const Icon(Icons.play_arrow_rounded, size: 26),
            label: Text(loc.runRecordStart),
          ),
          if (showDebugSimulate) ...[
            const SizedBox(height: 2),
            TextButton.icon(
              onPressed: onDebugSimulate,
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.onSurfaceVariant,
                minimumSize: const Size.fromHeight(36),
                textStyle: theme.textTheme.labelMedium,
              ),
              icon: const Icon(Icons.bug_report_outlined, size: 16),
              label: Text(loc.runRecordDebugSimulate),
            ),
          ],
        ],
      );
    } else {
      actions = Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: state.isPaused ? onResume : onPause,
              style: outlineActionStyle,
              icon: Icon(
                state.isPaused
                    ? Icons.play_arrow_rounded
                    : Icons.pause_rounded,
                size: 22,
              ),
              label: Text(
                state.isPaused ? loc.runRecordResume : loc.runRecordPause,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: onFinish,
              style: actionButtonStyle,
              icon: const Icon(Icons.stop_rounded, size: 22),
              label: Text(loc.runRecordFinish),
            ),
          ),
        ],
      );
    }

    // Collapsed: hug content. Expanded: metrics + buttons stay put; only
    // splits scroll. Sheet max is 90% of the screen.
    const sheetRadius = BorderRadius.vertical(top: Radius.circular(28));

    Widget buildHandle() {
      return Center(
        child: Container(
          width: 44,
          height: 5,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      );
    }

    Widget buildPermissionBanner() {
      if (state.locationGranted || !state.supported) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.errorContainer.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            loc.runRecordPermissionNeeded,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onErrorContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    Widget buildMetrics() {
      return Row(
        children: [
          Expanded(
            child: _Metric(
              label: loc.runRecordTime,
              value: RunFormatters.duration(state.durationSeconds),
              emphasize: state.isActive,
            ),
          ),
          Container(
            width: 1,
            height: 40,
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
          ),
          Expanded(
            child: _Metric(
              label: loc.runRecordDistance,
              value: RunFormatters.distanceKm(state.distanceMeters),
              unit: 'km',
              emphasize: state.isActive,
            ),
          ),
          Container(
            width: 1,
            height: 40,
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
          ),
          Expanded(
            child: _Metric(
              label: loc.runRecordPace,
              value: RunFormatters.pace(pace),
              unit: loc.runRecordPaceUnit,
              emphasize: state.isActive,
            ),
          ),
        ],
      );
    }

    Widget buildHeader() {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          buildHandle(),
          buildPermissionBanner(),
          buildMetrics(),
          const SizedBox(height: 12),
          _RunPlanCard(
            goal: goal,
            goalSnapshot: goalSnapshot,
            intervalsOn: intervalsOn,
            intervalSnapshot: intervalSnapshot,
            active: state.isActive,
            onGoalChanged: onGoalChanged,
          ),
        ],
      );
    }

    Widget buildCollapsedSplits() {
      if (last == null && best == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: _SplitSummaryList(
          lastTitle: loc.runRecordSplitLast,
          bestTitle: loc.runRecordSplitBest,
          last: last,
          best: best,
          emptyLabel: '—',
          expandHint: state.splits.length > 1
              ? loc.runRecordSplitsExpandHint
              : null,
        ),
      );
    }

    final splitsHeader = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Text(
          loc.runRecordSplitsTitle,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        if (allSplits.isNotEmpty)
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
      ],
    );

    final sheet = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.98),
        borderRadius: sheetRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 20,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: expanded
          ? Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, bottomPad),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  buildHeader(),
                  splitsHeader,
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      physics: const ClampingScrollPhysics(),
                      itemCount: allSplits.isEmpty ? 1 : allSplits.length,
                      itemBuilder: (context, index) {
                        if (allSplits.isEmpty) {
                          return Text(
                            loc.runRecordSplitsEmpty,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          );
                        }
                        return _SplitRow(split: allSplits[index]);
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  actions,
                ],
              ),
            )
          : SingleChildScrollView(
              controller: scrollController,
              physics: const ClampingScrollPhysics(),
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, bottomPad),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    buildHeader(),
                    buildCollapsedSplits(),
                    const SizedBox(height: 12),
                    actions,
                  ],
                ),
              ),
            ),
    );

    return sheet;
  }
}

class _RunPlanCard extends StatelessWidget {
  final RunSessionGoal goal;
  final RunGoalSnapshot goalSnapshot;
  final bool intervalsOn;
  final RunIntervalSnapshot intervalSnapshot;
  final bool active;
  final ValueChanged<RunSessionGoal>? onGoalChanged;

  const _RunPlanCard({
    required this.goal,
    required this.goalSnapshot,
    required this.intervalsOn,
    required this.intervalSnapshot,
    required this.active,
    required this.onGoalChanged,
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
      goalSubtitle = onGoalChanged != null && !active
          ? '${loc.runRecordGoalNone} · ${loc.runRecordGoalTapToChange}'
          : loc.runRecordGoalNone;
    } else if (goalSnapshot.completed) {
      goalSubtitle = loc.runRecordGoalDone;
    } else if (active) {
      goalSubtitle = loc.runRecordGoalRemaining(_formatRemaining(goalSnapshot));
    } else {
      goalSubtitle = onGoalChanged != null
          ? '${_formatGoalValue(goal)} · ${loc.runRecordGoalTapToChange}'
          : _formatGoalValue(goal);
    }

    final showIntervalStatus = intervalsOn && active;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            loc.runRecordPlanSection.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 1.0,
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.65,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              _PlanOptionTile(
                icon: Icons.flag_rounded,
                title: loc.runRecordGoal,
                subtitle: goalSubtitle,
                selected: goal.enabled,
                showChevron: onGoalChanged != null && !active,
                onTap: onGoalChanged == null ? null : () => _editGoal(context),
                trailing: active
                    ? const SizedBox.shrink()
                    : Switch.adaptive(
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
                footer: goal.enabled && active
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: goalSnapshot.progress.clamp(0.0, 1.0),
                          minHeight: 4,
                        ),
                      )
                    : null,
              ),
              if (showIntervalStatus) ...[
                Divider(
                  height: 1,
                  indent: 12,
                  endIndent: 12,
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.45,
                  ),
                ),
                _PlanOptionTile(
                  icon: Icons.av_timer_rounded,
                  title: loc.runRecordIntervals,
                  subtitle: intervalPhase ?? loc.runRecordIntervals,
                  selected: true,
                  trailing: intervalSnapshot.isActive
                      ? Text(
                          intervalSnapshot.currentMetric ==
                                  RunIntervalMetric.distance
                              ? '${intervalSnapshot.remaining.round()} m'
                              : RunFormatters.duration(
                                  intervalSnapshot.remaining.round(),
                                ),
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        )
                      : const SizedBox.shrink(),
                  footer: intervalSnapshot.isActive
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: intervalSnapshot.progress.clamp(0.0, 1.0),
                            minHeight: 4,
                          ),
                        )
                      : null,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PlanOptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final bool showChevron;
  final VoidCallback? onTap;
  final Widget trailing;
  final Widget? footer;

  const _PlanOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.trailing,
    this.showChevron = false,
    this.onTap,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconBg = selected
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest;
    final iconColor = selected
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurfaceVariant;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: iconBg,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(icon, size: 18, color: iconColor),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: title,
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          TextSpan(
                            text: '  ·  $subtitle',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (showChevron)
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  trailing,
                ],
              ),
              if (footer != null) ...[
                const SizedBox(height: 6),
                footer!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SplitSummaryList extends StatelessWidget {
  final String lastTitle;
  final String bestTitle;
  final RunSplit? last;
  final RunSplit? best;
  final String emptyLabel;
  final String? expandHint;

  const _SplitSummaryList({
    required this.lastTitle,
    required this.bestTitle,
    required this.last,
    required this.best,
    required this.emptyLabel,
    this.expandHint,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.65,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              _SplitSummaryRow(
                title: lastTitle,
                split: last,
                emptyLabel: emptyLabel,
              ),
              Divider(
                height: 1,
                indent: 12,
                endIndent: 12,
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
              ),
              _SplitSummaryRow(
                title: bestTitle,
                split: best,
                emptyLabel: emptyLabel,
                highlight: true,
              ),
            ],
          ),
        ),
        if (expandHint != null) ...[
          const SizedBox(height: 6),
          Text(
            expandHint!,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _SplitSummaryRow extends StatelessWidget {
  final String title;
  final RunSplit? split;
  final String emptyLabel;
  final bool highlight;

  const _SplitSummaryRow({
    required this.title,
    required this.split,
    required this.emptyLabel,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final accent = highlight ? theme.colorScheme.primary : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: accent ?? theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (split == null)
            Text(
              emptyLabel,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            )
          else ...[
            Text(
              loc.runRecordSplitKm(split!.km),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              RunFormatters.paceWithUnit(split!.paceSecPerKm),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: accent,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 10),
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
  final bool emphasize;

  const _Metric({
    required this.label,
    required this.value,
    this.unit,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelMedium?.copyWith(
            letterSpacing: 0.9,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: (emphasize
                  ? theme.textTheme.headlineMedium
                  : theme.textTheme.headlineSmall)
              ?.copyWith(
            fontWeight: FontWeight.w800,
            height: 1.05,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (unit != null) ...[
          const SizedBox(height: 2),
          Text(
            unit!,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

