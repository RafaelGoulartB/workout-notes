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
}
