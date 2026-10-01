import 'package:workout_notes/models/nutrition/nutrition_values.dart';
import 'package:workout_notes/utils/ai_json.dart';

/// One serving extracted from a nutrition label photo or proposed by the AI.
class AiFoodLabelServingDraft {
  final String label;
  final double quantity;
  final String unit;
  final double? gramsEquivalent;
  final double? mlEquivalent;

  const AiFoodLabelServingDraft({
    required this.label,
    this.quantity = 1,
    required this.unit,
    this.gramsEquivalent,
    this.mlEquivalent,
  });

  /// Null when the entry is empty or unusable: no label and no unit, or a
  /// quantity that is present but zero.
  static AiFoodLabelServingDraft? tryParse(Map<String, dynamic> json) {
    final label = AiJson.text(json['label']) ?? '';
    final unit = AiJson.text(json['unit']) ?? '';
    if (label.isEmpty && unit.isEmpty) return null;
    final rawQuantity = json['quantity'];
    final quantity = AiJson.number(rawQuantity);
    // A missing quantity means one serving; a zero or garbage quantity means
    // the entry is not a real serving.
    if (AiJson.text(rawQuantity) != null || rawQuantity is num) {
      if (quantity == null || quantity <= 0) return null;
    }
    return AiFoodLabelServingDraft(
      label: label,
      quantity: quantity ?? 1,
      unit: unit,
      gramsEquivalent: AiJson.positive(json['grams_equivalent']),
      mlEquivalent: AiJson.positive(json['ml_equivalent']),
    );
  }

  Map<String, dynamic> toJson() => {
    'label': label,
    'quantity': quantity,
    'unit': unit,
    if (gramsEquivalent != null) 'grams_equivalent': gramsEquivalent,
    if (mlEquivalent != null) 'ml_equivalent': mlEquivalent,
  };
}

/// Food identified by the AI (from a nutrition label photo or described by
/// the user in the chat). Values refer to [referenceAmount] of
/// [referenceUnit] (normally 100 g).
class AiFoodLabelDraft {
  final String name;
  final String? brand;
  final String? barcode;
  final double referenceAmount;
  final String referenceUnit;
  final NutritionValues values;
  final List<AiFoodLabelServingDraft> servings;

  const AiFoodLabelDraft({
    required this.name,
    this.brand,
    this.barcode,
    this.referenceAmount = 100,
    this.referenceUnit = 'g',
    this.values = NutritionValues.empty,
    this.servings = const [],
  });

  /// Keys of the nutrient fields, in display order. The single source for the
  /// parser, the tool schema and the extraction prompt.
  static List<String> get nutrientKeys =>
      NutritionValues.empty.toMap().keys.toList(growable: false);

  /// Unit of a nutrient key (`calories` → kcal, `sodium_mg` → mg…).
  static String nutrientUnit(String key) {
    if (key == 'calories') return 'kcal';
    final suffix = key.split('_').last;
    return const {'g': 'g', 'mg': 'mg', 'ug': 'µg'}[suffix] ?? '';
  }

  /// Parses the model's answer. Throws [FormatException] naming the field
  /// when the name, the reference amount or the reference unit is missing or
  /// unreadable: a reference is never guessed (it would silently scale every
  /// nutrient).
  factory AiFoodLabelDraft.fromJson(Map<String, dynamic> json) {
    final name = AiJson.text(json['name']);
    if (name == null) throw const FormatException('name is required');
    final amount = AiJson.positive(json['reference_amount']);
    if (amount == null) {
      throw const FormatException(
        'reference_amount is required and must be a positive number',
      );
    }
    final unit = AiJson.text(json['reference_unit']);
    if (unit == null) {
      throw const FormatException('reference_unit is required (g or ml)');
    }
    final per = AiJson.objectOrNull(json['per']) ?? const {};
    final values = NutritionValues.fromMap({
      for (final key in nutrientKeys) key: AiJson.number(per[key]),
    });
    final servings = <AiFoodLabelServingDraft>[];
    final rawServings = json['servings'];
    if (rawServings is List) {
      for (final item in rawServings) {
        final map = AiJson.objectOrNull(item);
        if (map == null) continue;
        final serving = AiFoodLabelServingDraft.tryParse(map);
        if (serving != null) servings.add(serving);
      }
    }
    return AiFoodLabelDraft(
      name: name,
      brand: AiJson.text(json['brand']),
      barcode: AiJson.text(json['barcode']),
      referenceAmount: amount,
      referenceUnit: unit,
      values: values,
      servings: servings,
    );
  }

  /// Plausibility problems the user should not have to discover: negative or
  /// impossible numbers are already dropped by the parser, so this checks
  /// relations (a macro cannot weigh more than the amount it is per).
  List<String> problems() {
    final out = <String>[];
    final unit = referenceUnit.trim().toLowerCase();
    final weighable = unit == 'g' || unit == 'ml';
    if (weighable) {
      for (final entry in values.toMap().entries) {
        final value = entry.value as double?;
        if (value == null) continue;
        if (nutrientUnit(entry.key) == 'g' && value > referenceAmount) {
          out.add(
            '${entry.key} ($value g) is larger than the reference amount '
            '($referenceAmount $unit)',
          );
        }
      }
    }
    final calories = values.calories;
    if (calories != null && weighable && calories > referenceAmount * 9.5) {
      out.add(
        'calories ($calories kcal) is impossible for $referenceAmount $unit',
      );
    }
    final macros =
        (values.proteinG ?? 0) + (values.carbsG ?? 0) + (values.fatG ?? 0);
    if (weighable && macros > referenceAmount * 1.05) {
      out.add(
        'protein + carbs + fat ($macros g) is larger than the reference '
        'amount ($referenceAmount $unit)',
      );
    }
    return out;
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    if (brand != null) 'brand': brand,
    if (barcode != null) 'barcode': barcode,
    'reference_amount': referenceAmount,
    'reference_unit': referenceUnit,
    'per': {
      for (final entry in values.toMap().entries)
        if (entry.value != null) entry.key: entry.value,
    },
    'servings': servings.map((serving) => serving.toJson()).toList(),
  };
}
