import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:workout_notes/services/ai_service.dart';
import 'package:workout_notes/services/open_food_facts_gateway.dart';

class _TrackedClient extends MockClient {
  bool closed = false;

  _TrackedClient() : super((request) async => http.Response('{}', 200));

  @override
  void close() {
    closed = true;
    super.close();
  }
}

void main() {
  test('AiService never closes an injected client', () {
    final client = _TrackedClient();
    AiService(client: client).close();
    expect(client.closed, isFalse);
  });

  test('OpenFoodFactsGateway never closes an injected client', () {
    final client = _TrackedClient();
    OpenFoodFactsGateway(client: client).close();
    expect(client.closed, isFalse);
  });

  test('a client the instance created itself can be closed repeatedly', () {
    final service = AiService();
    service.close();
    service.close();
    final gateway = OpenFoodFactsGateway();
    gateway.close();
    gateway.close();
  });

  test('the shared instances are single long-lived objects', () {
    expect(identical(AiService.shared, AiService.shared), isTrue);
    expect(
      identical(OpenFoodFactsGateway.instance, OpenFoodFactsGateway.instance),
      isTrue,
    );
  });
}
