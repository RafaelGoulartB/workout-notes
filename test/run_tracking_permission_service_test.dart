import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/services/run_tracking_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    calls.clear();
    messenger.setMockMethodCallHandler(RunTrackingService.methods, (
      call,
    ) async {
      calls.add(call);
      switch (call.method) {
        case 'getCapabilities':
          return <String, Object?>{
            'supported': true,
            'location_granted': false,
            'notifications_granted': false,
            'notifications_permission_required': true,
            'background_location_required': false,
          };
        case 'requestLocationPermission':
          return true;
        case 'requestNotificationPermission':
          return false;
        case 'openAppSettings':
          return true;
        case 'listPendingSpools':
          return <Map<String, Object?>>[
            <String, Object?>{
              'id': 'review-pending',
              'status': 'pending_review',
            },
          ];
        case 'readSpool':
          return <String, Object?>{
            'activity': <String, Object?>{
              'id': 'review-pending',
              'status': 'pending_review',
              'started_at': '2026-08-25T10:00:00.000Z',
              'ended_at': '2026-08-25T10:10:00.000Z',
              'duration_seconds': 600,
              'moving_time_seconds': 590,
              'distance_meters': 1500.0,
            },
            'points': <Object?>[],
          };
      }
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(RunTrackingService.methods, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'requests location and notifications through separate actions',
    () async {
      final service = RunTrackingService.instance;
      final state = await service.refreshPermissions();

      expect(state.locationGranted, isFalse);
      expect(state.notificationsNeedAttention, isTrue);
      expect(await service.requestLocationPermission(), isTrue);
      expect(await service.requestNotificationPermission(), isFalse);

      expect(
        calls.map((call) => call.method),
        containsAllInOrder(<String>[
          'getCapabilities',
          'requestLocationPermission',
          'requestNotificationPermission',
        ]),
      );
    },
  );

  test('start does not open a permission dialog implicitly', () async {
    final service = RunTrackingService.instance;
    await service.refreshPermissions();
    calls.clear();

    expect(await service.start(), isFalse);
    expect(calls.where((call) => call.method.startsWith('request')), isEmpty);
  });

  test('keeps a completed spool available as a pending review', () async {
    final reviews = await RunTrackingService.instance.listPendingReviews();

    expect(reviews, hasLength(1));
    expect(reviews.single.id, 'review-pending');
    expect(reviews.single.activity.distanceMeters, 1500);
    expect(calls.map((call) => call.method), contains('readSpool'));
  });
}
