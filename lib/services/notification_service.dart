import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/l10n/app_localizations_en.dart';
import 'package:workout_notes/l10n/app_localizations_pt.dart';
import 'package:workout_notes/utils/duration_format.dart';

/// Centralized notification service for timer notifications.
///
/// Uses `flutter_local_notifications` to show and update local notifications
/// for the rest timer (countdown) and workout timer (elapsed time).
///
/// The plugin is initialised lazily, on the first notification (or when the
/// settings screen asks for the permission). Settings are cached from the
/// database at that point and can be refreshed via [loadSettings].
class NotificationService {
  static final NotificationService _instance = NotificationService._();
  static NotificationService get instance => _instance;

  NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  Future<void>? _initFuture;
  bool? _notificationsAllowed;
  String _localeCode = 'en';

  // Notification IDs
  static const int _restTimerId = 1001;
  static const int _workoutTimerId = 1002;

  // Android channels. Sound and vibration are frozen when a channel is
  // created (Android ignores later changes), so the ids carry the settings and
  // a change moves to a new channel instead of re-creating the old one.
  static const String _restChannelPrefix = 'rest_timer';
  static const String _workoutChannelPrefix = 'workout_timer';

  String get _restChannelId => channelId(
    _restChannelPrefix,
    sound: _restSound,
    vibration: _restVibration,
  );
  String get _workoutChannelId => channelId(
    _workoutChannelPrefix,
    sound: _workoutSound,
    vibration: _workoutVibration,
  );

  /// `<prefix>_v<n>`, where `n` encodes sound (1) and vibration (2).
  @visibleForTesting
  static String channelId(
    String prefix, {
    required bool sound,
    required bool vibration,
  }) => '${prefix}_v${(sound ? 1 : 0) | (vibration ? 2 : 0)}';

  // Cached settings
  bool _restEnabled = true;
  bool _restSound = true;
  bool _restVibration = true;
  bool _workoutEnabled = true;
  bool _workoutSound = true;
  bool _workoutVibration = true;

  AppLocalizations get _loc =>
      _localeCode == 'pt' ? AppLocalizationsPt() : AppLocalizationsEn();

  // Initialization

  /// Initialize the plugin and create notification channels. Concurrent
  /// callers share one run; a failed run can be retried.
  Future<void> init() {
    final running = _initFuture;
    if (running != null) return running;
    final future = _initialize();
    _initFuture = future;
    future.catchError((Object _) {
      if (identical(_initFuture, future)) _initFuture = null;
    });
    return future;
  }

  Future<void> _initialize() async {
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
    await _readSettings();
    await _syncChannels();

    _initialized = true;
  }

  /// Initialises on demand; false when that fails (the caller just skips the
  /// notification).
  Future<bool> _ready() async {
    try {
      await init();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Reload the cached notification settings and move the channels to match.
  Future<void> loadSettings() async {
    await _readSettings();
    if (_initialized) await _syncChannels();
  }

  Future<void> _readSettings() async {
    final settingsRepo = DatabaseHelper.instance.settingsRepo;
    final settings = await settingsRepo.getAllSettings();

    _restEnabled = settings['notification_rest_timer_enabled'] != 'false';
    _restSound = settings['notification_rest_timer_sound'] != 'false';
    _restVibration = settings['notification_rest_timer_vibration'] != 'false';
    _workoutEnabled = settings['notification_workout_timer_enabled'] != 'false';
    _workoutSound = settings['notification_workout_timer_sound'] == 'true';
    _workoutVibration =
        settings['notification_workout_timer_vibration'] == 'true';
    await _loadLocale();
  }

  /// Request the POST_NOTIFICATIONS permission on Android 13+.
  /// Returns `true` if already granted or permission was granted.
  Future<bool> requestPermission() async {
    await _ready();
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

  /// Creates the channels for the current settings and deletes the ones left
  /// by earlier settings (and the pre-versioning ids).
  Future<void> _syncChannels() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return;

    final restId = _restChannelId;
    final workoutId = _workoutChannelId;
    await android.createNotificationChannel(
      AndroidNotificationChannel(
        restId,
        _loc.notificationRestChannelName,
        description: _loc.notificationRestChannelDesc,
        importance: Importance.high,
        playSound: _restSound,
        enableVibration: _restVibration,
      ),
    );
    await android.createNotificationChannel(
      AndroidNotificationChannel(
        workoutId,
        _loc.notificationWorkoutChannelName,
        description: _loc.notificationWorkoutChannelDesc,
        importance: Importance.defaultImportance,
        playSound: _workoutSound,
        enableVibration: _workoutVibration,
      ),
    );

    final existing = await android.getNotificationChannels() ?? const [];
    for (final channel in existing) {
      final id = channel.id;
      final stale =
          (_isChannelOf(id, _restChannelPrefix) && id != restId) ||
          (_isChannelOf(id, _workoutChannelPrefix) && id != workoutId);
      if (stale) await android.deleteNotificationChannel(channelId: id);
    }
  }

  static bool _isChannelOf(String id, String prefix) =>
      id == prefix || id.startsWith('${prefix}_v');

  // Rest Timer Notifications

  /// Show or update the rest timer countdown notification.
  Future<void> showRestTimer(int remainingSeconds) async {
    if (!await _ready() || !_restEnabled) return;
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
    if (!await _ready() || !_restEnabled) return;
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
  Future<void> cancelRestTimer() => _cancel(_restTimerId);

  // Workout Timer Notifications

  /// Show or update the workout timer notification.
  ///
  /// While running, the system chronometer counts up from [startedAt], so the
  /// notification never has to be refreshed to keep the time live. A paused
  /// workout ([pausedElapsed]) shows the frozen time as static text.
  Future<void> showWorkoutTimer({
    required DateTime startedAt,
    String? pausedElapsed,
  }) async {
    if (!await _ready() || !_workoutEnabled) return;
    if (!await _ensureNotificationPermission()) return;

    final paused = pausedElapsed != null;
    await _plugin.show(
      id: _workoutTimerId,
      title: _loc.notificationWorkoutTimerTitle,
      body: pausedElapsed,
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
          showWhen: !paused,
          when: paused ? null : startedAt.millisecondsSinceEpoch,
          usesChronometer: !paused,
        ),
      ),
    );
  }

  /// Cancel the workout timer notification.
  Future<void> cancelWorkoutTimer() => _cancel(_workoutTimerId);

  /// Cancelling never throws: without the platform plugin (tests, desktop)
  /// there is nothing to cancel.
  Future<void> _cancel(int id) async {
    try {
      await _plugin.cancel(id: id);
    } catch (_) {}
  }

  // Helpers

  String _formatCountdown(int seconds) => DurationFormat.mmss(seconds);

  @override
  String toString() => 'NotificationService(initialized: $_initialized)';
}
