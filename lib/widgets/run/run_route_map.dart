import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_track_point.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/utils/run_route_geometry.dart';
import 'package:workout_notes/utils/run_route_pace_style.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Pace-coloured GPS route on an OpenStreetMap base with start / finish
/// markers, an optional legend and a marker that follows [selectedDistance]
/// (metres from the start), so a chart can point at a spot on the route.
class RunRouteMap extends StatefulWidget {
  final List<RunTrackPoint> points;
  final double? averagePaceSecPerKm;

  /// Distance (m) currently highlighted by a chart; null hides the marker.
  final ValueListenable<double?>? selectedDistance;

  /// When false the map is a static preview: pans/zooms are ignored so it
  /// can sit inside a scroll view and react to [onTap] instead.
  final bool interactive;
  final bool showKmMarkers;
  final bool showMapTiles;
  final VoidCallback? onTap;
  final EdgeInsets fitPadding;

  const RunRouteMap({
    super.key,
    required this.points,
    required this.averagePaceSecPerKm,
    this.selectedDistance,
    this.interactive = false,
    this.showKmMarkers = false,
    this.showMapTiles = true,
    this.onTap,
    this.fitPadding = const EdgeInsets.all(32),
  });

  /// Fit bounds only when the trail spans a usable area; degenerate bounds
  /// make flutter_map compute Infinity/NaN zoom and crash the TileLayer.
  static LatLngBounds? boundsFor(List<LatLng> trail) {
    final bounds = RunRouteGeometry.boundsOf([
      for (final p in trail) (lat: p.latitude, lng: p.longitude),
    ]);
    if (bounds == null) return null;
    return LatLngBounds(
      LatLng(bounds.minLat, bounds.minLng),
      LatLng(bounds.maxLat, bounds.maxLng),
    );
  }

  @override
  State<RunRouteMap> createState() => _RunRouteMapState();
}

class _RunRouteMapState extends State<RunRouteMap> {
  late List<LatLng> _trail;
  late RunRouteGeometry _geometry;
  late List<Polyline> _polylines;
  late List<Marker> _kmMarkers;
  LatLngBounds? _bounds;

  @override
  void initState() {
    super.initState();
    _rebuild();
  }

