import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/sleep_monitor_mode.dart';
import 'package:workout_notes/models/sleep_monitor_state.dart';
import 'package:workout_notes/models/sleep_stage_type.dart';
import 'package:workout_notes/screens/sleep/sleep_monitor_controller.dart';
import 'package:workout_notes/utils/sleep_alarm_time.dart';
import 'package:workout_notes/widgets/sleep/monitor/monitor_alarm_cards.dart';
import 'package:workout_notes/widgets/sleep/monitor/monitor_mode_widgets.dart';
import 'package:workout_notes/widgets/sleep/monitor/monitor_status_widgets.dart';
import 'package:workout_notes/widgets/sleep/monitor/sleep_monitor_texts.dart';
import 'package:workout_notes/widgets/ui/second_ticker.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Body of the sleep monitor while idle: wake time, mode picker, tips and any
/// permission/validity warnings.
class SleepMonitorReadyContent extends StatelessWidget {
  const SleepMonitorReadyContent({
    super.key,
    required this.controller,
    required this.alarmAt,
    required this.onChooseAlarmTime,
    required this.onShiftAlarmTime,
    required this.onShowModePicker,
  });

  final SleepMonitorController controller;
  final DateTime? alarmAt;
  final VoidCallback onChooseAlarmTime;
  final ValueChanged<int> onShiftAlarmTime;
  final VoidCallback onShowModePicker;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final state = controller.state;
    final selectedMode = controller.selectedMode;
    final alarmAt = this.alarmAt;
    final valid =
        alarmAt == null || SleepAlarmTime.isWithinMonitoringWindow(alarmAt);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MonitorNightHero(
          icon: Icons.nightlight_round,
          title: loc.sleepMonitorReady,
          subtitle: selectedMode.hasAlarm
              ? loc.sleepAlarmSectionTitle
              : loc.sleepMonitorModeOnly,
        ),
        const SizedBox(height: 16),
        if (alarmAt != null)
          AlarmClockCard(
            time: formatMonitorTime(context, alarmAt),
            date: formatModeDate(context, alarmAt),
            remaining: formatMonitorRemaining(alarmAt),
            sectionTitle: loc.sleepMonitorReadyWakeTime,
            changeLabel: loc.sleepMonitorChangeWakeTime,
            onTap: onChooseAlarmTime,
            onEarlier: () => onShiftAlarmTime(-15),
            onLater: () => onShiftAlarmTime(15),
          )
        else
          MonitoringOnlyCard(
            title: loc.sleepMonitorModeOnly,
            body: loc.sleepMonitorModeOnlyBody,
          ),
        const SizedBox(height: 18),
        ModeSelectorCard(
          sectionLabel: loc.sleepMonitorModeSection,
          title: sleepMonitorModeTitle(loc, selectedMode),
          body: controller.isModeLocked(selectedMode)
              ? loc.sleepMonitorModeMissionUnavailable
              : sleepMonitorModeBody(loc, selectedMode),
          icon: modeIcon(selectedMode),
          onTap: onShowModePicker,
        ),
        const SizedBox(height: 10),
        TipsCard(
          title: loc.sleepMonitorTipsTitle,
          tips: [
            (
              Icons.phone_android_rounded,
              loc.sleepMonitorPlacementTitle,
              loc.sleepMonitorPlacementBody,
            ),
            if (selectedMode.hasAlarm)
              (
                Icons.snooze_rounded,
                loc.sleepMonitorSnoozesTitle,
                !controller.globalSnoozeEnabled ||
                        controller.globalMaxSnoozes == 0
                    ? loc.sleepMonitorSnoozesDisabled
                    : loc.sleepMonitorSnoozesConfigured(
                        controller.globalMaxSnoozes,
                      ),
              ),
          ],
        ),
        if (!valid) ...[
          const SizedBox(height: 10),
          AppBanner.warning(
            loc.sleepAlarmInvalidWindow,
            icon: Icons.schedule_rounded,
          ),
        ],
        if (selectedMode.hasAlarm && !state.exactAlarmGranted) ...[
          const SizedBox(height: 10),
          PermissionNotice(
            text: loc.sleepAlarmExactPermission,
            action: loc.sleepAlarmEnableExactPermission,
            onPressed: controller.service.requestExactAlarmPermission,
          ),
        ],
        if (selectedMode.hasAlarm &&
            state.exactAlarmGranted &&
            !state.fullScreenIntentGranted) ...[
          const SizedBox(height: 10),
          PermissionNotice(
            text: loc.sleepAlarmFullScreenLimited,
            action: loc.sleepAlarmEnableFullScreen,
            onPressed: controller.service.requestFullScreenPermission,
          ),
        ],
      ],
    );
  }
}

/// Body of the sleep monitor while a snoozed alarm waits to be dismissed.
class SleepMonitorSnoozingContent extends StatelessWidget {
  const SleepMonitorSnoozingContent({
    super.key,
    required this.state,
    required this.alarmAt,
  });

