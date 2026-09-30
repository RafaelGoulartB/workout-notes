import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/nutrition/food.dart';
import 'package:workout_notes/models/nutrition/nutrition_selection.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/screens/nutrition/food_label_photo_screen.dart';
import 'package:workout_notes/screens/nutrition/manual_food_screen.dart';
import 'package:workout_notes/widgets/nutrition/nutrition_day_ui.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

enum _FoodLibraryAction { edit, delete }

enum _FoodLibraryCreateAction { scanWithAi, manual }

enum _FoodLibraryFilter { all, manual, database }

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
  _FoodLibraryFilter _activeFilter = _FoodLibraryFilter.all;
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

  Future<void> _scanFoodWithAi() async {
    final created = await Navigator.of(context).push<NutritionSelection>(
      MaterialPageRoute(
        builder: (_) => FoodLabelPhotoScreen(repository: widget.repository),
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

  Future<void> _editFood(FoodSearchResultLite entry) async {
    if (!entry.food.isUserCreated) return;
    final updated = await Navigator.of(context).push<Food>(
      MaterialPageRoute(
        builder: (_) => ManualFoodScreen(
          repository: widget.repository,
          existingFood: FoodWithDetails(
            food: entry.food,
            variants: entry.variants,
            servings: entry.servings,
          ),
        ),
      ),
    );
    if (updated != null) await _load();
  }

  Future<void> _deleteFood(FoodSearchResultLite entry) async {
    if (!entry.food.isUserCreated) return;
    final loc = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: loc.nutritionFoodDelete,
      message: loc.nutritionFoodDeleteConfirm(entry.food.name),
      confirmLabel: loc.commonDelete,
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.repository.deleteManualFood(entry.food.id);
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.nutritionFoodDeleted)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.commonError(e.toString()))));
    }
  }

  List<FoodSearchResultLite> get _visibleFoods {
    final query = Food.normalizeForSearch(_searchController.text);
    return _foods.where((entry) {
      final matchesSource = switch (_activeFilter) {
        _FoodLibraryFilter.all => true,
        _FoodLibraryFilter.manual => entry.food.isUserCreated,
        _FoodLibraryFilter.database => !entry.food.isUserCreated,
      };
      if (!matchesSource) return false;
      if (query.isEmpty) return true;
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
          PopupMenuButton<_FoodLibraryCreateAction>(
            tooltip: loc.nutritionAddItem,
            icon: const Icon(Icons.add_rounded),
            onSelected: (action) {
              switch (action) {
                case _FoodLibraryCreateAction.scanWithAi:
                  _scanFoodWithAi();
                case _FoodLibraryCreateAction.manual:
                  _createFood();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: _FoodLibraryCreateAction.scanWithAi,
                child: Row(
                  children: [
                    const Icon(Icons.document_scanner_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        loc.nutritionScanMeal,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: _FoodLibraryCreateAction.manual,
                child: Row(
                  children: [
                    const Icon(Icons.edit_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        loc.nutritionAddManually,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _foods.isEmpty
          ? AppEmptyState(
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
                _FoodLibraryFilters(
                  active: _activeFilter,
                  onSelected: (filter) =>
                      setState(() => _activeFilter = filter),
                ),
                const SizedBox(height: 8),
                Expanded(child: _buildList(loc)),
              ],
            ),
    );
  }

  Widget _buildList(AppLocalizations loc) {
    final foods = _visibleFoods;
    if (foods.isEmpty) {
      return AppEmptyState(
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
        separatorBuilder: (_, _) => const SizedBox(height: 6),
        itemBuilder: (context, index) => _FoodLibraryTile(
          entry: foods[index],
          onFavorite: () => _toggleFavorite(foods[index]),
          onEdit: foods[index].food.isUserCreated
              ? () => _editFood(foods[index])
              : null,
          onDelete: foods[index].food.isUserCreated
              ? () => _deleteFood(foods[index])
              : null,
        ),
      ),
    );
  }
}

class _FoodLibraryFilters extends StatelessWidget {
  final _FoodLibraryFilter active;
  final ValueChanged<_FoodLibraryFilter> onSelected;

  const _FoodLibraryFilters({required this.active, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: AppSegmentedTabs<_FoodLibraryFilter>(
        values: _FoodLibraryFilter.values,
        selected: active,
        labelOf: (filter) => switch (filter) {
          _FoodLibraryFilter.all => loc.nutritionSearchAll,
          _FoodLibraryFilter.manual => loc.nutritionSearchManual,
          _FoodLibraryFilter.database => loc.nutritionSearchDatabase,
        },
        onChanged: onSelected,
      ),
    );
  }
}

/// One food: icon, name, reference portion with calories and macros, the
/// source, a favorite star and (for user foods) an edit / delete menu.
/// Tapping a user food opens the editor.
class _FoodLibraryTile extends StatelessWidget {
  final FoodSearchResultLite entry;
  final VoidCallback onFavorite;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _FoodLibraryTile({
    required this.entry,
    required this.onFavorite,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final food = entry.food;
    final variant = entry.primaryVariant;
    final values = variant?.values;
    final calories = values?.calories;
    final favorite = food.isFavorite ?? false;
    final details = <String>[
      if (variant != null)
        '${nutritionNumber(variant.referenceAmount)} ${variant.referenceUnit}',
      if (calories != null) '${nutritionNumber(calories.roundToDouble())} kcal',
      if (food.brand?.trim().isNotEmpty ?? false) food.brand!.trim(),
    ];

    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 2, 10),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: colors.primaryContainer.withAlpha(140),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  food.isUserCreated
                      ? Icons.restaurant_rounded
                      : Icons.public_rounded,
                  color: colors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      food.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        ...details,
                        food.isUserCreated
                            ? loc.nutritionSourceManual
                            : loc.nutritionSourceGateway,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    if (values != null &&
                        (values.proteinG != null ||
                            values.carbsG != null ||
                            values.fatG != null)) ...[
                      const SizedBox(height: 5),
                      NutritionMacroLine(
                        proteinG: values.proteinG ?? 0,
                        carbsG: values.carbsG ?? 0,
                        fatG: values.fatG ?? 0,
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: favorite
                    ? loc.nutritionSearchUnfavorite
                    : loc.nutritionSearchFavorite,
                onPressed: onFavorite,
                icon: Icon(
                  favorite ? Icons.star_rounded : Icons.star_border_rounded,
                  size: 22,
                  color: favorite ? colors.primary : colors.onSurfaceVariant,
                ),
              ),
              if (onEdit != null && onDelete != null)
                PopupMenuButton<_FoodLibraryAction>(
                  tooltip: loc.nutritionFoodActions,
                  icon: Icon(
                    Icons.more_vert_rounded,
                    size: 20,
                    color: colors.onSurfaceVariant,
                  ),
                  onSelected: (action) {
                    switch (action) {
                      case _FoodLibraryAction.edit:
                        onEdit!();
                      case _FoodLibraryAction.delete:
                        onDelete!();
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: _FoodLibraryAction.edit,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.edit_outlined),
                        title: Text(loc.nutritionFoodEdit),
                      ),
                    ),
                    PopupMenuItem(
                      value: _FoodLibraryAction.delete,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.delete_outline),
                        title: Text(loc.nutritionFoodDelete),
                      ),
                    ),
                  ],
                )
              else
                const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}
