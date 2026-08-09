import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:workout_notes/models/nutrition/food_search_result.dart';

import 'nutrition_gateway.dart';

/// HTTP-based gateway that talks to a Nutrition Gateway service.
///
/// Configure the base URL through `--dart-define`:
///
///   flutter run --dart-define=NUTRITION_GATEWAY_BASE_URL=https://...
///
/// When the variable is empty or missing, every call short-circuits to
/// a [NutritionGatewayError] with code `not_configured` so the UI can
/// fall back to local cache + manual entry without crashing.
class HttpNutritionGateway implements NutritionGateway {
  static const String baseUrlEnvironmentKey = 'NUTRITION_GATEWAY_BASE_URL';

  final http.Client _client;
  final Duration timeout;
  final String? _baseUrl;

  HttpNutritionGateway({
    http.Client? client,
    this.timeout = const Duration(seconds: 6),
    String? baseUrl,
  }) : _client = client ?? http.Client(),
       _baseUrl =
           (baseUrl ??
                   const String.fromEnvironment(
                     HttpNutritionGateway.baseUrlEnvironmentKey,
                   ))
               .trim();

  @override
  String? get baseUrl =>
      (_baseUrl == null || _baseUrl.isEmpty) ? null : _baseUrl;

  @override
  Future<NutritionGatewayResult<List<FoodSearchResult>>> search(
    String query, {
    int limit = 20,
  }) async {
    if (!isConfigured) {
      return NutritionGatewayResult.error(
        const NutritionGatewayError('not_configured', 'Gateway URL is empty'),
      );
    }
    final url = _buildSearchUrl(query, limit);
    try {
      final response = await _client
          .get(url, headers: _headers())
          .timeout(timeout);
      if (response.statusCode == 404) {
        return NutritionGatewayResult.error(
          const NutritionGatewayError('not_found', 'Endpoint not found'),
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return NutritionGatewayResult.error(
          NutritionGatewayError('http_error', 'Status ${response.statusCode}'),
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return NutritionGatewayResult.error(
          const NutritionGatewayError(
            'malformed_response',
            'Body is not an object',
          ),
        );
      }
      final payload = NutritionGatewaySearchPayload.fromJson(decoded);
      final results = payload.results
          .map((item) => item.toSearchResult())
          .toList();
      return NutritionGatewayResult.ok(results);
    } on TimeoutException {
      return NutritionGatewayResult.error(
        const NutritionGatewayError('timeout', 'Gateway request timed out'),
      );
    } on http.ClientException catch (e) {
      return NutritionGatewayResult.error(
        NutritionGatewayError('network', e.message),
      );
    } on FormatException catch (e) {
      return NutritionGatewayResult.error(
        NutritionGatewayError('malformed_response', e.message),
      );
    } catch (e) {
      return NutritionGatewayResult.error(
        NutritionGatewayError('unknown', e.toString()),
      );
    }
  }

  @override
  Future<NutritionGatewayResult<FoodSearchResult>> getFood(
    String source,
    String externalId,
  ) async {
    if (!isConfigured) {
      return NutritionGatewayResult.error(
        const NutritionGatewayError('not_configured', 'Gateway URL is empty'),
      );
    }
    final url = _buildFoodUrl(source, externalId);
    try {
      final response = await _client
          .get(url, headers: _headers())
          .timeout(timeout);
      if (response.statusCode == 404) {
        return NutritionGatewayResult.error(
          const NutritionGatewayError('not_found', 'Food not found'),
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return NutritionGatewayResult.error(
          NutritionGatewayError('http_error', 'Status ${response.statusCode}'),
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return NutritionGatewayResult.error(
          const NutritionGatewayError(
            'malformed_response',
            'Body is not an object',
          ),
        );
      }
      final payload = NutritionGatewayFoodPayload.fromJson(decoded);
      return NutritionGatewayResult.ok(payload.toSearchResult());
    } on TimeoutException {
      return NutritionGatewayResult.error(
        const NutritionGatewayError('timeout', 'Gateway request timed out'),
      );
    } on http.ClientException catch (e) {
      return NutritionGatewayResult.error(
        NutritionGatewayError('network', e.message),
      );
    } on FormatException catch (e) {
      return NutritionGatewayResult.error(
        NutritionGatewayError('malformed_response', e.message),
      );
    } catch (e) {
      return NutritionGatewayResult.error(
        NutritionGatewayError('unknown', e.toString()),
      );
    }
  }

  /// Convenience helper that returns the [FoodSearchResult] for a food
  /// (with its primary variant + servings when available).
  Future<NutritionGatewayResult<FoodSearchResult>> fetchFoodDetail(
    String source,
    String externalId,
  ) async {
    final result = await getFood(source, externalId);
    if (result.error != null) {
      return NutritionGatewayResult.error(result.error!);
    }
    return NutritionGatewayResult.ok(result.data!);
  }

  bool get isConfigured => baseUrl != null;

  // ===================================================================
  // Internals
  // ===================================================================

  Uri _buildSearchUrl(String query, int limit) {
    final base = Uri.parse(baseUrl!);
    return base.replace(
      path: '${_ensureTrailingSlash(base.path)}foods/search',
      queryParameters: <String, String>{'q': query, 'limit': limit.toString()},
    );
  }

  Uri _buildFoodUrl(String source, String externalId) {
    final base = Uri.parse(baseUrl!);
    return base.replace(
      path:
          '${_ensureTrailingSlash(base.path)}foods/${Uri.encodeComponent(source)}/${Uri.encodeComponent(externalId)}',
    );
  }

  static String _ensureTrailingSlash(String path) {
    if (path.isEmpty) return '/';
    return path.endsWith('/') ? path : '$path/';
  }

  static Map<String, String> _headers() => {
    'Accept': 'application/json',
    'User-Agent': 'workout-notes/1.0',
  };
}
