import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/models/run_track_point.dart';
import 'package:workout_notes/services/run_route_codec.dart';

/// Stores [points] as the compact route of [activityId] (`run_route_data`),
/// the only route format the app reads.
Future<void> insertCompactRoute(
  DatabaseExecutor db,
  String activityId,
  List<RunTrackPoint> points,
) async {
  final encoded = RunRouteCodec.encode(points);
  await db.insert('run_route_data', {
    'activity_id': activityId,
    'codec_version': RunRouteCodec.version,
    'quality': encoded.quality.databaseValue,
    'point_count': encoded.storedPointCount,
    'original_point_count': encoded.originalPointCount,
    'payload': encoded.payload,
    'checksum': encoded.checksum,
    'compacted_at': DateTime.now().toIso8601String(),
  });
}
