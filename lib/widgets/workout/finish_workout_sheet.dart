import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/utils/app_number_format.dart';
import 'package:workout_notes/utils/duration_format.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/utils/strength_workout_format.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Summary data class for finished workout.
class WorkoutSummary {
  final int durationSeconds;
  final double totalVolume;
  final int totalSets;
  final int completedSets;
  final List<PR> prs;
  final double totalDistance;
  final int totalCardioTime;
  final double? estimatedCalories;

  const WorkoutSummary({
    required this.durationSeconds,
    required this.totalVolume,
    required this.totalSets,
    required this.completedSets,
    this.prs = const [],
    this.totalDistance = 0,
    this.totalCardioTime = 0,
    this.estimatedCalories,
  });

  String get formattedDuration {
    if (durationSeconds <= 0) return '--';
    final h = durationSeconds ~/ 3600;
    if (h >= 24) {
      final d = h ~/ 24;
      final restH = h % 24;
      return restH > 0 ? '${d}d ${restH}h' : '${d}d';
    }
    return DurationFormat.elapsed(durationSeconds);
  }

  String get formattedVolume {
    if (totalVolume >= 1000000) {
      return '${AppNumberFormat.decimal(totalVolume / 1000000, 1)}M';
    }
    if (totalVolume >= 1000) {
      return '${AppNumberFormat.decimal(totalVolume / 1000, 1)}k';
    }
    return AppNumberFormat.decimal(totalVolume, 0);
  }

  double? get densityKgPerMinute {
    if (durationSeconds <= 0 || totalVolume <= 0) return null;
    return totalVolume / (durationSeconds / 60.0);
  }

  String get formattedDensity {
    final density = densityKgPerMinute;
    if (density == null) return '--';
    return AppNumberFormat.decimal(density, density >= 10 ? 0 : 1);
  }

  String get formattedDistance {
    if (totalDistance <= 0) return '--';
    return '${AppNumberFormat.decimal(totalDistance, 1)} km';
  }

  String get formattedCardioTime {
    if (totalCardioTime <= 0) return '--';
    final min = totalCardioTime ~/ 60;
    if (min >= 60) {
      return '${min ~/ 60}h${min % 60}min';
    }
    return '${min}min';
  }

  String get formattedCalories {
    final calories = estimatedCalories;
    if (calories == null || calories <= 0) return '--';
    return calories.round().toString();
  }
}

/// Personal record data class.
///
/// [type] is `e1rm`, `weight`, `volume` or `distance`; [value] is the new
/// best already formatted, [previous] the one it beat (empty when unknown).
class PR {
  final String exerciseName;
  final String type;
  final String value;
  final String previous;

  const PR({
    required this.exerciseName,
    required this.type,
    required this.value,
    required this.previous,
  });

  IconData get icon => switch (type) {
    'volume' => Icons.bar_chart_rounded,
    'distance' => Icons.route_rounded,
    _ => Icons.emoji_events_rounded,
  };

  String label(AppLocalizations loc) => switch (type) {
    'e1rm' => loc.activeWorkoutPrKindE1rm,
    'volume' => loc.activeWorkoutPrKindVolume,
    'distance' => loc.activeWorkoutPrKindDistance,
    _ => loc.activeWorkoutPrKindWeight,
  };
}

/// Cardio bests data class for tracking distance/pace PRs.
class CardioBests {
  final String name;
  final double distance;
  final int timeSeconds;

  const CardioBests({
    required this.name,
    required this.distance,
    required this.timeSeconds,
  });
}

/// A bottom sheet shown when finishing a workout.
/// Displays summary stats, PRs, feeling rating, and comment input.
class FinishWorkoutSheet extends StatefulWidget {
  final WorkoutSummary summary;

  const FinishWorkoutSheet({super.key, required this.summary});

  @override
  State<FinishWorkoutSheet> createState() => _FinishWorkoutSheetState();
}

class _FinishWorkoutSheetState extends State<FinishWorkoutSheet> {
  int _rating = 3;
  final _commentCtl = TextEditingController();

  @override
  void dispose() {
    _commentCtl.dispose();
    super.dispose();
  }

  String _feelingLabel(AppLocalizations loc) => switch (_rating) {
    1 => loc.activeWorkoutFeeling1,
    2 => loc.activeWorkoutFeeling2,
    3 => loc.activeWorkoutFeeling3,
    4 => loc.activeWorkoutFeeling4,
    5 => loc.activeWorkoutFeeling5,
    _ => '',
  };

  IconData get _feelingIcon => switch (_rating) {
    1 => Icons.sentiment_very_dissatisfied_rounded,
    2 => Icons.sentiment_dissatisfied_rounded,
    3 => Icons.sentiment_neutral_rounded,
    4 => Icons.sentiment_satisfied_rounded,
    _ => Icons.sentiment_very_satisfied_rounded,
  };

