import 'package:workout_notes/widgets/nutrition/nutrition_day_ui.dart';
import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/nutrition/nutrition_values.dart';
import 'package:workout_notes/widgets/nutrition/saved_meal/saved_meal_form_widgets.dart';

/// Card that summarises the live nutrition totals for the saved meal
/// being edited. Mirrors the visual language of the home screen
/// `_NutritionMacroStat` (same colors, same label hierarchy) so the two
/// screens feel like part of the same product.
class SavedMealTotalsCard extends StatelessWidget {
  final NutritionValues? totals;
  final double portions;
  final bool isComputing;
  final bool hasIngredients;
  final int ingredientCount;

  const SavedMealTotalsCard({
    super.key,
    required this.totals,
    required this.portions,
    required this.isComputing,
    required this.hasIngredients,
    required this.ingredientCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final showTotals = totals != null;
    final showPerPortion = portions > 1;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(75)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SavedMealSectionIcon(
                  icon: Icons.local_fire_department_rounded,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    loc.nutritionSavedMealTotalsTitle,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (isComputing) ...[
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    loc.nutritionSavedMealFoodsCount(ingredientCount),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (!showTotals)
              Text(
                hasIngredients
                    ? loc.nutritionSavedMealTotalsPartial
                    : loc.nutritionSavedMealTotalsEmpty,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else ...[
              SavedMealCaloriesRow(calories: totals!.calories ?? 0),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: SavedMealMacroColumn(
                      label: loc.nutritionProgressProtein,
                      grams: totals!.proteinG ?? 0,
                      color: NutritionMacroColors.protein,
                    ),
                  ),
                  SavedMealMacroDivider(theme: theme),
                  Expanded(
                    child: SavedMealMacroColumn(
                      label: loc.nutritionProgressCarbs,
                      grams: totals!.carbsG ?? 0,
                      color: NutritionMacroColors.carbs,
                    ),
                  ),
                  SavedMealMacroDivider(theme: theme),
                  Expanded(
                    child: SavedMealMacroColumn(
                      label: loc.nutritionProgressFat,
                      grams: totals!.fatG ?? 0,
                      color: NutritionMacroColors.fat,
                    ),
                  ),
                ],
              ),
              if (showPerPortion) ...[
                const SizedBox(height: 14),
                Container(
                  height: 1,
                  color: theme.colorScheme.outlineVariant.withAlpha(60),
                ),
                const SizedBox(height: 10),
                SavedMealPerPortionRow(
                  totals: totals!,
                  portions: portions,
                  label: loc.nutritionSavedMealTotalsPerPortion,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class SavedMealCaloriesRow extends StatelessWidget {
  final double calories;

  const SavedMealCaloriesRow({super.key, required this.calories});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          _formatKcal(calories),
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            height: 1.0,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          'kcal',
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  static String _formatKcal(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(1);
  }
}

class SavedMealMacroColumn extends StatelessWidget {
  final String label;
  final double grams;
  final Color color;

  const SavedMealMacroColumn({
    super.key,
    required this.label,
    required this.grams,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              _formatGrams(grams),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.0,
              ),
            ),
            const SizedBox(width: 2),
            Text(
              'g',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: grams > 0 ? 1.0 : 0.0,
            minHeight: 3,
            backgroundColor: color.withAlpha(35),
            color: color,
          ),
        ),
      ],
    );
  }

  static String _formatGrams(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(1);
  }
}

class SavedMealMacroDivider extends StatelessWidget {
  final ThemeData theme;
  const SavedMealMacroDivider({super.key, required this.theme});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 36,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: theme.colorScheme.outlineVariant.withAlpha(70),
    );
  }
}

class SavedMealPerPortionRow extends StatelessWidget {
  final NutritionValues totals;
  final double portions;
  final String label;

  const SavedMealPerPortionRow({
    super.key,
    required this.totals,
    required this.portions,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parts = <String>[];
    final kcal = (totals.calories ?? 0) / portions;
    parts.add('${_formatGrams(kcal)} kcal');
    final protein = (totals.proteinG ?? 0) / portions;
    final carbs = (totals.carbsG ?? 0) / portions;
    final fat = (totals.fatG ?? 0) / portions;
    if (protein > 0) parts.add('P ${_formatGrams(protein)} g');
    if (carbs > 0) parts.add('C ${_formatGrams(carbs)} g');
    if (fat > 0) parts.add('G ${_formatGrams(fat)} g');
    return RichText(
      text: TextSpan(
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          TextSpan(text: parts.join(' · ')),
        ],
      ),
    );
  }

  static String _formatGrams(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(1);
  }
}
