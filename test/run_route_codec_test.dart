import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/run_track_point.dart';
import 'package:workout_notes/services/run_route_codec.dart';
import 'package:workout_notes/utils/run_pace_analytics.dart';

void main() {
  test('round-trips a detailed route with bounded spatial and time loss', () {
    final start = DateTime.utc(2026, 8, 30, 10);
    final points = <RunTrackPoint>[
      for (var index = 0; index <= 2700; index++)
        RunTrackPoint(
          id: 'raw-$index',
          activityId: 'run-1',
          seq: index,
          lat: -23.55 + index * 0.0000025,
          lng: -46.63 + index * 0.000025,
          altitude: 700 + index / 300,
          accuracy: 5,
          speed: 3,
          recordedAt: start.add(Duration(seconds: index)),
        ),
    ];

    final encoded = RunRouteCodec.encode(points);
    final decoded = RunRouteCodec.decode(
      activityId: 'run-1',
      payload: encoded.payload,
      expectedChecksum: encoded.checksum,
    );

    expect(encoded.originalPointCount, points.length);
    expect(encoded.storedPointCount, lessThan(1000));
    expect(encoded.payload.length, lessThan(30000));
    expect(decoded, hasLength(encoded.storedPointCount));
    expect(decoded.first.recordedAt, points.first.recordedAt);
    expect(decoded.last.recordedAt, points.last.recordedAt);
    expect(
      RunPaceAnalytics.haversineMeters(
        lat1: decoded.last.lat,
        lng1: decoded.last.lng,
        lat2: points.last.lat,
        lng2: points.last.lng,
      ),
      lessThan(0.2),
    );
    expect(decoded.last.altitude, closeTo(points.last.altitude!, 0.11));
  });

  test('archived quality stores fewer points than detailed quality', () {
    final start = DateTime.utc(2026, 8, 30);
    final points = <RunTrackPoint>[
      for (var index = 0; index < 1200; index++)
        RunTrackPoint(
          id: '$index',
          activityId: 'run',
          seq: index,
          lat: -23.5 + index * 0.000004,
          lng: -46.6 + index * 0.000025,
          altitude: null,
          accuracy: 8,
          speed: 3,
          recordedAt: start.add(Duration(seconds: index)),
        ),
    ];
    final detailed = RunRouteCodec.encode(points);
    final archived = RunRouteCodec.encode(
      points,
      quality: RunRouteQuality.archived,
    );
    expect(archived.storedPointCount, lessThan(detailed.storedPointCount));
    expect(archived.payload.length, lessThan(detailed.payload.length));
  });

  test('rejects a payload whose checksum does not match', () {
    final point = RunTrackPoint(
      id: 'p',
      activityId: 'run',
      seq: 0,
      lat: 1,
      lng: 2,
      altitude: null,
      accuracy: null,
      speed: null,
      recordedAt: DateTime.utc(2026),
    );
    final encoded = RunRouteCodec.encode([point]);
    final corrupt = Uint8List.fromList(encoded.payload)..[5] ^= 0xff;
    expect(
      () => RunRouteCodec.decode(
        activityId: 'run',
        payload: corrupt,
        expectedChecksum: encoded.checksum,
      ),
      throwsFormatException,
    );
  });
}
