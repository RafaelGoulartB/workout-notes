import 'package:workout_notes/models/run_track_point.dart';
import 'package:workout_notes/utils/run_pace_analytics.dart';

/// One altitude reading along the run, keyed by cumulative distance.
class RunElevationSample {
  final double distanceMeters;
  final double altitudeMeters;

  const RunElevationSample({
    required this.distanceMeters,
    required this.altitudeMeters,
  });
}

/// Smoothed altitude profile, gain / loss and per-km climb of a GPS run.
///
/// Raw GPS altitude is noisy (several metres of jitter on flat ground), so the
/// profile is averaged over a short distance window and gain / loss only count
/// climbs larger than [hysteresisMeters].
class RunElevationProfile {
  final List<RunElevationSample> samples;
  final double gainMeters;
  final double lossMeters;
  final double? minAltitudeMeters;
  final double? maxAltitudeMeters;

  /// Climb attributed to each kilometre, keyed by the 1-based split number
  /// (the partial last split included).
  final Map<int, double> gainByKm;

  const RunElevationProfile({
    required this.samples,
    required this.gainMeters,
    required this.lossMeters,
    required this.minAltitudeMeters,
    required this.maxAltitudeMeters,
    required this.gainByKm,
  });

  static const empty = RunElevationProfile(
    samples: [],
    gainMeters: 0,
    lossMeters: 0,
    minAltitudeMeters: null,
    maxAltitudeMeters: null,
    gainByKm: {},
  );

  bool get hasData => samples.length >= 2;

  /// Distance window averaged around every reading.
  static const double smoothingWindowMeters = 100;

  /// A climb / descent only counts once it exceeds this many metres.
  static const double hysteresisMeters = 4;

  static const int maxChartSamples = 200;

  static RunElevationProfile fromTrackPoints(
    List<RunTrackPoint> points, {
    int maxSamples = maxChartSamples,
    RunTrackProfile? profile,
  }) {
    if (points.length < 2) return empty;
    final cumulative = (profile ?? RunTrackProfile.fromPoints(points))
        .cumulativeMeters;

    final distances = <double>[];
    final altitudes = <double>[];
    for (var i = 0; i < points.length; i++) {
      final altitude = points[i].altitude;
      if (altitude == null || !altitude.isFinite) continue;
      distances.add(cumulative[i]);
      altitudes.add(altitude);
    }
    if (altitudes.length < 2) return empty;

    final smoothed = _smooth(distances, altitudes);

    var gain = 0.0;
    var loss = 0.0;
    final gainByKm = <int, double>{};
    var anchor = smoothed.first;
    // Highest / lowest point since the last confirmed anchor, so a climb
    // that ends short of the threshold can still be credited to its km.
    var peak = anchor;
    var peakIndex = 0;
    var trough = anchor;
    for (var i = 1; i < smoothed.length; i++) {
      final value = smoothed[i];
      if (value > peak) {
        peak = value;
        peakIndex = i;
      }
      if (value < trough) trough = value;
      final delta = value - anchor;
      if (delta >= hysteresisMeters) {
        gain += delta;
        final km = (distances[i] / 1000).floor() + 1;
        gainByKm[km] = (gainByKm[km] ?? 0) + delta;
        anchor = value;
      } else if (delta <= -hysteresisMeters) {
        loss += -delta;
        anchor = value;
      } else {
        continue;
      }
      peak = anchor;
      peakIndex = i;
      trough = anchor;
    }
    // The last climb/descent may stop short of the threshold; keep it when it
    // is clearly more than jitter so a steady hill isn't undercounted.
    final pendingGain = peak - anchor;
    final pendingLoss = anchor - trough;
    if (pendingGain >= hysteresisMeters / 2 && pendingGain >= pendingLoss) {
      gain += pendingGain;
      final km = (distances[peakIndex] / 1000).floor() + 1;
      gainByKm[km] = (gainByKm[km] ?? 0) + pendingGain;
    } else if (pendingLoss >= hysteresisMeters / 2) {
      loss += pendingLoss;
    }

    var minAlt = smoothed.first;
    var maxAlt = smoothed.first;
    for (final value in smoothed) {
      if (value < minAlt) minAlt = value;
      if (value > maxAlt) maxAlt = value;
    }

    final all = [
      for (var i = 0; i < smoothed.length; i++)
        RunElevationSample(
          distanceMeters: distances[i],
          altitudeMeters: smoothed[i],
        ),
    ];

    return RunElevationProfile(
      samples: _downsample(all, maxSamples),
      gainMeters: gain,
      lossMeters: loss,
      minAltitudeMeters: minAlt,
      maxAltitudeMeters: maxAlt,
      gainByKm: gainByKm,
    );
  }

  /// Mean of every reading within +-half the window (two-pointer prefix sum).
  static List<double> _smooth(List<double> distances, List<double> altitudes) {
    final prefix = <double>[0.0];
    for (final value in altitudes) {
      prefix.add(prefix.last + value);
    }
    const half = smoothingWindowMeters / 2;
    final result = <double>[];
    var lo = 0;
    var hi = 0;
    for (var i = 0; i < altitudes.length; i++) {
      while (distances[i] - distances[lo] > half) {
        lo++;
      }
      if (hi < i) hi = i;
      while (hi + 1 < altitudes.length &&
          distances[hi + 1] - distances[i] <= half) {
        hi++;
      }
      result.add((prefix[hi + 1] - prefix[lo]) / (hi - lo + 1));
    }
    return result;
  }

  static List<RunElevationSample> _downsample(
    List<RunElevationSample> samples,
    int max,
  ) {
    if (samples.length <= max) return samples;
    final step = (samples.length - 1) / (max - 1);
    return [
      for (var i = 0; i < max; i++)
        samples[(i * step).round().clamp(0, samples.length - 1)],
    ];
  }
}

/// Y axis for the elevation chart: never zooms into a few metres of noise.
class RunElevationAxis {
  final double minAltitude;
  final double maxAltitude;
  final double interval;

  const RunElevationAxis({
    required this.minAltitude,
    required this.maxAltitude,
    required this.interval,
  });

  static const List<double> _steps = [5, 10, 20, 25, 50, 100, 200, 500];

  /// Smallest vertical span shown, so a flat run reads as flat.
  static const double minSpanMeters = 20;

  factory RunElevationAxis.compute(RunElevationProfile profile) {
    final lo = profile.minAltitudeMeters ?? 0;
    final hi = profile.maxAltitudeMeters ?? lo;
    var span = hi - lo;
    var low = lo;
    var high = hi;
    if (span < minSpanMeters) {
      final mid = (lo + hi) / 2;
      low = mid - minSpanMeters / 2;
      high = mid + minSpanMeters / 2;
      span = minSpanMeters;
    } else {
      final pad = span * 0.1;
      low -= pad;
      high += pad;
    }
    var step = _steps.last;
    for (final candidate in _steps) {
      if ((high - low) / candidate <= 4) {
        step = candidate;
        break;
      }
    }
    low = (low / step).floor() * step;
    high = (high / step).ceil() * step;
    return RunElevationAxis(
      minAltitude: low,
      maxAltitude: high,
      interval: step,
    );
  }
}
