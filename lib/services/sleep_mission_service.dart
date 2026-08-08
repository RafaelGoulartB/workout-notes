import 'package:flutter/foundation.dart';

import '../models/sleep_monitor_mode.dart';
import '../repositories/settings_repository.dart';

/// Stores the barcode mission configuration in the same SQLite-backed settings
/// store used by the Workout settings screen.
class SleepMissionService extends ChangeNotifier {
  SleepMissionService({SettingsRepository? settings})
    : _settings = settings ?? SettingsRepository();

  final SettingsRepository _settings;
  SleepMissionConfig _config = const SleepMissionConfig.empty();
  SleepMonitoringMode _lastMode = SleepMonitoringMode.alarmWithoutMission;
  bool _loaded = false;

  SleepMissionConfig get config => _config;
  SleepMonitoringMode get lastMode => _lastMode;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    final values = await _settings.getAllSettings();
    _config = SleepMissionConfig.fromSettings(values);
    _lastMode = SleepMonitoringMode.values.firstWhere(
      (mode) => mode.wireValue == values['sleep_monitor_default_mode'],
      orElse: () => SleepMonitoringMode.alarmWithoutMission,
    );
    _loaded = true;
    notifyListeners();
  }

  Future<void> saveScanResult(Map<String, dynamic> result) async {
    final hash = result['hash'] as String?;
    final salt = result['salt'] as String?;
    if (hash == null || salt == null || hash.isEmpty || salt.isEmpty) {
      throw const FormatException('barcode_hash_missing');
    }
    final registeredText = result['registered_at'] as String?;
    final config = SleepMissionConfig(
      enabled: true,
      type: 'barcode',
      hash: hash,
      salt: salt,
      format: result['format'] as String?,
      registeredAt: registeredText == null
          ? DateTime.now()
          : DateTime.tryParse(registeredText) ?? DateTime.now(),
    );
    for (final entry in config.toSettings().entries) {
      await _settings.setSetting(entry.key, entry.value);
    }
    _config = config;
    _loaded = true;
    notifyListeners();
  }

  Future<void> setEnabled(bool enabled) async {
    if (enabled && !_config.isConfigured) {
      return;
    }
    await _settings.setSetting(
      'sleep_mission_enabled',
      enabled ? 'true' : 'false',
    );
    _config = _config.copyWith(enabled: enabled);
    notifyListeners();
  }

  Future<void> clear() async {
    final cleared = _config.copyWith(enabled: false, clearBarcode: true);
    for (final entry in cleared.toSettings().entries) {
      await _settings.setSetting(entry.key, entry.value);
    }
    _config = cleared;
    notifyListeners();
  }

  Future<void> setLastMode(SleepMonitoringMode mode) async {
    await _settings.setSetting('sleep_monitor_default_mode', mode.wireValue);
    _lastMode = mode;
    notifyListeners();
  }
}
