import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/l10n/app_localizations_en.dart';
import 'package:workout_notes/l10n/app_localizations_pt.dart';
import 'package:workout_notes/services/notification_service.dart';

import 'support/test_db.dart';

const _channel = MethodChannel('dexterous.com/flutter/local_notifications');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <MethodCall>[];
  var notificationsEnabled = true;
  var permissionGranted = true;
  var exactAllowed = true;
  var existingChannels = <String>[];
  var failZonedSchedule = false;

  final service = NotificationService.instance;
  final en = AppLocalizationsEn();
  final pt = AppLocalizationsPt();

  Iterable<MethodCall> named(String method) =>
      calls.where((c) => c.method == method);

  Map<Object?, Object?> argsOf(MethodCall call) =>
      call.arguments as Map<Object?, Object?>;

  Map<Object?, Object?> androidDetails(MethodCall call) =>
      argsOf(call)['platformSpecifics'] as Map<Object?, Object?>;

  Future<void> setSettings(Map<String, String> values) async {
    final repo = DatabaseHelper.instance.settingsRepo;
    for (final entry in values.entries) {
      await repo.setSetting(entry.key, entry.value);
    }
    await service.loadSettings();
  }

  setUpAll(() {
    initSqfliteFfiForTests();
    AndroidFlutterLocalNotificationsPlugin.registerWith();
  });

  setUp(() async {
    calls.clear();
    notificationsEnabled = true;
    permissionGranted = true;
    exactAllowed = true;
    existingChannels = [];
    failZonedSchedule = false;
    SharedPreferences.setMockInitialValues({});
    await installTestDb();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'initialize':
              return true;
            case 'areNotificationsEnabled':
              return notificationsEnabled;
            case 'requestNotificationsPermission':
              if (permissionGranted) notificationsEnabled = true;
              return permissionGranted;
            case 'canScheduleExactNotifications':
              return exactAllowed;
            case 'getNotificationChannels':
              return [
                for (final id in existingChannels)
                  <String, Object?>{
                    'id': id,
                    'name': id,
                    'importance': 3,
                    'showBadge': true,
                    'bypassDnd': false,
                    'playSound': true,
                    'enableLights': false,
                    'enableVibration': false,
                    'ledColor': 0,
                  },
              ];
            case 'zonedSchedule':
              if (failZonedSchedule) {
                throw PlatformException(code: 'exact_alarms_not_permitted');
              }
          }
          return null;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    await uninstallTestDb();
  });

  test('channelId encodes sound and vibration', () {
    String id({required bool sound, required bool vibration}) =>
        NotificationService.channelId('x', sound: sound, vibration: vibration);
    expect(id(sound: false, vibration: false), 'x_v0');
    expect(id(sound: true, vibration: false), 'x_v1');
    expect(id(sound: false, vibration: true), 'x_v2');
    expect(id(sound: true, vibration: true), 'x_v3');
  });

  // Declared first on purpose: the service is a process-wide singleton that
  // initialises once, so this is the only test that observes that first run.
  test('the first notification initialises the plugin once', () async {
    expect(service.toString(), contains('initialized: false'));
    await service.showRestTimer(90);

    expect(named('initialize'), hasLength(1));
    expect(service.toString(), contains('initialized: true'));
    // A second notification reuses the initialised plugin.
    await service.showRestTimer(80);
    expect(named('initialize'), hasLength(1));
    expect(named('show'), hasLength(2));
  });

  test(
    'the rest countdown shows mm:ss on the silent ongoing channel',
    () async {
      await service.showRestTimer(125);

      final shown = named('show').single;
      final args = argsOf(shown);
      expect(args['id'], 1001);
      expect(args['title'], en.notificationRestTimerTitle);
      expect(args['body'], '02:05');
      final details = androidDetails(shown);
      expect(details['channelId'], 'rest_timer_progress');
      expect(details['ongoing'], true);
      expect(details['playSound'], false);
      expect(details['usesChronometer'], true);
      expect(details['chronometerCountDown'], true);
    },
  );

  test('the rest completion cancels the countdown then alerts', () async {
    await service.showRestTimerComplete();

    final order = calls
        .map((c) => c.method)
        .where((m) => m == 'cancel' || m == 'show')
        .toList();
    expect(order, ['cancel', 'show']);
    expect(argsOf(named('cancel').single)['id'], 1001);
    final shown = named('show').single;
    expect(argsOf(shown)['title'], en.notificationRestCompleteTitle);
    expect(androidDetails(shown)['channelId'], 'rest_alert_v3');
    expect(androidDetails(shown)['autoCancel'], true);
    expect(androidDetails(shown)['ongoing'], false);
  });

  test('a disabled rest timer posts nothing', () async {
    await setSettings({'notification_rest_timer_enabled': 'false'});

    await service.showRestTimer(30);
    await service.showRestTimerComplete();
    expect(
      await service.scheduleRestTimerComplete(DateTime(2026, 9, 1)),
      isFalse,
    );

    expect(named('show'), isEmpty);
    expect(named('zonedSchedule'), isEmpty);
  });

  test('texts follow the saved app language', () async {
    SharedPreferences.setMockInitialValues({'app_locale': 'pt'});
    await service.loadSettings();

    await service.showRestTimer(45);
    expect(
      argsOf(named('show').single)['title'],
      pt.notificationRestTimerTitle,
    );
    expect(pt.notificationRestTimerTitle, isNot(en.notificationRestTimerTitle));

    SharedPreferences.setMockInitialValues({});
    await service.loadSettings();
    calls.clear();
    await service.showRestTimer(45);
    expect(
      argsOf(named('show').single)['title'],
      en.notificationRestTimerTitle,
    );
  });

  test('changing sound or vibration moves to new channels and drops '
      'stale ones', () async {
    existingChannels = [
      'rest_timer', // the single channel of earlier versions
      'rest_timer_progress',
      'rest_alert_v3',
      'workout_timer_v0',
      'unrelated_channel',
    ];
    await service.init(); // channels are only synced once initialised
    calls.clear();

    await setSettings({
      'notification_rest_timer_sound': 'false',
      'notification_rest_timer_vibration': 'true',
      'notification_workout_timer_sound': 'true',
      'notification_workout_timer_vibration': 'true',
    });

    final created = named(
      'createNotificationChannel',
    ).map((c) => argsOf(c)['id']);
    expect(created, containsAll(['rest_alert_v2', 'workout_timer_v3']));
    final deleted = named(
      'deleteNotificationChannel',
    ).map((c) => c.arguments is Map ? argsOf(c)['id'] : c.arguments);
    expect(
      deleted,
      unorderedEquals(['rest_timer', 'rest_alert_v3', 'workout_timer_v0']),
    );

    calls.clear();
    await service.showRestTimerComplete();
    expect(androidDetails(named('show').single)['channelId'], 'rest_alert_v2');
  });

  test('the workout timer counts up while running and freezes when '
      'paused', () async {
    final startedAt = DateTime(2026, 9, 1, 8, 30);

    await service.showWorkoutTimer(startedAt: startedAt);
    var shown = named('show').single;
    expect(argsOf(shown)['id'], 1002);
    expect(argsOf(shown)['title'], en.notificationWorkoutTimerTitle);
    expect(androidDetails(shown)['usesChronometer'], true);
    expect(androidDetails(shown)['when'], startedAt.millisecondsSinceEpoch);

    calls.clear();
    await service.showWorkoutTimer(
      startedAt: startedAt,
      pausedElapsed: '12:34',
    );
    shown = named('show').single;
    expect(argsOf(shown)['body'], '12:34');
    expect(androidDetails(shown)['usesChronometer'], false);
    expect(androidDetails(shown)['showWhen'], false);

    calls.clear();
    await service.cancelWorkoutTimer();
    expect(argsOf(named('cancel').single)['id'], 1002);
  });

  test('a disabled workout timer posts nothing', () async {
    await setSettings({'notification_workout_timer_enabled': 'false'});
    await service.showWorkoutTimer(startedAt: DateTime(2026, 9, 1));
    expect(named('show'), isEmpty);
  });

  group('permission', () {
    test('is prompted once and re-read from the system afterwards', () async {
      notificationsEnabled = false;
      permissionGranted = false;

      await service.showRestTimer(30);
      expect(named('show'), isEmpty);
      expect(named('requestNotificationsPermission'), hasLength(1));

      // Denied before: do not nag again, but keep reading the system state.
      await service.showRestTimer(29);
      expect(named('requestNotificationsPermission'), hasLength(1));
      expect(named('show'), isEmpty);

      // The user enabled notifications in the system settings.
      notificationsEnabled = true;
      await service.showRestTimer(28);
      expect(named('show'), hasLength(1));
    });

    test('requestPermission reports the system answer', () async {
      permissionGranted = false;
      expect(await service.requestPermission(), isFalse);
      permissionGranted = true;
      expect(await service.requestPermission(), isTrue);
    });
  });

  group('scheduled rest alert', () {
    // The plugin rejects past instants, so this one is relative to now.
    final at = DateTime.now().add(const Duration(minutes: 5));

    test('is exact when allowed, inexact otherwise', () async {
      expect(await service.scheduleRestTimerComplete(at), isTrue);
      expect(
        androidDetails(named('zonedSchedule').single)['scheduleMode'],
        'exactAllowWhileIdle',
      );

      calls.clear();
      exactAllowed = false;
      expect(await service.scheduleRestTimerComplete(at), isTrue);
      expect(
        androidDetails(named('zonedSchedule').single)['scheduleMode'],
        'inexactAllowWhileIdle',
      );
    });

    test('a platform failure means no alert was scheduled', () async {
      failZonedSchedule = true;
      expect(await service.scheduleRestTimerComplete(at), isFalse);
    });

    test('cancelRestTimer invalidates a schedule still waiting', () async {
      final pending = service.scheduleRestTimerComplete(at);
      final cancelled = service.cancelRestTimer();

      expect(await pending, isFalse);
      await cancelled;
      expect(named('zonedSchedule'), isEmpty);
      expect(argsOf(named('cancel').single)['id'], 1001);
    });
  });
}
