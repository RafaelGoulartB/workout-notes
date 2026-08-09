import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/nutrition/food.dart';
import 'package:workout_notes/models/nutrition/food_serving.dart';
import 'package:workout_notes/models/nutrition/food_search_result.dart';
import 'package:workout_notes/models/nutrition/food_variant.dart';
import 'package:workout_notes/models/nutrition/nutrition_selection.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/services/nutrition_gateway.dart';

import 'barcode_scan_screen.dart';
import 'food_label_photo_screen.dart';
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
  /// Remote searches are explicit (keyboard search action / search icon),
  /// because the Open Food Facts endpoint must not be used as type-ahead.
  /// The minimum interval also protects against repeatedly submitting the
  /// same field faster than the provider's anonymous rate limit.
  static const Duration _remoteMinInterval = Duration(seconds: 6);

  final TextEditingController _controller = TextEditingController();
  DateTime _lastRemoteSearchAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _remoteRequestGeneration = 0;

  List<FoodSearchResult> _localResults = const [];
  List<FoodSearchResult> _remoteResults = const [];
  bool _isSearchingRemote = false;
  NutritionGatewayError? _remoteError;
  bool _showQueryTooShort = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    // Invalidate a request that may still be in flight. Its response must
    // never be rendered under the newly typed query.
    _remoteRequestGeneration++;
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
    setState(() {
      _remoteResults = const [];
      _remoteError = null;
      _isSearchingRemote = false;
    });
    _scheduleLocal(value);
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
    Navigator.of(context).pop(
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
        Navigator.of(context).pop(
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
    Navigator.of(context).pop(
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
    Navigator.of(context).pop(result);
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
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.nutritionSearchTitle),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: loc.nutritionScanBarcode,
            onPressed: _scanBarcode,
            icon: const Icon(Icons.qr_code_scanner),
          ),
          IconButton(
            tooltip: loc.nutritionPhotoTitle,
            onPressed: _photoLabel,
            icon: const Icon(Icons.camera_alt_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                controller: _controller,
                autofocus: true,
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
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest
                      .withAlpha(80),
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: _searchRemote,
              ),
            ),
            if (_showQueryTooShort)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Text(
                  loc.nutritionSearchQueryTooShort,
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
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
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(AppLocalizations loc) {
    final theme = Theme.of(context);
    final hasAny = _localResults.isNotEmpty || _remoteResults.isNotEmpty;
    final hasRemoteBanner = _remoteError != null || _isSearchingRemote;
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
              itemBuilder: (_, index) => _FoodCard(result: _localResults[index]),
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
              itemBuilder: (_, index) => _FoodCard(result: _remoteResults[index]),
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
}

class _FoodCard extends StatelessWidget {
  final FoodSearchResult result;

  const _FoodCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final variant = result.primaryVariant;
    final isManual = result.food.isManual;
    final sourceColor = isManual
        ? theme.colorScheme.tertiaryContainer
        : theme.colorScheme.secondaryContainer;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withAlpha(80),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.of(context).pop(
            NutritionSelection(
              food: result.food,
              primaryVariant: variant,
              servings: result.servings,
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withAlpha(80),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.restaurant_outlined,
                  color: theme.colorScheme.onPrimaryContainer,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
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
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (result.food.brand != null &&
                            result.food.brand!.isNotEmpty)
                          result.food.brand!,
                        if (variant != null)
                          loc.nutritionPer100g(
                            variant.referenceAmount.toStringAsFixed(0),
                            variant.referenceUnit,
                          ),
                        if (variant?.values.calories != null)
                          '${variant!.values.calories!.toStringAsFixed(0)} kcal',
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: sourceColor.withAlpha(90),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isManual
                      ? loc.nutritionSourceManual
                      : loc.nutritionSourceGateway,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: isManual
                        ? theme.colorScheme.onTertiaryContainer
                        : theme.colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurfaceVariant.withAlpha(140),
              ),
            ],
          ),
        ),
      ),
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
