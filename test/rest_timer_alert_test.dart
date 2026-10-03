import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_notes/services/notification_service.dart';
import 'package:workout_notes/services/rest_timer_service.dart';

import 'support/test_db.dart';

const _channel = MethodChannel('dexterous.com/flutter/local_notifications');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RestTimerService.alertsInApp', () {
    final alertAt = DateTime(2026, 9, 1, 10, 0, 2);

    test('alerts when no background alert was scheduled', () {
      expect(
        RestTimerService.alertsInApp(
          alertScheduled: false,
          alertAt: alertAt,
          now: alertAt.add(const Duration(minutes: 5)),
        ),
        isTrue,
      );
    });

    test('alerts when the app finishes before the background alert', () {
      expect(
        RestTimerService.alertsInApp(
          alertScheduled: true,
          alertAt: alertAt,
          now: alertAt.subtract(const Duration(seconds: 1)),
        ),
        isTrue,
      );
    });

    test('stays quiet once the scheduled alert has already rung', () {
      expect(
        RestTimerService.alertsInApp(
          alertScheduled: true,
          alertAt: alertAt,
          now: alertAt,
        ),
        isFalse,
      );
    });
  });

  group('rest timer background alert', () {
    final calls = <MethodCall>[];
    var exactAllowed = true;
    var notificationsEnabled = true;

    setUpAll(() async {
      initSqfliteFfiForTests();
      AndroidFlutterLocalNotificationsPlugin.registerWith();
    });

    setUp(() async {
      calls.clear();
      exactAllowed = true;
      notificationsEnabled = true;
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
                return false;
              case 'canScheduleExactNotifications':
                return exactAllowed;
              case 'getNotificationChannels':
                return <Object?>[];
            }
            return null;
          });
    });

    tearDown(() async {
      RestTimerService.instance.stop();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null);
      await uninstallTestDb();
    });

    Iterable<MethodCall> named(String method) =>
        calls.where((c) => c.method == method);

    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 50));

    test(
      'start schedules an exact alert after the end plus the grace',
      () async {
        final before = DateTime.now();
        RestTimerService.instance.start(60);
        await settle();

        final scheduled = named('zonedSchedule').single;
        final args = scheduled.arguments as Map;
        expect(args['id'], 1001);
        expect(
          (args['platformSpecifics'] as Map)['scheduleMode'],
          'exactAllowWhileIdle',
        );
        // The channel is the alerting one, not the silent countdown channel.
        expect(
          (args['platformSpecifics'] as Map)['channelId'] as String,
          startsWith('rest_alert_v'),
        );
        // The instant is sent as UTC wall-clock fields plus the zone name.
        expect(args['timeZoneName'], 'Etc/UTC');
        final raw = args['scheduledDateTime'] as String;
        final at = DateTime.parse(raw.endsWith('Z') ? raw : '${raw}Z');
        final expected = before.add(
          const Duration(seconds: 60) + NotificationService.restAlertGrace,
        );
        expect(
          at.difference(expected).inMilliseconds.abs(),
          lessThan(2000),
          reason: 'scheduled at $at, expected about $expected',
        );
      },
    );

    test(
      'falls back to an inexact alert without the exact alarm grant',
      () async {
        exactAllowed = false;

        RestTimerService.instance.start(60);
        await settle();

        final args = named('zonedSchedule').single.arguments as Map;
        expect(
          (args['platformSpecifics'] as Map)['scheduleMode'],
          'inexactAllowWhileIdle',
        );
      },
    );

    test(
      'pause and stop cancel it, resume and a restart reschedule it',
      () async {
        final service = RestTimerService.instance;
        service.start(60);
        await settle();
        expect(named('zonedSchedule'), hasLength(1));

        service.pause();
        await settle();
        expect(named('cancel'), hasLength(1));
        expect((named('cancel').single.arguments as Map)['id'], 1001);

        service.resume();
        await settle();
        expect(named('zonedSchedule'), hasLength(2));

        service.start(30); // adjusting replaces the alert (same id)
        await settle();
        expect(named('zonedSchedule'), hasLength(3));

        service.stop();
        await settle();
        expect(named('cancel'), hasLength(2));
      },
    );

    test('a stop right after start leaves nothing scheduled', () async {
      final service = RestTimerService.instance;
      service.start(60);
      service.stop(); // before the plugin finished initialising
      await settle();

      expect(named('zonedSchedule'), isEmpty);
      expect(named('cancel'), isNotEmpty);
    });

    test('notification permission is re-read, not cached', () async {
      notificationsEnabled = false;
      expect(
        await NotificationService.instance.scheduleRestTimerComplete(
          DateTime.now().add(const Duration(minutes: 1)),
        ),
        isFalse,
      );
      expect(named('zonedSchedule'), isEmpty);

      notificationsEnabled = true;
      expect(
        await NotificationService.instance.scheduleRestTimerComplete(
          DateTime.now().add(const Duration(minutes: 1)),
        ),
        isTrue,
      );
      expect(named('zonedSchedule'), hasLength(1));
    });
  });
}
