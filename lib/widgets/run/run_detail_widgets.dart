import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_achievement.dart';
import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/widgets/run/run_achievements_section.dart';
import 'package:workout_notes/widgets/run/run_medal_badge.dart';
import 'package:workout_notes/widgets/run/run_theme_colors.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Title used when the run has none: the part of the day it happened in.
String runDefaultTitle(AppLocalizations loc, RunActivity activity) {
  if (activity.isStationaryBike) return loc.stationaryBikeDetailUntitled;
  if (activity.isTreadmill) return loc.runDetailTreadmillUntitled;
  final hour = activity.startedAt.toLocal().hour;
  if (hour >= 5 && hour < 12) return loc.runDetailTitleMorning;
  if (hour >= 12 && hour < 18) return loc.runDetailTitleAfternoon;
  if (hour >= 18 && hour < 22) return loc.runDetailTitleEvening;
  return loc.runDetailTitleNight;
}

/// Headline card of the run detail: title, date, feeling + effort, notes and
/// one de-duplicated grid of numbers.
class RunDetailHero extends StatelessWidget {
  final RunActivity activity;

  /// Preferred over the stored average when the GPS series gives a better one.
  final double? avgPaceSecPerKm;
  final double? fastestKmPaceSecPerKm;

  /// Elevation shown in the grid (stored summary, or the GPS profile).
  final double? elevationGainMeters;
  final double? elevationLossMeters;

