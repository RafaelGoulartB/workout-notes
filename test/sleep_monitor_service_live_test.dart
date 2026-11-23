import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/sleep_stage_type.dart';
import 'package:workout_notes/services/sleep_monitor_service.dart';
import 'support/sleep_bedside_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'restores live evidence once from spool and ignores duplicate state snapshots',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
      });
      var latest = 3;
      var reads = 0;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SleepMonitorService.methods, (
        call,
      ) async {
        if (call.method == 'getState') {
          return {
            'supported': true,
            'status': 'running',
            'session_id': 'bedside',
            'started_at': bedsideStart.toIso8601String(),
            'latest_segment': bedsideSegment(latest, periodic: true).toMap(),
          };
        }
        if (call.method == 'readSession') {
          reads++;
          return {
            'segments': [
              for (var i = 0; i <= latest; i++)
                bedsideSegment(i, periodic: true).toMap(),
            ],
          };
        }
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(SleepMonitorService.methods, null);
      });
      final service = SleepMonitorService.instance;
      await service.getState();
      // Replayed from the first window, so the user is known awake at first.
      expect(service.liveDecision!.epoch.stage, SleepStageType.awake);
      for (var i = 0; i < 5; i++) {
        await service.getState();
      }
      expect(service.liveDecision!.epoch.stage, SleepStageType.awake);
      expect(reads, 1);
      // Each new window extends the live estimate; silence with audible
      // breathing becomes sleep within minutes. The spool is read only once.
      var asleepAt = -1;
      while (latest < 60 && asleepAt < 0) {
        latest++;
        await service.getState();
        if (service.liveDecision!.epoch.stage == SleepStageType.sleeping) {
          asleepAt = latest;
        }
      }
      expect(asleepAt, inInclusiveRange(8, 40));
      expect(reads, 1);
    },
  );

  test(
    'spool containing >45 s capture gaps replays exactly once without recursing',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
      });
      var reads = 0;
      var notifications = 0;
      // Spool with two >45 s gaps (indices 0, 1, 5, 6, 10, 11).
      var spooledIndices = [0, 1, 5, 6, 10, 11];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SleepMonitorService.methods, (
        call,
      ) async {
        if (call.method == 'getState') {
          return {
            'supported': true,
            'status': 'running',
            'session_id': 'bedside-gaps',
            'started_at': bedsideStart.toIso8601String(),
            'latest_segment': {
              ...bedsideSegment(spooledIndices.last, periodic: true).toMap(),
              'session_id': 'bedside-gaps',
            },
          };
        }
        if (call.method == 'readSession') {
          reads++;
          return {
            'segments': [
              for (final i in spooledIndices)
                {
                  ...bedsideSegment(i, periodic: true).toMap(),
                  'session_id': 'bedside-gaps',
                },
            ],
          };
        }
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(SleepMonitorService.methods, null);
      });

      final service = SleepMonitorService.instance;
      void onNotify() => notifications++;
      service.addListener(onNotify);
      addTearDown(() => service.removeListener(onNotify));

      await service.getState();
      // Give any accidental unawaited recursive restore a chance to fire.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(reads, 1);
      expect(notifications, greaterThanOrEqualTo(1));
      expect(service.liveDecision, isNotNull);

      // Simulate returning from background after >45 s of skipped events:
      // triggers one forced restore (replaying the same gaps) without looping.
      spooledIndices = [...spooledIndices, 20, 21];
      final notificationsBeforeJump = notifications;
      await service.getState();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(reads, 2);
      expect(notifications, greaterThan(notificationsBeforeJump));
    },
  );
}
