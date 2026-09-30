import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/screens/nutrition/saved_meal_editor_controller.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

class SavedMealDetailsCard extends StatelessWidget {
  final TextEditingController nameController;
  final TextEditingController portionsController;
  final VoidCallback? onDecreasePortions;
  final VoidCallback? onIncreasePortions;

  const SavedMealDetailsCard({
    super.key,
    required this.nameController,
    required this.portionsController,
    required this.onDecreasePortions,
    required this.onIncreasePortions,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final fieldColor = theme.colorScheme.surfaceContainerHighest.withAlpha(75);

    return AppSectionCard(
      color: theme.colorScheme.surfaceContainerLow,
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SavedMealSectionIcon(
                icon: Icons.restaurant_menu_rounded,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Text(
                loc.nutritionSavedMealDetails,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: nameController,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: loc.nutritionSavedMealName,
              prefixIcon: const Icon(Icons.edit_outlined, size: 20),
              filled: true,
              fillColor: fieldColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: theme.colorScheme.outlineVariant.withAlpha(65),
                ),
              ),
            ),
            validator: (value) => (value == null || value.trim().isEmpty)
                ? loc.nutritionFieldRequired
                : null,
          ),
          const SizedBox(height: 16),
          Text(
            loc.nutritionSavedMealPortions,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 196,
              child: Row(
                children: [
                  SavedMealPortionButton(
                    icon: Icons.remove_rounded,
                    tooltip: loc.nutritionSavedMealDecreasePortions,
                    onPressed: onDecreasePortions,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: portionsController,
                      textAlign: TextAlign.center,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: fieldColor,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: theme.colorScheme.outlineVariant.withAlpha(
                              65,
                            ),
                          ),
                        ),
                      ),
                      validator: (value) {
                        final parsed = double.tryParse(
                          (value ?? '').trim().replaceAll(',', '.'),
                        );
                        if (parsed == null || parsed <= 0) {
                          return loc.nutritionInvalidQuantity;
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  SavedMealPortionButton(
                    icon: Icons.add_rounded,
                    tooltip: loc.nutritionSavedMealIncreasePortions,
                    onPressed: onIncreasePortions,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SavedMealPortionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const SavedMealPortionButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        minimumSize: const Size.square(44),
        maximumSize: const Size.square(44),
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class SavedMealEmptyIngredientsCard extends StatelessWidget {
  final VoidCallback? onAdd;

  const SavedMealEmptyIngredientsCard({super.key, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withAlpha(75),
        ),
      ),
      child: Column(
        children: [
          SavedMealSectionIcon(
            icon: Icons.add_shopping_cart_rounded,
            color: theme.colorScheme.primary,
            size: 44,
          ),
          const SizedBox(height: 12),
          Text(
            loc.nutritionSavedMealEmptyIngredients,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
            label: Text(loc.nutritionAddItem),
          ),
        ],
      ),
    );
  }
}

class SavedMealIngredientCard extends StatelessWidget {
  final SavedMealIngredient ingredient;
  final bool enabled;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  const SavedMealIngredientCard({
    super.key,
    required this.ingredient,
    required this.enabled,
    required this.onEdit,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final brand = ingredient.brand?.trim();
    final quantity = SavedMealEditorController.formatQuantity(
      ingredient.quantity,
    );
    final unitSuffix = ingredient.unit.trim().isEmpty
        ? ''
        : ' ${ingredient.unit}';
    final subtitle = <String>[
      '$quantity$unitSuffix',
      if (brand != null && brand.isNotEmpty) brand,
    ].join(' · ');
    final calories = ingredient.calories;

    return AppSectionCard(
      key: ValueKey(ingredient.id),
      color: theme.colorScheme.surfaceContainerLow,
      radius: 14,
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: enabled ? onEdit : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      ingredient.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (calories != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    loc.nutritionConsumedKcal(
                      calories.toStringAsFixed(calories < 10 ? 1 : 0),
                    ),
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              PopupMenuButton<SavedMealIngredientAction>(
                enabled: enabled,
                tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
                onSelected: (action) {
                  switch (action) {
                    case SavedMealIngredientAction.edit:
                      onEdit();
                    case SavedMealIngredientAction.remove:
                      onRemove();
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: SavedMealIngredientAction.edit,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.edit_outlined),
                      title: Text(loc.nutritionEditItem),
                    ),
                  ),
                  PopupMenuItem(
                    value: SavedMealIngredientAction.remove,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.delete_outline_rounded,
                        color: theme.colorScheme.error,
                      ),
                      title: Text(
                        loc.nutritionDeleteItem,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum SavedMealIngredientAction { edit, remove }

class SavedMealSectionIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;

  const SavedMealSectionIcon({
    super.key,
    required this.icon,
    required this.color,
    this.size = 34,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(size * .32),
      ),
      child: Icon(icon, size: size * .55, color: color),
    );
  }
}
