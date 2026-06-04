import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RestTimerService extends ChangeNotifier {
  static final RestTimerService _instance = RestTimerService._();
  static RestTimerService get instance => _instance;

  RestTimerService._();

  Timer? _timer;
  int _remainingSeconds = 0;
  int _totalSeconds = 90;
  bool _isRunning = false;
  bool _isPaused = false;

  int get remainingSeconds => _remainingSeconds;
  int get totalSeconds => _totalSeconds;
  bool get isRunning => _isRunning;
  bool get isPaused => _isPaused;
  bool get isActive => _isRunning || _isPaused;
  double get progress => _totalSeconds > 0 ? _remainingSeconds / _totalSeconds : 0;

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
    notifyListeners();

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds <= 0) {
        timer.cancel();
        _isRunning = false;
        _isPaused = false;
        notifyListeners();
        HapticFeedback.heavyImpact();
        return;
      }
      _remainingSeconds--;
      notifyListeners();
    });
  }

  void pause() {
    _timer?.cancel();
    _isPaused = true;
    notifyListeners();
  }

  void resume() {
    _isPaused = false;
    notifyListeners();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds <= 0) {
        timer.cancel();
        _isRunning = false;
        _isPaused = false;
        notifyListeners();
        HapticFeedback.heavyImpact();
        return;
      }
      _remainingSeconds--;
      notifyListeners();
    });
  }

  void stop() {
    _timer?.cancel();
    _remainingSeconds = 0;
    _totalSeconds = 90;
    _isRunning = false;
    _isPaused = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
