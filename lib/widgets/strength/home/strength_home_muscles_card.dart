import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/strength_workout_summary.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';
import 'package:workout_notes/widgets/strength/home/strength_home_format.dart';

/// Working sets per muscle group this week as horizontal bars in the group's
/// colour, with a shaded reference band (10 to 20 sets a week is the usual
/// range to grow a muscle) so under and over-trained groups stand out.
class StrengthMusclesCard extends StatelessWidget {
  final List<StrengthMuscleLoad> muscles;
  final VoidCallback? onTap;
  final int rangeMin;
  final int rangeMax;
  final int maxRows;

  const StrengthMusclesCard({
    super.key,
    required this.muscles,
    this.onTap,
    this.rangeMin = 10,
    this.rangeMax = 20,
    this.maxRows = 8,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final rows = muscles.where((m) => m.sets > 0).take(maxRows).toList();

    if (rows.isEmpty) {
      return RunSectionCard(
        onTap: onTap,
        child: Text(
          loc.strengthHomeMusclesEmpty,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      );
    }

    final maxSets = rows.map((m) => m.sets).reduce((a, b) => a > b ? a : b);
    final scale = (maxSets > rangeMax ? maxSets : rangeMax) * 1.1;

    return RunSectionCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final muscle in rows) ...[
            _MuscleRow(
              muscle: muscle,
              scale: scale,
              rangeMin: rangeMin,
              rangeMax: rangeMax,
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Container(
                width: 14,
                height: 8,
                decoration: BoxDecoration(
                  color: colors.onSurface.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  loc.strengthHomeMusclesRange('$rangeMin–$rangeMax'),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MuscleRow extends StatelessWidget {
  final StrengthMuscleLoad muscle;
  final double scale;
  final int rangeMin;
  final int rangeMax;

  const _MuscleRow({
    required this.muscle,
    required this.scale,
    required this.rangeMin,
    required this.rangeMax,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final color = Color(muscle.category.color);

    return Row(
      children: [
        SizedBox(
          width: 82,
          child: Text(
            StrengthHomeFormat.categoryName(loc, muscle.category),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              double at(num sets) => (sets / scale).clamp(0.0, 1.0) * width;
              return SizedBox(
                height: 14,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerHighest.withValues(
                            alpha: 0.5,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    Positioned(
                      left: at(rangeMin),
                      width: at(rangeMax) - at(rangeMin),
                      top: 0,
                      bottom: 0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.onSurface.withValues(alpha: 0.14),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      width: at(muscle.sets).clamp(4.0, width),
                      top: 2,
                      bottom: 2,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        SizedBox(
          width: 30,
          child: Text(
            '${muscle.sets}',
            textAlign: TextAlign.end,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w800,
              fontFeatures: RunUi.tabular,
            ),
          ),
        ),
      ],
    );
  }
}
