/// A pair of shoes (or other running gear) whose mileage is tracked.
class RunGear {
  final String id;
  final String name;
  final String? brand;
  final String? notes;

  /// Distance already on the shoe before it was added to the app.
  final double initialDistanceMeters;

  /// Distance at which the app suggests replacing the shoe.
  final double retireDistanceMeters;

  /// Pre-selected for new runs.
  final bool isDefault;
  final DateTime? retiredAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const RunGear({
    required this.id,
    required this.name,
    this.brand,
    this.notes,
    this.initialDistanceMeters = 0,
    this.retireDistanceMeters = defaultRetireDistanceMeters,
    this.isDefault = false,
    this.retiredAt,
    required this.createdAt,
    required this.updatedAt,
  });

  static const double defaultRetireDistanceMeters = 700000;

  bool get isRetired => retiredAt != null;

  factory RunGear.fromMap(Map<String, dynamic> map) {
    return RunGear(
      id: map['id'] as String,
      name: map['name'] as String? ?? '',
      brand: map['brand'] as String?,
      notes: map['notes'] as String?,
      initialDistanceMeters:
          (map['initial_distance_meters'] as num?)?.toDouble() ?? 0,
      retireDistanceMeters:
          (map['retire_distance_meters'] as num?)?.toDouble() ??
          defaultRetireDistanceMeters,
      isDefault: (map['is_default'] as num?)?.toInt() == 1,
      retiredAt: DateTime.tryParse(map['retired_at'] as String? ?? ''),
      createdAt:
          DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(map['updated_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'brand': brand,
    'notes': notes,
    'initial_distance_meters': initialDistanceMeters,
    'retire_distance_meters': retireDistanceMeters,
    'is_default': isDefault ? 1 : 0,
    'retired_at': retiredAt?.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  RunGear copyWith({
    String? name,
    String? brand,
    String? notes,
    double? initialDistanceMeters,
    double? retireDistanceMeters,
    bool? isDefault,
    DateTime? retiredAt,
    bool clearRetired = false,
    DateTime? updatedAt,
  }) {
    return RunGear(
      id: id,
      name: name ?? this.name,
      brand: brand ?? this.brand,
      notes: notes ?? this.notes,
      initialDistanceMeters:
          initialDistanceMeters ?? this.initialDistanceMeters,
      retireDistanceMeters: retireDistanceMeters ?? this.retireDistanceMeters,
      isDefault: isDefault ?? this.isDefault,
      retiredAt: clearRetired ? null : (retiredAt ?? this.retiredAt),
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// A gear item plus the distance logged with it.
class RunGearUsage {
  final RunGear gear;
  final double loggedDistanceMeters;
  final int runCount;
  final DateTime? lastUsedAt;

  const RunGearUsage({
    required this.gear,
    required this.loggedDistanceMeters,
    required this.runCount,
    required this.lastUsedAt,
  });

  double get totalDistanceMeters =>
      gear.initialDistanceMeters + loggedDistanceMeters;

  /// 0..1+ share of the retirement distance already used.
  double get wearRatio => gear.retireDistanceMeters <= 0
      ? 0
      : totalDistanceMeters / gear.retireDistanceMeters;

  bool get needsReplacement => wearRatio >= 1;

  bool get nearingReplacement => wearRatio >= 0.85;
}
