import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/l10n/exercise_locale_helper.dart';
import 'package:workout_notes/models/exercise_with_sets.dart';
import 'package:workout_notes/utils/strength_workout_format.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';

enum ActiveWorkoutTimerPhase { idle, running, paused, finished }

/// Top of the active workout: workout timer, set progress, sets done, live
/// volume and the expandable per-muscle comparison with the last session.
class ActiveWorkoutHeader extends StatelessWidget {
  final ActiveWorkoutTimerPhase phase;
  final String elapsed;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final int completedSets;
  final int totalSets;
  final double volume;
  final List<CategoryVolumeComparison> categories;
  final bool expanded;
  final VoidCallback onToggleExpanded;

  const ActiveWorkoutHeader({
    super.key,
    required this.phase,
    required this.elapsed,
    required this.startedAt,
    required this.endedAt,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.completedSets,
    required this.totalSets,
    required this.volume,
    required this.categories,
    required this.expanded,
    required this.onToggleExpanded,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final hasComparison = categories.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: RunHeroCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                RunIconBadge(
                  switch (phase) {
                    ActiveWorkoutTimerPhase.idle =>
                      Icons.play_circle_outline_rounded,
                    ActiveWorkoutTimerPhase.running => Icons.timer_outlined,
                    ActiveWorkoutTimerPhase.paused =>
                      Icons.pause_circle_outline_rounded,
                    ActiveWorkoutTimerPhase.finished =>
                      Icons.check_circle_outline_rounded,
                  },
                  size: 42,
                  iconSize: 22,
                  color: phase == ActiveWorkoutTimerPhase.paused
                      ? colors.tertiary
                      : colors.primary,
                ),
                const SizedBox(width: 12),
                Expanded(child: _timerText(context, loc)),
                if (phase != ActiveWorkoutTimerPhase.finished)
                  _timerButton(loc),
              ],
            ),
            if (totalSets > 0) ...[
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: completedSets / totalSets,
                  minHeight: 6,
                  backgroundColor: colors.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: hasComparison ? onToggleExpanded : null,
                borderRadius: BorderRadius.circular(RunUi.tileRadius),
                child: Row(
                  children: [
                    Expanded(
                      child: RunStatRow(
                        children: [
                          RunStatTile(
                            icon: Icons.repeat_rounded,
                            label: loc.commonSets,
                            value: '$completedSets',
                            unit: '/$totalSets',
                          ),
                          RunStatTile(
                            icon: Icons.monitor_weight_outlined,
                            label: loc.commonVolume,
                            value: StrengthWorkoutFormat.volume(volume),
                          ),
                        ],
                      ),
                    ),
                    if (hasComparison)
                      AnimatedRotation(
                        turns: expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: expanded && hasComparison
                    ? _MuscleComparison(categories: categories)
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _timerText(BuildContext context, AppLocalizations loc) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final clock = DateFormat('HH:mm');
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final start = startedAt;
    switch (phase) {
      case ActiveWorkoutTimerPhase.idle:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              loc.activeWorkoutTimerTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(loc.activeWorkoutStartTimerTooltip, style: muted),
          ],
        );
      case ActiveWorkoutTimerPhase.running:
      case ActiveWorkoutTimerPhase.paused:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              elapsed,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                fontFeatures: RunUi.tabular,
              ),
            ),
            Row(
              children: [
                if (phase == ActiveWorkoutTimerPhase.paused) ...[
                  RunPill(label: loc.restTimerPaused, color: colors.tertiary),
                  const SizedBox(width: 8),
                ],
                if (start != null)
                  Flexible(
                    child: Text(
                      '${loc.activeWorkoutTimerStartLabel} ${clock.format(start)}',
                      style: muted,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ],
        );
      case ActiveWorkoutTimerPhase.finished:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${loc.activeWorkoutTimerDuration} $elapsed',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                fontFeatures: RunUi.tabular,
              ),
            ),
            if (start != null && endedAt != null)
              Text(
                '${clock.format(start)} → ${clock.format(endedAt!)}',
                style: muted,
              ),
          ],
        );
    }
  }

  Widget _timerButton(AppLocalizations loc) {
    switch (phase) {
      case ActiveWorkoutTimerPhase.idle:
        return FilledButton(
          onPressed: onStart,
          child: Text(loc.activeWorkoutStart),
        );
      case ActiveWorkoutTimerPhase.running:
        return FilledButton.tonal(
          onPressed: onPause,
          child: Text(loc.restTimerPause),
        );
      case ActiveWorkoutTimerPhase.paused:
        return FilledButton(
          onPressed: onResume,
          child: Text(loc.restTimerResume),
        );
      case ActiveWorkoutTimerPhase.finished:
        return const SizedBox.shrink();
    }
  }
}

/// Current vs last-session volume per muscle group.
class _MuscleComparison extends StatelessWidget {
  final List<CategoryVolumeComparison> categories;

  const _MuscleComparison({required this.categories});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final maxVolume = categories.fold<double>(0, (max, item) {
      final itemMax = item.currentVolume > item.lastVolume
          ? item.currentVolume
          : item.lastVolume;
      return itemMax > max ? itemMax : max;
    });

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(height: 1, color: RunUi.divider(colors)),
          const SizedBox(height: 10),
          Text(
            loc.activeWorkoutByMuscleGroup,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          for (final comparison in categories)
            _row(theme, colors, loc, comparison, maxVolume),
        ],
      ),
    );
  }

  Widget _row(
    ThemeData theme,
    ColorScheme colors,
    AppLocalizations loc,
    CategoryVolumeComparison comparison,
    double maxVolume,
  ) {
    final name = comparison.categoryId.isNotEmpty
        ? ExerciseLocaleHelper.categoryNameFromId(loc, comparison.categoryId)
        : comparison.categoryName;
    final delta = comparison.delta;
    final deltaColor = delta > 0
        ? colors.primary
        : delta < 0
        ? colors.error
        : colors.onSurfaceVariant;
    final percent = comparison.deltaPercent;
    final deltaText =
        '${StrengthWorkoutFormat.signedVolume(delta)}'
        '${percent == null ? '' : ' (${percent > 0 ? '+' : ''}${percent.round()}%)'}';
    final width = maxVolume > 0
        ? (comparison.currentVolume / maxVolume).clamp(0.0, 1.0)
        : 0.0;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: comparison.categoryColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                deltaText,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: deltaColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Stack(
                    children: [
                      Container(
                        height: 6,
                        color: colors.surfaceContainerHighest,
                      ),
                      FractionallySizedBox(
                        widthFactor: width,
                        child: Container(
                          height: 6,
                          color: comparison.categoryColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${StrengthWorkoutFormat.volume(comparison.currentVolume)} / '
                '${StrengthWorkoutFormat.volume(comparison.lastVolume)}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
