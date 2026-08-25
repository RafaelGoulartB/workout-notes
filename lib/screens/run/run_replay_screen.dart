import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/models/run_track_point.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/utils/run_pace_analytics.dart';
import 'package:workout_notes/utils/run_route_pace_style.dart';

/// A short, accelerated playback of a completed run's GPS trail.
class RunReplayScreen extends StatefulWidget {
  final RunActivity activity;
  final List<RunTrackPoint> points;
  final bool showMapTiles;

  const RunReplayScreen({
    super.key,
    required this.activity,
    required this.points,
    this.showMapTiles = true,
  }) : assert(points.length >= 2);

  /// Replays the activity at 60x speed: every real minute takes one second.
  @visibleForTesting
  static Duration replayDurationFor(int movingTimeSeconds) {
    final milliseconds = (movingTimeSeconds * 1000 / 60).round();
    return Duration(milliseconds: milliseconds < 1 ? 1 : milliseconds);
  }

  @override
  State<RunReplayScreen> createState() => _RunReplayScreenState();
}

class _RunReplayScreenState extends State<RunReplayScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<RunTrackPoint> _points;
  late final List<double> _timeline;
  late final List<double> _cumulativeDistance;
  late final List<double?> _segmentPaces;

  @override
  void initState() {
    super.initState();
    _points = List<RunTrackPoint>.of(widget.points)
      ..sort((a, b) => a.seq.compareTo(b.seq));
    _timeline = _buildTimeline(_points);
    _cumulativeDistance = _buildCumulativeDistance(_points);
    _segmentPaces = RunRoutePaceStyle.segmentPaces(
      _points,
      averagePaceSecPerKm: widget.activity.avgPaceSecPerKm,
    );
    _controller = AnimationController(
      vsync: this,
      duration: RunReplayScreen.replayDurationFor(
        widget.activity.movingTimeSeconds,
      ),
    )..addListener(_onTick);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onTick)
      ..dispose();
    super.dispose();
  }

  void _onTick() => setState(() {});

  void _togglePlayback() {
    if (_controller.isAnimating) {
      _controller.stop();
    } else if (_controller.isCompleted) {
      _controller.forward(from: 0);
    } else {
      _controller.forward();
    }
    setState(() {});
  }

  static List<double> _buildTimeline(List<RunTrackPoint> points) {
    if (points.length < 2) return const [0];
    final start = points.first.recordedAt.millisecondsSinceEpoch;
    final span = points.last.recordedAt.millisecondsSinceEpoch - start;
    if (span <= 0) {
      return List<double>.generate(
        points.length,
        (index) => index / (points.length - 1),
      );
    }
    final timeline = <double>[];
    var previous = 0.0;
    for (final point in points) {
      final normalized =
          ((point.recordedAt.millisecondsSinceEpoch - start) / span).clamp(
            0.0,
            1.0,
          );
      previous = normalized < previous ? previous : normalized;
      timeline.add(previous);
    }
    return timeline;
  }

  static List<double> _buildCumulativeDistance(List<RunTrackPoint> points) {
    if (points.isEmpty) return const [];
    final result = <double>[0];
    for (var index = 1; index < points.length; index++) {
      final previous = points[index - 1];
      final current = points[index];
      final segment = RunPaceAnalytics.haversineMeters(
        lat1: previous.lat,
        lng1: previous.lng,
        lat2: current.lat,
        lng2: current.lng,
      );
      result.add(result.last + segment);
    }
    return result;
  }

  int _pointIndexAt(double progress) {
    var low = 0;
    var high = _timeline.length - 1;
    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      if (_timeline[mid] <= progress) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low;
  }

  double _segmentFraction(int index, double progress) {
    if (index >= _points.length - 1) return 0;
    final start = _timeline[index];
    final end = _timeline[index + 1];
    if (end <= start) return 0;
    return ((progress - start) / (end - start)).clamp(0.0, 1.0);
  }

  LatLng _interpolatedPosition(int index, double fraction) {
    final current = _points[index];
    if (index >= _points.length - 1) return LatLng(current.lat, current.lng);
    final next = _points[index + 1];
    return LatLng(
      current.lat + (next.lat - current.lat) * fraction,
      current.lng + (next.lng - current.lng) * fraction,
    );
  }

  double _distanceAt(int index, double fraction) {
    if (_cumulativeDistance.isEmpty) return 0;
    var gpsDistance = _cumulativeDistance[index];
    if (index < _cumulativeDistance.length - 1) {
      gpsDistance +=
          (_cumulativeDistance[index + 1] - _cumulativeDistance[index]) *
          fraction;
    }
    final totalGpsDistance = _cumulativeDistance.last;
    if (totalGpsDistance <= 0) return widget.activity.distanceMeters;
    return widget.activity.distanceMeters * (gpsDistance / totalGpsDistance);
  }

  double? _paceAt(int index) {
    final speed = _points[index].speed;
    if (speed != null && speed > 0.55) {
      return (1000 / speed).clamp(
        RunPaceAnalytics.minPaceSecPerKm,
        RunPaceAnalytics.maxPaceSecPerKm,
      );
    }

    final startIndex = (index - 5).clamp(0, index);
    final distance =
        _cumulativeDistance[index] - _cumulativeDistance[startIndex];
    final seconds =
        _points[index].recordedAt
            .difference(_points[startIndex].recordedAt)
            .inMilliseconds /
        1000;
    if (distance >= 5 && seconds > 0) {
      final pace = seconds / (distance / 1000);
      if (pace >= RunPaceAnalytics.minPaceSecPerKm &&
          pace <= RunPaceAnalytics.maxPaceSecPerKm) {
        return pace;
      }
    }
    return widget.activity.avgPaceSecPerKm;
  }

  LatLngBounds? _routeBounds() {
    if (_points.length < 2) return null;
    var minLat = _points.first.lat;
    var maxLat = minLat;
    var minLng = _points.first.lng;
    var maxLng = minLng;
    for (final point in _points.skip(1)) {
      if (point.lat < minLat) minLat = point.lat;
      if (point.lat > maxLat) maxLat = point.lat;
      if (point.lng < minLng) minLng = point.lng;
      if (point.lng > maxLng) maxLng = point.lng;
    }
    if ((maxLat - minLat) < 1e-4 && (maxLng - minLng) < 1e-4) {
      return null;
    }
    return LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng));
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final progress = _controller.value;
    final index = _pointIndexAt(progress);
    final fraction = _segmentFraction(index, progress);
    final position = _interpolatedPosition(index, fraction);
    final revealedSegments = <Polyline>[
      for (var segment = 0; segment < index; segment++)
        Polyline(
          points: [
            LatLng(_points[segment].lat, _points[segment].lng),
            LatLng(_points[segment + 1].lat, _points[segment + 1].lng),
          ],
          color: RunRoutePaceStyle.colorForPace(
            paceSecPerKm: _segmentPaces[segment],
            averagePaceSecPerKm: widget.activity.avgPaceSecPerKm,
          ),
          strokeWidth: RunRoutePaceStyle.routeStrokeWidth,
          strokeCap: StrokeCap.butt,
        ),
      if (index < _points.length - 1 && fraction > 0)
        Polyline(
          points: [LatLng(_points[index].lat, _points[index].lng), position],
          color: RunRoutePaceStyle.colorForPace(
            paceSecPerKm: _segmentPaces[index],
            averagePaceSecPerKm: widget.activity.avgPaceSecPerKm,
          ),
          strokeWidth: RunRoutePaceStyle.routeStrokeWidth,
          strokeCap: StrokeCap.butt,
        ),
    ];
    final bounds = _routeBounds();
    final elapsedSeconds = (widget.activity.durationSeconds * progress).round();
    final pace = _paceAt(index);
    final distance = _distanceAt(index, fraction);

    return Scaffold(
      appBar: AppBar(title: Text(loc.runReplayTitle)),
      body: Stack(
        fit: StackFit.expand,
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: position,
              initialZoom: bounds == null ? 15 : 14,
              initialCameraFit: bounds == null
                  ? null
                  : CameraFit.bounds(
                      bounds: bounds,
                      padding: const EdgeInsets.fromLTRB(28, 120, 28, 230),
                      minZoom: 3,
                      maxZoom: 17,
                    ),
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              if (widget.showMapTiles)
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.workoutnotes.workout_notes',
                ),
              if (revealedSegments.isNotEmpty)
                PolylineLayer(polylines: revealedSegments),
              MarkerLayer(
                markers: [
                  Marker(
                    point: position,
                    width: 28,
                    height: 28,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black38,
                            blurRadius: 5,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            left: 16,
            right: 16,
            top: 16,
            child: _ReplayStats(
              elapsedLabel: loc.runReplayTime,
              elapsed: RunFormatters.duration(elapsedSeconds),
              paceLabel: loc.runReplayPace,
              pace: RunFormatters.paceWithUnit(pace),
              distanceLabel: loc.runRecordDistance,
              distance: RunFormatters.distanceWithUnit(distance),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 20,
            child: SafeArea(
              top: false,
              child: _ReplayControls(
                progress: progress,
                isPlaying: _controller.isAnimating,
                isCompleted: _controller.isCompleted,
                playLabel: loc.runReplayPlay,
                pauseLabel: loc.runReplayPause,
                replayLabel: loc.runReplayAgain,
                onPressed: _togglePlayback,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReplayStats extends StatelessWidget {
  final String elapsedLabel;
  final String elapsed;
  final String paceLabel;
  final String pace;
  final String distanceLabel;
  final String distance;

  const _ReplayStats({
    required this.elapsedLabel,
    required this.elapsed,
    required this.paceLabel,
    required this.pace,
    required this.distanceLabel,
    required this.distance,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 5,
      color: theme.colorScheme.surface.withValues(alpha: 0.94),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: _ReplayStat(label: elapsedLabel, value: elapsed),
            ),
            Expanded(
              child: _ReplayStat(label: paceLabel, value: pace),
            ),
            Expanded(
              child: _ReplayStat(label: distanceLabel, value: distance),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReplayStat extends StatelessWidget {
  final String label;
  final String value;

  const _ReplayStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _ReplayControls extends StatelessWidget {
  final double progress;
  final bool isPlaying;
  final bool isCompleted;
  final String playLabel;
  final String pauseLabel;
  final String replayLabel;
  final VoidCallback onPressed;

  const _ReplayControls({
    required this.progress,
    required this.isPlaying,
    required this.isCompleted,
    required this.playLabel,
    required this.pauseLabel,
    required this.replayLabel,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = isPlaying
        ? pauseLabel
        : (isCompleted ? replayLabel : playLabel);
    return Card(
      elevation: 5,
      color: theme.colorScheme.surface.withValues(alpha: 0.94),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              borderRadius: BorderRadius.circular(3),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              key: const ValueKey('run-replay-control'),
              onPressed: onPressed,
              icon: Icon(
                isPlaying
                    ? Icons.pause_rounded
                    : (isCompleted
                          ? Icons.replay_rounded
                          : Icons.play_arrow_rounded),
              ),
              label: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}
