import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:workout_notes/l10n/app_localizations.dart';

/// Live map of the run. The camera follows the runner only while [follow] is
/// true; the first pan or zoom gesture calls [onUserMoved] so the screen can
/// stop following and offer a "recenter" button.
class RunRecordMap extends StatelessWidget {
  final MapController controller;
  final LatLng center;
  final List<LatLng> trail;
  final VoidCallback onUserMoved;

  const RunRecordMap({
    super.key,
    required this.controller,
    required this.center,
    required this.trail,
    required this.onUserMoved,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: center,
        initialZoom: 16,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
        onPositionChanged: (camera, hasGesture) {
          if (hasGesture) onUserMoved();
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.workoutnotes.workout_notes',
        ),
        if (trail.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: trail,
                color: theme.colorScheme.primary,
                strokeWidth: 5,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            Marker(
              point: center,
              width: 22,
              height: 22,
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Shown instead of the map until the first GPS fix arrives.
class RunRecordMapPlaceholder extends StatelessWidget {
  final String label;

  const RunRecordMapPlaceholder({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerLow,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 240),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.location_searching_rounded,
                size: 48,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(label, style: theme.textTheme.titleMedium),
            ],
          ),
        ),
      ),
    );
  }
}

/// Floating button that re-enables map following after a manual pan.
class RunRecenterButton extends StatelessWidget {
  final VoidCallback onPressed;

  const RunRecenterButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    return Material(
      color: theme.colorScheme.primaryContainer,
      elevation: 3,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('run-recenter'),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.my_location_rounded,
                size: 18,
                color: theme.colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: 6),
              Text(
                loc.runRecordRecenter,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
