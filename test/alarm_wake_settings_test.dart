import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/models/alarm_wake_settings.dart';
import 'package:workout_notes/models/sleep_monitor_session.dart';
import 'package:workout_notes/repositories/traditional_alarm_repository.dart';
import 'package:workout_notes/services/alarm_wake_settings_service.dart';
import 'support/test_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initSqfliteFfiForTests);
  setUp(installTestDb);
  tearDown(uninstallTestDb);

  test('persists choices and ignores values outside the options', () async {
    final service = AlarmWakeSettingsService();
    const chosen = AlarmWakeSettings(
      windowMinutes: 20,
      sensitivity: SmartWakeSensitivity.conservative,
      rampSeconds: 300,
      boost: false,
    );
    await service.save(chosen);
    expect(await service.load(), chosen);

    final settings = DatabaseHelper.instance.settingsRepo;
    await settings.setSetting(AlarmWakeSettingsService.windowKey, '17');
    await settings.setSetting(AlarmWakeSettingsService.rampKey, 'x');
    await settings.setSetting(AlarmWakeSettingsService.sensitivityKey, '?');
    final fallback = await service.load();
    expect(fallback.windowMinutes, AlarmWakeSettings.defaultWindowMinutes);
    expect(fallback.rampSeconds, AlarmWakeSettings.defaultRampSeconds);
    expect(fallback.sensitivity, SmartWakeSensitivity.balanced);
  });

  test('mirrors the volume rise to Android on save', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const channel = MethodChannel('workout_notes/traditional_alarms/methods');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await AlarmWakeSettingsService().save(
      const AlarmWakeSettings(rampSeconds: 60, boost: false),
    );

    final call = calls.single;
    expect(call.method, 'setWakeSettings');
    expect(call.arguments, {'ramp_seconds': 60, 'boost': false});
  });

  test('the smart window start follows the wake time', () {
    final deadline = DateTime(2026, 9, 30, 7);
    expect(
      AlarmWakeSettings.defaults.windowStartFor(deadline),
      DateTime(2026, 9, 30, 6, 30),
    );
    expect(
      const AlarmWakeSettings(windowMinutes: 0).windowStartFor(deadline),
      isNull,
    );
  });

  test('a standalone alarm keeps its gradual volume choice', () async {
    final repository = TraditionalAlarmRepository();
    final alarm = await repository.insert(
      hour: 6,
      minute: 45,
      weekdays: const [],
      snoozeEnabled: true,
      snoozeMinutes: 5,
      maxSnoozes: 3,
      requiresMission: false,
      gradualVolume: true,
    );
    expect((await repository.getAll()).single.gradualVolume, isTrue);
    await repository.update(alarm.copyWith(gradualVolume: false));
    expect((await repository.getAll()).single.gradualVolume, isFalse);
  });

  group('smart alarm result of a night', () {
    SleepMonitorSession night({
      DateTime? firedAt,
      String? trigger,
      int? window = 30,
    }) => SleepMonitorSession(
      id: 'night',
      sleepEntryId: null,
      status: SleepMonitorSession.completed,
      startedAt: DateTime.utc(2026, 9, 29, 23),
      endedAt: firedAt ?? DateTime.utc(2026, 9, 30, 10),
      alarmAt: DateTime.utc(2026, 9, 30, 10),
      utcOffsetStartMinutes: -180,
      utcOffsetEndMinutes: -180,
      sensorMode: 'audio_bedside',
      algorithmVersion: 'audio-features-v5',
      timeInBedMinutes: 660,
      quietMinutes: null,
      noisyMinutes: null,
      estimatedSleepMinutes: null,
      noiseEventCount: 0,
      signalQualityScore: null,
      endReason: 'alarm',
      createdAt: DateTime.utc(2026, 9, 29, 23),
      smartWindowMinutes: window,
      alarmFiredAt: firedAt,
      alarmTrigger: trigger,
    );

    test('reports how early it rang and survives a round trip', () {
      final early = night(
        firedAt: DateTime.utc(2026, 9, 30, 9, 47, 10),
        trigger: SleepMonitorSession.triggerStirring,
      );
      expect(early.smartWindowStart, DateTime.utc(2026, 9, 30, 9, 30));
      expect(early.smartWakeLeadMinutes, 13);
      final restored = SleepMonitorSession.fromMap(
        early.copyWith(wakeFeeling: 3).toMap(),
      );
      expect(restored.smartWindowMinutes, 30);
      expect(restored.alarmFiredAt, early.alarmFiredAt);
      expect(restored.alarmTrigger, SleepMonitorSession.triggerStirring);
      expect(restored.wakeFeeling, 3);
    });

    test('a ring at the deadline or without a window is not early', () {
      expect(
        night(
          firedAt: DateTime.utc(2026, 9, 30, 10),
          trigger: SleepMonitorSession.triggerDeadline,
        ).smartWakeLeadMinutes,
        isNull,
      );
      expect(night(window: null).smartWindowStart, isNull);
    });
  });
}
