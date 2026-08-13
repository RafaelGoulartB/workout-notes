import 'dart:async';

import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/nutrition/food.dart';
import 'package:workout_notes/models/nutrition/food_serving.dart';
import 'package:workout_notes/models/nutrition/food_search_result.dart';
import 'package:workout_notes/models/nutrition/food_variant.dart';
import 'package:workout_notes/models/nutrition/meal_log.dart';
import 'package:workout_notes/models/nutrition/meal_type.dart';
import 'package:workout_notes/models/nutrition/nutrition_selection.dart';
import 'package:workout_notes/models/nutrition/saved_meal.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/services/nutrition_gateway.dart';

import 'barcode_scan_screen.dart';
import 'food_label_photo_screen.dart';
import 'manual_food_screen.dart';

enum _FoodSearchFilter { all, meals, favorites, myFoods }

/// Food search screen. Combines local cache + remote gateway results
/// with a debounce and explicit fallback messaging. Before any query
/// it surfaces favorites, recent foods and meal-specific suggestions.
class FoodSearchScreen extends StatefulWidget {
  final NutritionGateway gateway;
  final NutritionRepository repository;
  final bool enableManualButton;
  final String? mealType;

  /// Display name of the meal section this search adds items to (free
  /// text on newer builds; legacy fixed types fall back to the
  /// localized label).
  final String? mealName;

  /// Day (yyyy-MM-dd) that saved meals are logged into. Defaults to
  /// today when omitted.
  final String? date;

  const FoodSearchScreen({
    super.key,
    required this.gateway,
    required this.repository,
    this.enableManualButton = true,
    this.mealType,
    this.mealName,
    this.date,
  });

  @override
  State<FoodSearchScreen> createState() => _FoodSearchScreenState();
}

class _FoodSearchScreenState extends State<FoodSearchScreen> {
  /// Remote searches are explicit (keyboard search action / search icon),
  /// because the Open Food Facts endpoint must not be used as type-ahead.
  /// The minimum interval also protects against repeatedly submitting the
  /// same field faster than the provider's anonymous rate limit.
  static const Duration _remoteMinInterval = Duration(seconds: 6);

  final TextEditingController _controller = TextEditingController();
  Timer? _localSearchDebounce;
  DateTime _lastRemoteSearchAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _remoteRequestGeneration = 0;

  List<FoodSearchResult> _localResults = const [];
  List<FoodSearchResult> _remoteResults = const [];
  List<FoodSearchResult> _favorites = const [];
  List<FoodSearchResult> _recents = const [];
  List<FoodSearchResult> _allFoods = const [];
  List<FoodSearchResult> _mealSuggestions = const [];
  List<MealTypeDefinition> _mealTypes = const [];
  List<SavedMealWithItems> _savedMeals = const [];
  _FoodSearchFilter _activeFilter = _FoodSearchFilter.all;
  String? _selectedMealType;
  String? _selectedMealName;
  bool _suggestionsLoading = true;
  bool _isSearchingRemote = false;
  bool _isLoggingMeal = false;
  NutritionGatewayError? _remoteError;
  bool _showQueryTooShort = false;
  late String _date;

  @override
  void initState() {
    super.initState();
    _date = widget.date ?? _todayString();
    _selectedMealType = widget.mealType;
    _selectedMealName = widget.mealName;
    _controller.addListener(_onChanged);
    _loadSuggestions();
  }

