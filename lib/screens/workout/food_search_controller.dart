import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/nutrition/food.dart';
import 'package:workout_notes/models/nutrition/food_search_result.dart';
import 'package:workout_notes/models/nutrition/food_serving.dart';
import 'package:workout_notes/models/nutrition/food_variant.dart';
import 'package:workout_notes/models/nutrition/meal_log.dart';
import 'package:workout_notes/models/nutrition/meal_type.dart';
import 'package:workout_notes/models/nutrition/nutrition_selection.dart';
import 'package:workout_notes/models/nutrition/saved_meal.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/services/nutrition_gateway.dart';
import 'package:workout_notes/utils/date_utils.dart';

/// Chip filter shown while the search field is empty.
enum FoodSearchFilter { all, meals, favorites, myFoods }

/// Outcome of resolving a scanned barcode / QR code.
enum BarcodeLookupKind {
  /// Nothing that looks like a product code was scanned.
  invalidCode,

  /// Found in the cache or on Open Food Facts; see [BarcodeLookup.selection].
  found,

  /// The cache had the food but without any variant to select.
  cachedWithoutVariant,

  /// The gateway failed; see [BarcodeLookup.errorCode].
  gatewayError,

  /// The gateway answered without a usable product.
  notFound,
}

class BarcodeLookup {
  const BarcodeLookup(this.kind, {this.selection, this.errorCode});

  final BarcodeLookupKind kind;
  final NutritionSelection? selection;
  final String? errorCode;
}

/// The lists shown before the user types anything, already de-duplicated so a
/// food appears only in the first section that would list it.
class EmptyQuerySections {
  const EmptyQuerySections({
    required this.favorites,
    required this.mealSuggestions,
    required this.recents,
    required this.allFoods,
    required this.showSavedMeals,
    required this.hasSuggestions,
  });

  final List<FoodSearchResult> favorites;
  final List<FoodSearchResult> mealSuggestions;
  final List<FoodSearchResult> recents;
  final List<FoodSearchResult> allFoods;
  final bool showSavedMeals;
  final bool hasSuggestions;
}

/// State and data flow of the food search screen: local (debounced) and remote
/// (explicit, rate limited) search, the suggestion lists, favorites, saved
/// meals and barcode lookup. The screen owns the text field and feeds the
/// controller through [onQueryChanged].
class FoodSearchController extends ChangeNotifier {
  FoodSearchController({
    required this.gateway,
    required this.repository,
    String? mealType,
    String? mealName,
    String? date,
  }) : _selectedMealType = mealType,
       _selectedMealName = mealName,
       date = date ?? dateKey(DateTime.now());

  final NutritionGateway gateway;
  final NutritionRepository repository;

  /// Day (yyyy-MM-dd) that saved meals are logged into.
  final String date;

  /// Remote searches are explicit (keyboard search action / search icon),
  /// because the Open Food Facts endpoint must not be used as type-ahead.
  /// The minimum interval also protects against repeatedly submitting the
  /// same field faster than the provider's anonymous rate limit.
  static const Duration remoteMinInterval = Duration(seconds: 6);

  Timer? _localSearchDebounce;
  DateTime _lastRemoteSearchAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _remoteRequestGeneration = 0;
  String _query = '';
  bool _disposed = false;

  List<FoodSearchResult> _localResults = const [];
  List<FoodSearchResult> _remoteResults = const [];
  List<FoodSearchResult> _favorites = const [];
  List<FoodSearchResult> _recents = const [];
  List<FoodSearchResult> _allFoods = const [];
  List<FoodSearchResult> _mealSuggestions = const [];
  List<MealTypeDefinition> _mealTypes = const [];
  List<SavedMealWithItems> _savedMeals = const [];
  FoodSearchFilter _activeFilter = FoodSearchFilter.all;
  String? _selectedMealType;
  String? _selectedMealName;
  bool _suggestionsLoading = true;
  bool _isSearchingRemote = false;
  bool _isLoggingMeal = false;
  NutritionGatewayError? _remoteError;
  bool _showQueryTooShort = false;

  List<FoodSearchResult> get localResults => _localResults;
  List<FoodSearchResult> get remoteResults => _remoteResults;
  List<FoodSearchResult> get allFoods => _allFoods;
  List<MealTypeDefinition> get mealTypes => _mealTypes;
  List<SavedMealWithItems> get savedMeals => _savedMeals;
  FoodSearchFilter get activeFilter => _activeFilter;
  String? get selectedMealType => _selectedMealType;
  bool get suggestionsLoading => _suggestionsLoading;
  bool get isSearchingRemote => _isSearchingRemote;
  bool get isLoggingMeal => _isLoggingMeal;
  NutritionGatewayError? get remoteError => _remoteError;
  bool get showQueryTooShort => _showQueryTooShort;

