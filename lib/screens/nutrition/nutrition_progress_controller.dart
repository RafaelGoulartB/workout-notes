import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/nutrition/calorie_analytics.dart';
import 'package:workout_notes/models/nutrition/nutrition_goal.dart';
import 'package:workout_notes/models/nutrition/nutrition_progress.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/services/effective_nutrition_goal_service.dart';
import 'package:workout_notes/utils/date_utils.dart';

/// State and data loading of the nutrition progress screen: the selected
/// calendar week/month, the calorie balance and breakdowns for it, and the
/// lazily loaded secondary-nutrient averages. UI-free; the screen listens to it.
class NutritionProgressController extends ChangeNotifier {
  NutritionProgressController({
    NutritionRepository? repository,
    DateTime Function()? now,
  }) : _repository = repository ?? DatabaseHelper.instance.nutritionRepo,
       _now = now ?? DateTime.now {
    _periodAnchor = dayOf(_now());
  }

  final NutritionRepository _repository;
  final DateTime Function() _now;

  BalancePeriod _period = BalancePeriod.week;
  late DateTime _periodAnchor;

  CalorieBalance? _balance;
  List<DailyCalorieTotal> _dailies = const [];
  List<CalorieContributor> _contributors = const [];
  List<MealTypeCalories> _mealDistribution = const [];
  NutritionGoal? _goal;
  MacroSummary? _macros;
  bool _isLoading = true;
  bool _loadFailed = false;
  bool _nutrientsExpanded = false;
  bool _isLoadingNutrients = false;
  bool _nutrientLoadFailed = false;
  NutrientAverages? _nutrientAverages;
  int _nutrientRequestId = 0;
  int _nutrientViewVersion = 0;
  int _loadRequestId = 0;
  bool _disposed = false;

  BalancePeriod get period => _period;
  CalorieBalance? get balance => _balance;
  List<DailyCalorieTotal> get dailies => _dailies;
  List<CalorieContributor> get contributors => _contributors;
  List<MealTypeCalories> get mealDistribution => _mealDistribution;
  NutritionGoal? get goal => _goal;
  MacroSummary? get macros => _macros;
  bool get isLoading => _isLoading;
  bool get loadFailed => _loadFailed;
  bool get nutrientsExpanded => _nutrientsExpanded;
  bool get isLoadingNutrients => _isLoadingNutrients;
  bool get nutrientLoadFailed => _nutrientLoadFailed;
  NutrientAverages? get nutrientAverages => _nutrientAverages;

  /// Bumped whenever the lazy nutrient card must be rebuilt from scratch.
  int get nutrientViewVersion => _nutrientViewVersion;

  DateTime get periodStart =>
      NutritionProgressCalculator.periodStart(_period, _periodAnchor);
  DateTime get periodEnd =>
      NutritionProgressCalculator.periodEnd(_period, _periodAnchor);
  int get periodDays =>
      NutritionProgressCalculator.periodDays(_period, _periodAnchor);

  bool get isCurrentPeriod => NutritionProgressCalculator.isCurrentPeriod(
    _period,
    _periodAnchor,
    _now(),
  );

  bool get canMoveNext =>
      NutritionProgressCalculator.canMoveNext(_period, _periodAnchor, _now());

  double? get rollingGoal => _goal?.calories;

  List<FlSpot> get rollingSpots =>
      NutritionProgressCalculator.rollingSpots(_dailies);

  String periodLabel(AppLocalizations loc) {
    if (isCurrentPeriod) {
      return _period == BalancePeriod.week
          ? loc.nutritionBalanceThisWeek
          : loc.nutritionBalanceThisMonth;
    }
    if (_period == BalancePeriod.month) {
      final label = DateFormat.yMMMM(Intl.defaultLocale).format(periodStart);
      return label.characters.first.toUpperCase() + label.substring(1);
    }
    final start = periodStart;
    final end = periodEnd;
    if (start.month == end.month && start.year == end.year) {
      return '${start.day}–${DateFormat.MMM(Intl.defaultLocale).format(end)} ${end.year}';
    }
    return '${DateFormat.MMMd(Intl.defaultLocale).format(start)} – '
        '${DateFormat.MMMd(Intl.defaultLocale).format(end)}';
  }

  /// Switches between the week and month windows and reloads.
  void setPeriod(BalancePeriod period) {
    if (period == _period) return;
    _period = period;
    _resetLazyNutrients();
    _notify();
    load();
  }

  Future<void> movePeriod(int delta) async {
    if (delta > 0 && !canMoveNext) return;
    _periodAnchor = NutritionProgressCalculator.shiftAnchor(
      _period,
      _periodAnchor,
      delta,
    );
    _resetLazyNutrients();
    _notify();
    await load();
  }

  void _resetLazyNutrients() {
    _nutrientsExpanded = false;
    _isLoadingNutrients = false;
    _nutrientLoadFailed = false;
    _nutrientAverages = null;
    _nutrientRequestId++;
    _nutrientViewVersion++;
  }

  Future<void> load() async {
    if (_disposed) return;
    final requestId = ++_loadRequestId;
    final start = periodStart;
    final end = periodEnd;
    _isLoading = true;
    _loadFailed = false;
    _resetLazyNutrients();
    _notify();
    try {
      final results = await Future.wait([
        // The active plan's current week overrides the settings goal;
        // the anchor day keeps past periods on their own plan target.
        EffectiveNutritionGoalService.resolve(
          nutritionRepository: _repository,
          date: _periodAnchor,
        ),
        _repository.getDailyCalorieTotalsForRange(
          startDate: start,
          endDate: end,
        ),
        _repository.getTopCalorieContributorsForRange(
          startDate: start,
          endDate: end,
          limit: 8,
        ),
        _repository.getCaloriesByMealTypeForRange(
          startDate: start,
          endDate: end,
        ),
        _repository.getDailyNutritionHistoryForRange(
          startDate: start,
          endDate: end,
        ),
      ]);
      if (_disposed || requestId != _loadRequestId) return;
      final goal = (results[0] as EffectiveNutritionGoal).goal;
      final dailies = results[1] as List<DailyCalorieTotal>;
      final balance = _repository.calculateCalorieBalance(
        dailies: dailies,
        goal: goal?.calories,
      );
      _goal = goal;
      _dailies = dailies;
      _balance = balance;
      _contributors = results[2] as List<CalorieContributor>;
      _mealDistribution = results[3] as List<MealTypeCalories>;
      _macros = MacroSummary.fromRows(results[4] as List<Map<String, dynamic>>);
      _isLoading = false;
      _notify();
    } catch (error, stack) {
      debugPrint('Nutrition progress failed to load: $error\n$stack');
      if (_disposed || requestId != _loadRequestId) return;
      _isLoading = false;
      _loadFailed = true;
      _notify();
    }
  }

  Future<void> toggleNutrients(bool expanded) async {
    _nutrientsExpanded = expanded;
    _notify();
    if (!expanded || _nutrientAverages != null || _isLoadingNutrients) return;

    final requestId = ++_nutrientRequestId;
    final start = periodStart;
    final end = periodEnd;
    _isLoadingNutrients = true;
    _nutrientLoadFailed = false;
    _notify();
    try {
      final rows = await _repository.getDailyNutritionHistoryForRange(
        startDate: start,
        endDate: end,
      );
      if (_disposed || requestId != _nutrientRequestId) return;
      _nutrientAverages = NutrientAverages.fromRows(rows);
      _isLoadingNutrients = false;
      _notify();
    } catch (_) {
      if (_disposed || requestId != _nutrientRequestId) return;
      _isLoadingNutrients = false;
      _nutrientLoadFailed = true;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
