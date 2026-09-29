import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/nutrition/food_search_result.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/screens/workout/food_search_controller.dart';
import 'package:workout_notes/services/nutrition_gateway.dart';

class _NoGateway implements NutritionGateway {
  @override
  Future<NutritionGatewayResult<List<FoodSearchResult>>> search(
    String query, {
    int limit = 20,
  }) => throw UnimplementedError();

  @override
  Future<NutritionGatewayResult<FoodSearchResult>> getFood(
    String source,
    String externalId,
  ) => throw UnimplementedError();

  @override
  String? get baseUrl => null;
}

void main() {
  group('extractProductCode', () {
    test('keeps only the digits of a plain barcode', () {
      expect(
        FoodSearchController.extractProductCode(' 789-1234 5678 '),
        '78912345678',
      );
    });

    test('reads the id from an Open Food Facts product url', () {
      expect(
        FoodSearchController.extractProductCode(
          'https://world.openfoodfacts.org/product/3017620422003/nutella',
        ),
        '3017620422003',
      );
    });

    test('rejects scans without digits', () {
      expect(FoodSearchController.extractProductCode('hello'), isNull);
    });
  });

  group('query handling', () {
    late FoodSearchController controller;

    setUp(() {
      controller = FoodSearchController(
        gateway: _NoGateway(),
        repository: NutritionRepository(),
        date: '2026-03-11',
      );
    });

    tearDown(() => controller.dispose());

    test('a one character query only shows the too-short hint', () {
      controller.onQueryChanged('a');
      expect(controller.showQueryTooShort, isTrue);
      expect(controller.localResults, isEmpty);
      expect(controller.isSearchingRemote, isFalse);
    });

    test('an empty query clears the hint and resets to all foods', () {
      controller.setFilter(FoodSearchFilter.favorites);
      controller.onQueryChanged('a');
      controller.onQueryChanged('');
      expect(controller.showQueryTooShort, isFalse);
      expect(controller.query, isEmpty);
      // Typing switches back to the "all" filter; clearing keeps it.
      expect(controller.activeFilter, FoodSearchFilter.all);
    });

    test(
      'a remote search under two characters never hits the gateway',
      () async {
        await controller.searchRemote(' a ');
        expect(controller.showQueryTooShort, isTrue);
        expect(controller.isSearchingRemote, isFalse);
      },
    );

    test('empty state shows saved meals only under the meals filter', () {
      expect(controller.emptyQuerySections.showSavedMeals, isFalse);
      controller.setFilter(FoodSearchFilter.meals);
      expect(controller.emptyQuerySections.showSavedMeals, isTrue);
      expect(controller.emptyQuerySections.hasSuggestions, isFalse);
    });
  });
}
