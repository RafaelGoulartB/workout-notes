import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/cardio_activity_type.dart';
import 'package:workout_notes/widgets/run/record/run_record_activity_picker.dart';

/// Full-screen backdrop that replaces the map for indoor sessions.
class RunIndoorBackdrop extends StatelessWidget {
  final CardioActivityType type;
  final bool active;
  final bool paused;

  const RunIndoorBackdrop({
    super.key,
    required this.type,
    required this.active,
    required this.paused,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final isTreadmill = type == CardioActivityType.treadmill;
    final status = active
        ? (paused
              ? (isTreadmill
                    ? loc.runTreadmillPaused
                    : loc.stationaryBikePaused)
              : (isTreadmill
                    ? loc.runTreadmillTiming
                    : loc.stationaryBikeTiming))
        : runActivitySubtitle(loc, type);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.secondaryContainer,
            theme.colorScheme.surfaceContainerLow,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Align(
        alignment: const Alignment(0, -0.42),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 116,
                height: 116,
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondary.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  runActivityIcon(type),
                  size: 62,
                  color: theme.colorScheme.secondary,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                loc.stationaryBikeIndoorHeadline,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                status,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Recorded without GPS, type the distance at the end" explainer.
class RunIndoorInfoCard extends StatelessWidget {
  final CardioActivityType type;

  const RunIndoorInfoCard({super.key, required this.type});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.location_off_outlined,
            size: 20,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              type == CardioActivityType.treadmill
                  ? loc.runTreadmillIndoorBody
                  : loc.stationaryBikeIndoorBody,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
