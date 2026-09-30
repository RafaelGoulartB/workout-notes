import 'dart:async';

import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/sleep_monitor_mode.dart';
import 'package:workout_notes/screens/workout/sleep_monitor_controller.dart';
import 'package:workout_notes/screens/workout/sleep_monitor_result_screen.dart';
import 'package:workout_notes/screens/workout/sleep_settings_screen.dart';
import 'package:workout_notes/widgets/sleep/monitor/monitor_mode_widgets.dart';
import 'package:workout_notes/widgets/sleep/monitor/monitor_sections.dart';
import 'package:workout_notes/widgets/sleep/monitor/monitor_status_widgets.dart';
import 'package:workout_notes/widgets/sleep/monitor/sleep_monitor_texts.dart';
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
    final snoozing = state.isAlarmSnoozing;
    final alarmAt = controller.alarmAtFor(state);
    final isBusy = controller.isBusy;
    return Scaffold(
      appBar: AppBar(toolbarHeight: compact ? 48 : null),
      body: controller.loading
          ? const Center(child: CircularProgressIndicator())
          : MonitorNightBackground(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  compact ? 12 : 16,
                  compact ? 8 : 12,
                  compact ? 12 : 16,
                  compact ? 16 : 28,
                ),
                children: [
                  snoozing
                      ? SleepMonitorSnoozingContent(
                          state: state,
                          alarmAt: alarmAt,
                        )
                      : active
                      ? SleepMonitorRunningContent(
                          controller: controller,
                          alarmAt: alarmAt,
                          onChooseAlarmTime: _chooseAlarmTime,
                          onDiscard: _discard,
                        )
                      : SleepMonitorReadyContent(
                          controller: controller,
                          alarmAt: alarmAt,
                          onChooseAlarmTime: _chooseAlarmTime,
                          onShiftAlarmTime: _shiftAlarmTime,
                          onShowModePicker: _showModePicker,
                        ),
                ],
              ),
            ),
      bottomNavigationBar: controller.loading
          ? null
          : SafeArea(
              minimum: EdgeInsets.fromLTRB(
                compact ? 12 : 16,
                compact ? 6 : 10,
                compact ? 12 : 16,
                compact ? 8 : 12,
              ),
              child: SizedBox(
                height: compact ? 52 : 56,
                child: snoozing
                    ? FilledButton.icon(
                        onPressed: isBusy ? null : _handleSnoozedAlarm,
                        icon: _busyIcon(
                          state.mode.requiresMission
                              ? Icons.qr_code_scanner_rounded
                              : Icons.alarm_off_rounded,
                        ),
                        label: Text(
                          state.mode.requiresMission
                              ? loc.alarmOpenMissionNow
                              : loc.alarmDismissSnooze,
                        ),
                      )
                    : active
                    ? FilledButton.icon(
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
  }

  Widget _busyIcon(IconData fallback) => _controller.isBusy
      ? const SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
      : Icon(fallback);

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _handleSnoozedAlarm() async {
    final succeeded = await _controller.handleSnoozedAlarm();
    if (!succeeded && mounted) {
      _showMessage(AppLocalizations.of(context)!.alarmSnoozeActionError);
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
        _showMessage(AppLocalizations.of(context)!.sleepAlarmInvalidWindow);
      case AlarmTimeResult.updateFailed:
        _showMessage(
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
      _showMessage(AppLocalizations.of(context)!.sleepAlarmInvalidWindow);
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
        _showMessage(loc.sleepAlarmInvalidWindow);
      case SleepStartResult.microphoneDenied:
        _showMessage(loc.sleepMonitorMicrophoneDenied);
      case SleepStartResult.notificationsDenied:
        _showMessage(loc.sleepAlarmNotificationRequired);
      case SleepStartResult.exactAlarmRequired:
        _showMessage(loc.sleepAlarmExactPermission);
      case SleepStartResult.missionUnavailable:
        _showMessage(loc.sleepMonitorModeMissionUnavailable);
      case SleepStartResult.failed:
        _showMessage(
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
    );
    if (confirmed != true) return;
    await _controller.discard();
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
