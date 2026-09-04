import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/traditional_alarm.dart';
import '../models/traditional_alarm_runtime_state.dart';
import '../repositories/traditional_alarm_repository.dart';
import '../repositories/settings_repository.dart';
import 'notification_service.dart';
import 'sleep_mission_service.dart';
import 'sleep_monitor_service.dart';

/// Persists alarm definitions in SQLite and mirrors the runnable snapshot to
/// Android. The native side owns ringing and repeat scheduling while the app is
/// closed; this service reconciles it whenever the app opens.
class TraditionalAlarmService extends ChangeNotifier {
  TraditionalAlarmService._();
  static final TraditionalAlarmService instance = TraditionalAlarmService._();
  static const _channel = MethodChannel(
    'workout_notes/traditional_alarms/methods',
  );

  final TraditionalAlarmRepository _repository = TraditionalAlarmRepository();
  final SettingsRepository _settings = SettingsRepository();
  List<TraditionalAlarm> _alarms = const [];
  List<TraditionalAlarm> get alarms => List.unmodifiable(_alarms);

  Map<String, TraditionalAlarmRuntimeState> _runtimeStates = const {};
  TraditionalAlarmRuntimeState? runtimeStateFor(String alarmId) =>
      _runtimeStates[alarmId];

  Future<void> initialize() async {
    await reconcile();
  }

  /// Syncs native schedules created while Flutter was closed, then schedules
  /// only database alarms that do not yet have a native snapshot.
  Future<void> reconcile() async {
    await refresh();
    if (!_isAndroid) {
      _runtimeStates = const {};
      return;
    }
    try {
      final states =
          await _channel.invokeListMethod<dynamic>('states') ?? const [];
      final nativeIds = <String>{};
      final runtimeStates = <String, TraditionalAlarmRuntimeState>{};
      for (final value in states) {
        if (value is! Map) continue;
        final map = Map<String, dynamic>.from(value);
        final id = map['id'] as String?;
        final epoch = map['alarm_at_epoch_ms'];
        if (id == null || epoch is! num) continue;
        nativeIds.add(id);
        runtimeStates[id] = TraditionalAlarmRuntimeState.fromMap(map);
        await _repository.updateNativeSchedule(
          id,
          enabled: map['enabled'] == true,
          nextTriggerAt: DateTime.fromMillisecondsSinceEpoch(epoch.toInt()),
        );
      }
      _runtimeStates = runtimeStates;
      await refresh();
      for (final alarm in _alarms.where(
        (alarm) => alarm.enabled && !nativeIds.contains(alarm.id),
      )) {
        await _scheduleBestEffort(alarm);
      }
      await _channel.invokeMethod<void>('restore');
    } on MissingPluginException {
      _runtimeStates = const {};
      // The alarm manager is intentionally an Android enhancement.
    }
  }

  Future<void> refresh() async {
    _alarms = await _repository.getAll();
    notifyListeners();
  }

  Future<TraditionalAlarm> create({
    required int hour,
    required int minute,
    required List<int> weekdays,
    required bool snoozeEnabled,
    required int snoozeMinutes,
    required int maxSnoozes,
    required bool requiresMission,
  }) async {
    final alarm = await _repository.insert(
      hour: hour,
      minute: minute,
      weekdays: weekdays,
      snoozeEnabled: snoozeEnabled,
      snoozeMinutes: snoozeMinutes,
      maxSnoozes: maxSnoozes,
      requiresMission: requiresMission,
    );
    await _scheduleBestEffort(alarm);
    await refresh();
    return alarm;
  }

  Future<void> save(TraditionalAlarm value) async {
    final now = DateTime.now();
    final alarm = value.copyWith(
      nextTriggerAt: value.enabled ? value.nextOccurrence(now: now) : null,
      clearNextTriggerAt: !value.enabled,
      updatedAt: now,
    );
    await _repository.update(alarm);
    if (alarm.enabled) {
      await _scheduleBestEffort(alarm);
    } else {
      await _cancel(alarm.id);
    }
    await refresh();
  }

