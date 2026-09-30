import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/screens/nutrition/manual_food_controller.dart';
import 'package:workout_notes/widgets/nutrition/manual_food/manual_food_form_widgets.dart';
import 'package:workout_notes/widgets/ui/form_section_card.dart';

/// All sections of the manual food form: basic info, reference macros, the
/// collapsible fat / other nutrients / micronutrient groups and the servings.
class ManualFoodFormSections extends StatelessWidget {
  const ManualFoodFormSections({
    super.key,
    required this.form,
    required this.validators,
  });

  final ManualFoodController form;
  final ManualFoodValidators validators;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormSectionCard(
          icon: Icons.fastfood_outlined,
          title: loc.nutritionManualSectionInfo,
          children: [
            FormFieldLabel(text: loc.nutritionManualName),
            TextFormField(
              controller: form.nameController,
              textCapitalization: TextCapitalization.words,
              decoration: _fieldDecoration(
                theme,
                hint: loc.nutritionManualNameHint,
              ),
              validator: validators.requiredText,
            ),
            const SizedBox(height: 16),
            FormFieldLabel(text: loc.nutritionManualBrand),
            TextFormField(
              controller: form.brandController,
              textCapitalization: TextCapitalization.words,
              decoration: _fieldDecoration(theme),
            ),
            const SizedBox(height: 16),
            FormFieldLabel(text: loc.nutritionManualBarcode),
            TextFormField(
              controller: form.barcodeController,
              keyboardType: TextInputType.number,
              decoration: _fieldDecoration(theme),
            ),
          ],
        ),
        const SizedBox(height: 14),
        FormSectionCard(
          icon: Icons.bar_chart_rounded,
          title: loc.nutritionManualSectionMacros,
          children: [
            Text(
              loc.nutritionManualReferenceHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: NutritionNumberField(
                    controller: form.referenceAmountController,
                    label: loc.nutritionManualReference,
                    validator: (v) => validators.number(v, allowZero: false),
                    allowDecimal: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: NutritionNumberField(
                    controller: form.referenceUnitController,
                    label: loc.nutritionUnit,
                    validator: validators.requiredText,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            NutritionMacroFieldRow(
              children: [
                NutritionNumberField(
                  controller: form.caloriesController,
                  label: loc.nutritionManualCalories,
                  validator: validators.number,
                  allowDecimal: true,
                ),
                NutritionNumberField(
                  controller: form.proteinController,
                  label: loc.nutritionManualProtein,
                  validator: validators.number,
                  allowDecimal: true,
                ),
              ],
            ),
            const SizedBox(height: 12),
            NutritionMacroFieldRow(
              children: [
                NutritionNumberField(
                  controller: form.carbsController,
                  label: loc.nutritionManualCarbs,
                  validator: validators.number,
                  allowDecimal: true,
                ),
                NutritionNumberField(
                  controller: form.fatController,
                  label: loc.nutritionManualFat,
                  validator: validators.number,
                  allowDecimal: true,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withAlpha(60),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Material(
                type: MaterialType.transparency,
                child: SwitchListTile(
                  value: form.isEstimated,
                  onChanged: (v) => form.setEstimated(v),
                  title: Text(loc.nutritionManualIsEstimated),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        NutritionExpandableSection(
          icon: Icons.opacity_outlined,
          title: loc.nutritionFatBreakdownTitle,
          subtitle: loc.nutritionFatBreakdownSubtitle,
          initiallyExpanded: ManualFoodController.hasAnyText([
            form.saturatedFatController,
            form.monounsaturatedFatController,
            form.polyunsaturatedFatController,
            form.transFatController,
          ]),
          children: [
            NutritionMacroFieldRow(
              children: [
                NutritionNumberField(
                  controller: form.saturatedFatController,
                  label: loc.nutritionFatSaturated,
                  validator: validators.number,
                  allowDecimal: true,
                  optional: true,
                ),
                NutritionNumberField(
                  controller: form.monounsaturatedFatController,
                  label: loc.nutritionFatMonounsaturated,
                  validator: validators.number,
                  allowDecimal: true,
                  optional: true,
                ),
              ],
            ),
            const SizedBox(height: 12),
            NutritionMacroFieldRow(
              children: [
                NutritionNumberField(
                  controller: form.polyunsaturatedFatController,
                  label: loc.nutritionFatPolyunsaturated,
                  validator: validators.number,
                  allowDecimal: true,
                  optional: true,
                ),
                NutritionNumberField(
                  controller: form.transFatController,
                  label: loc.nutritionFatTrans,
                  validator: validators.fatSubtype,
                  allowDecimal: true,
                  optional: true,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        NutritionExpandableSection(
          icon: Icons.tune_rounded,
          title: loc.nutritionOtherNutrientsTitle,
          subtitle: loc.nutritionOtherNutrientsSubtitle,
          initiallyExpanded: ManualFoodController.hasAnyText([
            form.fiberController,
            form.sugarsController,
            form.sodiumController,
          ]),
          children: [
            NutritionMacroFieldRow(
              children: [
                NutritionNumberField(
                  controller: form.fiberController,
                  label: loc.nutritionManualFiber,
                  validator: validators.number,
                  allowDecimal: true,
                  optional: true,
                ),
                NutritionNumberField(
                  controller: form.sugarsController,
                  label: loc.nutritionManualSugars,
                  validator: validators.number,
                  allowDecimal: true,
                  optional: true,
                ),
              ],
            ),
            const SizedBox(height: 12),
            NutritionNumberField(
              controller: form.sodiumController,
              label: loc.nutritionManualSodium,
              validator: validators.number,
              allowDecimal: true,
              optional: true,
            ),
          ],
        ),
        const SizedBox(height: 14),
        NutritionExpandableSection(
          icon: Icons.eco_outlined,
          title: loc.nutritionManualSectionMicronutrients,
          subtitle: loc.nutritionManualMicronutrientsHint,
          initiallyExpanded: ManualFoodController.hasAnyText([
            form.potassiumController,
            form.calciumController,
            form.ironController,
            form.magnesiumController,
            form.zincController,
            form.vitaminAController,
            form.vitaminCController,
            form.vitaminDController,
            form.vitaminB12Controller,
          ]),
          children: [
            for (final row
                in <
                  (TextEditingController, String, TextEditingController, String)
                >[
                  (
                    form.potassiumController,
                    loc.nutritionProgressPotassium,
                    form.calciumController,
                    loc.nutritionProgressCalcium,
                  ),
                  (
                    form.ironController,
                    loc.nutritionProgressIron,
                    form.magnesiumController,
                    loc.nutritionProgressMagnesium,
                  ),
                  (
                    form.zincController,
                    loc.nutritionProgressZinc,
                    form.vitaminAController,
                    loc.nutritionProgressVitaminA,
                  ),
                  (
                    form.vitaminCController,
                    loc.nutritionProgressVitaminC,
                    form.vitaminDController,
                    loc.nutritionProgressVitaminD,
                  ),
                ]) ...[
              NutritionMacroFieldRow(
                children: [
                  _micronutrientField(validators, row.$1, row.$2),
                  _micronutrientField(validators, row.$3, row.$4),
                ],
              ),
              const SizedBox(height: 12),
            ],
            _micronutrientField(
              validators,
              form.vitaminB12Controller,
              loc.nutritionProgressVitaminB12,
            ),
          ],
        ),
        const SizedBox(height: 14),
        NutritionExpandableSection(
          icon: Icons.restaurant_menu_rounded,
          title: loc.nutritionServingsAvailable,
          subtitle: loc.nutritionManualServingsHint,
          initiallyExpanded: form.servings.isNotEmpty,
          children: [
            if (form.servings.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 20,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withAlpha(
                    50,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withAlpha(80),
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.lunch_dining_outlined,
                      size: 28,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      loc.nutritionManualServingsHint,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              )
            else
              Column(
                children: List.generate(form.servings.length, (i) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: ManualServingCard(
                      index: i,
                      draft: form.servings[i],
                      onRemove: () => form.removeServing(i),
                    ),
                  );
                }),
              ),
            OutlinedButton.icon(
              onPressed: form.addServing,
              icon: const Icon(Icons.add, size: 18),
              label: Text(loc.nutritionManualAddServing),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
              ),
            ),
          ],
        ),
      ],
    );
  }

  static InputDecoration _fieldDecoration(ThemeData theme, {String? hint}) {
    return InputDecoration(
      hintText: hint,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      filled: true,
      fillColor: theme.colorScheme.surfaceContainerHighest.withAlpha(60),
    );
  }

  Widget _micronutrientField(
    ManualFoodValidators validators,
    TextEditingController controller,
    String label,
  ) {
    final usesMicrograms =
        identical(controller, form.vitaminAController) ||
        identical(controller, form.vitaminDController) ||
        identical(controller, form.vitaminB12Controller);
    return NutritionNumberField(
      controller: controller,
      label: '$label (${usesMicrograms ? 'µg' : 'mg'})',
      validator: validators.number,
      allowDecimal: true,
      optional: true,
    );
  }
}
