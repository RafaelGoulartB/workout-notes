import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/models/run_track_point.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/utils/run_pace_analytics.dart';
import 'package:workout_notes/utils/run_route_geometry.dart';
import 'package:workout_notes/utils/run_route_pace_style.dart';
import 'package:workout_notes/widgets/run/run_route_map.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';

/// A short, accelerated playback of a completed run's GPS trail, with a
/// scrub slider and a speed selector.
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

  static const int defaultSpeed = 60;
  static const List<int> speeds = [30, 60, 120];

  /// Playback length at [speed]x (default 60x: every real minute takes one
  /// second).
  @visibleForTesting
  static Duration replayDurationFor(
    int movingTimeSeconds, {
    int speed = defaultSpeed,
  }) {
    final milliseconds = (movingTimeSeconds * 1000 / speed).round();
    return Duration(milliseconds: milliseconds < 1 ? 1 : milliseconds);
  }

  @override
  State<RunReplayScreen> createState() => _RunReplayScreenState();
}

/// Where the runner is at one instant of the replay.
class _ReplayFrame {
  final int index;
  final double fraction;
  final LatLng position;

  const _ReplayFrame(this.index, this.fraction, this.position);
}

class _RunReplayScreenState extends State<RunReplayScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<RunTrackPoint> _points;
  late final List<LatLng> _trail;
  late final List<double> _timeline;
  late final RunRouteGeometry _geometry;
  late final List<RunRouteColorRun> _runs;
  late final List<Polyline> _runPolylines;
  late final List<RunPaceSample> _paceSamples;
  late final Polyline _ghost;
  late final bool _hasAltitude;
  late final int _movingSeconds;

  int _speed = RunReplayScreen.defaultSpeed;

  /// Completed-run layer, rebuilt only when another colour run finishes.
  int _completedCount = -1;
  List<Polyline> _completedLayer = const [];

  @override
  void initState() {
    super.initState();
    _points = List<RunTrackPoint>.of(widget.points)
      ..sort((a, b) => a.seq.compareTo(b.seq));
    _trail = [for (final p in _points) LatLng(p.lat, p.lng)];
    _timeline = _buildTimeline(_points);
    final profile = RunTrackProfile.fromPoints(_points);
    _geometry = RunRouteGeometry.fromPoints(_points, profile: profile);
    _hasAltitude = _points.any((p) => p.altitude != null);
    _movingSeconds = widget.activity.movingTimeSeconds > 0
        ? widget.activity.movingTimeSeconds
        : widget.activity.durationSeconds;
    _paceSamples = RunPaceAnalytics.fromTrackPoints(
      _points,
      profile: profile,
    ).samples;

    final average = widget.activity.avgPaceSecPerKm;
    final paces = RunRoutePaceStyle.segmentPaces(
      _points,
      averagePaceSecPerKm: average,
    );
    _runs = RunRoutePaceStyle.colorRuns(paces, averagePaceSecPerKm: average);
    _runPolylines = [
      for (final run in _runs)
        Polyline(
          points: _trail.sublist(run.firstPoint, run.lastPoint + 1),
          color: run.color,
          strokeWidth: RunRoutePaceStyle.routeStrokeWidth,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
        ),
    ];
    _ghost = Polyline(
      points: _trail,
      color: Colors.grey.withValues(alpha: 0.45),
      strokeWidth: RunRoutePaceStyle.routeStrokeWidth - 1,
      strokeCap: StrokeCap.round,
      strokeJoin: StrokeJoin.round,
    );

    _controller = AnimationController(
      vsync: this,
      duration: RunReplayScreen.replayDurationFor(
        _movingSeconds,
        speed: _speed,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

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

  /// Changes the playback speed keeping the current position.
  void _setSpeed(int speed) {
    if (speed == _speed) return;
    final wasPlaying = _controller.isAnimating;
    final value = _controller.value;
    setState(() => _speed = speed);
    _controller.duration = RunReplayScreen.replayDurationFor(
      _movingSeconds,
      speed: speed,
    );
    // Setting the duration rescales the ticker, so restart from the same
    // position to keep the runner where they are.
    _controller.value = value;
    if (wasPlaying) _controller.forward();
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

  _ReplayFrame _frameAt(double progress) {
    final index = _pointIndexAt(progress);
    final current = _points[index];
    if (index >= _points.length - 1) {
      return _ReplayFrame(index, 0, LatLng(current.lat, current.lng));
    }
    final start = _timeline[index];
    final end = _timeline[index + 1];
    final fraction = end <= start
        ? 0.0
        : ((progress - start) / (end - start)).clamp(0.0, 1.0);
    final next = _points[index + 1];
    return _ReplayFrame(
      index,
      fraction,
      LatLng(
        current.lat + (next.lat - current.lat) * fraction,
        current.lng + (next.lng - current.lng) * fraction,
      ),
    );
  }

  double _gpsDistanceAt(_ReplayFrame frame) {
    final cumulative = _geometry.cumulativeMeters;
    var distance = cumulative[frame.index];
    if (frame.index < cumulative.length - 1) {
      distance +=
          (cumulative[frame.index + 1] - cumulative[frame.index]) *
          frame.fraction;
    }
    return distance;
  }

  /// Reported distance: GPS distance scaled to the recorded total, so the
  /// counter ends exactly on the activity's distance.
  double _distanceAt(double gpsDistance) {
    final total = _geometry.totalMeters;
    if (total <= 0) return widget.activity.distanceMeters;
    return widget.activity.distanceMeters * (gpsDistance / total);
  }

  /// Smoothed pace of the sample closest to [gpsDistance].
  double? _paceAt(double gpsDistance) {
    if (_paceSamples.isEmpty) return widget.activity.avgPaceSecPerKm;
    var low = 0;
    var high = _paceSamples.length - 1;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (_paceSamples[mid].distanceMeters < gpsDistance) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    if (low > 0 &&
        (gpsDistance - _paceSamples[low - 1].distanceMeters) <
            (_paceSamples[low].distanceMeters - gpsDistance)) {
      low--;
    }
    return _paceSamples[low].paceSecPerKm;
  }

  double? _altitudeAt(_ReplayFrame frame) {
    final current = _points[frame.index].altitude;
    if (current == null || frame.index >= _points.length - 1) return current;
    final next = _points[frame.index + 1].altitude;
    if (next == null) return current;
    return current + (next - current) * frame.fraction;
  }

  /// Polylines for the colour runs already covered, plus the partial one.
  List<Widget> _routeLayers(_ReplayFrame frame) {
    final covered = frame.index + frame.fraction;
    var complete = 0;
    while (complete < _runs.length && _runs[complete].lastPoint <= covered) {
      complete++;
    }
    if (complete != _completedCount) {
      _completedCount = complete;
      _completedLayer = _runPolylines.sublist(0, complete);
    }
    final partial = <Polyline>[];
    if (complete < _runs.length) {
      final run = _runs[complete];
      final upTo = frame.index.clamp(run.firstPoint, run.lastPoint);
      final points = [..._trail.sublist(run.firstPoint, upTo + 1)];
      if (frame.fraction > 0 || points.length == 1) points.add(frame.position);
      if (points.length >= 2) {
        partial.add(
          Polyline(
            points: points,
            color: run.color,
            strokeWidth: RunRoutePaceStyle.routeStrokeWidth,
            strokeCap: StrokeCap.round,
            strokeJoin: StrokeJoin.round,
          ),
        );
      }
    }
    return [
      if (_completedLayer.isNotEmpty) PolylineLayer(polylines: _completedLayer),
      if (partial.isNotEmpty) PolylineLayer(polylines: partial),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final bounds = RunRouteMap.boundsFor(_trail);
    final start = _trail.first;

    return Scaffold(
      appBar: AppBar(title: Text(loc.runReplayTitle)),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // The map and its ghost route are built once; only the layers that
          // depend on playback listen to the controller.
          FlutterMap(
            options: MapOptions(
              initialCenter: start,
              initialZoom: bounds == null ? 15 : 14,
              initialCameraFit: bounds == null
                  ? null
                  : CameraFit.bounds(
                      bounds: bounds,
                      padding: const EdgeInsets.fromLTRB(28, 120, 28, 250),
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
              PolylineLayer(polylines: [_ghost]),
              AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final frame = _frameAt(_controller.value);
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      ..._routeLayers(frame),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: frame.position,
                            width: 28,
                            height: 28,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 3,
                                ),
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
                  );
                },
              ),
            ],
          ),
          Positioned(
            left: 16,
            right: 16,
            top: 16,
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final progress = _controller.value;
                  final frame = _frameAt(progress);
                  final gpsDistance = _gpsDistanceAt(frame);
                  final altitude = _hasAltitude ? _altitudeAt(frame) : null;
                  return _ReplayStats(
                    items: [
                      (
                        loc.runReplayTime,
                        RunFormatters.duration(
                          (_movingSeconds * progress).round(),
                        ),
                      ),
                      (
                        loc.runReplayPace,
                        RunFormatters.paceWithUnit(_paceAt(gpsDistance)),
                      ),
                      (
                        loc.runRecordDistance,
                        RunFormatters.distanceWithUnit(
                          _distanceAt(gpsDistance),
                        ),
                      ),
                      if (_hasAltitude)
                        (
                          loc.runReplayDistanceGain,
                          RunFormatters.elevation(altitude),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 20,
            child: SafeArea(
              top: false,
              child: _ReplayControls(
                controller: _controller,
                speed: _speed,
                onSpeedChanged: _setSpeed,
                onTogglePlayback: _togglePlayback,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReplayStats extends StatelessWidget {
  final List<(String, String)> items;

  const _ReplayStats({required this.items});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 5,
      color: theme.colorScheme.surface.withValues(alpha: 0.94),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Row(
          children: [
            for (final (label, value) in items)
              Expanded(
                child: _ReplayStat(label: label, value: value),
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
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            maxLines: 1,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              fontFeatures: RunUi.tabular,
            ),
          ),
        ),
      ],
    );
  }
}

class _ReplayControls extends StatelessWidget {
  final AnimationController controller;
  final int speed;
  final ValueChanged<int> onSpeedChanged;
  final VoidCallback onTogglePlayback;

  const _ReplayControls({
    required this.controller,
    required this.speed,
    required this.onSpeedChanged,
    required this.onTogglePlayback,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    return Card(
      elevation: 5,
      color: theme.colorScheme.surface.withValues(alpha: 0.94),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: controller,
              builder: (context, _) => Semantics(
                label: loc.runReplaySeek,
                child: Slider(
                  key: const ValueKey('run-replay-slider'),
                  value: controller.value.clamp(0.0, 1.0),
                  onChangeStart: (_) => controller.stop(),
                  onChanged: (value) => controller.value = value,
                ),
              ),
            ),
            AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                final playing = controller.isAnimating;
                final completed = controller.isCompleted;
                return FilledButton.icon(
                  key: const ValueKey('run-replay-control'),
                  onPressed: onTogglePlayback,
                  icon: Icon(
                    playing
                        ? Icons.pause_rounded
                        : (completed
                              ? Icons.replay_rounded
                              : Icons.play_arrow_rounded),
                  ),
                  label: Text(
                    playing
                        ? loc.runReplayPause
                        : (completed ? loc.runReplayAgain : loc.runReplayPlay),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            Semantics(
              label: loc.runReplaySpeed,
              child: RunSegmentedTabs<int>(
                values: RunReplayScreen.speeds,
                selected: speed,
                labelOf: (value) => '$value×',
                onChanged: onSpeedChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