  @override
  void dispose() {
    _localSearchDebounce?.cancel();
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadSuggestions() async {
    if (!mounted) return;
    try {
      final results = await Future.wait([
        widget.repository.getFavoriteFoods(),
        widget.repository.getRecentFoods(),
        widget.repository.getAllFoods(),
        widget.repository.getMealTypes(),
        widget.repository.getSavedMeals(),
        if (_selectedMealType != null)
          widget.repository.getMealSuggestions(_selectedMealType!),
      ]);
      if (!mounted) return;
      setState(() {
        _favorites = _attachVariants(results[0]);
        _recents = _attachVariants(results[1]);
        _allFoods = _attachVariants(results[2]);
        _mealTypes = results[3] as List<MealTypeDefinition>;
        _savedMeals = results[4] as List<SavedMealWithItems>;
        _mealSuggestions = _selectedMealType == null
            ? const []
            : _attachVariants(results[5]);
        _suggestionsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _suggestionsLoading = false);
    }
  }

  Future<void> _toggleFavorite(FoodSearchResult result) async {
    final currently = result.food.isFavorite ?? false;
    setState(() {
      // Optimistic update so the star reacts instantly.
      _replaceInLists(result, !currently);
    });
    try {
      await widget.repository.setFoodFavorite(result.food.id, !currently);
      await _loadSuggestions();
    } catch (_) {
      if (!mounted) return;
      setState(() => _replaceInLists(result, currently));
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

  void _onChanged() {
    // Invalidate a request that may still be in flight. Its response must
    // never be rendered under the newly typed query.
    _remoteRequestGeneration++;
    final value = _controller.text;
    if (value.trim().isNotEmpty) _activeFilter = _FoodSearchFilter.all;
    if (value.trim().length < 2) {
      setState(() {
        _localResults = const [];
        _remoteResults = const [];
        _remoteError = null;
        _isSearchingRemote = false;
        _showQueryTooShort = value.trim().isNotEmpty;
      });
      return;
    }
    setState(() {
      _remoteResults = const [];
      _remoteError = null;
      _isSearchingRemote = false;
    });
    _scheduleLocal(value);
  }

  void _scheduleLocal(String query) {
    setState(() => _showQueryTooShort = false);
    _localSearchDebounce?.cancel();
    // Debounce: one DB search + hydration per pause in typing instead
    // of one per keystroke.
    _localSearchDebounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        final results = await widget.repository.searchLocalFoods(query);
        if (!mounted || _controller.text != query) return;
        setState(() => _localResults = _attachVariants(results));
      } catch (_) {
        if (!mounted) return;
        setState(() => _localResults = const []);
      }
    });
  }

  Future<void> _searchRemote(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.length < 2 || _isSearchingRemote) {
      if (query.isNotEmpty && query.length < 2 && mounted) {
        setState(() => _showQueryTooShort = true);
      }
      return;
    }

    final generation = ++_remoteRequestGeneration;
    setState(() {
      _isSearchingRemote = true;
      _remoteError = null;
      _showQueryTooShort = false;
    });

    final elapsed = DateTime.now().difference(_lastRemoteSearchAt);
    if (elapsed < _remoteMinInterval) {
      await Future<void>.delayed(_remoteMinInterval - elapsed);
    }

    if (!_isCurrentRemoteRequest(generation, query)) return;
    _lastRemoteSearchAt = DateTime.now();
    final result = await widget.gateway.search(query);
    if (!_isCurrentRemoteRequest(generation, query)) return;
    if (result.error != null) {
      setState(() {
        _remoteResults = const [];
        _remoteError = result.error;
        _isSearchingRemote = false;
      });
      return;
    }
    final hydrated = await _hydrateRemote(result.data ?? const []);
    if (!_isCurrentRemoteRequest(generation, query)) return;
    setState(() {
      _remoteResults = _mergeWithLocal(hydrated, _localResults);
      _isSearchingRemote = false;
      _remoteError = null;
    });
    // The upsert refreshed the cached rows; reload the local section so
    // it never displays stale values for foods that were just updated.
    _scheduleLocal(query);
  }

