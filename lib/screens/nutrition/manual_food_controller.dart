import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/nutrition/ai_food_label_draft.dart';
import 'package:workout_notes/models/nutrition/food.dart';
import 'package:workout_notes/models/nutrition/food_lookup.dart';
import 'package:workout_notes/models/nutrition/food_serving.dart';
import 'package:workout_notes/models/nutrition/manual_serving_input.dart';
import 'package:workout_notes/models/nutrition/nutrition_values.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/utils/app_number_format.dart';

/// Text fields of one serving row being edited.
class ManualServingDraft {
  final TextEditingController labelController = TextEditingController();
  final TextEditingController quantityController = TextEditingController(
    text: '1',
  );
  final TextEditingController unitController = TextEditingController();
  final TextEditingController gramsController = TextEditingController();
  final TextEditingController mlController = TextEditingController();

  void dispose() {
    labelController.dispose();
    quantityController.dispose();
    unitController.dispose();
    gramsController.dispose();
    mlController.dispose();
  }
}

/// Form state of the manual food screen: every text field, the estimated flag
/// and the serving rows. It pre-fills from an existing food (edit) or an AI
/// label draft, and turns the fields into repository input on [save].
class ManualFoodController extends ChangeNotifier {
  ManualFoodController({
    required this.repository,
    this.source = FoodSource.manual,
    AiFoodLabelDraft? initial,
    this.existingFood,
  }) {
    _prefill(initial);
  }

  final NutritionRepository repository;
  final String source;
  final FoodWithDetails? existingFood;

  final nameController = TextEditingController();
  final brandController = TextEditingController();
  final barcodeController = TextEditingController();
  final referenceAmountController = TextEditingController(text: '100');
  final referenceUnitController = TextEditingController(text: 'g');
  final caloriesController = TextEditingController();
  final proteinController = TextEditingController();
  final carbsController = TextEditingController();
  final fatController = TextEditingController();
  final saturatedFatController = TextEditingController();
  final monounsaturatedFatController = TextEditingController();
  final polyunsaturatedFatController = TextEditingController();
  final transFatController = TextEditingController();
  final fiberController = TextEditingController();
  final sugarsController = TextEditingController();
  final sodiumController = TextEditingController();
  final potassiumController = TextEditingController();
  final calciumController = TextEditingController();
  final ironController = TextEditingController();
  final magnesiumController = TextEditingController();
  final zincController = TextEditingController();
  final vitaminAController = TextEditingController();
  final vitaminCController = TextEditingController();
  final vitaminDController = TextEditingController();
  final vitaminB12Controller = TextEditingController();

  final List<ManualServingDraft> servings = [];
  bool _isEstimated = false;
  bool _isSaving = false;
  bool _disposed = false;

  bool get isEstimated => _isEstimated;
  bool get isSaving => _isSaving;

  /// The four fat-breakdown fields.
  List<TextEditingController> get fatBreakdownControllers => [
    saturatedFatController,
    monounsaturatedFatController,
    polyunsaturatedFatController,
    transFatController,
  ];

  void setEstimated(bool value) {
    _isEstimated = value;
    notifyListeners();
  }

  void addServing() {
    servings.add(ManualServingDraft());
    notifyListeners();
  }

