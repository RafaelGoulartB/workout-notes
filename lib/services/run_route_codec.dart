import 'dart:math' as math;
import 'dart:typed_data';

import 'package:workout_notes/models/run_track_point.dart';
import 'package:workout_notes/utils/run_pace_analytics.dart';

enum RunRouteQuality { detailed, archived }

extension RunRouteQualityValue on RunRouteQuality {
  String get databaseValue => name;

  static RunRouteQuality fromDatabase(Object? value) =>
      value == RunRouteQuality.archived.name
      ? RunRouteQuality.archived
      : RunRouteQuality.detailed;
}

class EncodedRunRoute {
  final Uint8List payload;
  final int checksum;
  final int originalPointCount;
  final int storedPointCount;
  final RunRouteQuality quality;

  const EncodedRunRoute({
    required this.payload,
    required this.checksum,
    required this.originalPointCount,
    required this.storedPointCount,
    required this.quality,
  });
}

/// Versioned compact route codec.
///
/// Coordinates are stored as delta-encoded microdegrees, timestamps as
/// millisecond deltas and altitude as signed decimetres. Point UUIDs,
/// repeated activity UUIDs, ISO timestamps, speed and accuracy are omitted.
/// Speed remains derivable from distance/time and accuracy is summarized when
/// the activity is imported.
abstract final class RunRouteCodec {
  static const int version = 1;
  static const _magic = <int>[0x57, 0x4e, 0x52, 0x31]; // WNR1
  static const _maxDecodedPoints = 1000000;

  static EncodedRunRoute encode(
    List<RunTrackPoint> input, {
    RunRouteQuality quality = RunRouteQuality.detailed,
  }) {
    final ordered = List<RunTrackPoint>.of(input)
      ..sort((a, b) => a.seq.compareTo(b.seq));
    final points = _simplify(ordered, quality);
    final writer = _VarintWriter()..addBytes(_magic);
    writer
      ..addUnsigned(version)
      ..addUnsigned(quality.index)
      ..addUnsigned(points.length);

    var previousLat = 0;
    var previousLng = 0;
    var previousTime = 0;
    for (final point in points) {
      final lat = (point.lat * 1000000).round();
      final lng = (point.lng * 1000000).round();
      final time = point.recordedAt.millisecondsSinceEpoch;
      writer
        ..addSigned(lat - previousLat)
        ..addSigned(lng - previousLng)
        ..addSigned(time - previousTime);
      previousLat = lat;
      previousLng = lng;
      previousTime = time;
      final altitude = point.altitude;
      writer.addUnsigned(altitude == null ? 0 : 1);
      if (altitude != null) writer.addSigned((altitude * 10).round());
    }

    final payload = writer.takeBytes();
    return EncodedRunRoute(
      payload: payload,
      checksum: checksum(payload),
      originalPointCount: input.length,
      storedPointCount: points.length,
      quality: quality,
    );
  }

  static List<RunTrackPoint> decode({
    required String activityId,
    required Uint8List payload,
    int? expectedChecksum,
  }) {
    if (expectedChecksum != null && checksum(payload) != expectedChecksum) {
      throw const FormatException('run_route_checksum_mismatch');
    }
    final reader = _VarintReader(payload);
    for (final byte in _magic) {
      if (reader.readByte() != byte) {
        throw const FormatException('run_route_invalid_magic');
      }
    }
    if (reader.readUnsigned() != version) {
      throw const FormatException('run_route_unsupported_version');
    }
    final qualityIndex = reader.readUnsigned();
    if (qualityIndex < 0 || qualityIndex >= RunRouteQuality.values.length) {
      throw const FormatException('run_route_invalid_quality');
    }
    final count = reader.readUnsigned();
    if (count < 0 || count > _maxDecodedPoints) {
      throw const FormatException('run_route_invalid_point_count');
    }

    final points = <RunTrackPoint>[];
    var lat = 0;
    var lng = 0;
    var time = 0;
    for (var index = 0; index < count; index++) {
      lat += reader.readSigned();
      lng += reader.readSigned();
      time += reader.readSigned();
      final hasAltitude = reader.readUnsigned();
      if (hasAltitude != 0 && hasAltitude != 1) {
        throw const FormatException('run_route_invalid_altitude_flag');
      }
      final altitude = hasAltitude == 1 ? reader.readSigned() / 10.0 : null;
      points.add(
        RunTrackPoint(
          id: '$activityId:$index',
          activityId: activityId,
          seq: index,
          lat: lat / 1000000.0,
          lng: lng / 1000000.0,
          altitude: altitude,
          accuracy: null,
          speed: null,
          recordedAt: DateTime.fromMillisecondsSinceEpoch(time, isUtc: true),
        ),
      );
    }
    if (!reader.isAtEnd) {
      throw const FormatException('run_route_trailing_bytes');
    }
    return points;
  }

