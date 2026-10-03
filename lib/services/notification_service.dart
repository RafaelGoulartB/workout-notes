import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/l10n/app_localizations_en.dart';
import 'package:workout_notes/l10n/app_localizations_pt.dart';
import 'package:workout_notes/utils/app_locale.dart';
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
  bool _permissionRequested = false;
  String _localeCode = 'en';

  /// Bumped by every schedule and by [cancelRestTimer] so a schedule that is
  /// still waiting for the plugin (or the permission) never lands after the
  /// timer was restarted or stopped.
  int _restAlertGeneration = 0;

  // Notification IDs
  static const int _restTimerId = 1001;
  static const int _workoutTimerId = 1002;

  // Android channels. Sound and vibration are frozen when a channel is
  // created (Android ignores later changes, and on Android 8+ the channel
  // alone decides them, not the notification), so the ids carry the settings
  // and a change moves to a new channel instead of re-creating the old one.
  //
  // The rest timer has two: a silent one for the ongoing countdown and an
  // alerting one for "rest finished" (with the vibration pattern).
  // `rest_timer*` was the single channel of earlier versions: it is deleted.
  static const String _legacyRestChannelPrefix = 'rest_timer';
  static const String _restProgressChannelId = 'rest_timer_progress';
  static const String _restAlertChannelPrefix = 'rest_alert';
  static const String _workoutChannelPrefix = 'workout_timer';

  /// How long the exact background alert waits after the timer's end. The
  /// app's own timer usually finishes first and then replaces it with the
  /// in-app alert, so a foreground finish is never announced twice.
  static const Duration restAlertGrace = Duration(seconds: 2);

  /// The "rest finished" vibration, about three seconds.
  static final Int64List _restAlertVibration = Int64List.fromList([0, 3000]);

  String get _restChannelId => channelId(
    _restAlertChannelPrefix,
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
    if (android == null) return true; // not Android
    _permissionRequested = true;
    return await android.requestNotificationsPermission() ?? false;
  }

  /// Whether notifications can be posted right now. The state is read from
  /// the system every time (the user can change it in the settings at any
  /// moment); the permission prompt is only raised once.
  Future<bool> _ensureNotificationPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return true; // not Android
    if (await android.areNotificationsEnabled() ?? false) return true;
    if (_permissionRequested) return false;
    return requestPermission();
  }

  Future<void> _loadLocale() async {
    final prefs = await SharedPreferences.getInstance();
    _localeCode = AppLocale.languageCode(prefs.getString('app_locale'));
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
        _restProgressChannelId,
        _loc.notificationRestChannelName,
        description: _loc.notificationRestChannelDesc,
        importance: Importance.low,
        playSound: false,
        enableVibration: false,
      ),
    );
    await android.createNotificationChannel(
      AndroidNotificationChannel(
        restId,
        _loc.notificationRestCompleteTitle,
        description: _loc.notificationRestCompleteBody,
        importance: Importance.high,
        playSound: _restSound,
        enableVibration: _restVibration,
        vibrationPattern: _restVibration ? _restAlertVibration : null,
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
          _isChannelOf(id, _legacyRestChannelPrefix) ||
          (_isChannelOf(id, _restAlertChannelPrefix) && id != restId) ||
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
          _restProgressChannelId,
          _loc.notificationRestChannelName,
          channelDescription: _loc.notificationRestChannelDesc,
          importance: Importance.low,
          priority: Priority.low,
          playSound: false,
          enableVibration: false,
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
      notificationDetails: _restAlertDetails(),
    );
  }

  /// The alerting notification shared by the immediate and the scheduled
  /// "rest finished". Sound and vibration are set here for Android < 8; on
  /// Android 8+ the channel (see [_syncChannels]) decides them.
  NotificationDetails _restAlertDetails() => NotificationDetails(
    android: AndroidNotificationDetails(
      _restChannelId,
      _loc.notificationRestCompleteTitle,
      channelDescription: _loc.notificationRestCompleteBody,
      importance: Importance.high,
      priority: Priority.high,
      playSound: _restSound,
      enableVibration: _restVibration,
      vibrationPattern: _restVibration ? _restAlertVibration : null,
      ongoing: false,
      autoCancel: true,
      onlyAlertOnce: false,
      showWhen: false,
      usesChronometer: false,
    ),
  );

  /// Schedules the "rest finished" alert at [at] with the system alarm
  /// manager, so it still fires when the screen is off and Dart's timers are
  /// throttled. It uses the id of the countdown notification, so it replaces
  /// it when it fires and [cancelRestTimer] drops both. Exact (allowed while
  /// idle) when the system grants exact alarms, otherwise inexact. Returns
  /// whether an alert is now scheduled.
  Future<bool> scheduleRestTimerComplete(DateTime at) async {
    // A newer schedule or a cancel makes this one stale before it lands.
    final generation = ++_restAlertGeneration;
    if (!await _ready() || !_restEnabled) return false;
    if (!await _ensureNotificationPermission()) return false;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return false;
    try {
      final exact = await android.canScheduleExactNotifications() ?? false;
      if (generation != _restAlertGeneration) return false;
      await _plugin.zonedSchedule(
        id: _restTimerId,
        title: _loc.notificationRestCompleteTitle,
        body: _loc.notificationRestCompleteBody,
        // An absolute instant: the zone only labels it, so no local time zone
        // database is needed.
        scheduledDate: tz.TZDateTime.fromMillisecondsSinceEpoch(
          tz.UTC,
          at.millisecondsSinceEpoch,
        ),
        notificationDetails: _restAlertDetails(),
        androidScheduleMode: exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
      );
      return true;
    } catch (e) {
      debugPrint('Could not schedule the rest timer alert: $e');
      return false;
    }
  }

  /// Cancel the rest timer notification and its scheduled alert.
  Future<void> cancelRestTimer() {
    _restAlertGeneration++;
    return _cancel(_restTimerId);
  }

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
    } catch (_) {
      // Cancelling a notification that is gone or unsupported is harmless.
    }
  }

  // Helpers

  String _formatCountdown(int seconds) => DurationFormat.mmss(seconds);

  @override
  String toString() => 'NotificationService(initialized: $_initialized)';
}
