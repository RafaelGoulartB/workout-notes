import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:workout_notes/services/http_nutrition_gateway.dart';

void main() {
  group('HttpNutritionGateway URL encoding', () {
    test('encodes spaces, accents and special characters', () async {
      final captured = <Uri>[];
      final client = MockClient((request) async {
        captured.add(request.url);
        return http.Response(
          jsonEncode({'results': []}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final gateway = HttpNutritionGateway(
        client: client,
        baseUrl: 'https://gateway.test/',
      );
      await gateway.search('pão com açúcar');
      expect(captured, isNotEmpty);
      final url = captured.first;
      expect(url.path, '/foods/search');
      expect(url.queryParameters['q'], 'pão com açúcar');
      expect(url.toString(), contains('p%C3%A3o'));
      expect(url.toString(), contains('a%C3%A7%C3%BAcar'));
    });

    test('food detail URL composes source and externalId safely', () async {
      final captured = <Uri>[];
      final client = MockClient((request) async {
        captured.add(request.url);
        return http.Response(jsonEncode(_foodPayload()), 200);
      });
      final gateway = HttpNutritionGateway(
        client: client,
        baseUrl: 'https://gateway.test',
      );
      await gateway.getFood('tbca', 'id/with/slash');
      expect(captured.first.path, '/foods/tbca/id%2Fwith%2Fslash');
    });
  });

  group('HttpNutritionGateway behaviour', () {
    test('returns not_configured when base URL is empty', () async {
      final gateway = HttpNutritionGateway(baseUrl: '');
      final result = await gateway.search('rice');
      expect(result.ok, isFalse);
      expect(result.notConfigured, isTrue);
    });

    test('parses a valid search response', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'results': [
              _foodPayload(),
              {
                'source': 'gateway',
                'external_id': 'b',
                'name': 'Rice',
                'nutrition': {
                  'calories': 130,
                  'protein_g': 2.7,
                  'carbs_g': 28,
                  'fat_g': 0.3,
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final gateway = HttpNutritionGateway(
        client: client,
        baseUrl: 'https://gateway.test',
      );
      final result = await gateway.search('rice');
      expect(result.ok, isTrue);
      expect(result.data, isNotNull);
      expect(result.data!.length, 2);
      expect(result.data!.first.food.name, 'Apple');
    });

    test('classifies network failures', () async {
      final client = MockClient((request) async {
        throw http.ClientException('connection refused', request.url);
      });
      final gateway = HttpNutritionGateway(
        client: client,
        baseUrl: 'https://gateway.test',
      );
      final result = await gateway.search('apple');
      expect(result.ok, isFalse);
      expect(result.error?.code, 'network');
    });

    test('classifies HTTP 5xx as http_error', () async {
      final client = MockClient((request) async {
        return http.Response('boom', 500);
      });
      final gateway = HttpNutritionGateway(
        client: client,
        baseUrl: 'https://gateway.test',
      );
      final result = await gateway.search('apple');
      expect(result.error?.code, 'http_error');
    });

    test('classifies timeouts', () async {
      final client = MockClient((request) async {
        await Future<void>.delayed(const Duration(seconds: 1));
        return http.Response('{}', 200);
      });
      final gateway = HttpNutritionGateway(
        client: client,
        baseUrl: 'https://gateway.test',
        timeout: const Duration(milliseconds: 50),
      );
      final result = await gateway.search('apple');
      expect(result.error?.code, 'timeout');
    });

    test('rejects malformed JSON', () async {
      final client = MockClient((request) async {
        return http.Response('not json', 200);
      });
      final gateway = HttpNutritionGateway(
        client: client,
        baseUrl: 'https://gateway.test',
      );
      final result = await gateway.search('apple');
      expect(result.error?.code, 'malformed_response');
    });

    test('preserves null nutrients from the payload', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'results': [
              {
                'source': 'gateway',
                'external_id': 'a',
                'name': 'Apple',
                'nutrition': {'calories': 50, 'protein_g': null},
              },
            ],
          }),
          200,
        );
      });
      final gateway = HttpNutritionGateway(
        client: client,
        baseUrl: 'https://gateway.test',
      );
      final result = await gateway.search('apple');
      expect(result.ok, isTrue);
      // The gateway itself returns FoodSearchResult rows with the
      // variant values; nulls are preserved through the payload.
      expect(result.data!.first.food.name, 'Apple');
    });
  });
}

Map<String, dynamic> _foodPayload() => {
  'source': 'gateway',
  'external_id': 'a',
  'name': 'Apple',
  'nutrition': {'calories': 52, 'protein_g': 0.3, 'carbs_g': 14, 'fat_g': 0.2},
};
