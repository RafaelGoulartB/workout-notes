import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/l10n/exercise_locale_helper.dart';
import 'package:workout_notes/models/exercise_with_sets.dart';
import 'package:workout_notes/utils/strength_workout_format.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

enum ActiveWorkoutTimerPhase { idle, running, paused, finished }

/// Compact top of the active workout: a ring with sets done, the workout
/// clock with its status and live volume, and a round play/pause button.
/// Tapping the card expands the per-muscle comparison with the last session.
class ActiveWorkoutHeader extends StatelessWidget {
  final ActiveWorkoutTimerPhase phase;

  /// The workout clock; only the time text listens to it.
  final ValueListenable<String> elapsed;
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
    final hasComparison = totalSets > 0 && categories.isNotEmpty;
    final clock = DateFormat('HH:mm');
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
      fontFeatures: AppUi.tabular,
    );

    // Status under the clock: not started / started at / paused / range.
    final start = startedAt;
    final (String status, Color? statusColor) = switch (phase) {
      ActiveWorkoutTimerPhase.idle => (loc.activeWorkoutTimerNotStarted, null),
      ActiveWorkoutTimerPhase.running => (
        start == null
            ? ''
            : '${loc.activeWorkoutTimerStartLabel} ${clock.format(start)}',
        null,
      ),
      ActiveWorkoutTimerPhase.paused => (loc.restTimerPaused, colors.tertiary),
      ActiveWorkoutTimerPhase.finished => (
        start != null && endedAt != null
            ? '${clock.format(start)} → ${clock.format(endedAt!)}'
            : loc.activeWorkoutTimerDuration,
        null,
      ),
    };
    final details = [
      if (status.isNotEmpty) status,
      if (totalSets > 0) StrengthWorkoutFormat.volume(volume),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      child: Material(
        color: colors.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppUi.cardRadius),
          side: BorderSide(color: AppUi.divider(colors)),
        ),
        child: InkWell(
          onTap: hasComparison ? onToggleExpanded : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _SetsRing(
                      done: completedSets,
                      total: totalSets,
                      label: loc.activeWorkoutSetsProgress(
                        completedSets,
                        totalSets,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ValueListenableBuilder<String>(
                            valueListenable: elapsed,
                            builder: (context, value, _) => Text(
                              phase == ActiveWorkoutTimerPhase.idle
                                  ? '00:00'
                                  : value,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                                height: 1.1,
                                fontFeatures: AppUi.tabular,
                                color: phase == ActiveWorkoutTimerPhase.idle
                                    ? colors.onSurfaceVariant
                                    : null,
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text.rich(
                            TextSpan(
                              children: [
                                for (var i = 0; i < details.length; i++) ...[
                                  if (i > 0) const TextSpan(text: ' · '),
                                  TextSpan(
                                    text: details[i],
                                    style: i == 0 && statusColor != null
                                        ? TextStyle(
                                            color: statusColor,
                                            fontWeight: FontWeight.w700,
                                          )
                                        : null,
                                  ),
                                ],
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: muted,
                          ),
                        ],
                      ),
                    ),
                    if (hasComparison)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: AnimatedRotation(
                          turns: expanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 180),
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    if (phase != ActiveWorkoutTimerPhase.finished)
                      _timerButton(loc, colors)
                    else
                      Icon(
                        Icons.check_circle_rounded,
                        color: colors.primary,
                        size: 28,
                      ),
                  ],
                ),
                if (totalSets > 0)
                  AnimatedSize(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: expanded && hasComparison
                        ? _MuscleComparison(categories: categories)
                        : const SizedBox(width: double.infinity),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Round play / pause action.
  Widget _timerButton(AppLocalizations loc, ColorScheme colors) {
    final (
      IconData icon,
      String tooltip,
      VoidCallback onPressed,
      bool tonal,
    ) = switch (phase) {
      ActiveWorkoutTimerPhase.idle => (
        Icons.play_arrow_rounded,
        loc.activeWorkoutStart,
        onStart,
        false,
      ),
      ActiveWorkoutTimerPhase.paused => (
        Icons.play_arrow_rounded,
        loc.restTimerResume,
        onResume,
        false,
      ),
      _ => (Icons.pause_rounded, loc.restTimerPause, onPause, true),
    };
    final style = IconButton.styleFrom(
      minimumSize: const Size(46, 46),
      iconSize: 26,
    );
    return tonal
        ? IconButton.filledTonal(
            style: style,
            tooltip: tooltip,
            onPressed: onPressed,
            icon: Icon(icon),
          )
        : IconButton.filled(
            style: style,
            tooltip: tooltip,
            onPressed: onPressed,
            icon: Icon(icon),
          );
  }
}

/// Completed working sets as a small ring with "done/total" inside.
class _SetsRing extends StatelessWidget {
  final int done;
  final int total;
  final String label;

  const _SetsRing({
    required this.done,
    required this.total,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final progress = total <= 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
    return SizedBox(
      width: 46,
      height: 46,
      child: CustomPaint(
        painter: _SetsRingPainter(
          progress: progress,
          color: colors.primary,
          track: colors.surfaceContainerHighest,
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: FittedBox(
              child: Text(
                total <= 0 ? '0' : label,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontFeatures: AppUi.tabular,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SetsRingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color track;

  const _SetsRingPainter({
    required this.progress,
    required this.color,
    required this.track,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 4.0;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );
    if (progress <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_SetsRingPainter old) =>
      old.progress != progress || old.color != color || old.track != track;
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
          Divider(height: 1, color: AppUi.divider(colors)),
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
