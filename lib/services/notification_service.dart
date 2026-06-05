import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../database/database_helper.dart';

/// Centralized notification service for timer notifications.
///
/// Uses `flutter_local_notifications` to show and update local notifications
/// for the rest timer (countdown) and workout timer (elapsed time).
///
/// Settings are cached from [DatabaseHelper] on init and can be refreshed
/// via [loadSettings].
class NotificationService {
  static final NotificationService _instance = NotificationService._();
  static NotificationService get instance => _instance;

  NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  // ── Notification IDs ──
  static const int _restTimerId = 1001;
  static const int _workoutTimerId = 1002;

  // ── Android Channels ──
  static const String _restChannelId = 'rest_timer';
  static const String _restChannelName = 'Timer de Descanso';
  static const String _restChannelDesc =
      'Notificações do temporizador de descanso entre séries';

  static const String _workoutChannelId = 'workout_timer';
  static const String _workoutChannelName = 'Timer de Treino';
  static const String _workoutChannelDesc =
      'Notificações do temporizador de treino ativo';

  // ── Cached settings ──
  bool _restEnabled = true;
  bool _restSound = true;
  bool _restVibration = true;
  bool _workoutEnabled = true;
  bool _workoutSound = true;
  bool _workoutVibration = true;

  /// Whether the plugin has been initialized.
  bool get isInitialized => _initialized;

  // ── Initialization ──

  /// Initialize the plugin and create notification channels.
  Future<void> init() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(initSettings);

    // Create/update channels with current settings
    await _updateRestChannel();
    await _updateWorkoutChannel();

    _initialized = true;
  }

  /// Load notification settings from the database and update channels.
  Future<void> loadSettings() async {
    final db = DatabaseHelper.instance;
    final settings = await db.getAllSettings();

    _restEnabled = settings['notification_rest_timer_enabled'] != 'false';
    _restSound = settings['notification_rest_timer_sound'] != 'false';
    _restVibration = settings['notification_rest_timer_vibration'] != 'false';
    _workoutEnabled = settings['notification_workout_timer_enabled'] != 'false';
    _workoutSound = settings['notification_workout_timer_sound'] == 'true';
    _workoutVibration =
        settings['notification_workout_timer_vibration'] == 'true';

    if (_initialized) {
      await _updateRestChannel();
      await _updateWorkoutChannel();
    }
  }

  /// Request the POST_NOTIFICATIONS permission on Android 13+.
  /// Returns `true` if already granted or permission was granted.
  Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true; // not Android
    final granted = await android.requestNotificationsPermission();
    return granted ?? false;
  }

  // ── Channel updates ──

  Future<void> _updateRestChannel() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;

    await android.createNotificationChannel(
      AndroidNotificationChannel(
        _restChannelId,
        _restChannelName,
        description: _restChannelDesc,
        importance: Importance.high,
        playSound: _restSound,
        enableVibration: _restVibration,
      ),
    );
  }

  Future<void> _updateWorkoutChannel() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;

    await android.createNotificationChannel(
      AndroidNotificationChannel(
        _workoutChannelId,
        _workoutChannelName,
        description: _workoutChannelDesc,
        importance: Importance.low,
        playSound: _workoutSound,
        enableVibration: _workoutVibration,
      ),
    );
  }

  // ── Rest Timer Notifications ──

  /// Show or update the rest timer countdown notification.
  Future<void> showRestTimer(int remainingSeconds) async {
    if (!_initialized || !_restEnabled) return;

    await _plugin.show(
      _restTimerId,
      '⏱ Descanso',
      _formatCountdown(remainingSeconds),
      NotificationDetails(
        android: AndroidNotificationDetails(
          _restChannelId,
          _restChannelName,
          channelDescription: _restChannelDesc,
          importance: Importance.high,
          priority: Priority.high,
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true, // silent updates after first show
          showWhen: false,
          usesChronometer: false,
        ),
      ),
    );
  }

  /// Show the rest timer completion notification (with sound/vibration).
  Future<void> showRestTimerComplete() async {
    if (!_initialized || !_restEnabled) return;

    // Cancel the ongoing first so a fresh notification alert plays
    await _plugin.cancel(_restTimerId);

    await _plugin.show(
      _restTimerId,
      '✅ Descanso Concluído',
      'O tempo de descanso acabou — hora da próxima série! 💪',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _restChannelId,
          _restChannelName,
          channelDescription: _restChannelDesc,
          importance: Importance.high,
          priority: Priority.high,
          ongoing: false,
          autoCancel: true,
          onlyAlertOnce: false, // alert on this specific show
          showWhen: false,
          usesChronometer: false,
        ),
      ),
    );
  }

  /// Cancel the rest timer notification.
  Future<void> cancelRestTimer() async {
    await _plugin.cancel(_restTimerId);
  }

  // ── Workout Timer Notifications ──

  /// Show or update the workout timer notification.
  Future<void> showWorkoutTimer(String elapsedFormatted) async {
    if (!_initialized || !_workoutEnabled) return;

    final durationParts = _parseDurationParts(elapsedFormatted);

    await _plugin.show(
      _workoutTimerId,
      '🏋️ Treino ativo',
      elapsedFormatted,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _workoutChannelId,
          _workoutChannelName,
          channelDescription: _workoutChannelDesc,
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,
          showWhen: false,
          usesChronometer: durationParts != null,
          chronometerCountDown: false,
        ),
      ),
    );
  }

  /// Cancel the workout timer notification.
  Future<void> cancelWorkoutTimer() async {
    await _plugin.cancel(_workoutTimerId);
  }

  /// Cancel all timer notifications.
  Future<void> cancelAll() async {
    await _plugin.cancel(_restTimerId);
    await _plugin.cancel(_workoutTimerId);
  }

  // ── Helpers ──

  String _formatCountdown(int seconds) {
    final min = seconds ~/ 60;
    final sec = seconds % 60;
    return '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  /// Try to parse a formatted elapsed string into (hours, minutes, seconds).
  /// Returns null if parsing fails (e.g. custom format).
  (int hours, int minutes, int seconds)? _parseDurationParts(String formatted) {
    // Formats: "MM:SS" or "XhXXmin"
    try {
      if (formatted.contains('h')) {
        // e.g. "1h15min"
        final parts = formatted.split('h');
        final h = int.parse(parts[0]);
        final minPart = parts[1].replaceAll('min', '');
        final m = int.parse(minPart);
        return (h, m, 0);
      } else {
        // e.g. "15:32"
        final parts = formatted.split(':');
        final m = int.parse(parts[0]);
        final s = int.parse(parts[1]);
        return (0, m, s);
      }
    } catch (_) {
      return null;
    }
  }
}
