import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/sleep_monitor_mode.dart';

/// Localized text and time formatting shared by the sleep monitor screen and
/// its section widgets.

String sleepMonitorModeTitle(AppLocalizations loc, SleepMonitoringMode mode) {
  switch (mode) {
    case SleepMonitoringMode.alarmWithoutMission:
      return loc.sleepMonitorModeAlarmNoMission;
    case SleepMonitoringMode.alarmWithMission:
      return loc.sleepMonitorModeAlarmWithMission;
    case SleepMonitoringMode.monitoringOnly:
      return loc.sleepMonitorModeOnly;
  }
}

String sleepMonitorModeBody(AppLocalizations loc, SleepMonitoringMode mode) {
  switch (mode) {
    case SleepMonitoringMode.alarmWithoutMission:
      return loc.sleepMonitorModeAlarmNoMissionBody;
    case SleepMonitoringMode.alarmWithMission:
      return loc.sleepMonitorModeAlarmWithMissionBody;
    case SleepMonitoringMode.monitoringOnly:
      return loc.sleepMonitorModeOnlyBody;
  }
}

/// User-facing text for a native monitor error [code].
String sleepMonitorErrorMessage(AppLocalizations loc, String? code) {
  if (code == 'diagnostic_save_failed') return loc.sleepDiagnosticError;
  switch (code) {
    case 'microphone_permission':
    case 'microphone_denied':
      return loc.sleepMonitorMicrophoneDenied;
    case 'audio_unavailable':
    case 'audio_error':
    case 'no_audio_data':
      return loc.sleepMonitorAudioUnavailable;
    case 'already_active':
      return loc.sleepMonitorAlreadyActive;
    case 'import_failed':
    case 'recovery_failed':
      return loc.sleepMonitorImportError;
    case 'exact_alarm_denied':
      return loc.sleepAlarmExactPermission;
    case 'invalid_alarm_time':
      return loc.sleepAlarmInvalidWindow;
    case 'alarm_not_configured':
      return loc.sleepMonitorModeOnlyBody;
    case 'alarm_schedule_failed':
      return loc.sleepAlarmScheduleFailed;
    case 'mission_not_configured':
      return loc.sleepMonitorModeMissionUnavailable;
    case 'camera_denied':
    case 'camera_permission':
      return loc.sleepMissionCameraDenied;
    default:
      return loc.sleepMonitorGenericError;
  }
}

String formatMonitorTime(BuildContext context, DateTime date) =>
    MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(date));

/// `HH:mm:ss` elapsed clock.
String formatMonitorDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  return '${hours.toString().padLeft(2, '0')}:'
      '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}

/// Time left until [alarmAt], clamped at zero.
String formatMonitorRemaining(DateTime alarmAt, {bool withSeconds = false}) {
  final duration = alarmAt.difference(DateTime.now());
  final safe = duration.isNegative ? Duration.zero : duration;
  final hours = safe.inHours;
  final minutes = safe.inMinutes.remainder(60);
  if (!withSeconds) return '${hours}h ${minutes}min';
  final seconds = safe.inSeconds.remainder(60);
  return '${hours.toString().padLeft(2, '0')}:'
      '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}
