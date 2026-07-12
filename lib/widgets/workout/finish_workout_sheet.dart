import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/workout_summary.dart';
import 'package:workout_notes/widgets/workout/stat_tile.dart';
import 'package:workout_notes/utils/pace_calculator.dart';

export 'package:workout_notes/models/workout_summary.dart'
    show PR, WorkoutSummary;

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

  double get paceSeconds => distance > 0 ? timeSeconds / distance : 0;
}

/// Exercise bests data class.
class ExerciseBests {
  final String name;
  final double maxWeight;
  final int bestReps;
  final double volume;
  final int completedSets;

  const ExerciseBests({
    required this.name,
    required this.maxWeight,
    required this.bestReps,
    required this.volume,
    required this.completedSets,
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

  String get _feelingLabel {
    final loc = AppLocalizations.of(context)!;
    switch (_rating) {
      case 1:
        return loc.activeWorkoutFeeling1;
      case 2:
        return loc.activeWorkoutFeeling2;
      case 3:
        return loc.activeWorkoutFeeling3;
      case 4:
        return loc.activeWorkoutFeeling4;
      case 5:
        return loc.activeWorkoutFeeling5;
      default:
        return '';
    }
  }

  IconData get _feelingIcon {
    switch (_rating) {
      case 1:
        return Icons.sentiment_very_dissatisfied;
      case 2:
        return Icons.sentiment_dissatisfied;
      case 3:
        return Icons.sentiment_neutral;
      case 4:
        return Icons.sentiment_satisfied;
      case 5:
        return Icons.sentiment_very_satisfied;
      default:
        return Icons.sentiment_neutral;
    }
  }

  Color _feelingColor(ThemeData theme) {
    if (_rating <= 2) return Colors.red;
    if (_rating == 3) return Colors.orange;
    return Colors.green;
  }

  Widget _buildStatsGrid(
    BuildContext context,
    ThemeData theme,
    WorkoutSummary summary,
  ) {
    final loc = AppLocalizations.of(context)!;
    final firstRow = [
      StatTile(
        icon: Icons.timer,
        label: loc.activeWorkoutTimerDuration,
        value: summary.formattedDuration,
        color: theme.colorScheme.primary,
        theme: theme,
      ),
      const SizedBox(width: 8),
      StatTile(
        icon: Icons.auto_graph,
        label: loc.commonVolume,
        value: '${summary.formattedVolume} kg',
        color: theme.colorScheme.secondary,
        theme: theme,
      ),
    ];

    final secondRow = [
      StatTile(
        icon: Icons.fitness_center,
        label: loc.commonSets,
        value: '${summary.completedSets}/${summary.totalSets}',
        color: Colors.orange,
        theme: theme,
      ),
      if (summary.densityKgPerMinute != null) ...[
        const SizedBox(width: 8),
        StatTile(
          icon: Icons.speed,
          label: loc.workoutStatsDensity,
          value: '${summary.formattedDensity} ${loc.workoutStatsKgPerMin}',
          color: Colors.teal,
          theme: theme,
        ),
      ],
    ];

    return Column(
      children: [
        Row(children: firstRow),
        const SizedBox(height: 6),
        Row(children: secondRow),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.summary;
    final completedPct = s.totalSets > 0 ? s.completedSets / s.totalSets : 0.0;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Handle ──
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withAlpha(80),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.celebration,
                      size: 36,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    AppLocalizations.of(context)!.activeWorkoutCompleted,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    AppLocalizations.of(context)!.activeWorkoutSummarySubtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Stats Grid ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _buildStatsGrid(context, theme, s),
            ),

            // Progress bar
            if (s.totalSets > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: completedPct,
                    minHeight: 8,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    color: completedPct >= 1.0
                        ? Colors.green
                        : theme.colorScheme.primary,
                  ),
                ),
              ),

            // Cardio stats - only show if there's cardio data
            if (s.totalDistance > 0 || s.totalCardioTime > 0) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    StatTile(
                      icon: Icons.map,
                      label: AppLocalizations.of(
                        context,
                      )!.workoutHomeCardioDistance,
                      value: s.formattedDistance,
                      color: const Color(0xFFE53935),
                      theme: theme,
                    ),
                    const SizedBox(width: 8),
                    StatTile(
                      icon: Icons.timer_outlined,
                      label: AppLocalizations.of(
                        context,
                      )!.workoutHomeCardioTime,
                      value: s.formattedCardioTime,
                      color: Colors.deepOrange,
                      theme: theme,
                    ),
                    if (s.totalDistance > 0 && s.totalCardioTime > 0) ...[
                      const SizedBox(width: 8),
                      StatTile(
                        icon: Icons.speed,
                        label: AppLocalizations.of(context)!.commonPace,
                        value: PaceCalculator.formatPace(
                          s.totalCardioTime / s.totalDistance,
                        ),
                        color: Colors.brown,
                        theme: theme,
                      ),
                    ],
                  ],
                ),
              ),
            ],

            // ── PRs Section ──
            if (s.prs.isNotEmpty) ...[
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.emoji_events,
                          size: 20,
                          color: Colors.amber.shade700,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          AppLocalizations.of(
                            context,
                          )!.activeWorkoutPersonalRecords,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...s.prs.map(
                      (pr) => Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.amber.withAlpha(20),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.amber.withAlpha(60)),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.emoji_events,
                              size: 18,
                              color: Colors.amber.shade700,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    pr.exerciseName,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    pr.value,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text('🎉', style: theme.textTheme.titleMedium),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ── Feeling Rating ──
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.favorite,
                        size: 18,
                        color: Colors.red.shade300,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        AppLocalizations.of(
                          context,
                        )!.activeWorkoutHowWasWorkout,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (i) {
                      final star = i + 1;
                      final isFilled = star <= _rating;
                      return GestureDetector(
                        onTap: () => setState(() => _rating = star),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          padding: const EdgeInsets.all(6),
                          child: Icon(
                            isFilled ? Icons.star : Icons.star_outline,
                            color: isFilled
                                ? Colors.amber
                                : theme.colorScheme.outlineVariant,
                            size: 36,
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(_feelingIcon, size: 16, color: _feelingColor(theme)),
                      const SizedBox(width: 6),
                      Text(
                        _feelingLabel,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: _feelingColor(theme),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ── Comment ──
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: TextField(
                controller: _commentCtl,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: AppLocalizations.of(
                    context,
                  )!.activeWorkoutCommentHint,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest
                      .withAlpha(80),
                  prefixIcon: Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Icon(
                      Icons.edit_note,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),

            // ── Buttons ──
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Row(
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
                      child: Text(AppLocalizations.of(context)!.commonCancel),
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
                        AppLocalizations.of(
                          context,
                        )!.activeWorkoutFinishWorkout,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Bottom padding for safe area
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
