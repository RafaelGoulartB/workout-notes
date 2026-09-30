import 'package:workout_notes/models/run_track_point.dart';
import 'package:workout_notes/utils/run_pace_analytics.dart';

/// Cumulative distance along a GPS trail, so a distance on a chart can be
/// mapped back to a spot on the map (and the other way around).
class RunRouteGeometry {
  final List<RunTrackPoint> points;

  /// Cumulative metres at each point; same length as [points].
  final List<double> cumulativeMeters;

  const RunRouteGeometry._(this.points, this.cumulativeMeters);

  static const RunRouteGeometry empty = RunRouteGeometry._([], []);

  /// Ignore tiny GPS hops so stationary jitter does not inflate distance.
  static const double minStepMeters = RunPaceAnalytics.minStepMeters;

  factory RunRouteGeometry.fromPoints(
    List<RunTrackPoint> points, {
    RunTrackProfile? profile,
  }) {
    if (points.isEmpty) return empty;
    return RunRouteGeometry._(
      points,
      (profile ?? RunTrackProfile.fromPoints(points)).cumulativeMeters,
    );
  }

  bool get isEmpty => points.isEmpty;
  double get totalMeters =>
      cumulativeMeters.isEmpty ? 0 : cumulativeMeters.last;

  /// Index of the last point at or before [meters].
  int indexAtDistance(double meters) {
    if (cumulativeMeters.isEmpty) return 0;
    var low = 0;
    var high = cumulativeMeters.length - 1;
    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      if (cumulativeMeters[mid] <= meters) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low;
  }

  /// Interpolated position at [meters] from the start; clamped to the trail.
  ({double lat, double lng})? positionAtDistance(double meters) {
    if (points.isEmpty) return null;
    if (points.length == 1 || meters <= 0) {
      return (lat: points.first.lat, lng: points.first.lng);
    }
    if (meters >= totalMeters) {
      return (lat: points.last.lat, lng: points.last.lng);
    }
    final index = indexAtDistance(meters);
    if (index >= points.length - 1) {
      return (lat: points.last.lat, lng: points.last.lng);
    }
    final from = points[index];
    final to = points[index + 1];
    final span = cumulativeMeters[index + 1] - cumulativeMeters[index];
    final fraction = span <= 0
        ? 0.0
        : ((meters - cumulativeMeters[index]) / span).clamp(0.0, 1.0);
    return (
      lat: from.lat + (to.lat - from.lat) * fraction,
      lng: from.lng + (to.lng - from.lng) * fraction,
    );
  }

  /// Bounding box `(minLat, minLng, maxLat, maxLng)`, or null when the trail
  /// is a single spot (about 11 m or less), which flutter_map cannot fit.
  static ({double minLat, double minLng, double maxLat, double maxLng})?
  boundsOf(Iterable<({double lat, double lng})> coordinates) {
    double? minLat;
    double? maxLat;
    double? minLng;
    double? maxLng;
    for (final c in coordinates) {
      minLat = minLat == null || c.lat < minLat ? c.lat : minLat;
      maxLat = maxLat == null || c.lat > maxLat ? c.lat : maxLat;
      minLng = minLng == null || c.lng < minLng ? c.lng : minLng;
      maxLng = maxLng == null || c.lng > maxLng ? c.lng : maxLng;
    }
    if (minLat == null || maxLat == null || minLng == null || maxLng == null) {
      return null;
    }
    if ((maxLat - minLat) < 1e-4 && (maxLng - minLng) < 1e-4) return null;
    return (minLat: minLat, minLng: minLng, maxLat: maxLat, maxLng: maxLng);
  }
}