  const RunDetailHero({
    super.key,
    required this.activity,
    required this.avgPaceSecPerKm,
    required this.fastestKmPaceSecPerKm,
    required this.elevationGainMeters,
    required this.elevationLossMeters,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final started = activity.startedAt.toLocal();
    final dateLabel = DateFormat.MMMEd(
      Localizations.localeOf(context).toString(),
    ).add_Hm().format(started);
    final title = activity.title?.trim().isNotEmpty == true
        ? activity.title!.trim()
        : runDefaultTitle(loc, activity);
    final notes = activity.notes?.trim();
    final hasFeedback = activity.feelingRating != null || activity.rpe != null;

    return AppHeroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                _timeOfDayIcon(started.hour),
                size: 15,
                color: colors.primary,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  dateLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          AppMetricGrid(children: _metrics(context, loc)),
          if (hasFeedback) ...[
            const SizedBox(height: 12),
            RunFeedbackRow(
              feelingRating: activity.feelingRating,
              rpe: activity.rpe,
            ),
          ],
          if (notes != null && notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.notes_rounded,
                  size: 16,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    notes,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (activity.gpsAccuracyMeanMeters != null) ...[
            const SizedBox(height: 10),
            Text(
              loc.runDetailGpsQuality(
                RunFormatters.decimal(activity.gpsAccuracyMeanMeters!, 0),
              ),
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.onSurfaceVariant.withValues(alpha: 0.85),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static IconData _timeOfDayIcon(int hour) {
    if (hour >= 5 && hour < 12) return Icons.wb_sunny_outlined;
    if (hour >= 12 && hour < 18) return Icons.wb_twilight_rounded;
    return Icons.nightlight_outlined;
  }

  List<Widget> _metrics(BuildContext context, AppLocalizations loc) {
    final elapsedDiffers =
        (activity.durationSeconds - activity.movingTimeSeconds).abs() >= 5 &&
        activity.durationSeconds > activity.movingTimeSeconds;
    final gain = elevationGainMeters;
    final loss = elevationLossMeters;
    final calories = activity.calories;
    final speed = activity.averageSpeedKmh;
    return [
      AppMetricBox(
        icon: Icons.route_outlined,
        label: loc.runRecordDistance,
        value: RunFormatters.distanceKm(activity.distanceMeters),
        unit: 'km',
      ),
      AppMetricBox(
        icon: Icons.timer_outlined,
        label: loc.runDetailMovingTime,
        value: RunFormatters.duration(
          activity.movingTimeSeconds > 0
              ? activity.movingTimeSeconds
              : activity.durationSeconds,
        ),
        caption: elapsedDiffers
            ? loc.runDetailElapsedCaption(
                RunFormatters.duration(activity.durationSeconds),
              )
            : null,
      ),
      if (activity.isStationaryBike)
        AppMetricBox(
          icon: Icons.speed_rounded,
          label: loc.stationaryBikeAverageSpeed,
          value: RunFormatters.speedKmh(speed),
          unit: loc.stationaryBikeSpeedUnit,
        )
      else
        AppMetricBox(
          icon: Icons.speed_rounded,
          label: loc.runDetailAvgPace,
          value: RunFormatters.paceShort(avgPaceSecPerKm),
          unit: '/km',
        ),
      if (activity.isRun && gain != null)
        AppMetricBox(
          icon: Icons.terrain_rounded,
          label: loc.runDetailElevation,
          value: '+${gain.round()}',
          unit: 'm',
          caption: loss == null ? null : '−${loss.round()} m',
        ),
      if (calories != null && calories > 0)
        AppMetricBox(
          icon: Icons.local_fire_department_outlined,
          label: loc.runDetailCalories,
          value: '$calories',
          unit: 'kcal',
        ),
      if (activity.isRun && fastestKmPaceSecPerKm != null)
        AppMetricBox(
          icon: Icons.bolt_rounded,
          label: loc.runDetailFastestKm,
          value: RunFormatters.paceShort(fastestKmPaceSecPerKm),
          unit: '/km',
          highlighted: true,
        ),
    ];
  }
}

/// Feeling stars and perceived effort on a single compact line.
class RunFeedbackRow extends StatelessWidget {
  final int? feelingRating;
  final double? rpe;

  const RunFeedbackRow({
    super.key,
    required this.feelingRating,
    required this.rpe,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final rating = feelingRating?.clamp(1, 5);
    final effort = rpe?.round().clamp(1, 10);
    return Wrap(
      spacing: 16,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (rating != null)
          Semantics(
            label: '${loc.runDetailFeeling}: $rating/5',
            child: ExcludeSemantics(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    loc.runDetailFeeling,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 6),
                  for (var star = 1; star <= 5; star++)
                    Icon(
                      star <= rating
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      size: 16,
                      color: star <= rating
                          ? Colors.amber.shade700
                          : colors.outline,
                    ),
                ],
              ),
            ),
          ),
        if (effort != null)
          Semantics(
            label: '${loc.runDetailRpe}: $effort/10',
            child: ExcludeSemantics(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    loc.runDetailRpe,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: RunThemeColors.effort(colors, effort),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$effort/10',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      fontFeatures: AppUi.tabular,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// One fixed-distance best effort inside a run.
class RunBestEffort {
  final RunAchievementKind kind;
  final double distanceMeters;
  final int seconds;

  const RunBestEffort({
    required this.kind,
    required this.distanceMeters,
    required this.seconds,
  });

  double get paceSecPerKm =>
      RunFormatters.paceSecondsPerKm(distanceMeters, seconds);

  /// The efforts this run itself contains, shortest first.
  static List<RunBestEffort> fromActivity(RunActivity activity) {
    final candidates = <(RunAchievementKind, double, int?)>[
      (RunAchievementKind.bestEffort1k, 1000, activity.bestEffort1kSec),
      (RunAchievementKind.bestEffort3k, 3000, activity.bestEffort3kSec),
      (RunAchievementKind.bestEffort5k, 5000, activity.bestEffort5kSec),
      (RunAchievementKind.bestEffort10k, 10000, activity.bestEffort10kSec),
      (RunAchievementKind.bestEffortHalf, 21097.5, activity.bestEffortHalfSec),
      (
        RunAchievementKind.bestEffortMarathon,
        42195,
        activity.bestEffortMarathonSec,
      ),
    ];
    return [
      for (final (kind, meters, seconds) in candidates)
        if (seconds != null && seconds > 0)
          RunBestEffort(kind: kind, distanceMeters: meters, seconds: seconds),
    ];
  }
}

/// "Best efforts in this run": times for 1k..marathon with a medal when the
/// effort is a top-3 all-time placement.
class RunBestEffortsCard extends StatelessWidget {
  final List<RunBestEffort> efforts;
  final List<RunAchievementPlacement> medals;

  const RunBestEffortsCard({
    super.key,
    required this.efforts,
    required this.medals,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    return AppSectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: AppDividedList(
        children: [
          for (final effort in efforts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 58,
                    child: Text(
                      runAchievementKindShortLabel(loc, effort.kind),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '${RunFormatters.paceShort(effort.paceSecPerKm)} /km',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontFeatures: AppUi.tabular,
                      ),
                    ),
                  ),
                  ..._medalFor(effort),
                  Text(
                    RunFormatters.duration(effort.seconds),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      fontFeatures: AppUi.tabular,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _medalFor(RunBestEffort effort) {
    for (final placement in medals) {
      if (placement.kind == effort.kind) {
        return [
          RunMedalDot(tier: placement.tier, size: 20),
          const SizedBox(width: 10),
        ];
      }
    }
    return const [];
  }
}

/// Banner shown instead of the map for timer-only (indoor) sessions.
class RunIndoorBanner extends StatelessWidget {
  final RunActivity activity;

  const RunIndoorBanner({super.key, required this.activity});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    return Container(
      height: 150,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colors.secondaryContainer, colors.surfaceContainerLow],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppUi.heroRadius),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            activity.isStationaryBike
                ? Icons.pedal_bike_rounded
                : Icons.directions_run_rounded,
            size: 54,
            color: colors.secondary,
          ),
          const SizedBox(height: 8),
          Text(
            loc.stationaryBikeIndoorHeadline,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            activity.isStationaryBike
                ? loc.cardioActivityStationaryBikeSubtitle
                : loc.runHistoryFilterTreadmill,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
