import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/screens/nutrition/saved_meal_editor_controller.dart';

void main() {
  SavedMealEditorController build({
    String? name,
    double portions = 1,
    List<SavedMealItemDraft> items = const [],
  }) {
    final controller = SavedMealEditorController(
      repository: NutritionRepository(),
      initialName: name,
      initialPortions: portions,
      initialItems: items,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  const oats = SavedMealItemDraft(
    foodId: 'food-1',
    foodVariantId: 'variant-1',
    foodNameSnapshot: 'Oats',
    brandSnapshot: 'Acme',
    quantity: 40,
    unit: 'g',
    servingLabel: 'scoop',
    servingGramsEquivalent: 40,
  );

  test('starts from the initial name, portions and ingredients', () {
    final controller = build(name: 'Breakfast', portions: 2.5, items: [oats]);

    expect(controller.nameController.text, 'Breakfast');
    expect(controller.portionsController.text, '2.5');
    expect(controller.currentPortions, 2.5);
    expect(controller.ingredients, hasLength(1));
    expect(controller.ingredients.single.name, 'Oats');
    expect(controller.isSaving, isFalse);
    expect(controller.totals, isNull);
  });

  test('invalid or non positive portions fall back to one', () {
    final controller = build();
    controller.portionsController.text = 'abc';
    expect(controller.currentPortions, 1);
    controller.portionsController.text = '0';
    expect(controller.currentPortions, 1);
    controller.portionsController.text = '3,5';
    expect(controller.currentPortions, 3.5);
  });

  test('changePortions stays between 1 and 999', () {
    final controller = build();
    controller.changePortions(-1);
    expect(controller.portionsController.text, '1');
    controller.changePortions(1);
    expect(controller.portionsController.text, '2');
    controller.portionsController.text = '999';
    controller.changePortions(1);
    expect(controller.portionsController.text, '999');
  });

  test('an ingredient round trips through its draft', () {
    final ingredient = SavedMealIngredient.fromDraft(oats);
    final draft = ingredient.toDraft();
    expect(draft.foodId, oats.foodId);
    expect(draft.foodVariantId, oats.foodVariantId);
    expect(draft.foodNameSnapshot, oats.foodNameSnapshot);
    expect(draft.brandSnapshot, oats.brandSnapshot);
    expect(draft.quantity, oats.quantity);
    expect(draft.unit, oats.unit);
    expect(draft.servingLabel, oats.servingLabel);
    expect(draft.servingGramsEquivalent, oats.servingGramsEquivalent);
  });

  test('quantities drop decimals only when whole', () {
    expect(SavedMealEditorController.formatQuantity(40), '40');
    expect(SavedMealEditorController.formatQuantity(1.5), '1.50');
  });
}
