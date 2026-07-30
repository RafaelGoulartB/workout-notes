import 'dart:async';

import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/nutrition/food.dart';
import 'package:workout_notes/models/nutrition/food_serving.dart';
import 'package:workout_notes/models/nutrition/food_search_result.dart';
import 'package:workout_notes/models/nutrition/food_variant.dart';
import 'package:workout_notes/models/nutrition/nutrition_selection.dart';
import 'package:workout_notes/models/nutrition/nutrition_values.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/services/nutrition_gateway.dart';

import 'manual_food_screen.dart';

/// Food search screen. Combines local cache + remote gateway results
/// with a debounce and explicit fallback messaging.
class FoodSearchScreen extends StatefulWidget {
  final NutritionGateway gateway;
  final NutritionRepository repository;
  final bool enableManualButton;

  const FoodSearchScreen({
    super.key,
    required this.gateway,
    required this.repository,
    this.enableManualButton = true,
  });

  @override
  State<FoodSearchScreen> createState() => _FoodSearchScreenState();
}

class _FoodSearchScreenState extends State<FoodSearchScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;

  List<FoodSearchResult> _localResults = const [];
  List<FoodSearchResult> _remoteResults = const [];
  bool _isSearchingRemote = false;
  NutritionGatewayError? _remoteError;
  String _lastQuery = '';
  bool _showQueryTooShort = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    _debounce?.cancel();
    final value = _controller.text;
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
    _scheduleLocal(value);
    _scheduleRemote(value);
  }

  void _scheduleLocal(String query) {
    setState(() => _showQueryTooShort = false);
    Future<void>(() async {
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

  void _scheduleRemote(String query) {
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted || _controller.text != query) return;
      setState(() {
        _isSearchingRemote = true;
        _remoteError = null;
        _lastQuery = query;
      });
      final result = await widget.gateway.search(query);
      if (!mounted || _controller.text != _lastQuery) return;
      if (result.error != null) {
        setState(() {
          _remoteResults = const [];
          _remoteError = result.error;
          _isSearchingRemote = false;
        });
        return;
      }
      final foods = result.data ?? const <Food>[];
      final hydrated = await _hydrateRemote(foods);
      if (!mounted || _controller.text != _lastQuery) return;
      setState(() {
        _remoteResults = _mergeWithLocal(hydrated, _localResults);
        _isSearchingRemote = false;
        _remoteError = null;
      });
    });
  }

  Future<List<FoodSearchResult>> _hydrateRemote(List<Food> foods) async {
    final result = <FoodSearchResult>[];
    for (final food in foods) {
      final persisted = await widget.repository.upsertFoodWithDetails(
        food: food,
        variants: [
          FoodVariant(
            id: 'remote_default',
            foodId: food.id,
            referenceAmount: 100,
            referenceUnit: 'g',
            values: NutritionValues.empty,
            isEstimated: false,
          ),
        ],
      );
      final details = await widget.repository.getFoodWithDetails(persisted.id);
      if (details == null) continue;
      final primary = details.variants.isEmpty ? null : details.variants.first;
      result.add(
        FoodSearchResult(
          food: details.food,
          primaryVariant: primary,
          servings: primary == null
              ? const []
              : details.servings[primary.id] ?? const [],
          isRemote: true,
        ),
      );
    }
    return result;
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
    Navigator.of(context).pop(
      NutritionSelection(
        food: created,
        primaryVariant: null,
        servings: const [],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(loc.nutritionSearchTitle), centerTitle: true),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _controller,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: loc.nutritionSearchHint,
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.search,
              ),
            ),
            if (_showQueryTooShort)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  loc.nutritionSearchQueryTooShort,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (_isSearchingRemote) const LinearProgressIndicator(),
            Expanded(child: _buildResults(loc)),
            if (widget.enableManualButton)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: FilledButton.tonalIcon(
                    onPressed: _manualEntry,
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(loc.nutritionAddManually),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(AppLocalizations loc) {
    final hasAny = _localResults.isNotEmpty || _remoteResults.isNotEmpty;
    final hasRemoteBanner = _remoteError != null || _isSearchingRemote;
    return CustomScrollView(
      slivers: [
        if (_remoteError?.code == 'not_configured')
          SliverToBoxAdapter(
            child: _InfoBanner(
              icon: Icons.cloud_off_outlined,
              text: loc.nutritionSearchNotConfigured,
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
          SliverList.separated(
            itemCount: _localResults.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, index) => _FoodRow(result: _localResults[index]),
          ),
        ],
        if (_remoteResults.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _SectionHeader(text: loc.nutritionSearchRemoteResults),
          ),
          SliverList.separated(
            itemCount: _remoteResults.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, index) => _FoodRow(result: _remoteResults[index]),
          ),
        ],
        if (!hasAny && !hasRemoteBanner && !_showQueryTooShort)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  loc.nutritionSearchEmpty,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _FoodRow extends StatelessWidget {
  final FoodSearchResult result;

  const _FoodRow({required this.result});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final variant = result.primaryVariant;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Icon(
          Icons.restaurant_outlined,
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
      title: Text(result.food.name),
      subtitle: Text(
        [
          if (result.food.brand != null && result.food.brand!.isNotEmpty)
            result.food.brand!,
          if (variant != null)
            loc.nutritionPer100g(
              variant.referenceAmount.toStringAsFixed(0),
              variant.referenceUnit,
            ),
          if (variant?.values.calories != null)
            '${variant!.values.calories!.toStringAsFixed(0)} kcal',
        ].join(' · '),
      ),
      trailing: Text(
        result.food.isManual
            ? loc.nutritionSourceManual
            : loc.nutritionSourceGateway,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      onTap: () {
        Navigator.of(context).pop(
          NutritionSelection(
            food: result.food,
            primaryVariant: variant,
            servings: result.servings,
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader({required this.text});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
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

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoBanner({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
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
    );
  }
}
