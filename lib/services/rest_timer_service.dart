import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'notification_service.dart';

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

  int get remainingSeconds => _remainingSeconds;
  int get totalSeconds => _totalSeconds;
  bool get isRunning => _isRunning;
  bool get isPaused => _isPaused;
  bool get isActive => _isRunning || _isPaused;
  double get progress =>
      _totalSeconds > 0 ? _remainingSeconds / _totalSeconds : 0;

  String get formattedTime {
    final min = _remainingSeconds ~/ 60;
    final sec = _remainingSeconds % 60;
    return '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  String get shortTime {
    if (_remainingSeconds <= 0) return '';
    if (_remainingSeconds >= 60) {
      return '${_remainingSeconds ~/ 60}:${(_remainingSeconds % 60).toString().padLeft(2, '0')}';
    }
    return '${_remainingSeconds}s';
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

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _syncRemainingTime();
      if (_remainingSeconds <= 0) {
        timer.cancel();
        _isRunning = false;
        _isPaused = false;
        _endsAt = null;
        notifyListeners();
        _longVibrate();
        _showCompleteNotification();
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
    _isPaused = true;
    notifyListeners();
    NotificationService.instance.cancelRestTimer();
  }

  void resume() {
    _isPaused = false;
    _isRunning = true;
    _endsAt = DateTime.now().add(Duration(seconds: _remainingSeconds));
    notifyListeners();
    _updateNotification();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _syncRemainingTime();
      if (_remainingSeconds <= 0) {
        timer.cancel();
        _isRunning = false;
        _isPaused = false;
        _endsAt = null;
        notifyListeners();
        _longVibrate();
        _showCompleteNotification();
        return;
      }
      notifyListeners();
    });
  }

  void stop() {
    _timer?.cancel();
    _remainingSeconds = 0;
    _totalSeconds = 90;
    _isRunning = false;
    _isPaused = false;
    _endsAt = null;
    notifyListeners();
    NotificationService.instance.cancelRestTimer();
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
        } catch (_) {}
      });
    }
  }
}