  /// The trimmed text currently typed in the search field.
  String get query => _query.trim();

  void setFilter(FoodSearchFilter filter) {
    _activeFilter = filter;
    _notify();
  }

  // ------------------------------------------------------------------
  // Suggestions
  // ------------------------------------------------------------------

  Future<void> loadSuggestions() async {
    if (_disposed) return;
    try {
      final results = await Future.wait([
        repository.getFavoriteFoods(),
        repository.getRecentFoods(),
        repository.getAllFoods(),
        repository.getMealTypes(),
        repository.getSavedMeals(),
        if (_selectedMealType != null)
          repository.getMealSuggestions(_selectedMealType!),
      ]);
      if (_disposed) return;
      _favorites = attachVariants(results[0]);
      _recents = attachVariants(results[1]);
      _allFoods = attachVariants(results[2]);
      _mealTypes = results[3] as List<MealTypeDefinition>;
      _savedMeals = results[4] as List<SavedMealWithItems>;
      _mealSuggestions = _selectedMealType == null
          ? const []
          : attachVariants(results[5]);
      _suggestionsLoading = false;
      _notify();
    } catch (_) {
      if (_disposed) return;
      _suggestionsLoading = false;
      _notify();
    }
  }

  /// Sections for the empty-query state under the active filter.
  EmptyQuerySections get emptyQuerySections {
    final showFavorites =
        (_activeFilter == FoodSearchFilter.all ||
            _activeFilter == FoodSearchFilter.favorites) &&
        _favorites.isNotEmpty;
    final favoritesToShow = showFavorites
        ? _favorites
        : const <FoodSearchResult>[];
    final shownFoodIds = favoritesToShow
        .map((result) => result.food.id)
        .toSet();
    final mealSuggestionsToShow =
        _activeFilter == FoodSearchFilter.all && _selectedMealType != null
        ? _mealSuggestions
              .where((result) => shownFoodIds.add(result.food.id))
              .toList()
        : const <FoodSearchResult>[];
    shownFoodIds.addAll(mealSuggestionsToShow.map((result) => result.food.id));
    final recentsToShow = _activeFilter == FoodSearchFilter.all
        ? _recents.where((result) => shownFoodIds.add(result.food.id)).toList()
        : const <FoodSearchResult>[];
    final showAllFoods =
        _activeFilter == FoodSearchFilter.myFoods && _allFoods.isNotEmpty;
    final showSavedMeals = _activeFilter == FoodSearchFilter.meals;
    final hasSuggestions =
        showFavorites ||
        mealSuggestionsToShow.isNotEmpty ||
        recentsToShow.isNotEmpty ||
        showAllFoods ||
        (showSavedMeals && _savedMeals.isNotEmpty);
    return EmptyQuerySections(
      favorites: favoritesToShow,
      mealSuggestions: mealSuggestionsToShow,
      recents: recentsToShow,
      allFoods: showAllFoods ? _allFoods : const [],
      showSavedMeals: showSavedMeals,
      hasSuggestions: hasSuggestions,
    );
  }

  Future<void> toggleFavorite(FoodSearchResult result) async {
    final currently = result.food.isFavorite ?? false;
    // Optimistic update so the star reacts instantly.
    _replaceInLists(result, !currently);
    _notify();
    try {
      await repository.setFoodFavorite(result.food.id, !currently);
      await loadSuggestions();
    } catch (_) {
      if (_disposed) return;
      _replaceInLists(result, currently);
      _notify();
    }
  }

  void _replaceInLists(FoodSearchResult result, bool isFavorite) {
    FoodSearchResult withFlag(FoodSearchResult r) => FoodSearchResult(
      food: r.food.copyWith(isFavorite: isFavorite),
      primaryVariant: r.primaryVariant,
      servings: r.servings,
      isRemote: r.isRemote,
    );
    if (result.food.isFavorite != isFavorite) {
      List<FoodSearchResult> replace(List<FoodSearchResult> items) => [
        for (final r in items)
          if (r.food.id == result.food.id) withFlag(r) else r,
      ];
      _localResults = replace(_localResults);
      _favorites = replace(_favorites);
      _recents = replace(_recents);
      _allFoods = replace(_allFoods);
      _mealSuggestions = replace(_mealSuggestions);
    }
  }

  // ------------------------------------------------------------------
  // Search
  // ------------------------------------------------------------------

