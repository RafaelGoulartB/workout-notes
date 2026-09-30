import 'package:workout_notes/screens/nutrition/food_search_controller.dart';
import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';

class FoodSearchFilters extends StatelessWidget {
  final FoodSearchFilter active;
  final ValueChanged<FoodSearchFilter> onSelected;

  const FoodSearchFilters({
    super.key,
    required this.active,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final labels = <FoodSearchFilter, String>{
      FoodSearchFilter.all: loc.nutritionSearchAll,
      FoodSearchFilter.meals: loc.nutritionSearchMyMeals,
      FoodSearchFilter.favorites: loc.nutritionSearchFavorites,
      FoodSearchFilter.myFoods: loc.nutritionSearchMyFoods,
    };
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final entry in labels.entries)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: ChoiceChip(
                label: Text(entry.value),
                selected: active == entry.key,
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => onSelected(entry.key),
              ),
            ),
        ],
      ),
    );
  }
}

class FoodSearchActions extends StatelessWidget {
  final VoidCallback onPhoto;
  final VoidCallback onBarcode;
  final VoidCallback? onManual;

  const FoodSearchActions({
    super.key,
    required this.onPhoto,
    required this.onBarcode,
    required this.onManual,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Container(
      height: 92,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(vertical: 9),
      color: theme.colorScheme.primaryContainer.withAlpha(42),
      child: Row(
        children: [
          Expanded(
            child: SearchActionCard(
              icon: Icons.center_focus_strong_rounded,
              label: loc.nutritionScanMeal,
              onTap: onPhoto,
            ),
          ),
          Expanded(
            child: SearchActionCard(
              icon: Icons.qr_code_scanner_rounded,
              label: loc.nutritionScanBarcode,
              onTap: onBarcode,
            ),
          ),
          if (onManual != null)
            Expanded(
              child: SearchActionCard(
                icon: Icons.edit_note_rounded,
                label: loc.nutritionAddManually,
                onTap: onManual!,
              ),
            ),
        ],
      ),
    );
  }
}

class SearchActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const SearchActionCard({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Material(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 25, color: theme.colorScheme.primary),
              const SizedBox(height: 5),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                    height: 1.1,
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