  bool _isCurrentRemoteRequest(int generation, String query) {
    return mounted &&
        generation == _remoteRequestGeneration &&
        _controller.text.trim() == query;
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
        await widget.repository.upsertFoodWithDetails(
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

  List<FoodSearchResult> _attachVariants(List<dynamic> results) {
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

  List<FoodSearchResult> _mergeWithLocal(
    List<FoodSearchResult> remote,
    List<FoodSearchResult> local,
  ) {
    final keys = <String>{for (final r in local) r.food.dedupKey};
    return remote.where((r) => keys.add(r.food.dedupKey)).toList();
  }

  Future<void> _manualEntry() async {
    final created = await Navigator.of(context).push<Food>(
      MaterialPageRoute(
        builder: (_) => ManualFoodScreen(repository: widget.repository),
      ),
    );
    if (created == null || !mounted) return;
    final details = await widget.repository.getFoodWithDetails(created.id);
    if (!mounted) return;
    if (details == null || details.variants.isEmpty) return;
    final variant = details.variants.first;
    _returnSelection(
      NutritionSelection(
        food: details.food,
        primaryVariant: variant,
        servings: details.servings[variant.id] ?? const [],
      ),
    );
  }

  Future<void> _scanBarcode() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScanScreen()),
    );
    if (code == null || !mounted) return;
    await _handleScannedCode(code);
  }

