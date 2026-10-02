import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:workout_notes/services/notification_service.dart';
import 'package:workout_notes/utils/duration_format.dart';

class RestTimerService extends ChangeNotifier {
  static final RestTimerService _instance = RestTimerService._();
  static RestTimerService get instance => _instance;

  RestTimerService._();

  Timer? _timer;
  int _remainingSeconds = 0;
  int _totalSeconds = 90;
  bool _isRunning = false;
  bool _isPaused = false;
  DateTime? _endsAt;

  /// When the background alert (a scheduled system notification, see
  /// [NotificationService.scheduleRestTimerComplete]) is due, and whether the
  /// system accepted it. It backs the Dart timer up: with the screen off the
  /// timer can fire late or not at all.
  DateTime? _alertAt;
  bool _alertScheduled = false;

  int get remainingSeconds => _remainingSeconds;
  int get totalSeconds => _totalSeconds;
  bool get isRunning => _isRunning;
  bool get isPaused => _isPaused;
  bool get isActive => _isRunning || _isPaused;
  double get progress =>
      _totalSeconds > 0 ? _remainingSeconds / _totalSeconds : 0;

  String get formattedTime => DurationFormat.mmss(_remainingSeconds);

  String get shortTime {
    if (_remainingSeconds <= 0) return '';
    return DurationFormat.minSecOrSeconds(_remainingSeconds);
  }

  void start(int seconds) {
    _timer?.cancel();
    _totalSeconds = seconds > 0 ? seconds : 90;
    _remainingSeconds = _totalSeconds;
    _isRunning = true;
    _isPaused = false;
    _endsAt = DateTime.now().add(Duration(seconds: _remainingSeconds));
    notifyListeners();
    _showInitialNotification();
    _scheduleBackgroundAlert();

    _startTicker();
  }

  /// Whether finishing at [now] must alert from the app: always, unless the
  /// background alert was scheduled and its time has passed (it already rang,
  /// for example while the screen was off, so a late timer must not ring a
  /// second time).
  @visibleForTesting
  static bool alertsInApp({
    required bool alertScheduled,
    required DateTime? alertAt,
    required DateTime now,
  }) => !alertScheduled || alertAt == null || now.isBefore(alertAt);

  void _scheduleBackgroundAlert() {
    final endsAt = _endsAt;
    if (endsAt == null) return;
    final alertAt = endsAt.add(NotificationService.restAlertGrace);
    _alertAt = alertAt;
    _alertScheduled = false;
    unawaited(
      NotificationService.instance.scheduleRestTimerComplete(alertAt).then((
        scheduled,
      ) {
        // Ignore the answer for a timer that was restarted or stopped since.
        if (_alertAt == alertAt) _alertScheduled = scheduled;
      }),
    );
  }

  void _clearBackgroundAlert() {
    _alertAt = null;
    _alertScheduled = false;
  }

  /// Replaces any running ticker with one that syncs the remaining time every
  /// second and finishes the timer at zero.
  void _startTicker() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _syncRemainingTime();
      if (_remainingSeconds <= 0) {
        timer.cancel();
        final alert = alertsInApp(
          alertScheduled: _alertScheduled,
          alertAt: _alertAt,
          now: DateTime.now(),
        );
        _isRunning = false;
        _isPaused = false;
        _endsAt = null;
        _clearBackgroundAlert();
        notifyListeners();
        if (alert) {
          _longVibrate();
          // Also cancels the scheduled background alert (same notification id).
          _showCompleteNotification();
        }
        return;
      }
      notifyListeners();
    });
  }

  void _syncRemainingTime() {
    final endsAt = _endsAt;
    if (endsAt == null) return;
    final milliseconds = endsAt.difference(DateTime.now()).inMilliseconds;
    _remainingSeconds = milliseconds <= 0
        ? 0
        : (milliseconds / Duration.millisecondsPerSecond).ceil();
  }

  void pause() {
    _timer?.cancel();
    _syncRemainingTime();
    _endsAt = null;
    _clearBackgroundAlert();
    _isPaused = true;
    notifyListeners();
    unawaited(NotificationService.instance.cancelRestTimer());
  }

  void resume() {
    _isPaused = false;
    _isRunning = true;
    _endsAt = DateTime.now().add(Duration(seconds: _remainingSeconds));
    notifyListeners();
    _updateNotification();
    _scheduleBackgroundAlert();
    _startTicker();
  }

  void stop() {
    _timer?.cancel();
    _remainingSeconds = 0;
    _totalSeconds = 90;
    _isRunning = false;
    _isPaused = false;
    _endsAt = null;
    _clearBackgroundAlert();
    notifyListeners();
    unawaited(NotificationService.instance.cancelRestTimer());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ── Notification helpers ──

  void _showInitialNotification() {
    NotificationService.instance.showRestTimer(_remainingSeconds);
  }

  void _updateNotification() {
    NotificationService.instance.showRestTimer(_remainingSeconds);
  }

  void _showCompleteNotification() {
    NotificationService.instance.showRestTimerComplete();
  }

  /// Vibrate for ~3 seconds using repeated haptic feedback.
  void _longVibrate() {
    // Immediate strong buzz
    HapticFeedback.heavyImpact();

    // Schedule additional vibrations to create ~3 seconds of feedback
    for (int i = 1; i <= 5; i++) {
      Future.delayed(Duration(milliseconds: 500 * i), () {
        try {
          HapticFeedback.heavyImpact();
        } catch (_) {
          // Haptics are optional (unsupported on some devices).
        }
      });
    }
  }
}
