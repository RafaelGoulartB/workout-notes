import 'dart:async';

import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/sleep_monitor_mode.dart';
import 'package:workout_notes/models/sleep_monitor_state.dart';
import 'package:workout_notes/screens/sleep/sleep_monitor_controller.dart';
import 'package:workout_notes/screens/sleep/sleep_monitor_result_screen.dart';
import 'package:workout_notes/screens/sleep/sleep_settings_screen.dart';
import 'package:workout_notes/widgets/sleep/monitor/monitor_mode_widgets.dart';
import 'package:workout_notes/widgets/sleep/monitor/monitor_sections.dart';
import 'package:workout_notes/widgets/sleep/monitor/monitor_status_widgets.dart';
import 'package:workout_notes/widgets/sleep/monitor/sleep_monitor_texts.dart';
import 'package:workout_notes/widgets/sleep/monitor/smart_wake_widgets.dart';
import 'package:workout_notes/widgets/ui/load_error_view.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

class SleepMonitorScreen extends StatefulWidget {
  const SleepMonitorScreen({super.key});

  @override
  State<SleepMonitorScreen> createState() => _SleepMonitorScreenState();
}

class _SleepMonitorScreenState extends State<SleepMonitorScreen>
    with WidgetsBindingObserver {
  final _controller = SleepMonitorController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.onAlarmResultReady = _openPendingAlarmResult;
    _controller.initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _controller.service.isSupported) {
      _controller.onResumed();
      _openPendingAlarmResult();
    }
  }

  Future<void> _openPendingAlarmResult() {
    return _controller.openPendingAlarmResult((sessionId) async {
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SleepMonitorResultScreen(sessionId: sessionId),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => _buildScreen(context),
    );
  }

  Widget _buildScreen(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final controller = _controller;
    final state = controller.state;
    final viewport = MediaQuery.sizeOf(context);
    final compact = viewport.width < 380 || viewport.height < 650;
    if (!state.supported) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              loc.sleepMonitorAndroidOnly,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final active = state.isActive;
    // A new night takes over; otherwise the last alarm waits for an answer.
    final pending = !active && state.isAlarmPending;
    final alarmAt = controller.alarmAtFor(state);
    final isBusy = controller.isBusy;
    final horizontal = compact ? 16.0 : 24.0;
    final content = CustomScrollView(
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontal),
            child: pending
                ? SleepMonitorAlarmContent(state: state, alarmAt: alarmAt)
                : active
                ? SleepMonitorRunningContent(
                    controller: controller,
                    alarmAt: alarmAt,
                    onChooseAlarmTime: _chooseAlarmTime,
                  )
                : SleepMonitorReadyContent(
                    controller: controller,
                    alarmAt: alarmAt,
                    onChooseAlarmTime: _chooseAlarmTime,
                    onShiftAlarmTime: _shiftAlarmTime,
                    onShowModePicker: _showModePicker,
                    onShowSmartWake: _showSmartWake,
                  ),
          ),
        ),
      ],
    );
    final scaffold = Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        toolbarHeight: compact ? 48 : null,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        actions: [
          if (!controller.loading && !controller.loadFailed && !active && !pending)
            IconButton(
              tooltip: loc.sleepMonitorTipsTitle,
              icon: const Icon(Icons.lightbulb_outline_rounded),
              onPressed: _showTips,
            ),
          if (active)
            PopupMenuButton<void>(
              key: const Key('sleep-monitor-menu'),
              enabled: !isBusy,
              itemBuilder: (context) => [
                PopupMenuItem(
                  onTap: () => unawaited(_discard()),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.delete_outline),
                    title: Text(loc.sleepMonitorDiscard),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: controller.loading
          ? const Center(child: CircularProgressIndicator())
          : controller.loadFailed
          ? LoadErrorView(onRetry: controller.initialize)
          : MonitorNightBackground(
              dim: active,
              child: SafeArea(bottom: false, child: content),
            ),
      bottomNavigationBar: controller.loading || controller.loadFailed
          ? null
          : SafeArea(
              minimum: EdgeInsets.fromLTRB(
                horizontal,
                compact ? 6 : 10,
                horizontal,
                compact ? 8 : 16,
              ),
              child: SizedBox(
                height: compact ? 52 : 58,
                child: pending
                    ? FilledButton.icon(
                        key: const Key('sleep-monitor-alarm-action'),
                        onPressed: isBusy ? null : _handlePendingAlarm,
                        icon: _busyIcon(
                          state.mode.requiresMission
                              ? Icons.qr_code_scanner_rounded
                              : Icons.alarm_off_rounded,
                        ),
                        label: Text(_pendingAlarmLabel(loc, state)),
                      )
                    : active
                    // Tonal, not a bright fill: this one is seen in the dark.
                    ? FilledButton.tonalIcon(
                        onPressed: isBusy ? null : _stop,
                        icon: _busyIcon(Icons.stop_rounded),
                        label: Text(
                          state.mode == SleepMonitoringMode.alarmWithMission
                              ? loc.sleepMonitorProtectedStop
                              : loc.sleepMonitorFinish,
                        ),
                      )
                    : FilledButton.icon(
                        onPressed: controller.canStart(alarmAt)
                            ? () => _start(alarmAt)
                            : null,
                        icon: _busyIcon(Icons.bedtime_rounded),
                        label: Text(loc.sleepMonitorStart),
                      ),
              ),
            ),
    );
    return MonitorAutoDim(enabled: active, child: scaffold);
  }

  Widget _busyIcon(IconData fallback) => _controller.isBusy
      ? const SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
      : Icon(fallback);

  static String _pendingAlarmLabel(
    AppLocalizations loc,
    SleepMonitorState state,
  ) {
    final mission = state.mode.requiresMission;
    if (state.isAlarmRinging) {
      return mission ? loc.sleepMonitorOpenMission : loc.sleepMonitorOpenAlarm;
    }
    return mission
        ? loc.sleepMonitorCompleteMissionNow
        : loc.sleepMonitorTurnOffAlarm;
  }

  Future<void> _handlePendingAlarm() async {
    final succeeded = await _controller.handlePendingAlarm();
    if (!succeeded && mounted) {
      showAppSnack(context, AppLocalizations.of(context)!.sleepMonitorAlarmActionError);
    }
  }

  Future<void> _chooseAlarmTime() async {
    if (!_controller.canChooseAlarmTime) return;
    final picked = await showTimePicker(
      context: context,
      initialTime: _controller.pickerInitialTime,
      initialEntryMode: TimePickerEntryMode.dial,
    );
    if (picked == null || !mounted) return;
    final result = await _controller.applyPickedAlarmTime(picked);
    if (!mounted) return;
    switch (result) {
      case AlarmTimeResult.invalidWindow:
        showAppSnack(context, AppLocalizations.of(context)!.sleepAlarmInvalidWindow);
      case AlarmTimeResult.updateFailed:
        showAppSnack(
          context,
          sleepMonitorErrorMessage(
            AppLocalizations.of(context)!,
            _controller.state.errorCode,
          ),
        );
      case AlarmTimeResult.updated:
      case AlarmTimeResult.selected:
        break;
    }
  }

  void _shiftAlarmTime(int minutes) {
    if (_controller.shiftAlarmTime(minutes) == AlarmShiftResult.invalidWindow) {
      showAppSnack(context, AppLocalizations.of(context)!.sleepAlarmInvalidWindow);
    }
  }

  Future<void> _start(DateTime? alarmAt) async {
    final loc = AppLocalizations.of(context)!;
    final result = await _controller.start(alarmAt);
    if (!mounted) return;
    switch (result) {
      case SleepStartResult.started:
        break;
      case SleepStartResult.invalidWindow:
        showAppSnack(context, loc.sleepAlarmInvalidWindow);
      case SleepStartResult.microphoneDenied:
        showAppSnack(context, loc.sleepMonitorMicrophoneDenied);
      case SleepStartResult.notificationsDenied:
        showAppSnack(context, loc.sleepAlarmNotificationRequired);
      case SleepStartResult.exactAlarmRequired:
        showAppSnack(context, loc.sleepAlarmExactPermission);
      case SleepStartResult.missionUnavailable:
        showAppSnack(context, loc.sleepMonitorModeMissionUnavailable);
      case SleepStartResult.failed:
        showAppSnack(
          context,
          sleepMonitorErrorMessage(loc, _controller.service.state.errorCode),
        );
    }
  }

  Future<void> _stop() {
    return _controller.stop((sessionId) async {
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SleepMonitorResultScreen(sessionId: sessionId),
        ),
      );
    });
  }

  Future<void> _discard() async {
    final loc = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: loc.sleepMonitorDiscardTitle,
      message: loc.sleepMonitorDiscardBody,
      confirmLabel: loc.commonDiscard,
      destructive: true,
    );
    if (confirmed != true) return;
    await _controller.discard();
  }

  Future<void> _showTips() {
    return showSleepTipsSheet(
      context,
      hasAlarm: _controller.selectedMode.hasAlarm,
      snoozeEnabled: _controller.globalSnoozeEnabled,
      maxSnoozes: _controller.globalMaxSnoozes,
      smartWake: _controller.wakeSettings.smartWindowEnabled,
    );
  }

  Future<void> _showSmartWake() async {
    final selected = await showSmartWakeSheet(
      context,
      _controller.wakeSettings,
    );
    if (selected == null || !mounted) return;
    await _controller.updateWakeSettings(selected);
  }

  Future<void> _showModePicker() async {
    final selected = await showSleepModePicker(
      context,
      modeOrder: SleepMonitorController.modeOrder,
      selected: _controller.selectedMode,
      isLocked: _controller.isModeLocked,
      onLockedTap: () => unawaited(_openSleepSettings()),
    );
    if (selected == null || !mounted) return;
    await _controller.selectMode(selected);
  }

  Future<void> _openSleepSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SleepSettingsScreen()),
    );
    await _controller.reloadAfterSettings();
  }
}
