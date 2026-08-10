/// A measurement/portion defined by the data source for a [FoodVariant].
///
/// A serving is **only** convertible to grams or millilitres when the
/// source (or the manual entry) provides an explicit
/// [gramsEquivalent] / [mlEquivalent] value. We never invent
/// conversions — a missing equivalency means the value cannot be used
/// for direct macro calculation.
class FoodServing {
  final String id;
  final String foodVariantId;
  final String label;
  final double quantity;
  final String unit;
  final double? gramsEquivalent;
  final double? mlEquivalent;

  const FoodServing({
    required this.id,
    required this.foodVariantId,
    required this.label,
    this.quantity = 1,
    required this.unit,
    this.gramsEquivalent,
    this.mlEquivalent,
  });

  /// True when the serving can be converted to grams explicitly.
  bool get hasGramConversion => gramsEquivalent != null && gramsEquivalent! > 0;

  /// True when the serving can be converted to millilitres explicitly.
  bool get hasMlConversion => mlEquivalent != null && mlEquivalent! > 0;

  FoodServing copyWith({
    String? id,
    String? foodVariantId,
    String? label,
    double? quantity,
    String? unit,
    Object? gramsEquivalent = _sentinel,
    Object? mlEquivalent = _sentinel,
  }) {
    return FoodServing(
      id: id ?? this.id,
      foodVariantId: foodVariantId ?? this.foodVariantId,
      label: label ?? this.label,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      gramsEquivalent: identical(gramsEquivalent, _sentinel)
          ? this.gramsEquivalent
          : gramsEquivalent as double?,
      mlEquivalent: identical(mlEquivalent, _sentinel)
          ? this.mlEquivalent
          : mlEquivalent as double?,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'food_variant_id': foodVariantId,
    'label': label,
    'quantity': quantity,
    'unit': unit,
    'grams_equivalent': gramsEquivalent,
    'ml_equivalent': mlEquivalent,
  };

  factory FoodServing.fromMap(Map<String, dynamic> map) {
    return FoodServing(
      id: map['id'] as String,
      foodVariantId: map['food_variant_id'] as String,
      label: map['label'] as String,
      quantity: (map['quantity'] as num?)?.toDouble() ?? 1.0,
      unit: map['unit'] as String,
      gramsEquivalent: (map['grams_equivalent'] as num?)?.toDouble(),
      mlEquivalent: (map['ml_equivalent'] as num?)?.toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is FoodServing && other.id == id);

  @override
  int get hashCode => id.hashCode;
}

const Object _sentinel = Object();
