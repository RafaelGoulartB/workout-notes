import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_achievement.dart';
import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/models/run_workout_step.dart';
import 'package:workout_notes/models/scheduled_run.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/utils/run_review_insights.dart';
import 'package:workout_notes/widgets/run/run_achievements_section.dart';
import 'package:workout_notes/widgets/run/run_medal_badge.dart';
import 'package:workout_notes/widgets/run/run_plan_ui.dart';
import 'package:workout_notes/widgets/run/run_route_sketch.dart';
import 'package:workout_notes/widgets/run/run_theme_colors.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Headline card of the post-run review: the distance, the route sketch and
/// a row of the numbers that matter.
class RunReviewHero extends StatelessWidget {
  final RunActivity activity;

  /// Distance shown (typed in by the runner for indoor sessions).
  final double distanceMeters;
  final String headline;
  final double? paceSecPerKm;

  /// Average speed instead of pace, for the stationary bike.
  final double? speedKmh;
  final String? speedUnit;
  final double? elevationGainMeters;
  final List<Offset> route;

  const RunReviewHero({
    super.key,
    required this.activity,
    required this.distanceMeters,
    required this.headline,
    required this.paceSecPerKm,
    this.speedKmh,
    this.speedUnit,
    this.elevationGainMeters,
    this.route = const [],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final dateLabel = DateFormat.MMMEd(
      Localizations.localeOf(context).toString(),
    ).add_Hm().format(activity.startedAt.toLocal());
    final hasRoute = RunRouteSketch.hasShape(route);
    final usesSpeed = speedUnit != null;
    final calories = activity.calories;
    final gain = elevationGainMeters;

    return AppHeroCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppIconBadge(
                activity.isStationaryBike
                    ? Icons.pedal_bike_rounded
                    : Icons.directions_run_rounded,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      dateLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loc.runReviewDistance.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: AppValueUnit(
                        value: RunFormatters.distanceKm(distanceMeters),
                        unit: 'km',
                        valueStyle: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.05,
                          letterSpacing: -1,
                        ),
                        unitStyle: theme.textTheme.titleLarge?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (hasRoute)
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surface.withAlpha(100),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: RunRouteSketch(points: route, width: 84, height: 84),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            decoration: BoxDecoration(
              color: colors.surface.withAlpha(140),
              borderRadius: BorderRadius.circular(AppUi.tileRadius + 4),
            ),
            child: AppStatRow(
              children: [
                AppStatTile(
                  icon: Icons.timer_outlined,
                  color: colors.onSurfaceVariant,
                  label: loc.runReviewTime,
                  value: RunFormatters.duration(activity.durationSeconds),
                ),
                if (usesSpeed)
                  AppStatTile(
                    icon: Icons.speed_rounded,
                    color: colors.onSurfaceVariant,
                    label: loc.stationaryBikeAverageSpeed,
                    value: RunFormatters.speedKmh(speedKmh),
                    unit: speedUnit,
                  )
                else
                  AppStatTile(
                    icon: Icons.speed_rounded,
                    color: colors.onSurfaceVariant,
                    label: loc.runReviewPace,
                    value: RunFormatters.paceShort(paceSecPerKm),
                    unit: '/km',
                  ),
                if (gain != null)
                  AppStatTile(
                    icon: Icons.terrain_rounded,
                    color: colors.onSurfaceVariant,
                    label: loc.runDetailElevation,
                    value: '+${gain.round()}',
                    unit: 'm',
                  ),
                if (calories != null && calories > 0)
                  AppStatTile(
                    icon: Icons.local_fire_department_outlined,
                    color: colors.onSurfaceVariant,
                    label: loc.runDetailCalories,
                    value: '$calories',
                    unit: 'kcal',
                  ),
              ],
            ),
          ),
          if (activity.isRun && activity.bestSplitPaceSecPerKm != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.bolt_rounded, size: 15, color: colors.tertiary),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '${loc.runDetailFastestKm}: '
                    '${RunFormatters.paceShort(activity.bestSplitPaceSecPerKm)} /km',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Planned vs actual comparison of the session the run was recorded against.
class RunReviewPlanCard extends StatelessWidget {
  final RunPlanWorkout workout;
  final RunActivity activity;
  final List<RunActivityStep> stepResults;
  final bool isTooShort;
  final bool completePlanned;
  final ValueChanged<bool> onCompletePlannedChanged;

  const RunReviewPlanCard({
    super.key,
    required this.workout,
    required this.activity,
    required this.stepResults,
    required this.isTooShort,
    required this.completePlanned,
    required this.onCompletePlannedChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final outline = RunPlanUi.stepsOutline(loc, workout);
    return AppSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            workout.name,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            RunPlanUi.sessionSummary(loc, workout),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          if (outline.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(outline, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 14),
          // IntrinsicHeight bounds the cross axis so the two panels can match
          // heights: a bare stretch Row inside a scrolling Column gets an
          // unbounded height and lays out garbage.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _ComparisonPanel(
                    label: loc.runReviewPlanned,
                    distanceMeters: workout.plannedDistanceMeters,
                    durationSeconds: workout.plannedDurationSeconds,
                    paceSecPerKm: workout.targetPaceSecPerKm,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ComparisonPanel(
                    label: loc.runReviewActual,
                    distanceMeters: activity.distanceMeters,
                    durationSeconds: activity.durationSeconds,
                    paceSecPerKm: activity.avgPaceSecPerKm,
                    highlight: true,
                  ),
                ),
              ],
            ),
          ),
          if (stepResults.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final step in stepResults) _StepResultRow(step: step),
          ],
          const SizedBox(height: 12),
          if (isTooShort)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.errorContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: colors.onErrorContainer,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          loc.runReviewShortTitle,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: colors.onErrorContainer,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          loc.runReviewShortBody,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onErrorContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else
            _ToggleRow(
              value: completePlanned,
              label: loc.runReviewCompletePlan,
              onChanged: onCompletePlannedChanged,
            ),
        ],
      ),
    );
  }
}

