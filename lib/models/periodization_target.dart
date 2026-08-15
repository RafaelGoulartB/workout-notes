import 'dart:convert';

class PeriodizationTarget {
  final String id;
  final String phaseId;
  final int version;
  final DateTime validFrom;
  final double? calories;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;

  /// How the nutrition grams were defined: g/kg ratios and the reference
  /// weight they were multiplied by. Meta only — consumers read the grams.
  final double? proteinGPerKg;
  final double? fatGPerKg;
  final double? weightKgUsed;
  final int? workoutsPerWeek;
  final int? minSetsPerWeek;
  final int? maxSetsPerWeek;
  final double? minRpe;
  final double? maxRpe;

  /// Routine linked to the week this target applies to. Serialized inside
  /// [trainingJson]; each phase week may carry its own routine.
  final String? routineId;
  final double? targetWeightKg;
  final double? weeklyWeightChangePercent;
  final double? sleepHours;
  final DateTime createdAt;

  const PeriodizationTarget({
    required this.id,
    required this.phaseId,
    required this.version,
    required this.validFrom,
    this.calories,
    this.proteinG,
    this.carbsG,
    this.fatG,
    this.proteinGPerKg,
    this.fatGPerKg,
    this.weightKgUsed,
    this.workoutsPerWeek,
    this.minSetsPerWeek,
    this.maxSetsPerWeek,
    this.minRpe,
    this.maxRpe,
    this.routineId,
    this.targetWeightKg,
    this.weeklyWeightChangePercent,
    this.sleepHours,
    required this.createdAt,
  });

  bool get isEmpty =>
      calories == null &&
      proteinG == null &&
      carbsG == null &&
      fatG == null &&
      workoutsPerWeek == null &&
      minSetsPerWeek == null &&
      maxSetsPerWeek == null &&
      minRpe == null &&
      maxRpe == null &&
      routineId == null &&
      targetWeightKg == null &&
      weeklyWeightChangePercent == null &&
      sleepHours == null;

  Map<String, dynamic> get nutritionJson => {
    if (calories != null) 'calories': calories,
    if (proteinG != null) 'protein_g': proteinG,
    if (carbsG != null) 'carbs_g': carbsG,
    if (fatG != null) 'fat_g': fatG,
    if (proteinGPerKg != null) 'protein_g_per_kg': proteinGPerKg,
    if (fatGPerKg != null) 'fat_g_per_kg': fatGPerKg,
    if (weightKgUsed != null) 'weight_kg_used': weightKgUsed,
  };

  Map<String, dynamic> get trainingJson => {
    if (workoutsPerWeek != null) 'workouts_per_week': workoutsPerWeek,
    if (minSetsPerWeek != null) 'min_sets_per_week': minSetsPerWeek,
    if (maxSetsPerWeek != null) 'max_sets_per_week': maxSetsPerWeek,
    if (minRpe != null) 'min_rpe': minRpe,
    if (maxRpe != null) 'max_rpe': maxRpe,
    if (routineId != null) 'routine_id': routineId,
  };

  Map<String, dynamic> get bodyJson => {
    if (targetWeightKg != null) 'target_weight_kg': targetWeightKg,
    if (weeklyWeightChangePercent != null)
      'weekly_weight_change_percent': weeklyWeightChangePercent,
  };

  Map<String, dynamic> get sleepJson => {
    if (sleepHours != null) 'hours': sleepHours,
  };

