import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:workout_notes/models/nutrition/food.dart';
import 'package:workout_notes/models/nutrition/food_search_result.dart';
import 'package:workout_notes/models/nutrition/food_serving.dart';
import 'package:workout_notes/models/nutrition/food_variant.dart';
import 'package:workout_notes/models/nutrition/nutrition_values.dart';

import 'nutrition_gateway.dart';

/// Gateway for the Open Food Facts collaborative database.
///
/// Talks to the global server `world.openfoodfacts.org` (which includes
/// products sold in Brazil), without any authentication. Anonymous
/// usage is subject to rate limits, so the gateway surfaces 429/503 as
/// a dedicated `rate_limited` error and relies on the app's local
/// cache for repeated lookups.
///
/// Endpoints used:
///
///   GET /cgi/search.pl?search_terms=…&json=1        (name search)
///   GET /api/v2/product/{code}.json                 (barcode lookup)
class OpenFoodFactsGateway implements NutritionGateway {
  static const String defaultBaseUrl = 'https://world.openfoodfacts.org';
  static const String sourceName = FoodSource.openFoodFacts;

  /// Fields requested from OFF so the payload stays small.
  static const String _fields =
      'code,product_name_pt_br,product_name_en,product_name,brands,'
      'nutriments,url,image_front_small_url,serving_quantity_g,serving_size';

  final http.Client _client;
  final Duration timeout;
  final String _baseUrl;
  final String language;
  final String country;
  final String userAgent;

  OpenFoodFactsGateway({
    http.Client? client,
    this.timeout = const Duration(seconds: 8),
    String? baseUrl,
    this.language = 'pt',
    this.country = 'br',
    this.userAgent = 'workout-notes/1.0',
  }) : _client = client ?? http.Client(),
       _baseUrl = (baseUrl ?? defaultBaseUrl).trim();

  @override
  String? get baseUrl => _baseUrl;

  @override
  Future<NutritionGatewayResult<List<FoodSearchResult>>> search(
    String query, {
    int limit = 20,
  }) async {
    final uri = Uri.parse('$_baseUrl/cgi/search.pl').replace(
      queryParameters: <String, String>{
        'search_terms': query,
        'search_simple': '1',
        'action': 'process',
        'json': '1',
        'page_size': limit.toString(),
        'fields': _fields,
        'lc': language,
        'cc': country,
      },
    );
    try {
      final decoded = await _getJson(uri);
      final results = <FoodSearchResult>[];
      final products = decoded['products'];
      if (products is List) {
        for (final item in products) {
          if (item is! Map) continue;
          try {
            final payload = _toPayload(item.cast<String, dynamic>());
            if (payload != null) {
              results.add(payload.toSearchResult());
            }
          } catch (_) {
            // Skip malformed entries rather than fail the whole search.
          }
        }
      }
      return NutritionGatewayResult.ok(results);
    } on NutritionGatewayError catch (e) {
      return NutritionGatewayResult.error(e);
    }
  }

  @override
  Future<NutritionGatewayResult<FoodSearchResult>> getFood(
    String source,
    String externalId,
  ) async {
    final code = externalId.trim();
    final uri = Uri.parse(
      '$_baseUrl/api/v2/product/${Uri.encodeComponent(code)}.json',
    ).replace(queryParameters: <String, String>{'fields': _fields});
    try {
      final decoded = await _getJson(uri);
      final status = decoded['status'];
      if (status is num && status == 0) {
        return NutritionGatewayResult.error(
          const NutritionGatewayError('not_found', 'Product not found'),
        );
      }
      final product = decoded['product'];
      if (product is! Map) {
        return NutritionGatewayResult.error(
          const NutritionGatewayError(
            'malformed_response',
            'Missing product in response',
          ),
        );
      }
      final payload = _toPayload(product.cast<String, dynamic>());
      if (payload == null) {
        return NutritionGatewayResult.error(
          const NutritionGatewayError(
            'malformed_response',
            'Invalid product in response',
          ),
        );
      }
      return NutritionGatewayResult.ok(payload.toSearchResult());
    } on NutritionGatewayError catch (e) {
      return NutritionGatewayResult.error(e);
    }
  }

