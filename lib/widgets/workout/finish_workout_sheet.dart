import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/widgets/workout/stat_tile.dart';

/// Summary data class for finished workout.
class WorkoutSummary {
  final int durationSeconds;
  final double totalVolume;
  final int totalSets;
  final int completedSets;
  final List<PR> prs;

  const WorkoutSummary({
    required this.durationSeconds,
    required this.totalVolume,
    required this.totalSets,
    required this.completedSets,
    required this.prs,
  });

  String get formattedDuration {
    if (durationSeconds <= 0) return '--';
    final h = durationSeconds ~/ 3600;
    final m = (durationSeconds % 3600) ~/ 60;
    final s = durationSeconds % 60;
    if (h > 0) {
      return '${h}h${m.toString().padLeft(2, '0')}min';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String get formattedVolume {
    if (totalVolume >= 1000000) {
      return '${(totalVolume / 1000000).toStringAsFixed(1)}M';
    }
    if (totalVolume >= 1000) {
      return '${(totalVolume / 1000).toStringAsFixed(1)}k';
    }
    return totalVolume.toStringAsFixed(0);
  }
}

/// Personal record data class.
class PR {
  final String exerciseName;
  final String type; // 'weight' or 'volume'
  final String value;
  final String previous;

  const PR({
    required this.exerciseName,
    required this.type,
    required this.value,
    required this.previous,
  });

  String get label {
    return type == 'weight' ? '🏋️ Peso Máximo' : '📦 Volume';
  }

  IconData get icon =>
      type == 'weight' ? Icons.emoji_events : Icons.inventory_2;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.summary;
    final completedPct =
        s.totalSets > 0 ? s.completedSets / s.totalSets : 0.0;

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
                  color: theme.colorScheme.onSurfaceVariant
                      .withAlpha(80),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // ── Header ──
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(24, 16, 24, 0),
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
                      color: theme
                          .colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    AppLocalizations.of(context)!
                        .activeWorkoutCompleted,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    AppLocalizations.of(context)!
                        .activeWorkoutSummarySubtitle,
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  StatTile(
                    icon: Icons.timer,
                    label: AppLocalizations.of(context)!
                        .activeWorkoutTimerDuration,
                    value: s.formattedDuration,
                    color: theme.colorScheme.primary,
                    theme: theme,
                  ),
                  const SizedBox(width: 8),
                  StatTile(
                    icon: Icons.auto_graph,
                    label: AppLocalizations.of(context)!
                        .commonVolume,
                    value: '${s.formattedVolume} kg',
                    color: theme.colorScheme.secondary,
                    theme: theme,
                  ),
                  const SizedBox(width: 8),
                  StatTile(
                    icon: Icons.fitness_center,
                    label: AppLocalizations.of(context)!
                        .commonSets,
                    value:
                        '${s.completedSets}/${s.totalSets}',
                    color: Colors.orange,
                    theme: theme,
                  ),
                ],
              ),
            ),

            // Progress bar
            if (s.totalSets > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    24, 12, 24, 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: completedPct,
                    minHeight: 8,
                    backgroundColor: theme
                        .colorScheme.surfaceContainerHighest,
                    color: completedPct >= 1.0
                        ? Colors.green
                        : theme.colorScheme.primary,
                  ),
                ),
              ),

            // ── PRs Section ──
            if (s.prs.isNotEmpty) ...[
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.emoji_events,
                            size: 20,
                            color: Colors.amber.shade700),
                        const SizedBox(width: 8),
                        Text(
                          AppLocalizations.of(context)!
                              .activeWorkoutPersonalRecords,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(
                                  fontWeight:
                                      FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...s.prs.map((pr) => Container(
                          margin: const EdgeInsets.only(
                              bottom: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.amber.withAlpha(20),
                            borderRadius:
                                BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.amber
                                  .withAlpha(60),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.emoji_events,
                                  size: 18,
                                  color:
                                      Colors.amber.shade700),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment
                                          .start,
                                  children: [
                                    Text(
                                      pr.exerciseName,
                                      style: theme
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                              fontWeight:
                                                  FontWeight
                                                      .w600),
                                    ),
                                    Text(
                                      pr.value,
                                      style: theme
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                        color: theme
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '🎉',
                                style: theme.textTheme
                                    .titleMedium,
                              ),
                            ],
                          ),
                        )),
                  ],
                ),
              ),
            ],

            // ── Feeling Rating ──
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 24),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.favorite,
                          size: 18,
                          color: Colors.red.shade300),
                      const SizedBox(width: 8),
                      Text(
                        AppLocalizations.of(context)!
                            .activeWorkoutHowWasWorkout,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(
                                fontWeight:
                                    FontWeight.bold),
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
                        onTap: () =>
                            setState(() => _rating = star),
                        child: Container(
                          margin:
                              const EdgeInsets.symmetric(
                                  horizontal: 4),
                          padding: const EdgeInsets.all(6),
                          child: Icon(
                            isFilled
                                ? Icons.star
                                : Icons.star_outline,
                            color: isFilled
                                ? Colors.amber
                                : theme.colorScheme
                                    .outlineVariant,
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
                      Icon(_feelingIcon,
                          size: 16,
                          color: _feelingColor(theme)),
                      const SizedBox(width: 6),
                      Text(
                        _feelingLabel,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(
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
              padding: const EdgeInsets.symmetric(
                  horizontal: 24),
              child: TextField(
                controller: _commentCtl,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: AppLocalizations.of(context)!
                      .activeWorkoutCommentHint,
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: theme
                      .colorScheme.surfaceContainerHighest
                      .withAlpha(80),
                  prefixIcon: Padding(
                    padding:
                        const EdgeInsets.only(bottom: 24),
                    child: Icon(
                      Icons.edit_note,
                      color: theme
                          .colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),

            // ── Buttons ──
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  24, 0, 24, 24),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () =>
                          Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(
                                vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                          AppLocalizations.of(context)!
                              .commonCancel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: () =>
                          Navigator.pop(context, {
                        'feeling': _rating,
                        'comment': _commentCtl.text,
                      }),
                      style: FilledButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(
                                vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        AppLocalizations.of(context)!
                            .activeWorkoutFinishWorkout,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold),
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
