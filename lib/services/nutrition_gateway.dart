import 'package:uuid/uuid.dart';

import 'package:workout_notes/models/nutrition/food.dart';
import 'package:workout_notes/models/nutrition/food_search_result.dart';
import 'package:workout_notes/models/nutrition/food_serving.dart';
import 'package:workout_notes/models/nutrition/food_variant.dart';
import 'package:workout_notes/models/nutrition/nutrition_values.dart';

/// Result of a gateway call: either a list of food records, an
/// explicit "not configured" state, or a structured error.
class NutritionGatewayResult<T> {
  final T? data;
  final NutritionGatewayError? error;

  const NutritionGatewayResult._(this.data, this.error);

  bool get ok => error == null;
  bool get notConfigured => error?.code == 'not_configured';

  factory NutritionGatewayResult.ok(T data) =>
      NutritionGatewayResult<T>._(data, null);
  factory NutritionGatewayResult.error(NutritionGatewayError error) =>
      NutritionGatewayResult<T>._(null, error);
}

class NutritionGatewayError {
  final String code;
  final String message;
  const NutritionGatewayError(this.code, this.message);
  @override
  String toString() => 'NutritionGatewayError($code): $message';
}

/// Abstract gateway contract used by the nutrition module. Each
/// implementation talks to one external provider (Open Food Facts,
/// USDA, FatSecret, …).
///
/// Results are rich: each [FoodSearchResult] carries the food plus its
/// primary variant (with the nutrition values) and any servings, so
/// the UI can persist and display provider data without a second call.
abstract class NutritionGateway {
  Future<NutritionGatewayResult<List<FoodSearchResult>>> search(
    String query, {
    int limit = 20,
  });

  Future<NutritionGatewayResult<FoodSearchResult>> getFood(
    String source,
    String externalId,
  );

  String? get baseUrl;
}

/// JSON shape returned by `GET /foods/search`.
///
/// The response is `{ "results": [ {<food payload>} ] }`. See
/// [NutritionGatewayFoodPayload] for the per-item schema.
class NutritionGatewaySearchPayload {
  final List<NutritionGatewayFoodPayload> results;

  const NutritionGatewaySearchPayload({required this.results});

  factory NutritionGatewaySearchPayload.fromJson(Map<String, dynamic> json) {
    final raw = json['results'] ?? json['foods'] ?? json['data'];
    final list = raw is List ? raw : const [];
    final results = <NutritionGatewayFoodPayload>[];
    for (final item in list) {
      if (item is Map) {
        try {
          results.add(
            NutritionGatewayFoodPayload.fromJson(item.cast<String, dynamic>()),
          );
        } catch (_) {
          // Skip malformed entries rather than fail the whole search.
        }
      }
    }
    return NutritionGatewaySearchPayload(results: results);
  }
}

/// JSON shape for a single food. Required fields: `source`, `external_id`,
/// `name`. Optional fields: `brand`, `barcode`, `source_url`,
/// `variants` (list), `servings` (list).
class NutritionGatewayFoodPayload {
  final String source;
  final String externalId;
  final String name;
  final String? brand;
  final String? barcode;
  final String? sourceUrl;
  final List<FoodVariant> variants;
  final Map<String, List<FoodServing>> servings;

  const NutritionGatewayFoodPayload({
    required this.source,
    required this.externalId,
    required this.name,
    this.brand,
    this.barcode,
    this.sourceUrl,
    this.variants = const [],
    this.servings = const {},
  });

  factory NutritionGatewayFoodPayload.fromJson(Map<String, dynamic> json) {
    final source = (json['source'] as String?)?.trim();
    final externalId = (json['external_id'] as String?)?.trim();
    final name = (json['name'] as String?)?.trim();
    if (source == null || source.isEmpty) {
      throw const FormatException('missing source');
    }
    if (externalId == null || externalId.isEmpty) {
      throw const FormatException('missing external_id');
    }
    if (name == null || name.isEmpty) {
      throw const FormatException('missing name');
    }
    final variantsRaw = json['variants'];
    final variants = <FoodVariant>[];
    if (variantsRaw is List) {
      for (final item in variantsRaw) {
        if (item is Map) {
          try {
            variants.add(_parseVariant(item.cast<String, dynamic>()));
          } catch (_) {}
        }
      }
    }
    if (variants.isEmpty) {
      variants.add(
        FoodVariant(
          id: 'remote_default',
          foodId: 'pending',
          referenceAmount: 100,
          referenceUnit: 'g',
          values: _parseValues(json['nutrition'] as Map<String, dynamic>?),
          isEstimated: (json['is_estimated'] as bool?) ?? false,
        ),
      );
    }
    final servings = <String, List<FoodServing>>{};
    final servingsRaw = json['servings'];
    if (servingsRaw is List) {
      for (final item in servingsRaw) {
        if (item is Map) {
          try {
            final serving = _parseServing(item.cast<String, dynamic>());
            servings.putIfAbsent(variants.first.id, () => []).add(serving);
          } catch (_) {}
        }
      }
    }
    return NutritionGatewayFoodPayload(
      source: source,
      externalId: externalId,
      name: name,
      brand: json['brand'] as String?,
      barcode: json['barcode'] as String?,
      sourceUrl: json['source_url'] as String?,
      variants: variants,
      servings: servings,
    );
  }

