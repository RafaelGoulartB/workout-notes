import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/sleep_monitor_mode.dart';
import 'package:workout_notes/models/sleep_monitor_state.dart';
import 'package:workout_notes/models/sleep_stage_type.dart';
import 'package:workout_notes/screens/sleep/sleep_monitor_controller.dart';
import 'package:workout_notes/utils/sleep_alarm_time.dart';
import 'package:workout_notes/widgets/sleep/monitor/monitor_mode_widgets.dart';
import 'package:workout_notes/widgets/sleep/monitor/monitor_status_widgets.dart';
import 'package:workout_notes/widgets/sleep/monitor/sleep_monitor_texts.dart';
import 'package:workout_notes/widgets/sleep/monitor/sleep_sound_waves.dart';
import 'package:workout_notes/widgets/ui/second_ticker.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Body of the sleep monitor while idle: the wake time front and centre,
/// calm waves and the mode pill. Tips live in a sheet ([showSleepTipsSheet]);
/// only actionable warnings are shown inline.
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
    final theme = Theme.of(context);
    final state = controller.state;
    final selectedMode = controller.selectedMode;
    final alarmAt = this.alarmAt;
    final valid =
        alarmAt == null || SleepAlarmTime.isWithinMonitoringWindow(alarmAt);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(flex: 3),
        if (alarmAt != null) ...[
          MonitorCaption(loc.sleepMonitorReadyWakeTime),
          const SizedBox(height: 4),
          Row(
            children: [
              IconButton.outlined(
                key: const Key('sleep-monitor-earlier'),
                tooltip: loc.sleepAlarmShiftEarlier,
                onPressed: () => onShiftAlarmTime(-15),
                icon: const Icon(Icons.remove_rounded),
              ),
              Expanded(
                child: MonitorBigTime(
                  key: const Key('sleep-monitor-wake-time'),
                  time: formatMonitorTime(context, alarmAt),
                  tooltip: loc.sleepMonitorChangeWakeTime,
                  onTap: onChooseAlarmTime,
                ),
              ),
              IconButton.outlined(
                key: const Key('sleep-monitor-later'),
                tooltip: loc.sleepAlarmShiftLater,
                onPressed: () => onShiftAlarmTime(15),
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          MonitorCaption(
            loc.sleepMonitorWakeIn(formatMonitorRemaining(alarmAt)),
            emphasis: true,
          ),
        ] else ...[
          Icon(
            Icons.graphic_eq_rounded,
            size: 56,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            sleepMonitorModeTitle(loc, selectedMode),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const Spacer(flex: 2),
        const SleepSoundWaves(height: 72),
        const Spacer(flex: 2),
        Center(
          child: ModePill(
            label: sleepMonitorModeTitle(loc, selectedMode),
            icon: modeIcon(selectedMode),
            onTap: onShowModePicker,
          ),
        ),
        if (!valid) ...[
          const SizedBox(height: 12),
          AppBanner.warning(
            loc.sleepAlarmInvalidWindow,
            icon: Icons.schedule_rounded,
          ),
        ],
        if (selectedMode.hasAlarm && !state.exactAlarmGranted) ...[
          const SizedBox(height: 12),
          PermissionNotice(
            text: loc.sleepAlarmExactPermission,
            action: loc.sleepAlarmEnableExactPermission,
            onPressed: controller.service.requestExactAlarmPermission,
          ),
        ],
        if (selectedMode.hasAlarm &&
            state.exactAlarmGranted &&
            !state.fullScreenIntentGranted) ...[
          const SizedBox(height: 12),
          PermissionNotice(
            text: loc.sleepAlarmFullScreenLimited,
            action: loc.sleepAlarmEnableFullScreen,
            onPressed: controller.service.requestFullScreenPermission,
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Bottom sheet with the bedside tips (placement and snoozes).
Future<void> showSleepTipsSheet(
  BuildContext context, {
  required bool hasAlarm,
  required bool snoozeEnabled,
  required int maxSnoozes,
}) {
  final loc = AppLocalizations.of(context)!;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: TipsCard(
          title: loc.sleepMonitorTipsTitle,
          tips: [
            (
              Icons.phone_android_rounded,
              loc.sleepMonitorPlacementTitle,
              loc.sleepMonitorPlacementBody,
            ),
            if (hasAlarm)
              (
                Icons.snooze_rounded,
                loc.sleepMonitorSnoozesTitle,
                !snoozeEnabled || maxSnoozes == 0
                    ? loc.sleepMonitorSnoozesDisabled
                    : loc.sleepMonitorSnoozesConfigured(maxSnoozes),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Body of the sleep monitor once the night ended and its alarm still needs
/// an answer: ringing now, or snoozed until the next ring. The mission (or the
/// dismissal) is always one tap away, even before the snooze rings again.
class SleepMonitorAlarmContent extends StatelessWidget {
  const SleepMonitorAlarmContent({
    super.key,
    required this.state,
    required this.alarmAt,
  });

  final SleepMonitorState state;
  final DateTime? alarmAt;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final ringing = state.isAlarmRinging;
    final mission = state.mode.requiresMission;
    final alarmAt = this.alarmAt;
    return Column(
      key: const Key('sleep-monitor-alarm'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(flex: 3),
        Center(
          child: Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.primary.withAlpha(ringing ? 46 : 26),
            ),
            child: Icon(
              ringing ? Icons.alarm_rounded : Icons.snooze_rounded,
              size: 40,
              color: colors.primary,
            ),
          ),
        ),
        const SizedBox(height: 20),
        MonitorCaption(
          ringing ? loc.sleepMonitorAlarmRinging : loc.sleepMonitorSnoozedUntil,
        ),
        const SizedBox(height: 4),
        if (ringing)
          SecondTicker(
            builder: (context) => MonitorBigTime(
              time: formatMonitorTime(context, DateTime.now()),
            ),
          )
        else if (alarmAt != null) ...[
          MonitorBigTime(time: formatMonitorTime(context, alarmAt)),
          SecondTicker(
            builder: (context) => MonitorCaption(
              loc.sleepMonitorWakeIn(formatMonitorRemaining(alarmAt)),
              emphasis: true,
            ),
          ),
        ],
        const Spacer(flex: 2),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            if (state.snoozeCount > 0)
              AppPill(
                icon: Icons.snooze_rounded,
                label: loc.alarmSnoozeProgress(
                  state.snoozeCount,
                  state.maxSnoozes,
                ),
              ),
            if (mission)
              AppPill(
                icon: Icons.qr_code_2_rounded,
                label: loc.sleepMonitorMissionPending,
                color: colors.tertiary,
              ),
          ],
        ),
        if (!ringing) ...[
          const SizedBox(height: 16),
          MonitorCaption(
            mission
                ? loc.sleepMonitorSnoozingMissionBody
                : loc.sleepMonitorSnoozingDismissBody,
          ),
        ],
        if (state.errorCode != null) ...[
          const SizedBox(height: 12),
          Text(
            sleepMonitorErrorMessage(loc, state.errorCode),
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.error),
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Body of the sleep monitor while a night is being recorded: the wake time,
/// live waves following the microphone and one line of status. Meant to be
/// glanced at in the dark, so everything else stays out of the way.
class SleepMonitorRunningContent extends StatelessWidget {
  const SleepMonitorRunningContent({
    super.key,
    required this.controller,
    required this.alarmAt,
    required this.onChooseAlarmTime,
  });

  final SleepMonitorController controller;
  final DateTime? alarmAt;
  final VoidCallback onChooseAlarmTime;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final state = controller.state;
    final alarmAt = this.alarmAt;
    final elapsed = SecondTicker(
      builder: (context) => Text(
        formatMonitorDuration(state.elapsed),
        key: const Key('sleep-monitor-elapsed'),
        style: theme.textTheme.labelLarge?.copyWith(
          color: colors.onSurfaceVariant,
          fontFeatures: AppUi.tabular,
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(flex: 3),
        if (alarmAt != null) ...[
          MonitorCaption(loc.sleepMonitorReadyWakeTime),
          const SizedBox(height: 4),
          MonitorBigTime(
            key: const Key('sleep-monitor-wake-time'),
            time: formatMonitorTime(context, alarmAt),
            tooltip: loc.sleepAlarmChange,
            onTap: controller.isBusy ? null : onChooseAlarmTime,
          ),
          SecondTicker(
            builder: (context) => MonitorCaption(
              loc.sleepMonitorWakeIn(formatMonitorRemaining(alarmAt)),
              emphasis: true,
            ),
          ),
        ] else ...[
          MonitorCaption(loc.sleepMonitorTimeMonitored),
          const SizedBox(height: 4),
          SecondTicker(
            builder: (context) =>
                MonitorBigTime(time: formatMonitorDuration(state.elapsed)),
          ),
        ],
        const Spacer(flex: 2),
        SleepSoundWaves(height: 140, sampler: controller.service.getLiveLevel),
        const SizedBox(height: 12),
        MonitorCaption(_statusLine(loc, controller)),
        const Spacer(flex: 3),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            if (alarmAt != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.fiber_manual_record_rounded,
                    size: 10,
                    color: colors.error.withAlpha(200),
                  ),
                  const SizedBox(width: 6),
                  elapsed,
                ],
              ),
            if (state.mode == SleepMonitoringMode.alarmWithMission)
              AppPill(
                icon: Icons.qr_code_2_rounded,
                label: loc.sleepMonitorMissionPending,
                color: colors.tertiary,
              ),
          ],
        ),
        if (!state.microphoneGranted) ...[
          const SizedBox(height: 12),
          AppBanner.warning(
            loc.sleepMonitorMicrophoneDenied,
            icon: Icons.mic_off_rounded,
          ),
        ],
        if (state.errorCode != null) ...[
          const SizedBox(height: 12),
          Text(
            sleepMonitorErrorMessage(loc, state.errorCode),
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.error),
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }

  /// One short line under the waves: the provisional live estimate once the
  /// engine has one, otherwise the state of the audio signal.
  static String _statusLine(
    AppLocalizations loc,
    SleepMonitorController controller,
  ) {
    final decision = controller.service.liveDecision;
    if (decision != null) {
      return switch (decision.epoch.stage) {
        SleepStageType.awake => loc.sleepLiveProbablyAwake,
        SleepStageType.sleeping ||
        SleepStageType.deep => loc.sleepLiveProbablyAsleep,
        SleepStageType.unknown => loc.sleepLiveUncertain,
      };
    }
    final segment = controller.state.latestSegment;
    if (segment == null) return loc.sleepMonitorListening;
    if (segment.isInvalid) return loc.sleepMonitorInvalidSignal;
    return loc.sleepMonitorListening;
  }
}
