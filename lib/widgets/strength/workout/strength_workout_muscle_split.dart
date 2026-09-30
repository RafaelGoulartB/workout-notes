import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/l10n/exercise_locale_helper.dart';
import 'package:workout_notes/models/workout_stats.dart';
import 'package:workout_notes/utils/strength_workout_format.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Share of the workout volume (or sets, for bodyweight-only work) per muscle
/// group as coloured bars.
class StrengthWorkoutMuscleSplit extends StatelessWidget {
  final WorkoutStats stats;

  const StrengthWorkoutMuscleSplit({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final byVolume = stats.categories.any((c) => c.volume > 0);
    double amount(CategoryWorkoutStats c) =>
        byVolume ? c.volume : c.completedSets.toDouble();
    final total = stats.categories.fold<double>(0, (s, c) => s + amount(c));
    final maxAmount = stats.categories.fold<double>(
      0,
      (m, c) => amount(c) > m ? amount(c) : m,
    );

    return AppSectionCard(
      child: Column(
        children: [
          for (var i = 0; i < stats.categories.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _row(
              theme,
              colors,
              loc,
              stats.categories[i],
              byVolume,
              amount,
              total,
              maxAmount,
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(
    ThemeData theme,
    ColorScheme colors,
    AppLocalizations loc,
    CategoryWorkoutStats category,
    bool byVolume,
    double Function(CategoryWorkoutStats) amount,
    double total,
    double maxAmount,
  ) {
    final name = ExerciseLocaleHelper.categoryName(loc, {
      'category_id': category.categoryId,
      'category_name': category.categoryName,
    });
    final share = total > 0 ? amount(category) / total : 0.0;
    final width = maxAmount > 0 ? amount(category) / maxAmount : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: category.categoryColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '${byVolume ? StrengthWorkoutFormat.volume(category.volume) : loc.strengthHistorySets(category.completedSets)}'
              ' · ${(share * 100).round()}%',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.onSurfaceVariant,
                fontFeatures: AppUi.tabular,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(
            children: [
              Container(height: 8, color: colors.surfaceContainerHighest),
              FractionallySizedBox(
                widthFactor: width.clamp(0.0, 1.0),
                child: Container(height: 8, color: category.categoryColor),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
