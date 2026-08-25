import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/models/run_session_goal.dart';
import 'package:workout_notes/models/run_session_context.dart';
import 'package:workout_notes/models/scheduled_run.dart';
import 'package:workout_notes/repositories/run_plan_repository.dart';
import 'package:workout_notes/services/run_workout_step_engine.dart';
import 'package:workout_notes/widgets/run/run_plan_ui.dart';
import 'package:workout_notes/widgets/run/run_permission_onboarding_sheet.dart';
import 'package:workout_notes/models/run_split.dart';
import 'package:workout_notes/models/run_tracking_state.dart';
import 'package:workout_notes/models/run_voice_settings.dart';
import 'package:workout_notes/screens/run/run_detail_screen.dart';
import 'package:workout_notes/screens/run/run_voice_settings_screen.dart';
import 'package:workout_notes/services/run_interval_engine.dart';
import 'package:workout_notes/services/run_audio_gate_service.dart';
import 'package:workout_notes/services/run_tracking_service.dart';
import 'package:workout_notes/services/run_voice_coach.dart';
import 'package:workout_notes/utils/run_formatters.dart';

class RunRecordScreen extends StatefulWidget {
  /// Structured session to execute. When set, the step engine drives the cues
  /// and the quick interval preset stays off.
  final RunPlanWorkout? planWorkout;

  /// Scheduled row this run fulfils. Linked to the activity once it is saved.
  final ScheduledRun? scheduledRun;

  const RunRecordScreen({super.key, this.planWorkout, this.scheduledRun});

  @override
  State<RunRecordScreen> createState() => _RunRecordScreenState();
}

class _RunRecordScreenState extends State<RunRecordScreen> {
  static const _permissionOnboardingSeenKey =
      'run_permission_onboarding_seen_v1';

  final _service = RunTrackingService.instance;
  final _mapController = MapController();
  final _coach = RunVoiceCoach();
  bool _busy = false;
  bool _sheetExpanded = false;
  double _lastCollapsedSize = 0.40;

  /// Real height of the collapsed sheet content, reported by [_MeasureHeight].
  /// The estimate below is only the first-frame fallback: it has to be updated
  /// by hand every time a row is added to the sheet, and when it lags behind
  /// (as it did for the plan tile) the action buttons fall off the bottom.
  double _measuredSheetH = 0;

  /// Identity of the live sheet. A change means it will be recreated, and a
  /// recreated sheet always starts collapsed.
  String? _lastSheetKey;
  bool _intervalsOn = false;
  RunSessionGoal _goal = const RunSessionGoal.defaults();
  RunAudioCapabilities _audioCapabilities =
      const RunAudioCapabilities.unknown();
  final _planRepo = RunPlanRepository();
  RunPlanWorkout? _resolvedPlanWorkout;
  ScheduledRun? _resolvedScheduledRun;
  bool _gpsPreparing = false;
  int _stableGpsFixes = 0;
  DateTime? _lastStableFixAt;
  int? _countdown;
  bool _allowPop = false;

  /// The planned session, either passed directly or carried by a scheduled run.
  RunPlanWorkout? get _planWorkout =>
      _resolvedPlanWorkout ??
      widget.planWorkout ??
      widget.scheduledRun?.workout;

  ScheduledRun? get _scheduledRun =>
      _resolvedScheduledRun ?? widget.scheduledRun;

  @override
  void initState() {
    super.initState();
    _resolvedPlanWorkout = widget.planWorkout ?? widget.scheduledRun?.workout;
    _resolvedScheduledRun = widget.scheduledRun;
    _service.addListener(_onChanged);
    _coach.addListener(_onCoachChanged);
    _service.initialize();
    _prepareCoach();
  }

  /// The collapsed sheet content just reported its real height. Resize the
  /// sheet to fit it, so nothing below the fold can be cut off.
  void _onSheetContentHeight(double height) {
    if (!mounted || (height - _measuredSheetH).abs() < 1) return;
    setState(() => _measuredSheetH = height);
  }

