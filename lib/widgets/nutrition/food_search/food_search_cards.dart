import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/nutrition/food_search_result.dart';
import 'package:workout_notes/models/nutrition/meal_log.dart';
import 'package:workout_notes/models/nutrition/saved_meal.dart';
import 'package:workout_notes/utils/app_number_format.dart';

class FoodCard extends StatelessWidget {
  final FoodSearchResult result;
  final VoidCallback onSelected;
  final VoidCallback? onToggleFavorite;

  const FoodCard({
    super.key,
    required this.result,
    required this.onSelected,
    this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final variant = result.primaryVariant;
    final details = <String>[
      if (variant?.values.calories != null)
        '${AppNumberFormat.decimal(variant!.values.calories!, 0)} kcal',
      if (result.food.brand != null && result.food.brand!.isNotEmpty)
        result.food.brand!,
      if (variant != null)
        loc.nutritionPer100g(
          AppNumberFormat.decimal(variant.referenceAmount, 0),
          variant.referenceUnit,
        ),
    ].join(' · ');

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onSelected,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.food.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (details.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        details,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              if (result.food.isFavorite != null)
                IconButton(
                  tooltip: result.food.isFavorite!
                      ? loc.nutritionSearchUnfavorite
                      : loc.nutritionSearchFavorite,
                  onPressed: onToggleFavorite,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    result.food.isFavorite!
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    size: 18,
                    color: result.food.isFavorite!
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withAlpha(65),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.add_rounded,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A saved meal template shown under the "Meals" filter. Tapping the
/// card logs the whole template into the target day's meal section.
class SavedMealCard extends StatelessWidget {
  final SavedMealWithItems meal;
  final bool isLogging;
  final VoidCallback onSelected;

  const SavedMealCard({
    super.key,
    required this.meal,
    required this.isLogging,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final totals = meal.totals;
    final subtitle = <String>[
      if (meal.meal.mealType != null) _mealTypeLabel(loc, meal.meal.mealType!),
      if (meal.meal.portions != 1)
        loc.nutritionSavedMealPortionsLabel(_format(meal.meal.portions)),
      if (totals?.calories != null)
        loc.nutritionConsumedKcal(_format(totals!.calories!)),
    ].join(' · ');
    final macros = <String>[
      if (totals?.proteinG != null) 'P ${_format(totals!.proteinG!)} g',
      if (totals?.carbsG != null) 'C ${_format(totals!.carbsG!)} g',
      if (totals?.fatG != null) 'G ${_format(totals!.fatG!)} g',
    ].join(' · ');

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: isLogging ? null : onSelected,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withAlpha(90),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.restaurant_menu,
                  color: theme.colorScheme.onPrimaryContainer,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meal.meal.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (macros.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        macros,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              if (isLogging)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withAlpha(65),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.add_rounded,
                    color: theme.colorScheme.primary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _mealTypeLabel(AppLocalizations loc, String type) {
    switch (type) {
      case MealType.breakfast:
        return loc.nutritionMealBreakfast;
      case MealType.lunch:
        return loc.nutritionMealLunch;
      case MealType.dinner:
        return loc.nutritionMealDinner;
      case MealType.snacks:
        return loc.nutritionMealSnacks;
    }
    return type;
  }

  static String _format(double value) {
    if (value == value.roundToDouble()) return AppNumberFormat.decimal(value, 0);
    return AppNumberFormat.decimal(value, 1);
  }
}
