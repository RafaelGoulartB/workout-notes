import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/cardio_activity_type.dart';
import 'package:workout_notes/models/run_data_field.dart';
import 'package:workout_notes/models/run_interval_snapshot.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/models/run_review_draft.dart';
import 'package:workout_notes/models/run_session_context.dart';
import 'package:workout_notes/models/run_session_goal.dart';
import 'package:workout_notes/models/run_step_snapshot.dart';
import 'package:workout_notes/models/run_tracking_state.dart';
import 'package:workout_notes/models/scheduled_run.dart';
import 'package:workout_notes/repositories/body_measurement_repository.dart';
import 'package:workout_notes/repositories/run_plan_repository.dart';
import 'package:workout_notes/screens/run/run_post_run_review_screen.dart';
import 'package:workout_notes/screens/run/run_voice_settings_screen.dart';
import 'package:workout_notes/services/run_audio_gate_service.dart';
import 'package:workout_notes/services/run_data_fields_store.dart';
import 'package:workout_notes/services/run_session_coach.dart';
import 'package:workout_notes/services/run_tracking_service.dart';
import 'package:workout_notes/services/stationary_bike_tracking_service.dart';
import 'package:workout_notes/widgets/run/record/run_data_fields_grid.dart';
import 'package:workout_notes/widgets/run/record/run_goal_sheet.dart';
import 'package:workout_notes/widgets/run/record/run_record_countdown.dart';
import 'package:workout_notes/widgets/run/record/run_record_indoor.dart';
import 'package:workout_notes/widgets/run/record/run_record_map.dart';
import 'package:workout_notes/widgets/run/record/run_record_sheet.dart';
import 'package:workout_notes/widgets/run/record/run_record_top_bar.dart';
import 'package:workout_notes/widgets/run/run_permission_onboarding_sheet.dart';

class RunRecordScreen extends StatefulWidget {
  /// Structured session to execute. When set, the step engine drives the cues
  /// and the quick interval preset stays off.
  final RunPlanWorkout? planWorkout;

  /// Scheduled row this run fulfils. Linked to the activity once it is saved.
  final ScheduledRun? scheduledRun;
  final CardioActivityType initialActivityType;

  const RunRecordScreen({
    super.key,
    this.planWorkout,
    this.scheduledRun,
    this.initialActivityType = CardioActivityType.running,
  });

  @override
  State<RunRecordScreen> createState() => _RunRecordScreenState();
}

enum _RunLeaveAction { stay, background, discard }

class _RunRecordScreenState extends State<RunRecordScreen> {
  static const _permissionOnboardingSeenKey =
      'run_permission_onboarding_seen_v1';
  static const _maxSheetSize = 0.90;

  final _service = RunTrackingService.instance;
  final _indoorService = StationaryBikeTrackingService.instance;
  final _mapController = MapController();
  final _coach = RunSessionCoach();
  final _planRepo = RunPlanRepository();

  bool _busy = false;
  bool _sheetExpanded = false;
  double _lastCollapsedSize = 0.40;

  /// Real height of the collapsed sheet content, reported by the sheet. The
  /// estimate is only the first-frame fallback.
  double _measuredSheetH = 0;

  /// Identity of the live sheet. A change means it will be recreated, and a
  /// recreated sheet always starts collapsed.
  String? _lastSheetKey;
  bool _intervalsOn = false;
  RunSessionGoal _goal = const RunSessionGoal.defaults();
  RunAudioCapabilities _audioCapabilities =
      const RunAudioCapabilities.unknown();
  RunPlanWorkout? _resolvedPlanWorkout;
  ScheduledRun? _resolvedScheduledRun;

  /// Today's planned session offered as a one-tap suggestion, and whether the
  /// attached workout came from it (only then can it be detached again).
  ScheduledRun? _todayRun;
  bool _attachedFromSuggestion = false;
  bool _gpsPreparing = false;
  int _stableGpsFixes = 0;
  DateTime? _lastStableFixAt;
  int? _countdown;
  bool _countdownSkipped = false;
  bool _allowPop = false;
  late CardioActivityType _activityType;

  /// The camera follows the runner until the user pans or zooms the map.
  bool _followMap = true;
  List<RunDataField> _fields = RunDataFieldLayout.defaults;
  double _bodyWeightKg = 70;

  bool get _isIndoor => _activityType.isIndoor;

