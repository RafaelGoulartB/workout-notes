import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/services/sleep_monitor_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  final alarmAt = DateTime.utc(2026, 8, 1, 10);

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    calls.clear();
    messenger.setMockMethodCallHandler(SleepMonitorService.methods, (
      call,
    ) async {
      calls.add(call);
      if (call.method == 'startMonitoring') {
        return {
          'supported': true,
          'microphone_granted': true,
          'status': 'running',
          'session_id': 'night-1',
          'started_at': DateTime.utc(2026, 8, 1, 2).toIso8601String(),
          'alarm_at': alarmAt.toIso8601String(),
          'updated_at': DateTime.utc(2026, 8, 1, 2).toIso8601String(),
          'exact_alarm_granted': true,
          'full_screen_intent_granted': true,
        };
      }
      if (call.method == 'updateAlarm') {
        final epoch =
            (call.arguments as Map<Object?, Object?>)['alarm_at_epoch_ms']
                as int;
        return {
          'supported': true,
          'microphone_granted': true,
          'status': 'running',
          'session_id': 'night-1',
          'started_at': DateTime.utc(2026, 8, 1, 2).toIso8601String(),
          'alarm_at': DateTime.fromMillisecondsSinceEpoch(
            epoch,
            isUtc: true,
          ).toIso8601String(),
          'updated_at': DateTime.utc(2026, 8, 1, 2).toIso8601String(),
          'exact_alarm_granted': true,
          'full_screen_intent_granted': true,
        };
      }
      if (call.method == 'getAlarmCapabilities') {
        return {
          'exact_alarm_granted': true,
          'full_screen_intent_granted': false,
        };
      }
      if (call.method == 'stopMonitoring') {
        return {
          'supported': true,
          'microphone_granted': true,
          'status': 'idle',
          'updated_at': DateTime.utc(2026, 8, 1, 2).toIso8601String(),
        };
      }
      if (call.method == 'listPendingSessions') return <Object?>[];
      return null;
    });
  });

  tearDown(() async {
    await SleepMonitorService.instance.stopMonitoring();
    messenger.setMockMethodCallHandler(SleepMonitorService.methods, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('passes the selected alarm instant when monitoring starts', () async {
    final service = SleepMonitorService.instance;

    final started = await service.startMonitoring(alarmAt: alarmAt);

    expect(started, isTrue);
    final call = calls.singleWhere((item) => item.method == 'startMonitoring');
    expect(
      (call.arguments as Map<Object?, Object?>)['alarm_at_epoch_ms'],
      alarmAt.millisecondsSinceEpoch,
    );
    expect(service.state.alarmAt, alarmAt);
  });

  test('atomically sends a replacement time for an active alarm', () async {
    final service = SleepMonitorService.instance;
    await service.startMonitoring(alarmAt: alarmAt);
    final replacement = alarmAt.add(const Duration(minutes: 30));

    final updated = await service.updateAlarm(replacement);

    expect(updated, isTrue);
    final call = calls.lastWhere((item) => item.method == 'updateAlarm');
    expect(
      (call.arguments as Map<Object?, Object?>)['alarm_at_epoch_ms'],
      replacement.millisecondsSinceEpoch,
    );
  });

  test('maps native alarm capabilities into state', () async {
    final service = SleepMonitorService.instance;

    final capabilities = await service.getAlarmCapabilities();

    expect(capabilities['exactAlarmGranted'], isTrue);
    expect(capabilities['fullScreenIntentGranted'], isFalse);
    expect(service.state.exactAlarmGranted, isTrue);
    expect(service.state.fullScreenIntentGranted, isFalse);
  });
}
