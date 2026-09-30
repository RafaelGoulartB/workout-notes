import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_track_point.dart';
import 'package:workout_notes/widgets/run/run_route_map.dart';

/// Full-screen, pannable version of the run route map with km markers.
class RunRouteMapScreen extends StatelessWidget {
  final String title;
  final List<RunTrackPoint> points;
  final double? averagePaceSecPerKm;
  final bool showMapTiles;

  const RunRouteMapScreen({
    super.key,
    required this.title,
    required this.points,
    required this.averagePaceSecPerKm,
    this.showMapTiles = true,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(title.isEmpty ? loc.runDetailMapTitle : title),
      ),
      body: RunRouteMap(
        points: points,
        averagePaceSecPerKm: averagePaceSecPerKm,
        interactive: true,
        showKmMarkers: true,
        showMapTiles: showMapTiles,
        fitPadding: const EdgeInsets.fromLTRB(40, 40, 40, 90),
      ),
    );
  }
}
