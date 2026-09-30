import 'package:flutter/material.dart';
import 'package:workout_notes/models/run_track_point.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/utils/run_pace_analytics.dart';

/// Converts GPS pace into a route color relative to the activity's average.
class RunRoutePaceStyle {
  static const averageColor = Color(0xFF1976D2);
  static const transitionColor = Color(0xFF7E57C2);
  static const fastColor = Color(0xFFE53935);
  static const routeStrokeWidth = 5.0;

  static const _fullColorDifference = 0.20;
  static const _windowMeters = 300.0;
  static const _minimumWindowMeters = 100.0;
  static const _transitionMeters = 120.0;

  const RunRoutePaceStyle._();

  /// Returns one pace for every segment, smoothed over roughly 300 meters.
  /// The larger distance window creates stable color blocks and prevents GPS
  /// noise from turning every short segment into a different color.
  static List<double?> segmentPaces(
    List<RunTrackPoint> points, {
    required double? averagePaceSecPerKm,
  }) {
    if (points.length < 2) return const [];

    final cumulativeDistance = <double>[0];
    for (var index = 1; index < points.length; index++) {
      cumulativeDistance.add(
        cumulativeDistance.last +
            RunPaceAnalytics.haversineMeters(
              lat1: points[index - 1].lat,
              lng1: points[index - 1].lng,
              lat2: points[index].lat,
              lng2: points[index].lng,
            ),
      );
    }

    final rawPaces = <double?>[];
    var start = 0;
    for (var end = 1; end < points.length; end++) {
      while (start < end - 1 &&
          cumulativeDistance[end] - cumulativeDistance[start + 1] >=
              _windowMeters) {
        start++;
      }

      final distance = cumulativeDistance[end] - cumulativeDistance[start];
      final elapsedSeconds =
          points[end].recordedAt
              .difference(points[start].recordedAt)
              .inMilliseconds /
          1000;
      double? pace;
      if (distance >= _minimumWindowMeters && elapsedSeconds > 0) {
        final candidate = RunFormatters.paceSecondsPerKm(
          distance,
          elapsedSeconds,
        );
        if (candidate.isFinite &&
            candidate >= RunPaceAnalytics.minPaceSecPerKm) {
          pace = candidate;
        }
      }

      rawPaces.add(pace ?? averagePaceSecPerKm);
    }
    return _smoothPaces(rawPaces, cumulativeDistance: cumulativeDistance);
  }

  static List<double?> _smoothPaces(
    List<double?> rawPaces, {
    required List<double> cumulativeDistance,
  }) {
    if (rawPaces.length < 2) return rawPaces;

    final forward = List<double?>.filled(rawPaces.length, null);
    forward[0] = rawPaces[0];
    for (var index = 1; index < rawPaces.length; index++) {
      final segmentMeters =
          cumulativeDistance[index + 1] - cumulativeDistance[index];
      final amount = (segmentMeters / _transitionMeters).clamp(0.02, 1.0);
      forward[index] = _blend(forward[index - 1], rawPaces[index], amount);
    }

    final backward = List<double?>.filled(rawPaces.length, null);
    backward[rawPaces.length - 1] = rawPaces.last;
    for (var index = rawPaces.length - 2; index >= 0; index--) {
      final segmentMeters =
          cumulativeDistance[index + 2] - cumulativeDistance[index + 1];
      final amount = (segmentMeters / _transitionMeters).clamp(0.02, 1.0);
      backward[index] = _blend(backward[index + 1], rawPaces[index], amount);
    }

    return List<double?>.generate(rawPaces.length, (index) {
      final before = forward[index];
      final after = backward[index];
      if (before == null) return after;
      if (after == null) return before;
      return (before + after) / 2;
    }, growable: false);
  }

  static double? _blend(double? current, double? target, double amount) {
    if (current == null) return target;
    if (target == null) return current;
    return current + (target - current) * amount;
  }

  /// Average and slower sections stay blue. Sections up to 20% faster than
  /// average transition continuously from blue to red.
  static Color colorForPace({
    required double? paceSecPerKm,
    required double? averagePaceSecPerKm,
  }) => colorForFraction(
    fasterFraction(
      paceSecPerKm: paceSecPerKm,
      averagePaceSecPerKm: averagePaceSecPerKm,
    ),
  );

  /// How much faster than average a pace is, eased into 0 (average or
  /// slower) .. 1 (20% faster or more).
  static double fasterFraction({
    required double? paceSecPerKm,
    required double? averagePaceSecPerKm,
  }) {
    if (paceSecPerKm == null ||
        averagePaceSecPerKm == null ||
        paceSecPerKm <= 0 ||
        averagePaceSecPerKm <= 0) {
      return 0;
    }
    final fasterDifference =
        ((averagePaceSecPerKm - paceSecPerKm) / averagePaceSecPerKm).clamp(
          0.0,
          _fullColorDifference,
        );
    final normalized = fasterDifference / _fullColorDifference;
    return normalized * normalized * (3 - 2 * normalized);
  }

  /// Colour for an eased fraction from [fasterFraction].
  static Color colorForFraction(double eased) {
    if (eased <= 0) return averageColor;
    if (eased <= 0.5) {
      return Color.lerp(averageColor, transitionColor, eased * 2)!;
    }
    return Color.lerp(transitionColor, fastColor, (eased - 0.5) * 2)!;
  }

  /// Legend stops from "average or slower" to "fastest".
  static const List<Color> legendColors = [
    averageColor,
    transitionColor,
    fastColor,
  ];

  /// Pace at which the route reaches [fastColor] for a run averaging
  /// [averagePaceSecPerKm].
  static double fastestLegendPace(double averagePaceSecPerKm) =>
      averagePaceSecPerKm * (1 - _fullColorDifference);

  /// Groups consecutive segments of the same colour into one polyline, so a
  /// long run is drawn with dozens of polylines instead of thousands.
  /// Segment `i` joins point `i` to point `i + 1`; a run covers segments
  /// `startSegment..endSegment` (inclusive), i.e. points
  /// `startSegment..endSegment + 1`.
  static List<RunRouteColorRun> colorRuns(
    List<double?> segmentPaces, {
    required double? averagePaceSecPerKm,
    int buckets = 24,
  }) {
    final runs = <RunRouteColorRun>[];
    int? currentBucket;
    var start = 0;
    for (var i = 0; i < segmentPaces.length; i++) {
      final fraction = fasterFraction(
        paceSecPerKm: segmentPaces[i],
        averagePaceSecPerKm: averagePaceSecPerKm,
      );
      final bucket = (fraction * buckets).round();
      if (currentBucket == null) {
        currentBucket = bucket;
        start = i;
      } else if (bucket != currentBucket) {
        runs.add(
          RunRouteColorRun(
            startSegment: start,
            endSegment: i - 1,
            color: colorForFraction(currentBucket / buckets),
          ),
        );
        currentBucket = bucket;
        start = i;
      }
    }
    if (currentBucket != null) {
      runs.add(
        RunRouteColorRun(
          startSegment: start,
          endSegment: segmentPaces.length - 1,
          color: colorForFraction(currentBucket / buckets),
        ),
      );
    }
    return runs;
  }
}

/// A stretch of the route drawn in one colour.
class RunRouteColorRun {
  final int startSegment;
  final int endSegment;
  final Color color;

  const RunRouteColorRun({
    required this.startSegment,
    required this.endSegment,
    required this.color,
  });

  /// Point indexes (inclusive) the polyline of this run passes through.
  int get firstPoint => startSegment;
  int get lastPoint => endSegment + 1;
}
