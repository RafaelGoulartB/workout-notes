/// Stable identifiers for meal types.
///
/// The values are persisted in [MealLog.mealType] and never translated.
/// The UI maps each value to a localized label.
class MealType {
  static const String breakfast = 'breakfast';
  static const String lunch = 'lunch';
  static const String dinner = 'dinner';
  static const String snacks = 'snacks';

  static const List<String> all = <String>[breakfast, lunch, dinner, snacks];

  /// Order in which meal types are displayed in the daily screen.
  static const List<String> displayOrder = <String>[
    breakfast,
    lunch,
    dinner,
    snacks,
  ];
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