  /// Fetches and decodes a JSON GET, mapping HTTP/network errors to
  /// [NutritionGatewayError] codes.
  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    try {
      final response = await _client
          .get(uri, headers: _headers())
          .timeout(timeout);
      if (response.statusCode == 404) {
        throw const NutritionGatewayError('not_found', 'Endpoint not found');
      }
      if (response.statusCode == 429 || response.statusCode == 503) {
        throw NutritionGatewayError(
          'rate_limited',
          'Open Food Facts is busy (${response.statusCode})',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw NutritionGatewayError(
          'http_error',
          'Status ${response.statusCode}',
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const NutritionGatewayError(
          'malformed_response',
          'Body is not an object',
        );
      }
      return decoded.cast<String, dynamic>();
    } on TimeoutException {
      throw const NutritionGatewayError('timeout', 'Gateway request timed out');
    } on http.ClientException catch (e) {
      throw NutritionGatewayError('network', e.message);
    } on FormatException catch (e) {
      throw NutritionGatewayError('malformed_response', e.message);
    } on NutritionGatewayError {
      rethrow;
    } catch (e) {
      throw NutritionGatewayError('unknown', e.toString());
    }
  }

  /// Maps a single OFF product object into the generic payload shape.
  /// Returns null when the record cannot be used (no code/name).
  NutritionGatewayFoodPayload? _toPayload(Map<String, dynamic> product) {
    final code = _nullableString(product['code']);
    final name = _firstNonEmpty([
      product['product_name_pt_br'],
      product['product_name_en'],
      product['product_name'],
    ]);
    if (code == null || name == null) return null;

    final nutriments = product['nutriments'];
    final nutrition = _parseNutriments(
      nutriments is Map ? nutriments.cast<String, dynamic>() : null,
    );

    // IDs are scoped to the product code: these are global primary
    // keys in the local cache, so a shared constant like `off_100g`
    // would collide between every product and silently drop all but
    // the first result. Deterministic per-code IDs also keep the
    // cache upsert idempotent.
    final variant = FoodVariant(
      id: 'off_${code}_100g',
      foodId: 'pending',
      label: '100 g',
      referenceAmount: 100,
      referenceUnit: 'g',
      values: nutrition,
      isEstimated: false,
      extraNutrients: nutriments is Map
          ? nutriments.cast<String, dynamic>()
          : null,
    );

    final servings = <String, List<FoodServing>>{};
    final servingGrams = _nonNegativeDouble(product['serving_quantity_g']);
    if (servingGrams != null && servingGrams > 0) {
      final label = _nullableString(product['serving_size']);
      servings[variant.id] = [
        FoodServing(
          id: 'off_${code}_serving',
          foodVariantId: variant.id,
          label: label ?? '1 serving',
          quantity: 1,
          unit: 'serving',
          gramsEquivalent: servingGrams,
        ),
      ];
    }

    return NutritionGatewayFoodPayload(
      source: FoodSource.openFoodFacts,
      externalId: code,
      name: name,
      brand: _nullableString(product['brands']),
      barcode: code,
      sourceUrl: _nullableString(product['url']),
      variants: [variant],
      servings: servings,
    );
  }

  NutritionValues _parseNutriments(Map<String, dynamic>? nutriments) {
    if (nutriments == null) return NutritionValues.empty;
    var calories = _nonNegativeDouble(nutriments['energy-kcal_100g']);
    if (calories == null) {
      final energyKj = _nonNegativeDouble(nutriments['energy_100g']);
      if (energyKj != null) calories = energyKj / 4.184;
    }
    return NutritionValues(
      calories: calories,
      proteinG: _nonNegativeDouble(nutriments['proteins_100g']),
      carbsG: _nonNegativeDouble(nutriments['carbohydrates_100g']),
      fatG: _nonNegativeDouble(nutriments['fat_100g']),
      saturatedFatG: _nonNegativeDouble(nutriments['saturated-fat_100g']),
      monounsaturatedFatG: _nonNegativeDouble(
        nutriments['monounsaturated-fat_100g'],
      ),
      polyunsaturatedFatG: _nonNegativeDouble(
        nutriments['polyunsaturated-fat_100g'],
      ),
      transFatG: _nonNegativeDouble(nutriments['trans-fat_100g']),
      fiberG: _nonNegativeDouble(nutriments['fiber_100g']),
      sugarsG: _nonNegativeDouble(nutriments['sugars_100g']),
      // Open Food Facts reports sodium (like every other nutrient)
      // per 100 g in *grams*; the app model uses milligrams.
      sodiumMg: _toMilligrams(nutriments['sodium_100g']),
      potassiumMg: _toMilligrams(nutriments['potassium_100g']),
      calciumMg: _toMilligrams(nutriments['calcium_100g']),
      ironMg: _toMilligrams(nutriments['iron_100g']),
      magnesiumMg: _toMilligrams(nutriments['magnesium_100g']),
      zincMg: _toMilligrams(nutriments['zinc_100g']),
      vitaminAUg: _toMicrograms(nutriments['vitamin-a_100g']),
      vitaminCMg: _toMilligrams(nutriments['vitamin-c_100g']),
      vitaminDUg: _toMicrograms(nutriments['vitamin-d_100g']),
      vitaminB12Ug: _toMicrograms(nutriments['vitamin-b12_100g']),
    );
  }

  static double? _toMilligrams(dynamic grams) {
    final value = _nonNegativeDouble(grams);
    if (value == null) return null;
    return value * 1000;
  }

  static double? _toMicrograms(dynamic grams) {
    final value = _nonNegativeDouble(grams);
    if (value == null) return null;
    return value * 1000000;
  }

  Map<String, String> _headers() => {
    'Accept': 'application/json',
    'User-Agent': userAgent,
  };

  static String? _firstNonEmpty(List<Object?> values) {
    for (final value in values) {
      final trimmed = _nullableString(value);
      if (trimmed != null) return trimmed;
    }
    return null;
  }

  static String? _nullableString(dynamic value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static double? _nonNegativeDouble(dynamic value) {
    if (value == null) return null;
    double? parsed;
    if (value is num) {
      parsed = value.toDouble();
    } else if (value is String) {
      parsed = double.tryParse(value.trim());
    }
    if (parsed == null || parsed.isNaN || parsed.isInfinite || parsed < 0) {
      return null;
    }
    return parsed;
  }
}
