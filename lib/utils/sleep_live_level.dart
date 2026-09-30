import 'dart:math' as math;

/// Maps the live microphone level of the sleep monitor to a 0–1 waveform
/// amplitude, relative to the room's own noise baseline.
abstract final class SleepLiveLevel {
  /// Decibels above the baseline that fill the waveform.
  static const double rangeDb = 30;

  /// 0 at (or below) the baseline, 1 at [rangeDb] above it. A gentle curve
  /// keeps breathing-level sounds visible without letting speech clip.
  static double normalize({
    required double levelDbfs,
    required double baselineDbfs,
  }) {
    if (!levelDbfs.isFinite || !baselineDbfs.isFinite) return 0;
    final above = ((levelDbfs - baselineDbfs) / rangeDb).clamp(0.0, 1.0);
    return math.pow(above, 0.6).toDouble();
  }
}
