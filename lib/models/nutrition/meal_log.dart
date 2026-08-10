import 'package:workout_notes/l10n/app_localizations.dart';

/// Legacy stable identifiers for meal types.
///
/// These values were the only meal types when the app shipped, and rows
/// created back then still carry them in [MealLog.mealType]. New meals are
/// created by the user with a free name and a random uuid as [MealLog.mealType];
/// when [MealLog.name] is null (legacy rows only), the UI maps these keys to a
/// localized label.
class MealType {
  static const String breakfast = 'breakfast';
  static const String lunch = 'lunch';
  static const String dinner = 'dinner';
  static const String snacks = 'snacks';

  /// Whether [value] is one of the legacy fixed meal type keys.
  static bool isLegacy(String value) =>
      value == breakfast || value == lunch || value == dinner || value == snacks;
}

/// A meal of a day. There is at most one [MealLog] for each pair
/// (date, mealType) — the repository lazily creates them.
class MealLog {
  final String id;
  final String date;
  final String mealType;
  final String? name;
  final String? notes;
  final DateTime createdAt;

  const MealLog({
    required this.id,
    required this.date,
    required this.mealType,
    this.name,
    this.notes,
    required this.createdAt,
  });

  /// Display label of this log's section: the name snapshot taken when
  /// the log was created, otherwise the localized legacy label,
  /// otherwise the raw key. Used for sections whose meal type was
  /// deleted from the catalog — history stays visible with its name.
  String displayName(AppLocalizations loc) {
    final snapshot = name;
    if (snapshot != null && snapshot.trim().isNotEmpty) return snapshot;
    switch (mealType) {
      case MealType.breakfast:
        return loc.nutritionMealBreakfast;
      case MealType.lunch:
        return loc.nutritionMealLunch;
      case MealType.dinner:
        return loc.nutritionMealDinner;
      case MealType.snacks:
        return loc.nutritionMealSnacks;
    }
    return mealType;
  }

  MealLog copyWith({
    String? id,
    String? date,
    String? mealType,
    Object? name = _sentinel,
    Object? notes = _sentinel,
    DateTime? createdAt,
  }) {
    return MealLog(
      id: id ?? this.id,
      date: date ?? this.date,
      mealType: mealType ?? this.mealType,
      name: identical(name, _sentinel) ? this.name : name as String?,
      notes: identical(notes, _sentinel) ? this.notes : notes as String?,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'date': date,
    'meal_type': mealType,
    'name': name,
    'notes': notes,
    'created_at': createdAt.toIso8601String(),
  };

  factory MealLog.fromMap(Map<String, dynamic> map) {
    return MealLog(
      id: map['id'] as String,
      date: map['date'] as String,
      mealType: map['meal_type'] as String,
      name: map['name'] as String?,
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

const Object _sentinel = Object();
