import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/nutrition/food.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/widgets/empty_state_placeholder.dart';

import 'manual_food_screen.dart';

/// Browsable list of every food stored on the device.
class FoodLibraryScreen extends StatefulWidget {
  final NutritionRepository repository;

  const FoodLibraryScreen({super.key, required this.repository});

  @override
  State<FoodLibraryScreen> createState() => _FoodLibraryScreenState();
}

class _FoodLibraryScreenState extends State<FoodLibraryScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<FoodSearchResultLite> _foods = const [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _load();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() => setState(() {});

  Future<void> _load() async {
    final foods = await widget.repository.getAllFoods();
    if (!mounted) return;
    setState(() {
      _foods = foods;
      _isLoading = false;
    });
  }

  Future<void> _createFood() async {
    final created = await Navigator.of(context).push<Food>(
      MaterialPageRoute(
        builder: (_) => ManualFoodScreen(repository: widget.repository),
      ),
    );
    if (created != null) await _load();
  }

  Future<void> _toggleFavorite(FoodSearchResultLite entry) async {
    await widget.repository.setFoodFavorite(
      entry.food.id,
      !(entry.food.isFavorite ?? false),
    );
    await _load();
  }

  List<FoodSearchResultLite> get _visibleFoods {
    final query = Food.normalizeForSearch(_searchController.text);
    if (query.isEmpty) return _foods;
    return _foods.where((entry) {
      final brand = Food.normalizeForSearch(entry.food.brand ?? '');
      return entry.food.searchName.contains(query) || brand.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.nutritionFoodLibraryTitle),
        actions: [
          IconButton(
            tooltip: loc.nutritionHomeManualFood,
            onPressed: _createFood,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _foods.isEmpty
          ? EmptyStatePlaceholder(
              icon: Icons.restaurant_menu_outlined,
              title: loc.nutritionFoodLibraryEmptyTitle,
              subtitle: loc.nutritionFoodLibraryEmptySubtitle,
              actionLabel: loc.nutritionHomeManualFood,
              onAction: _createFood,
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: SearchBar(
                    controller: _searchController,
                    hintText: loc.nutritionFoodLibrarySearchHint,
                    leading: const Icon(Icons.search_rounded),
                    trailing: [
                      if (_searchController.text.isNotEmpty)
                        IconButton(
                          tooltip: loc.nutritionFoodLibraryClearSearch,
                          onPressed: _searchController.clear,
                          icon: const Icon(Icons.close_rounded),
                        ),
                    ],
                  ),
                ),
                Expanded(child: _buildList(loc)),
              ],
            ),
    );
  }

  Widget _buildList(AppLocalizations loc) {
    final foods = _visibleFoods;
    if (foods.isEmpty) {
      return EmptyStatePlaceholder(
        icon: Icons.search_off_rounded,
        title: loc.nutritionFoodLibraryNoResults,
        subtitle: loc.nutritionFoodLibraryNoResultsSubtitle,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: foods.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) => _FoodLibraryTile(
          entry: foods[index],
          onFavorite: () => _toggleFavorite(foods[index]),
        ),
      ),
    );
  }
}

class _FoodLibraryTile extends StatelessWidget {
  final FoodSearchResultLite entry;
  final VoidCallback onFavorite;

  const _FoodLibraryTile({required this.entry, required this.onFavorite});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final food = entry.food;
    final variant = entry.primaryVariant;
    final calories = variant?.values.calories;
    final details = <String>[
      if (food.brand?.trim().isNotEmpty ?? false) food.brand!.trim(),
      if (variant != null)
        '${_format(variant.referenceAmount)} ${variant.referenceUnit}'
            '${calories == null ? '' : ' · ${_format(calories)} kcal'}',
      food.isManual ? loc.nutritionSourceManual : loc.nutritionSourceGateway,
    ];

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          foregroundColor: theme.colorScheme.onPrimaryContainer,
          child: const Icon(Icons.restaurant_outlined),
        ),
        title: Text(
          food.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          details.join('\n'),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: IconButton(
          tooltip: (food.isFavorite ?? false)
              ? loc.nutritionSearchUnfavorite
              : loc.nutritionSearchFavorite,
          onPressed: onFavorite,
          icon: Icon(
            (food.isFavorite ?? false)
                ? Icons.star_rounded
                : Icons.star_border_rounded,
            color: (food.isFavorite ?? false)
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  static String _format(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
}