  Future<void> _handleScannedCode(String rawCode) async {
    final loc = AppLocalizations.of(context)!;
    final code = _extractProductCode(rawCode);
    if (code == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.nutritionScanInvalid)));
      return;
    }
    // 1. Local cache: no network call needed for known products.
    final local = await widget.repository.getFoodByBarcode(code);
    if (local != null) {
      if (!mounted) return;
      final variant = local.variants.isEmpty ? null : local.variants.first;
      if (variant != null) {
        _returnSelection(
          NutritionSelection(
            food: local.food,
            primaryVariant: variant,
            servings: local.servings[variant.id] ?? const [],
          ),
        );
      }
      return;
    }
    // 2. Open Food Facts by barcode.
    final result = await widget.gateway.getFood(FoodSource.openFoodFacts, code);
    if (!mounted) return;
    if (result.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_barcodeErrorText(loc, result.error!.code))),
      );
      return;
    }
    final remote = result.data;
    final variant = remote?.primaryVariant;
    if (remote == null || variant == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.nutritionScanNotFound)));
      return;
    }
    try {
      await widget.repository.upsertFoodWithDetails(
        food: remote.food,
        variants: [variant],
        servings: {variant.id: remote.servings},
      );
    } catch (_) {}
    if (!mounted) return;
    _returnSelection(
      NutritionSelection(
        food: remote.food,
        primaryVariant: variant,
        servings: remote.servings,
      ),
    );
  }

  Future<void> _photoLabel() async {
    final result = await Navigator.of(context).push<NutritionSelection>(
      MaterialPageRoute(
        builder: (_) => FoodLabelPhotoScreen(repository: widget.repository),
      ),
    );
    if (result == null || !mounted) return;
    _returnSelection(result);
  }

  Future<void> _selectMeal(String mealType) async {
    final definition = _mealTypes.firstWhere((type) => type.key == mealType);
    final loc = AppLocalizations.of(context)!;
    setState(() {
      _selectedMealType = definition.key;
      _selectedMealName = definition.displayName(loc);
      _mealSuggestions = const [];
      _suggestionsLoading = true;
    });
    try {
      final suggestions = await widget.repository.getMealSuggestions(mealType);
      if (!mounted || _selectedMealType != mealType) return;
      setState(() {
        _mealSuggestions = _attachVariants(suggestions);
        _suggestionsLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _suggestionsLoading = false);
    }
  }

  void _returnSelection(NutritionSelection selection) {
    Navigator.of(context).pop(
      NutritionSelection(
        food: selection.food,
        primaryVariant: selection.primaryVariant,
        servings: selection.servings,
        mealType: _selectedMealType,
        mealName: _selectedMealName,
      ),
    );
  }

  void _selectFood(FoodSearchResult result) {
    if (result.primaryVariant == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.nutritionFoodNoVariant),
        ),
      );
      return;
    }
    _returnSelection(
      NutritionSelection(
        food: result.food,
        primaryVariant: result.primaryVariant,
        servings: result.servings,
      ),
    );
  }

  /// Logs a saved meal into the target day. When the search screen is
  /// bound to a specific meal section (opened from a per-meal row) the
  /// template goes straight there; otherwise the user picks a section
  /// from the configured meal catalog.
  Future<void> _logSavedMeal(SavedMealWithItems meal) async {
    final loc = AppLocalizations.of(context)!;
    String mealType;
    String mealName;
    if (_selectedMealType != null) {
      mealType = _selectedMealType!;
      mealName = _mealLabel(loc);
    } else if (_mealTypes.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.nutritionSavedMealNoMealTypes)),
      );
      return;
    } else {
      final picked = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text(loc.nutritionSavedMealPickMeal),
          children: [
            for (final type in _mealTypes)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, type.key),
                child: Text(type.displayName(loc)),
              ),
          ],
        ),
      );
      if (picked == null || !mounted) return;
      final type = _mealTypes.firstWhere((t) => t.key == picked);
      mealType = type.key;
      mealName = type.displayName(loc);
    }
    if (!mounted) return;
    setState(() => _isLoggingMeal = true);
    try {
      final result = await widget.repository.addSavedMealToDate(
        date: _date,
        mealType: mealType,
        mealName: mealName,
        savedMealId: meal.meal.id,
      );
      if (!mounted) return;
      final message = result.added == 0
          ? loc.nutritionSavedMealNothingLogged
          : (result.skipped > 0
                ? loc.nutritionSavedMealPartialLogged(
                    result.added,
                    result.skipped,
                  )
                : loc.nutritionSavedMealLogged(result.added));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.commonError(e.toString()))));
    } finally {
      if (mounted) setState(() => _isLoggingMeal = false);
    }
  }

  /// Extracts a product code from a raw scan. Handles plain barcodes
  /// and QR codes that encode an Open Food Facts product URL.
  static String? _extractProductCode(String raw) {
    final trimmed = raw.trim();
    final urlMatch = RegExp(r'/product/(\d+)(?:[/?]|$)').firstMatch(trimmed);
    if (urlMatch != null) return urlMatch.group(1);
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    return digits.isEmpty ? null : digits;
  }

  static String _barcodeErrorText(AppLocalizations loc, String code) {
    switch (code) {
      case 'not_found':
        return loc.nutritionScanNotFound;
      case 'rate_limited':
        return loc.nutritionRateLimited;
      case 'network':
        return loc.nutritionScanNetwork;
      default:
        return loc.nutritionScanError;
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final mealLabel = _mealLabel(loc);
    return Scaffold(
      appBar: AppBar(
        title: PopupMenuButton<String>(
          tooltip: loc.nutritionSearchChooseMeal,
          initialValue: _selectedMealType,
          onSelected: _selectMeal,
          itemBuilder: (context) => [
            for (final meal in _mealTypes)
              PopupMenuItem(
                value: meal.key,
                child: Row(
                  children: [
                    if (meal.key == _selectedMealType) ...[
                      Icon(
                        Icons.check_rounded,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(meal.displayName(loc)),
                  ],
                ),
              ),
          ],
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  mealLabel.isEmpty ? loc.nutritionSearchTitle : mealLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_mealTypes.isNotEmpty) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_drop_down_rounded,
                  color: theme.colorScheme.primary,
                ),
              ],
            ],
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
              child: TextField(
                controller: _controller,
                autofocus: false,
                decoration: InputDecoration(
                  hintText: loc.nutritionSearchHint,
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: IconButton(
                    tooltip: loc.nutritionSearchTitle,
                    onPressed: _isSearchingRemote
                        ? null
                        : () => _searchRemote(_controller.text),
                    icon: const Icon(Icons.arrow_forward_rounded),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: BorderSide(color: theme.colorScheme.outline),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerLow,
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: _searchRemote,
              ),
            ),
            _FoodSearchFilters(
              active: _activeFilter,
              onSelected: (filter) {
                if (_controller.text.isNotEmpty) _controller.clear();
                setState(() => _activeFilter = filter);
              },
            ),
            _FoodSearchActions(
              onPhoto: _photoLabel,
              onBarcode: _scanBarcode,
              onManual: widget.enableManualButton ? _manualEntry : null,
            ),
            if (_showQueryTooShort)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Text(
                  loc.nutritionSearchQueryTooShort,
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            if (_isSearchingRemote) const LinearProgressIndicator(),
            Expanded(child: _buildResults(loc)),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(AppLocalizations loc) {
    final theme = Theme.of(context);
    final query = _controller.text.trim();
    final hasAny = _localResults.isNotEmpty || _remoteResults.isNotEmpty;
    final hasRemoteBanner = _remoteError != null || _isSearchingRemote;

    // Before the user types: favorites, meal-specific suggestions and
    // recents take over the empty state.
    if (query.isEmpty && !_showQueryTooShort) {
      final showFavorites =
          (_activeFilter == _FoodSearchFilter.all ||
              _activeFilter == _FoodSearchFilter.favorites) &&
          _favorites.isNotEmpty;
      final showMeal =
          _activeFilter == _FoodSearchFilter.all &&
          _selectedMealType != null &&
          _mealSuggestions.isNotEmpty;
      final showRecents =
          _activeFilter == _FoodSearchFilter.all && _recents.isNotEmpty;
      final showAllFoods =
          _activeFilter == _FoodSearchFilter.myFoods && _allFoods.isNotEmpty;
      final showSavedMeals = _activeFilter == _FoodSearchFilter.meals;
      final hasSuggestions =
          showFavorites ||
          showMeal ||
          showRecents ||
          showAllFoods ||
          (showSavedMeals && _savedMeals.isNotEmpty);
      return CustomScrollView(
        slivers: [
          if (showFavorites) ...[
            SliverToBoxAdapter(
              child: _SectionHeader(text: loc.nutritionSearchFavorites),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              sliver: SliverList.separated(
                itemCount: _favorites.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (_, index) => _FoodCard(
                  result: _favorites[index],
                  onSelected: () => _selectFood(_favorites[index]),
                  onToggleFavorite: () => _toggleFavorite(_favorites[index]),
                ),
              ),
            ),
          ],
          if (showMeal) ...[
            SliverToBoxAdapter(
              child: _SectionHeader(
                text: loc.nutritionSearchSuggestedFor(_mealLabel(loc)),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              sliver: SliverList.separated(
                itemCount: _mealSuggestions.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (_, index) => _FoodCard(
                  result: _mealSuggestions[index],
                  onSelected: () => _selectFood(_mealSuggestions[index]),
                  onToggleFavorite: () =>
                      _toggleFavorite(_mealSuggestions[index]),
                ),
              ),
            ),
          ],
          if (showRecents) ...[
            SliverToBoxAdapter(
              child: _HistoryHeader(
                title: loc.nutritionSearchHistory,
                sortLabel: loc.nutritionSearchMostRecent,
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              sliver: SliverList.separated(
                itemCount: _recents.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (_, index) => _FoodCard(
                  result: _recents[index],
                  onSelected: () => _selectFood(_recents[index]),
                  onToggleFavorite: () => _toggleFavorite(_recents[index]),
                ),
              ),
            ),
          ],
          if (showAllFoods) ...[
            SliverToBoxAdapter(
              child: _SectionHeader(text: loc.nutritionSearchMyFoods),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              sliver: SliverList.separated(
                itemCount: _allFoods.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (_, index) => _FoodCard(
                  result: _allFoods[index],
                  onSelected: () => _selectFood(_allFoods[index]),
                  onToggleFavorite: () => _toggleFavorite(_allFoods[index]),
                ),
              ),
            ),
          ],
          if (showSavedMeals) ...[
            SliverToBoxAdapter(
              child: _SectionHeader(text: loc.nutritionSavedMeals),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              sliver: SliverList.separated(
                itemCount: _savedMeals.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (_, index) => _SavedMealCard(
                  meal: _savedMeals[index],
                  isLogging: _isLoggingMeal,
                  onSelected: () => _logSavedMeal(_savedMeals[index]),
                ),
              ),
            ),
          ],
          if (!hasSuggestions && !_suggestionsLoading)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        showSavedMeals
                            ? Icons.restaurant_menu_outlined
                            : Icons.restaurant_menu_rounded,
                        size: 80,
                        color: theme.colorScheme.primary.withAlpha(80),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        showSavedMeals
                            ? loc.nutritionSavedMealsEmptyTitle
                            : loc.nutritionSearchEmpty,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        showSavedMeals
                            ? loc.nutritionSavedMealsEmptySubtitle
                            : loc.nutritionSearchEmptyHint,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    }

    return CustomScrollView(
      slivers: [
        if (_remoteError?.code == 'rate_limited')
          SliverToBoxAdapter(
            child: _InfoBanner(
              icon: Icons.hourglass_top,
              text: loc.nutritionRateLimited,
            ),
          )
        else if (_remoteError != null)
          SliverToBoxAdapter(
            child: _InfoBanner(
              icon: Icons.error_outline,
              text: loc.nutritionSearchUnavailable,
            ),
          )
        else if (_isSearchingRemote)
          SliverToBoxAdapter(
            child: _InfoBanner(
              icon: Icons.cloud_sync_outlined,
              text: loc.nutritionSearchLoading,
            ),
          ),
        if (_localResults.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _SectionHeader(text: loc.nutritionSearchLocalResults),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverList.separated(
              itemCount: _localResults.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (_, index) => _FoodCard(
                result: _localResults[index],
                onSelected: () => _selectFood(_localResults[index]),
                onToggleFavorite: () => _toggleFavorite(_localResults[index]),
              ),
            ),
          ),
        ],
        if (_remoteResults.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _SectionHeader(text: loc.nutritionSearchRemoteResults),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            sliver: SliverList.separated(
              itemCount: _remoteResults.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (_, index) => _FoodCard(
                result: _remoteResults[index],
                onSelected: () => _selectFood(_remoteResults[index]),
              ),
            ),
          ),
        ],
        if (!hasAny && !hasRemoteBanner && !_showQueryTooShort)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.restaurant_menu_rounded,
                      size: 80,
                      color: theme.colorScheme.primary.withAlpha(80),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      loc.nutritionSearchEmpty,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      loc.nutritionSearchEmptyHint,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (hasAny) const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  String _mealLabel(AppLocalizations loc) {
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

  static String _todayString() {
    final now = DateTime.now();
    return DateTime(
      now.year,
      now.month,
      now.day,
    ).toIso8601String().substring(0, 10);
  }
}

class _FoodSearchFilters extends StatelessWidget {
  final _FoodSearchFilter active;
  final ValueChanged<_FoodSearchFilter> onSelected;

  const _FoodSearchFilters({required this.active, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final labels = <_FoodSearchFilter, String>{
      _FoodSearchFilter.all: loc.nutritionSearchAll,
      _FoodSearchFilter.meals: loc.nutritionSearchMyMeals,
      _FoodSearchFilter.favorites: loc.nutritionSearchFavorites,
      _FoodSearchFilter.myFoods: loc.nutritionSearchMyFoods,
    };
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final entry in labels.entries)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: ChoiceChip(
                label: Text(entry.value),
                selected: active == entry.key,
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => onSelected(entry.key),
              ),
            ),
        ],
      ),
    );
  }
}

class _FoodSearchActions extends StatelessWidget {
  final VoidCallback onPhoto;
  final VoidCallback onBarcode;
  final VoidCallback? onManual;

  const _FoodSearchActions({
    required this.onPhoto,
    required this.onBarcode,
    required this.onManual,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Container(
      height: 92,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(vertical: 9),
      color: theme.colorScheme.primaryContainer.withAlpha(42),
      child: Row(
        children: [
          Expanded(
            child: _SearchActionCard(
              icon: Icons.center_focus_strong_rounded,
              label: loc.nutritionScanMeal,
              onTap: onPhoto,
            ),
          ),
          Expanded(
            child: _SearchActionCard(
              icon: Icons.qr_code_scanner_rounded,
              label: loc.nutritionScanBarcode,
              onTap: onBarcode,
            ),
          ),
          if (onManual != null)
            Expanded(
              child: _SearchActionCard(
                icon: Icons.edit_note_rounded,
                label: loc.nutritionAddManually,
                onTap: onManual!,
              ),
            ),
        ],
      ),
    );
  }
}

class _SearchActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SearchActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Material(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 25, color: theme.colorScheme.primary),
              const SizedBox(height: 5),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                    height: 1.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FoodCard extends StatelessWidget {
  final FoodSearchResult result;
  final VoidCallback onSelected;
  final VoidCallback? onToggleFavorite;

  const _FoodCard({
    required this.result,
    required this.onSelected,
    this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final variant = result.primaryVariant;
    final details = <String>[
      if (variant?.values.calories != null)
        '${variant!.values.calories!.toStringAsFixed(0)} kcal',
      if (result.food.brand != null && result.food.brand!.isNotEmpty)
        result.food.brand!,
      if (variant != null)
        loc.nutritionPer100g(
          variant.referenceAmount.toStringAsFixed(0),
          variant.referenceUnit,
        ),
    ].join(' · ');

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onSelected,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.food.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (details.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        details,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              if (result.food.isFavorite != null)
                IconButton(
                  tooltip: result.food.isFavorite!
                      ? loc.nutritionSearchUnfavorite
                      : loc.nutritionSearchFavorite,
                  onPressed: onToggleFavorite,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    result.food.isFavorite!
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    size: 18,
                    color: result.food.isFavorite!
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withAlpha(65),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.add_rounded,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A saved meal template shown under the "Meals" filter. Tapping the
/// card logs the whole template into the target day's meal section.
class _SavedMealCard extends StatelessWidget {
  final SavedMealWithItems meal;
  final bool isLogging;
  final VoidCallback onSelected;

  const _SavedMealCard({
    required this.meal,
    required this.isLogging,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final totals = meal.totals;
    final subtitle = <String>[
      if (meal.meal.mealType != null) _mealTypeLabel(loc, meal.meal.mealType!),
      if (meal.meal.portions != 1)
        loc.nutritionSavedMealPortionsLabel(_format(meal.meal.portions)),
      if (totals?.calories != null)
        loc.nutritionConsumedKcal(_format(totals!.calories!)),
    ].join(' · ');
    final macros = <String>[
      if (totals?.proteinG != null) 'P ${_format(totals!.proteinG!)} g',
      if (totals?.carbsG != null) 'C ${_format(totals!.carbsG!)} g',
      if (totals?.fatG != null) 'G ${_format(totals!.fatG!)} g',
    ].join(' · ');

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: isLogging ? null : onSelected,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withAlpha(90),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.restaurant_menu,
                  color: theme.colorScheme.onPrimaryContainer,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meal.meal.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (macros.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        macros,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              if (isLogging)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withAlpha(65),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.add_rounded,
                    color: theme.colorScheme.primary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _mealTypeLabel(AppLocalizations loc, String type) {
    switch (type) {
      case MealType.breakfast:
        return loc.nutritionMealBreakfast;
      case MealType.lunch:
        return loc.nutritionMealLunch;
      case MealType.dinner:
        return loc.nutritionMealDinner;
      case MealType.snacks:
        return loc.nutritionMealSnacks;
    }
    return type;
  }

  static String _format(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(1);
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader({required this.text});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _HistoryHeader extends StatelessWidget {
  final String title;
  final String sortLabel;

  const _HistoryHeader({required this.title, required this.sortLabel});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.sort_rounded,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  sortLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoBanner({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withAlpha(70),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
