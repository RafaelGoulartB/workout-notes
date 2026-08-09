import 'package:workout_notes/l10n/app_localizations.dart';

import 'meal_log.dart';

/// A user-defined meal type from the nutrition catalog.
///
/// The catalog is managed in the nutrition settings and the diary
/// renders one section per type. [key] is the stable identifier stored
/// in [MealLog.mealType]: the four legacy keys (`breakfast`, `lunch`,
/// `dinner`, `snacks`) are seeded with [name] == null so their label
/// resolves through l10n; renamed and custom types carry their own
/// [name].
class MealTypeDefinition {
  final String id;
  final String key;
  final String? name;
  final int orderIndex;
  final DateTime createdAt;

  const MealTypeDefinition({
    required this.id,
    required this.key,
    this.name,
    required this.orderIndex,
    required this.createdAt,
  });

  String displayName(AppLocalizations loc) {
    final custom = name;
    if (custom != null && custom.trim().isNotEmpty) return custom;
    switch (key) {
      case MealType.breakfast:
        return loc.nutritionMealBreakfast;
      case MealType.lunch:
        return loc.nutritionMealLunch;
      case MealType.dinner:
        return loc.nutritionMealDinner;
      case MealType.snacks:
        return loc.nutritionMealSnacks;
    }
    return key;
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'key': key,
    'name': name,
    'order_index': orderIndex,
    'created_at': createdAt.toIso8601String(),
  };

  factory MealTypeDefinition.fromMap(Map<String, dynamic> map) {
    return MealTypeDefinition(
      id: map['id'] as String,
      key: map['key'] as String,
      name: map['name'] as String?,
      orderIndex: (map['order_index'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
