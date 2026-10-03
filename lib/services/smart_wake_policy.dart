import 'package:workout_notes/models/sleep_monitor_session.dart';

/// When a smart alarm rings before its deadline.
///
/// The Android monitor makes this decision while the app is closed
/// (`SmartWakePolicy.kt`); this Dart copy replays it on exported nights
/// (`tool/replay_sleep.dart --smart-window`) and pins the native behaviour in
/// `test/fixtures/sleep_wake_parity.json`.
///
/// Inside the window before the deadline, the alarm rings at the first
/// 30-second window whose probability of sleep falls below [threshold]: the
/// person is moving or already awake. The live filter starts every night
/// assuming the person is awake, so nothing fires until it has seen
/// [armingSeconds] of confident sleep. The deadline is a separate exact
/// alarm; this policy can only ring earlier.
class SmartWakePolicy {
  static const armingSeconds = 10 * 60;
  static const armingProbability = 0.8;
  static const awakeProbability = 0.3;
  static const triggerAwake = SleepMonitorSession.triggerAwake;
  static const triggerStirring = SleepMonitorSession.triggerStirring;
  static const triggerDeadline = SleepMonitorSession.triggerDeadline;

  final double threshold;
  int _confidentSleepSeconds = 0;

  SmartWakePolicy(this.threshold);

  bool get isArmed => _confidentSleepSeconds >= armingSeconds;

  /// Feeds one window ending at [now]; returns the trigger when the alarm
  /// should ring now, otherwise null.
  String? onWindow({
    required double sleepProbability,
    required bool validSignal,
    required int seconds,
    required DateTime now,
    required DateTime windowStart,
    required DateTime deadline,
  }) {
    if (validSignal && sleepProbability >= armingProbability) {
      _confidentSleepSeconds += seconds < 0 ? 0 : seconds;
    }
    if (!isArmed || !validSignal) return null;
    if (now.isBefore(windowStart) || !now.isBefore(deadline)) return null;
    if (sleepProbability >= threshold) return null;
    return sleepProbability < awakeProbability ? triggerAwake : triggerStirring;
  }
}
