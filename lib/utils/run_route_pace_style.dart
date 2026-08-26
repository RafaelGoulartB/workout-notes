import 'package:flutter/material.dart';
import 'package:workout_notes/models/run_track_point.dart';
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
        final candidate = elapsedSeconds / (distance / 1000);
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
  }) {
    if (paceSecPerKm == null ||
        averagePaceSecPerKm == null ||
        paceSecPerKm <= 0 ||
        averagePaceSecPerKm <= 0) {
      return averageColor;
    }

    final fasterDifference =
        ((averagePaceSecPerKm - paceSecPerKm) / averagePaceSecPerKm).clamp(
          0.0,
          _fullColorDifference,
        );
    final normalized = fasterDifference / _fullColorDifference;
    final eased = normalized * normalized * (3 - 2 * normalized);
    if (eased <= 0.5) {
      return Color.lerp(averageColor, transitionColor, eased * 2)!;
    }
    return Color.lerp(transitionColor, fastColor, (eased - 0.5) * 2)!;
  }
}