  @override
  void didUpdateWidget(RunRouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.points != widget.points ||
        oldWidget.averagePaceSecPerKm != widget.averagePaceSecPerKm) {
      _rebuild();
    }
  }

  /// Everything derived from the points is computed once, not per frame.
  void _rebuild() {
    final points = widget.points;
    _trail = [for (final p in points) LatLng(p.lat, p.lng)];
    _geometry = RunRouteGeometry.fromPoints(points);
    _bounds = RunRouteMap.boundsFor(_trail);
    final paces = RunRoutePaceStyle.segmentPaces(
      points,
      averagePaceSecPerKm: widget.averagePaceSecPerKm,
    );
    _polylines = [
      for (final run in RunRoutePaceStyle.colorRuns(
        paces,
        averagePaceSecPerKm: widget.averagePaceSecPerKm,
      ))
        Polyline(
          points: _trail.sublist(run.firstPoint, run.lastPoint + 1),
          color: run.color,
          strokeWidth: RunRoutePaceStyle.routeStrokeWidth,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
        ),
    ];
    _kmMarkers = [];
  }

  List<Marker> _buildKmMarkers(ColorScheme colors) {
    final markers = <Marker>[];
    final total = _geometry.totalMeters;
    for (var km = 1; km * 1000.0 < total - 150; km++) {
      final position = _geometry.positionAtDistance(km * 1000.0);
      if (position == null) continue;
      markers.add(
        Marker(
          point: LatLng(position.lat, position.lng),
          width: 22,
          height: 22,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: colors.outline, width: 1),
            ),
            child: Center(
              child: Text(
                '$km',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: colors.onSurface,
                ),
              ),
            ),
          ),
        ),
      );
    }
    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final trail = _trail;
    final bounds = _bounds;
    final center = trail.isNotEmpty
        ? trail[trail.length ~/ 2]
        : const LatLng(-23.5505, -46.6333);
    if (widget.showKmMarkers && _kmMarkers.isEmpty) {
      _kmMarkers = _buildKmMarkers(colors);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        FlutterMap(
          options: MapOptions(
            initialCenter: center,
            initialZoom: bounds == null ? 15 : 14,
            initialCameraFit: bounds == null
                ? null
                : CameraFit.bounds(
                    bounds: bounds,
                    padding: widget.fitPadding,
                    maxZoom: 17,
                    minZoom: 3,
                  ),
            interactionOptions: InteractionOptions(
              flags: widget.interactive
                  ? InteractiveFlag.all & ~InteractiveFlag.rotate
                  : InteractiveFlag.none,
            ),
          ),
          children: [
            if (widget.showMapTiles)
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.workoutnotes.workout_notes',
              ),
            if (_polylines.isNotEmpty) PolylineLayer(polylines: _polylines),
            if (_kmMarkers.isNotEmpty) MarkerLayer(markers: _kmMarkers),
            if (trail.isNotEmpty)
              MarkerLayer(
                markers: [
                  Marker(
                    point: trail.first,
                    width: 22,
                    height: 22,
                    child: Semantics(
                      label: loc.runDetailMapStart,
                      child: _EndpointDot(
                        color: colors.primary,
                        icon: Icons.play_arrow_rounded,
                        iconColor: colors.onPrimary,
                      ),
                    ),
                  ),
                  if (trail.length > 1)
                    Marker(
                      point: trail.last,
                      width: 24,
                      height: 24,
                      child: Semantics(
                        label: loc.runDetailMapFinish,
                        child: _EndpointDot(
                          color: colors.inverseSurface,
                          icon: Icons.flag_rounded,
                          iconColor: colors.onInverseSurface,
                        ),
                      ),
                    ),
                ],
              ),
            if (widget.selectedDistance != null)
              ValueListenableBuilder<double?>(
                valueListenable: widget.selectedDistance!,
                builder: (context, meters, _) {
                  final position = meters == null
                      ? null
                      : _geometry.positionAtDistance(meters);
                  if (position == null) return const SizedBox.shrink();
                  return MarkerLayer(
                    markers: [
                      Marker(
                        point: LatLng(position.lat, position.lng),
                        width: 24,
                        height: 24,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors.surface,
                            shape: BoxShape.circle,
                            border: Border.all(color: colors.primary, width: 4),
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
                  );
                },
              ),
          ],
        ),
        if (!widget.interactive && widget.onTap != null)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap,
            ),
          ),
        if (_polylines.isNotEmpty)
          Positioned(
            left: 10,
            bottom: 10,
            child: RunRoutePaceLegend(
              averagePaceSecPerKm: widget.averagePaceSecPerKm,
            ),
          ),
      ],
    );
  }
}

class _EndpointDot extends StatelessWidget {
  final Color color;
  final IconData icon;
  final Color iconColor;

  const _EndpointDot({
    required this.color,
    required this.icon,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 1)),
        ],
      ),
      child: Icon(icon, size: 13, color: iconColor),
    );
  }
}

/// Slow -> fast colour ramp of the route with the two end paces.
class RunRoutePaceLegend extends StatelessWidget {
  final double? averagePaceSecPerKm;

  const RunRoutePaceLegend({super.key, required this.averagePaceSecPerKm});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final average = averagePaceSecPerKm;
    final caption = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontSize: 10,
    );
    final value = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurface,
      fontWeight: FontWeight.w700,
      fontFeatures: AppUi.tabular,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withAlpha(225),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: IntrinsicWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 6,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  gradient: const LinearGradient(
                    colors: RunRoutePaceStyle.legendColors,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(loc.runDetailMapLegendSlow, style: caption),
                  const SizedBox(width: 10),
                  Text(loc.runDetailMapLegendFast, style: caption),
                ],
              ),
              if (average != null)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(RunFormatters.paceShort(average), style: value),
                    Text(
                      '${RunFormatters.paceShort(RunRoutePaceStyle.fastestLegendPace(average))}'
                      ' /km',
                      style: value,
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
