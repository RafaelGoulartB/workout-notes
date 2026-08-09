import '../repositories/settings_repository.dart';

/// Persists the user's target amount of sleep per night.
///
/// The goal is intentionally a lightweight app preference rather than a
/// clinical recommendation. Values are kept in 15-minute increments so the
/// dashboard can compare a night consistently with the configured target.
class SleepGoalService {
  SleepGoalService({SettingsRepository? settings})
    : _settings = settings ?? SettingsRepository();

  static const settingKey = 'sleep_goal_minutes';
  static const defaultGoalMinutes = 480;
  static const minimumGoalMinutes = 240;
  static const maximumGoalMinutes = 720;
  static const stepMinutes = 15;

  final SettingsRepository _settings;

  Future<int> load() async {
    final raw = await _settings.getSetting(settingKey);
    return normalize(int.tryParse(raw ?? '') ?? defaultGoalMinutes);
  }

  Future<void> save(int minutes) async {
    await _settings.setSetting(settingKey, normalize(minutes).toString());
  }

  static int normalize(int minutes) {
    final clamped = minutes.clamp(minimumGoalMinutes, maximumGoalMinutes);
    return ((clamped / stepMinutes).round() * stepMinutes).clamp(
      minimumGoalMinutes,
      maximumGoalMinutes,
    );
  }
}
