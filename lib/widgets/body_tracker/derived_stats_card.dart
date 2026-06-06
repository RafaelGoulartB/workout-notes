import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/body_measurement_types.dart';

/// Card showing estimated body composition (lean mass, fat mass, WHR).
class BodyDerivedStatsCard extends StatelessWidget {
  final double weight;
  final Map<String, Map<String, dynamic>?> latestByType;

  const BodyDerivedStatsCard({
    super.key,
    required this.weight,
    required this.latestByType,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;

    final bodyFatLatest = latestByType['bodyFat'];
    final bodyFatVal = bodyFatLatest != null
        ? (bodyFatLatest['value'] as num?)?.toDouble()
        : null;
    final waistLatest = latestByType['waist'];
    final hipLatest = latestByType['hip'];
    final waistVal = waistLatest != null
        ? (waistLatest['value'] as num?)?.toDouble()
        : null;
    final hipVal = hipLatest != null
        ? (hipLatest['value'] as num?)?.toDouble()
        : null;
    final whr = (waistVal != null && hipVal != null && hipVal > 0)
        ? waistVal / hipVal
        : null;
    final leanMass =
        (bodyFatVal != null) ? weight * (1 - bodyFatVal / 100) : null;
    final fatMass =
        (bodyFatVal != null) ? weight * (bodyFatVal / 100) : null;

    final stats = <DerivedStat>[];
    if (leanMass != null) {
      stats.add(DerivedStat(
        loc.bodyTrackerLeanMass,
        '${leanMass.toStringAsFixed(1)} kg',
        Icons.fitness_center,
        Colors.green,
      ));
    }
    if (fatMass != null) {
      stats.add(DerivedStat(
        loc.bodyTrackerFatMass,
        '${fatMass.toStringAsFixed(1)} kg',
        Icons.water_drop,
        Colors.orange,
      ));
    }
    if (whr != null) {
      final whrEval = whr < 0.9
          ? loc.bodyTrackerHealthy
          : whr < 1.0
              ? loc.bodyTrackerModerate
              : loc.bodyTrackerHigh;
      stats.add(DerivedStat(
        loc.bodyTrackerWHR,
        '${whr.toStringAsFixed(2)} · $whrEval',
        Icons.monitor_weight,
        Colors.teal,
      ));
    }

    if (stats.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
              color: theme.colorScheme.outlineVariant.withAlpha(80)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                loc.bodyTrackerEstimatedComposition,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: stats
                    .map((s) => Expanded(
                          child: Column(
                            children: [
                              Icon(s.icon,
                                  size: 20, color: s.color.withAlpha(200)),
                              const SizedBox(height: 4),
                              Text(
                                s.value,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              Text(
                                s.label,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 9,
                                  color:
                                      theme.colorScheme.onSurfaceVariant,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