  Future<void> _prepareCoach() async {
    await _service.initialize();
    await _coach.prepare();
    final audioCapabilities = await RunAudioGateService.instance
        .getCapabilities();
    final activeState = _service.state;
    final context = activeState.sessionContext;
    if (context?.planWorkoutId != null && _planWorkout == null) {
      _resolvedPlanWorkout = await _planRepo.getWorkout(
        context!.planWorkoutId!,
      );
    }
    if (context?.scheduledRunId != null && _scheduledRun == null) {
      _resolvedScheduledRun = await _planRepo.getScheduledRun(
        context!.scheduledRunId!,
      );
    }
    final plan = _planWorkout;
    if (plan != null) _coach.setPlanWorkout(plan);
    if (activeState.isActive && context != null) {
      _goal = context.goal;
      await _coach.attachToActiveSession(
        intervalsOn: context.intervalsOn,
        goal: context.goal,
        planWorkout: plan,
      );
    }
    if (!mounted) return;
    // A planned session replaces the quick interval preset.
    setState(() {
      _intervalsOn = activeState.isActive && context != null
          ? context.intervalsOn
          : plan != null
          ? false
          : _coach.intervalsOn;
      _audioCapabilities = audioCapabilities;
    });
    if (!activeState.isActive && activeState.locationGranted) {
      await _prepareGps();
    }
  }

