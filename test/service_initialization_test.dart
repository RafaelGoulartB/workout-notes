import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/services/notification_service.dart';
import 'package:workout_notes/services/run_tracking_service.dart';
import 'package:workout_notes/services/sleep_monitor_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('shared initialisation', () {
    test('RunTrackingService.initialize shares one run', () async {
      final service = RunTrackingService.instance;
      service.resetInitializationForTest();
      final first = service.initialize();
      final second = service.initialize();
      expect(identical(first, second), isTrue);
      await first;
      // Later callers get the finished run instead of repeating it.
      expect(identical(service.initialize(), first), isTrue);
    });

    test('SleepMonitorService.initialize shares one run', () async {
      final service = SleepMonitorService.instance;
      service.resetInitializationForTest();
      final first = service.initialize();
      expect(identical(service.initialize(), first), isTrue);
      await first;
    });
  });

  group('notification channels', () {
    test('the id carries sound and vibration', () {
      String id(bool sound, bool vibration) => NotificationService.channelId(
        'rest_timer',
        sound: sound,
        vibration: vibration,
      );
      expect(id(false, false), 'rest_timer_v0');
      expect(id(true, false), 'rest_timer_v1');
      expect(id(false, true), 'rest_timer_v2');
      expect(id(true, true), 'rest_timer_v3');
    });

    test('changing a setting moves to a different channel', () {
      final before = NotificationService.channelId(
        'workout_timer',
        sound: false,
        vibration: false,
      );
      final after = NotificationService.channelId(
        'workout_timer',
        sound: true,
        vibration: false,
      );
      expect(after, isNot(before));
    });
  });
}