  /// Converts the parsed payload into a domain [FoodSearchResult],
  /// assigning fresh/scoped local ids and the normalized search name.
  FoodSearchResult toSearchResult() {
    final foodId = const Uuid().v4();
    final food = Food(
      id: foodId,
      source: source,
      externalId: externalId,
      name: name,
      searchName: Food.normalizeForSearch(name),
      brand: brand,
      barcode: barcode,
      sourceUrl: sourceUrl,
      fetchedAt: DateTime.now(),
    );
    final remotePrimary = variants.isEmpty ? null : variants.first;
    final primary = remotePrimary?.copyWith(
      id: _scopedId('variant', remotePrimary.id),
      foodId: foodId,
    );
    final primaryServings = remotePrimary == null || primary == null
        ? const <FoodServing>[]
        : (servings[remotePrimary.id] ?? const <FoodServing>[])
              .asMap()
              .entries
              .map(
                (entry) => entry.value.copyWith(
                  id: _scopedId('serving_${entry.key}', entry.value.id),
                  foodVariantId: primary.id,
                ),
              )
              .toList();
    return FoodSearchResult(
      food: food,
      primaryVariant: primary,
      servings: primaryServings,
      isRemote: true,
    );
  }

  String _scopedId(String kind, String remoteId) =>
      '$source::$externalId::$kind::$remoteId';

  static FoodVariant _parseVariant(Map<String, dynamic> map) {
    final referenceAmount =
        (map['reference_amount'] as num?)?.toDouble() ??
        (map['amount'] as num?)?.toDouble() ??
        100.0;
    final referenceUnit =
        (map['reference_unit'] as String?) ?? (map['unit'] as String?) ?? 'g';
    final values = _parseValues(map['nutrition'] as Map<String, dynamic>?);
    return FoodVariant(
      id: (map['id'] as String?) ?? 'remote',
      foodId: 'pending',
      label: map['label'] as String?,
      referenceAmount: referenceAmount,
      referenceUnit: referenceUnit,
      values: values,
      isEstimated: (map['is_estimated'] as bool?) ?? false,
      extraNutrients: map['extra'] is Map<String, dynamic>
          ? map['extra'] as Map<String, dynamic>
          : null,
    );
  }

  static FoodServing _parseServing(Map<String, dynamic> map) {
    return FoodServing(
      id: (map['id'] as String?) ?? 'remote_serving',
      foodVariantId: 'pending',
      label: (map['label'] as String?) ?? '',
      quantity: (map['quantity'] as num?)?.toDouble() ?? 1.0,
      unit: (map['unit'] as String?) ?? '',
      gramsEquivalent: (map['grams_equivalent'] as num?)?.toDouble(),
      mlEquivalent: (map['ml_equivalent'] as num?)?.toDouble(),
    );
  }

  static NutritionValues _parseValues(Map<String, dynamic>? map) {
    if (map == null) return NutritionValues.empty;
    return NutritionValues(
      calories: (map['calories'] as num?)?.toDouble(),
      proteinG: (map['protein_g'] as num?)?.toDouble(),
      carbsG: (map['carbs_g'] as num?)?.toDouble(),
      fatG: (map['fat_g'] as num?)?.toDouble(),
      fiberG: (map['fiber_g'] as num?)?.toDouble(),
      sugarsG: (map['sugars_g'] as num?)?.toDouble(),
      sodiumMg: (map['sodium_mg'] as num?)?.toDouble(),
      potassiumMg: (map['potassium_mg'] as num?)?.toDouble(),
      calciumMg: (map['calcium_mg'] as num?)?.toDouble(),
      ironMg: (map['iron_mg'] as num?)?.toDouble(),
      magnesiumMg: (map['magnesium_mg'] as num?)?.toDouble(),
      zincMg: (map['zinc_mg'] as num?)?.toDouble(),
      vitaminAUg: (map['vitamin_a_ug'] as num?)?.toDouble(),
      vitaminCMg: (map['vitamin_c_mg'] as num?)?.toDouble(),
      vitaminDUg: (map['vitamin_d_ug'] as num?)?.toDouble(),
      vitaminB12Ug: (map['vitamin_b12_ug'] as num?)?.toDouble(),
    );
  }
}
