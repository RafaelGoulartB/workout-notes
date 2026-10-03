import 'dart:async';
import 'package:flutter/material.dart';
import 'package:workout_notes/models/alarm_wake_settings.dart';
import 'package:workout_notes/models/sleep_monitor_mode.dart';
import 'package:workout_notes/models/sleep_monitor_state.dart';
import 'package:workout_notes/services/alarm_wake_settings_service.dart';
import 'package:workout_notes/services/notification_service.dart';
import 'package:workout_notes/services/sleep_mission_service.dart';
import 'package:workout_notes/services/sleep_monitor_service.dart';
import 'package:workout_notes/services/traditional_alarm_service.dart';
import 'package:workout_notes/utils/sleep_alarm_time.dart';

/// Why [SleepMonitorController.start] did (not) begin a monitoring session.
enum SleepStartResult {
  started,
  invalidWindow,
  microphoneDenied,
  notificationsDenied,
  exactAlarmRequired,
  missionUnavailable,

  /// The native side refused; the reason is in `service.state.errorCode`.
  failed,
}

/// What [SleepMonitorController.applyPickedAlarmTime] did with the time chosen
/// in the picker.
enum AlarmTimeResult { invalidWindow, selected, updated, updateFailed }

/// What [SleepMonitorController.shiftAlarmTime] did.
enum AlarmShiftResult { ignored, invalidWindow, shifted }

/// Mission/permission/alarm logic behind the sleep monitor screen: the chosen
/// mode and wake time, the busy flag around native calls, and the hand-off of
/// a finished alarm night to the result screen. Widgets only render it and
/// map the outcomes to messages; it holds no `BuildContext`.
class SleepMonitorController extends ChangeNotifier {
  SleepMonitorController({
    SleepMonitorService? service,
    SleepMissionService? missions,
    TraditionalAlarmService? alarmSettings,
    AlarmWakeSettingsService? wakeSettings,
  }) : service = service ?? SleepMonitorService.instance,
       missions = missions ?? SleepMissionService(),
       _alarmSettings = alarmSettings ?? TraditionalAlarmService.instance,
       _wakeSettings = wakeSettings ?? AlarmWakeSettingsService() {
    _alarmWasDismissed = this.service.state.alarmDismissed;
    this.service.addListener(_onServiceChanged);
  }

  static const modeOrder = <SleepMonitoringMode>[
    SleepMonitoringMode.alarmWithoutMission,
    SleepMonitoringMode.alarmWithMission,
    SleepMonitoringMode.monitoringOnly,
  ];

  final SleepMonitorService service;
  final SleepMissionService missions;
  final TraditionalAlarmService _alarmSettings;
  final AlarmWakeSettingsService _wakeSettings;
  AlarmWakeSettings _wake = AlarmWakeSettings.defaults;

  TimeOfDay _selectedTime = const TimeOfDay(hour: 7, minute: 0);
  SleepMonitoringMode _selectedMode = SleepMonitoringMode.alarmWithoutMission;
  int _globalMaxSnoozes = TraditionalAlarmService.defaultMaxSnoozes;
  bool _globalSnoozeEnabled = true;
  bool _isBusy = false;
  bool _loading = true;
  bool _loadFailed = false;
  bool _openingResult = false;
  bool _disposed = false;
  String? _pendingAlarmResultId;

  /// Last seen dismissal flag. The native state keeps reporting a dismissed
  /// alarm until the next night starts, so only the change to "dismissed"
  /// (seen while this screen is open) leads to the result.
  bool _alarmWasDismissed = false;

  /// Called when a night ended by its alarm has a result waiting and the app
  /// is in the foreground; the screen opens the result page from it.
  VoidCallback? onAlarmResultReady;

  SleepMonitorState get state => service.state;
  TimeOfDay get selectedTime => _selectedTime;
  SleepMonitoringMode get selectedMode => _selectedMode;
  int get globalMaxSnoozes => _globalMaxSnoozes;
  bool get globalSnoozeEnabled => _globalSnoozeEnabled;
  bool get isBusy => _isBusy;
  bool get loading => _loading;
  bool get loadFailed => _loadFailed;
  bool get missionReady => missions.config.isReady;
  AlarmWakeSettings get wakeSettings => _wake;

  /// Start of the smart window shown for [alarmAt]: the running night's own
  /// window, otherwise the configured one (alarm modes only).
  DateTime? smartWindowStartFor(SleepMonitorState state, DateTime? alarmAt) {
    if (alarmAt == null) return null;
    final running = state.isActive || state.isAlarmPending;
    final minutes = running
        ? state.smartWindowMinutes
        : (_selectedMode.hasAlarm ? _wake.windowMinutes : 0);
    if (minutes <= 0) return null;
    return alarmAt.subtract(Duration(minutes: minutes));
  }

  /// Whether [mode] is unusable until a mission is configured.
  bool isModeLocked(SleepMonitoringMode mode) =>
      mode.requiresMission && !missionReady;