  Color _feelingColor(ColorScheme colors) {
    if (_rating <= 2) return colors.error;
    if (_rating == 3) return colors.tertiary;
    return colors.primary;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final s = widget.summary;
    final completedPct = s.totalSets > 0 ? s.completedSets / s.totalSets : 0.0;
    final hasCardio = s.totalDistance > 0 || s.totalCardioTime > 0;
    final calories = s.estimatedCalories;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.onSurfaceVariant.withAlpha(80),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Header
            Row(
              children: [
                AppIconBadge(
                  s.prs.isNotEmpty
                      ? Icons.emoji_events_rounded
                      : Icons.check_circle_outline_rounded,
                  size: 48,
                  iconSize: 26,
                  color: s.prs.isNotEmpty ? colors.tertiary : colors.primary,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loc.activeWorkoutCompleted,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        s.prs.isNotEmpty
                            ? loc.activeWorkoutSummaryRecordsCount(s.prs.length)
                            : loc.activeWorkoutSummarySubtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Key numbers
            AppMetricGrid(
              children: [
                AppMetricBox(
                  icon: Icons.timer_outlined,
                  label: loc.activeWorkoutTimerDuration,
                  value: s.formattedDuration,
                ),
                AppMetricBox(
                  icon: Icons.monitor_weight_outlined,
                  label: loc.commonVolume,
                  value: StrengthWorkoutFormat.volume(s.totalVolume),
                ),
                AppMetricBox(
                  icon: Icons.repeat_rounded,
                  label: loc.commonSets,
                  value: '${s.completedSets}/${s.totalSets}',
                ),
                if (s.densityKgPerMinute != null)
                  AppMetricBox(
                    icon: Icons.bolt_rounded,
                    label: loc.workoutStatsDensity,
                    value: '${s.formattedDensity} ${loc.workoutStatsKgPerMin}',
                  ),
                if (calories != null && calories > 0)
                  AppMetricBox(
                    icon: Icons.local_fire_department_rounded,
                    label: loc.workoutEstimatedCalories,
                    value: '${s.formattedCalories} kcal',
                  ),
              ],
            ),
            if (s.totalSets > 0) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: completedPct,
                  minHeight: 6,
                  backgroundColor: colors.surfaceContainerHighest,
                ),
              ),
            ],

            // Cardio stats - only show if there's cardio data
            if (hasCardio) ...[
              const SizedBox(height: 12),
              AppMetricGrid(
                children: [
                  AppMetricBox(
                    icon: Icons.map_outlined,
                    label: loc.workoutHomeCardioDistance,
                    value: s.formattedDistance,
                  ),
                  AppMetricBox(
                    icon: Icons.timer_outlined,
                    label: loc.workoutHomeCardioTime,
                    value: s.formattedCardioTime,
                  ),
                  if (s.totalDistance > 0 && s.totalCardioTime > 0)
                    AppMetricBox(
                      icon: Icons.speed_rounded,
                      label: loc.commonPace,
                      value:
                          '${RunFormatters.paceShort(s.totalCardioTime / s.totalDistance)} /km',
                    ),
                ],
              ),
            ],

            // Personal records of this session
            if (s.prs.isNotEmpty) ...[
              AppSectionHeader(loc.activeWorkoutPersonalRecords),
              AppSectionCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: AppDividedList(
                  children: [for (final pr in s.prs) _PrRow(pr: pr)],
                ),
              ),
            ],

            // Feeling
            AppSectionHeader(loc.activeWorkoutHowWasWorkout),
            AppSectionCard(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (i) {
                      final star = i + 1;
                      final isFilled = star <= _rating;
                      return InkResponse(
                        radius: 26,
                        onTap: () => setState(() => _rating = star),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(
                            isFilled
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            color: isFilled
                                ? colors.tertiary
                                : colors.outlineVariant,
                            size: 36,
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _feelingIcon,
                        size: 18,
                        color: _feelingColor(colors),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _feelingLabel(loc),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: _feelingColor(colors),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Comment
            const SizedBox(height: 12),
            TextField(
              controller: _commentCtl,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: loc.activeWorkoutCommentHint,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppUi.tileRadius),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: colors.surfaceContainerHighest.withAlpha(90),
                prefixIcon: Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Icon(
                    Icons.edit_note_rounded,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ),

            // Buttons
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(loc.commonCancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, {
                      'feeling': _rating,
                      'comment': _commentCtl.text,
                    }),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      loc.activeWorkoutFinishWorkout,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _PrRow extends StatelessWidget {
  final PR pr;

  const _PrRow({required this.pr});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          AppIconBadge(pr.icon, color: colors.tertiary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pr.exerciseName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${pr.label(loc)} · ${pr.value}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                if (pr.previous.isNotEmpty)
                  Text(
                    loc.activeWorkoutPrPrevious(pr.previous),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