  Future<void> setEnabled(TraditionalAlarm value, bool enabled) async {
    await save(value.copyWith(enabled: enabled));
  }

  Future<void> delete(TraditionalAlarm value) async {
    await _cancel(value.id);
    await _repository.delete(value.id);
    await refresh();
  }

  Future<void> openSnoozedMission(String alarmId) async {
    if (!_isAndroid) return;
    await _channel.invokeMethod<void>('openSnoozedMission', {'id': alarmId});
    await reconcile();
  }

  Future<void> dismissSnooze(String alarmId) async {
    if (!_isAndroid) return;
    await _channel.invokeMethod<void>('dismissSnooze', {'id': alarmId});
    await reconcile();
  }

  Future<bool> preparePermissions() async {
    if (!_isAndroid) return true;
    if (!await NotificationService.instance.requestPermission()) return false;
    final monitor = SleepMonitorService.instance;
    final capabilities = await monitor.getAlarmCapabilities();
    if (capabilities['exactAlarmGranted'] != true) {
      await monitor.requestExactAlarmPermission();
      return false;
    }
    if (capabilities['fullScreenIntentGranted'] != true) {
      await monitor.requestFullScreenPermission();
    }
    return true;
  }

  Future<bool> hasConfiguredMission() async {
    final missions = SleepMissionService();
    await missions.load();
    return missions.config.isConfigured;
  }

  Future<void> _schedule(TraditionalAlarm alarm) async {
    if (!_isAndroid) return;
    final mission = SleepMissionService();
    await mission.load();
    if (alarm.requiresMission && !mission.config.isConfigured) {
      throw StateError('mission_not_configured');
    }
    final next = alarm.nextTriggerAt ?? alarm.nextOccurrence();
    await _channel.invokeMethod<void>('schedule', {
      'id': alarm.id,
      'alarm_at_epoch_ms': next.millisecondsSinceEpoch,
      'hour': alarm.hour,
      'minute': alarm.minute,
      'weekdays': alarm.weekdays,
      'snooze_enabled': alarm.snoozeEnabled,
      'snooze_minutes': alarm.snoozeMinutes,
      'max_snoozes': alarm.maxSnoozes,
      'requires_mission': alarm.requiresMission,
      'mission_type': mission.config.type,
      'mission_hash': mission.config.hash,
      'mission_salt': mission.config.salt,
      'mission_format': mission.config.format,
    });
  }

  static const globalMaxSnoozesKey = 'alarm_global_max_snoozes';
  static const globalSnoozeEnabledKey = 'alarm_global_snooze_enabled';
  static const defaultMaxSnoozes = 3;

  Future<int> getGlobalMaxSnoozes() async {
    final raw = await _settings.getSetting(globalMaxSnoozesKey);
    return (int.tryParse(raw ?? '') ?? defaultMaxSnoozes).clamp(0, 10);
  }

  Future<void> setGlobalMaxSnoozes(int value) =>
      _settings.setSetting(globalMaxSnoozesKey, value.clamp(0, 10).toString());

  Future<bool> getGlobalSnoozeEnabled() async =>
      (await _settings.getSetting(globalSnoozeEnabledKey)) != 'false';

  Future<void> setGlobalSnoozeEnabled(bool enabled) =>
      _settings.setSetting(globalSnoozeEnabledKey, enabled ? 'true' : 'false');

  /// The SQLite write already succeeded when this is called. A temporary
  /// platform-channel failure (for example during an Android hot restart) must
  /// not make the editor report that the alarm was not created. [reconcile]
  /// schedules this persisted alarm as soon as the native side is available.
  Future<void> _scheduleBestEffort(TraditionalAlarm alarm) async {
    try {
      await _schedule(alarm);
    } on MissingPluginException catch (error) {
      debugPrint('Traditional alarm channel unavailable: $error');
    } on PlatformException catch (error) {
      debugPrint('Traditional alarm schedule deferred: ${error.code}');
    }
  }

  Future<void> _cancel(String id) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>('cancel', {'id': id});
    } on MissingPluginException {
      // Android-only channel is unavailable on other platforms.
    }
  }

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
}