  void removeServing(int index) {
    servings.removeAt(index).dispose();
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Pre-fill
  // ------------------------------------------------------------------

  void _prefill(AiFoodLabelDraft? initial) {
    final existing = existingFood;
    if (existing != null) {
      nameController.text = existing.food.name;
      if (existing.food.brand != null) {
        brandController.text = existing.food.brand!;
      }
      if (existing.food.barcode != null) {
        barcodeController.text = existing.food.barcode!;
      }
      final variant = existing.variants.isEmpty
          ? null
          : existing.variants.first;
      if (variant != null) {
        referenceAmountController.text = formatAmount(variant.referenceAmount);
        referenceUnitController.text = variant.referenceUnit;
        _fillValues(variant.values);
        _isEstimated = variant.isEstimated;
        for (final serving
            in existing.servings[variant.id] ?? const <FoodServing>[]) {
          servings.add(_servingDraftFromFoodServing(serving));
        }
      }
      return;
    }
    if (initial == null) return;
    nameController.text = initial.name;
    if (initial.brand != null) brandController.text = initial.brand!;
    if (initial.barcode != null) barcodeController.text = initial.barcode!;
    referenceAmountController.text = formatAmount(initial.referenceAmount);
    referenceUnitController.text = initial.referenceUnit;
    _fillValues(initial.values);
    _isEstimated = true;
    for (final serving in initial.servings) {
      servings.add(_servingDraftFrom(serving));
    }
  }

  void _fillValues(NutritionValues values) {
    _fillNumber(caloriesController, values.calories);
    _fillNumber(proteinController, values.proteinG);
    _fillNumber(carbsController, values.carbsG);
    _fillNumber(fatController, values.fatG);
    _fillFatBreakdown(values);
    _fillNumber(fiberController, values.fiberG);
    _fillNumber(sugarsController, values.sugarsG);
    _fillNumber(sodiumController, values.sodiumMg);
    _fillMicronutrients(values);
  }

  void _fillMicronutrients(NutritionValues values) {
    _fillNumber(potassiumController, values.potassiumMg);
    _fillNumber(calciumController, values.calciumMg);
    _fillNumber(ironController, values.ironMg);
    _fillNumber(magnesiumController, values.magnesiumMg);
    _fillNumber(zincController, values.zincMg);
    _fillNumber(vitaminAController, values.vitaminAUg);
    _fillNumber(vitaminCController, values.vitaminCMg);
    _fillNumber(vitaminDController, values.vitaminDUg);
    _fillNumber(vitaminB12Controller, values.vitaminB12Ug);
  }

  void _fillFatBreakdown(NutritionValues values) {
    _fillNumber(saturatedFatController, values.saturatedFatG);
    _fillNumber(monounsaturatedFatController, values.monounsaturatedFatG);
    _fillNumber(polyunsaturatedFatController, values.polyunsaturatedFatG);
    _fillNumber(transFatController, values.transFatG);
  }

  static void _fillNumber(TextEditingController controller, double? value) {
    if (value == null) return;
    controller.text = formatAmount(value);
  }

  static ManualServingDraft _servingDraftFrom(
    AiFoodLabelServingDraft serving,
  ) => _draft(
    label: serving.label,
    quantity: serving.quantity,
    unit: serving.unit,
    grams: serving.gramsEquivalent,
    ml: serving.mlEquivalent,
  );

  static ManualServingDraft _servingDraftFromFoodServing(FoodServing serving) =>
      _draft(
        label: serving.label,
        quantity: serving.quantity,
        unit: serving.unit,
        grams: serving.gramsEquivalent,
        ml: serving.mlEquivalent,
      );

  static ManualServingDraft _draft({
    required String label,
    required double quantity,
    required String unit,
    double? grams,
    double? ml,
  }) {
    final draft = ManualServingDraft();
    draft.labelController.text = label;
    draft.quantityController.text = formatAmount(quantity);
    draft.unitController.text = unit;
    if (grams != null) draft.gramsController.text = formatAmount(grams);
    if (ml != null) draft.mlController.text = formatAmount(ml);
    return draft;
  }

  // ------------------------------------------------------------------
  // Parsing
  // ------------------------------------------------------------------

  /// Parses a decimal typed with `.` or `,`. Empty or unparsable input gives
  /// [fallback]; a negative number gives null.
  static double? parseDouble(String raw, double? fallback) {
    final cleaned = raw.trim().replaceAll(',', '.');
    if (cleaned.isEmpty) return fallback;
    final value = double.tryParse(cleaned);
    if (value == null || value.isNaN || value.isInfinite) return fallback;
    if (value < 0) return null;
    return value;
  }

  static String? nullableText(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String formatAmount(double value) {
    if (value == value.roundToDouble()) return AppNumberFormat.decimal(value, 0);
    return AppNumberFormat.decimal(value, 2);
  }

  static bool hasAnyText(Iterable<TextEditingController> controllers) =>
      controllers.any((controller) => controller.text.trim().isNotEmpty);

  /// Whether the fat sub-types add up to more than the total fat (with a
  /// small tolerance). False when no total fat was entered.
  bool get fatBreakdownExceedsTotal {
    final totalFat = parseDouble(fatController.text, null);
    if (totalFat == null) return false;
    final breakdown = fatBreakdownControllers.fold<double>(
      0,
      (sum, controller) => sum + (parseDouble(controller.text, null) ?? 0),
    );
    return breakdown > totalFat + 0.1;
  }

  // ------------------------------------------------------------------
  // Saving
  // ------------------------------------------------------------------

  /// Persists the food (creating it, or updating [existingFood]) and returns
  /// it. Busy while it runs; rethrows repository failures.
  Future<Food> save() async {
    _isSaving = true;
    notifyListeners();
    try {
      final servingInputs = servings
          .where((s) => s.labelController.text.trim().isNotEmpty)
          .map(
            (s) => ManualServingInput(
              label: s.labelController.text.trim(),
              quantity: parseDouble(s.quantityController.text, 1) ?? 1,
              unit: s.unitController.text.trim().isEmpty
                  ? 'g'
                  : s.unitController.text.trim(),
              gramsEquivalent: parseDouble(s.gramsController.text, null),
              mlEquivalent: parseDouble(s.mlController.text, null),
            ),
          )
          .toList();
      final name = nameController.text.trim();
      final brand = nullableText(brandController.text);
      final barcode = nullableText(barcodeController.text);
      final referenceAmount = parseDouble(referenceAmountController.text, 100)!;
      final referenceUnit = referenceUnitController.text.trim().isEmpty
          ? 'g'
          : referenceUnitController.text.trim();
      final referenceValues = _referenceValues();
      final existing = existingFood;
      return existing == null
          ? await repository.createManualFood(
              name: name,
              brand: brand,
              barcode: barcode,
              source: source,
              referenceAmount: referenceAmount,
              referenceUnit: referenceUnit,
              referenceValues: referenceValues,
              isEstimated: _isEstimated,
              servings: servingInputs,
            )
          : await repository.updateManualFood(
              foodId: existing.food.id,
              name: name,
              brand: brand,
              barcode: barcode,
              referenceAmount: referenceAmount,
              referenceUnit: referenceUnit,
              referenceValues: referenceValues,
              isEstimated: _isEstimated,
              servings: servingInputs,
            );
    } finally {
      if (!_disposed) {
        _isSaving = false;
        notifyListeners();
      }
    }
  }

  NutritionValues _referenceValues() {
    double? read(TextEditingController controller) =>
        parseDouble(controller.text, null);
    return NutritionValues(
      // Empty fields stay null ("unknown"), never 0: a blank
      // macro is different from a measured zero and must keep
      // flagging the food as incomplete in the UI.
      calories: read(caloriesController),
      proteinG: read(proteinController),
      carbsG: read(carbsController),
      fatG: read(fatController),
      saturatedFatG: read(saturatedFatController),
      monounsaturatedFatG: read(monounsaturatedFatController),
      polyunsaturatedFatG: read(polyunsaturatedFatController),
      transFatG: read(transFatController),
      fiberG: read(fiberController),
      sugarsG: read(sugarsController),
      sodiumMg: read(sodiumController),
      potassiumMg: read(potassiumController),
      calciumMg: read(calciumController),
      ironMg: read(ironController),
      magnesiumMg: read(magnesiumController),
      zincMg: read(zincController),
      vitaminAUg: read(vitaminAController),
      vitaminCMg: read(vitaminCController),
      vitaminDUg: read(vitaminDController),
      vitaminB12Ug: read(vitaminB12Controller),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    for (final c in [
      nameController,
      brandController,
      barcodeController,
      referenceAmountController,
      referenceUnitController,
      caloriesController,
      proteinController,
      carbsController,
      fatController,
      saturatedFatController,
      monounsaturatedFatController,
      polyunsaturatedFatController,
      transFatController,
      fiberController,
      sugarsController,
      sodiumController,
      potassiumController,
      calciumController,
      ironController,
      magnesiumController,
      zincController,
      vitaminAController,
      vitaminCController,
      vitaminDController,
      vitaminB12Controller,
    ]) {
      c.dispose();
    }
    for (final s in servings) {
      s.dispose();
    }
    super.dispose();
  }
}

/// Field validators of the manual food form, localized through [loc].
class ManualFoodValidators {
  ManualFoodValidators(this.loc, this.form);

  final AppLocalizations loc;
  final ManualFoodController form;

  String? requiredText(String? value) {
    if (value == null || value.trim().isEmpty) {
      return loc.nutritionFieldRequired;
    }
    return null;
  }

  String? number(String? value, {bool allowZero = true}) {
    if (value == null || value.trim().isEmpty) return null;
    final cleaned = value.trim().replaceAll(',', '.');
    final parsed = double.tryParse(cleaned);
    if (parsed == null || parsed.isNaN || parsed.isInfinite) {
      return loc.nutritionInvalidNumber;
    }
    if (!allowZero && parsed <= 0) {
      return loc.nutritionInvalidQuantity;
    }
    if (parsed < 0) {
      return loc.nutritionInvalidNumber;
    }
    return null;
  }

  /// Number check that also flags fat sub-types adding up to more than the
  /// total fat.
  String? fatSubtype(String? value) {
    final numericError = number(value);
    if (numericError != null) return numericError;
    if (form.fatBreakdownExceedsTotal) {
      return loc.nutritionFatBreakdownExceedsTotal;
    }
    return null;
  }
}