  /// Alarm shown for the current state: the running/snoozing alarm when there
  /// is one, otherwise the next occurrence of the selected time (only for
  /// alarm modes).
  DateTime? alarmAtFor(SleepMonitorState state) {
    final running = state.isActive || state.isAlarmPending;
    if (running && state.alarmAt != null) return state.alarmAt!.toLocal();
    return _selectedMode.hasAlarm
        ? SleepAlarmTime.nextOccurrence(_selectedTime)
        : null;
  }

  /// Whether the start button is enabled for [alarmAt].
  bool canStart(DateTime? alarmAt) {
    if (_isBusy) return false;
    if (_selectedMode.hasAlarm &&
        !SleepAlarmTime.isWithinMonitoringWindow(alarmAt!)) {
      return false;
    }
    if (_selectedMode.requiresMission && !missionReady) return false;
    return true;
  }

  // ------------------------------------------------------------------
  // Lifecycle
  // ------------------------------------------------------------------

  Future<void> initialize() async {
    if (_loadFailed) {
      _loadFailed = false;
      _loading = true;
      _notify();
    }
    try {
      await _readState();
    } catch (error, stack) {
      debugPrint('Sleep monitor failed to initialize: $error\n$stack');
      _loadFailed = true;
      _loading = false;
      _notify();
    }
  }

  Future<void> _readState() async {
    await service.initialize();
    // Opening the screen re-reads the native state (initialize() runs once).
    await service.refresh();
    if (!service.isSupported) {
      _loading = false;
      _notify();
      return;
    }
    await service.getAlarmCapabilities();
    await missions.load();
    final globalMaxSnoozes = await _alarmSettings.getGlobalMaxSnoozes();
    final globalSnoozeEnabled = await _alarmSettings.getGlobalSnoozeEnabled();
    final wake = await _wakeSettings.load();
    final defaultAlarm = SleepAlarmTime.defaultAlarm();
    if (_disposed) return;
    _wake = wake;
    _selectedTime = TimeOfDay.fromDateTime(defaultAlarm);
    final remembered = missions.lastMode;
    _selectedMode =
        remembered == SleepMonitoringMode.alarmWithMission && !missionReady
        ? SleepMonitoringMode.alarmWithoutMission
        : remembered;
    _globalMaxSnoozes = globalMaxSnoozes;
    _globalSnoozeEnabled = globalSnoozeEnabled;
    _loading = false;
    _notify();
  }

  /// App returned to the foreground: refresh mission config and native state.
  Future<void> onResumed() async {
    if (!service.isSupported) return;
    unawaited(reloadMission());
    unawaited(service.resync().then((_) => service.getAlarmCapabilities()));
  }

  Future<void> reloadMission() async {
    await missions.load();
    if (_disposed) return;
    if (_selectedMode == SleepMonitoringMode.alarmWithMission &&
        !missions.config.isReady) {
      _selectedMode = SleepMonitoringMode.alarmWithoutMission;
      _notify();
      await missions.setLastMode(_selectedMode);
      return;
    }
    _notify();
  }

  /// Re-reads mission and snooze defaults after the sleep settings closed.
  Future<void> reloadAfterSettings() async {
    await reloadMission();
    final maxSnoozes = await _alarmSettings.getGlobalMaxSnoozes();
    final snoozeEnabled = await _alarmSettings.getGlobalSnoozeEnabled();
    final wake = await _wakeSettings.load();
    if (_disposed) return;
    _wake = wake;
    _globalMaxSnoozes = maxSnoozes;
    _globalSnoozeEnabled = snoozeEnabled;
    _notify();
  }