  PeriodizationTarget copyWith({
    String? id,
    String? phaseId,
    int? version,
    DateTime? validFrom,
    double? calories,
    double? proteinG,
    double? carbsG,
    double? fatG,
    double? proteinGPerKg,
    double? fatGPerKg,
    double? weightKgUsed,
    int? workoutsPerWeek,
    int? minSetsPerWeek,
    int? maxSetsPerWeek,
    double? minRpe,
    double? maxRpe,
    String? routineId,
    double? targetWeightKg,
    double? weeklyWeightChangePercent,
    double? sleepHours,
    DateTime? createdAt,
  }) => PeriodizationTarget(
    id: id ?? this.id,
    phaseId: phaseId ?? this.phaseId,
    version: version ?? this.version,
    validFrom: validFrom ?? this.validFrom,
    calories: calories ?? this.calories,
    proteinG: proteinG ?? this.proteinG,
    carbsG: carbsG ?? this.carbsG,
    fatG: fatG ?? this.fatG,
    proteinGPerKg: proteinGPerKg ?? this.proteinGPerKg,
    fatGPerKg: fatGPerKg ?? this.fatGPerKg,
    weightKgUsed: weightKgUsed ?? this.weightKgUsed,
    workoutsPerWeek: workoutsPerWeek ?? this.workoutsPerWeek,
    minSetsPerWeek: minSetsPerWeek ?? this.minSetsPerWeek,
    maxSetsPerWeek: maxSetsPerWeek ?? this.maxSetsPerWeek,
    minRpe: minRpe ?? this.minRpe,
    maxRpe: maxRpe ?? this.maxRpe,
    routineId: routineId ?? this.routineId,
    targetWeightKg: targetWeightKg ?? this.targetWeightKg,
    weeklyWeightChangePercent:
        weeklyWeightChangePercent ?? this.weeklyWeightChangePercent,
    sleepHours: sleepHours ?? this.sleepHours,
    createdAt: createdAt ?? this.createdAt,
  );

  Map<String, dynamic> toSnapshot() => {
    'version': version,
    'valid_from': _date(validFrom),
    'nutrition': nutritionJson,
    'training': trainingJson,
    'body': bodyJson,
    'sleep': sleepJson,
  };

  Map<String, dynamic> toMap() => {
    'id': id,
    'phase_id': phaseId,
    'nutrition_json': jsonEncode(nutritionJson),
    'training_json': jsonEncode(trainingJson),
    'body_json': jsonEncode(bodyJson),
    'sleep_json': jsonEncode(sleepJson),
    'version': version,
    'valid_from': _date(validFrom),
    'created_at': createdAt.toIso8601String(),
  };

  factory PeriodizationTarget.fromMap(Map<String, dynamic> map) {
    final nutrition = _decode(map['nutrition_json']);
    final training = _decode(map['training_json']);
    final body = _decode(map['body_json']);
    final sleep = _decode(map['sleep_json']);
    return PeriodizationTarget(
      id: map['id'] as String,
      phaseId: map['phase_id'] as String,
      version: (map['version'] as num?)?.toInt() ?? 1,
      validFrom: DateTime.parse(map['valid_from'] as String),
      calories: _double(nutrition['calories']),
      proteinG: _double(nutrition['protein_g']),
      carbsG: _double(nutrition['carbs_g']),
      fatG: _double(nutrition['fat_g']),
      proteinGPerKg: _double(nutrition['protein_g_per_kg']),
      fatGPerKg: _double(nutrition['fat_g_per_kg']),
      weightKgUsed: _double(nutrition['weight_kg_used']),
      workoutsPerWeek: (training['workouts_per_week'] as num?)?.toInt(),
      minSetsPerWeek: (training['min_sets_per_week'] as num?)?.toInt(),
      maxSetsPerWeek: (training['max_sets_per_week'] as num?)?.toInt(),
      minRpe: _double(training['min_rpe']),
      maxRpe: _double(training['max_rpe']),
      routineId: training['routine_id'] as String?,
      targetWeightKg: _double(body['target_weight_kg']),
      weeklyWeightChangePercent: _double(body['weekly_weight_change_percent']),
      sleepHours: _double(sleep['hours']),
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  static Map<String, dynamic> _decode(dynamic raw) {
    if (raw is! String || raw.isEmpty) return {};
    final decoded = jsonDecode(raw);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
  }

  static double? _double(dynamic value) => (value as num?)?.toDouble();
  static String _date(DateTime value) => DateTime(
    value.year,
    value.month,
    value.day,
  ).toIso8601String().substring(0, 10);
}