  @override
  void dispose() {
    _service.removeListener(_onChanged);
    _coach.removeListener(_onCoachChanged);
    if (!_service.state.isActive) {
      _coach.endSession();
    }
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
      try {
        _mapController.move(
          LatLng(state.lat!, state.lng!),
          _mapController.camera.zoom,
        );
      } catch (_) {
        // The neutral preflight map has not mounted FlutterMap yet.
      }
    }
    _coach.onTrackingUpdate(state);
  }

  Future<void> _openVoiceSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RunVoiceSettingsScreen()),
    );
    await _coach.reloadSettings();
    final audioCapabilities = await RunAudioGateService.instance
        .getCapabilities();
    if (!mounted) return;
    if (!_service.state.isActive) {
      setState(() {
        _intervalsOn = _coach.settings.intervalsEnabledByDefault;
        _audioCapabilities = audioCapabilities;
      });
    } else {
      setState(() => _audioCapabilities = audioCapabilities);
    }
  }

  Future<void> _beginVoiceSession({bool debugSim = false}) async {
    await _coach.beginSession(
      intervalsOn: _intervalsOn,
      goal: _goal,
      planWorkout: _planWorkout,
      bypassHeadphonesGate: debugSim,
    );
  }

  void _setGoal(RunSessionGoal goal) {
    setState(() => _goal = goal);
    _coach.setGoal(goal);
  }

  void _setIntervals(bool value) {
    if (_planWorkout != null || _service.state.isActive) return;
    setState(() => _intervalsOn = value);
    _coach.setIntervalsOn(value);
  }

  Future<RunGpsFix?> _prepareGps() async {
    if (_gpsPreparing || _service.state.isActive) return null;
    setState(() => _gpsPreparing = true);
    try {
      final fix = await _service.prepareLocation();
      if (!mounted) return fix;
      setState(() {
        if (fix?.isReady == true) {
          final fixAt = fix?.recordedAt;
          final isFresh = fixAt == null || fixAt != _lastStableFixAt;
          if (isFresh) {
            _stableGpsFixes = (_stableGpsFixes + 1).clamp(0, 3);
            _lastStableFixAt = fixAt;
          }
        } else if (fix?.isRegular != true) {
          _stableGpsFixes = 0;
          _lastStableFixAt = null;
        }
      });
      return fix;
    } finally {
      if (mounted) setState(() => _gpsPreparing = false);
    }
  }

  Future<void> _runCountdown() async {
    for (var value = 3; value >= 1; value--) {
      if (!mounted) return;
      setState(() => _countdown = value);
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    if (mounted) setState(() => _countdown = null);
  }

  Future<bool> _confirmStartWithoutGps() async {
    final loc = AppLocalizations.of(context)!;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.runRecordGpsNotReadyTitle),
        content: Text(loc.runRecordGpsNotReadyBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc.runRecordWaitForGps),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(loc.runRecordStartAnyway),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<bool> _showPermissionOnboarding() async {
    final initialState = await _service.refreshPermissions();
    if (!mounted) return false;
    final shouldContinue = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      builder: (context) => RunPermissionOnboardingSheet(
        initialState: initialState,
        onRefresh: _service.refreshPermissions,
        onRequestLocation: _service.requestLocationPermission,
        onRequestNotifications: _service.requestNotificationPermission,
        onOpenSettings: _service.openAppSettings,
      ),
    );
    final refreshed = await _service.refreshPermissions();
    if (shouldContinue == true && refreshed.locationGranted) {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(_permissionOnboardingSeenKey, true);
      return true;
    }
    return false;
  }

  Future<bool> _ensurePermissionOnboardingForStart() async {
    final permissionState = await _service.refreshPermissions();
    if (!mounted) return false;
    final preferences = await SharedPreferences.getInstance();
    final hasSeenOnboarding =
        preferences.getBool(_permissionOnboardingSeenKey) ?? false;
    final shouldShow =
        !permissionState.locationGranted ||
        (permissionState.notificationsNeedAttention && !hasSeenOnboarding);
    if (!shouldShow) return permissionState.locationGranted;
    return _showPermissionOnboarding();
  }

  Future<void> _startDebugSimulation() async {
    setState(() => _busy = true);
    try {
      await _service.setSessionContext(
        RunSessionContext(
          planWorkoutId: _planWorkout?.id,
          scheduledRunId: _scheduledRun?.id,
          goal: _goal,
          intervalsOn: _intervalsOn,
          planSteps: _planWorkout?.stepsJson() ?? const [],
        ),
      );
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(loc.runVoiceDebugSimHint)));
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _ensurePermissionAndStart() async {
    final loc = AppLocalizations.of(context)!;
    if (!_service.isSupported) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.runRecordUnsupported)));
      return;
    }
    if (!await _ensurePermissionOnboardingForStart()) {
      if (mounted && !_service.state.locationGranted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(loc.runRecordPermissionNeeded)));
      }
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      var attempts = 0;
      while (_stableGpsFixes < 2 && mounted && attempts < 3) {
        attempts += 1;
        final fix = await _prepareGps();
        if (fix == null || !fix.isReady) break;
      }
      if (!mounted) return;
      if (_stableGpsFixes < 2 && !await _confirmStartWithoutGps()) {
        await _prepareGps();
        return;
      }

      await _service.setSessionContext(
        RunSessionContext(
          planWorkoutId: _planWorkout?.id,
          scheduledRunId: _scheduledRun?.id,
          goal: _goal,
          intervalsOn: _intervalsOn,
          planSteps: _planWorkout?.stepsJson() ?? const [],
        ),
      );
      await _runCountdown();
      if (!mounted) return;
      final ok = await _service.start();
      if (!ok && mounted) {
        final msg =
            _service.state.errorMessage ?? loc.runRecordPermissionNeeded;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      } else if (ok) {
        await _beginVoiceSession();
        await _coach.onTrackingUpdate(_service.state);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Links the recorded activity back to the plan and stores the per-step
  /// planned-vs-actual rows. Best-effort: a failure here must not cost the run.
  Future<void> _persistPlanResults(
    String activityId,
    List<RunStepResult> results,
  ) async {
    final plan = _planWorkout;
    if (plan == null) return;
    try {
      await _planRepo.setActivityPlanWorkout(
        activityId: activityId,
        planWorkoutId: plan.id,
      );
      if (results.isNotEmpty) {
        await _planRepo.saveActivitySteps(activityId, [
          for (final result in results)
            RunActivityStep(
              id: '',
              runActivityId: activityId,
              orderIndex: result.sequence,
              role: result.role.value,
              repIndex: result.repIndex,
              plannedMetric: result.plannedMetric.name,
              plannedValue: result.plannedValue,
              plannedPaceSecPerKm: result.plannedPaceSecPerKm,
              actualDistanceMeters: result.distanceMeters,
              actualDurationSeconds: result.durationSeconds,
              actualPaceSecPerKm: result.actualPaceSecPerKm,
            ),
        ]);
      }
      final scheduled = _scheduledRun;
      if (scheduled != null) {
        await _planRepo.attachActivity(
          scheduledRunId: scheduled.id,
          runActivityId: activityId,
        );
      } else {
        // Started from the plan or the planning screen rather than from the
        // calendar: without this the session would stay "planned" forever and
        // the plan's progress would never move.
        await _planRepo.markPlanWorkoutCompleted(
          planWorkoutId: plan.id,
          date: DateTime.now(),
          runActivityId: activityId,
        );
      }
    } catch (_) {
      // The run itself is already saved; the plan link can be redone later.
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
      final stepResults = await _coach.collectStepResults();
      final activity = await _service.stop();
      await _coach.announceManualCompletion();
      if (activity != null) {
        await _persistPlanResults(activity.id, stepResults);
      }
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

  Future<void> _discard({bool confirm = true}) async {
    final loc = AppLocalizations.of(context)!;
    final confirmed = !confirm
        ? true
        : await showDialog<bool>(
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

  Future<void> _handleLeaveRequested() async {
    if (!_service.state.isActive || _busy) return;
    final loc = AppLocalizations.of(context)!;
    final action = await showDialog<_RunLeaveAction>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.runRecordLeaveTitle),
        content: Text(loc.runRecordLeaveBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, _RunLeaveAction.stay),
            child: Text(loc.runRecordStay),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _RunLeaveAction.discard),
            child: Text(loc.runRecordDiscard),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, _RunLeaveAction.background),
            child: Text(loc.runRecordKeepRunning),
          ),
        ],
      ),
    );
    if (!mounted || action == null || action == _RunLeaveAction.stay) return;
    if (action == _RunLeaveAction.discard) {
      await _discard(confirm: false);
      return;
    }
    setState(() => _allowPop = true);
    Navigator.pop(context);
  }

  String _gpsStatusLabel(AppLocalizations loc, RunTrackingState state) {
    if (_gpsPreparing) return loc.runRecordGpsSearching;
    final accuracy = state.accuracyMeters;
    if (state.lat == null || state.lng == null || accuracy == null) {
      return loc.runRecordGpsNoFix;
    }
    final quality = accuracy <= 20
        ? loc.runRecordGpsReady
        : accuracy <= 35
        ? loc.runRecordGpsRegular
        : loc.runRecordGpsWeak;
    return '$quality · ${accuracy.round()} m';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final state = _service.state;
    final hasLocation = state.lat != null && state.lng != null;
    final center = hasLocation ? LatLng(state.lat!, state.lng!) : null;
    final trail = state.trail
        .map((p) => LatLng(p.lat, p.lng))
        .toList(growable: false);
    final interval = _coach.intervalSnapshot;
    final goalSnap = _coach.goalSnapshotFor(state);
    final nativeStep = state.nativeStepSnapshot;
    final stepSnapshot = nativeStep == null
        ? _coach.stepSnapshot
        : RunStepSnapshot.fromMap(nativeStep);

    return PopScope(
      canPop: !state.isActive || _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleLeaveRequested();
      },
      child: Scaffold(
        body: Stack(
          children: [
            if (center == null)
              ColoredBox(
                color: theme.colorScheme.surfaceContainerLow,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 240),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.location_searching_rounded,
                          size: 48,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _gpsStatusLabel(loc, state),
                          style: theme.textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
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
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
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
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: center,
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
                            ? _handleLeaveRequested
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
                    if (!state.isActive && !_service.isDebugSimulating)
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface.withValues(
                            alpha: 0.92,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _gpsStatusLabel(loc, state),
                          style: theme.textTheme.labelMedium,
                        ),
                      ),
                    if (state.isActive &&
                        (state.hasWeakGps ||
                            (state.isRecording &&
                                state.lat == null &&
                                !_service.isDebugSimulating)))
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
                // Evita trocar o conteúdo (altura) no meio do gesto — isso
                // causava o "para no meio" porque o SingleChildScrollView
                // mudava de tamanho enquanto o usuário arrastava. Só atualiza
                // quando o sheet já assentou num snap.
                final nearCollapsed =
                    (notification.extent - _lastCollapsedSize).abs() < 0.03;
                final nearExpanded = (notification.extent - 0.90).abs() < 0.03;
                if (!nearCollapsed && !nearExpanded) return false;
                final expanded = notification.extent >= 0.75;
                if (expanded != _sheetExpanded && mounted) {
                  setState(() => _sheetExpanded = expanded);
                }
                return false;
              },
              child: Builder(
                builder: (context) {
                  final hasSplitSummary = state.splits.isNotEmpty;
                  final showDebug =
                      kDebugMode &&
                      !state.isActive &&
                      _service.canDebugSimulate;
                  final notificationsNeedAttention =
                      _service.permissionState.notificationsNeedAttention;
                  final showPermissionBanner =
                      !state.isActive &&
                      state.supported &&
                      (!state.locationGranted || notificationsNeedAttention);
                  final hasIntervalStatus = state.isActive && _intervalsOn;
                  final media = MediaQuery.of(context);
                  final systemBottom = media.viewPadding.bottom;
                  final bottomPad =
                      (systemBottom > 0 ? systemBottom : 16.0) + 16.0;
                  // Sheet height tracks only the widgets that are on screen —
                  // no reserved empty slots for hidden intervals/splits.
                  var contentH = 23.0; // handle
                  if (showPermissionBanner) {
                    contentH += 100;
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
                  // Once the sheet has been laid out, trust the measurement over
                  // the estimate — that is what keeps the buttons on screen no
                  // matter which rows the session happens to show.
                  final wanted = _measuredSheetH > 0
                      ? _measuredSheetH
                      : contentH;
                  const maxSize = 0.90;
                  final collapsedSize = (wanted / media.size.height).clamp(
                    0.28,
                    maxSize,
                  );
                  _lastCollapsedSize = collapsedSize;
                  final canExpand = maxSize - collapsedSize > 0.01;
                  // Recreating the sheet is the only way to change its min size,
                  // so the key carries just that. It used to also carry
                  // isActive/splits/intervals, which recreated the sheet mid-run
                  // (first split completing) and dropped it back to the collapsed
                  // extent while the expanded content was still on screen —
                  // pushing the action buttons below the fold.
                  final sheetKey =
                      'run-sheet-${collapsedSize.toStringAsFixed(3)}';
                  if (_lastSheetKey != null &&
                      _lastSheetKey != sheetKey &&
                      _sheetExpanded) {
                    // A recreated sheet starts collapsed; bring the content back
                    // in sync so it always fits the extent it lands on.
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && _sheetExpanded) {
                        setState(() => _sheetExpanded = false);
                      }
                    });
                  }
                  _lastSheetKey = sheetKey;
                  return DraggableScrollableSheet(
                    key: ValueKey(sheetKey),
                    initialChildSize: collapsedSize,
                    minChildSize: collapsedSize,
                    maxChildSize: maxSize,
                    snap: true,
                    snapSizes: canExpand ? [collapsedSize, maxSize] : null,
                    builder: (context, scrollController) {
                      return _MetricsSheet(
                        scrollController: scrollController,
                        onContentHeight: _onSheetContentHeight,
                        state: state,
                        busy: _busy || _gpsPreparing,
                        expanded: _sheetExpanded,
                        showDebugSimulate: showDebug,
                        intervalsOn: _intervalsOn,
                        intervalSnapshot: interval,
                        intervalPreset: _coach.settings.interval,
                        planWorkout: _planWorkout,
                        stepSnapshot: stepSnapshot,
                        goal: _goal,
                        goalSnapshot: goalSnap,
                        onGoalChanged: state.isActive ? null : _setGoal,
                        onIntervalsChanged:
                            state.isActive || _planWorkout != null
                            ? null
                            : _setIntervals,
                        voiceEnabled: _coach.settings.enabled,
                        headphonesOnly: _coach.settings.headphonesOnly,
                        headsetConnected: _audioCapabilities.headsetConnected,
                        notificationsNeedAttention: notificationsNeedAttention,
                        onOpenVoiceSettings: _openVoiceSettings,
                        onOpenPermissions: _showPermissionOnboarding,
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
            if (_countdown != null)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.52),
                  child: Center(
                    child: Text(
                      '$_countdown',
                      semanticsLabel: loc.runRecordCountdown('$_countdown'),
                      style: theme.textTheme.displayLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 104,
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

enum _RunLeaveAction { stay, background, discard }

class _MetricsSheet extends StatelessWidget {
  final ScrollController scrollController;

  /// Reports the height of the collapsed content so the sheet can hug it.
  final ValueChanged<double> onContentHeight;
  final RunTrackingState state;
  final bool busy;
  final bool expanded;
  final bool showDebugSimulate;
  final bool intervalsOn;
  final RunIntervalSnapshot intervalSnapshot;
  final RunIntervalPreset intervalPreset;
  final RunPlanWorkout? planWorkout;
  final RunStepSnapshot stepSnapshot;
  final RunSessionGoal goal;
  final RunGoalSnapshot goalSnapshot;
  final ValueChanged<RunSessionGoal>? onGoalChanged;
  final ValueChanged<bool>? onIntervalsChanged;
  final bool voiceEnabled;
  final bool headphonesOnly;
  final bool headsetConnected;
  final bool notificationsNeedAttention;
  final VoidCallback onOpenVoiceSettings;
  final VoidCallback onOpenPermissions;
  final VoidCallback onStart;
  final VoidCallback onDebugSimulate;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onFinish;

  const _MetricsSheet({
    required this.scrollController,
    required this.onContentHeight,
    required this.state,
    required this.busy,
    required this.expanded,
    required this.showDebugSimulate,
    required this.intervalsOn,
    required this.intervalSnapshot,
    required this.intervalPreset,
    required this.planWorkout,
    required this.stepSnapshot,
    required this.goal,
    required this.goalSnapshot,
    required this.onGoalChanged,
    required this.onIntervalsChanged,
    required this.voiceEnabled,
    required this.headphonesOnly,
    required this.headsetConnected,
    required this.notificationsNeedAttention,
    required this.onOpenVoiceSettings,
    required this.onOpenPermissions,
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
    final pace =
        state.currentPaceSecPerKm ??
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
                state.isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
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
      final locationMissing = !state.locationGranted;
      if (state.isActive ||
          !state.supported ||
          (!locationMissing && !notificationsNeedAttention)) {
        return const SizedBox.shrink();
      }
      final backgroundColor = locationMissing
          ? theme.colorScheme.errorContainer
          : theme.colorScheme.secondaryContainer;
      final foregroundColor = locationMissing
          ? theme.colorScheme.onErrorContainer
          : theme.colorScheme.onSecondaryContainer;
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: backgroundColor.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                locationMissing
                    ? loc.runRecordPermissionNeeded
                    : loc.runPermissionsNotificationsBanner,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: foregroundColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: onOpenPermissions,
                style: TextButton.styleFrom(foregroundColor: foregroundColor),
                child: Text(loc.runPermissionsSetupAction),
              ),
            ],
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
            intervalPreset: intervalPreset,
            planWorkout: planWorkout,
            stepSnapshot: stepSnapshot,
            active: state.isActive,
            onGoalChanged: onGoalChanged,
            onIntervalsChanged: onIntervalsChanged,
            voiceEnabled: voiceEnabled,
            headphonesOnly: headphonesOnly,
            headsetConnected: headsetConnected,
            onOpenVoiceSettings: onOpenVoiceSettings,
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
      // Fix: sheet deve usar sempre o mesmo scrollable com o controller do
      // DraggableScrollableSheet. Antes, expandido era Column+Expanded(ListView)
      // e recolhido SingleChildScrollView — trocar o tipo no meio do gesto
      // (via extent >= 0.75) destacava o controller e travava para baixo.
      // Tentativa anterior de manter header/actions pinados fora do scroll
      // quebrou o arraste para cima, pois o gesto no header não chegava ao
      // controller. Agora todo o conteúdo fica dentro de um único
      // SingleChildScrollView com o scrollController, então qualquer ponto
      // do sheet arrasta/expande e, quando no topo, recolhe.
      child: SingleChildScrollView(
        controller: scrollController,
        physics: const ClampingScrollPhysics(),
        // Measured only while collapsed: expanded content is the full splits
        // list, which must not drive the collapsed height. The scroll view
        // gives its child unbounded height, so this is the intrinsic height.
        child: _MeasureHeight(
          onHeight: expanded ? null : onContentHeight,
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, bottomPad),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                buildHeader(),
                if (expanded) ...[
                  splitsHeader,
                  if (allSplits.isEmpty)
                    Text(
                      loc.runRecordSplitsEmpty,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  else
                    ...allSplits.map((s) => _SplitRow(split: s)),
                  const SizedBox(height: 12),
                ] else ...[
                  const SizedBox(height: 10),
                  buildCollapsedSplits(),
                  const SizedBox(height: 12),
                ],
                actions,
              ],
            ),
          ),
        ),
      ),
    );

    return sheet;
  }
}

/// Reports its child's laid-out height, without affecting layout. Lets the run
/// sheet size itself from what it actually renders instead of from an estimate
/// that has to be kept in sync by hand.
class _MeasureHeight extends SingleChildRenderObjectWidget {
  final ValueChanged<double>? onHeight;

  const _MeasureHeight({required this.onHeight, required Widget super.child});

  @override
  _RenderMeasureHeight createRenderObject(BuildContext context) =>
      _RenderMeasureHeight(onHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderMeasureHeight renderObject,
  ) {
    renderObject.onHeight = onHeight;
  }
}

class _RenderMeasureHeight extends RenderProxyBox {
  _RenderMeasureHeight(this.onHeight);

  ValueChanged<double>? onHeight;
  double _reported = 0;

  @override
  void performLayout() {
    super.performLayout();
    final callback = onHeight;
    if (callback == null) return;
    final height = size.height;
    if ((height - _reported).abs() < 1) return;
    _reported = height;
    // setState is illegal during layout — report on the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => callback(height));
  }
}

class _RunPlanCard extends StatelessWidget {
  final RunSessionGoal goal;
  final RunGoalSnapshot goalSnapshot;
  final bool intervalsOn;
  final RunIntervalSnapshot intervalSnapshot;
  final RunIntervalPreset intervalPreset;
  final RunPlanWorkout? planWorkout;
  final RunStepSnapshot stepSnapshot;
  final bool active;
  final ValueChanged<RunSessionGoal>? onGoalChanged;
  final ValueChanged<bool>? onIntervalsChanged;
  final bool voiceEnabled;
  final bool headphonesOnly;
  final bool headsetConnected;
  final VoidCallback onOpenVoiceSettings;

  const _RunPlanCard({
    required this.goal,
    required this.goalSnapshot,
    required this.intervalsOn,
    required this.intervalSnapshot,
    required this.intervalPreset,
    required this.planWorkout,
    required this.stepSnapshot,
    required this.active,
    required this.onGoalChanged,
    required this.onIntervalsChanged,
    required this.voiceEnabled,
    required this.headphonesOnly,
    required this.headsetConnected,
    required this.onOpenVoiceSettings,
  });

  /// While recording, show where in the session we are; before starting,
  /// show what the session is.
  String _planSubtitle(AppLocalizations loc, RunPlanWorkout plan) {
    if (!stepSnapshot.isActive) {
      if (stepSnapshot.isDone && active) return loc.runRecordIntervalDone;
      return '${RunPlanUi.kindLabel(loc, plan.kind)} · '
          '${RunPlanUi.sessionSummary(loc, plan)}';
    }
    final role = RunPlanUi.roleLabel(loc, stepSnapshot.role);
    if (stepSnapshot.repTotal > 1) {
      return '$role · '
          '${loc.runRecordPlanRepOf(stepSnapshot.repIndex, stepSnapshot.repTotal)}';
    }
    return '$role · '
        '${loc.runRecordPlanStepOf(stepSnapshot.stepIndex + 1, stepSnapshot.totalSteps)}';
  }

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

  String _formatIntervalAmount(RunIntervalMetric metric, int value) {
    if (metric == RunIntervalMetric.time) return RunFormatters.duration(value);
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)} km';
    return '$value m';
  }

  Future<void> _editGoal(BuildContext context) async {
    if (onGoalChanged == null) return;
    final loc = AppLocalizations.of(context)!;
    var draft = goal.enabled
        ? goal
        : goal.copyWith(
            enabled: true,
            value: goal.value > 0 ? goal.value : 5000,
          );

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
                  onPressed: () =>
                      Navigator.pop(ctx, draft.copyWith(enabled: false)),
                  child: Text(loc.runRecordGoalNone),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.pop(ctx, draft.copyWith(enabled: true)),
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
    final plan = planWorkout;
    final showGoal = !active || goal.enabled;
    final showQuickIntervals = plan == null && (!active || intervalsOn);
    final voiceSubtitle = !voiceEnabled
        ? loc.runRecordVoiceOff
        : headphonesOnly && !headsetConnected
        ? loc.runRecordVoiceHeadsetMissing
        : loc.runRecordVoiceReady;

    // An active run without a goal should not show the empty goal tile. Keep
    // the section when it still has a plan or interval status to display.
    if (!showGoal && plan == null && !showIntervalStatus) {
      return const SizedBox.shrink();
    }

    final sectionDivider = Divider(
      height: 1,
      indent: 12,
      endIndent: 12,
      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
    );
    final goalTile = _PlanOptionTile(
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
    );

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
              if (!active) ...[
                _PlanOptionTile(
                  icon: Icons.record_voice_over_outlined,
                  title: loc.runVoiceEnabled,
                  subtitle: voiceSubtitle,
                  selected:
                      voiceEnabled && (!headphonesOnly || headsetConnected),
                  showChevron: true,
                  trailing: const SizedBox.shrink(),
                  onTap: onOpenVoiceSettings,
                ),
                sectionDivider,
              ],
              if (showGoal) goalTile,
              if (plan != null) ...[
                if (showGoal) sectionDivider,
                _PlanOptionTile(
                  icon: RunPlanUi.kindIcon(plan.kind),
                  title: loc.runRecordPlanSessionTitle,
                  subtitle: _planSubtitle(loc, plan),
                  selected: true,
                  trailing: stepSnapshot.isActive
                      ? Text(
                          stepSnapshot.metric == RunIntervalMetric.distance
                              ? '${stepSnapshot.remaining.round()} m'
                              : RunFormatters.duration(
                                  stepSnapshot.remaining.round(),
                                ),
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        )
                      : const SizedBox.shrink(),
                  footer: stepSnapshot.isActive
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: stepSnapshot.progress.clamp(0.0, 1.0),
                            minHeight: 4,
                          ),
                        )
                      : null,
                ),
              ],
              if (showQuickIntervals) ...[
                if (showGoal || plan != null) sectionDivider,
                _PlanOptionTile(
                  icon: Icons.av_timer_rounded,
                  title: loc.runRecordIntervals,
                  subtitle: active
                      ? (intervalPhase ?? loc.runRecordIntervals)
                      : loc.runIntervalPresetSummary(
                          _formatIntervalAmount(
                            intervalPreset.workMetric,
                            intervalPreset.workValue,
                          ),
                          _formatIntervalAmount(
                            intervalPreset.restMetric,
                            intervalPreset.restValue,
                          ),
                          intervalPreset.repeats,
                        ),
                  selected: intervalsOn,
                  trailing: active && intervalSnapshot.isActive
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
                      : Switch.adaptive(
                          value: intervalsOn,
                          onChanged: onIntervalsChanged,
                        ),
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
              if (footer != null) ...[const SizedBox(height: 6), footer!],
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
          style:
              (emphasize
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
