import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/models/alarm_wake_settings.dart';
import 'package:workout_notes/repositories/settings_repository.dart';

/// Persists [AlarmWakeSettings] in `app_settings` and mirrors the volume rise
/// to Android, where the ringing services read it while the app is closed.
/// The smart window travels with each monitored night when it starts.
class AlarmWakeSettingsService {
  AlarmWakeSettingsService({SettingsRepository? settings})
    : _settings = settings ?? DatabaseHelper.instance.settingsRepo;

  static const windowKey = 'smart_wake_window_minutes';
  static const sensitivityKey = 'smart_wake_sensitivity';
  static const rampKey = 'alarm_ramp_seconds';
  static const boostKey = 'alarm_ramp_boost';
  static const _channel = MethodChannel(
    'workout_notes/traditional_alarms/methods',
  );

  final SettingsRepository _settings;

  Future<AlarmWakeSettings> load() async {
    final window = int.tryParse(await _settings.getSetting(windowKey) ?? '');
    final ramp = int.tryParse(await _settings.getSetting(rampKey) ?? '');
    return AlarmWakeSettings(
      windowMinutes: _option(
        window,
        AlarmWakeSettings.windowOptions,
        AlarmWakeSettings.defaultWindowMinutes,
      ),
      sensitivity: SmartWakeSensitivity.fromWire(
        await _settings.getSetting(sensitivityKey),
      ),
      rampSeconds: _option(
        ramp,
        AlarmWakeSettings.rampOptions,
        AlarmWakeSettings.defaultRampSeconds,
      ),
      boost: await _settings.getSetting(boostKey) != 'false',
    );
  }

  Future<void> save(AlarmWakeSettings value) async {
    await _settings.setSetting(windowKey, value.windowMinutes.toString());
    await _settings.setSetting(sensitivityKey, value.sensitivity.wireValue);
    await _settings.setSetting(rampKey, value.rampSeconds.toString());
    await _settings.setSetting(boostKey, value.boost ? 'true' : 'false');
    await syncNative(value);
  }

  /// Pushes the volume rise to Android. Best effort: the app pushes it again
  /// on every start (alarm reconcile) and before each monitored night.
  Future<void> syncNative([AlarmWakeSettings? value]) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final settings = value ?? await load();
    try {
      await _channel.invokeMethod<void>('setWakeSettings', {
        'ramp_seconds': settings.rampSeconds,
        'boost': settings.boost,
      });
    } on MissingPluginException {
      // Android-only channel; absent in tests and on other platforms.
    } on PlatformException catch (error) {
      debugPrint('Alarm wake settings not synced: ${error.code}');
    }
  }

  static int _option(int? value, List<int> options, int fallback) =>
      value != null && options.contains(value) ? value : fallback;
}