class _ComparisonPanel extends StatelessWidget {
  final String label;
  final double distanceMeters;
  final int durationSeconds;
  final double? paceSecPerKm;
  final bool highlight;

  const _ComparisonPanel({
    required this.label,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.paceSecPerKm,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: highlight
            ? colors.primaryContainer.withAlpha(115)
            : colors.surfaceContainerHighest.withAlpha(128),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 0.9,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            // A planned session may target only time, or only distance.
            distanceMeters >= 1
                ? RunFormatters.distanceWithUnit(distanceMeters)
                : '—',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            durationSeconds > 0 ? RunFormatters.duration(durationSeconds) : '—',
            style: theme.textTheme.bodySmall,
          ),
          Text(
            '${RunFormatters.paceShort(paceSecPerKm)} /km',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepResultRow extends StatelessWidget {
  final RunActivityStep step;

  const _StepResultRow({required this.step});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final role = RunStepRole.fromString(step.role);
    final color = RunPlanUi.roleColor(theme.colorScheme, role);
    final done =
        step.actualDistanceMeters != null && step.actualDistanceMeters! >= 1
        ? RunFormatters.distanceWithUnit(step.actualDistanceMeters!)
        : RunFormatters.duration(step.actualDurationSeconds ?? 0);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 24,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${RunPlanUi.roleLabel(loc, role)} ${step.repIndex}',
              style: theme.textTheme.bodySmall,
            ),
          ),
          Text(
            done,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: AppUi.tabular,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            RunFormatters.paceShort(step.actualPaceSecPerKm),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontFeatures: AppUi.tabular,
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final bool value;
  final String label;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.value,
    required this.label,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: value
          ? colors.primaryContainer.withAlpha(100)
          : colors.surfaceContainerHighest.withAlpha(128),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 14, 4),
          child: Row(
            children: [
              Checkbox(
                value: value,
                visualDensity: VisualDensity.compact,
                onChanged: (next) => onChanged(next ?? true),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: value ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 1..10 perceived-effort picker with a zone label.
class RunEffortSelector extends StatelessWidget {
  final double? rpe;
  final ValueChanged<double> onChanged;

  const RunEffortSelector({
    super.key,
    required this.rpe,
    required this.onChanged,
  });

  static String zoneLabel(AppLocalizations loc, int value) {
    if (value <= 3) return loc.runReviewEffortZoneEasy;
    if (value <= 6) return loc.runReviewEffortZoneModerate;
    if (value <= 8) return loc.runReviewEffortZoneHard;
    return loc.runReviewEffortZoneMax;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final selected = rpe?.round();
    return AppSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (var value = 1; value <= 10; value++) ...[
                if (value > 1) const SizedBox(width: 4),
                Expanded(child: _option(context, value)),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                loc.runReviewEffortScaleMin,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Text(
                loc.runReviewEffortScaleMax,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AnimatedSize(
            duration: const Duration(milliseconds: 140),
            alignment: Alignment.centerLeft,
            child: selected == null
                ? Text(
                    loc.runReviewEffortEmpty,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  )
                : Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: RunThemeColors.effort(colors, selected),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$selected/10 · ${zoneLabel(loc, selected)}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _option(BuildContext context, int value) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final selected = rpe == value.toDouble();
    final zoneColor = RunThemeColors.effort(colors, value);
    final foreground = selected
        ? (ThemeData.estimateBrightnessForColor(zoneColor) == Brightness.dark
              ? Colors.white
              : Colors.black87)
        : colors.onSurfaceVariant;
    return Semantics(
      label: '$value',
      selected: selected,
      button: true,
      child: SizedBox(
        key: ValueKey('run-review-rpe-$value'),
        height: 44,
        child: Material(
          color: selected ? zoneColor : colors.surfaceContainerHighest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: selected
                  ? zoneColor
                  : colors.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              onChanged(value.toDouble());
            },
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(
                    '$value',
                    maxLines: 1,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: foreground,
                      fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Five-star "how did you feel" picker; tapping the current rating clears it.
class RunFeelingSelector extends StatelessWidget {
  /// 0 or null = no rating.
  final int? rating;
  final ValueChanged<int> onChanged;

  const RunFeelingSelector({
    super.key,
    required this.rating,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final ratingColor = Colors.amber.shade600;
    final labels = [
      loc.runReviewFeelingVeryBad,
      loc.runReviewFeelingBad,
      loc.runReviewFeelingNeutral,
      loc.runReviewFeelingGood,
      loc.runReviewFeelingGreat,
    ];
    final value = rating ?? 0;
    return AppSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(5, (index) {
              final isSelected = index < value;
              return IconButton(
                key: ValueKey('run-review-feeling-${index + 1}'),
                tooltip: labels[index],
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  onChanged(isSelected && value == index + 1 ? 0 : index + 1);
                },
                icon: Icon(
                  isSelected ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 32,
                  color: isSelected
                      ? ratingColor
                      : colors.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              );
            }),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              value >= 1 && value <= 5
                  ? labels[value - 1]
                  : loc.runReviewFeelingEmpty,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: value >= 1 ? FontWeight.w700 : FontWeight.w400,
                color: value >= 1 ? colors.onSurface : colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Manual distance field for sessions recorded with a timer only.
class RunIndoorDistanceField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;

  const RunIndoorDistanceField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      child: TextField(
        key: const ValueKey('stationary-bike-distance'),
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
        ],
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: const Icon(Icons.straighten_rounded),
          suffixText: 'km',
        ),
      ),
    );
  }
}

/// "What this run meant": record placements, month bests, the week's volume
/// and the next planned session, computed against the history.
class RunReviewMeaningCard extends StatelessWidget {
  final bool loading;
  final RunReviewInsights insights;
  final ScheduledRun? nextSession;

  /// Week volume to show when it differs from [insights] (indoor sessions
  /// whose distance is typed in after the insights were computed).
  final double? weekMeters;

  const RunReviewMeaningCard({
    super.key,
    required this.loading,
    required this.insights,
    required this.nextSession,
    this.weekMeters,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    if (loading) {
      return const AppSectionCard(
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }

    final locale = Localizations.localeOf(context).toString();
    final rows = <Widget>[];
    for (final placement in insights.placements.take(4)) {
      rows.add(
        _MeaningRow(
          leading: RunMedalDot(tier: placement.tier, size: 22),
          text:
              '${_tierLabel(loc, placement.tier)} · '
              '${runAchievementKindLabel(loc, placement.kind)}',
          emphasized: true,
        ),
      );
    }
    if (insights.longestOfMonth) {
      rows.add(
        _MeaningRow(
          leading: _icon(context, Icons.straighten_rounded),
          text: loc.runReviewMeaningLongestMonth,
        ),
      );
    }
    if (insights.fastestOfMonth) {
      rows.add(
        _MeaningRow(
          leading: _icon(context, Icons.bolt_rounded),
          text: loc.runReviewMeaningFastestMonth,
        ),
      );
    }
    if (insights.isFirstRun) {
      rows.add(
        _MeaningRow(
          leading: _icon(context, Icons.flag_rounded),
          text: loc.runReviewMeaningFirst,
        ),
      );
    } else if (!insights.hasHighlights) {
      rows.add(
        _MeaningRow(
          leading: _icon(context, Icons.workspace_premium_outlined),
          text: loc.runReviewNoAchievements,
          muted: true,
        ),
      );
    }
    final week = weekMeters ?? insights.weekMeters;
    if (week > 0) {
      rows.add(
        _MeaningRow(
          leading: _icon(context, Icons.date_range_rounded),
          text: loc.runReviewMeaningWeekTotal(
            RunFormatters.distanceWithUnit(week),
          ),
        ),
      );
    }
    final next = nextSession;
    if (next != null) {
      rows.add(
        _MeaningRow(
          leading: _icon(context, Icons.event_available_rounded),
          text: loc.runReviewMeaningNext(
            next.workout?.name ?? loc.runDetailUntitled,
            DateFormat.MMMEd(locale).format(next.date),
          ),
        ),
      );
    }

    return AppSectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(height: 1, color: colors.outlineVariant.withAlpha(70)),
            rows[i],
          ],
        ],
      ),
    );
  }

  static Widget _icon(BuildContext context, IconData icon) =>
      Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary);

  static String _tierLabel(AppLocalizations loc, RunMedalTier tier) =>
      switch (tier) {
        RunMedalTier.gold => loc.runAchievementTierGold,
        RunMedalTier.silver => loc.runAchievementTierSilver,
        RunMedalTier.bronze => loc.runAchievementTierBronze,
      };
}

class _MeaningRow extends StatelessWidget {
  final Widget leading;
  final String text;
  final bool emphasized;
  final bool muted;

  const _MeaningRow({
    required this.leading,
    required this.text,
    this.emphasized = false,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          SizedBox(width: 26, child: Center(child: leading)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: emphasized ? FontWeight.w700 : FontWeight.w500,
                color: muted ? theme.colorScheme.onSurfaceVariant : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