  final SleepMonitorState state;
  final DateTime? alarmAt;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final alarmAt = this.alarmAt;
    final maximum = state.maxSnoozes <= 0 ? 1 : state.maxSnoozes;
    final progress = (state.snoozeCount / maximum).clamp(0.0, 1.0).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MonitorNightHero(
          icon: Icons.snooze_rounded,
          title: loc.sleepMonitorAlarmSnoozingTitle,
          subtitle: alarmAt == null
              ? loc.sleepAlarmSectionTitle
              : loc.alarmSnoozingUntil(formatMonitorTime(context, alarmAt)),
        ),
        const SizedBox(height: 16),
        Card(
          key: const Key('sleep-monitor-snoozing-card'),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      state.mode.requiresMission
                          ? Icons.qr_code_scanner_rounded
                          : Icons.alarm_off_rounded,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        state.mode.requiresMission
                            ? loc.sleepMonitorMissionPending
                            : loc.sleepMonitorAlarmSnoozingTitle,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                LinearProgressIndicator(value: progress),
                const SizedBox(height: 8),
                Text(
                  loc.alarmSnoozeProgress(state.snoozeCount, state.maxSnoozes),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 14),
                Text(
                  state.mode.requiresMission
                      ? loc.sleepMonitorSnoozingMissionBody
                      : loc.sleepMonitorSnoozingDismissBody,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
        if (state.errorCode != null) ...[
          const SizedBox(height: 14),
          Text(
            sleepMonitorErrorMessage(loc, state.errorCode),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }
}

/// Body of the sleep monitor while a night is being recorded.
class SleepMonitorRunningContent extends StatelessWidget {
  const SleepMonitorRunningContent({
    super.key,
    required this.controller,
    required this.alarmAt,
    required this.onChooseAlarmTime,
    required this.onDiscard,
  });

  final SleepMonitorController controller;
  final DateTime? alarmAt;
  final VoidCallback onChooseAlarmTime;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final state = controller.state;
    final alarmAt = this.alarmAt;
    final isBusy = controller.isBusy;
    final liveDecision = controller.service.liveDecision;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MonitorNightHero(
          icon: Icons.graphic_eq_rounded,
          title: loc.sleepMonitorRunning,
          subtitle: alarmAt == null
              ? loc.sleepMonitorModeOnly
              : loc.sleepAlarmScheduledFor(formatMonitorTime(context, alarmAt)),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                Text(
                  loc.sleepMonitorTimeMonitored,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                // Only the clock rebuilds every second, not the whole screen.
                SecondTicker(
                  builder: (context) => Text(
                    formatMonitorDuration(state.elapsed),
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                if (alarmAt != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxWidth < 320;
                        final remaining = Row(
                          children: [
                            const Icon(Icons.alarm_rounded),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    loc.sleepAlarmRemaining,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelMedium,
                                  ),
                                  SecondTicker(
                                    builder: (context) => Text(
                                      formatMonitorRemaining(
                                        alarmAt,
                                        withSeconds: true,
                                      ),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                        final changeButton = TextButton(
                          onPressed: isBusy ? null : onChooseAlarmTime,
                          child: Text(loc.sleepAlarmChange),
                        );
                        return compact
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  remaining,
                                  Align(
                                    alignment: AlignmentDirectional.centerEnd,
                                    child: changeButton,
                                  ),
                                ],
                              )
                            : Row(children: [remaining, changeButton]);
                      },
                    ),
                  ),
                const SizedBox(height: 14),
                if (state.mode == SleepMonitoringMode.alarmWithMission)
                  MissionStatusBanner(
                    label: loc.sleepMonitorMissionPending,
                    body: loc.sleepMonitorModeAlarmWithMissionBody,
                  ),
                if (state.mode == SleepMonitoringMode.alarmWithMission)
                  const SizedBox(height: 12),
                PermissionRow(
                  granted: state.microphoneGranted,
                  label: loc.sleepMonitorMicrophone,
                ),
                const SizedBox(height: 12),
                LiveSignal(
                  segment: state.latestSegment,
                  noiseScore: state.currentNoiseScore,
                  loc: loc,
                ),
                if (liveDecision != null) ...[
                  const SizedBox(height: 8),
                  Text(switch (liveDecision.epoch.stage) {
                    SleepStageType.awake => loc.sleepLiveProbablyAwake,
                    SleepStageType.sleeping ||
                    SleepStageType.deep => loc.sleepLiveProbablyAsleep,
                    SleepStageType.unknown => loc.sleepLiveUncertain,
                  }),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (state.mode == SleepMonitoringMode.alarmWithMission)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              loc.sleepMonitorProtectedStopBody,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        OutlinedButton.icon(
          onPressed: isBusy ? null : onDiscard,
          icon: const Icon(Icons.delete_outline),
          label: Text(loc.sleepMonitorDiscard),
        ),
        if (state.errorCode != null) ...[
          const SizedBox(height: 14),
          Text(
            sleepMonitorErrorMessage(loc, state.errorCode),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }
}
