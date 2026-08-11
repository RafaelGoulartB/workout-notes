import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:workout_notes/models/nutrition/food.dart';
import 'package:workout_notes/services/open_food_facts_gateway.dart';

void main() {
  group('OpenFoodFactsGateway URL composition', () {
    test('search URL uses search.pl with language and country', () async {
      final captured = <Uri>[];
      final client = MockClient((request) async {
        captured.add(request.url);
        return http.Response(
          jsonEncode({'count': 0, 'products': []}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final gateway = OpenFoodFactsGateway(
        client: client,
        baseUrl: 'https://world.openfoodfacts.org',
      );
      await gateway.search('arroz integral');
      final url = captured.first;
      expect(url.path, '/cgi/search.pl');
      expect(url.queryParameters['search_terms'], 'arroz integral');
      expect(url.queryParameters['json'], '1');
      expect(url.queryParameters['lc'], 'pt');
      expect(url.queryParameters['cc'], 'br');
      expect(url.queryParameters['fields'], isNotEmpty);
    });

    test('getFood URL embeds the barcode in the product endpoint', () async {
      final captured = <Uri>[];
      final client = MockClient((request) async {
        captured.add(request.url);
        return http.Response(
          jsonEncode({'status': 0, 'product': {}}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final gateway = OpenFoodFactsGateway(
        client: client,
        baseUrl: 'https://world.openfoodfacts.org',
      );
      await gateway.getFood(FoodSource.openFoodFacts, '7891234567890');
      expect(captured.first.path, '/api/v2/product/7891234567890.json');
    });
  });

  group('OpenFoodFactsGateway parsing', () {
    test('maps a product to food, variant and values per 100 g', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'count': 1,
            'products': [
              {
                'code': '7891234567890',
                'product_name_pt_br': 'Arroz integral',
                'product_name_en': 'Brown rice',
                'brands': 'Tio João',
                'url': 'https://world.openfoodfacts.org/product/7891234567890',
                'nutriments': {
                  'energy-kcal_100g': 350,
                  'proteins_100g': 7.2,
                  'carbohydrates_100g': 77,
                  'fat_100g': 2.4,
                  'fiber_100g': 4,
                  'sugars_100g': 0.5,
                  'sodium_100g': 0.3,
                  'potassium_100g': 0.42,
                  'calcium_100g': 0.12,
                  'iron_100g': 0.0025,
                  'vitamin-a_100g': 0.00009,
                  'vitamin-c_100g': 0.018,
                  'vitamin-d_100g': 0.0000025,
                  'vitamin-b12_100g': 0.0000006,
                },
                'serving_quantity_g': 50,
                'serving_size': '1/2 xícara (50 g)',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final gateway = OpenFoodFactsGateway(
        client: client,
        baseUrl: 'https://world.openfoodfacts.org',
      );
      final result = await gateway.search('arroz');
      expect(result.ok, isTrue);
      expect(result.data, hasLength(1));
      final row = result.data!.first;
      expect(row.food.name, 'Arroz integral');
      expect(row.food.source, FoodSource.openFoodFacts);
      expect(row.food.externalId, '7891234567890');
      expect(row.food.barcode, '7891234567890');
      expect(row.food.brand, 'Tio João');
      expect(row.food.sourceUrl, contains('7891234567890'));
      final variant = row.primaryVariant!;
      expect(variant.referenceAmount, 100);
      expect(variant.referenceUnit, 'g');
      expect(variant.values.calories, 350);
      expect(variant.values.proteinG, 7.2);
      expect(variant.values.carbsG, 77);
      expect(variant.values.fatG, 2.4);
      expect(variant.values.fiberG, 4);
      expect(variant.values.sugarsG, 0.5);
      // OFF reports sodium per 100 g in grams; the model stores mg.
      expect(variant.values.sodiumMg, 300);
      expect(variant.values.potassiumMg, 420);
      expect(variant.values.calciumMg, 120);
      expect(variant.values.ironMg, 2.5);
      expect(variant.values.vitaminAUg, closeTo(90, 0.001));
      expect(variant.values.vitaminCMg, 18);
      expect(variant.values.vitaminDUg, closeTo(2.5, 0.001));
      expect(variant.values.vitaminB12Ug, closeTo(0.6, 0.001));
      expect(variant.isEstimated, isFalse);
      expect(row.servings, hasLength(1));
      expect(row.servings.first.gramsEquivalent, 50);
      expect(row.servings.first.label, '1/2 xícara (50 g)');
    });

    test('scopes variant and serving ids to the product code', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'count': 2,
            'products': [
              {
                'code': '111',
                'product_name': 'Produto A',
                'nutriments': {'energy-kcal_100g': 100},
                'serving_quantity_g': 30,
              },
              {
                'code': '222',
                'product_name': 'Produto B',
                'nutriments': {'energy-kcal_100g': 200},
                'serving_quantity_g': 40,
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final gateway = OpenFoodFactsGateway(
        client: client,
        baseUrl: 'https://world.openfoodfacts.org',
      );
      final result = await gateway.search('x');
      final rows = result.data!;
      expect(rows, hasLength(2));
      // Shared constants would collide on the global PK and silently
      // drop every product but the first during the cache upsert.
      expect(
        rows.first.primaryVariant!.id,
        'open_food_facts::111::variant::off_111_100g',
      );
      expect(
        rows.last.primaryVariant!.id,
        'open_food_facts::222::variant::off_222_100g',
      );
      expect(
        rows.first.servings.first.id,
        'open_food_facts::111::serving_0::off_111_serving',
      );
      expect(
        rows.last.servings.first.id,
        'open_food_facts::222::serving_0::off_222_serving',
      );
    });

    test('falls back to English name when pt-BR is missing', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'count': 1,
            'products': [
              {
                'code': '123',
                'product_name_en': 'Greek yogurt',
                'nutriments': {'energy-kcal_100g': 60},
              },
            ],
          }),
          200,
        );
      });
      final gateway = OpenFoodFactsGateway(
        client: client,
        baseUrl: 'https://world.openfoodfacts.org',
      );
      final result = await gateway.search('yogurt');
      expect(result.data!.first.food.name, 'Greek yogurt');
    });

    test('converts energy in kJ to kcal when kcal is missing', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'count': 1,
            'products': [
              {
                'code': '456',
                'product_name': 'Suco',
                'nutriments': {'energy_100g': 209.2},
              },
            ],
          }),
          200,
        );
      });
      final gateway = OpenFoodFactsGateway(
        client: client,
        baseUrl: 'https://world.openfoodfacts.org',
      );
      final result = await gateway.search('suco');
      expect(
        result.data!.first.primaryVariant!.values.calories,
        closeTo(50, 0.01),
      );
    });

    test('skips products without code or name', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'count': 3,
            'products': [
              {'code': '1', 'product_name': 'Válido'},
              {'code': '2'},
              {'product_name': 'Sem código'},
            ],
          }),
          200,
        );
      });
      final gateway = OpenFoodFactsGateway(
        client: client,
        baseUrl: 'https://world.openfoodfacts.org',
      );
      final result = await gateway.search('x');
      expect(result.data, hasLength(1));
      expect(result.data!.first.food.name, 'Válido');
    });

    test('getFood returns not_found when status is 0', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({'status': 0, 'status_verbose': 'product not found'}),
          200,
        );
      });
      final gateway = OpenFoodFactsGateway(
        client: client,
        baseUrl: 'https://world.openfoodfacts.org',
      );
      final result = await gateway.getFood(
        FoodSource.openFoodFacts,
        '9999999999999',
      );
      expect(result.ok, isFalse);
      expect(result.error?.code, 'not_found');
    });

    test('getFood parses a valid product', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'status': 1,
            'product': {
              'code': '7891234567890',
              'product_name': 'Leite integral',
              'nutriments': {'proteins_100g': 3.2},
            },
          }),
          200,
        );
      });
      final gateway = OpenFoodFactsGateway(
        client: client,
        baseUrl: 'https://world.openfoodfacts.org',
      );
      final result = await gateway.getFood(
        FoodSource.openFoodFacts,
        '7891234567890',
      );
      expect(result.ok, isTrue);
      expect(result.data!.food.name, 'Leite integral');
      expect(result.data!.primaryVariant!.values.proteinG, 3.2);
    });
  });

  group('OpenFoodFactsGateway error mapping', () {
    test('maps 429 to rate_limited', () async {
      final client = MockClient((request) async => http.Response('busy', 429));
      final gateway = OpenFoodFactsGateway(
        client: client,
        baseUrl: 'https://world.openfoodfacts.org',
      );
      final result = await gateway.search('rice');
      expect(result.error?.code, 'rate_limited');
    });

    test('maps 503 to rate_limited', () async {
      final client = MockClient((request) async => http.Response('down', 503));
      final gateway = OpenFoodFactsGateway(
        client: client,
        baseUrl: 'https://world.openfoodfacts.org',
      );
      final result = await gateway.search('rice');
      expect(result.error?.code, 'rate_limited');
    });

    test('maps network failures to network', () async {
      final client = MockClient((request) async {
        throw http.ClientException('connection refused', request.url);
      });
      final gateway = OpenFoodFactsGateway(
        client: client,
        baseUrl: 'https://world.openfoodfacts.org',
      );
      final result = await gateway.search('rice');
      expect(result.error?.code, 'network');
    });

    test('maps malformed JSON to malformed_response', () async {
      final client = MockClient(
        (request) async => http.Response('not json', 200),
      );
      final gateway = OpenFoodFactsGateway(
        client: client,
        baseUrl: 'https://world.openfoodfacts.org',
      );
      final result = await gateway.search('rice');
      expect(result.error?.code, 'malformed_response');
    });
  });
}