  /// Called on every change of the search field with its current text.
  void onQueryChanged(String value) {
    _query = value;
    // Invalidate a request that may still be in flight. Its response must
    // never be rendered under the newly typed query.
    _remoteRequestGeneration++;
    if (value.trim().isNotEmpty) _activeFilter = FoodSearchFilter.all;
    if (value.trim().length < 2) {
      _localResults = const [];
      _remoteResults = const [];
      _remoteError = null;
      _isSearchingRemote = false;
      _showQueryTooShort = value.trim().isNotEmpty;
      _notify();
      return;
    }
    _remoteResults = const [];
    _remoteError = null;
    _isSearchingRemote = false;
    _notify();
    _scheduleLocal(value);
  }

  void _scheduleLocal(String query) {
    _showQueryTooShort = false;
    _notify();
    _localSearchDebounce?.cancel();
    // Debounce: one DB search + hydration per pause in typing instead
    // of one per keystroke.
    _localSearchDebounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        final results = await repository.searchLocalFoods(query);
        if (_disposed || _query != query) return;
        _localResults = attachVariants(results);
        _notify();
      } catch (_) {
        if (_disposed) return;
        _localResults = const [];
        _notify();
      }
    });
  }

  Future<void> searchRemote(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.length < 2 || _isSearchingRemote) {
      if (query.isNotEmpty && query.length < 2 && !_disposed) {
        _showQueryTooShort = true;
        _notify();
      }
      return;
    }

    final generation = ++_remoteRequestGeneration;
    _isSearchingRemote = true;
    _remoteError = null;
    _showQueryTooShort = false;
    _notify();

    final elapsed = DateTime.now().difference(_lastRemoteSearchAt);
    if (elapsed < remoteMinInterval) {
      await Future<void>.delayed(remoteMinInterval - elapsed);
    }

    if (!_isCurrentRemoteRequest(generation, query)) return;
    _lastRemoteSearchAt = DateTime.now();
    final result = await gateway.search(query);
    if (!_isCurrentRemoteRequest(generation, query)) return;
    if (result.error != null) {
      _remoteResults = const [];
      _remoteError = result.error;
      _isSearchingRemote = false;
      _notify();
      return;
    }
    final hydrated = await _hydrateRemote(result.data ?? const []);
    if (!_isCurrentRemoteRequest(generation, query)) return;
    _remoteResults = mergeWithLocal(hydrated, _localResults);
    _isSearchingRemote = false;
    _remoteError = null;
    _notify();
    // The upsert refreshed the cached rows; reload the local section so
    // it never displays stale values for foods that were just updated.
    _scheduleLocal(query);
  }

  bool _isCurrentRemoteRequest(int generation, String query) {
    return !_disposed &&
        generation == _remoteRequestGeneration &&
        _query.trim() == query;
  }

  /// Persists each remote result (food + variant + servings) into the
  /// local cache so it shows up in future searches even offline, and
  /// returns the hydrated rows for display.
  Future<List<FoodSearchResult>> _hydrateRemote(
    List<FoodSearchResult> results,
  ) async {
    final hydrated = <FoodSearchResult>[];
    for (final result in results) {
      final variant = result.primaryVariant;
      if (variant == null) continue;
      try {
        await repository.upsertFoodWithDetails(
          food: result.food,
          variants: [variant],
          servings: {variant.id: result.servings},
        );
        hydrated.add(result);
      } catch (_) {
        // Skip foods that failed to persist rather than failing the
        // whole search.
      }
    }
    return hydrated;
  }

  static List<FoodSearchResult> attachVariants(List<dynamic> results) {
    return results.map<FoodSearchResult>((entry) {
      final primaryVariant = entry.primaryVariant as FoodVariant?;
      final servings = (entry.servings as Map<String, List<FoodServing>>);
      return FoodSearchResult(
        food: entry.food as Food,
        primaryVariant: primaryVariant,
        servings: primaryVariant == null
            ? const []
            : servings[primaryVariant.id] ?? const [],
        isRemote: false,
      );
    }).toList();
  }

  /// Remote results minus the foods already listed locally.
  @visibleForTesting
  static List<FoodSearchResult> mergeWithLocal(
    List<FoodSearchResult> remote,
    List<FoodSearchResult> local,
  ) {
    final keys = <String>{for (final r in local) r.food.dedupKey};
    return remote.where((r) => keys.add(r.food.dedupKey)).toList();
  }

  // ------------------------------------------------------------------
  // Meal target
  // ------------------------------------------------------------------

  String mealLabel(AppLocalizations loc) {
    final name = _selectedMealName;
    if (name != null && name.trim().isNotEmpty) return name;
    switch (_selectedMealType) {
      case MealType.breakfast:
        return loc.nutritionMealBreakfast;
      case MealType.lunch:
        return loc.nutritionMealLunch;
      case MealType.dinner:
        return loc.nutritionMealDinner;
      case MealType.snacks:
        return loc.nutritionMealSnacks;
    }
    return _selectedMealType ?? '';
  }

  /// Switches the meal the search adds to and reloads its suggestions.
  Future<void> selectMeal(MealTypeDefinition definition, String name) async {
    final mealType = definition.key;
    _selectedMealType = mealType;
    _selectedMealName = name;
    _mealSuggestions = const [];
    _suggestionsLoading = true;
    _notify();
    try {
      final suggestions = await repository.getMealSuggestions(mealType);
      if (_disposed || _selectedMealType != mealType) return;
      _mealSuggestions = attachVariants(suggestions);
      _suggestionsLoading = false;
      _notify();
    } catch (_) {
      if (!_disposed) {
        _suggestionsLoading = false;
        _notify();
      }
    }
  }

  /// [selection] tagged with the meal the search is bound to.
  NutritionSelection withSelectedMeal(NutritionSelection selection) {
    return NutritionSelection(
      food: selection.food,
      primaryVariant: selection.primaryVariant,
      servings: selection.servings,
      mealType: _selectedMealType,
      mealName: _selectedMealName,
    );
  }

  // ------------------------------------------------------------------
  // Selections and lookups
  // ------------------------------------------------------------------

  /// Selection for a food the user just created by hand, or null when it has
  /// no variant to log.
  Future<NutritionSelection?> selectionForCreatedFood(Food created) async {
    final details = await repository.getFoodWithDetails(created.id);
    if (details == null || details.variants.isEmpty) return null;
    final variant = details.variants.first;
    return NutritionSelection(
      food: details.food,
      primaryVariant: variant,
      servings: details.servings[variant.id] ?? const [],
    );
  }

  /// Resolves a scan: local cache first (no network for known products), then
  /// Open Food Facts by barcode, caching what it finds.
  Future<BarcodeLookup> lookupScannedCode(String rawCode) async {
    final code = extractProductCode(rawCode);
    if (code == null) {
      return const BarcodeLookup(BarcodeLookupKind.invalidCode);
    }
    // 1. Local cache: no network call needed for known products.
    final local = await repository.getFoodByBarcode(code);
    if (local != null) {
      final variant = local.variants.isEmpty ? null : local.variants.first;
      if (variant == null) {
        return const BarcodeLookup(BarcodeLookupKind.cachedWithoutVariant);
      }
      return BarcodeLookup(
        BarcodeLookupKind.found,
        selection: NutritionSelection(
          food: local.food,
          primaryVariant: variant,
          servings: local.servings[variant.id] ?? const [],
        ),
      );
    }
    // 2. Open Food Facts by barcode.
    final result = await gateway.getFood(FoodSource.openFoodFacts, code);
    if (result.error != null) {
      return BarcodeLookup(
        BarcodeLookupKind.gatewayError,
        errorCode: result.error!.code,
      );
    }
    final remote = result.data;
    final variant = remote?.primaryVariant;
    if (remote == null || variant == null) {
      return const BarcodeLookup(BarcodeLookupKind.notFound);
    }
    try {
      await repository.upsertFoodWithDetails(
        food: remote.food,
        variants: [variant],
        servings: {variant.id: remote.servings},
      );
    } catch (_) {}
    return BarcodeLookup(
      BarcodeLookupKind.found,
      selection: NutritionSelection(
        food: remote.food,
        primaryVariant: variant,
        servings: remote.servings,
      ),
    );
  }

  /// Extracts a product code from a raw scan. Handles plain barcodes
  /// and QR codes that encode an Open Food Facts product URL.
  static String? extractProductCode(String raw) {
    final trimmed = raw.trim();
    final urlMatch = RegExp(r'/product/(\d+)(?:[/?]|$)').firstMatch(trimmed);
    if (urlMatch != null) return urlMatch.group(1);
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    return digits.isEmpty ? null : digits;
  }

  /// Logs [meal] into [date] under the given meal section. Marks the
  /// controller as logging while the write runs.
  Future<({int added, int skipped})> logSavedMeal(
    SavedMealWithItems meal, {
    required String mealType,
    required String mealName,
  }) async {
    _isLoggingMeal = true;
    _notify();
    try {
      return await repository.addSavedMealToDate(
        date: date,
        mealType: mealType,
        mealName: mealName,
        savedMealId: meal.meal.id,
      );
    } finally {
      if (!_disposed) {
        _isLoggingMeal = false;
        _notify();
      }
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _localSearchDebounce?.cancel();
    super.dispose();
  }
}
