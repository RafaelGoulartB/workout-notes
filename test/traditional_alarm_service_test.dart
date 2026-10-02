import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/models/traditional_alarm.dart';
import 'package:workout_notes/services/sleep_mission_service.dart';
import 'package:workout_notes/services/traditional_alarm_service.dart';

import 'support/test_db.dart';

const _alarms = MethodChannel('workout_notes/traditional_alarms/methods');
const _sleep = MethodChannel('workout_notes/sleep_monitor/methods');
const _notifications = MethodChannel(
  'dexterous.com/flutter/local_notifications',
);

/// Complements `traditional_alarm_reconcile_test.dart` with the rest of the
/// service: create/save/delete mirroring to Android, failure tolerance,
/// snooze actions, permissions and the global snooze defaults.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final service = TraditionalAlarmService.instance;

  late List<MethodCall> calls;
  late List<Object?> nativeStates;
  Object? scheduleError;
  var notificationsGranted = true;
  var exactAlarmGranted = true;
  var fullScreenGranted = true;

  setUpAll(() {
    initSqfliteFfiForTests();
    AndroidFlutterLocalNotificationsPlugin.registerWith();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await installTestDb();
    calls = [];
    nativeStates = [];
    scheduleError = null;
    notificationsGranted = true;
    exactAlarmGranted = true;
    fullScreenGranted = true;
    messenger.setMockMethodCallHandler(_alarms, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'states':
          return nativeStates;
        case 'schedule':
          final error = scheduleError;
          if (error != null) {
            Error.throwWithStackTrace(error, StackTrace.current);
          }
      }
      return null;
    });
    messenger.setMockMethodCallHandler(_sleep, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'getAlarmCapabilities':
          return {
            'exact_alarm_granted': exactAlarmGranted,
            'full_screen_intent_granted': fullScreenGranted,
          };
        case 'requestExactAlarmPermission':
          return false;
        case 'requestFullScreenPermission':
          return false;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(_notifications, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'initialize':
          return true;
        case 'getNotificationChannels':
          return <Object?>[];
        case 'requestNotificationsPermission':
          return notificationsGranted;
      }
      return null;
    });
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(_alarms, null);
    messenger.setMockMethodCallHandler(_sleep, null);
    messenger.setMockMethodCallHandler(_notifications, null);
    debugDefaultTargetPlatformOverride = null;
    await uninstallTestDb();
  });

  Iterable<MethodCall> named(String method) =>
      calls.where((call) => call.method == method);

  Map<Object?, Object?> argsOf(MethodCall call) =>
      call.arguments as Map<Object?, Object?>;

  Future<TraditionalAlarm> create({
    int hour = 6,
    int minute = 45,
    List<int> weekdays = const [1, 3, 5],
    bool requiresMission = false,
    bool gradualVolume = false,
  }) => service.create(
    hour: hour,
    minute: minute,
    weekdays: weekdays,
    snoozeEnabled: true,
    snoozeMinutes: 9,
    maxSnoozes: 2,
    requiresMission: requiresMission,
    gradualVolume: gradualVolume,
  );

  Future<void> configureMission() => SleepMissionService().saveScanResult({
    'hash': 'abc123',
    'salt': 'pepper',
    'format': 'qr',
    'registered_at': '2026-09-01T08:00:00',
  });

  group('create, save and delete', () {
    test('create persists the alarm and mirrors it to Android', () async {
      var notified = 0;
      service.addListener(() => notified++);

      final alarm = await create(gradualVolume: true);

      expect(service.alarms.map((a) => a.id), contains(alarm.id));
      expect(notified, greaterThan(0));
      final args = argsOf(named('schedule').single);
      expect(args['id'], alarm.id);
      expect(args['hour'], 6);
      expect(args['minute'], 45);
      expect(args['weekdays'], [1, 3, 5]);
      expect(args['snooze_enabled'], true);
      expect(args['snooze_minutes'], 9);
      expect(args['max_snoozes'], 2);
      expect(args['requires_mission'], false);
      expect(args['gradual_volume'], true);
      expect(args['mission_hash'], isNull);
      final next = DateTime.fromMillisecondsSinceEpoch(
        args['alarm_at_epoch_ms'] as int,
      );
      expect(next.isAfter(DateTime.now()), isTrue);
      expect([next.hour, next.minute], [6, 45]);
      expect([1, 3, 5], contains(next.weekday));
    });

    test('a native failure never loses the saved alarm', () async {
      scheduleError = PlatformException(code: 'alarm_manager_unavailable');
      final alarm = await create();
      expect(service.alarms.map((a) => a.id), contains(alarm.id));

      scheduleError = MissingPluginException();
      final other = await create(hour: 7);
      expect(
        service.alarms.map((a) => a.id),
        containsAll([alarm.id, other.id]),
      );
    });

    test(
      'a mission alarm needs a configured mission to be scheduled',
      () async {
        await expectLater(
          create(requiresMission: true),
          throwsA(isA<StateError>()),
        );
        expect(named('schedule'), isEmpty);
        expect(await service.hasConfiguredMission(), isFalse);

        await configureMission();
        expect(await service.hasConfiguredMission(), isTrue);

        final alarm = await create(requiresMission: true);
        final args = argsOf(named('schedule').single);
        expect(args['id'], alarm.id);
        expect(args['requires_mission'], true);
        expect(args['mission_type'], 'barcode');
        expect(args['mission_hash'], 'abc123');
        expect(args['mission_salt'], 'pepper');
        expect(args['mission_format'], 'qr');
      },
    );

    test('save reschedules an enabled alarm with its new time', () async {
      final alarm = await create();
      calls.clear();

      await service.save(alarm.copyWith(hour: 21, minute: 5));

      final saved = service.alarms.firstWhere((a) => a.id == alarm.id);
      expect([saved.hour, saved.minute], [21, 5]);
      expect(saved.nextTriggerAt, isNotNull);
      final args = argsOf(named('schedule').single);
      expect([args['hour'], args['minute']], [21, 5]);
      expect(named('cancel'), isEmpty);
    });

    test(
      'disabling cancels the native alarm and clears the next trigger',
      () async {
        final alarm = await create();
        calls.clear();

        await service.setEnabled(alarm, false);

        final saved = service.alarms.firstWhere((a) => a.id == alarm.id);
        expect(saved.enabled, isFalse);
        expect(saved.nextTriggerAt, isNull);
        expect(argsOf(named('cancel').single)['id'], alarm.id);
        expect(named('schedule'), isEmpty);

        calls.clear();
        await service.setEnabled(saved, true);
        expect(
          service.alarms.firstWhere((a) => a.id == alarm.id).enabled,
          isTrue,
        );
        expect(named('schedule'), hasLength(1));
      },
    );

    test('delete cancels natively and removes the row', () async {
      final alarm = await create();
      calls.clear();

      await service.delete(alarm);

      expect(argsOf(named('cancel').single)['id'], alarm.id);
      expect(service.alarms.map((a) => a.id), isNot(contains(alarm.id)));
      final rows = await (await DatabaseHelper.instance.database).query(
        'traditional_alarms',
      );
      expect(rows, isEmpty);
    });

    test('delete works when the native channel is missing', () async {
      final alarm = await create();
      messenger.setMockMethodCallHandler(_alarms, null);

      await service.delete(alarm);

      expect(service.alarms, isEmpty);
    });
  });

  group('reconcile', () {
    test('imports the native schedule and exposes the snooze state', () async {
      final alarm = await create();
      final snoozedUntil = DateTime.now().add(const Duration(minutes: 9));
      nativeStates = [
        {
          'id': alarm.id,
          'enabled': true,
          'state': 'scheduled',
          'alarm_at_epoch_ms': snoozedUntil.millisecondsSinceEpoch,
          'snooze_count': 1,
          'max_snoozes': 2,
          'requires_mission': false,
        },
        {'id': 'no-epoch', 'enabled': true}, // malformed: ignored
        'not a map',
      ];
      calls.clear();

      await service.reconcile();

      final runtime = service.runtimeStateFor(alarm.id)!;
      expect(runtime.isSnoozing, isTrue);
      expect(runtime.snoozeCount, 1);
      expect(
        service.alarms.firstWhere((a) => a.id == alarm.id).nextTriggerAt,
        DateTime.fromMillisecondsSinceEpoch(
          snoozedUntil.millisecondsSinceEpoch,
        ),
      );
      // The malformed entries are neither cancelled nor tracked.
      expect(named('cancel'), isEmpty);
      expect(service.runtimeStateFor('no-epoch'), isNull);
      expect(named('restore'), hasLength(1));
      expect(named('setWakeSettings'), hasLength(1));
    });

    test(
      'a native alarm that fired and was disabled disables the row',
      () async {
        final alarm = await create(weekdays: const []);
        nativeStates = [
          {
            'id': alarm.id,
            'enabled': false,
            'state': 'fired',
            'alarm_at_epoch_ms': DateTime(
              2026,
              9,
              1,
              6,
              45,
            ).millisecondsSinceEpoch,
          },
        ];

        await service.reconcile();

        expect(
          service.alarms.firstWhere((a) => a.id == alarm.id).enabled,
          isFalse,
        );
        // Disabled alarms are not re-armed by a plain reconcile.
        expect(named('schedule').length, 1); // only the one from create()
      },
    );

    test('without the native channel it only reloads the database', () async {
      final alarm = await create();
      messenger.setMockMethodCallHandler(_alarms, null);

      await service.reconcile();

      expect(service.alarms.map((a) => a.id), contains(alarm.id));
      expect(service.runtimeStateFor(alarm.id), isNull);
    });

    test('off Android there are no native calls at all', () async {
      final alarm = await create();
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      calls.clear();

      await service.initialize();

      expect(calls, isEmpty);
      expect(service.alarms.map((a) => a.id), contains(alarm.id));
      expect(service.runtimeStateFor(alarm.id), isNull);
    });
  });

  group('snooze actions', () {
    test(
      'open the snoozed mission / dismiss the snooze then reconcile',
      () async {
        await service.openSnoozedMission('a1');
        expect(
          calls.map((c) => c.method),
          containsAllInOrder(['openSnoozedMission', 'states', 'restore']),
        );
        expect(argsOf(named('openSnoozedMission').single)['id'], 'a1');

        calls.clear();
        await service.dismissSnooze('a2');
        expect(argsOf(named('dismissSnooze').single)['id'], 'a2');
        expect(named('states'), hasLength(1));
      },
    );

    test('are no-ops off Android', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      await service.openSnoozedMission('a1');
      await service.dismissSnooze('a1');

      expect(calls, isEmpty);
    });
  });

  group('preparePermissions', () {
    test('is true off Android without asking anything', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(await service.preparePermissions(), isTrue);
      expect(calls, isEmpty);
    });

    test('stops when notifications are denied', () async {
      notificationsGranted = false;

      expect(await service.preparePermissions(), isFalse);

      expect(named('getAlarmCapabilities'), isEmpty);
    });

    test('sends the user to the exact-alarm setting when missing', () async {
      exactAlarmGranted = false;

      expect(await service.preparePermissions(), isFalse);

      expect(named('requestExactAlarmPermission'), hasLength(1));
      expect(named('requestFullScreenPermission'), isEmpty);
    });

    test('asks for the full-screen intent but still succeeds', () async {
      fullScreenGranted = false;

      expect(await service.preparePermissions(), isTrue);

      expect(named('requestFullScreenPermission'), hasLength(1));
    });

    test('succeeds when everything is granted', () async {
      expect(await service.preparePermissions(), isTrue);
      expect(named('requestExactAlarmPermission'), isEmpty);
      expect(named('requestFullScreenPermission'), isEmpty);
    });
  });

  group('global snooze defaults', () {
    test('default to three snoozes, enabled', () async {
      expect(await service.getGlobalMaxSnoozes(), 3);
      expect(await service.getGlobalSnoozeEnabled(), isTrue);
    });

    test('are stored and the snooze count is clamped to 0..10', () async {
      await service.setGlobalMaxSnoozes(7);
      expect(await service.getGlobalMaxSnoozes(), 7);

      await service.setGlobalMaxSnoozes(99);
      expect(await service.getGlobalMaxSnoozes(), 10);
      await service.setGlobalMaxSnoozes(-4);
      expect(await service.getGlobalMaxSnoozes(), 0);

      await service.setGlobalSnoozeEnabled(false);
      expect(await service.getGlobalSnoozeEnabled(), isFalse);
      await service.setGlobalSnoozeEnabled(true);
      expect(await service.getGlobalSnoozeEnabled(), isTrue);
    });

    test('a corrupt stored value falls back to the default', () async {
      await DatabaseHelper.instance.settingsRepo.setSetting(
        TraditionalAlarmService.globalMaxSnoozesKey,
        'many',
      );
      expect(await service.getGlobalMaxSnoozes(), 3);
    });
  });
}
