import 'dart:typed_data';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/l10n/app_localizations_en.dart';
import 'package:workout_notes/l10n/app_localizations_pt.dart';
import '../repositories/settings_repository.dart';

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
  bool? _notificationsAllowed;
  String _localeCode = 'en';

  // Notification IDs
  static const int _restTimerId = 1001;
  static const int _workoutTimerId = 1002;

  // Android Channels
  static const String _restChannelId = 'rest_timer';
  static const String _workoutChannelId = 'workout_timer';

  // Cached settings
  bool _restEnabled = true;
  bool _restSound = true;
  bool _restVibration = true;
  bool _workoutEnabled = true;
  bool _workoutSound = true;
  bool _workoutVibration = true;

  /// Whether the plugin has been initialized.
  bool get isInitialized => _initialized;

  AppLocalizations get _loc =>
      _localeCode == 'pt' ? AppLocalizationsPt() : AppLocalizationsEn();

  // Initialization

  /// Initialize the plugin and create notification channels.
  Future<void> init() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(settings: initSettings);
    await _loadLocale();

    // Create/update channels with current settings
    await _updateRestChannel();
    await _updateWorkoutChannel();

    _initialized = true;
  }

  /// Load notification settings from the database and update channels.
  Future<void> loadSettings() async {
    final settingsRepo = SettingsRepository();
    final settings = await settingsRepo.getAllSettings();

    _restEnabled = settings['notification_rest_timer_enabled'] != 'false';
    _restSound = settings['notification_rest_timer_sound'] != 'false';
    _restVibration = settings['notification_rest_timer_vibration'] != 'false';
    _workoutEnabled = settings['notification_workout_timer_enabled'] != 'false';
    _workoutSound = settings['notification_workout_timer_sound'] == 'true';
    _workoutVibration =
        settings['notification_workout_timer_vibration'] == 'true';
    await _loadLocale();

    if (_initialized) {
      await _updateRestChannel();
      await _updateWorkoutChannel();
    }
  }

  /// Request the POST_NOTIFICATIONS permission on Android 13+.
  /// Returns `true` if already granted or permission was granted.
  Future<bool> requestPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) {
      _notificationsAllowed = true;
      return true; // not Android
    }
    final granted = await android.requestNotificationsPermission();
    _notificationsAllowed = granted ?? false;
    return _notificationsAllowed!;
  }

  Future<bool> _ensureNotificationPermission() async {
    if (_notificationsAllowed != null) return _notificationsAllowed!;
    return requestPermission();
  }

  Future<void> _loadLocale() async {
    final prefs = await SharedPreferences.getInstance();
    _localeCode = prefs.getString('app_locale') == 'pt' ? 'pt' : 'en';
  }

  // Channel updates

  Future<void> _updateRestChannel() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return;

    await android.createNotificationChannel(
      AndroidNotificationChannel(
        _restChannelId,
        _loc.notificationRestChannelName,
        description: _loc.notificationRestChannelDesc,
        importance: Importance.high,
        playSound: _restSound,
        enableVibration: _restVibration,
      ),
    );
  }

  Future<void> _updateWorkoutChannel() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return;

    await android.createNotificationChannel(
      AndroidNotificationChannel(
        _workoutChannelId,
        _loc.notificationWorkoutChannelName,
        description: _loc.notificationWorkoutChannelDesc,
        importance: Importance.defaultImportance,
        playSound: _workoutSound,
        enableVibration: _workoutVibration,
      ),
    );
  }

  // Rest Timer Notifications

  /// Show or update the rest timer countdown notification.
  Future<void> showRestTimer(int remainingSeconds) async {
    if (!_initialized || !_restEnabled) return;
    if (!await _ensureNotificationPermission()) return;

    await _plugin.show(
      id: _restTimerId,
      title: _loc.notificationRestTimerTitle,
      body: _formatCountdown(remainingSeconds),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _restChannelId,
          _loc.notificationRestChannelName,
          channelDescription: _loc.notificationRestChannelDesc,
          importance: Importance.high,
          priority: Priority.high,
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,
          showWhen: true,
          when: DateTime.now()
              .add(Duration(seconds: remainingSeconds))
              .millisecondsSinceEpoch,
          usesChronometer: true,
          chronometerCountDown: true,
        ),
      ),
    );
  }

  /// Show the rest timer completion notification (with sound/vibration).
  Future<void> showRestTimerComplete() async {
    if (!_initialized || !_restEnabled) return;
    if (!await _ensureNotificationPermission()) return;

    // Cancel the ongoing first so a fresh notification alert plays
    await _plugin.cancel(id: _restTimerId);

    await _plugin.show(
      id: _restTimerId,
      title: _loc.notificationRestCompleteTitle,
      body: _loc.notificationRestCompleteBody,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _restChannelId,
          _loc.notificationRestChannelName,
          channelDescription: _loc.notificationRestChannelDesc,
          importance: Importance.high,
          priority: Priority.high,
          ongoing: false,
          autoCancel: true,
          onlyAlertOnce: false, // alert on this specific show
          showWhen: false,
          usesChronometer: false,
          vibrationPattern: Int64List.fromList([
            0,
            3000,
          ]), // vibrate for 3 seconds
        ),
      ),
    );
  }

  /// Cancel the rest timer notification.
  Future<void> cancelRestTimer() async {
    await _plugin.cancel(id: _restTimerId);
  }

  // Workout Timer Notifications

  /// Show or update the workout timer notification.
  /// The elapsed time is shown in the notification body only (no header timer).
  Future<void> showWorkoutTimer(String elapsedFormatted) async {
    if (!_initialized || !_workoutEnabled) return;
    if (!await _ensureNotificationPermission()) return;

    await _plugin.show(
      id: _workoutTimerId,
      title: _loc.notificationWorkoutTimerTitle,
      body: elapsedFormatted,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _workoutChannelId,
          _loc.notificationWorkoutChannelName,
          channelDescription: _loc.notificationWorkoutChannelDesc,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,
          showWhen: false,
        ),
      ),
    );
  }

  /// Cancel the workout timer notification.
  Future<void> cancelWorkoutTimer() async {
    await _plugin.cancel(id: _workoutTimerId);
  }

  /// Cancel all timer notifications.
  Future<void> cancelAll() async {
    await _plugin.cancel(id: _restTimerId);
    await _plugin.cancel(id: _workoutTimerId);
  }

  // Helpers

  String _formatCountdown(int seconds) {
    final min = seconds ~/ 60;
    final sec = seconds % 60;
    return '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  String toString() => 'NotificationService(initialized: $_initialized)';
}
