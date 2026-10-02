import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_notes/services/traditional_alarm_service.dart';

import 'support/test_db.dart';

const _channel = MethodChannel('workout_notes/traditional_alarms/methods');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> calls;
  late List<Map<String, Object?>> nativeStates;

  setUpAll(initSqfliteFfiForTests);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await installTestDb();
    calls = [];
    nativeStates = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls.add(call);
          if (call.method == 'states') return nativeStates;
          if (call.method == 'cancel') {
            final id = (call.arguments as Map)['id'];
            nativeStates = [
              for (final state in nativeStates)
                if (state['id'] != id) state,
            ];
          }
          return null;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    debugDefaultTargetPlatformOverride = null;
    await uninstallTestDb();
  });

  Map<String, Object?> nativeState(String id, DateTime at) => {
    'id': id,
    'enabled': true,
    'state': 'scheduled',
    'alarm_at_epoch_ms': at.millisecondsSinceEpoch,
    'snooze_count': 0,
    'max_snoozes': 3,
    'requires_mission': false,
  };

  Iterable<String> ids(String method) => calls
      .where((call) => call.method == method)
      .map((call) => (call.arguments as Map)['id'] as String);

  Future<String> createAlarm(int hour, int minute) async {
    final alarm = await TraditionalAlarmService.instance.create(
      hour: hour,
      minute: minute,
      weekdays: const [],
      snoozeEnabled: true,
      snoozeMinutes: 5,
      maxSnoozes: 3,
      requiresMission: false,
    );
    return alarm.id;
  }

  test('cancels native alarms that are no longer in the database', () async {
    final service = TraditionalAlarmService.instance;
    final id = await createAlarm(7, 30);
    calls.clear();
    final soon = DateTime.now().add(const Duration(hours: 1));
    nativeStates = [
      nativeState(id, soon),
      nativeState('deleted-by-restore', soon),
    ];

    await service.reconcile();

    expect(ids('cancel'), ['deleted-by-restore']);
    expect(ids('schedule'), isEmpty);
    expect(service.runtimeStateFor('deleted-by-restore'), isNull);
    expect(service.runtimeStateFor(id), isNotNull);
  });

  test('schedules a database alarm that has no native snapshot', () async {
    final id = await createAlarm(7, 30);
    calls.clear();

    await TraditionalAlarmService.instance.reconcile();

    expect(ids('schedule'), [id]);
    expect(ids('cancel'), isEmpty);
  });

  test('resync reschedules enabled alarms and cancels disabled ones', () async {
    final service = TraditionalAlarmService.instance;
    final enabledId = await createAlarm(7, 30);
    final disabledId = await createAlarm(8, 0);
    final disabled = service.alarms.firstWhere((a) => a.id == disabledId);
    await service.setEnabled(disabled, false);
    calls.clear();
    final soon = DateTime.now().add(const Duration(hours: 1));
    // A restore reused both ids; the native side still has the old times.
    nativeStates = [
      nativeState(enabledId, soon),
      nativeState(disabledId, soon),
    ];

    await service.reconcile(resync: true);

    expect(ids('schedule'), contains(enabledId));
    expect(ids('schedule'), isNot(contains(disabledId)));
    expect(ids('cancel'), [disabledId]);
    // The database wins: native state never re-enables a restored alarm.
    expect(service.alarms.firstWhere((a) => a.id == disabledId).enabled, false);
    final scheduled = calls.firstWhere((call) => call.method == 'schedule');
    expect((scheduled.arguments as Map)['hour'], 7);
    expect((scheduled.arguments as Map)['minute'], 30);
  });
}