  static int checksum(Uint8List bytes) {
    var crc = 0xffffffff;
    for (final byte in bytes) {
      crc ^= byte;
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
      }
    }
    return (crc ^ 0xffffffff) & 0xffffffff;
  }

  static List<RunTrackPoint> _simplify(
    List<RunTrackPoint> points,
    RunRouteQuality quality,
  ) {
    if (points.length <= 2) return points;
    final tolerance = quality == RunRouteQuality.detailed ? 3.0 : 8.0;
    final maxSeconds = quality == RunRouteQuality.detailed ? 5.0 : 10.0;
    final maxMeters = quality == RunRouteQuality.detailed ? 10.0 : 25.0;

    final keep = _douglasPeuckerIndices(points, tolerance)
      ..addAll({0, points.length - 1});
    for (var index = 1; index < points.length; index++) {
      final gap =
          points[index].recordedAt
              .difference(points[index - 1].recordedAt)
              .inMilliseconds
              .abs() /
          1000.0;
      if (gap > maxSeconds * 2) {
        keep
          ..add(index - 1)
          ..add(index);
      }
    }

    var anchor = 0;
    for (var index = 1; index < points.length - 1; index++) {
      final elapsed =
          points[index].recordedAt
              .difference(points[anchor].recordedAt)
              .inMilliseconds
              .abs() /
          1000.0;
      final distance = _distance(points[anchor], points[index]);
      if (elapsed >= maxSeconds || distance >= maxMeters) {
        keep.add(index);
        anchor = index;
      } else if (keep.contains(index)) {
        anchor = index;
      }
    }
    final indices = keep.toList()..sort();
    return [for (final index in indices) points[index]];
  }

  static Set<int> _douglasPeuckerIndices(
    List<RunTrackPoint> points,
    double toleranceMeters,
  ) {
    final keep = <int>{0, points.length - 1};
    final stack = <(int, int)>[(0, points.length - 1)];
    while (stack.isNotEmpty) {
      final (start, end) = stack.removeLast();
      var bestIndex = -1;
      var bestDistance = 0.0;
      for (var index = start + 1; index < end; index++) {
        final distance = _distanceToSegment(
          points[index],
          points[start],
          points[end],
        );
        if (distance > bestDistance) {
          bestDistance = distance;
          bestIndex = index;
        }
      }
      if (bestIndex >= 0 && bestDistance > toleranceMeters) {
        keep.add(bestIndex);
        stack
          ..add((start, bestIndex))
          ..add((bestIndex, end));
      }
    }
    return keep;
  }

  static double _distanceToSegment(
    RunTrackPoint point,
    RunTrackPoint start,
    RunTrackPoint end,
  ) {
    final referenceLat = (start.lat + end.lat + point.lat) / 3;
    final scaleX = 111320.0 * math.cos(referenceLat * math.pi / 180);
    const scaleY = 110540.0;
    final px = (point.lng - start.lng) * scaleX;
    final py = (point.lat - start.lat) * scaleY;
    final ex = (end.lng - start.lng) * scaleX;
    final ey = (end.lat - start.lat) * scaleY;
    final lengthSquared = ex * ex + ey * ey;
    if (lengthSquared <= 0) return math.sqrt(px * px + py * py);
    final t = ((px * ex + py * ey) / lengthSquared).clamp(0.0, 1.0);
    final dx = px - ex * t;
    final dy = py - ey * t;
    return math.sqrt(dx * dx + dy * dy);
  }

  static double _distance(RunTrackPoint a, RunTrackPoint b) =>
      RunPaceAnalytics.haversineMeters(
        lat1: a.lat,
        lng1: a.lng,
        lat2: b.lat,
        lng2: b.lng,
      );
}

class _VarintWriter {
  final _bytes = <int>[];

  void addBytes(Iterable<int> values) => _bytes.addAll(values);

  void addUnsigned(int value) {
    if (value < 0) throw ArgumentError.value(value, 'value');
    var remaining = value;
    while (remaining >= 0x80) {
      _bytes.add((remaining & 0x7f) | 0x80);
      remaining >>= 7;
    }
    _bytes.add(remaining);
  }

  void addSigned(int value) => addUnsigned((value << 1) ^ (value >> 63));

  Uint8List takeBytes() => Uint8List.fromList(_bytes);
}

class _VarintReader {
  final Uint8List bytes;
  int _offset = 0;

  _VarintReader(this.bytes);

  bool get isAtEnd => _offset == bytes.length;

  int readByte() {
    if (_offset >= bytes.length) {
      throw const FormatException('run_route_unexpected_end');
    }
    return bytes[_offset++];
  }

  int readUnsigned() {
    var result = 0;
    var shift = 0;
    while (shift <= 63) {
      final byte = readByte();
      result |= (byte & 0x7f) << shift;
      if ((byte & 0x80) == 0) return result;
      shift += 7;
    }
    throw const FormatException('run_route_invalid_varint');
  }

  int readSigned() {
    final value = readUnsigned();
    return (value >> 1) ^ -(value & 1);
  }
}