  RunTrackingState get _trackingState =>
      _isIndoor ? _indoorService.state : _service.state;

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
    final hasPlan = widget.planWorkout != null || widget.scheduledRun != null;
    _activityType = _indoorService.isActive
        ? _indoorService.activityType
        : hasPlan
        // A planned workout is a run; only the treadmill is a valid variant.
        ? (widget.initialActivityType == CardioActivityType.treadmill
              ? CardioActivityType.treadmill
              : CardioActivityType.running)
        : widget.initialActivityType;
    _resolvedPlanWorkout = widget.planWorkout ?? widget.scheduledRun?.workout;
    _resolvedScheduledRun = widget.scheduledRun;
    _service.addListener(_onChanged);
    _indoorService.addListener(_onIndoorChanged);
    _coach.addListener(_onCoachChanged);
    _service.initialize();
    _prepareCoach();
    _loadPreferences();
    _loadTodayWorkout();
  }

  /// The collapsed sheet content just reported its real height. Resize the
  /// sheet to fit it, so nothing below the fold can be cut off.
  void _onSheetContentHeight(double height) {
    if (!mounted || (height - _measuredSheetH).abs() < 1) return;
    setState(() => _measuredSheetH = height);
  }

  Future<void> _loadPreferences() async {
    final fields = await RunDataFieldsStore.instance.load();
    var weight = 70.0;
    try {
      weight = await BodyMeasurementRepository().getLatestWeightKg() ?? 70;
    } catch (_) {
      // Optional table on partially migrated databases: keep the default.
    }
    if (!mounted) return;
    setState(() {
      _fields = fields;
      _bodyWeightKg = weight;
    });
  }

  /// Offers today's planned session when the screen was opened "empty".
  Future<void> _loadTodayWorkout() async {
    if (widget.planWorkout != null || widget.scheduledRun != null) return;
    if (_service.state.isActive || _indoorService.isActive) return;
    try {
      final runs = await _planRepo.getScheduledRunsForDate(DateTime.now());
      ScheduledRun? planned;
      for (final run in runs) {
        if (run.isPlanned && run.workout != null) {
          planned = run;
          break;
        }
      }
      if (!mounted) return;
      setState(() => _todayRun = planned);
    } catch (_) {
      // No plan tables yet (fresh install): simply no suggestion.
    }
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
    if (!_isIndoor && !activeState.isActive && activeState.locationGranted) {
      await _prepareGps();
    }
  }

  @override
  void dispose() {
    _service.removeListener(_onChanged);
    _indoorService.removeListener(_onIndoorChanged);
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
    if (_isIndoor) return;
    final state = _service.state;
    if (_followMap && state.lat != null && state.lng != null) {
      _moveMapTo(state.lat!, state.lng!);
    }
    _coach.onTrackingUpdate(state);
  }

  void _moveMapTo(double lat, double lng) {
    try {
      _mapController.move(LatLng(lat, lng), _mapController.camera.zoom);
    } catch (_) {
      // The neutral preflight map has not mounted FlutterMap yet.
    }
  }

  void _onIndoorChanged() {
    if (!mounted) return;
    setState(() {});
  }

  /// The user panned or zoomed: stop chasing the runner until they ask.
  void _onMapMovedByUser() {
    if (_followMap && mounted) setState(() => _followMap = false);
  }

  void _recenterMap() {
    setState(() => _followMap = true);
    final state = _service.state;
    if (state.lat != null && state.lng != null) {
      _moveMapTo(state.lat!, state.lng!);
    }
  }

  void _setActivityType(CardioActivityType value) {
    if (_trackingState.isActive) return;
    // A workout attached to the run rules out the bike.
    if (_planWorkout != null && value == CardioActivityType.stationaryBike) {
      return;
    }
    setState(() {
      _activityType = value;
      _measuredSheetH = 0;
      _sheetExpanded = false;
    });
    if (value.usesGps && _service.state.locationGranted) {
      _prepareGps();
    }
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
        _intervalsOn = _planWorkout == null
            ? _coach.settings.intervalsEnabledByDefault
            : false;
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
      nativeVoice: !debugSim,
    );
  }

  void _setGoal(RunSessionGoal goal) {
    setState(() => _goal = goal);
    _coach.setGoal(goal);
  }

  Future<void> _editGoal() async {
    if (_service.state.isActive) return;
    final result = await showRunGoalSheet(context, goal: _goal);
    if (result != null && mounted) _setGoal(result);
  }

  void _setIntervals(bool value) {
    if (_planWorkout != null || _service.state.isActive) return;
    setState(() => _intervalsOn = value);
    _coach.setIntervalsOn(value);
  }

  /// One tap: run today's planned session instead of a free run.
  void _useTodayWorkout() {
    final run = _todayRun;
    final workout = run?.workout;
    if (run == null || workout == null || _service.state.isActive) return;
    setState(() {
      _resolvedScheduledRun = run;
      _resolvedPlanWorkout = workout;
      _attachedFromSuggestion = true;
      if (_activityType == CardioActivityType.stationaryBike) {
        _activityType = CardioActivityType.running;
      }
      _intervalsOn = false;
    });
    _coach.setIntervalsOn(false);
    _coach.setPlanWorkout(workout);
  }

  void _detachPlan() {
    if (!_attachedFromSuggestion || _service.state.isActive) return;
    setState(() {
      _resolvedScheduledRun = null;
      _resolvedPlanWorkout = null;
      _attachedFromSuggestion = false;
    });
    _coach.setPlanWorkout(null);
  }

  Future<void> _customizeFields() async {
    await showRunDataFieldsSheet(
      context,
      initial: _fields,
      onChanged: (next) {
        if (!mounted) return;
        setState(() => _fields = RunDataFieldLayout.sanitize(next));
        RunDataFieldsStore.instance.save(next);
      },
    );
  }

  Future<void> _replaceField(int index) async {
    if (index < 0 || index >= _fields.length) return;
    final picked = await showRunDataFieldPicker(
      context,
      replacing: _fields[index],
      current: _fields,
    );
    if (picked == null || !mounted) return;
    final next = [..._fields]..[index] = picked;
    setState(() => _fields = next);
    RunDataFieldsStore.instance.save(next);
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

  /// Counts down [RunVoiceSettings.countdownSeconds] before recording; a tap
  /// anywhere skips the rest.
  Future<void> _runCountdown() async {
    final seconds = _coach.settings.countdownSeconds;
    if (seconds <= 0) return;
    _countdownSkipped = false;
    for (var value = seconds; value >= 1; value--) {
      if (!mounted || _countdownSkipped) break;
      setState(() => _countdown = value);
      // Wait in slices so a tap ends the countdown at once.
      for (var i = 0; i < 10 && mounted && !_countdownSkipped; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    if (mounted) setState(() => _countdown = null);
  }

  void _skipCountdown() => _countdownSkipped = true;

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

  RunSessionContext _sessionContext() => RunSessionContext(
    planWorkoutId: _planWorkout?.id,
    scheduledRunId: _scheduledRun?.id,
    goal: _goal,
    intervalsOn: _intervalsOn,
    planSteps: _planWorkout?.stepsJson() ?? const [],
  );

  Future<void> _startDebugSimulation() async {
    setState(() => _busy = true);
    try {
      await _service.setSessionContext(_sessionContext());
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
        _coach.onTrackingUpdate(_service.state);
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

      await _service.setSessionContext(_sessionContext());
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
        _coach.onTrackingUpdate(_service.state);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startSelectedActivity() async {
    if (!_isIndoor) {
      await _ensurePermissionAndStart();
      return;
    }
    if (_indoorService.isActive) return;
    setState(() => _busy = true);
    try {
      await _runCountdown();
      if (!mounted) return;
      await _indoorService.start(
        type: _activityType,
        context: _planWorkout == null ? null : _sessionContext(),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pause() =>
      _isIndoor ? _indoorService.pause() : _service.pause();

  Future<void> _resume() =>
      _isIndoor ? _indoorService.resume() : _service.resume();

  /// Marks a manual lap and confirms it with a haptic tick and a short toast.
  Future<void> _lap() async {
    final loc = AppLocalizations.of(context)!;
    final lap = await _service.lap();
    if (lap == null || !mounted) return;
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          content: Text(loc.runLapMarked(lap.index)),
        ),
      );
  }

  Future<void> _skipStep() async {
    await _coach.skipStep();
    if (mounted) setState(() {});
  }

  String _finishTitle(AppLocalizations loc) =>
      _activityType == CardioActivityType.stationaryBike
      ? loc.stationaryBikeFinishConfirm
      : loc.runRecordFinishConfirm;

  String _finishBody(AppLocalizations loc) => _isIndoor
      ? loc.stationaryBikeFinishConfirmBody
      : loc.runRecordFinishConfirmBody;

  Future<void> _finish() async {
    final loc = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_finishTitle(loc)),
        content: Text(_finishBody(loc)),
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
      final draft = _isIndoor
          ? await _indoorService.stopForReview()
          : await _finishRunForReview();
      if (!mounted) return;
      if (draft != null) {
        await Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => RunPostRunReviewScreen(draft: draft),
          ),
        );
      } else {
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<RunReviewDraft?> _finishRunForReview() async {
    await _coach.endSession();
    final stepResults = await _coach.collectStepResults();
    final draft = await _service.stopForReview(stepResults: stepResults);
    await _coach.announceManualCompletion();
    return draft;
  }

  Future<void> _discard({bool confirm = true}) async {
    final loc = AppLocalizations.of(context)!;
    final bike = _activityType == CardioActivityType.stationaryBike;
    final confirmed = !confirm
        ? true
        : await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(
                bike
                    ? loc.stationaryBikeReviewDiscardTitle
                    : loc.runRecordDiscardConfirm,
              ),
              content: Text(
                _isIndoor
                    ? loc.stationaryBikeReviewDiscardBody
                    : loc.runRecordDiscardConfirmBody,
              ),
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
      if (_isIndoor) {
        await _indoorService.discard();
      } else {
        await _coach.endSession();
        await _service.discard();
      }
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleLeaveRequested() async {
    if (!_trackingState.isActive || _busy) return;
    final loc = AppLocalizations.of(context)!;
    final bike = _activityType == CardioActivityType.stationaryBike;
    final action = await showDialog<_RunLeaveAction>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          bike ? loc.stationaryBikeLeaveTitle : loc.runRecordLeaveTitle,
        ),
        content: Text(
          _isIndoor ? loc.stationaryBikeLeaveBody : loc.runRecordLeaveBody,
        ),
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
            child: Text(
              _isIndoor
                  ? loc.stationaryBikeKeepActive
                  : loc.runRecordKeepRunning,
            ),
          ),
        ],
      ),
    );
    if (!mounted || action == null || action == _RunLeaveAction.stay) return;
    if (action == _RunLeaveAction.discard) {
      // "Discard" here still asks once more: it throws the recording away.
      await _discard();
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

  Widget _buildBackground(
    AppLocalizations loc,
    RunTrackingState state,
    LatLng? center,
    List<LatLng> trail,
  ) {
    if (_isIndoor) {
      return RunIndoorBackdrop(
        type: _activityType,
        active: state.isActive,
        paused: state.isPaused,
      );
    }
    if (center == null) {
      return RunRecordMapPlaceholder(label: _gpsStatusLabel(loc, state));
    }
    return RunRecordMap(
      controller: _mapController,
      center: center,
      trail: trail,
      onUserMoved: _onMapMovedByUser,
    );
  }

  /// Bottom sheet: collapsed it hugs its content, expanded it shows the laps
  /// and every split.
  Widget _buildSheet(
    BuildContext context,
    RunTrackingState state, {
    required RunGoalSnapshot goalSnapshot,
    required RunStepSnapshot stepSnapshot,
  }) {
    final media = MediaQuery.of(context);
    final notificationsNeedAttention =
        _service.permissionState.notificationsNeedAttention;
    final showDebug =
        kDebugMode &&
        !_isIndoor &&
        !state.isActive &&
        _service.canDebugSimulate;
    final systemBottom = media.viewPadding.bottom;
    final bottomPad = (systemBottom > 0 ? systemBottom : 16.0) + 16.0;
    // First-frame fallback until the real height is measured.
    final estimate = (state.isActive ? 330.0 : 470.0) + bottomPad;
    final wanted = _measuredSheetH > 0 ? _measuredSheetH : estimate;
    final collapsedSize = (wanted / media.size.height).clamp(
      0.28,
      _maxSheetSize,
    );
    _lastCollapsedSize = collapsedSize;
    final canExpand = _maxSheetSize - collapsedSize > 0.01;
    // Recreating the sheet is the only way to change its min size, so the key
    // carries just that.
    final sheetKey = 'run-sheet-${collapsedSize.toStringAsFixed(3)}';
    if (_lastSheetKey != null && _lastSheetKey != sheetKey && _sheetExpanded) {
      // A recreated sheet starts collapsed; bring the content back in sync so
      // it always fits the extent it lands on.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _sheetExpanded) {
          setState(() => _sheetExpanded = false);
        }
      });
    }
    _lastSheetKey = sheetKey;
    final locked = state.isActive;
    return DraggableScrollableSheet(
      key: ValueKey(sheetKey),
      initialChildSize: collapsedSize,
      minChildSize: collapsedSize,
      maxChildSize: _maxSheetSize,
      snap: true,
      snapSizes: canExpand ? [collapsedSize, _maxSheetSize] : null,
      builder: (context, scrollController) {
        return RunRecordSheet(
          scrollController: scrollController,
          onContentHeight: _onSheetContentHeight,
          state: state,
          activityType: _activityType,
          busy: _busy || _gpsPreparing,
          expanded: _sheetExpanded,
          showDebugSimulate: showDebug,
          fields: _fields,
          bodyWeightKg: _bodyWeightKg,
          onCustomizeFields: _customizeFields,
          onFieldLongPress: _replaceField,
          intervalsOn: !_isIndoor && _intervalsOn,
          intervalSnapshot:
              state.intervalSnapshot ?? const RunIntervalSnapshot.idle(),
          intervalPreset: _coach.settings.interval,
          planWorkout: _planWorkout,
          onDetachPlan: _attachedFromSuggestion ? _detachPlan : null,
          todayWorkout: _todayRun?.workout,
          onUseTodayWorkout: _useTodayWorkout,
          stepSnapshot: stepSnapshot,
          goal: _goal,
          goalSnapshot: goalSnapshot,
          onEditGoal: locked ? null : _editGoal,
          onClearGoal: locked
              ? null
              : () => _setGoal(const RunSessionGoal.defaults()),
          onIntervalsChanged: locked || _planWorkout != null
              ? null
              : _setIntervals,
          voiceEnabled: _coach.settings.enabled,
          headphonesOnly: _coach.settings.headphonesOnly,
          headsetConnected: _audioCapabilities.headsetConnected,
          notificationsNeedAttention: notificationsNeedAttention,
          onActivityTypeChanged: locked ? null : _setActivityType,
          onOpenVoiceSettings: _openVoiceSettings,
          onOpenPermissions: _showPermissionOnboarding,
          onStart: _startSelectedActivity,
          onDebugSimulate: _startDebugSimulation,
          onPause: _pause,
          onResume: _resume,
          onLap: _lap,
          onFinish: _finish,
          onSkipStep: _skipStep,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final state = _trackingState;
    final hasLocation = state.lat != null && state.lng != null;
    final center = hasLocation ? LatLng(state.lat!, state.lng!) : null;
    final trail = state.trail
        .map((p) => LatLng(p.lat, p.lng))
        .toList(growable: false);
    final goalSnapshot = _coach.goalSnapshotFor(state);
    final stepSnapshot = state.stepSnapshot ?? const RunStepSnapshot.idle();

    return PopScope(
      canPop: !state.isActive || _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleLeaveRequested();
      },
      child: Scaffold(
        body: Stack(
          children: [
            _buildBackground(loc, state, center, trail),
            RunRecordTopBar(
              state: state,
              usesGps: !_isIndoor,
              debugSimulating: _service.isDebugSimulating,
              gpsLabel: _gpsStatusLabel(loc, state),
              onClose: state.isActive
                  ? _handleLeaveRequested
                  : () => Navigator.pop(context),
              onSettings: _openVoiceSettings,
            ),
            if (!_isIndoor && center != null && !_followMap)
              SafeArea(
                child: Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 68, right: 12),
                    child: RunRecenterButton(onPressed: _recenterMap),
                  ),
                ),
              ),
            NotificationListener<DraggableScrollableNotification>(
              onNotification: (notification) {
                // Only swap the content (its height) once the sheet has
                // settled on a snap point: doing it mid-drag made the sheet
                // stop halfway as its scroll view changed size under the
                // gesture.
                final nearCollapsed =
                    (notification.extent - _lastCollapsedSize).abs() < 0.03;
                final nearExpanded =
                    (notification.extent - _maxSheetSize).abs() < 0.03;
                if (!nearCollapsed && !nearExpanded) return false;
                final expanded = notification.extent >= 0.75;
                if (expanded != _sheetExpanded && mounted) {
                  setState(() => _sheetExpanded = expanded);
                }
                return false;
              },
              child: Builder(
                builder: (context) => _buildSheet(
                  context,
                  state,
                  goalSnapshot: goalSnapshot,
                  stepSnapshot: stepSnapshot,
                ),
              ),
            ),
            if (_countdown != null)
              Positioned.fill(
                child: RunRecordCountdown(
                  value: _countdown!,
                  onSkip: _skipCountdown,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
