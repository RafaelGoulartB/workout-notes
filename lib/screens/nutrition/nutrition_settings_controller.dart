import 'package:flutter/foundation.dart';
import 'package:workout_notes/models/nutrition/meal_type.dart';
import 'package:workout_notes/models/nutrition/nutrition_goal.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/services/effective_nutrition_goal_service.dart';
import 'package:workout_notes/utils/app_number_format.dart';
import 'package:workout_notes/utils/nutrition_goal_suggest.dart';

/// State and persistence of the nutrition settings screen: the stored daily
/// goal (TDEE + adjustment + macros), the plan override that may replace it,
/// and the meal-type catalog. Methods that write throw on failure; the screen
/// decides how to report it.
class NutritionSettingsController extends ChangeNotifier {
  NutritionSettingsController({required this.repository});

  final NutritionRepository repository;

  bool _isLoading = true;
  NutritionGoal? _current;
  EffectiveNutritionGoal _effective = const EffectiveNutritionGoal();
  List<MealTypeDefinition> _mealTypes = const [];
  bool _disposed = false;

  bool get isLoading => _isLoading;
  NutritionGoal? get current => _current;
  EffectiveNutritionGoal get effective => _effective;
  List<MealTypeDefinition> get mealTypes => _mealTypes;

  Future<void> load() async {
    try {
      final results = await Future.wait([
        repository.getActiveGoal(),
        repository.getMealTypes(),
        // Detects whether an active plan is overriding the settings goal.
        EffectiveNutritionGoalService.resolve(nutritionRepository: repository),
      ]);
      if (_disposed) return;
      _current = results[0] as NutritionGoal?;
      _mealTypes = results[1] as List<MealTypeDefinition>;
      _effective = results[2] as EffectiveNutritionGoal;
      _isLoading = false;
      notifyListeners();
    } catch (_) {
      if (_disposed) return;
      _isLoading = false;
      notifyListeners();
    }
  }

  // ===================================================================
  // Goal saving
  // ===================================================================

  Future<void> saveGoalField({
    double? calories,
    double? proteinG,
    double? carbsG,
    double? fatG,
    double? tdee,
    String? adjustmentKind,
    double? adjustmentPercent,
  }) async {
    final goal = await repository.saveGoal(
      calories: calories,
      proteinG: proteinG,
      carbsG: carbsG,
      fatG: fatG,
      tdee: tdee,
      adjustmentKind: adjustmentKind,
      adjustmentPercent: adjustmentPercent,
    );
    _setCurrent(goal);
  }

  /// Carbohydrates always absorb the energy left by protein and fat, so a TDEE
  /// or adjustment change re-derives them to keep the macro split consistent
  /// with the goal. Falls back to [carbsG] when the goal cannot be computed.
  static double? resolveCarbs({
    required double? tdee,
    required double? adjustmentPercent,
    required double? proteinG,
    required double? fatG,
    required double? carbsG,
  }) {
    final goalKcal = (tdee != null && tdee > 0 && adjustmentPercent != null)
        ? tdee * (1 + adjustmentPercent / 100)
        : null;
    return (goalKcal != null && proteinG != null && fatG != null)
        ? ((goalKcal - proteinG * 4 - fatG * 9) / 4)
              .clamp(0, double.infinity)
              .roundToDouble()
        : carbsG;
  }

  Future<void> saveTdeeGoal({
    required double? tdee,
    required String? adjustmentKind,
    required double? adjustmentPercent,
    double? proteinG,
    double? carbsG,
    double? fatG,
  }) async {
    final goal = await repository.saveGoal(
      tdee: tdee,
      adjustmentKind: adjustmentKind,
      adjustmentPercent: adjustmentPercent,
      proteinG: proteinG,
      carbsG: resolveCarbs(
        tdee: tdee,
        adjustmentPercent: adjustmentPercent,
        proteinG: proteinG,
        fatG: fatG,
        carbsG: carbsG,
      ),
      fatG: fatG,
    );
    _setCurrent(goal);
  }

  Future<void> clearGoal() async {
    await repository.clearActiveGoal();
    _setCurrent(null);
  }

  void _setCurrent(NutritionGoal? goal) {
    if (_disposed) return;
    _current = goal;
    notifyListeners();
  }

  // ===================================================================
  // Meal types catalog
  // ===================================================================

  Future<void> loadMealTypes() async {
    final types = await repository.getMealTypes();
    if (_disposed) return;
    _mealTypes = types;
    notifyListeners();
  }

  Future<void> addMealType(String name) async {
    await repository.createMealType(name);
    await loadMealTypes();
  }

  Future<void> renameMealType(MealTypeDefinition type, String name) async {
    await repository.renameMealType(type.id, name);
    await loadMealTypes();
  }

  Future<void> deleteMealType(MealTypeDefinition type) async {
    await repository.deleteMealType(type.id);
    await loadMealTypes();
  }

  /// Moves [type] by [delta] positions, updating the list optimistically and
  /// reloading it if persisting the order fails.
  Future<void> moveMealType(MealTypeDefinition type, int delta) async {
    final index = _mealTypes.indexWhere((t) => t.id == type.id);
    final target = index + delta;
    if (index < 0 || target < 0 || target >= _mealTypes.length) return;
    final reordered = [..._mealTypes];
    final item = reordered.removeAt(index);
    reordered.insert(target, item);
    _mealTypes = reordered;
    notifyListeners();
    try {
      await repository.reorderMealTypes([for (final t in reordered) t.id]);
    } catch (_) {
      await loadMealTypes();
    }
  }

  // ===================================================================
  // Formatting helpers
  // ===================================================================

  static String formatNum(double value) {
    if (value == value.roundToDouble()) return AppNumberFormat.decimal(value, 0);
    return AppNumberFormat.decimal(value, 1);
  }

  static String formatPercent(double percent) {
    final rounded = percent.round();
    if (rounded > 0) return '+${AppNumberFormat.decimal(rounded, 0)}%';
    return '${AppNumberFormat.decimal(rounded, 0)}%';
  }

  static NutritionObjective parseAdjustmentKind(String? raw) {
    return NutritionObjective.values.firstWhere(
      (o) => o.name == raw,
      orElse: () => NutritionObjective.maintenance,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
