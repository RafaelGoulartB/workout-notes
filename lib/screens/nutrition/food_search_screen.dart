import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/nutrition/food.dart';
import 'package:workout_notes/models/nutrition/food_search_result.dart';
import 'package:workout_notes/models/nutrition/nutrition_selection.dart';
import 'package:workout_notes/models/nutrition/saved_meal.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/screens/nutrition/barcode_scan_screen.dart';
import 'package:workout_notes/screens/nutrition/food_label_photo_screen.dart';
import 'package:workout_notes/screens/nutrition/food_search_controller.dart';
import 'package:workout_notes/screens/nutrition/manual_food_screen.dart';
import 'package:workout_notes/services/nutrition_gateway.dart';
import 'package:workout_notes/widgets/nutrition/food_search/food_search_controls.dart';
import 'package:workout_notes/widgets/nutrition/food_search/food_search_results.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

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
  final TextEditingController _textController = TextEditingController();
  late final FoodSearchController _controller;

  @override
  void initState() {
    super.initState();
    _controller = FoodSearchController(
      gateway: widget.gateway,
      repository: widget.repository,
      mealType: widget.mealType,
      mealName: widget.mealName,
      date: widget.date,
    );
    _textController.addListener(_onTextChanged);
    _controller.loadSuggestions();
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() => _controller.onQueryChanged(_textController.text);

  Future<void> _manualEntry() async {
    final created = await Navigator.of(context).push<Food>(
      MaterialPageRoute(
        builder: (_) => ManualFoodScreen(repository: widget.repository),
      ),
    );
    if (created == null || !mounted) return;
    final selection = await _controller.selectionForCreatedFood(created);
    if (!mounted) return;
    if (selection == null) return;
    _returnSelection(selection);
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
    if (FoodSearchController.extractProductCode(rawCode) == null) {
      showAppSnack(context, loc.nutritionScanInvalid);
      return;
    }
    final lookup = await _controller.lookupScannedCode(rawCode);
    if (!mounted) return;
    switch (lookup.kind) {
      case BarcodeLookupKind.invalidCode:
        showAppSnack(context, loc.nutritionScanInvalid);
      case BarcodeLookupKind.cachedWithoutVariant:
        break;
      case BarcodeLookupKind.gatewayError:
        showAppSnack(context, _barcodeErrorText(loc, lookup.errorCode!));
      case BarcodeLookupKind.notFound:
        showAppSnack(context, loc.nutritionScanNotFound);
      case BarcodeLookupKind.found:
        _returnSelection(lookup.selection!);
    }
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

  Future<void> _selectMeal(String mealType) {
    final definition = _controller.mealTypes.firstWhere(
      (type) => type.key == mealType,
    );
    final loc = AppLocalizations.of(context)!;
    return _controller.selectMeal(definition, definition.displayName(loc));
  }

  void _returnSelection(NutritionSelection selection) {
    Navigator.of(context).pop(_controller.withSelectedMeal(selection));
  }

  void _selectFood(FoodSearchResult result) {
    if (result.primaryVariant == null) {
      if (!mounted) return;
      showAppSnack(
        context,
        AppLocalizations.of(context)!.nutritionFoodNoVariant,
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
    if (_controller.selectedMealType != null) {
      mealType = _controller.selectedMealType!;
      mealName = _controller.mealLabel(loc);
    } else if (_controller.mealTypes.isEmpty) {
      if (!mounted) return;
      showAppSnack(context, loc.nutritionSavedMealNoMealTypes);
      return;
    } else {
      final mealTypes = _controller.mealTypes;
      final picked = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text(loc.nutritionSavedMealPickMeal),
          children: [
            for (final type in mealTypes)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, type.key),
                child: Text(type.displayName(loc)),
              ),
          ],
        ),
      );
      if (picked == null || !mounted) return;
      final type = _controller.mealTypes.firstWhere((t) => t.key == picked);
      mealType = type.key;
      mealName = type.displayName(loc);
    }
    if (!mounted) return;
    try {
      final result = await _controller.logSavedMeal(
        meal,
        mealType: mealType,
        mealName: mealName,
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
      showAppSnack(context, message);
    } catch (e, stack) {
      debugPrint('food_search_screen: action failed: $e\n$stack');
      if (!mounted) return;
      showAppSnack(context, loc.commonSomethingWentWrong);
    }
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
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => _buildScreen(context),
    );
  }

  Widget _buildScreen(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final controller = _controller;
    final mealLabel = controller.mealLabel(loc);
    final mealTypes = controller.mealTypes;
    final selectedMealType = controller.selectedMealType;
    return Scaffold(
      appBar: AppBar(
        title: PopupMenuButton<String>(
          tooltip: loc.nutritionSearchChooseMeal,
          initialValue: selectedMealType,
          onSelected: _selectMeal,
          itemBuilder: (context) => [
            for (final meal in mealTypes)
              PopupMenuItem(
                value: meal.key,
                child: Row(
                  children: [
                    if (meal.key == selectedMealType) ...[
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
              if (mealTypes.isNotEmpty) ...[
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
                controller: _textController,
                autofocus: false,
                decoration: InputDecoration(
                  hintText: loc.nutritionSearchHint,
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: IconButton(
                    tooltip: loc.nutritionSearchTitle,
                    onPressed: controller.isSearchingRemote
                        ? null
                        : () => controller.searchRemote(_textController.text),
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
                onSubmitted: controller.searchRemote,
              ),
            ),
            FoodSearchFilters(
              active: controller.activeFilter,
              onSelected: (filter) {
                if (_textController.text.isNotEmpty) _textController.clear();
                controller.setFilter(filter);
              },
            ),
            FoodSearchActions(
              onPhoto: _photoLabel,
              onBarcode: _scanBarcode,
              onManual: widget.enableManualButton ? _manualEntry : null,
            ),
            if (controller.showQueryTooShort)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Text(
                  loc.nutritionSearchQueryTooShort,
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            if (controller.isSearchingRemote) const LinearProgressIndicator(),
            Expanded(
              child: FoodSearchResultsView(
                controller: controller,
                mealLabel: mealLabel,
                onSelectFood: _selectFood,
                onLogSavedMeal: _logSavedMeal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