  void _onServiceChanged() {
    final state = service.state;
    final justDismissed = state.alarmDismissed && !_alarmWasDismissed;
    _alarmWasDismissed = state.alarmDismissed;
    final sessionId = state.sessionId;
    if (justDismissed &&
        !state.isActive &&
        state.endReason == 'alarm' &&
        sessionId != null &&
        service.claimAlarmResult(sessionId)) {
      _pendingAlarmResultId = sessionId;
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        onAlarmResultReady?.call();
      }
    }
    _notify();
  }

  /// Imports pending native sessions, then hands the finished alarm night's id
  /// to [show] (which navigates to the result screen).
  Future<void> openPendingAlarmResult(
    Future<void> Function(String sessionId) show,
  ) async {
    final sessionId = _pendingAlarmResultId;
    if (_disposed || sessionId == null || _openingResult) return;
    _openingResult = true;
    try {
      await service.recoverPendingSessions();
      if (_disposed) return;
      _pendingAlarmResultId = null;
      // A night discarded or deleted meanwhile has no result to show.
      if (!await service.hasSession(sessionId) || _disposed) return;
      await show(sessionId);
    } finally {
      _openingResult = false;
    }
  }

  // ------------------------------------------------------------------
  // Mode and wake time
  // ------------------------------------------------------------------

  Future<void> selectMode(SleepMonitoringMode mode) async {
    if (_disposed || mode == _selectedMode) return;
    _selectedMode = mode;
    _notify();
    await missions.setLastMode(mode);
  }

  /// Changes the smart window or its sensitivity for this and later nights.
  Future<void> updateWakeSettings(AlarmWakeSettings value) async {
    if (_disposed || value == _wake) return;
    _wake = value;
    _notify();
    await _wakeSettings.save(value);
  }

  bool get canChooseAlarmTime =>
      _selectedMode.hasAlarm || service.state.mode.hasAlarm;

  /// Time the picker should open on: the running alarm, else the selection.
  TimeOfDay get pickerInitialTime {
    final stateAlarm = service.state.alarmAt?.toLocal();
    return stateAlarm == null
        ? _selectedTime
        : TimeOfDay(hour: stateAlarm.hour, minute: stateAlarm.minute);
  }

  /// Applies a time chosen in the picker: updates the native alarm while a
  /// night is being monitored, otherwise just remembers it for the next start.
  Future<AlarmTimeResult> applyPickedAlarmTime(TimeOfDay picked) async {
    final alarmAt = SleepAlarmTime.nextOccurrence(picked);
    if (!SleepAlarmTime.isWithinMonitoringWindow(alarmAt)) {
      return AlarmTimeResult.invalidWindow;
    }
    if (service.isMonitoring) {
      _setBusy(true);
      final updated = await service.updateAlarm(alarmAt);
      _setBusy(false);
      return updated ? AlarmTimeResult.updated : AlarmTimeResult.updateFailed;
    }
    _selectedTime = picked;
    _notify();
    return AlarmTimeResult.selected;
  }

  AlarmShiftResult shiftAlarmTime(int minutes) {
    if (!_selectedMode.hasAlarm) return AlarmShiftResult.ignored;
    final shifted = SleepAlarmTime.nextOccurrence(
      _selectedTime,
    ).add(Duration(minutes: minutes));
    if (!SleepAlarmTime.isWithinMonitoringWindow(shifted)) {
      return AlarmShiftResult.invalidWindow;
    }
    _selectedTime = TimeOfDay.fromDateTime(shifted);
    _notify();
    return AlarmShiftResult.shifted;
  }

  // ------------------------------------------------------------------
  // Session actions
  // ------------------------------------------------------------------

  /// Checks permissions and starts monitoring. Busy while it runs.
  Future<SleepStartResult> start(DateTime? alarmAt) async {
    if (_selectedMode.hasAlarm &&
        (alarmAt == null ||
            !SleepAlarmTime.isWithinMonitoringWindow(alarmAt))) {
      return SleepStartResult.invalidWindow;
    }
    _setBusy(true);
    try {
      var granted = service.state.microphoneGranted;
      if (!granted) granted = await service.requestMicrophonePermission();
      if (!granted) return SleepStartResult.microphoneDenied;

      final notificationsGranted = await NotificationService.instance
          .requestPermission();
      if (!notificationsGranted) return SleepStartResult.notificationsDenied;

      if (_selectedMode.hasAlarm) {
        final capabilities = await service.getAlarmCapabilities();
        if (capabilities['exactAlarmGranted'] != true) {
          await service.requestExactAlarmPermission();
          return SleepStartResult.exactAlarmRequired;
        }
      }

      if (_selectedMode.requiresMission && !missions.config.isReady) {
        return SleepStartResult.missionUnavailable;
      }

      // The ringing service reads the volume rise natively.
      await _wakeSettings.syncNative(_wake);
      final started = await service.startMonitoring(
        alarmAt: alarmAt,
        mode: _selectedMode,
        mission: missions.config,
        maxSnoozes: _globalSnoozeEnabled ? _globalMaxSnoozes : 0,
        smartWindowMinutes: _selectedMode.hasAlarm ? _wake.windowMinutes : 0,
        smartThreshold: _wake.sensitivity.threshold,
      );
      return started ? SleepStartResult.started : SleepStartResult.failed;
    } finally {
      _setBusy(false);
    }
  }

  /// Stops monitoring, then hands the session id to [showResult] while the
  /// screen stays busy.
  Future<void> stop(Future<void> Function(String sessionId) showResult) async {
    final sessionId = service.state.sessionId;
    _setBusy(true);
    try {
      await service.stopMonitoring();
      if (_disposed || sessionId == null) return;
      await showResult(sessionId);
    } finally {
      _setBusy(false);
    }
  }

  Future<void> discard() async {
    _setBusy(true);
    await service.discardSession();
    _setBusy(false);
  }

  /// Answers a pending alarm: a snooze without mission is dismissed here;
  /// otherwise the alarm screen opens (silently during a snooze, so its
  /// mission can be completed early). Returns whether the native call
  /// succeeded.
  Future<bool> handlePendingAlarm() async {
    if (_isBusy) return true;
    _setBusy(true);
    final state = service.state;
    final succeeded = state.isAlarmSnoozing && !state.mode.requiresMission
        ? await service.dismissSnoozedAlarm()
        : await service.openAlarmScreen();
    if (!succeeded && !_disposed) {
      // The caller shows the error; refresh the native state meanwhile.
      await service.getState();
    }
    _setBusy(false);
    return succeeded;
  }

  void _setBusy(bool value) {
    _isBusy = value;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    service.removeListener(_onServiceChanged);
    super.dispose();
  }
}
